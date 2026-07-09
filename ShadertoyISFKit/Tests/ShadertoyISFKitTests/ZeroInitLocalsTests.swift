import XCTest
@testable import ShadertoyISFKit

/// Task-1 triage class (6/10 corpus BLACKs): golf shaders declare locals uninitialized
/// (`float i, d, z, r;` … `for(O*=i; i++<9e1;)`). ANGLE zero-initializes locals on WebGL;
/// Metal does not — loop guards read garbage/NaN, loops never run, output stays black.
/// Zero-initializing matches the WebGL behavior the shader was authored against.
final class ZeroInitLocalsTests: XCTestCase {
    func test_commaDeclaredScalars_initialized() {
        let out = ZeroInitLocals.rewrite("void f(){ float t = 1.0,i,z,d; }")
        XCTAssertEqual(out.code, "void f(){ float t = 1.0,i = 0.0,z = 0.0,d = 0.0; }")
        XCTAssertEqual(out.warnings.count, 1)
        XCTAssertTrue(out.warnings[0].message.contains("i, z, d"), out.warnings[0].message)
    }

    func test_vectorLocals_initialized() {
        XCTAssertEqual(ZeroInitLocals.rewrite("void f(){ vec4 o, P; }").code,
                       "void f(){ vec4 o = vec4(0.0), P = vec4(0.0); }")
    }

    func test_initlessForLoopVar_initialized() {
        XCTAssertEqual(ZeroInitLocals.rewrite("void f(){ for (float i; i < 8.; i++) {} }").code,
                       "void f(){ for (float i = 0.0; i < 8.; i++) {} }")
    }

    func test_initializedForLoopVar_untouched() {
        let src = "void f(){ for (int i = 0; i < 4; i++) {} }"
        XCTAssertEqual(ZeroInitLocals.rewrite(src).code, src)
    }

    func test_fileScopeGlobals_untouched() {
        let src = "float g;\nvoid f(){ }"
        XCTAssertEqual(ZeroInitLocals.rewrite(src).code, src)
    }

    func test_structMembers_untouched() {
        let src = "void f(){ struct S { float a, b; }; S s = S(1., 2.); }"
        XCTAssertEqual(ZeroInitLocals.rewrite(src).code, src)
    }

    func test_constAndInitialized_untouched() {
        let src = "void f(){ const float c = 1.0; float x = 2.0; }"
        XCTAssertEqual(ZeroInitLocals.rewrite(src).code, src)
    }

    func test_arrayAndUserStructDeclarators_untouched() {
        let src = "void f(){ float arr[4]; MyType m; }"
        XCTAssertEqual(ZeroInitLocals.rewrite(src).code, src)
    }

    func test_commentedDeclaration_untouched() {
        let src = "void f(){ // float i, j;\n float k = 1.; }"
        XCTAssertEqual(ZeroInitLocals.rewrite(src).code, src)
    }

    func test_functionParams_untouched() {
        let src = "void f(vec2 p, out vec4 O){ O = vec4(p, 0., 1.); }"
        XCTAssertEqual(ZeroInitLocals.rewrite(src).code, src)
    }

    /// The 3XBBWD shape end-to-end at unit level: mixed initialized/uninitialized comma list.
    func test_golfIdiom_mixedCommaList() {
        let out = ZeroInitLocals.rewrite(
            "void mainImage( out vec4 o, in vec2 I ){ float t = 1.0,i,z,d;\n for(o*=i;i++<80.;){} }")
        XCTAssertTrue(out.code.contains("float t = 1.0,i = 0.0,z = 0.0,d = 0.0;"), out.code)
    }

    func test_intUintBool_zeroValues() {
        XCTAssertEqual(ZeroInitLocals.rewrite("void f(){ int i; uint u; bool b; }").code,
                       "void f(){ int i = 0; uint u = 0u; bool b = false; }")
    }
}
