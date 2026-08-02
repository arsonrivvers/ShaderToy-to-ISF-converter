import XCTest
import Metal
import VVMetalKit
import ImageIO
import CoreGraphics
@testable import ARShader

final class ThumbnailServiceTests: XCTestCase {
    private func temporaryCacheDirectory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("thumbsvc-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return dir
    }

    private func fixtureURL(_ name: String) throws -> URL {
        try XCTUnwrap(Bundle(for: Self.self)
            .url(forResource: name, withExtension: "fs", subdirectory: "Fixtures"))
    }

    /// Decode a PNG back into a known RGBA8 layout, mirroring `FramePNGEncoderTests.decodeRGBA` —
    /// so I4's pixel assertion doesn't depend on the decoder's preferred format.
    private func decodeRGBA(_ png: Data) -> (w: Int, h: Int, bytes: [UInt8])? {
        guard let src = CGImageSourceCreateWithData(png as CFData, nil),
              let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
        let w = img.width, h = img.height
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        let ok = bytes.withUnsafeMutableBytes { buf -> Bool in
            guard let ctx = CGContext(
                data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8,
                bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        return ok ? (w, h, bytes) : nil
    }

    func testAValidShaderProducesAnImage() async throws {
        let service = ThumbnailService(cacheDirectory: try temporaryCacheDirectory())
        let result = await service.thumbnail(for: try fixtureURL("solid_red"), priority: .batch)
        guard case .image = result else { return XCTFail("expected an image, got \(result)") }
    }

    /// The whole reason t is not 0: many shaders are black at t=0, and a black thumbnail is worse
    /// than no thumbnail. 2.0s is past nearly every fade-in and early enough that feedback shaders
    /// have not drifted into mush.
    ///
    /// I4 (round-1 review): this is a sanity check on the CONSTANT only — it catches an edit to
    /// `sampleTime` but not a render call site that ignores it and passes a literal instead. That
    /// mutation is proven by `testTheRenderedThumbnailReflectsTheSampleTimeNotZero` below, which
    /// inspects actual rendered pixels rather than comparing two literals.
    func testTheSampleTimeIsTwoSeconds() {
        XCTAssertEqual(ThumbnailService.sampleTime, 2.0)
    }

    /// The real proof for I4: `solid_red` is time-invariant and can't catch a render call site
    /// that silently ignores `sampleTime` — passing a literal `0.0` at the call site instead of
    /// `Self.sampleTime` would still produce a red image and this suite would stay green. This
    /// renders `time_gate.fs` (black at t=0, red past t=1) and inspects the decoded pixels, so a
    /// render that actually happened at t=0 is visibly different from one at `sampleTime` (2.0).
    func testTheRenderedThumbnailReflectsTheSampleTimeNotZero() async throws {
        let service = ThumbnailService(cacheDirectory: try temporaryCacheDirectory())
        let result = await service.thumbnail(for: try fixtureURL("time_gate"), priority: .batch)
        guard case .image(let png) = result else { return XCTFail("expected an image, got \(result)") }
        let decoded = try XCTUnwrap(decodeRGBA(png), "PNG failed to decode")
        let hasRedPixel = stride(from: 0, to: decoded.bytes.count, by: 4).contains { i in
            decoded.bytes[i] > 200 && decoded.bytes[i + 1] < 50 && decoded.bytes[i + 2] < 50
        }
        XCTAssertTrue(hasRedPixel,
                      "expected a red frame (rendered past t=1), got an all-black one — the render "
                      + "did not actually sample at sampleTime")
    }

    func testABrokenShaderResolvesAsUnavailable() async throws {
        let service = ThumbnailService(cacheDirectory: try temporaryCacheDirectory())
        let result = await service.thumbnail(for: try fixtureURL("broken"), priority: .batch)
        XCTAssertEqual(result, .unavailable)
    }

    /// A broken shader must be compiled ONCE. The second call is a cache read, not a recompile.
    func testABrokenShaderIsNotRecompiledOnEveryRequest() async throws {
        let service = ThumbnailService(cacheDirectory: try temporaryCacheDirectory())
        let broken = try fixtureURL("broken")
        _ = await service.thumbnail(for: broken, priority: .batch)
        let compilesBefore = await service.compileCountForTesting
        _ = await service.thumbnail(for: broken, priority: .batch)
        let compilesAfter = await service.compileCountForTesting
        XCTAssertEqual(compilesBefore, compilesAfter,
                       "the second request must be served from the cached failure")
    }

    /// The safety property that no other test can see, because no unit test has a live render
    /// loop: a thumbnail compile must never share the queue the instrument is drawing on.
    func testTheServiceNeverUsesTheLiveRenderQueue() async throws {
        let service = ThumbnailService(cacheDirectory: try temporaryCacheDirectory())
        let serviceQueue = await service.commandQueueForTesting
        XCTAssertFalse(serviceQueue === RenderProperties.global().renderQueue,
                       "sharing the live queue is how a thumbnail becomes a dropped frame mid-set")
        // The POSITIVE half (final-review L33/F13a). "Not the live queue" alone passes for a
        // service that minted its own third queue, or wired one to nil — it says what the queue
        // is NOT. `bgCmdQueue` is the singleton's documented background queue and the one this
        // service is supposed to be on.
        XCTAssertTrue(serviceQueue === RenderProperties.global().bgCmdQueue,
                      "and it must be the shared background queue specifically, not merely some "
                      + "other queue that happens not to be the live one")
    }

    /// Nothing protected this before (final-review L33). A harness `Instrument()` that resolved the
    /// real `~/Library/Application Support/ARShader/Thumbnails` would create it, and — before the
    /// sweep was gated — a test run above the 2,000-entry ceiling could EVICT the operator's real
    /// thumbnails. Pure string comparison, no I/O: the assertion is about which path was chosen.
    @MainActor
    func testAHarnessInstrumentNeverResolvesTheOperatorsRealThumbnailCache() async throws {
        let instrument = Instrument()
        let resolved = await instrument.thumbnailService.cacheDirectoryForTesting
        let path = try XCTUnwrap(resolved).path

        let temp = FileManager.default.temporaryDirectory.path
        XCTAssertTrue(path.hasPrefix(temp),
                      "a test instrument's cache must live under the temporary directory — got "
                      + path)

        let appSupport = try XCTUnwrap(FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first).path
        XCTAssertFalse(path.hasPrefix(appSupport),
                       "and must never be under Application Support, where the operator's real "
                       + "~2,000-entry cache lives")
    }

    /// Hover is superseded constantly as the pointer moves; a thumbnail for a row the pointer has
    /// left is wasted work. This is the OPPOSITE of the bank's requirement, which is why priority
    /// is a parameter rather than a policy baked into the service.
    ///
    /// NOTE: no counterpart test here proves an in-flight `.interactive` request is actually
    /// interrupted by `cancelInteractive()`, and this test is deliberately SEQUENTIAL rather than
    /// racing `cancelInteractive()` against a concurrently-started `.batch` call — both were tried
    /// and abandoned as undeliverable without new production surface. `render()` has no `await`
    /// between its entry and either return path, so once the actor dequeues a render it runs to
    /// completion without ever yielding — an externally-issued `cancelInteractive()` can only
    /// matter if it reaches the actor before that dequeue, and across ~24 empirical trials
    /// (`async let`, `Task.detached`, two fixture speeds including a deliberately expensive
    /// 2M-iteration loop) it never once did; duration didn't move the result, because the race is
    /// about enqueue order, not render speed. See the "determinism decision" section of
    /// task-7-report.md for the full evidence.
    ///
    /// What IS deterministic, and what this test proves instead: cancelling hover work must never
    /// leave a mark that a LATER, independent bank request trips over. `cancelInteractive()` runs
    /// to completion first (a safe no-op — nothing interactive is in flight), then a fresh
    /// `.batch` request is made and must succeed.
    ///
    /// **Fix round 1, F3 — honest scope, not a weaker stand-in dressed up as a strong one.** Step
    /// 4's brief named the mutation "make `cancelInteractive()` cancel everything," meaning: route
    /// `.batch` through the same `interactiveTask`-tracked `Task` `.interactive` uses, so a racing
    /// `cancelInteractive()` cancels it too. **That literal mutation does NOT fail this test** —
    /// tried and confirmed: at the moment `cancelInteractive()` runs (line above, sequential, no
    /// batch work started yet), there is nothing for it to cancel, so the mutated `.batch` branch
    /// still runs to completion untouched. This is not a gap I missed; it is the SAME finding as
    /// the dropped `testAnInteractiveRequestSupersedesItsPredecessor` wearing a different hat — the
    /// operator ruled it unfalsifiable rather than asking for a fix: `.batch`'s case body
    /// (`ThumbnailService.swift:97-98`) never reads `interactiveTask` or anything else
    /// `cancelInteractive()` touches (`:141-144`), and actor serialization means an EXTERNAL
    /// `cancelInteractive()` call cannot preempt a render already dequeued regardless of what it's
    /// wired to touch — so "cancelling hover drops a queued bank thumbnail" has no reachable
    /// failure mode as this service is built, by ANY mutation that only changes what gets raced
    /// against an in-flight render.
    ///
    /// **The mutation actually run and reverted for this test (see task-7-report.md) was a
    /// DIFFERENT, sequential-reachable class:** a sticky flag — `cancelInteractive()` sets a bit
    /// that never resets, and `render()`'s first guard checks it — so a call already completed
    /// (line above) poisons every `.batch` request made AFTER it, forever. That mutation DOES fail
    /// this test, because it doesn't need to win any race: it corrupts persistent actor state that
    /// a later, fully-sequential call reads. That is the actual, narrower guarantee this test has
    /// power to enforce: cancelling hover work leaves no lasting mark for a later bank request to
    /// trip over — not "an in-flight bank render survives a concurrent cancel," which no test here
    /// (or achievable here) proves.
    func testCancellingInteractiveWorkLeavesBatchWorkAlone() async throws {
        let service = ThumbnailService(cacheDirectory: try temporaryCacheDirectory())
        await service.cancelInteractive()
        let result = await service.thumbnail(for: try fixtureURL("solid_red"), priority: .batch)
        guard case .image = result else {
            return XCTFail("A prior cancelInteractive() call must never poison a LATER, "
                            + "independent .batch request — got \(result) instead of an image for "
                            + "a fresh, uncached solid_red render.")
        }
    }

    /// C1/I2 (round-1 review, Critical): the original brief persisted `.unavailable` for ANY
    /// non-image outcome, including a cancelled request — so a hover interrupted mid-request
    /// permanently marked a valid shader broken. `.batch` cancellation is the deterministic way to
    /// test the shared fix (`RenderOutcome.cancelled` is never persisted): unlike `.interactive`
    /// (which hands the render off to an inner unstructured `Task` not reachable from the caller's
    /// own task), `.batch` awaits `render` directly on the CALLING task with no intervening
    /// `await`, so cancelling that task immediately after creation — before it has had a chance to
    /// run — guarantees `Task.isCancelled` reads true for its entire body. No scheduling race.
    func testACancelledRequestIsNeverPersistedAsUnavailable() async throws {
        let service = ThumbnailService(cacheDirectory: try temporaryCacheDirectory())
        let shader = try fixtureURL("solid_red")
        let cancelled = Task { await service.thumbnail(for: shader, priority: .batch) }
        cancelled.cancel()
        _ = await cancelled.value
        // If the cancelled request had persisted `.unavailable`, this uncancelled follow-up would
        // read the poisoned cache entry back instead of rendering fresh.
        let result = await service.thumbnail(for: shader, priority: .batch)
        guard case .image = result else {
            return XCTFail("a cancelled request must not poison the cache; got \(result)")
        }
    }
}
