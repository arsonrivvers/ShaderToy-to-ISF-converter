// Spyglass is a local-path package that exists only in the operator checkout (see
// App/spyglass-local.yml), which is also the only place the SPYGLASS compilation condition is
// defined. That keeps a clean clone compiling without the package; `DEBUG` keeps
// the whole surface out of Release regardless.
#if DEBUG && SPYGLASS
import XCTest
import ImageIO
import Metal
import QuartzCore
import SpyglassCapture
import SpyglassCore
import SpyglassHost
import SpyglassProtocol

/// ARShader's `ControlFacade` conformance — Spyglass Task 13a, Steps 3 and 5.
///
/// Written against the five conformance obligations rather than against the implementation, and
/// every assertion is one that would fail if the code were subtly wrong: the size test decodes the
/// returned PNG instead of trusting the metadata, the rejection tests assert the work was *skipped*
/// rather than done and relabelled, and the blocking test measures whether a capture finishes while
/// the main actor is genuinely unavailable.
@MainActor
final class InstrumentControlFacadeTests: XCTestCase {
    private var device: MTLDevice!
    private var queue: MTLCommandQueue!
    private var mixer: MixerState!
    private var renderer: InstrumentRenderer!
    private var facade: InstrumentControlFacade!

    override func setUpWithError() throws {
        device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        queue = try XCTUnwrap(device.makeCommandQueue())
        mixer = MixerState()
        renderer = InstrumentRenderer(device: device, queue: queue, mixer: mixer)
        // Built here, not per-test: its Metal library compile would otherwise land inside the
        // timing test and be mistaken for a blocking capture.
        facade = InstrumentControlFacade(device: device, queue: queue,
                                         renderer: renderer, mixer: mixer)
    }

    override func tearDown() {
        facade = nil
        renderer = nil
        mixer = nil
        queue = nil
        device = nil
        super.tearDown()
    }

    // MARK: - helpers

