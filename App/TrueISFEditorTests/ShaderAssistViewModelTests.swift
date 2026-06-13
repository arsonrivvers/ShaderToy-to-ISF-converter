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
        let vm = ShaderAssistViewModel(binaryOverride: { nil }, providerOverride: provider)
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
        let vm = ShaderAssistViewModel(binaryOverride: { nil }, providerOverride: provider)
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

    func testToggleSelectionByIdeaID() {
        let vm = ShaderAssistViewModel(binaryOverride: { nil }, providerOverride: nil)
        vm.toggleIdeaSelection("speed")
        XCTAssertEqual(vm.selectedIdeaIDs, ["speed"])
        vm.toggleIdeaSelection("speed")
        XCTAssertTrue(vm.selectedIdeaIDs.isEmpty)
    }

    func testApplySelectedBlocksWhenSourceChanged() async {
        let idea = AIIdea(id: "speed", title: "Speed", detail: "Expose speed",
                          kind: "make-interactive", lines: [3], impact: "Playable")
        let provider = FakeAssistProvider([.success(#"{"goal":"Expose controls","ideas":[{"id":"speed","title":"Speed","detail":"Expose speed","kind":"make-interactive","lines":[3],"impact":"Playable"}]}"#)])
        let vm = ShaderAssistViewModel(binaryOverride: { nil }, providerOverride: provider)
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

    func testApplySelectedProducesApplyPreview() async {
        let idea = AIIdea(id: "speed", title: "Speed", detail: "Expose speed",
                          kind: "make-interactive", lines: [3], impact: "Playable")
        let source = "/*{}*/\nvoid main(){}"
        let provider = FakeAssistProvider([.success(#"{"explanation":"Added speed","replacementSource":"/*{}*/\nvoid main(){ gl_FragColor = vec4(1.0); }","changedLines":[2]}"#)])
        let vm = ShaderAssistViewModel(binaryOverride: { nil }, providerOverride: provider)
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
        let vm = ShaderAssistViewModel(binaryOverride: { nil }, providerOverride: provider)
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
