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

    /// Regression for ssjyWc: a "header macro" `#define Main …{ …` has an unbalanced `{`. The brace
    /// must NOT leak scope to the rest of the file, and the uniforms inside the directive body must
    /// still be rewritten (a #define is file-scope, not a function body).
    func test_headerMacroWithUnbalancedBrace_rewritesBodyAndDoesNotLeakScope() {
        let src = "#define Main void mainImage(out vec4 Q){ R = iResolution.xy; I = iFrame;\nfloat g = iTime;"
        let out = CommonUniformRewriter.rewrite(src)
        XCTAssertTrue(out.contains("R = vec3(RENDERSIZE, 1.0).xy"), "uniform in #define body must rewrite; got:\n\(out)")
        XCTAssertTrue(out.contains("I = FRAMEINDEX"))
        XCTAssertTrue(out.contains("float g = TIME;"), "unbalanced { in #define must not protect the next line")
    }

    /// Regression for mslGRX: a Common `#define Res iChannelResolution[0]` left `iChannelResolution`
    /// undeclared when `Res` expanded at pass scope. The file-scope #define must map the whole indexed
    /// access to vec3(RENDERSIZE, 1.0).
    func test_iChannelResolutionDefine_rewritten() {
        let r = CommonUniformRewriter.rewrite("#define Res iChannelResolution[0]\n")
        XCTAssertEqual(r, "#define Res vec3(RENDERSIZE, 1.0)\n")
    }

    /// C5 interim — a uniform used inside a function BODY with no parameter of that name declared
    /// anywhere in the file is NOT rewritten by the scope-aware pass and WILL be undeclared;
    /// detect it so the converter can warn loudly.
    func test_unrewrittenBodyUniforms_detected() {
        let src = "float n(vec2 p){ return sin(p.x + iTime); }"
        XCTAssertEqual(CommonUniformRewriter.unrewrittenBodyUniforms(src), ["iTime"])
    }

    /// C5 interim — a param-shadowed uniform is legitimate (the helper uses its parameter): no flag.
    func test_paramShadowedUniform_notFlaggedAsUnrewritten() {
        let src = "vec2 f(vec2 iResolution) {\n  return iResolution.xy * 2.0;\n}"
        XCTAssertTrue(CommonUniformRewriter.unrewrittenBodyUniforms(src).isEmpty)
    }

    /// C5 interim — file-scope uses are rewritten normally, so they must not be flagged.
    func test_fileScopeUniform_notFlaggedAsUnrewritten() {
        XCTAssertTrue(CommonUniformRewriter.unrewrittenBodyUniforms("#define res iResolution.xy\n").isEmpty)
    }

    /// C6 — a file-scope Common `#define M iMouse` must be rewritten (it previously survived as an
    /// undeclared identifier), while a helper that threads iMouse as a PARAMETER stays protected.
    func test_iMouseDefine_rewritten_parameterThreaded_protected() {
        let src = "#define M iMouse\nvoid f(vec4 iMouse){ vec2 p = iMouse.xy; }"
        let out = CommonUniformRewriter.rewrite(src)
        XCTAssertTrue(out.contains("#define M vec4(mouse * RENDERSIZE, mouse * RENDERSIZE)"),
                      "file-scope define must rewrite; got:\n\(out)")
        XCTAssertTrue(out.contains("void f(vec4 iMouse){ vec2 p = iMouse.xy; }"),
                      "param-threaded iMouse must stay protected; got:\n\(out)")
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
