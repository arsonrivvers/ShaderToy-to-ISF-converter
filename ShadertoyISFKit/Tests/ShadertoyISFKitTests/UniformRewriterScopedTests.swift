import XCTest
@testable import ShadertoyISFKit

/// Scope-aware uniform rewriting (C5/M20) — successor to the CommonUniformRewriter tests. The
/// scope model is per-FUNCTION now: a uniform name is protected inside a function only when that
/// function's own parameter list declares it; everything else (file scope, directive bodies,
/// unshadowed function bodies) rewrites.
final class UniformRewriterScopedTests: XCTestCase {
    // MARK: - ported contract (same expectations as the walkRuns-era tests)

    /// File-scope #define referencing a Shadertoy uniform IS rewritten (the N323DD blocker).
    func test_fileScopeDefine_rewritten() {
        let r = UniformRewriter.rewriteScoped("#define res iResolution.xy\n")
        XCTAssertEqual(r, "#define res vec3(RENDERSIZE, 1.0).xy\n")
    }

    /// A uniform name used as a function PARAMETER must NOT be rewritten.
    func test_parameterDeclaration_protected() {
        let src = "bool inside(vec2 p, vec2 iResolution) { return p.x > 0.0; }"
        XCTAssertEqual(UniformRewriter.rewriteScoped(src), src)
    }

    /// A uniform referenced inside a body whose function declares it as a param stays protected.
    func test_functionBodyUniform_paramShadowed_protected() {
        let src = "vec2 f(vec2 iResolution) {\n  return iResolution.xy * 2.0;\n}"
        XCTAssertEqual(UniformRewriter.rewriteScoped(src), src)
    }

    func test_fileScopeGlobal_rewritten() {
        let r = UniformRewriter.rewriteScoped("const float startTime = iTime;")
        XCTAssertEqual(r, "const float startTime = TIME;")
    }

    /// An unbalanced delimiter inside a COMMENT must not protect the rest of the file.
    func test_unbalancedParenInComment_doesNotProtectRest() {
        let src = """
        // measly 2x speedup :(
        #define res iResolution.xy
        """
        let expected = """
        // measly 2x speedup :(
        #define res vec3(RENDERSIZE, 1.0).xy
        """
        XCTAssertEqual(UniformRewriter.rewriteScoped(src), expected)
    }

    func test_unbalancedBraceInBlockComment_doesNotProtectRest() {
        let src = "/* note { unbalanced */\nfloat t = iTime;"
        let expected = "/* note { unbalanced */\nfloat t = TIME;"
        XCTAssertEqual(UniformRewriter.rewriteScoped(src), expected)
    }

    /// ssjyWc header-macro: uniforms inside a #define body rewrite; its unbalanced `{` leaks nothing.
    func test_headerMacroWithUnbalancedBrace_rewritesBodyAndDoesNotLeakScope() {
        let src = "#define Main void mainImage(out vec4 Q){ R = iResolution.xy; I = iFrame;\nfloat g = iTime;"
        let out = UniformRewriter.rewriteScoped(src)
        XCTAssertTrue(out.contains("R = vec3(RENDERSIZE, 1.0).xy"), "uniform in #define body must rewrite; got:\n\(out)")
        XCTAssertTrue(out.contains("I = FRAMEINDEX"))
        XCTAssertTrue(out.contains("float g = TIME;"), "unbalanced { in #define must not protect the next line")
    }

    /// mslGRX: file-scope `#define Res iChannelResolution[0]` maps the whole indexed access.
    func test_iChannelResolutionDefine_rewritten() {
        let r = UniformRewriter.rewriteScoped("#define Res iChannelResolution[0]\n")
        XCTAssertEqual(r, "#define Res vec3(RENDERSIZE, 1.0)\n")
    }

    /// C6: file-scope `#define M iMouse` rewrites; a param-threaded helper stays protected.
    func test_iMouseDefine_rewritten_parameterThreaded_protected() {
        let src = "#define M iMouse\nvoid f(vec4 iMouse){ vec2 p = iMouse.xy; }"
        let out = UniformRewriter.rewriteScoped(src)
        XCTAssertTrue(out.contains("#define M vec4(mouse * RENDERSIZE, mouse * RENDERSIZE)"),
                      "file-scope define must rewrite; got:\n\(out)")
        XCTAssertTrue(out.contains("void f(vec4 iMouse){ vec2 p = iMouse.xy; }"),
                      "param-threaded iMouse must stay protected; got:\n\(out)")
    }

