import XCTest
@testable import ShadertoyISFKit

final class GLSLBodyBuilderTests: XCTestCase {
    func test_singlePass_wrapsAndDispatches() {
        let body = "void mainImage( out vec4 fragColor, in vec2 fragCoord ){ fragColor = vec4(1.0); }"
        let r = GLSLBodyBuilder.build(passBodies: [body], commonCode: "")
        XCTAssertTrue(r.code.contains("void pass0_mainImage("))
        XCTAssertTrue(r.code.contains("void main()"))
        XCTAssertTrue(r.code.contains("if (PASSINDEX == 0)"))
        XCTAssertTrue(r.code.contains("pass0_mainImage(c, gl_FragCoord.xy)"))
        XCTAssertTrue(r.code.contains("gl_FragColor = c;"))
    }

    func test_common_prependedOnce() {
        let r = GLSLBodyBuilder.build(passBodies: ["void mainImage(out vec4 c, in vec2 f){ c=vec4(0.0);}"],
                                      commonCode: "#define PI 3.14159")
        XCTAssertTrue(r.code.contains("#define PI 3.14159"))
        XCTAssertEqual(r.code.components(separatedBy: "#define PI").count - 1, 1)
    }

    func test_vectorTernary_warns() {
        let r = GLSLBodyBuilder.build(passBodies: ["void mainImage(out vec4 c, in vec2 f){ vec2 q = a>0.0 ? b : d; c=vec4(q,0,1);}"],
                                      commonCode: "")
        XCTAssertTrue(r.warnings.contains { $0.message.contains("ternary") })
    }
}
