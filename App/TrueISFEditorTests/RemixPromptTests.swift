import XCTest
@testable import TrueISFEditor

final class RemixPromptTests: XCTestCase {
    func test_crossover_user_includesBothParents_mode_steer_directive() {
        let p = RemixPrompt.user(parents: ["/*{A}*/ a", "/*{B}*/ b"],
                                 mode: .crossover, steer: "wavy", directive: "lean chaotic")
        XCTAssertTrue(p.contains("/*{A}*/ a"))
        XCTAssertTrue(p.contains("/*{B}*/ b"))
        XCTAssertTrue(p.lowercased().contains("crossover") || p.lowercased().contains("breed"))
        XCTAssertTrue(p.contains("wavy"))
        XCTAssertTrue(p.contains("lean chaotic"))
    }
    func test_mutate_user_singleParent() {
        let p = RemixPrompt.user(parents: ["/*{A}*/ a"], mode: .mutate, steer: "", directive: "lean minimal")
        XCTAssertTrue(p.contains("/*{A}*/ a"))
        XCTAssertTrue(p.lowercased().contains("mutate") || p.lowercased().contains("vary"))
    }
    func test_system_loadsSkillsOrFallback_andDemandsRawISF() {
        let s = RemixPrompt.system()
        XCTAssertFalse(s.isEmpty)
        XCTAssertTrue(s.contains("ISF"))
    }
}
