import XCTest
@testable import ShadertoyISFKit

final class GLSLReservedIdentifierRewriterTests: XCTestCase {
    /// Regression for 7l3yz4 / Nl3czM: `char` is a GLSL identifier but an MSL/C++ keyword, so
    /// `float char = …` transpiles to "cannot combine with previous 'float' declaration specifier".
    func test_renamesCharVariableAndItsUses() {
        let src = "void f(){ float char = 1.0; char += 2.0; gl_FragColor = vec4(char); }"
        let out = GLSLReservedIdentifierRewriter.rewrite(src)
        XCTAssertNil(out.range(of: #"\bchar\b"#, options: .regularExpression))
        XCTAssertTrue(out.contains("float usr_char = 1.0;"))
        XCTAssertTrue(out.contains("usr_char += 2.0;"))
        XCTAssertTrue(out.contains("vec4(usr_char)"))
    }

    /// Regression for wXffDH: a user function named `coord` is ambiguous with `metal::coord`.
    func test_renamesCoordFunctionAndCalls() {
        let src = "vec2 coord(vec2 f){ return f; }\nvoid main(){ vec2 uv = coord(gl_FragCoord.xy); }"
        let out = GLSLReservedIdentifierRewriter.rewrite(src)
        XCTAssertNil(out.range(of: #"\bcoord\b"#, options: .regularExpression))
        XCTAssertTrue(out.contains("vec2 usr_coord(vec2 f)"))
        XCTAssertTrue(out.contains("usr_coord(gl_FragCoord.xy)"))
    }

    /// Builtins that merely CONTAIN a reserved word as a substring must be untouched — `\b` word
    /// boundaries protect `chars`, `gl_FragCoord`, `isf_FragNormCoord`, `texture`.
    func test_leavesSubstringMatchesAlone() {
        let src = "void main(){ float chars[2]; vec2 p = gl_FragCoord.xy; p = isf_FragNormCoord; vec4 c = texture(iChannel0, p); }"
        XCTAssertEqual(GLSLReservedIdentifierRewriter.rewrite(src), src)
    }

    /// A shader using none of the reserved words is returned unchanged.
    func test_noReservedWordsIsUnchanged() {
        let src = "vec3 palette(float t){ return vec3(t); }\nvoid mainImage(out vec4 o, in vec2 f){ o = vec4(palette(f.x), 1.0); }"
        XCTAssertEqual(GLSLReservedIdentifierRewriter.rewrite(src), src)
    }
}
