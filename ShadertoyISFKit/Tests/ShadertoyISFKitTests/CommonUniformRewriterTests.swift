import XCTest
@testable import ShadertoyISFKit

final class CommonUniformRewriterTests: XCTestCase {
    /// File-scope #define referencing a Shadertoy uniform IS rewritten (this is the N323DD blocker:
    /// `#define res iResolution.xy` left `iResolution` undeclared when `res` expanded at pass scope).
    func test_fileScopeDefine_rewritten() {
        let r = CommonUniformRewriter.rewrite("#define res iResolution.xy\n")
        XCTAssertEqual(r, "#define res vec3(RENDERSIZE, 1.0).xy\n")
    }

    /// A uniform name used as a function PARAMETER must NOT be rewritten — substituting the
    /// expression `vec3(RENDERSIZE, 1.0)` into a parameter declaration is a syntax error.
    func test_parameterDeclaration_protected() {
        let src = "bool inside(vec2 p, vec2 iResolution) { return p.x > 0.0; }"
        XCTAssertEqual(CommonUniformRewriter.rewrite(src), src)
    }

    /// A uniform referenced inside a function body must NOT be rewritten either (it's the param in
    /// scope for these parameterized helpers; rewriting would diverge from the declaration).
    func test_functionBodyUniform_protected() {
        let src = "vec2 f(vec2 iResolution) {\n  return iResolution.xy * 2.0;\n}"
        XCTAssertEqual(CommonUniformRewriter.rewrite(src), src)
    }

    /// A genuine file-scope global declaration is rewritten.
    func test_fileScopeGlobal_rewritten() {
        let r = CommonUniformRewriter.rewrite("const float startTime = iTime;")
        XCTAssertEqual(r, "const float startTime = TIME;")
    }

    /// Regression: an unbalanced delimiter inside a COMMENT (e.g. a smiley `:(`) must not make the
    /// rest of the file look "protected". This is the actual N323DD failure mode.
    func test_unbalancedParenInComment_doesNotProtectRest() {
        let src = """
        // measly 2x speedup :(
        #define res iResolution.xy
        """
        let expected = """
        // measly 2x speedup :(
        #define res vec3(RENDERSIZE, 1.0).xy
        """
        XCTAssertEqual(CommonUniformRewriter.rewrite(src), expected)
    }

    /// A block comment with an unbalanced brace likewise must not leak scope.
    func test_unbalancedBraceInBlockComment_doesNotProtectRest() {
        let src = "/* note { unbalanced */\nfloat t = iTime;"
        let expected = "/* note { unbalanced */\nfloat t = TIME;"
        XCTAssertEqual(CommonUniformRewriter.rewrite(src), expected)
    }

    /// Mixed: file-scope #define rewritten, helper body left alone, in one pass.
    func test_mixed_defineRewritten_helperUntouched() {
        let src = """
        #define res iResolution.xy
        float k(vec2 iResolution){ return res.x; }
        """
        let expected = """
        #define res vec3(RENDERSIZE, 1.0).xy
        float k(vec2 iResolution){ return res.x; }
        """
        XCTAssertEqual(CommonUniformRewriter.rewrite(src), expected)
    }
}
