import XCTest
import Metal
import ISFMSLKit

@MainActor
final class DeckTests: XCTestCase {
    private var device: MTLDevice!
    private var queue: MTLCommandQueue!

    override func setUpWithError() throws {
        device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        queue = try XCTUnwrap(device.makeCommandQueue())
    }

    private func fixture(_ name: String) throws -> String {
        let url = try XCTUnwrap(Bundle(for: Self.self)
            .url(forResource: name, withExtension: "fs", subdirectory: "Fixtures"))
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// The output resolution a deck normally renders at.
    private var full: MTLSize { RenderSize.default.size }

    private func makeDeck() -> Deck {
        Deck(id: .one, device: device, queue: queue, clock: RenderClock())
    }

    /// Load synchronously for tests: compile happens off-main, so wait for the callback.
    private func loadAndWait(_ deck: Deck, source: String, name: String) {
        let done = expectation(description: "compile \(name)")
        deck.onCompileFinished = { done.fulfill() }
        deck.load(source: source, name: name)
        wait(for: [done], timeout: 30)
        deck.onCompileFinished = nil
    }

    private func meanRGB(of texture: MTLTexture) throws -> SIMD3<Double> {
        let readback = try XCTUnwrap(
            TextureReadback.managedCopy(of: texture, device: device, queue: queue))
        return try XCTUnwrap(TestPixels.meanRGB(of: readback))
    }

    func testEmptyDeckRendersNothing() throws {
        let deck = makeDeck()
        let cb = try XCTUnwrap(queue.makeCommandBuffer())
        XCTAssertNil(deck.render(in: cb, renderSize: full, ownedSize: full), "A deck with no shader must return nil, not a stale texture")
        cb.commit()
    }

    func testLoadedDeckRendersItsShader() throws {
        let deck = makeDeck()
        loadAndWait(deck, source: try fixture("solid_red"), name: "solid_red.fs")
        XCTAssertNil(deck.compileError)
        XCTAssertEqual(deck.shaderName, "solid_red.fs")

        let cb = try XCTUnwrap(queue.makeCommandBuffer())
        let tex = try XCTUnwrap(deck.render(in: cb, renderSize: full, ownedSize: full))
        cb.commit()
        cb.waitUntilCompleted()

        let rgb = try meanRGB(of: tex)
        XCTAssertEqual(rgb.x, 1.0, accuracy: 0.02)
        XCTAssertEqual(rgb.y, 0.0, accuracy: 0.02)
        XCTAssertEqual(rgb.z, 0.0, accuracy: 0.02)
    }

    func testFailedCompileLeavesTheRunningShaderUntouched() throws {
        let deck = makeDeck()
        loadAndWait(deck, source: try fixture("solid_red"), name: "solid_red.fs")
        loadAndWait(deck, source: try fixture("broken"), name: "broken.fs")

        XCTAssertNotNil(deck.compileError, "The failure must be reported")
        XCTAssertEqual(deck.shaderName, "solid_red.fs",
                       "A failed compile must not claim to have loaded")

        let cb = try XCTUnwrap(queue.makeCommandBuffer())
        let tex = try XCTUnwrap(deck.render(in: cb, renderSize: full, ownedSize: full), "The previous shader must still be rendering")
        cb.commit()
        cb.waitUntilCompleted()
        let rgb = try meanRGB(of: tex)
        XCTAssertEqual(rgb.x, 1.0, accuracy: 0.02, "Still red — the failed compile never swapped in")
    }

    func testDeckOutputTextureIsReusedAcrossFrames() throws {
        let deck = makeDeck()
        loadAndWait(deck, source: try fixture("solid_red"), name: "solid_red.fs")
        let cb1 = try XCTUnwrap(queue.makeCommandBuffer())
        let first = try XCTUnwrap(deck.render(in: cb1, renderSize: full, ownedSize: full))
        cb1.commit(); cb1.waitUntilCompleted()
        let cb2 = try XCTUnwrap(queue.makeCommandBuffer())
        let second = try XCTUnwrap(deck.render(in: cb2, renderSize: full, ownedSize: full))
        cb2.commit(); cb2.waitUntilCompleted()
        XCTAssertTrue(first === second,
                      "The deck owns ONE output texture — a per-frame allocation would also mean "
                      + "monitors could sample a pool-recycled texture")
    }

    func testRenderOffscreenDoesNotCommitTheCallersCommandBuffer() throws {
        let core = MetalRenderCore(device: device, renderQueue: queue)
        let result = ISFSceneLoader.load(source: try fixture("solid_red"), device: device)
        core.setScene(result.scene, imageInputNames: [])
        let cb = try XCTUnwrap(queue.makeCommandBuffer())
        _ = core.renderOffscreen(size: MTLSize(width: 64, height: 36, depth: 1), in: cb)
        XCTAssertEqual(cb.status, .notEnqueued,
                       "renderOffscreen must leave the command buffer to its caller — the whole "
                       + "frame is one buffer")
        cb.commit()
    }

    // MARK: resolution

    func testTheOwnedTextureTracksTheOWNEDSizeNotTheRenderSize() throws {
        // A cued deck rasterises small and is upscaled into a full-size owned texture, so starting
        // a fade costs no reallocation and no hitch. The owned texture must therefore follow
        // ownedSize, never renderSize.
        let deck = makeDeck()
        loadAndWait(deck, source: try fixture("solid_red"), name: "solid_red.fs")
        let cue = RenderSize(width: 960, height: 540).size
        let cb = try XCTUnwrap(queue.makeCommandBuffer())
        let tex = try XCTUnwrap(deck.render(in: cb, renderSize: cue, ownedSize: full))
        cb.commit(); cb.waitUntilCompleted()
        XCTAssertEqual(tex.width, full.width)
        XCTAssertEqual(tex.height, full.height)
    }

    func testCueRenderingDoesNotReallocateWhenTheDeckGoesLive() throws {
        // The whole point of a fixed owned size: the fade must not allocate.
        let deck = makeDeck()
        loadAndWait(deck, source: try fixture("solid_red"), name: "solid_red.fs")
        let cue = RenderSize(width: 960, height: 540).size

        let cb1 = try XCTUnwrap(queue.makeCommandBuffer())
        let cued = try XCTUnwrap(deck.render(in: cb1, renderSize: cue, ownedSize: full))
        cb1.commit(); cb1.waitUntilCompleted()

        let cb2 = try XCTUnwrap(queue.makeCommandBuffer())
        let live = try XCTUnwrap(deck.render(in: cb2, renderSize: full, ownedSize: full))
        cb2.commit(); cb2.waitUntilCompleted()

        XCTAssertTrue(cued === live, "Going live must reuse the same texture, not allocate one")
    }

    func testChangingTheOutputResolutionDoesReallocate() throws {
        let deck = makeDeck()
        loadAndWait(deck, source: try fixture("solid_red"), name: "solid_red.fs")
        let cb1 = try XCTUnwrap(queue.makeCommandBuffer())
        let at1080 = try XCTUnwrap(deck.render(in: cb1, renderSize: full, ownedSize: full))
        cb1.commit(); cb1.waitUntilCompleted()

        let smaller = RenderSize(width: 1280, height: 720).size
        let cb2 = try XCTUnwrap(queue.makeCommandBuffer())
        let at720 = try XCTUnwrap(deck.render(in: cb2, renderSize: smaller, ownedSize: smaller))
        cb2.commit(); cb2.waitUntilCompleted()

        XCTAssertFalse(at1080 === at720)
        XCTAssertEqual(at720.width, 1280)
    }

    func testACuedDeckStillProducesAWatchableImage() throws {
        // Cueing saves GPU by rasterising small — it must NOT mean the cue monitor goes blank or
        // black, which is the whole reason the operator is cueing.
        let deck = makeDeck()
        loadAndWait(deck, source: try fixture("solid_red"), name: "solid_red.fs")
        let cb = try XCTUnwrap(queue.makeCommandBuffer())
        let tex = try XCTUnwrap(deck.render(in: cb, renderSize: RenderSize(width: 640, height: 360).size,
                                            ownedSize: full))
        cb.commit(); cb.waitUntilCompleted()
        let rgb = try meanRGB(of: tex)
        XCTAssertEqual(rgb.x, 1.0, accuracy: 0.02)
    }

    func testUnloadStopsTheDeckContributing() throws {
        let deck = makeDeck()
        loadAndWait(deck, source: try fixture("solid_red"), name: "solid_red.fs")
        deck.unload()
        XCTAssertNil(deck.shaderName)
        let cb = try XCTUnwrap(queue.makeCommandBuffer())
        XCTAssertNil(deck.render(in: cb, renderSize: full, ownedSize: full))
        cb.commit()
    }
}
