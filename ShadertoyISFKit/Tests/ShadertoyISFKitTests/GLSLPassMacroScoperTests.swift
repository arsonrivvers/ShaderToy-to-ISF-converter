import XCTest
@testable import ShadertoyISFKit

final class GLSLPassMacroScoperTests: XCTestCase {
    /// Regression for the FLOATCONSTANT class (4ldGDB/4XXGDl/ftGXzz/Ndc3zj): one pass defines an
    /// object macro (`#define _G0 0.25`) and ANOTHER pass declares a real identifier with the same
    /// name (`const float _G0 = 0.25;`). Shadertoy compiles passes separately so they never collide;
    /// concatenating into one file leaks the file-global `#define` forward, rewriting the declaration
    /// into `const float 0.25 = 0.25;` → "unexpected FLOATCONSTANT". Scope the macro to its own pass
    /// with a trailing `#undef`.
    func test_undefsObjectMacroShadowedByDeclarationInAnotherPass() {
        let pass0 = "#define _G0 0.25\nvoid mainImage(out vec4 o, in vec2 f){ o = vec4(_G0); }"
        let pass1 = "const float _G0 = 0.25;\nvoid mainImage(out vec4 o, in vec2 f){ o = vec4(_G0); }"
        let out = GLSLPassMacroScoper.scope([pass0, pass1], commonCode: "")

        // The defining pass gains a trailing `#undef`; the declaring pass is untouched.
        XCTAssertTrue(out[0].contains("#undef _G0"), "defining pass should #undef its macro")
        XCTAssertTrue(out[0].hasSuffix("#undef _G0"), "#undef must come AFTER the pass's own code")
        XCTAssertEqual(out[1], pass1, "the pass that only declares the identifier is unchanged")
    }

    /// Regression for the macro-redefinition class (M3cGW2 `bb`, tlX3zs `A`): two passes each
    /// `#define` the SAME function-like macro. The bodies look identical in source but SamplerRewriter
    /// rewrites the `iChannelN` inside each to a per-pass sampler → genuinely "different substitutions"
    /// at glslang. `#undef` after each defining pass makes every redefinition clean.
    func test_undefsFunctionMacroRedefinedAcrossPasses() {
        let pass0 = "#define A(U) texture(bufA, (U))\nvoid mainImage(out vec4 o, in vec2 f){ o = A(f); }"
        let pass1 = "#define A(U) texture(bufB, (U))\nvoid mainImage(out vec4 o, in vec2 f){ o = A(f); }"
        let out = GLSLPassMacroScoper.scope([pass0, pass1], commonCode: "")

        // `#undef` uses the bare macro name (no parameter list), in every pass that defines it.
        XCTAssertTrue(out[0].hasSuffix("#undef A"))
        XCTAssertTrue(out[1].hasSuffix("#undef A"))
    }

    /// A macro used only within its own pass must be left byte-for-byte unchanged — most shaders never
    /// collide, and churning their output would defeat reviewability (mirrors GLSLPassNamespace).
    func test_leavesPassLocalMacroAlone() {
        let pass0 = "#define LOCAL 1.0\nvoid mainImage(out vec4 o, in vec2 f){ o = vec4(LOCAL); }"
        let pass1 = "void mainImage(out vec4 o, in vec2 f){ o = vec4(0.0); }"
        let out = GLSLPassMacroScoper.scope([pass0, pass1], commonCode: "")
        XCTAssertEqual(out, [pass0, pass1])
    }

    /// A macro defined in Common-only style (no pass defines it) is irrelevant here — only PASS-body
    /// `#define`s are scoped. A single pass with a macro used elsewhere-as-token still scopes only the
    /// defining pass. Sanity: empty input round-trips.
    func test_emptyInputRoundTrips() {
        XCTAssertEqual(GLSLPassMacroScoper.scope([], commonCode: ""), [])
    }

    /// M18 — a pass redefining a Common macro: `#undef` inserted immediately BEFORE the pass's
    /// own `#define` (code above it legitimately uses the Common meaning), and the Common
    /// definition restored after the pass so later passes/Common helpers keep their meaning.
    func test_passDefineShadowingCommonMacro_undeffedAndRestored_M18() {
        let common = "#define A 1.0"
        let passes = ["float x = A;\n#define A 2.0\nfloat y = A;", "float z = A;"]
        let out = GLSLPassMacroScoper.scope(passes, commonCode: common)
        XCTAssertTrue(out[0].contains("float x = A;\n#undef A\n#define A 2.0"), out[0])
        XCTAssertTrue(out[0].hasSuffix("#undef A\n#define A 1.0"), out[0])
        XCTAssertEqual(out[1], "float z = A;")
    }

    /// M18 comment-awareness — a macro name mentioned only inside another pass's COMMENT is not
    /// a collision; no spurious #undef.
    func test_macroMentionedOnlyInComment_noUndef_M18() {
        let passes = ["#define B 1.0\nfloat x = B;", "// B is prose here\nfloat y = 0.;"]
        let out = GLSLPassMacroScoper.scope(passes, commonCode: "")
        XCTAssertEqual(out, passes)
    }

    /// A #define inside a comment is not a definition.
    func test_commentedOutDefine_notCollected() {
        let passes = ["// #define C 1.0\nfloat x = 0.;", "#define C 2.0\nfloat y = C;"]
        let out = GLSLPassMacroScoper.scope(passes, commonCode: "")
        XCTAssertEqual(out, passes)   // C defined in one pass only, mentioned nowhere else real
    }
}
