import XCTest
import Metal
@testable import TrueISFEditor

@MainActor
final class TemplatePackTests: XCTestCase {
    func testTemplatesFolderIsBundled() {
        XCTAssertNotNil(TemplateCatalog.bundledTemplatesDir, "templates folder missing from bundle")
    }

    func testCatalogListsOnlyFSFiles() {
        // README.md rides along in the folder reference; the catalog must ignore it.
        XCTAssertTrue(TemplateCatalog.all.allSatisfy { !$0.name.contains("README") })
    }

    func testEveryNSTemplateCarriesCredit() {
        for t in TemplateCatalog.all where t.name.hasPrefix("NS ") {
            XCTAssertTrue(t.sourceText.contains("Adapted from null_signal by VJ CYBERPATROLUNIT (MIT)"),
                          "\(t.name) is missing its CREDIT header")
        }
    }

    func testEveryTemplateCompilesAndRendersNonBlack() async throws {
        guard MTLCreateSystemDefaultDevice() != nil else { throw XCTSkip("No Metal device") }
        for t in TemplateCatalog.all {
            let controller = MetalPreviewController()
            controller.setPaused(true)
            controller.load(isf: t.sourceText)
            for _ in 0..<200 where !(controller.compileValid || controller.compileError != nil) {
                try await Task.sleep(nanoseconds: 50_000_000)
            }
            XCTAssertTrue(controller.compileValid,
                          "template \(t.name) failed to compile: \(controller.compileError ?? "?")")
            // The gate renders these frames SEQUENTIALLY on the SAME scene, so persistent
            // buffers accumulate across them — 4 frames pushes a PERSISTENT-buffer template
            // (NS Feedback Echo) past its FRAMEINDEX < 2 init and executes the accumulate
            // path, not just the first-frame passthrough. (Trail DEPTH is an eyeball check.)
            let verdict = controller.runPixelGate(times: [0.0, 0.4, 0.8, 1.2])
            XCTAssertFalse(verdict.isFail, "template \(t.name) rendered \(verdict.rawValue)")
        }
    }
}