    func test_mixed_defineRewritten_helperUntouched() {
        let src = """
        #define res iResolution.xy
        float k(vec2 iResolution){ return res.x; }
        """
        let expected = """
        #define res vec3(RENDERSIZE, 1.0).xy
        float k(vec2 iResolution){ return res.x; }
        """
        XCTAssertEqual(UniformRewriter.rewriteScoped(src), expected)
    }

    // MARK: - C5: the new behavior

    /// C5 — THE fix: an unshadowed uniform inside a helper body IS now rewritten.
    /// (Was the "interim warn" case: `float n(vec2 p){ … iTime … }` shipped raw → black import.)
    func test_unshadowedBodyUniform_isRewritten_C5() {
        XCTAssertEqual(UniformRewriter.rewriteScoped("float n(vec2 p){ return sin(p.x + iTime); }"),
                       "float n(vec2 p){ return sin(p.x + TIME); }")
    }

    /// Per-function scope: shadowed function protected, unshadowed sibling rewritten — one file.
    func test_mixedFunctions_shadowedProtected_unshadowedRewritten() {
        let src = """
        vec2 f(vec2 iResolution){ return iResolution.xy; }
        float g(vec2 p){ return p.x / iResolution.x; }
        """
        let out = UniformRewriter.rewriteScoped(src)
        XCTAssertTrue(out.contains("vec2 f(vec2 iResolution){ return iResolution.xy; }"), out)
        XCTAssertTrue(out.contains("p.x / vec3(RENDERSIZE, 1.0).x"), out)
    }

    /// Comment content is never rewritten (the Common-path sibling of N2).
    func test_commentContent_neverRewritten() {
        XCTAssertEqual(UniformRewriter.rewriteScoped("// uses iTime\nfloat t = iTime;"),
                       "// uses iTime\nfloat t = TIME;")
    }

    // MARK: - tripwire

    /// On correctly-rewritten output, nothing is unresolved.
    func test_unresolvedUniformUses_emptyAfterScopedRewrite() {
        let out = UniformRewriter.rewriteScoped("float n(vec2 p){ return sin(p.x + iTime); }")
        XCTAssertTrue(UniformRewriter.unresolvedUniformUses(out).isEmpty)
    }

    /// A bare (un-indexed) iChannelResolution survives the rewrite and IS flagged.
    func test_unresolvedUniformUses_flagsBareChannelResolution() {
        let out = UniformRewriter.rewriteScoped("vec3 r = iChannelResolution;")
        XCTAssertEqual(UniformRewriter.unresolvedUniformUses(out), ["iChannelResolution"])
    }

    /// Param-shadowed uses in the output are legitimate — not flagged.
    func test_unresolvedUniformUses_paramShadowedNotFlagged() {
        let out = UniformRewriter.rewriteScoped("vec2 f(vec2 iResolution){ return iResolution.xy; }")
        XCTAssertTrue(UniformRewriter.unresolvedUniformUses(out).isEmpty)
    }

    // MARK: - nested-edit safety (M44)

    /// A word-rule uniform INSIDE an indexed access's index (`iChannelResolution[iFrame % 2]`)
    /// must not queue a second, nested edit — the indexed replacement consumes the whole access.
    /// (Descending-location application of overlapping ranges corrupts the trailing character.)
    func test_wordRuleInsideIndexedAccess_noNestedEditCorruption() {
        let out = UniformRewriter.rewriteScoped("vec3 r = iChannelResolution[iFrame % 2];")
        XCTAssertEqual(out, "vec3 r = vec3(RENDERSIZE, 1.0);")
    }

    func test_iTimeInsideChannelTimeIndex_noNestedEditCorruption() {
        let out = UniformRewriter.rewriteScoped("float t = iChannelTime[int(iTime)] + 1.0;")
        XCTAssertEqual(out, "float t = TIME + 1.0;")
    }
}
