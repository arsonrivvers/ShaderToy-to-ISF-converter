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
    // #7: tolerate length drift — a URL-extracted ID is unambiguous by position, accept any reasonable length.
    func test_urlID_nonStandardLength() {
        XCTAssertEqual(ShadertoyURL.shaderID(from: "https://www.shadertoy.com/view/abcD1234"), "abcD1234")
        XCTAssertEqual(ShadertoyURL.shaderID(from: "https://www.shadertoy.com/view/Xy9"), "Xy9")
    }
    func test_bareID_lengthWindow() {
        XCTAssertEqual(ShadertoyURL.shaderID(from: "abc12"), "abc12")           // 5 ok
        XCTAssertEqual(ShadertoyURL.shaderID(from: "abcd123456"), "abcd123456") // 10 ok
        XCTAssertNil(ShadertoyURL.shaderID(from: "abcd"))                       // 4 too short for a bare guess
        XCTAssertNil(ShadertoyURL.shaderID(from: "abcdefghijk1"))               // 12 too long for a bare guess
    }
}
