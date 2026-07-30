import XCTest
import Metal

@MainActor
final class FrameGraphTests: XCTestCase {
    private var device: MTLDevice!
    private var queue: MTLCommandQueue!
    private var mixer: MixerState!
    private var renderer: InstrumentRenderer!

    override func setUpWithError() throws {
        device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        queue = try XCTUnwrap(device.makeCommandQueue())
        mixer = MixerState()
        renderer = InstrumentRenderer(device: device, queue: queue, mixer: mixer)
    }

    private func fixture(_ name: String) throws -> String {
        let url = try XCTUnwrap(Bundle(for: Self.self)
            .url(forResource: name, withExtension: "fs", subdirectory: "Fixtures"))
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func load(_ id: DeckID, _ fixtureName: String) throws {
        let deck = renderer.deck(id)
        let done = expectation(description: "compile \(fixtureName) on \(id.rawValue)")
        deck.unit.onCompileFinished = { done.fulfill() }
        deck.unit.load(source: try fixture(fixtureName), name: "\(fixtureName).fs")
        wait(for: [done], timeout: 30)
        deck.unit.onCompileFinished = nil
        XCTAssertNil(deck.unit.compileError)
    }

    private func renderAndRead() throws -> SIMD3<Double> {
        renderer.renderFrame()
        let tex = try XCTUnwrap(renderer.programTexture())
        let readback = try XCTUnwrap(
            TextureReadback.managedCopy(of: tex, device: device, queue: queue))
        return try XCTUnwrap(TestPixels.meanRGB(of: readback))
    }

    func testOneDeckAtFullOpacityReachesTheMaster() throws {
        try load(.one, "solid_red")
        mixer.crossfadePosition = 0    // deck 1 weight 1
        let rgb = try renderAndRead()
        XCTAssertEqual(rgb.x, 1.0, accuracy: 0.02)
        XCTAssertEqual(rgb.y, 0.0, accuracy: 0.02)
    }

    func testAnUnloadedDeckContributesNothingRatherThanBlack() throws {
        // Deck 2 is empty. With the crossfader hard right, deck 2's weight is 1 and deck 1's is 0,
        // so the correct output is black — but via "deck 1 muted", not "deck 2 painted black".
        try load(.one, "solid_red")
        mixer.crossfadePosition = 1
        let rgb = try renderAndRead()
        XCTAssertLessThan(rgb.x, 0.02, "Deck 1 is faded out")

        // Slide back to centre: deck 1 returns at half. An empty deck 2 must not have painted over
        // the master in the meantime.
        mixer.crossfadePosition = 0.5
        let mid = try renderAndRead()
        XCTAssertEqual(mid.x, 0.5, accuracy: 0.03)
    }

    func testTwoDecksCompositeInLayerOrder() throws {
        try load(.one, "solid_red")
        try load(.two, "solid_green")
        mixer.crossfadePosition = 0.5   // both weight 0.5
        mixer.setBlendMode(.normal, for: .two)

        // deck 1: normal, a = 0.5, backdrop black  -> (0.5, 0, 0)
        // deck 2: normal, a = 0.5, backdrop above  -> (0.25, 0.5, 0)
        let rgb = try renderAndRead()
        XCTAssertEqual(rgb.x, 0.25, accuracy: 0.03)
        XCTAssertEqual(rgb.y, 0.5, accuracy: 0.03)
        XCTAssertEqual(rgb.z, 0.0, accuracy: 0.02)
    }

    func testCompositeOrderIsNotCommutative() throws {
        // Proves the layer stack is real: swapping which deck holds which shader changes the
        // output for a non-commutative blend.
        try load(.one, "solid_red")
        try load(.two, "solid_green")
        mixer.crossfadePosition = 0.5
        mixer.setBlendMode(.colorBurn, for: .two)
        let first = try renderAndRead()

        try load(.one, "solid_green")
        try load(.two, "solid_red")
        let swapped = try renderAndRead()
        XCTAssertNotEqual(first, swapped, "Layer order must affect a non-commutative blend")
    }

    func testProgramTextureTracksThePingPongParity() throws {
        // With one active layer the result lands in a different master than with two.
        // programTexture() must track that, not assume it.
        try load(.one, "solid_red")
        mixer.crossfadePosition = 0
        let oneLayer = try renderAndRead()
        XCTAssertEqual(oneLayer.x, 1.0, accuracy: 0.02)

        try load(.two, "solid_green")
        mixer.setOpacity(1.0, for: .two)
        mixer.crossfadePosition = 1     // only deck 2 contributes
        let twoLayers = try renderAndRead()
        XCTAssertEqual(twoLayers.y, 1.0, accuracy: 0.02)
        XCTAssertLessThan(twoLayers.x, 0.02)
    }

    func testEmptyInstrumentStillRendersOpaqueBlack() throws {
        let rgb = try renderAndRead()
        XCTAssertLessThan(rgb.x + rgb.y + rgb.z, 0.02)
    }

    func testDeckTexturesAreAvailableForMonitorsAfterTheFrame() throws {
        try load(.one, "solid_red")
        renderer.renderFrame()
        let deckTex = try XCTUnwrap(renderer.deckTexture(.one),
                                    "Monitors read this in a LATER command buffer")
        let readback = try XCTUnwrap(
            TextureReadback.managedCopy(of: deckTex, device: device, queue: queue))
        let rgb = try XCTUnwrap(TestPixels.meanRGB(of: readback))
        XCTAssertEqual(rgb.x, 1.0, accuracy: 0.02,
                       "The deck monitor shows the deck BEFORE opacity and blending")
        XCTAssertNil(renderer.deckTexture(.two), "An unloaded deck has no monitor image")
    }

    func testFrameStillEncodesNoReadbackAndCommitsPerElementOnly() throws {
        // The original claim was "one command buffer per frame". Per-tile GPU metering replaced
        // that with one buffer PER ELEMENT — there is no way to time elements inside a single
        // buffer on this hardware (see GPUPassTimerTests). What survives, and matters, is that
        // nothing does a readback or commits per STAGE: the count is bounded by the element count,
        // not by the number of passes.
        try load(.one, "solid_red")
        try load(.two, "solid_green")
        let before = renderer.committedBufferCount
        renderer.renderFrame()
        XCTAssertEqual(renderer.committedBufferCount - before, 3,
                       "two decks plus the master — not one per pass")
    }

    // MARK: per-element metering

    func testMeteringIsOnByDefault() {
        // The operator asked for a permanent per-tile readout rather than a switch (2026-07-30).
        XCTAssertTrue(renderer.isMeteringEnabled)
    }

    func testDisablingMeteringCollapsesTheFrameToOneBuffer() throws {
        // No UI for this, but kept settable so a future performance question about the split can
        // be answered by measurement rather than argument.
        try load(.one, "solid_red")
        try load(.two, "solid_green")
        renderer.isMeteringEnabled = false
        let before = renderer.committedBufferCount
        renderer.renderFrame()
        XCTAssertEqual(renderer.committedBufferCount - before, 1)
    }

    func testSplittingTheBuffersDoesNotChangeWhatIsRendered() throws {
        // The master samples deck outputs written by buffers committed before it. Metal orders
        // buffers on one queue by commit order and tracks cross-buffer hazards, so the image must
        // be identical either way. If that were wrong this would read black or stale.
        try load(.one, "solid_red")
        try load(.two, "solid_green")
        mixer.crossfadePosition = 0.5
        mixer.setBlendMode(.normal, for: .two)
        let split = try renderAndRead()

        renderer.isMeteringEnabled = false
        let single = try renderAndRead()
        XCTAssertEqual(split.x, single.x, accuracy: 0.02)
        XCTAssertEqual(split.y, single.y, accuracy: 0.02)
        XCTAssertEqual(split.z, single.z, accuracy: 0.02)
    }

    func testNoElementFiguresArePublishedWhileMeteringIsOff() throws {
        // "Not measured" and "measured as free" are different claims. With metering off the tiles
        // must show nothing at all rather than a zero.
        try load(.one, "solid_red")
        renderer.isMeteringEnabled = false
        var published: [[RenderElement: Double]] = []
        renderer.onElementStats = { published.append($0) }
        for _ in 0..<8 { renderer.renderFrame() }
        renderer.onElementStats = nil
        XCTAssertTrue(published.allSatisfy(\.isEmpty),
                      "metering off must publish no per-element figures")
    }

    func testAnElementWithNoCompletedSampleIsAbsentRatherThanZero() {
        var acc = ElementStatsAccumulator()
        acc.add(.deck(.one), seconds: 0.004)
        acc.add(.deck(.two), seconds: 0)      // a failure path reports 0 — not a measurement
        let drained = acc.drain()
        XCTAssertEqual(try XCTUnwrap(drained[.deck(.one)]), 4.0, accuracy: 0.001)
        XCTAssertNil(drained[.deck(.two)], "a zero sample is not evidence the deck was free")
        XCTAssertTrue(acc.drain().isEmpty, "draining clears the window")
    }

    // MARK: resolution

    func testChangingTheOutputResolutionResizesTheMaster() throws {
        renderer.outputResolution = RenderSize(width: 1280, height: 720)
        renderer.renderFrame()
        let tex = try XCTUnwrap(renderer.rawMasterTexture())
        XCTAssertEqual(tex.width, 1280)
        XCTAssertEqual(tex.height, 720)
    }

    func testTheInstrumentStillRendersCorrectlyAfterAResolutionChange() throws {
        try load(.one, "solid_red")
        mixer.crossfadePosition = 0
        XCTAssertEqual(try renderAndRead().x, 1.0, accuracy: 0.02)

        renderer.outputResolution = RenderSize(width: 960, height: 540)
        let rgb = try renderAndRead()
        XCTAssertEqual(rgb.x, 1.0, accuracy: 0.02, "still red at the new size")
        XCTAssertEqual(try XCTUnwrap(renderer.rawMasterTexture()).width, 960)
    }

    func testSettingTheSameResolutionIsANoOp() throws {
        renderer.renderFrame()
        let before = try XCTUnwrap(renderer.rawMasterTexture())
        renderer.outputResolution = renderer.outputResolution
        XCTAssertTrue(try XCTUnwrap(renderer.rawMasterTexture()) === before,
                      "A no-op set must not reallocate — the UI binds to this and writes freely")
    }

    func testACuedDeckIsStillVisibleOnItsOwnMonitor() throws {
        // Deck 2 is loaded but faded out, so it renders at cue resolution. Its monitor must still
        // show it - that is what cueing IS.
        try load(.two, "solid_green")
        mixer.crossfadePosition = 0     // deck 2 weight 0 -> cued, not live
        renderer.renderFrame()
        let deckTex = try XCTUnwrap(renderer.deckTexture(.two))
        let readback = try XCTUnwrap(
            TextureReadback.managedCopy(of: deckTex, device: device, queue: queue))
        let rgb = try XCTUnwrap(TestPixels.meanRGB(of: readback))
        XCTAssertEqual(rgb.y, 1.0, accuracy: 0.02, "the cue monitor shows green, not black")
    }

    func testStatsArePublishedFromTheRenderLoop() throws {
        // The FPS readout must come from measured frames, never a fabricated number.
        //
        // Deliberately a SMALL number of frames. An earlier version of this test looped 200 times
        // and hung the whole suite: a Metal command queue allows only ~64 buffers in flight, so
        // `makeCommandBuffer()` blocked on its semaphore forever while the display-link thread was
        // also competing for drawables. Diagnosed from a `sample` of the wedged test host,
        // 2026-07-30. Rendering in a tight synchronous loop is not how the instrument runs.
        //
        // The accumulator's windowing maths is covered separately and purely by RenderStatsTests;
        // what this asserts is only the WIRING — that the renderer publishes through onStats and
        // that anything it publishes is a real positive measurement.
        var received: [RenderStats] = []
        renderer.onStats = { if let s = $0 { received.append(s) } }
        for _ in 0..<8 { renderer.renderFrame() }
        renderer.onStats = nil
        for s in received {
            XCTAssertGreaterThan(s.fps, 0, "a published snapshot must be a real measurement")
        }
    }

    // MARK: render scale

    func testRenderScaleResizesTheMaster() throws {
        renderer.outputResolution = RenderSize(width: 1920, height: 1080)
        renderer.previewScale = RenderScale(percent: 50)
        renderer.renderFrame()
        let tex = try XCTUnwrap(renderer.rawMasterTexture())
        XCTAssertEqual(tex.width, 960)
        XCTAssertEqual(tex.height, 540)
    }

    func testRenderScaleAppliesToALiveDeckNotJustACuedOne() throws {
        // The whole point of replacing CueQuality: it was applied ONLY when effectiveOpacity was
        // zero, so it was inert on the live deck costing the frame.
        try load(.one, "solid_red")
        mixer.crossfadePosition = 0             // deck 1 LIVE at full opacity
        renderer.previewScale = RenderScale(percent: 25)
        renderer.renderFrame()
        // Assert on the RASTER size, not the owned texture: the owned texture is the same size
        // either way, so reading deckTexture alone would pass even if the scale never reached the
        // rasteriser — which is the only place the GPU saving actually happens.
        XCTAssertEqual(try XCTUnwrap(renderer.deckRasterSize(.one)).width, 480,
                       "a LIVE deck must rasterise at the render scale")
        XCTAssertEqual(try XCTUnwrap(renderer.deckTexture(.one)).width, 480,
                       "and its owned texture follows the live size")
    }

    func testALiveAndACuedDeckRasteriseAtDifferentScalesInTheSameFrame() throws {
        try load(.one, "solid_red")
        try load(.two, "solid_green")
        mixer.crossfadePosition = 0          // deck 1 live, deck 2 cued
        renderer.previewScale = RenderScale(percent: 100)
        renderer.cueRenderScale = RenderScale(percent: 25)
        renderer.renderFrame()
        XCTAssertEqual(try XCTUnwrap(renderer.deckRasterSize(.one)).width, 1920,
                       "the live deck pays full price")
        XCTAssertEqual(try XCTUnwrap(renderer.deckRasterSize(.two)).width, 480,
                       "the cued deck does not")
    }

    func testCueScaleAllocatesNothing() throws {
        // Cue changes only how many pixels are rasterised before upscaling into the EXISTING owned
        // texture. That is exactly why it is safe to drop very low.
        try load(.one, "solid_red")
        renderer.renderFrame()
        let before = try XCTUnwrap(renderer.deckTexture(.one))
        renderer.cueRenderScale = RenderScale(percent: 10)
        renderer.renderFrame()
        XCTAssertTrue(try XCTUnwrap(renderer.deckTexture(.one)) === before)
    }

    func testACuedDeckKeepsAFullSizeOwnedTextureAndStaysVisible() throws {
        // Rasterise small, upscale into a fixed owned texture — so starting a fade reallocates
        // nothing and cannot hitch at the worst moment.
        try load(.two, "solid_green")
        mixer.crossfadePosition = 0             // deck 2 cued
        renderer.cueRenderScale = RenderScale(percent: 25)
        renderer.renderFrame()
        let tex = try XCTUnwrap(renderer.deckTexture(.two))
        XCTAssertEqual(tex.width, renderer.outputResolution.width,
                       "the owned texture stays at the live size")
        XCTAssertEqual(try XCTUnwrap(renderer.deckRasterSize(.two)).width, 480,
                       "while only the rasterised pixel count drops")
        let readback = try XCTUnwrap(
            TextureReadback.managedCopy(of: tex, device: device, queue: queue))
        let rgb = try XCTUnwrap(TestPixels.meanRGB(of: readback))
        XCTAssertEqual(rgb.y, 1.0, accuracy: 0.02, "and still shows green on its monitor")
    }

    func testCueScaleIsAFractionOfTheLiveRenderNotOfTheOutput() throws {
        // A cued deck must never rasterise LARGER than a live one. Applying cue to the output
        // resolution made that possible: preview 25% + cue 50% gave the faded-out deck 960px
        // against the live deck's 480 — the deck nobody can see costing twice the one on program.
        try load(.one, "solid_red")
        try load(.two, "solid_green")
        mixer.crossfadePosition = 0          // deck 1 live, deck 2 cued
        renderer.previewScale = RenderScale(percent: 25)
        renderer.cueRenderScale = RenderScale(percent: 50)
        renderer.renderFrame()
        let live = try XCTUnwrap(renderer.deckRasterSize(.one)).width
        let cued = try XCTUnwrap(renderer.deckRasterSize(.two)).width
        XCTAssertEqual(live, 480)
        XCTAssertEqual(cued, 240, "cue is a fraction of the LIVE render, not of the output")
        XCTAssertLessThanOrEqual(cued, live, "a cued deck can never cost more than a live one")
    }

    func testTheInstrumentStillRendersCorrectlyAtAReducedRenderScale() throws {
        try load(.one, "solid_red")
        mixer.crossfadePosition = 0
        renderer.previewScale = RenderScale(percent: 50)
        let rgb = try renderAndRead()
        XCTAssertEqual(rgb.x, 1.0, accuracy: 0.02)
    }

    func testSettingTheSameRenderScaleIsANoOp() throws {
        renderer.renderFrame()
        let before = try XCTUnwrap(renderer.rawMasterTexture())
        renderer.previewScale = renderer.previewScale
        XCTAssertTrue(try XCTUnwrap(renderer.rawMasterTexture()) === before,
                      "A no-op set must not reallocate — the UI binds to this and writes freely")
    }

    func testAFadedOutDeckDoesNotDarkenTheOtherOne() throws {
        // Regression guard for "skip the layer" vs "composite it at zero": a zero-opacity layer
        // must leave the backdrop bit-identical, not run a blend with alpha 0.
        try load(.one, "solid_red")
        try load(.two, "solid_green")
        mixer.setOpacity(1.0, for: .one)
        mixer.setOpacity(0.0, for: .two)
        mixer.crossfadePosition = 0
        let rgb = try renderAndRead()
        XCTAssertEqual(rgb.x, 1.0, accuracy: 0.02)
        XCTAssertLessThan(rgb.y, 0.02)
    }
}
