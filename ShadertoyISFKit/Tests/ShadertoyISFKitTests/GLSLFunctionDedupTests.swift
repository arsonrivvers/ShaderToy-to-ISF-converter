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
}
