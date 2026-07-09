import XCTest
@testable import ShadertoyISFKit

final class GLSLGlobalScannerTests: XCTestCase {
    func test_simpleGlobal_found() {
        let defs = GLSLGlobalScanner.defs(in: "float f = 0.025;\n")
        XCTAssertEqual(defs.map(\.name), ["f"])
    }

    func test_constAndArrayGlobals_found() {
        let code = "const float pi = 3.14159;\nvec3 pal[16];"
        XCTAssertEqual(GLSLGlobalScanner.defs(in: code).map(\.name), ["pi", "pal"])
    }

    func test_localDeclaration_excluded() {
        let code = "void f() {\n    float local = 1.0;\n}"
        XCTAssertTrue(GLSLGlobalScanner.defs(in: code).isEmpty)
    }

    func test_functionDefinitionAndPrototype_excluded() {
        let code = "float f(vec2 p) { return p.x; }\nfloat g(vec2 p);"
        XCTAssertTrue(GLSLGlobalScanner.defs(in: code).isEmpty)
    }

    func test_defRange_coversWholeStatement() {
        let code = "float f = 0.025;"
        let d = GLSLGlobalScanner.defs(in: code)[0]
        XCTAssertEqual((code as NSString).substring(with: NSRange(location: d.start, length: d.end - d.start)),
                       "float f = 0.025;")
    }

    /// M14 — a global inside a block comment must NOT become a Def (phantom defs made
    /// GLSLFunctionDedup delete the REAL definition and keep the commented text).
    func test_globalInsideBlockComment_isNotADef_M14() {
        let code = "/*\nfloat ghost = 1.0;\n*/\nfloat real = 2.0;"
        XCTAssertEqual(GLSLGlobalScanner.defs(in: code).map(\.name), ["real"])
    }

    /// M14 — line-commented global likewise.
    func test_globalInsideLineComment_isNotADef_M14() {
        XCTAssertEqual(GLSLGlobalScanner.defs(in: "// float ghost = 1.0;\nfloat real = 2.0;").map(\.name),
                       ["real"])
    }

    /// M2 — `float a, b, c;` previously matched only `a` (and `float a = 1., b = 2.;` matched as
    /// a single Def named `a`), leaving the rest invisible to dedup/namespacing → cross-pass
    /// redefinition errors.
    func test_commaSeparatedGlobals_allDeclaratorsVisible_M2() {
        let defs = GLSLGlobalScanner.defs(in: "float a, b, c;")
        XCTAssertEqual(defs.map(\.name), ["a", "b", "c"])
        XCTAssertEqual(Set(defs.map(\.start)).count, 1)   // one statement, three declarators
    }

    func test_commaListWithInitializers_M2() {
        XCTAssertEqual(GLSLGlobalScanner.defs(in: "float a = 1., b = 2.;").map(\.name), ["a", "b"])
    }

    func test_initializerCommas_doNotSplitDeclarators_M2() {
        XCTAssertEqual(GLSLGlobalScanner.defs(in: "vec2 q = vec2(1., 2.), r = vec2(3., 4.);").map(\.name),
                       ["q", "r"])
    }
}
