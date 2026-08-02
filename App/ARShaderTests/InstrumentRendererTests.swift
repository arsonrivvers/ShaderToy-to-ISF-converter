import XCTest
import Metal
import VVMetalKit

@MainActor
final class InstrumentRendererTests: XCTestCase {
    private func makeRenderer() throws -> (InstrumentRenderer, MTLDevice, MTLCommandQueue) {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let queue = try XCTUnwrap(device.makeCommandQueue())
        return (InstrumentRenderer(device: device, queue: queue, mixer: MixerState()), device, queue)
    }

    func testMasterIsFixedAt1920x1080() throws {
        let (renderer, _, _) = try makeRenderer()
        renderer.isProgramLive = false      // output closed: PREVIEW SCALE governs the live chain
        renderer.renderFrame()
        // rawMasterTexture, not programTexture: this measures the texture, not the blackout gate.
        let tex = try XCTUnwrap(renderer.rawMasterTexture())
        XCTAssertEqual(tex.width, 1920)
        XCTAssertEqual(tex.height, 1080)
    }

    func testEmptyInstrumentRendersOpaqueBlack() throws {
        let (renderer, device, queue) = try makeRenderer()
        renderer.renderFrame()
        let tex = try XCTUnwrap(renderer.programTexture())
        let readback = try XCTUnwrap(TextureReadback.managedCopy(of: tex, device: device, queue: queue))
        let stats = try XCTUnwrap(FramePixelStats.analyze(texture: readback))
        XCTAssertLessThan(stats.maxLuma, PixelGate.blackLumaFloor,
                          "An instrument with no shaders loaded must render black, not garbage")
        XCTAssertEqual(stats.nanCount, 0)
    }

    // MARK: the mid-frame resize race (final-review F4)

    /// `renderFrame` captures the live render size under its FIRST lock, releases the lock to
    /// rasterise the decks, then re-locks to composite. `isProgramLive` (and `previewScale`, and
    /// `outputResolution`) run on the main actor and reallocate `masters` inside that window — so
    /// that frame composited deck output rasterised at the SCALED size into FULL-SIZE targets and
    /// ran the master FX chain at the stale size. On the wall, at the moment the projector opens:
    /// a small image in the corner of an otherwise black frame, at the instant the audience first
    /// sees anything.
    ///
    /// Driven through the real production race, not a re-derivation: `didRasteriseDecksForTesting`
    /// fires inside `renderFrame`'s own unlocked window, and this flips the real
    /// `isProgramLive` setter from it.
    func testAFrameWhoseLiveSizeMovesMidRenderSkipsTheCompositeRatherThanDrawingItWrong() throws {
        let (renderer, _, _) = try makeRenderer()
        renderer.isProgramLive = false
        renderer.previewScale = RenderScale(percent: 25)
        renderer.renderFrame()
        XCTAssertEqual(renderer.skippedStaleCompositeCountForTesting, 0,
                       "an undisturbed frame must composite normally")

        // The projector opens exactly between deck rasterisation and the composite.
        renderer.didRasteriseDecksForTesting = { renderer.isProgramLive = true }
        renderer.renderFrame()
        renderer.didRasteriseDecksForTesting = nil

        XCTAssertEqual(renderer.skippedStaleCompositeCountForTesting, 1,
                       "the frame whose live size moved under it must be skipped — one repeated "
                       + "black frame is recoverable, one malformed frame on the wall is not")

        // And the very next frame is normal again: this skips ONE frame, it does not wedge.
        renderer.renderFrame()
        XCTAssertEqual(renderer.skippedStaleCompositeCountForTesting, 1)
    }

    /// The other half: a size that does NOT move must not be treated as stale, or every frame skips
    /// its composite and the instrument renders nothing at all.
    func testAnUndisturbedFrameNeverSkipsItsComposite() throws {
        let (renderer, _, _) = try makeRenderer()
        renderer.isProgramLive = false
        for _ in 0..<10 { renderer.renderFrame() }
        XCTAssertEqual(renderer.skippedStaleCompositeCountForTesting, 0)
    }

    // MARK: PREVIEW SCALE is inert while projecting — including its allocations (final-review F9)

