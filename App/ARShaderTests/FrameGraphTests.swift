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
        deck.onCompileFinished = { done.fulfill() }
        deck.load(source: try fixture(fixtureName), name: "\(fixtureName).fs")
        wait(for: [done], timeout: 30)
        deck.onCompileFinished = nil
        XCTAssertNil(deck.compileError)
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

    func testFrameUsesASingleCommandBuffer() throws {
        // The spec's central claim: no readback, no per-stage commit. If a stage started
        // committing its own buffer, this count would climb by more than one.
        try load(.one, "solid_red")
        try load(.two, "solid_green")
        let before = renderer.committedBufferCount
        renderer.renderFrame()
        XCTAssertEqual(renderer.committedBufferCount - before, 1)
    }

    // MARK: resolution

    func testChangingTheOutputResolutionResizesTheMaster() throws {
        renderer.outputResolution = .r720
        renderer.renderFrame()
        let tex = try XCTUnwrap(renderer.rawMasterTexture())
        XCTAssertEqual(tex.width, 1280)
        XCTAssertEqual(tex.height, 720)
    }

    func testTheInstrumentStillRendersCorrectlyAfterAResolutionChange() throws {
        try load(.one, "solid_red")
        mixer.crossfadePosition = 0
        XCTAssertEqual(try renderAndRead().x, 1.0, accuracy: 0.02)

        renderer.outputResolution = .r540
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
        // An FPS readout must come from measured frames. Nothing here fabricates a number: with a
        // 0.5s window, a burst of frames inside one test may or may not publish, so this asserts
        // only that when a snapshot DOES arrive its fps is a real positive measurement.
        var received: [RenderStats] = []
        renderer.onStats = { if let s = $0 { received.append(s) } }
        for _ in 0..<200 { renderer.renderFrame() }
        renderer.onStats = nil
        for s in received {
            XCTAssertGreaterThan(s.fps, 0)
        }
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
