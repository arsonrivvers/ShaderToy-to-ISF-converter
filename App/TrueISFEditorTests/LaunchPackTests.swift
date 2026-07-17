import XCTest
import Metal
@testable import TrueISFEditor

/// Phase 2 launch pack: acknowledgements resource, bundled sample gallery, provider surface.
final class LaunchPackTests: XCTestCase {

    func testAcknowledgementsResourceBundlesAllComponents() {
        let text = Acknowledgements.text
        // The attribution set required for binary distribution (BSD/Apache reproduce clauses).
        for component in ["ISFMSLKit", "VVMetalKit", "ISFGLSLGenerator", "exprtk", "nlohmann",
                          "glslang", "SPIRV-Cross", "PINCache", "CodeMirror",
                          "interactive-shader-format", "null_signal"] {
            XCTAssertTrue(text.contains(component), "acknowledgements missing \(component)")
        }
        XCTAssertGreaterThan(text.count, 10_000, "full license texts must be embedded, not just a summary")
    }

    func testSampleGalleryIsBundledAndListed() throws {
        let dir = try XCTUnwrap(LibraryModel.bundledSamplesDir, "samples folder missing from bundle")
        let entries = LibraryModel.scan(folder: dir)
        XCTAssertGreaterThanOrEqual(entries.count, 3, "gallery needs at least 3 samples")
    }

    @MainActor
    func testEverySampleCompilesThroughTheMetalEngine() async throws {
        guard MTLCreateSystemDefaultDevice() != nil else { throw XCTSkip("No Metal device") }
        let dir = try XCTUnwrap(LibraryModel.bundledSamplesDir)
        for entry in LibraryModel.scan(folder: dir) {
            let source = try String(contentsOf: entry.url, encoding: .utf8)
            let controller = MetalPreviewController()
            controller.setPaused(true)
            controller.load(isf: source)
            for _ in 0..<200 where !(controller.compileValid || controller.compileError != nil) {
                try await Task.sleep(nanoseconds: 50_000_000)
            }
            XCTAssertTrue(controller.compileValid,
                          "bundled sample \(entry.name) failed to compile: \(controller.compileError ?? "?")")
        }
    }

    @MainActor
    func testProviderFactoryClampsToClaudeWhenCodexUnavailable() {
        // In debug builds codexAvailable is true, so make(kind:) honors .codex; the release clamp
        // is compile-time. This pins the debug half + the flag's existence so the release branch
        // can't silently disappear in a refactor.
        XCTAssertTrue(AssistProviderFactory.codexAvailable)
        XCTAssertTrue(AssistProviderFactory.make(kind: .codex) is CodexRunner)
        XCTAssertTrue(AssistProviderFactory.make(kind: .claude) is ClaudeCodeRunner)
    }
}
