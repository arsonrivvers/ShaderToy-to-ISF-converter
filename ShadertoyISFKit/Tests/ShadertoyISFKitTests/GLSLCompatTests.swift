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

    /// Regression for N323DD: shaders using packHalf2x16/unpackHalf2x16 need the
    /// GL_ARB_shading_language_packing extension requested, or glslang (the ISFMSLKit preview
    /// transpiler) rejects them. Inject the directive + warn.
    func test_packHalf_requestsExtension_andWarns() {
        let r = GLSLCompat.apply("void main(){ uint u = packHalf2x16(vec2(0.5)); vec2 v = unpackHalf2x16(u); }")
        XCTAssertTrue(r.code.contains("#extension GL_ARB_shading_language_packing : require"))
        XCTAssertTrue(r.warnings.contains { $0.message.contains("GL_ARB_shading_language_packing") })
    }

    func test_noExtension_whenNoPacking() {
        let r = GLSLCompat.apply("void main(){ gl_FragColor = vec4(1.0); }")
        XCTAssertFalse(r.code.contains("#extension"))
    }
}
