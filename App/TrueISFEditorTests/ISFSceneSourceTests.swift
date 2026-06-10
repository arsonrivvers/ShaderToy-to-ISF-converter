import XCTest
import Metal
import ShadertoyISFKit
@testable import TrueISFEditor

@MainActor
final class ISFSceneSourceTests: XCTestCase {
    func test_validPatternProducesTexture() throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let queue = try XCTUnwrap(device.makeCommandQueue())
        let smpte = TestPatternCatalog.default
        let src = try XCTUnwrap(
            ISFSceneSource(displayName: smpte.name, sourceText: smpte.sourceText, device: device, queue: queue))
        let cb = try XCTUnwrap(queue.makeCommandBuffer())
        let tex = src.texture(size: MTLSize(width: 64, height: 64, depth: 1), in: cb)
        cb.commit(); cb.waitUntilCompleted()
        XCTAssertNotNil(tex)
    }

    func test_garbageSourceFailsInit() throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let queue = try XCTUnwrap(device.makeCommandQueue())
        let bad = ISFSceneSource(displayName: "bad", sourceText: "not a shader", device: device, queue: queue)
        XCTAssertNil(bad)
    }
}
