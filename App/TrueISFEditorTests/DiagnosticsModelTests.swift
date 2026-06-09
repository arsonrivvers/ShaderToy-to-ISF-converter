import XCTest
import ShadertoyISFKit

@MainActor
final class DiagnosticsModelTests: XCTestCase {
    func testMergesAndOrders() {
        let m = DiagnosticsModel()
        m.update(converterWarnings: [ConversionWarning(severity: .warning, message: "w", context: "")],
                 compileError: "ERROR: 0:5: bad", compileErrorLine: 5)
        XCTAssertEqual(m.diagnostics.count, 2)
        XCTAssertEqual(m.diagnostics.first?.source, .compiler)   // errors first
        XCTAssertEqual(m.diagnostics.first?.line, 5)
    }
    func testGutterProjection() {
        let m = DiagnosticsModel()
        m.update(converterWarnings: [], compileError: "boom", compileErrorLine: 7)
        XCTAssertEqual(m.editorDiagnostics, [EditorDiagnostic(line: 7, message: "boom", severity: "error")])
    }
    func testNoCompileErrorWhenValid() {
        let m = DiagnosticsModel()
        m.update(converterWarnings: [], compileError: nil, compileErrorLine: nil)
        XCTAssertTrue(m.diagnostics.isEmpty)
        XCTAssertTrue(m.editorDiagnostics.isEmpty)
    }
}
