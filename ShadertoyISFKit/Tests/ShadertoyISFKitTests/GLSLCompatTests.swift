import XCTest
@testable import ShadertoyISFKit

final class GLSLCompatTests: XCTestCase {
    func test_tanh_addsGuardedPolyfill() {
        let r = GLSLCompat.apply("void main(){ vec4 c = tanh(vec4(1.0)); }")
        XCTAssertTrue(r.code.contains("#if __VERSION__ < 130"))
        XCTAssertTrue(r.code.contains("float tanh(float x)"))
        XCTAssertTrue(r.code.contains("vec4 tanh(vec4 v)"))
        XCTAssertTrue(r.code.contains("#endif"))
        XCTAssertTrue(r.warnings.contains { $0.message.contains("tanh") })
    }
    func test_noPolyfill_whenUnused() {
        let r = GLSLCompat.apply("void main(){ gl_FragColor = vec4(1.0); }")
        XCTAssertFalse(r.code.contains("__VERSION__"))
        XCTAssertTrue(r.warnings.isEmpty)
    }
    func test_multipleFunctions_eachDefined() {
        let r = GLSLCompat.apply("float a = sinh(1.0); float b = round(2.3); float c = trunc(2.9);")
        XCTAssertTrue(r.code.contains("float sinh(float x)"))
        XCTAssertTrue(r.code.contains("float round(float x)"))
        XCTAssertTrue(r.code.contains("float trunc(float x)"))
    }
    func test_bitShift_warns() {
        let r = GLSLCompat.apply("int x = 1 << 3;")
        XCTAssertTrue(r.warnings.contains { $0.message.lowercased().contains("bit-shift") })
    }
}
