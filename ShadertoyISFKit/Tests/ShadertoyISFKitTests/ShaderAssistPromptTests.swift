import XCTest
@testable import ShadertoyISFKit
final class ShaderAssistPromptTests: XCTestCase {
    func testUserPromptHasNumberedSourceAndDiagnostics() {
        let src = "void main(){\n  gl_FragColor = vec4(1.0);\n}"
        let diags = [Diagnostic.compiler(message: "ERROR: 2: bad", line: 2)]
        let p = ShaderAssistPrompt.user(task: .diagnoseAndFix, source: src, diagnostics: diags)
        XCTAssertTrue(p.contains("1: void main(){")); XCTAssertTrue(p.contains("ERROR: 2: bad"))
    }
    func testSystemNamesBothSkillsAndJSONOnly() {
        let s = ShaderAssistPrompt.system(for: .diagnoseAndFix)
        XCTAssertTrue(s.contains("isf-shader-development")); XCTAssertTrue(s.contains("shader-dev"))
        XCTAssertTrue(s.lowercased().contains("json")); XCTAssertTrue(s.contains("\"edits\""))
    }
    func testSuggestionsSystemHasIdeasSchema() { XCTAssertTrue(ShaderAssistPrompt.system(for: .suggestions(goal: "Improve motion")).contains("\"ideas\"")) }

    func testGoalSystemHasGoalsSchema() {
        let s = ShaderAssistPrompt.system(for: .suggestionGoals)
        XCTAssertTrue(s.contains("\"goals\""))
        XCTAssertTrue(s.contains("4-5"))
        XCTAssertTrue(s.contains("whyThisShader"))
    }

    func testScopedSuggestionsPromptIncludesGoal() {
        let p = ShaderAssistPrompt.user(task: .suggestions(goal: "Expose controls"),
                                        source: "void main(){}",
                                        diagnostics: [])
        XCTAssertTrue(p.contains("Goal: Expose controls"))
        XCTAssertTrue(p.contains("1: void main(){}"))
    }

    func testResearchSystemHasIdeasSchemaAndSkillMining() {
        let s = ShaderAssistPrompt.system(for: .research(request: "analog video decay"))
        XCTAssertTrue(s.contains("\"ideas\""))
        XCTAssertTrue(s.contains("3-6"))
        XCTAssertTrue(s.contains("technique catalog"))
        XCTAssertTrue(s.contains("THIS"))   // must demand shader-specific application, not generic advice
    }

    func testResearchUserPromptIncludesRequestAndSource() {
        let p = ShaderAssistPrompt.user(task: .research(request: "analog video decay"),
                                        source: "void main(){}",
                                        diagnostics: [])
        XCTAssertTrue(p.contains("Request: analog video decay"))
        XCTAssertTrue(p.contains("1: void main(){}"))
    }

    func testApplyPromptIncludesSelectedIdeas() {
        let idea = AIIdea(id: "speed-slider", title: "Expose speed", detail: "Make speed live",
                          kind: "make-interactive", lines: [23], impact: "Playable speed")
        let p = ShaderAssistPrompt.user(task: .applySuggestions(goal: "Expose controls", selectedIdeas: [idea]),
                                        source: "/*{}*/\nvoid main(){}",
                                        diagnostics: [])
        XCTAssertTrue(p.contains("Goal: Expose controls"))
        XCTAssertTrue(p.contains("speed-slider"))
        XCTAssertTrue(p.contains("replacementSource"))
    }
}