    private func fixture(_ name: String) throws -> String {
        let url = try XCTUnwrap(Bundle(for: Self.self)
            .url(forResource: name, withExtension: "fs", subdirectory: "Fixtures"))
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// `async`, and awaiting `fulfillment(of:)` rather than calling `wait(for:)` as `FrameGraphTests`
    /// does. The compile completion is delivered on the main actor, and the synchronous waiter holds
    /// the main actor without yielding — inside an `async` test that is a deadlock, not a wait, and
    /// it presents as a 30-second timeout on a compile that never had a chance to report.
    private func load(_ id: DeckID, _ fixtureName: String) async throws {
        let deck = renderer.deck(id)
        let done = expectation(description: "compile \(fixtureName) on \(id.rawValue)")
        deck.unit.onCompileFinished = { done.fulfill() }
        deck.unit.load(source: try fixture(fixtureName), name: "\(fixtureName).fs")
        await fulfillment(of: [done], timeout: 30)
        deck.unit.onCompileFinished = nil
        XCTAssertNil(deck.unit.compileError)
    }

    /// The PNG's own dimensions, read from the encoded bytes rather than from the metadata beside
    /// them — the metadata is exactly the thing under test.
    private func pngPixelSize(_ base64: String) throws -> (width: Int, height: Int) {
        let data = try XCTUnwrap(Data(base64Encoded: base64), "capture was not valid base64")
        XCTAssertEqual(Array(data.prefix(4)), [0x89, 0x50, 0x4E, 0x47], "not PNG magic bytes")
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        return (image.width, image.height)
    }

    private func failureCode(_ outcome: CaptureOutcome) -> String? {
        if case .failure(let error) = outcome { return error.code }
        return nil
    }

    // MARK: - Taps (Step 3: declare time support honestly)

    /// The instrument has no render-at-time path anywhere — `renderFrame()` draws from `clock.now`
    /// and takes no time argument — so any `.explicitTime` here would be a declaration the renderer
    /// cannot honour, and a `time` argument would be silently ignored rather than refused.
    func testEveryTapDeclaresLiveOnlyBecauseNothingHereCanRenderAtATime() async {
        let taps = await facade.taps
        XCTAssertEqual(taps.map(\.name), ["program", "deck-a", "deck-b"],
                       "The program feed plus one tap per deck, named as the operator's surface names them")
        for tap in taps {
            XCTAssertEqual(tap.timeSupport, .liveOnly, "\(tap.name) must not claim it can seek")
            XCTAssertFalse(tap.acceptsExplicitTime)
        }
    }

    /// Gate 0's whole point: the rejection happens in the protocol extension, so `performCapture`
    /// never sees the request. Asserting the call count is what separates "rejected" from
    /// "captured anyway and then relabelled".
    func testATimeArgumentIsRejectedRatherThanSilentlyIgnored() async {
        let outcome = await facade.capture(tap: "program", width: 64, height: 64, time: 1.0)
        XCTAssertEqual(failureCode(outcome), "time_unsupported")
        XCTAssertEqual(facade.performCaptureCallCountForTesting, 0,
                       "A rejected request must not have reached the renderer at all")
    }

    func testAnUnknownTapIsRejectedBeforeAnyRendererWork() async {
        let outcome = await facade.capture(tap: "master-raw", width: 64, height: 64, time: nil)
        XCTAssertEqual(failureCode(outcome), "unknown_tap")
        XCTAssertEqual(facade.performCaptureCallCountForTesting, 0)
    }

    /// `master-raw` is not a typo in the test above: `rawMasterTexture()` bypasses the blackout gate
    /// and is deliberately not exposed, so an agent asking for it must be told no tap exists.
    func testTheRawMasterIsNotAnAgentVisibleTap() async {
        let names = await facade.taps.map(\.name)
        XCTAssertFalse(names.contains { $0.contains("raw") },
                       "Blackout is the operator's panic button; nothing may look behind it")
    }

    func testAnIllegalCaptureSizeIsRejectedBeforeAnyRendererWork() async {
        let outcome = await facade.capture(tap: "program", width: 0, height: 64, time: nil)
        XCTAssertEqual(failureCode(outcome), "bad_size")
        XCTAssertEqual(facade.performCaptureCallCountForTesting, 0)
    }

    // MARK: - Render health (obligation 3)

    /// A renderer that has never composited has no honest last-frame time. Returning
    /// `0 frames / 0 seconds` would read as permanently healthy and silently defeat stall detection
    /// — which is precisely the failure this whole path exists to make visible.
    func testHealthIsReportedUnavailableBeforeTheFirstFrameRatherThanFabricated() async {
        let result = await facade.renderHealth()
        guard case .failure(let error) = result else {
            return XCTFail("A renderer with no frames must not report a measurement")
        }
        XCTAssertEqual(error.code, "health_unavailable")
    }

    func testHealthReportsRealSignalsOnceFramesLand() async throws {
        try await load(.one, "solid_red")
        renderer.renderFrame()

        guard case .success(let health) = await facade.renderHealth() else {
            return XCTFail("A renderer that has drawn must report its liveness")
        }
        XCTAssertGreaterThan(health.frameCounter, 0)
        XCTAssertTrue(health.secondsSinceLastFrame.isFinite)
        XCTAssertGreaterThanOrEqual(health.secondsSinceLastFrame, 0,
                                    "Elapsed is measured against the renderer's own clock base")
        XCTAssertFalse(health.isStalled(), "A frame just landed")
    }

    /// The failure propagates rather than being swallowed into a picture: with no honest health
    /// reading there is no basis on which to call a capture current.
    func testACaptureBeforeAnyFrameFailsWithHealthUnavailableAndNoImage() async {
        let outcome = await facade.capture(tap: "program", width: 64, height: 64, time: nil)
        XCTAssertEqual(failureCode(outcome), "health_unavailable")
        XCTAssertNil(outcome.health, "A failed request measured nothing and must not appear to have")
        XCTAssertEqual(facade.performCaptureCallCountForTesting, 1,
                       "The request was valid — it failed on measurement, not on validation")
    }

    /// A renderer that has not advanced must yield a finding, not a picture. `.stale` carries no
    /// image by design, so there is nothing for a caller to mistake for a current frame.
    func testAStalledRendererYieldsStaleAndNoPicture() async throws {
        try await load(.one, "solid_red")
        renderer.renderFrame()
        // Nothing drives the renderer here — this is the wedged display link, in miniature.
        try await Task.sleep(nanoseconds: 600_000_000)   // past the 0.5s stall threshold

        let outcome = await facade.capture(tap: "program", width: 64, height: 64, time: nil)
        XCTAssertTrue(outcome.isStale, "Got \(outcome) instead of a stall finding")
        let health = try XCTUnwrap(outcome.health)
        XCTAssertTrue(health.isStalled())
        XCTAssertGreaterThan(health.secondsSinceLastFrame, 0.5)
    }

    // MARK: - Capture

    /// The size is honoured, not echoed. Decoding the PNG is the point: metadata that merely
    /// repeated the request would pass a metadata-only assertion while the caller received a
    /// 1920×1080 image it never asked for.
    func testACaptureReturnsAPNGAtTheRequestedSizeNotTheTexturesOwn() async throws {
        try await load(.one, "solid_red")
        renderer.renderFrame()

        let outcome = await facade.capture(tap: "program", width: 160, height: 120, time: nil)
        guard case .success(let frame, let health) = outcome else {
            return XCTFail("Expected a capture, got \(outcome)")
        }
        let size = try pngPixelSize(frame.pngBase64)
        XCTAssertEqual(size.width, 160)
        XCTAssertEqual(size.height, 120)
        XCTAssertNotEqual(size.width, renderer.programTexture()?.width,
                          "A capture that returned the master's own size would pass a metadata-only check")
        XCTAssertEqual(frame.metadata.width, 160)
        XCTAssertEqual(frame.metadata.height, 120)
        XCTAssertEqual(frame.metadata.tap, "program")
        XCTAssertEqual(frame.metadata.pixelFormat, "rgba8Unorm")
        XCTAssertNil(frame.metadata.time, "A live-only tap can never carry a time")
        XCTAssertEqual(frame.metadata.documentGeneration, 0,
                       "ARShader has no document; 0 says 'not applicable' where 1 would claim a version")
        XCTAssertGreaterThan(health.frameCounter, 0)
    }

    func testEachDeckIsCapturableOnItsOwnTap() async throws {
        try await load(.two, "solid_green")
        renderer.renderFrame()

        let outcome = await facade.capture(tap: "deck-b", width: 64, height: 64, time: nil)
        guard case .success(let frame, _) = outcome else {
            return XCTFail("Expected a capture, got \(outcome)")
        }
        XCTAssertEqual(frame.metadata.tap, "deck-b")
        let size = try pngPixelSize(frame.pngBase64)
        XCTAssertEqual(size.width, 64)
        XCTAssertEqual(size.height, 64)
    }

    // MARK: - Blackout semantics (Step 5)

    /// The finding Step 5 exists for: a nil `programTexture()` during blackout means the operator
    /// cut the output, not that no scene is compiled. Reporting it as `no_output` would tell an
    /// agent the show is broken when it is working exactly as the operator intended.
    func testACaptureDuringBlackoutSaysBlackoutRatherThanNoOutput() async throws {
        try await load(.one, "solid_red")
        mixer.toggleBlackoutLatch()
        XCTAssertTrue(mixer.isBlackedOutForRender(), "Precondition: the gate is closed")
        renderer.renderFrame()

        let outcome = await facade.capture(tap: "program", width: 64, height: 64, time: nil)
        XCTAssertEqual(failureCode(outcome), "blacked_out")
        XCTAssertNotEqual(failureCode(outcome), "no_output")
    }

    /// The blackout message must be usable by whoever reads it, not merely correctly coded.
    func testTheBlackoutErrorSaysWhatItIsAndWhatItIsNot() async throws {
        try await load(.one, "solid_red")
        mixer.toggleBlackoutLatch()
        renderer.renderFrame()

        let outcome = await facade.capture(tap: "program", width: 64, height: 64, time: nil)
        guard case .failure(let error) = outcome else { return XCTFail("Expected a rejection") }
        XCTAssertTrue(error.message.lowercased().contains("blacked out"))
        let hint = try XCTUnwrap(error.hint)
        XCTAssertTrue(hint.lowercased().contains("panic button"),
                      "The hint must distinguish a deliberate cut from a failure")
    }

    /// The deliberate asymmetry, matching the app: `monitorTexture` routes deck monitors to
    /// `deckTexture`, so the operator's cue monitors stay live while the room is dark. An agent
    /// that lost them during blackout would see less than the operator does.
    func testDeckTapsStayCapturableWhileTheProgramIsBlackedOut() async throws {
        try await load(.one, "solid_red")
        mixer.toggleBlackoutLatch()
        renderer.renderFrame()

        let outcome = await facade.capture(tap: "deck-a", width: 64, height: 64, time: nil)
        guard case .success = outcome else {
            return XCTFail("A cue monitor is not blacked out; got \(outcome)")
        }
    }

    /// The other half of the blackout distinction: with the gate OPEN and nothing loaded, the same
    /// nil must read as "no output", not as blackout.
    func testAnEmptyDeckReportsNoOutputRatherThanBlackout() async throws {
        try await load(.one, "solid_red")   // so the renderer has frames and health is readable
        renderer.renderFrame()
        XCTAssertFalse(mixer.isBlackedOutForRender(), "Precondition: the gate is open")

        let outcome = await facade.capture(tap: "deck-b", width: 64, height: 64, time: nil)
        XCTAssertEqual(failureCode(outcome), "no_output")
        guard case .failure(let error) = outcome else { return XCTFail("Expected a rejection") }
        XCTAssertTrue(error.message.contains("deck B"), "Names the deck the operator sees")
    }

    // MARK: - Obligation 1: do not block

    /// **What this proves, and what it does not.** It proves a capture never *requires* the main
    /// actor: the main actor is held in a synchronous spin — nothing main-actor-isolated can run for
    /// a full second — and the capture must still finish inside that window. It would fail if the
    /// facade were made `@MainActor`, or if a hop like `await MainActor.run` appeared on this path.
    ///
    /// It does **not** prove the other half of obligation 1. The facade is non-isolated, so an
    /// `async` call from anywhere already switches to the generic executor, and a blocking
    /// `waitUntilCompleted()` on a cooperative thread would still complete inside this window. That
    /// half is held by `testTheCapturePathNeverWaitsOnTheGPU` below (construction) and verified for
    /// real by Task 14 Leg B on device (instrument FPS does not drop across a capture).
    func testACaptureCompletesWithoutTheMainActor() async throws {
        try await load(.one, "solid_red")
        renderer.renderFrame()

        let finished = DispatchSemaphore(value: 0)
        let facade = try XCTUnwrap(self.facade)
        // Detached so it cannot inherit this test's main-actor isolation and quietly pass by
        // running after the spin ends.
        let work = Task.detached {
            let outcome = await facade.capture(tap: "program", width: 64, height: 64, time: nil)
            finished.signal()
            return outcome
        }

        var completedWhileBlocked = false
        let spinUntil = CACurrentMediaTime() + 1.0
        while CACurrentMediaTime() < spinUntil {
            if finished.wait(timeout: .now()) == .success {
                completedWhileBlocked = true
                break
            }
        }

        let outcome = await work.value
        XCTAssertTrue(completedWhileBlocked,
                      "The capture did not finish while the main actor was unavailable — it is "
                      + "blocking on it, which is conformance obligation 1")
        guard case .success = outcome else { return XCTFail("Expected a capture, got \(outcome)") }
    }

    /// The half of obligation 1 no behavioural test in this process can reach, guarded the only way
    /// that can fail: by reading the source.
    ///
    /// `waitUntilCompleted()` is not marked `noasync`, so a conformer that blocks compiles clean —
    /// and the readback every other capture path in this app reaches for
    /// (`TextureReadback.managedCopy`) blocks by design, in one line, without saying so at the call
    /// site. Naming both here means the trap cannot re-enter this file silently; it has to be
    /// argued for.
    func testTheCapturePathNeverWaitsOnTheGPU() throws {
        let source = try String(contentsOf: Self.facadeSourceURL, encoding: .utf8)
        // Comments are stripped first, so the doc comments above — which discuss both by name —
        // cannot make this guard vacuous by permanently satisfying its own search.
        let code = source
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.drop { $0 == " " }.hasPrefix("//") ? "" : String($0) }
            .joined(separator: "\n")

        XCTAssertFalse(code.contains("waitUntilCompleted"),
                       "A blocking GPU wait on the capture path parks whatever executor called it "
                       + "— ControlFacade obligation 1. Await the buffer instead.")
        XCTAssertFalse(code.contains("TextureReadback.managedCopy"),
                       "managedCopy commits and blocks. The capture path builds its own awaited "
                       + "command buffer for exactly this reason.")
        XCTAssertFalse(code.contains("DispatchSemaphore"),
                       "A semaphore wait is the same trap wearing a different name.")
        // Non-vacuous: the file really does contain the awaited alternative, so the three
        // assertions above are passing because of the design and not because the search is wrong.
        XCTAssertTrue(code.contains("addCompletedHandler"),
                      "Guard is looking at the wrong file or an empty string")
    }

