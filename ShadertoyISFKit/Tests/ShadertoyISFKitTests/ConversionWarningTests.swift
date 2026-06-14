import XCTest
@testable import ShadertoyISFKit

final class ConversionWarningTests: XCTestCase {
    func test_equatable() {
        let a = ConversionWarning(severity: .warning, message: "x", context: "Buffer A")
        let b = ConversionWarning(severity: .warning, message: "x", context: "Buffer A")
        XCTAssertEqual(a, b)
    }

    func test_reportSummary_clean() {
        XCTAssertEqual(ConversionReportSummary.line(source: "Shader", warnings: []),
                       "Shader converted cleanly.")
    }

    func test_reportSummary_countsBySeverityAndPluralizes() {
        let w = [
            ConversionWarning(severity: .error, message: "e1"),
            ConversionWarning(severity: .warning, message: "w1"),
            ConversionWarning(severity: .warning, message: "w2"),
            ConversionWarning(severity: .info, message: "i1"),
        ]
        XCTAssertEqual(ConversionReportSummary.line(source: "Shader", warnings: w),
                       "Shader converted with 1 error, 2 warnings, 1 note. Review below.")
    }
}
