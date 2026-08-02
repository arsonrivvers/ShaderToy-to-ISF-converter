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

    func testSteadyStateAllocatesNoNewTextures() throws {
        let (renderer, _, _) = try makeRenderer()
        renderer.renderFrame()
        let first = try XCTUnwrap(renderer.rawMasterTexture())
        for _ in 0..<30 { renderer.renderFrame() }
        let last = try XCTUnwrap(renderer.rawMasterTexture())
        XCTAssertTrue(first === last,
                      "Master textures are pooled and reused; a new object per frame means the "
                      + "steady-state frame is allocating")
    }
}