    /// `previewScale`'s setter guarded on its own input changing, then reallocated unconditionally.
    /// While `programLive` is true the resolved size ignores `renderScale` entirely, so the "fresh"
    /// pair was the same size as the old one: ~16 MB allocated and discarded, and `masterIndex`
    /// reset, per keystroke in a field that is documented to do nothing while the projector is up.
    func testTypingIntoPreviewScaleWhileProjectingReallocatesNothing() throws {
        let (renderer, _, _) = try makeRenderer()
        renderer.isProgramLive = true
        renderer.renderFrame()
        let before = try XCTUnwrap(renderer.rawMasterTexture())

        // "100" typed one character at a time: 1, 10, 100.
        for percent in [1, 10, 100] { renderer.previewScale = RenderScale(percent: percent) }

        let after = try XCTUnwrap(renderer.rawMasterTexture())
        XCTAssertTrue(before === after,
                      "a control that is inert while projecting must not churn the master pair — "
                      + "same resolved size means no reallocation at all")
    }

    /// …and the guard must not break the case it exists inside: with the projector CLOSED,
    /// PREVIEW SCALE governs the live chain and a genuine size change must still reallocate.
    func testPreviewScaleStillReallocatesWhenItActuallyChangesTheLiveSize() throws {
        let (renderer, _, _) = try makeRenderer()
        renderer.isProgramLive = false
        renderer.renderFrame()
        let before = try XCTUnwrap(renderer.rawMasterTexture())

        renderer.previewScale = RenderScale(percent: 25)

        let after = try XCTUnwrap(renderer.rawMasterTexture())
        XCTAssertFalse(before === after, "a real size change must still allocate a matching pair")
        XCTAssertEqual(after.width, 480)
    }

    /// **Fast-fail shape, not a root-cause fix.** This test intermittently HANGS when run inside the
    /// full 327-test suite — observed 2 times in 7 runs, eventually killed by SIGTERM after a
    /// variable ~195-518s (not a fixed watchdog timeout) — even though it passes in 0.003s alone,
    /// passes with its whole class alone, and passes with the 12 alphabetically-preceding classes
    /// (153/153). With this one test skipped, the rest of the suite is a healthy 326/326 in ~25s.
    /// Root cause is unknown and is tracked separately; this only converts a silent multi-minute
    /// suite stall into a named ~30s failure so one bad run doesn't cost the whole CI cycle.
    ///
    /// `executionTimeAllowance` was considered and rejected: the scheme has no test-timeout key, so
    /// XCTest's own timeout enforcement is not reliably wired up, and a mechanism that silently does
    /// nothing when a flag is absent is worse than none. Instead the 31-frame loop runs on a
    /// background queue while this thread waits on an `XCTestExpectation` with an explicit 30s
    /// timeout — self-contained regardless of scheme configuration.
    ///
    /// Running the loop off the main thread is consistent with production, not a compromise made
    /// for the test: `InstrumentRenderer` is deliberately NOT `@MainActor` because `renderFrame()`
    /// is driven from the CVDisplayLink thread (see its doc comment above the class declaration),
    /// and is `@unchecked Sendable` with one coarse lock guarding every render-thread-touched field.
    /// `MixerState.renderLayers()`/`isBlackedOutForRender()`, which `renderFrame()` calls into, are
    /// themselves `nonisolated` for the same reason. `rawMasterTexture()` takes the same lock.
    ///
    /// If the timeout fires, the background thread is simply abandoned mid-loop — acceptable here
    /// because the point is the SUITE staying alive to report a real, named failure, not this one
    /// renderer's cleanup.
    func testSteadyStateAllocatesNoNewTextures() throws {
        let (renderer, _, _) = try makeRenderer()

        let done = expectation(description: "31-frame steady-state render loop completed")
        var first: MTLTexture?
        var last: MTLTexture?
        DispatchQueue.global(qos: .userInitiated).async {
            renderer.renderFrame()
            first = renderer.rawMasterTexture()
            for _ in 0..<30 { renderer.renderFrame() }
            last = renderer.rawMasterTexture()
            done.fulfill()
        }
        wait(for: [done], timeout: 30)

        guard let first, let last else {
            XCTFail("The steady-state render loop did not complete within 30s. This is the known "
                    + "intermittent full-suite hang on testSteadyStateAllocatesNoNewTextures "
                    + "(observed 2/7 runs, SIGTERM after ~195-518s) — the rest of the suite is "
                    + "otherwise healthy (326/326 in ~25s with this test skipped). Root cause is "
                    + "not fixed here; see the doc comment on this test for what has already been "
                    + "ruled out.")
            return
        }
        XCTAssertTrue(first === last,
                      "Master textures are pooled and reused; a new object per frame means the "
                      + "steady-state frame is allocating")
    }
}
