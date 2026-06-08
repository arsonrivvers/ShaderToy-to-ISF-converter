import XCTest
@testable import ShadertoyISFKit

final class GLSLLintTests: XCTestCase {
    func test_xorPattern_warnsAboutUninitializedOutput() {
        let code = "void mainImage(out vec4 O, vec2 I){ for(O*=i; i++<9.;) O += vec4(1.0); O = tanh(O); }"
        let w = GLSLLint.check(code)
        XCTAssertTrue(w.contains { $0.message.contains("O") && $0.message.lowercased().contains("initial") })
    }
    func test_properlyInitializedOutput_noWarning() {
        let code = "void mainImage(out vec4 O, vec2 I){ O = vec4(0.0); O += vec4(1.0); }"
        XCTAssertTrue(GLSLLint.check(code).isEmpty)
    }
    func test_noOutParam_noWarning() {
        XCTAssertTrue(GLSLLint.check("void main(){ gl_FragColor = vec4(1.0); }").isEmpty)
    }
}
