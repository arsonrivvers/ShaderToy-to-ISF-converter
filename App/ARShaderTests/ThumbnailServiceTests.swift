import XCTest
import Metal
import VVMetalKit
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

    func testAValidShaderProducesAnImage() async throws {
        let service = ThumbnailService(cacheDirectory: try temporaryCacheDirectory())
        let result = await service.thumbnail(for: try fixtureURL("solid_red"), priority: .batch)
        guard case .image = result else { return XCTFail("expected an image, got \(result)") }
    }

    /// The whole reason t is not 0: many shaders are black at t=0, and a black thumbnail is worse
    /// than no thumbnail. 2.0s is past nearly every fade-in and early enough that feedback shaders
    /// have not drifted into mush.
    func testTheSampleTimeIsTwoSeconds() {
        XCTAssertEqual(ThumbnailService.sampleTime, 2.0)
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
    }
}
