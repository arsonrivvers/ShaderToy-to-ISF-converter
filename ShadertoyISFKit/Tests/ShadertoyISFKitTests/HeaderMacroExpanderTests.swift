import XCTest
@testable import ShadertoyISFKit

final class HeaderMacroExpanderTests: XCTestCase {
    /// XftGRj class: a Common `#define Main void mainImage(…)` hides the entry-point signature behind a
    /// macro. Each pass writes `Main { … }`, so the literal `mainImage` never appears in a pass body and
    /// GLSLBodyBuilder's per-pass rename can't make it unique → every pass expands to a duplicate
    /// `void mainImage`. Expand the macro into each pass body and drop the #define.
    func test_expandsHeaderMacroIntoPasses_andStripsDefine() {
        let common = "#define Main void mainImage(out vec4 Q, in vec2 U)\nfloat helper(){ return 1.0; }"
        let passes = ["Main { Q = vec4(1.0); }", "Main { Q = vec4(U, 0.0, 1.0); }"]
        let r = HeaderMacroExpander.expand(commonCode: common, passBodies: passes)
        XCTAssertEqual(r.passBodies[0], "void mainImage(out vec4 Q, in vec2 U) { Q = vec4(1.0); }")
        XCTAssertEqual(r.passBodies[1], "void mainImage(out vec4 Q, in vec2 U) { Q = vec4(U, 0.0, 1.0); }")
        XCTAssertFalse(r.commonCode.contains("#define Main"))
        XCTAssertTrue(r.commonCode.contains("float helper()"))   // other Common content preserved
    }

    /// A pass that defines mainImage directly (no macro) is left untouched.
    func test_passWithoutMacro_untouched() {
        let common = "#define Main void mainImage(out vec4 Q, in vec2 U)\n"
        let passes = ["Main { Q = vec4(1.0); }", "void mainImage(out vec4 o, in vec2 f){ o = vec4(0.0); }"]
        let r = HeaderMacroExpander.expand(commonCode: common, passBodies: passes)
        XCTAssertEqual(r.passBodies[1], "void mainImage(out vec4 o, in vec2 f){ o = vec4(0.0); }")
    }

    /// No header macro present → everything passes through unchanged.
    func test_noHeaderMacro_unchanged() {
        let common = "#define PI 3.14159\nfloat f(){ return PI; }"
        let passes = ["void mainImage(out vec4 o, in vec2 f){ o = vec4(0.0); }"]
        let r = HeaderMacroExpander.expand(commonCode: common, passBodies: passes)
        XCTAssertEqual(r.commonCode, common)
        XCTAssertEqual(r.passBodies, passes)
    }

    /// Word-boundary safety: the macro name must not be rewritten inside a longer identifier.
    func test_macroNameWordBoundary() {
        let common = "#define M void mainImage(out vec4 Q, in vec2 U)\n"
        let passes = ["M { float Mx = 1.0; Q = vec4(Mx); }"]
        let r = HeaderMacroExpander.expand(commonCode: common, passBodies: passes)
        XCTAssertTrue(r.passBodies[0].hasPrefix("void mainImage(out vec4 Q, in vec2 U) {"))
        XCTAssertTrue(r.passBodies[0].contains("float Mx = 1.0;"))   // `Mx` untouched
    }

    /// A function-like macro (`#define X(a) …`) is NOT a header macro — left alone.
    func test_functionLikeMacro_notExpanded() {
        let common = "#define WRAP(x) mainImage(x)\n"
        let passes = ["void mainImage(out vec4 o, in vec2 f){ o = vec4(0.0); }"]
        let r = HeaderMacroExpander.expand(commonCode: common, passBodies: passes)
        XCTAssertEqual(r.commonCode, common)
        XCTAssertEqual(r.passBodies, passes)
    }
}
