import XCTest
@testable import TrueISFEditor

final class RemixPromptTests: XCTestCase {
    func test_crossover_user_includesBothParents_mode_steer_directive() {
        let p = RemixPrompt.user(parents: [("A", "/*{A}*/ a"), ("B", "/*{B}*/ b")],
                                 mode: .crossover, steer: "wavy", directive: "lean chaotic")
        XCTAssertTrue(p.contains("/*{A}*/ a"))
        XCTAssertTrue(p.contains("/*{B}*/ b"))
        XCTAssertTrue(p.contains("PARENT A"))
        XCTAssertTrue(p.contains("PARENT B"))
        XCTAssertTrue(p.lowercased().contains("crossover") || p.lowercased().contains("breed"))
        XCTAssertTrue(p.contains("wavy"))
        XCTAssertTrue(p.contains("lean chaotic"))
    }

    func test_mutate_user_singleParent() {
        let p = RemixPrompt.user(parents: [("A", "/*{A}*/ a")], mode: .mutate, steer: "", directive: "lean minimal")
        XCTAssertTrue(p.contains("/*{A}*/ a"))
        XCTAssertTrue(p.lowercased().contains("mutate") || p.lowercased().contains("vary"))
    }

    func test_user_injectsSettingsPromptLines() {
        var s = RemixCrossoverSettings(); s.balance = 0.7
        let p = RemixPrompt.user(parents: [("A", "a"), ("B", "b")],
                                 mode: .crossover, steer: "", directive: "d", settings: s)
        XCTAssertTrue(p.contains("70%"))           // balance line injected
    }

    func test_user_labelOrderFollowsArrayOrder_butLabelsAreExplicit() {
        // B-first presentation; labels still name the right source.
        let p = RemixPrompt.user(parents: [("B", "srcB"), ("A", "srcA")],
                                 mode: .crossover, steer: "", directive: "d")
        let bIdx = p.range(of: "PARENT B")!.lowerBound
        let aIdx = p.range(of: "PARENT A")!.lowerBound
        XCTAssertLessThan(bIdx, aIdx)              // printed B before A
        XCTAssertTrue(p.contains("srcB"))
        XCTAssertTrue(p.contains("srcA"))
    }
    func test_system_loadsSkillsOrFallback_andDemandsRawISF() {
        let s = RemixPrompt.system()
        XCTAssertFalse(s.isEmpty)
        XCTAssertTrue(s.contains("ISF"))
    }

    func test_skillPaths_includeCorpusCatalog_onlyOnGenerationPath() {
        // The 38K corpus catalog must be wired into Remix generation (it's invisible to the
        // tool-stripped subprocess otherwise). It is deliberately NOT on ShaderAssist's paths.
        XCTAssertTrue(RemixPrompt.skillPaths.contains { $0.hasSuffix("arsonrivvers_technique_catalog.md") },
                      "corpus catalog missing from Remix load paths")
        XCTAssertFalse(SkillPreamble.defaultPaths.contains { $0.hasSuffix("arsonrivvers_technique_catalog.md") },
                       "catalog should stay off the ShaderAssist path")
    }

    func test_skillPaths_catalogIsLast_soCoreSkillsSurviveTruncation() {
        // Descending priority: the catalog (deep reference) must be last so a future ARG_MAX
        // truncation drops it before the core skills.
        XCTAssertTrue(RemixPrompt.skillPaths.last?.hasSuffix("arsonrivvers_technique_catalog.md") == true)
    }
}
