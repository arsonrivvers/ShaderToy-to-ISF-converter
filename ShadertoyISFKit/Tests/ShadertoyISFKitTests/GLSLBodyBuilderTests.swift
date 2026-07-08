import XCTest
@testable import ShadertoyISFKit

final class GLSLBodyBuilderTests: XCTestCase {
    func test_singlePass_wrapsAndDispatches() {
        let body = "void mainImage( out vec4 fragColor, in vec2 fragCoord ){ fragColor = vec4(1.0); }"
        let r = GLSLBodyBuilder.build(passBodies: [body], commonCode: "")
        XCTAssertTrue(r.code.contains("void pass0_mainImage("))
        XCTAssertTrue(r.code.contains("void main()"))
        XCTAssertTrue(r.code.contains("if (PASSINDEX == 0)"))
        XCTAssertTrue(r.code.contains("pass0_mainImage(_isf_passColor, gl_FragCoord.xy)"))
        XCTAssertTrue(r.code.contains("gl_FragColor = _isf_passColor;"))
    }

    func test_common_prependedOnce() {
        let r = GLSLBodyBuilder.build(passBodies: ["void mainImage(out vec4 c, in vec2 f){ c=vec4(0.0);}"],
                                      commonCode: "#define PI 3.14159")
        XCTAssertTrue(r.code.contains("#define PI 3.14159"))
        XCTAssertEqual(r.code.components(separatedBy: "#define PI").count - 1, 1)
    }

    /// flcSzr-class: two passes define `Po(int,int)` with DIFFERENT bodies. After merge there must be
    /// no duplicate top-level `Po(` definition (would be "function already has a body"); each pass's
    /// helper is namespaced and its call site follows.
    func test_collidingHelperAcrossPasses_isNamespaced() {
        let pass0 = "vec4 Po(int x, int y){ return vec4(float(x)); }\nvoid mainImage(out vec4 o, in vec2 f){ o = Po(1,2); }"
        let pass1 = "vec4 Po(int x, int y){ return vec4(float(y)); }\nvoid mainImage(out vec4 o, in vec2 f){ o = Po(3,4); }"
        let r = GLSLBodyBuilder.build(passBodies: [pass0, pass1], commonCode: "")
        XCTAssertEqual(r.code.components(separatedBy: " Po(int x, int y)").count - 1, 0)  // no bare collision
        XCTAssertTrue(r.code.contains("vec4 p0_Po(int x, int y)"))
        XCTAssertTrue(r.code.contains("vec4 p1_Po(int x, int y)"))
    }

    /// M17 — the dispatch temp must not be a single-letter name a golfed pass macro can capture:
    /// a last-pass `#define c ...` would expand `vec4 c;` in main() into garbage → compile fail.
    func test_dispatchTemp_isCollisionResistant() {
        let r = GLSLBodyBuilder.build(passBodies: ["void mainImage(out vec4 O, in vec2 f){ O=vec4(0.0);}"],
                                      commonCode: "")
        XCTAssertFalse(r.code.contains("vec4 c;"), "single-letter dispatch temp is macro-capturable")
        XCTAssertTrue(r.code.contains("vec4 _isf_passColor;"), r.code)
        XCTAssertTrue(r.code.contains("gl_FragColor = _isf_passColor;"), r.code)
    }

    func test_vectorTernary_warns() {
        let r = GLSLBodyBuilder.build(passBodies: ["void mainImage(out vec4 c, in vec2 f){ vec2 q = a>0.0 ? b : d; c=vec4(q,0,1);}"],
                                      commonCode: "")
        XCTAssertTrue(r.warnings.contains { $0.message.contains("ternary") })
    }
}
