import XCTest
@testable import ShadertoyISFKit

final class GLSLPassNamespaceTests: XCTestCase {
    /// Regression for flcSzr: two passes each define a top-level `Po(int,int)` with DIFFERENT bodies
    /// (one reads bufA, the other bufB). Merging passes into one file collides ("function already has
    /// a body"); dedup can't help because the bodies aren't identical. Namespace the colliding helper
    /// per-pass so the merge is conflict-free.
    func test_renamesCollidingDifferentBodyHelper() {
        let pass0 = "vec4 Po(int x, int y){ return texture(bufA, vec2(x,y)); }\nvoid mainImage(out vec4 o, in vec2 f){ o = Po(1,2); }"
        let pass1 = "vec4 Po(int x, int y){ return texture(bufB, vec2(x,y)); }\nvoid mainImage(out vec4 o, in vec2 f){ o = Po(3,4); }"
        let out = GLSLPassNamespace.namespace([pass0, pass1])

        // Definition renamed per pass…
        XCTAssertTrue(out[0].contains("vec4 p0_Po(int x, int y)"))
        XCTAssertTrue(out[1].contains("vec4 p1_Po(int x, int y)"))
        // …and call sites within the SAME pass renamed to match.
        XCTAssertTrue(out[0].contains("Po(1,2)".replacingOccurrences(of: "Po", with: "p0_Po")))
        XCTAssertTrue(out[1].contains("Po(3,4)".replacingOccurrences(of: "Po", with: "p1_Po")))
        // No bare `Po(` remains in either pass.
        XCTAssertNil(out[0].range(of: #"\bPo\("#, options: .regularExpression))
        XCTAssertNil(out[1].range(of: #"\bPo\("#, options: .regularExpression))
    }

    /// Helpers that collide but are BYTE-IDENTICAL must be left alone — GLSLFunctionDedup already
    /// merges those, and namespacing them would defeat the dedup (two identical bodies kept).
    func test_leavesIdenticalCollisionAlone() {
        let p = "float hash(float n){ return fract(n*43.0); }\nvoid mainImage(out vec4 o, in vec2 f){ o = vec4(hash(f.x)); }"
        let out = GLSLPassNamespace.namespace([p, p])
        XCTAssertEqual(out, [p, p])
    }

    /// A helper defined in only one pass has no collision risk — untouched (zero diff for the common case).
    func test_leavesSinglePassHelperAlone() {
        let pass0 = "float only(float n){ return n; }\nvoid mainImage(out vec4 o, in vec2 f){ o = vec4(only(f.x)); }"
        let pass1 = "void mainImage(out vec4 o, in vec2 f){ o = vec4(0.0); }"
        let out = GLSLPassNamespace.namespace([pass0, pass1])
        XCTAssertEqual(out, [pass0, pass1])
    }

    /// `mainImage` is renamed downstream by GLSLBodyBuilder per pass — namespacing must NOT touch it,
    /// even though it "collides" (every pass has one).
    func test_doesNotRenameMainImage() {
        let pass0 = "void mainImage(out vec4 o, in vec2 f){ o = vec4(1.0); }"
        let pass1 = "void mainImage(out vec4 o, in vec2 f){ o = vec4(2.0); }"
        let out = GLSLPassNamespace.namespace([pass0, pass1])
        XCTAssertEqual(out, [pass0, pass1])
        XCTAssertFalse(out[0].contains("p0_mainImage"))
    }

    /// A pass that REFERENCES a Common-tab helper `Shared` (without defining it) while OTHER passes
    /// define a differing top-level `Shared` must keep its reference intact — we only rename inside
    /// passes that actually DEFINE the colliding name.
    func test_leavesCommonHelperReferenceInNonDefiningPass() {
        let pass0 = "vec4 Shared(int i){ return vec4(float(i)); }\nvoid mainImage(out vec4 o, in vec2 f){ o = Shared(1); }"
        let pass1 = "vec4 Shared(int i){ return vec4(float(i)*2.0); }\nvoid mainImage(out vec4 o, in vec2 f){ o = Shared(2); }"
        let pass2 = "void mainImage(out vec4 o, in vec2 f){ o = Shared(9); }"  // calls a common Shared
        let out = GLSLPassNamespace.namespace([pass0, pass1, pass2])
        XCTAssertTrue(out[0].contains("p0_Shared(int i)"))
        XCTAssertTrue(out[1].contains("p1_Shared(int i)"))
        XCTAssertEqual(out[2], pass2)                       // untouched — keeps the common reference
        XCTAssertTrue(out[2].contains("Shared(9)"))
    }

    /// Word-boundary safety: a colliding name that is a substring of another identifier must not be
    /// partially rewritten.
    func test_wordBoundarySafe() {
        let pass0 = "vec4 Po(int x){ return vec4(0.0); }\nvoid mainImage(out vec4 o, in vec2 f){ vec4 Point = Po(1); o = Point; }"
        let pass1 = "vec4 Po(int x){ return vec4(1.0); }\nvoid mainImage(out vec4 o, in vec2 f){ o = Po(2); }"
        let out = GLSLPassNamespace.namespace([pass0, pass1])
        XCTAssertTrue(out[0].contains("vec4 Point = p0_Po(1)"))   // `Point` untouched, `Po(` renamed
        XCTAssertTrue(out[0].contains("vec4 Point ="))
    }
}
