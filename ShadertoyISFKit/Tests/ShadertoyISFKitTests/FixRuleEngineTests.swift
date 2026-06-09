import XCTest
@testable import ShadertoyISFKit

final class FixRuleEngineTests: XCTestCase {
    func testTexture2DSuggestsImgPixelWithEdit() throws {
        let d = Diagnostic.compiler(message: "ERROR: 11: 'texture2D' : no matching overloaded function found", line: 11)
        let line = "    vec4 c = texture2D(inputImage, uv);"
        let s = FixRuleEngine.suggestions(for: d, sourceLine: line)
        XCTAssertEqual(s.count, 1)
        XCTAssertTrue(s[0].title.contains("IMG_PIXEL"))
        let edit = try XCTUnwrap(s[0].edit)
        XCTAssertEqual(edit.fromLine, 11)
        XCTAssertTrue(edit.replacement.contains("IMG_PIXEL(inputImage, uv)"))
        XCTAssertFalse(edit.replacement.contains("texture2D"))
    }
    func testNoMatchReturnsEmpty() {
        let d = Diagnostic.compiler(message: "ERROR: 3: syntax error near '}'", line: 3)
        XCTAssertTrue(FixRuleEngine.suggestions(for: d, sourceLine: "}").isEmpty)
    }
    func testReservedWordSuggestsRename() throws {
        let d = Diagnostic.compiler(message: "ERROR: 340: 'active' : Reserved word.", line: 340)
        let s = FixRuleEngine.suggestions(for: d, sourceLine: "    float active = 1.0;")
        XCTAssertEqual(s.count, 1)
        XCTAssertTrue(s[0].title.lowercased().contains("rename"))
        XCTAssertEqual(try XCTUnwrap(s[0].edit).replacement.contains("active_"), true)
    }
    func testTanhSuggestsPolyfill() throws {
        let d = Diagnostic.compiler(message: "ERROR: 8: 'tanh' : no matching overloaded function found", line: 8)
        let s = FixRuleEngine.suggestions(for: d, sourceLine: "    float t = tanh(x);")
        XCTAssertEqual(s.count, 1)
        XCTAssertTrue(s[0].explanation.lowercased().contains("polyfill"))
        XCTAssertNotNil(s[0].edit)
    }
    func testUndeclaredIsAdvisoryOnly() {
        let d = Diagnostic.compiler(message: "ERROR: 31: 'uvAspect' : undeclared identifier", line: 31)
        let s = FixRuleEngine.suggestions(for: d, sourceLine: "    vec2 uv = p / uvAspect;")
        XCTAssertEqual(s.count, 1)
        XCTAssertNil(s[0].edit)
    }
}
