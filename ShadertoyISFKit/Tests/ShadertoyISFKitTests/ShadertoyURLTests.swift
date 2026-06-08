import XCTest
@testable import ShadertoyISFKit

final class ShadertoyURLTests: XCTestCase {
    func test_fullViewURL() {
        XCTAssertEqual(ShadertoyURL.shaderID(from: "https://www.shadertoy.com/view/ Ms2SD1".replacingOccurrences(of: " ", with: "")), "Ms2SD1")
    }
    func test_noWWW_trailingSlash() {
        XCTAssertEqual(ShadertoyURL.shaderID(from: "http://shadertoy.com/view/XdfGDS/"), "XdfGDS")
    }
    func test_embedURL_withQuery() {
        XCTAssertEqual(ShadertoyURL.shaderID(from: "https://www.shadertoy.com/embed/wlcGzn?gui=true&t=10"), "wlcGzn")
    }
    func test_bareID() {
        XCTAssertEqual(ShadertoyURL.shaderID(from: "4ttSWf"), "4ttSWf")
    }
    func test_invalid_returnsNil() {
        XCTAssertNil(ShadertoyURL.shaderID(from: "https://example.com/foo"))
        XCTAssertNil(ShadertoyURL.shaderID(from: "not a url"))
        XCTAssertNil(ShadertoyURL.shaderID(from: ""))
    }
}
