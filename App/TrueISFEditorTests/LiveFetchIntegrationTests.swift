import XCTest
import ShadertoyISFKit

/// Hits the live Shadertoy site through WKWebView. Skipped unless RUN_LIVE=1 is set,
/// so routine `xcodebuild test` runs stay offline and deterministic.
final class LiveFetchIntegrationTests: XCTestCase {
    private var runLive: Bool { ProcessInfo.processInfo.environment["RUN_LIVE"] == "1" }

    @MainActor
    func test_liveFetch_singlePass_convertsToISF() async throws {
        try XCTSkipUnless(runLive, "set RUN_LIVE=1 to run live network test")
        let fetcher = WebKitShaderFetcher()
        let shader = try await fetcher.fetchShader(id: "Ms2SD1")   // Seascape, single pass
        XCTAssertEqual(shader.info.name, "Seascape")
        let (doc, _) = ISFConverter.convert(shader)
        XCTAssertTrue(doc.fileText.contains("RENDERSIZE"))
        XCTAssertTrue(doc.fileText.contains("void main()"))
        XCTAssertFalse(doc.fileText.contains("iResolution"))
    }

    @MainActor
    func test_liveFetch_multiPass_hasBufferPasses() async throws {
        try XCTSkipUnless(runLive, "set RUN_LIVE=1 to run live network test")
        let fetcher = WebKitShaderFetcher()
        let shader = try await fetcher.fetchShader(id: "MdXyzX")   // known multi-pass (verify/replace at run time)
        XCTAssertGreaterThan(shader.renderpass.count, 1)
        let (doc, _) = ISFConverter.convert(shader)
        XCTAssertTrue(doc.fileText.contains("\"PASSES\""))
        XCTAssertTrue(doc.fileText.contains("PERSISTENT"))
    }
}
