import XCTest
@testable import ShadertoyISFKit

final class OutputInitializerTests: XCTestCase {
    /// Regression for NXsSRN: `for(O*=i; …)` accumulates into an uninitialized out param. On Metal
    /// O is undefined (NaN) → stays NaN → black. Inject `O = vec4(0.0);` at the function start.
    func test_injectsInitForAccumulatorOutput() {
        let src = "void pass0_mainImage( out vec4 O, vec2 I ){\n  for (O*=i; i++<40.;){ O+=v; }\n  O=tanh(O);\n}"
        let r = OutputInitializer.apply(src)
        XCTAssertTrue(r.code.contains("){\n    O = vec4(0.0);"), "expected init after the brace; got:\n\(r.code)")
        XCTAssertTrue(r.warnings.contains { $0.message.contains("Auto-initialized output 'O'") })
    }

    /// An output that is plainly assigned before any compound use must NOT be touched.
    func test_leavesProperlyInitializedOutputAlone() {
        let src = "void f( out vec4 O, vec2 I ){\n  O = vec4(1.0);\n  O += vec4(0.5);\n}"
        let r = OutputInitializer.apply(src)
        XCTAssertEqual(r.code, src)
        XCTAssertTrue(r.warnings.isEmpty)
    }

    /// No out param → unchanged.
    func test_noOutput_unchanged() {
        let src = "void helper(vec2 p){ float x = 1.0; }"
        let r = OutputInitializer.apply(src)
        XCTAssertEqual(r.code, src)
        XCTAssertTrue(r.warnings.isEmpty)
    }

    /// C4 — an `inout vec4` accumulator must NOT be zero-injected: the injected `col = vec4(0.0);`
    /// would wipe the value the caller passed in (silent wrong render, zero diagnostics).
    func test_inoutParam_isNotInjected() {
        let src = "void addGlow(inout vec4 col, vec2 p){\n  col += vec4(p, 0.0, 1.0);\n}"
        let r = OutputInitializer.apply(src)
        XCTAssertEqual(r.code, src)
        XCTAssertTrue(r.warnings.isEmpty)
    }

    /// C4 — when a real `out` accumulator and an `inout` helper share the output NAME, only the
    /// `out` signature gets the injection (the old pattern injected into ALL matching signatures).
    func test_mixedOutAndInout_onlyOutSignatureIsInjected() {
        let src = "void glow(inout vec4 O){\n  O += vec4(0.1);\n}\nvoid mainImage( out vec4 O, vec2 I ){\n  for (O*=i; i++<9.;){ O+=v; }\n}"
        let r = OutputInitializer.apply(src)
        XCTAssertTrue(r.code.contains("void mainImage( out vec4 O, vec2 I ){\n    O = vec4(0.0);"),
                      "out signature must be initialized; got:\n\(r.code)")
        XCTAssertTrue(r.code.contains("void glow(inout vec4 O){\n  O += vec4(0.1);"),
                      "inout signature must be untouched; got:\n\(r.code)")
    }
}
