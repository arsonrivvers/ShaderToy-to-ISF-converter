import XCTest
@testable import ShadertoyISFKit

final class GLSLFunctionDedupTests: XCTestCase {
    /// Regression for N3fXRl / flcSzr: a multipass shader with no Common tab copies the same helper
    /// into each tab; merging the passes into one file produces a duplicate definition
    /// ("function already has a body"). Remove byte-identical duplicate top-level functions.
    func test_removesDuplicateIdenticalFunction() {
        let src = "float hash(float n){ return n; }\nvoid main(){}\nfloat hash(float n){ return n; }"
        let out = GLSLFunctionDedup.dedup(src)
        XCTAssertEqual(out.components(separatedBy: "float hash(float n)").count - 1, 1)
        XCTAssertTrue(out.contains("void main(){}"))
    }

    func test_keepsDistinctFunctions() {
        let src = "float a(float n){ return n; }\nfloat b(float n){ return n + 1.0; }"
        XCTAssertEqual(GLSLFunctionDedup.dedup(src), src)
    }

    /// Different bodies under the same name are NOT removed (not byte-identical) — leaving the
    /// conflict visible rather than silently dropping one.
    func test_keepsSameNameDifferentBody() {
        let src = "float f(float n){ return n; }\nfloat f(float n){ return n + 1.0; }"
        XCTAssertEqual(GLSLFunctionDedup.dedup(src), src)
    }

    /// Two tab copies that differ only by comments/whitespace must still dedup (code is identical).
    func test_dedupsWhenOnlyCommentsDiffer() {
        let a = "float g(float n){ return n * 2.0; }"
        let b = "float g(float n){ // tweaked in this tab\n  return n * 2.0;\n}"
        let out = GLSLFunctionDedup.dedup(a + "\n" + b)
        XCTAssertEqual(out.components(separatedBy: "float g(float n)").count - 1, 1)
    }

    func test_doesNotMatchControlFlow() {
        let src = "void main(){ for (int i=0;i<3;i++){ x+=float(i); } if (y>0.0){ z=1.0; } }"
        XCTAssertEqual(GLSLFunctionDedup.dedup(src), src)
    }

    /// A `}` inside a comment in the body must not end the block early (would mis-bound the dedup).
    func test_braceInCommentInBody_matchesCorrectly() {
        let f = "float f(float n){ // close }\n return n; }"
        let out = GLSLFunctionDedup.dedup(f + "\n" + f)
        XCTAssertEqual(out.components(separatedBy: "float f(float n)").count - 1, 1)
    }

    /// Regression for WdtXzs / t3ycDR: Allman brace style — the opening `{` on its OWN line after
    /// the `)`. The header scanner must still detect the def so identical copies across passes dedup.
    func test_dedupsAllmanBraceFunction() {
        let f = "vec4 B(vec2 pos)\n{\n    return vec4(pos, 0.0, 1.0);\n}"
        let out = GLSLFunctionDedup.dedup(f + "\nvoid main(){}\n" + f)
        XCTAssertEqual(out.components(separatedBy: "vec4 B(vec2 pos)").count - 1, 1)
    }

    /// Multi-line signature with an array out-param and Allman brace (t3ycDR's gather8FromB) must
    /// be detected as one def so identical copies across passes dedup.
    func test_dedupsMultiLineArrayParamSignature() {
        let f = "void gather(sampler2D ch, vec2 pos,\n            out int nb[8], out int cnt)\n{\n    cnt = 0;\n}"
        let out = GLSLFunctionDedup.dedup(f + "\nvoid main(){}\n" + f)
        XCTAssertEqual(out.components(separatedBy: "void gather(").count - 1, 1)
    }

    /// Regression for Nl3czM: an identical top-level GLOBAL (here a const array) defined in 2 passes
    /// collides at file scope after the merge. Keep one shared copy — passes that merely REFERENCE it
    /// (without redefining) then still resolve, which is why dedup (not namespacing) is correct.
    func test_dedupsIdenticalGlobalArray() {
        let g = "const vec3 PAL[2] = vec3[]( vec3(1.0,0.0,0.0), vec3(0.0,1.0,0.0) );"
        let out = GLSLFunctionDedup.dedup(g + "\nvoid main(){}\n" + g)
        XCTAssertEqual(out.components(separatedBy: "PAL[2]").count - 1, 1)
    }

    /// A simple identical scalar global dedups too.
    func test_dedupsIdenticalScalarGlobal() {
        let g = "const float TAU = 6.2831;"
        let out = GLSLFunctionDedup.dedup(g + "\nvoid main(){}\n" + g)
        XCTAssertEqual(out.components(separatedBy: "TAU").count - 1, 1)
    }

    /// Globals with the SAME name but DIFFERENT bodies must NOT be deduped (namespacing handles those).
    func test_keepsDistinctSameNameGlobals() {
        let src = "float f = 0.025;\nvoid main(){}\nfloat f = 0.035;"
        XCTAssertEqual(GLSLFunctionDedup.dedup(src), src)
    }

    /// A LOCAL variable inside a function body (depth > 0) must never be treated as a global and
    /// deduped away — even if an identical declaration appears in another function.
    func test_doesNotDedupLocalVariables() {
        let src = "void a(){ float t = 1.0; }\nvoid b(){ float t = 1.0; }"
        XCTAssertEqual(GLSLFunctionDedup.dedup(src), src)
    }
}
