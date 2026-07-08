import XCTest
@testable import ShadertoyISFKit

/// C1 — comment-aware call parsing. A `,` or unbalanced paren inside a comment must not be counted
/// as argument structure, and a call appearing inside a comment must not be rewritten. Before the
/// fix, these mis-parses silently left real calls un-rewritten (→ undeclared-identifier black screen)
/// or corrupted the source by closing the arg list early.
final class GLSLCallParserTests: XCTestCase {
    /// transform that makes the parse result visible: <arg0|arg1|…>
    private func wrap(_ code: String, fn: String, arity: Int) -> String {
        GLSLCallParser.replaceCall(in: code, fn: fn, arity: arity) {
            "<" + $0.joined(separator: "|") + ">"
        }
    }

    func test_comma_insideBlockComment_doesNotSplitArgs() {
        // Real arity is 2; the comma in the comment must be ignored.
        let out = wrap("f(a /*, ignore */, b)", fn: "f", arity: 2)
        XCTAssertEqual(out, "<a /*, ignore */| b>")
    }

    func test_unbalancedParen_insideBlockComment_doesNotCloseEarly() {
        // The `)` in `:)` must not terminate the arg list before the real close paren.
        let out = wrap("f(a /* :) */)", fn: "f", arity: 1)
        XCTAssertEqual(out, "<a /* :) */>")
    }

    func test_comma_insideLineComment_doesNotSplitArgs() {
        let out = wrap("f(a, // b, c\n d)", fn: "f", arity: 2)
        XCTAssertEqual(out, "<a| // b, c\n d>")
    }

    func test_callInsideComment_isNotRewritten() {
        let out = wrap("// f(x)\nf(y)", fn: "f", arity: 1)
        XCTAssertEqual(out, "// f(x)\n<y>")
    }

    func test_callInsideBlockComment_isNotRewritten() {
        let out = wrap("/* f(x) */ f(y)", fn: "f", arity: 1)
        XCTAssertEqual(out, "/* f(x) */ <y>")
    }

    /// End-to-end through SamplerRewriter: a texture() call with a comment in its args must still
    /// be converted, not left as raw `texture(...)`.
    func test_samplerRewriter_textureWithCommentInArgs_isConverted() {
        let bindings: [Int: ChannelBinding.Binding] = [0: .init(glslName: "bufA", kind: .buffer)]
        let r = SamplerRewriter.rewrite("texture(iChannel0 /* the src */, uv)", bindings: bindings)
        XCTAssertFalse(r.code.contains("texture("), r.code)
        XCTAssertTrue(r.code.contains("IMG_NORM_PIXEL(bufA"), r.code)
    }

    /// M21 — valid GLSL permits whitespace between the function name and its paren
    /// (`texture (iChannel0, uv)`); requiring adjacency let the call fall through to the
    /// bare-identifier rename with host-dependent results.
    func test_spaceBetweenIdentifierAndParen_isRewritten() {
        let out = wrap("f (a, b)", fn: "f", arity: 2)
        XCTAssertEqual(out, "<a| b>")
    }

    /// C7 — a call nested inside another matched call's ARGS must also be rewritten. Skipping past
    /// the outer match left the inner call raw (texture-inside-texture is the standard
    /// distortion/feedback idiom).
    func test_nestedSameFnCall_insideArgs_isRewritten() {
        let out = wrap("f(a, f(b, c))", fn: "f", arity: 2)
        XCTAssertEqual(out, "<a| <b| c>>")
    }

    /// C7 end-to-end through SamplerRewriter: `texture(iCh0, uv + texture(iCh1, uv).xy)` — both
    /// the outer and the inner call must become IMG_NORM_PIXEL; no raw `texture(` may survive.
    func test_samplerRewriter_nestedTextureCalls_bothConverted() {
        let bindings: [Int: ChannelBinding.Binding] = [
            0: .init(glslName: "bufA", kind: .buffer),
            1: .init(glslName: "bufB", kind: .buffer),
        ]
        let r = SamplerRewriter.rewrite("texture(iChannel0, uv + texture(iChannel1, uv).xy)",
                                        bindings: bindings)
        XCTAssertFalse(r.code.contains("texture("), r.code)
        XCTAssertTrue(r.code.contains("IMG_NORM_PIXEL(bufA"), r.code)
        XCTAssertTrue(r.code.contains("IMG_NORM_PIXEL(bufB"), r.code)
    }
}