    private static var facadeSourceURL: URL {
        // ARShaderTests compiles the ARShader sources directly, so this file and the facade are
        // siblings in the source tree at build time.
        URL(fileURLWithPath: #filePath)          // .../App/ARShaderTests/InstrumentControlFacadeTests.swift
            .deletingLastPathComponent()          // .../App/ARShaderTests
            .deletingLastPathComponent()          // .../App
            .appendingPathComponent("ARShader/InstrumentControlFacade.swift")
    }

    // MARK: - Obligation 2: cancellation is a value

    /// Cancelling a `Task` created on the main actor and never awaited in between is deterministic:
    /// the body cannot begin until this synchronous region yields, by which time `cancel()` has
    /// already run. So this is a real assertion about the facade, not a race that usually lands.
    func testCancellationIsReportedAsAValueRatherThanThrown() async {
        let work = Task { await facade.capture(tap: "program", width: 64, height: 64, time: nil) }
        work.cancel()
        let outcome = await work.value

        XCTAssertEqual(failureCode(outcome), "cancelled")
        XCTAssertNil(outcome.health, "A cancelled request measured nothing")
        XCTAssertEqual(facade.performCaptureCallCountForTesting, 1,
                       "Validation passed — this failed on cancellation, not on a bad request")
        // What this pins is the obligation (cancellation crosses as `.failure(.cancelled)`, never
        // thrown, and no picture is produced), NOT any particular line. `performCapture` and
        // `renderHealth` both check, so either one alone satisfies it; deleting the entry check
        // was mutation-tested and correctly did not turn this red.
    }

    func testCancellationIsAlsoAValueOnTheHealthPath() async {
        let work = Task { await facade.renderHealth() }
        work.cancel()
        guard case .failure(let error) = await work.value else {
            return XCTFail("A cancelled health read must not invent a reading")
        }
        XCTAssertEqual(error.code, "cancelled")
    }

    // MARK: - Capabilities (obligation 4, and the annotation inversion)

    /// Un-annotated MCP tools default to `destructiveHint: true` client-side, so the deliberately
    /// safest surface in the project is the one that would advertise as the most dangerous.
    func testEveryAdvertisedCommandIsMarkedReadOnlyAndNotDestructive() {
        XCTAssertFalse(InstrumentControlFacade.commands.isEmpty)
        for command in InstrumentControlFacade.commands {
            XCTAssertTrue(command.annotations.readOnlyHint, "\(command.name)")
            XCTAssertFalse(command.annotations.destructiveHint, "\(command.name)")
            XCTAssertTrue(command.annotations.idempotentHint, "\(command.name)")
        }
    }

    /// Obligation 4 in the other direction: the inventory must be neither empty nor inflated. Only
    /// what this facade can actually serve is advertised — spec §6.4 also names `get_element_stats`
    /// and `get_render_stats`, and neither is expressible through `ControlFacade` today.
    func testTheAdvertisedInventoryIsExactlyWhatTheFacadeCanServe() async {
        let capabilities = await facade.capabilities()
        XCTAssertEqual(capabilities.commands.map(\.name).sorted(),
                       ["instrument.capture", "instrument.describe_state"])
        XCTAssertEqual(capabilities.protocolVersion, "1")
        for command in capabilities.commands {
            XCTAssertFalse(command.schemaHash.isEmpty, "\(command.name) publishes no schema hash")
        }
    }

    /// A schema advertising a parameter every tap rejects would invite the exact request the facade
    /// then has to refuse.
    func testTheCaptureSchemaAdvertisesNoTimeArgument() async {
        let capabilities = await facade.capabilities()
        let capture = capabilities.commands.first { $0.name == "instrument.capture" }
        let schema = try? XCTUnwrap(capture?.schema)
        XCTAssertNil(schema?.properties["time"],
                     "No tap accepts a time, so none may be advertised")
        XCTAssertEqual(schema?.required.sorted(), ["height", "tap", "width"])
    }
}
#endif
