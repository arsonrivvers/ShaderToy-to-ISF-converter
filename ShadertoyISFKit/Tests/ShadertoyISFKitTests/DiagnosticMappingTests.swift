import XCTest
@testable import ShadertoyISFKit

final class DiagnosticMappingTests: XCTestCase {
    func testConversionWarningMapsToDiagnostic() {
        let w = ConversionWarning(severity: .warning, message: "deprecated texture2D", context: "Image pass")
        let d = Diagnostic(w)
        XCTAssertEqual(d.severity, .warning)
        XCTAssertEqual(d.message, "deprecated texture2D (Image pass)")
        XCTAssertEqual(d.source, .converter)
        XCTAssertNil(d.line)
    }
    func testCompilerDiagnosticFactory() {
        let d = Diagnostic.compiler(message: "ERROR: 0:12: 'x' undeclared", line: 12)
        XCTAssertEqual(d.severity, .error)
        XCTAssertEqual(d.line, 12)
        XCTAssertEqual(d.source, .compiler)
    }
}
