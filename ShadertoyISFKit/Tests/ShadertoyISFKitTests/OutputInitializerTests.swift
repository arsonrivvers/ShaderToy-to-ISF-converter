import XCTest
@testable import ShadertoyISFKit

final class OutputInitializerTests: XCTestCase {
    /// Regression for NXsSRN: `for(O*=i; …)` accumulates into an uninitialized out param. On Metal
    /// O is undefined (NaN) → stays NaN → black. Inject `O = vec4(0.0);` at the function start.
    func test_injectsInitForAccumulatorOutput() {
        let src = "void pass0_mainImage( out vec4 O, vec2 I ){\n  for (O*=i; i++<40.;){ O+=v; }\n  O=tanh(O);\n}"
        let r = OutputInitializer.apply(src)
        XCTAssertTrue(r.code.contains("){\n    O = vec4(0.0);"), "expected init after the brace; got:\n\(r.code)")
        XCTAssertTrue(r.notes.contains { $0.message.contains("Auto-initialized output 'O'") })
    }

    /// An output that is plainly assigned before any compound use must NOT be touched.
    func test_leavesProperlyInitializedOutputAlone() {
        let src = "void f( out vec4 O, vec2 I ){\n  O = vec4(1.0);\n  O += vec4(0.5);\n}"
        let r = OutputInitializer.apply(src)
        XCTAssertEqual(r.code, src)
        XCTAssertTrue(r.notes.isEmpty)
    }

    /// No out param → unchanged.
    func test_noOutput_unchanged() {
        let src = "void helper(vec2 p){ float x = 1.0; }"
        let r = OutputInitializer.apply(src)
        XCTAssertEqual(r.code, src)
        XCTAssertTrue(r.notes.isEmpty)
    }
}
