import XCTest
import Metal
import VVMetalKit

@MainActor
final class InstrumentRendererTests: XCTestCase {
    private func makeRenderer() throws -> (InstrumentRenderer, MTLDevice, MTLCommandQueue) {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let queue = try XCTUnwrap(device.makeCommandQueue())
        return (InstrumentRenderer(device: device, queue: queue), device, queue)
    }

    func testMasterIsFixedAt1920x1080() throws {
        let (renderer, _, _) = try makeRenderer()
        renderer.renderFrame()
        let tex = try XCTUnwrap(renderer.programTexture())
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

    func testSteadyStateAllocatesNoNewTextures() throws {
        let (renderer, _, _) = try makeRenderer()
        renderer.renderFrame()
        let first = try XCTUnwrap(renderer.programTexture())
        for _ in 0..<30 { renderer.renderFrame() }
        let last = try XCTUnwrap(renderer.programTexture())
        XCTAssertTrue(first === last,
                      "Master textures are pooled and reused; a new object per frame means the "
                      + "steady-state frame is allocating")
    }
}
