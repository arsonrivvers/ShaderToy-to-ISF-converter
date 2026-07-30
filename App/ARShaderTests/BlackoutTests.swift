import XCTest
import Metal

@MainActor
final class BlackoutTests: XCTestCase {
    private var device: MTLDevice!
    private var queue: MTLCommandQueue!
    private var mixer: MixerState!
    private var renderer: InstrumentRenderer!

    override func setUpWithError() throws {
        device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        queue = try XCTUnwrap(device.makeCommandQueue())
        mixer = MixerState()
        renderer = InstrumentRenderer(device: device, queue: queue, mixer: mixer)
        let deck = renderer.deck(.one)
        let url = try XCTUnwrap(Bundle(for: Self.self)
            .url(forResource: "solid_red", withExtension: "fs", subdirectory: "Fixtures"))
        let done = expectation(description: "compile")
        deck.onCompileFinished = { done.fulfill() }
        deck.load(source: try String(contentsOf: url, encoding: .utf8), name: "solid_red.fs")
        wait(for: [done], timeout: 30)
        deck.onCompileFinished = nil
        mixer.crossfadePosition = 0
    }

    func testBlackoutWithdrawsTheProgramTexture() throws {
        renderer.renderFrame()
        XCTAssertNotNil(renderer.programTexture(), "Sanity: the instrument is producing output")

        mixer.toggleBlackoutLatch()
        renderer.renderFrame()
        XCTAssertNil(renderer.programTexture(),
                     "Blackout must withdraw the texture entirely — consumers render black on nil, "
                     + "so no pipeline can stand between the panic button and darkness")
    }

    func testBlackoutReleasesBackToTheSameImage() throws {
        mixer.toggleBlackoutLatch()
        renderer.renderFrame()
        XCTAssertNil(renderer.programTexture())

        mixer.toggleBlackoutLatch()
        renderer.renderFrame()
        let tex = try XCTUnwrap(renderer.programTexture())
        let readback = try XCTUnwrap(
            TextureReadback.managedCopy(of: tex, device: device, queue: queue))
        let rgb = try XCTUnwrap(TestPixels.meanRGB(of: readback))
        XCTAssertEqual(rgb.x, 1.0, accuracy: 0.02)
    }

    func testTheMasterMonitorGoesDarkWithTheRoom() throws {
        // A master monitor showing video while the room is dark is the same class of false readout
        // as a recorder that counts frames it never wrote. It taps POST-blackout.
        mixer.toggleBlackoutLatch()
        renderer.renderFrame()
        XCTAssertNil(renderer.monitorTexture(.master))
    }

    func testDeckMonitorsKeepShowingTheirDecksDuringBlackout() throws {
        // Deck monitors are cue monitors: the operator must be able to line up the next shader
        // while the room is dark. They are not program output and do not tap post-blackout.
        mixer.toggleBlackoutLatch()
        renderer.renderFrame()
        XCTAssertNotNil(renderer.monitorTexture(.deck(.one)))
    }

    func testBlackoutStillHoldsWhileTheDecksKeepRendering() throws {
        mixer.toggleBlackoutLatch()
        for _ in 0..<10 {
            renderer.renderFrame()
            XCTAssertNil(renderer.programTexture())
        }
    }

    func testAMomentaryHoldBlacksOutForExactlyTheHold() throws {
        mixer.beginBlackoutHold()
        renderer.renderFrame()
        XCTAssertNil(renderer.programTexture())
        mixer.endBlackoutHold()
        renderer.renderFrame()
        XCTAssertNotNil(renderer.programTexture())
    }

    func testAnInstrumentWithNoCompositorOutputsBlackRatherThanGarbage() throws {
        // The failure floor: if the compositor pipeline could not be built, the instrument must
        // still start and must show black — never a stale or uninitialised frame (spec §8).
        let broken = InstrumentRenderer(device: device, queue: queue, mixer: MixerState(),
                                        compositorOverride: .failed)
        let deck = broken.deck(.one)
        let url = try XCTUnwrap(Bundle(for: Self.self)
            .url(forResource: "solid_red", withExtension: "fs", subdirectory: "Fixtures"))
        let done = expectation(description: "compile on broken renderer")
        deck.onCompileFinished = { done.fulfill() }
        deck.load(source: try String(contentsOf: url, encoding: .utf8), name: "solid_red.fs")
        wait(for: [done], timeout: 30)

        broken.renderFrame()
        let tex = try XCTUnwrap(broken.programTexture(),
                                "Still produces a master; it is simply black")
        let readback = try XCTUnwrap(
            TextureReadback.managedCopy(of: tex, device: device, queue: queue))
        let stats = try XCTUnwrap(FramePixelStats.analyze(texture: readback))
        XCTAssertLessThan(stats.maxLuma, PixelGate.blackLumaFloor,
                          "A deck IS loaded and rendering — with no compositor its pixels must "
                          + "never reach the master")
        XCTAssertEqual(stats.nanCount, 0)
    }
}
