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

    func test_skillSources_includeCorpusCatalog_onlyOnGenerationPath() {
        // The 38K corpus catalog must be wired into Remix generation (it's invisible to the
        // tool-stripped subprocess otherwise). It is deliberately NOT on ShaderAssist's sources.
        XCTAssertTrue(RemixPrompt.skillSources.contains { $0.name == "arsonrivvers_technique_catalog" },
                      "corpus catalog missing from Remix skill sources")
        XCTAssertFalse(SkillPreamble.defaultSources.contains { $0.name == "arsonrivvers_technique_catalog" },
                       "catalog should stay off the ShaderAssist path")
    }

    func test_skillSources_catalogIsLast_soCoreSkillsSurviveTruncation() {
        // Descending priority: the catalog (deep reference) must be last so a future ARG_MAX
        // truncation drops it before the core skills.
        XCTAssertEqual(RemixPrompt.skillSources.last?.name, "arsonrivvers_technique_catalog")
    }

    // M39 — every skill source must have a bundled copy so PUBLIC installs (no ~/.claude) get the
    // full knowledge, not the tiny primer.
    func test_everySkillSource_hasABundledCopy() {
        for src in RemixPrompt.skillSources + SkillPreamble.defaultSources {
            XCTAssertNotNil(Bundle.main.url(forResource: src.name, withExtension: "md"),
                            "no bundled copy for skill source '\(src.name)'")
        }
    }

    // M39 — with the user path absent (a public machine), the bundled copy loads — and the full
    // Remix set stays under the ARG_MAX ceiling (no silent truncation).
    func test_bundledSkills_loadWithoutUserPaths_andWithoutTruncation() {
        let publicSources = RemixPrompt.skillSources.map {
            SkillPreamble.SkillSource(name: $0.name, userPath: "/nonexistent/\($0.name).md")
        }
        let out = SkillPreamble.load(sources: publicSources)
        XCTAssertNotEqual(out, SkillPreamble.fallback, "public installs must not fall back to the primer")
        XCTAssertTrue(out.contains("## Skill: arsonrivvers_technique_catalog"), "catalog must survive")
        XCTAssertLessThan(out.count, SkillPreamble.defaultCap, "preamble must never hit the ARG_MAX ceiling")
    }

    func test_unknownSource_fallsBackToPrimer() {
        let out = SkillPreamble.load(sources: [.init(name: "no-such-skill", userPath: "/nonexistent")])
        XCTAssertEqual(out, SkillPreamble.fallback)
    }
}
