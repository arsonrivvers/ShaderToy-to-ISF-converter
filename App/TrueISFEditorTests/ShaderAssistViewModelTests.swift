import XCTest
import ShadertoyISFKit

@MainActor
final class ShaderAssistViewModelTests: XCTestCase {
    func testEditMappingDerivesExpectedContains() {
        let src = "line one\n  vec4 c = texture2D(a, b);\nline three"
        let edit = AIEdit(fromLine: 2, toLine: 2, replacement: "  vec4 c = IMG_PIXEL(a, b);", rationale: "r")
        let te = ShaderAssistViewModel.textEdit(from: edit, source: src)
        XCTAssertEqual(te.fromLine, 2); XCTAssertEqual(te.toLine, 2)
        XCTAssertEqual(te.replacement, "  vec4 c = IMG_PIXEL(a, b);")
        XCTAssertNotNil(te.expectedContains)
        XCTAssertTrue("  vec4 c = texture2D(a, b);".contains(te.expectedContains!))
    }
}
