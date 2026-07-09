import XCTest
@testable import ShadertoyISFKit

/// M19 interim — a comment-blind detection scan invents inputs (`// TODO try iChannel2` produced a
/// stub image input). `GLSLComments.strip` blanks comment CONTENT (preserving offsets/newlines) so
/// detection scans see only real code. Detection-only; rewrites never consume its output.
final class GLSLCommentsTests: XCTestCase {
    func test_lineCommentContent_blanked() {
        XCTAssertEqual(GLSLComments.strip("a; // iChannel2\nb;"), "a; //          \nb;")
    }
    func test_blockCommentContent_blanked_offsetsPreserved() {
        let out = GLSLComments.strip("a;/* iMouse */b;")
        XCTAssertEqual(out.count, "a;/* iMouse */b;".count)
        XCTAssertFalse(out.contains("iMouse"))
        XCTAssertTrue(out.hasPrefix("a;/*"))
        XCTAssertTrue(out.hasSuffix("*/b;"))
    }
    func test_codeUntouched() {
        let src = "vec4 c = texture(iChannel0, uv);"
        XCTAssertEqual(GLSLComments.strip(src), src)
    }
    func test_multilineBlock_preservesNewlines() {
        let out = GLSLComments.strip("/* a\n b */x;")
        XCTAssertTrue(out.contains("\n"))
        XCTAssertTrue(out.hasSuffix("x;"))
    }
}
