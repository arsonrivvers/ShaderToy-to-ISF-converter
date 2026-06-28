import XCTest
import ShadertoyISFKit

@MainActor
final class ShaderAssistViewModelTests: XCTestCase {
    func testEditMappingDerivesExpectedContains() {
        let src = "line one\n  vec4 c = texture2D(a, b);\nline three"
        let edit = AIEdit(fromLine: 2, toLine: 2, replacement: "  vec4 c = IMG_PIXEL(a, b);", rationale: "r")
        let te = ShaderAssistViewModel.textEdit(from: edit, source: src)
        XCTAssertEqual(te.fromLine, 2); XCTAssertEqual(te.toLine, 2)
        XCTAssertEqual(te.replacement, "  vec4 c = IMG_PIXEL(a, b);")
        XCTAssertNotNil(te.expectedContains)
        XCTAssertTrue("  vec4 c = texture2D(a, b);".contains(te.expectedContains!))
    }

    func testSuggestionGoalsTransition() async {
        let provider = FakeAssistProvider([.success(#"{"goals":[{"id":"motion","title":"Add motion","detail":"Animate it","kind":"design","whyThisShader":"Static shader"}]}"#)])
        let vm = ShaderAssistViewModel(providerOverride: provider)
        vm.requestSuggestionGoals(source: "/*{}*/\nvoid main(){}", diagnostics: [])
        await settle()
        if case .suggestionGoals(let result) = vm.state {
            XCTAssertEqual(result.goals[0].id, "motion")
        } else {
            XCTFail("expected suggestionGoals")
        }
    }

    func testChoosingGoalRunsScopedSuggestionsAndStoresFingerprint() async {
        let provider = FakeAssistProvider([.success(#"{"goal":"Expose controls","ideas":[{"id":"speed","title":"Speed","detail":"Expose speed","kind":"make-interactive","lines":[3],"impact":"Playable"}]}"#)])
        let vm = ShaderAssistViewModel(providerOverride: provider)
        vm.chooseSuggestionGoal("Expose controls", source: "/*{}*/\nvoid main(){}", diagnostics: [])
        await settle()
        XCTAssertEqual(vm.activeSuggestionGoal, "Expose controls")
        if case .suggestions(let result) = vm.state {
            XCTAssertEqual(result.goal, "Expose controls")
            XCTAssertEqual(result.ideas[0].id, "speed")
        } else {
            XCTFail("expected suggestions")
        }
    }

    func testCombineGoalsTrimsAndDropsBlanksPreservingOrder() {
        XCTAssertEqual(
            ShaderAssistViewModel.combineGoals(["  Add color  ", "", "Expose speed", "   "]),
            "Add color; Expose speed")
        XCTAssertEqual(ShaderAssistViewModel.combineGoals([]), "")
        XCTAssertEqual(ShaderAssistViewModel.combineGoals(["   ", ""]), "")
    }

    func testChoosingMultipleGoalsCombinesIntoOneSuggestionCall() async {
        let provider = FakeAssistProvider([.success(#"{"goal":"Add color; Expose speed","ideas":[{"id":"a","title":"A","detail":"d","kind":"creative","lines":[1],"impact":"x"}]}"#)])
        let vm = ShaderAssistViewModel(providerOverride: provider)
        vm.chooseSuggestionGoals(["Add color", "  ", "Expose speed"],
                                 source: "/*{}*/\nvoid main(){}", diagnostics: [])
        await settle()
        XCTAssertEqual(vm.activeSuggestionGoal, "Add color; Expose speed")
        if case .suggestions = vm.state {} else { XCTFail("expected suggestions") }
    }

    func testChoosingNoValidGoalsIsNoOp() async {
        let vm = ShaderAssistViewModel(providerOverride: nil)
        vm.chooseSuggestionGoals(["   ", ""], source: "/*{}*/\nvoid main(){}", diagnostics: [])
        await settle()
        XCTAssertNil(vm.activeSuggestionGoal)
        if case .idle = vm.state {} else { XCTFail("expected idle, got \(vm.state)") }
    }

    func testToggleSelectionByIdeaID() {
        let vm = ShaderAssistViewModel(providerOverride: nil)
        vm.toggleIdeaSelection("speed")
        XCTAssertEqual(vm.selectedIdeaIDs, ["speed"])
        vm.toggleIdeaSelection("speed")
        XCTAssertTrue(vm.selectedIdeaIDs.isEmpty)
    }

    func testApplySelectedBlocksWhenSourceChanged() async {
        let idea = AIIdea(id: "speed", title: "Speed", detail: "Expose speed",
                          kind: "make-interactive", lines: [3], impact: "Playable")
        let provider = FakeAssistProvider([.success(#"{"goal":"Expose controls","ideas":[{"id":"speed","title":"Speed","detail":"Expose speed","kind":"make-interactive","lines":[3],"impact":"Playable"}]}"#)])
        let vm = ShaderAssistViewModel(providerOverride: provider)
        vm.activeSuggestionGoal = "Expose controls"
        vm.lastSuggestions = AISuggestionsResult(goal: "Expose controls", ideas: [idea])
        vm.suggestionSourceFingerprint = ShaderAssistViewModel.sourceFingerprint("original")
        vm.toggleIdeaSelection("speed")
        vm.applySelectedSuggestions(source: "edited")
        await settle()
        if case .error(let message) = vm.state {
            XCTAssertTrue(message.contains("Shader changed"))
        } else {
            XCTFail("expected stale-source error")
        }
    }

    func testApplySelectedGoalsGoesStraightToApplyPreview() async {
        let source = "/*{}*/\nvoid main(){}"
        let provider = FakeAssistProvider([.success(#"{"explanation":"Done","replacementSource":"/*{}*/\nvoid main(){ gl_FragColor = vec4(1.0); }","changedLines":[2]}"#)])
        let vm = ShaderAssistViewModel(providerOverride: provider)
        let ideas = [AIIdea(id: "g1", title: "Add motion", detail: "animate it",
                            kind: "design", lines: nil, impact: nil)]
        vm.applySelectedGoals(ideas, source: source, diagnostics: [])
        await settle()
        XCTAssertEqual(vm.activeSuggestionGoal, "Add motion")
        if case .applyPreview(let r) = vm.state {
            XCTAssertEqual(r.explanation, "Done")
            XCTAssertEqual(vm.applyPreviewSourceFingerprint, ShaderAssistViewModel.sourceFingerprint(source))
        } else {
            XCTFail("expected applyPreview, got \(vm.state)")
        }
    }

    func testApplySelectedGoalsNoOpWhenEmpty() async {
        let vm = ShaderAssistViewModel(providerOverride: nil)
        vm.applySelectedGoals([], source: "/*{}*/\nvoid main(){}", diagnostics: [])
        await settle()
        if case .idle = vm.state {} else { XCTFail("expected idle, got \(vm.state)") }
    }

    func testApplySelectedProducesApplyPreview() async {
        let idea = AIIdea(id: "speed", title: "Speed", detail: "Expose speed",
                          kind: "make-interactive", lines: [3], impact: "Playable")
        let source = "/*{}*/\nvoid main(){}"
        let provider = FakeAssistProvider([.success(#"{"explanation":"Added speed","replacementSource":"/*{}*/\nvoid main(){ gl_FragColor = vec4(1.0); }","changedLines":[2]}"#)])
        let vm = ShaderAssistViewModel(providerOverride: provider)
        vm.activeSuggestionGoal = "Expose controls"
        vm.lastSuggestions = AISuggestionsResult(goal: "Expose controls", ideas: [idea])
        vm.suggestionSourceFingerprint = ShaderAssistViewModel.sourceFingerprint(source)
        vm.toggleIdeaSelection("speed")
        vm.applySelectedSuggestions(source: source)
        await settle()
        if case .applyPreview(let result) = vm.state {
            XCTAssertEqual(result.explanation, "Added speed")
            XCTAssertEqual(vm.applyPreviewSourceFingerprint, ShaderAssistViewModel.sourceFingerprint(source))
        } else {
            XCTFail("expected applyPreview")
        }
    }

    func testApplyRejectsReplacementWithoutISFHeader() async {
        let idea = AIIdea(id: "speed", title: "Speed", detail: "Expose speed",
                          kind: "make-interactive", lines: [3], impact: "Playable")
        let source = "/*{}*/\nvoid main(){}"
        let provider = FakeAssistProvider([.success(#"{"explanation":"Bad","replacementSource":"void main(){}","changedLines":[1]}"#)])
        let vm = ShaderAssistViewModel(providerOverride: provider)
        vm.activeSuggestionGoal = "Expose controls"
        vm.lastSuggestions = AISuggestionsResult(goal: "Expose controls", ideas: [idea])
        vm.suggestionSourceFingerprint = ShaderAssistViewModel.sourceFingerprint(source)
        vm.toggleIdeaSelection("speed")
        vm.applySelectedSuggestions(source: source)
        await settle()
        if case .error(let message) = vm.state {
            XCTAssertTrue(message.contains("valid ISF"))
        } else {
            XCTFail("expected invalid replacement error")
        }
    }

    func testApplyRejectsReplacementWithMalformedISFHeader() async {
        let idea = AIIdea(id: "speed", title: "Speed", detail: "Expose speed",
                          kind: "make-interactive", lines: [3], impact: "Playable")
        let source = "/*{}*/\nvoid main(){}"
        let provider = FakeAssistProvider([.success(#"{"explanation":"Bad","replacementSource":"/*{bad}*/\nvoid main(){}","changedLines":[1]}"#)])
        let vm = ShaderAssistViewModel(providerOverride: provider)
        vm.activeSuggestionGoal = "Expose controls"
        vm.lastSuggestions = AISuggestionsResult(goal: "Expose controls", ideas: [idea])
        vm.suggestionSourceFingerprint = ShaderAssistViewModel.sourceFingerprint(source)
        vm.toggleIdeaSelection("speed")
        vm.applySelectedSuggestions(source: source)
        await settle()
        if case .error(let message) = vm.state {
            XCTAssertTrue(message.contains("valid ISF"))
        } else {
            XCTFail("expected invalid replacement error")
        }
    }
}

@MainActor
private final class FakeAssistProvider: AssistProvider {
    var scripts: [Result<String, Error>]
    private(set) var prompts: [String] = []

    init(_ scripts: [Result<String, Error>]) {
        self.scripts = scripts
    }

    func run(prompt: String, system: String, model: String?, timeout: TimeInterval,
             onEvent: @escaping @Sendable (String) -> Void) async throws -> String {
        prompts.append(prompt)
        let result = scripts.removeFirst()
        switch result {
        case .success(let text):
            return text
        case .failure(let error):
            throw error
        }
    }
}

private func settle() async {
    await Task.yield()
    try? await Task.sleep(nanoseconds: 20_000_000)
}
