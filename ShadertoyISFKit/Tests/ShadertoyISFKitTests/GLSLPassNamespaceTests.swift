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

    /// Regression for tXlfzr / 7l3yz4: `map` differs across passes (so it's namespaced), and
    /// `calcNormal` is BYTE-IDENTICAL across passes but CALLS `map`. Once `map` is renamed per-pass,
    /// the two calcNormal copies diverge — so calcNormal must ALSO be namespaced (transitive), else
    /// dedup can no longer collapse the now-differing duplicates → "function already has a body".
    func test_namespacesIdenticalHelperThatCallsNamespacedCallee() {
        let p0 = "float map(vec3 p){ return p.x; }\nvec3 calcNormal(vec3 p){ return vec3(map(p)); }\nvoid mainImage(out vec4 o, in vec2 f){ o = vec4(calcNormal(vec3(f,0.0)),1.0); }"
        let p1 = "float map(vec3 p){ return p.y; }\nvec3 calcNormal(vec3 p){ return vec3(map(p)); }\nvoid mainImage(out vec4 o, in vec2 f){ o = vec4(calcNormal(vec3(f,0.0)),1.0); }"
        let out = GLSLPassNamespace.namespace([p0, p1])
        XCTAssertTrue(out[0].contains("float p0_map"))         // seed: differing body
        XCTAssertTrue(out[1].contains("float p1_map"))
        XCTAssertTrue(out[0].contains("vec3 p0_calcNormal"))   // transitive: identical but calls map
        XCTAssertTrue(out[1].contains("vec3 p1_calcNormal"))
        XCTAssertNil(out[0].range(of: #"\bcalcNormal\("#, options: .regularExpression))
        XCTAssertNil(out[1].range(of: #"\bmap\("#, options: .regularExpression))
    }

    /// The transitive rule must NOT over-reach: an identical helper that does NOT reference any
    /// namespaced name stays untouched (dedup collapses it) even when OTHER names are namespaced.
    func test_leavesIdenticalHelperAloneWhenItCallsNoNamespacedCallee() {
        let p0 = "vec4 Po(int x){ return vec4(0.0); }\nfloat hash(float n){ return fract(n); }\nvoid mainImage(out vec4 o, in vec2 f){ o = Po(1)*hash(f.x); }"
        let p1 = "vec4 Po(int x){ return vec4(1.0); }\nfloat hash(float n){ return fract(n); }\nvoid mainImage(out vec4 o, in vec2 f){ o = Po(2)*hash(f.x); }"
        let out = GLSLPassNamespace.namespace([p0, p1])
        XCTAssertTrue(out[0].contains("p0_Po"))
        XCTAssertTrue(out[1].contains("p1_Po"))
        XCTAssertTrue(out[0].contains("float hash(float n)"))   // untouched — dedup's job
        XCTAssertFalse(out[0].contains("p0_hash"))
    }

    /// Regression for 4tfBRB / wXffDH: a top-level GLOBAL (`float f = 0.025;`) defined with a DIFFERENT
    /// value per pass collides at file scope after the merge ("redefinition"). Namespace it per-pass —
    /// definition AND every reference in the same pass — exactly like a colliding function.
    func test_namespacesDistinctGlobalAcrossPasses() {
        let p0 = "float f = 0.025;\nvoid mainImage(out vec4 o, in vec2 fc){ o = vec4(f); }"
        let p1 = "float f = 0.035;\nvoid mainImage(out vec4 o, in vec2 fc){ o = vec4(f); }"
        let out = GLSLPassNamespace.namespace([p0, p1])
        XCTAssertTrue(out[0].contains("float p0_f = 0.025;"))
        XCTAssertTrue(out[1].contains("float p1_f = 0.035;"))
        XCTAssertTrue(out[0].contains("vec4(p0_f)"))
        XCTAssertTrue(out[1].contains("vec4(p1_f)"))
    }

    /// `const` vs non-`const` counts as a differing body (wXffDH's `pi`) — still namespaced per pass.
    func test_namespacesGlobalDifferingOnlyInConstQualifier() {
        let p0 = "float pi = 3.14159;\nvoid mainImage(out vec4 o, in vec2 fc){ o = vec4(pi); }"
        let p1 = "const float pi = 3.14159;\nvoid mainImage(out vec4 o, in vec2 fc){ o = vec4(pi); }"
        let out = GLSLPassNamespace.namespace([p0, p1])
        XCTAssertTrue(out[0].contains("float p0_pi = 3.14159;"))
        XCTAssertTrue(out[1].contains("const float p1_pi = 3.14159;"))
    }

    /// An IDENTICAL global across passes is left untouched — GLSLFunctionDedup keeps one shared
    /// file-scope copy (namespacing it would break passes that reference it without redefining it).
    func test_leavesIdenticalGlobalAloneForDedup() {
        let p = "const float TAU = 6.2831;\nvoid mainImage(out vec4 o, in vec2 fc){ o = vec4(TAU); }"
        let out = GLSLPassNamespace.namespace([p, p])
        XCTAssertEqual(out, [p, p])
    }

    /// A LOCAL variable (inside a function body, depth > 0) must never be treated as a top-level
    /// global — even with the same name and a differing initializer across passes.
    func test_doesNotNamespaceLocalVariable() {
        let p0 = "void mainImage(out vec4 o, in vec2 fc){ float f = 0.025; o = vec4(f); }"
        let p1 = "void mainImage(out vec4 o, in vec2 fc){ float f = 0.035; o = vec4(f); }"
        let out = GLSLPassNamespace.namespace([p0, p1])
        XCTAssertEqual(out, [p0, p1])
    }

    /// `else if (...)` has two words before `(`, so the header regex can mis-read it as a function
    /// named `if` — and with Allman braces (`{` on the next line) the misread is live. Control
    /// keywords are never function names: the scanner must exclude them so `if` is NEVER renamed.
    func test_doesNotNamespaceElseIfKeyword() {
        let p0 = "void mainImage(out vec4 o, in vec2 fc)\n{\n    if (fc.x > 0.0)\n    {\n        o = vec4(1.0);\n    }\n    else if (fc.y > 0.0)\n    {\n        o = vec4(2.0);\n    }\n}"
        let p1 = "void mainImage(out vec4 o, in vec2 fc)\n{\n    if (fc.x > 0.0)\n    {\n        o = vec4(3.0);\n    }\n    else if (fc.y > 0.0)\n    {\n        o = vec4(4.0);\n    }\n}"
        let out = GLSLPassNamespace.namespace([p0, p1])
        XCTAssertFalse(out[0].contains("p0_if"))
        XCTAssertFalse(out[1].contains("p1_if"))
        XCTAssertFalse(out[0].contains("else p0_if"))
    }

    /// M2 end-to-end: comma globals colliding across passes with differing values are ALL renamed.
    func test_commaGlobals_collidingAcrossPasses_allRenamed_M2() {
        let out = GLSLPassNamespace.namespace([
            "float a = 1., b = 2.;\nfloat u(){ return a + b; }",
            "float a = 3., b = 4.;\nfloat v(){ return a + b; }",
        ])
        XCTAssertTrue(out[0].contains("p0_a") && out[0].contains("p0_b"), out[0])
        XCTAssertTrue(out[1].contains("p1_a") && out[1].contains("p1_b"), out[1])
    }
}
