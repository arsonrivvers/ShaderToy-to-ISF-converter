import XCTest
@testable import ShadertoyISFKit

final class GLSLLineContinuationTests: XCTestCase {
    /// Regression for 7323zz: a `\` line-continuation black-screens the shader because glslang
    /// (the ISFMSLKit transpiler) rejects it ("line continuation not supported"). Splice it.
    func test_splicesContinuationToSpace() {
        XCTAssertEqual(GLSLLineContinuation.splice("vec4 q = a;\\\nfloat l = b;"),
                       "vec4 q = a; float l = b;")
    }
    func test_splicesMacroContinuation() {
        XCTAssertEqual(GLSLLineContinuation.splice("#define M x\\\n+ 1"), "#define M x + 1")
    }
    func test_trailingWhitespaceBeforeNewline_spliced() {
        XCTAssertEqual(GLSLLineContinuation.splice("a\\  \nb"), "a b")
    }
    func test_crlf_spliced() {
        XCTAssertEqual(GLSLLineContinuation.splice("a\\\r\nb"), "a b")
    }
    func test_plainNewline_unchanged() {
        XCTAssertEqual(GLSLLineContinuation.splice("a;\nb;"), "a;\nb;")
    }
}
