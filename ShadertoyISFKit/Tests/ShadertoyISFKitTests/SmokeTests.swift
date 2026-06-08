import XCTest
@testable import ShadertoyISFKit

final class SmokeTests: XCTestCase {
    func test_version_isSet() {
        XCTAssertEqual(ShadertoyISFKit.version, "0.1.0")
    }
}
