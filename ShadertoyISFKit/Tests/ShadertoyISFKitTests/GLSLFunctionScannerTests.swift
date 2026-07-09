import XCTest
@testable import ShadertoyISFKit

final class GLSLFunctionScannerTests: XCTestCase {
    func test_simpleDef_nameAndRange() {
        let code = "float noise(vec2 p) { return p.x; }"
        let d = GLSLFunctionScanner.defs(in: code)[0]
        XCTAssertEqual(d.name, "noise")
        XCTAssertEqual(d.start, 0)
        XCTAssertEqual(d.end, (code as NSString).length)
    }

    func test_allmanBrace_stillADef() {
        XCTAssertEqual(GLSLFunctionScanner.defs(in: "vec3 f(vec2 p)\n{\n  return vec3(p, 0.);\n}").map(\.name),
                       ["f"])
    }

    func test_controlFlow_notADef() {
        XCTAssertTrue(GLSLFunctionScanner.defs(in: "void g(){ if (x) { } else if (y) { } }").map(\.name)
            .allSatisfy { $0 == "g" })
    }

    /// M14 — commented-out function must not become a Def (worst case Dedup deletes the REAL one).
    func test_commentedOutFunction_isNotADef_M14() {
        let code = "/*\nfloat helper(vec2 p) { return p.x; }\n*/\nfloat helper(vec2 p) { return p.y; }"
        let defs = GLSLFunctionScanner.defs(in: code)
        XCTAssertEqual(defs.count, 1)
        let kept = (code as NSString).substring(with: NSRange(location: defs[0].start,
                                                              length: defs[0].end - defs[0].start))
        XCTAssertTrue(kept.contains("p.y"))
    }

    // MARK: - functionDefs — the C5 scope model

    func test_paramNames_basicAndQualified() {
        let defs = GLSLFunctionScanner.functionDefs(in:
            "void ups(in vec2 uv, inout vec4 col, vec2 iResolution, sampler2D iChannel0) { }")
        XCTAssertEqual(defs[0].paramNames, ["uv", "col", "iResolution", "iChannel0"])
    }

    func test_paramNames_voidAndEmpty() {
        XCTAssertEqual(GLSLFunctionScanner.functionDefs(in: "float a() { return 1.; }")[0].paramNames, [])
        XCTAssertEqual(GLSLFunctionScanner.functionDefs(in: "float b(void) { return 1.; }")[0].paramNames, [])
    }

    func test_paramNames_arraySuffix() {
        XCTAssertEqual(GLSLFunctionScanner.functionDefs(in: "float c(float arr[4]) { return arr[0]; }")[0].paramNames,
                       ["arr"])
    }

    func test_normalize_ignoresCommentsAndWhitespace() {
        let a = GLSLFunctionScanner.normalize("float f() { // note\n  return 1.0; }")
        let b = GLSLFunctionScanner.normalize("float f() {  return 1.0; }")
        XCTAssertEqual(a, b)
    }
}
