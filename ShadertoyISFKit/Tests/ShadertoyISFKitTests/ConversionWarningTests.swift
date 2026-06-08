import XCTest
@testable import ShadertoyISFKit

final class ConversionWarningTests: XCTestCase {
    func test_equatable() {
        let a = ConversionWarning(severity: .warning, message: "x", context: "Buffer A")
        let b = ConversionWarning(severity: .warning, message: "x", context: "Buffer A")
        XCTAssertEqual(a, b)
    }
}
