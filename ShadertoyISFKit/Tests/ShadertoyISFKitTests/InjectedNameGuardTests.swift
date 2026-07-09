import XCTest
@testable import ShadertoyISFKit

/// Task-1 triage class (tXfBz2): a user local `vec2 mouse = iMouse.xy` — the iMouse rule rewrites
/// the initializer to reference the ISF `mouse` input, which the just-declared local shadows
/// self-referentially → garbage camera → black. Guarded names are renamed BEFORE any uniform
/// rewriting, so injected references can never be shadowed.
final class InjectedNameGuardTests: XCTestCase {
    func test_userMouseLocal_renamedEverywhere() {
        let r = InjectedNameGuard.rewrite(
            passBodies: ["void mainImage(out vec4 O, in vec2 U){ vec2 mouse = iMouse.xy; O = vec4(mouse, 0, 1); }"],
            commonCode: "")
        XCTAssertTrue(r.passBodies[0].contains("vec2 usr_mouse = iMouse.xy"), r.passBodies[0])
        XCTAssertTrue(r.passBodies[0].contains("vec4(usr_mouse, 0, 1)"), r.passBodies[0])
        XCTAssertEqual(r.warnings.count, 1)
    }

    func test_commonHelperNamedTIME_renamedInPassToo() {
        let r = InjectedNameGuard.rewrite(
            passBodies: ["void mainImage(out vec4 O, in vec2 U){ O = vec4(TIME(1.)); }"],
            commonCode: "float TIME(float x){ return x; }")
        XCTAssertTrue(r.commonCode.contains("float usr_TIME(float x)"), r.commonCode)
        XCTAssertTrue(r.passBodies[0].contains("usr_TIME(1.)"), r.passBodies[0])
    }

    func test_nameOnlyInComment_notRenamed() {
        let src = "// mouse driven\nvoid mainImage(out vec4 O, in vec2 U){ O = vec4(1); }"
        let r = InjectedNameGuard.rewrite(passBodies: [src], commonCode: "")
        XCTAssertEqual(r.passBodies[0], src)
        XCTAssertTrue(r.warnings.isEmpty)
    }

    func test_noCollisions_identity() {
        let r = InjectedNameGuard.rewrite(
            passBodies: ["void mainImage(out vec4 O, in vec2 U){ O = vec4(1); }"],
            commonCode: "")
        XCTAssertTrue(r.warnings.isEmpty)
    }

    /// `iMouse` itself is NOT a guarded name — only the names our REWRITES inject.
    func test_iMouseUse_isNotAGuardTrigger() {
        let src = "void mainImage(out vec4 O, in vec2 U){ O = iMouse; }"
        let r = InjectedNameGuard.rewrite(passBodies: [src], commonCode: "")
        XCTAssertEqual(r.passBodies[0], src)
    }
}
