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
}
