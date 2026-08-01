import XCTest
import ShadertoyISFKit

@MainActor
final class ShaderAssistViewModelTests: XCTestCase {
    private func claudeRunner(response: String) throws -> ClaudeCodeRunner {
        let assistantObject: [String: Any] = [
            "type": "assistant",
            "message": [
                "id": "m1", "stop_reason": "end_turn",
                "content": [["type": "text", "text": response]]
            ]
        ]
        let assistantLine = String(
            data: try JSONSerialization.data(withJSONObject: assistantObject), encoding: .utf8
        )!
        let resultObject: [String: Any] = [
            "type": "result", "is_error": false, "result": response, "duration_ms": 1200.0,
        ]
        let resultLine = String(
            data: try JSONSerialization.data(withJSONObject: resultObject), encoding: .utf8
        )!
        let stream = [
            #"{"type":"system","subtype":"init","session_id":"s1","model":"sonnet"}"#,
            #"{"type":"stream_event","event":{"type":"content_block_start","index":0}}"#,
            #"{"type":"stream_event","message_id":"m1","event":{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"partial"}}}"#,
            #"{"type":"stream_event","event":{"type":"content_block_stop","index":0}}"#,
            assistantLine,
            resultLine,
        ].joined(separator: "\n")
        return ClaudeCodeRunner(
            binary: URL(fileURLWithPath: "/x/claude"),
            process: { ClaudeCodeRunnerTests.FakeProcess(stdout: stream, exitCode: 0, stderr: "") }
        )
    }

    private func assertLegacyTelemetry(
        _ vm: ShaderAssistViewModel,
        response: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(vm.eventCount, 3, file: file, line: line)
        XCTAssertEqual(vm.transcript, ["session started · sonnet", response, "done in 1.2s"],
                       file: file, line: line)
    }

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

    func testClaudePartialMessagesPreserveQuickGoalsParsingAndLegacyTelemetry() async throws {
        let response = #"{"goals":[{"id":"motion","title":"Add motion","detail":"Animate it","kind":"design","whyThisShader":"Static shader"}]}"#
        let vm = ShaderAssistViewModel(providerOverride: try claudeRunner(response: response))
        vm.requestSuggestionGoals(source: "/*{}*/\nvoid main(){}", diagnostics: [])
        await settle()
        guard case .suggestionGoals(let result) = vm.state else {
            return XCTFail("expected suggestionGoals, got \(vm.state)")
        }
        XCTAssertEqual(result.goals.first?.id, "motion")
        assertLegacyTelemetry(vm, response: response)
    }

    func testClaudePartialMessagesPreserveSuggestionsParsingAndLegacyTelemetry() async throws {
        let response = #"{"goal":"Expose controls","ideas":[{"id":"speed","title":"Speed","detail":"Expose speed","kind":"make-interactive","lines":[3],"impact":"Playable"}]}"#
        let vm = ShaderAssistViewModel(providerOverride: try claudeRunner(response: response))
        vm.chooseSuggestionGoal("Expose controls", source: "/*{}*/\nvoid main(){}", diagnostics: [])
        await settle()
        guard case .suggestions(let result) = vm.state else {
            return XCTFail("expected suggestions, got \(vm.state)")
        }
        XCTAssertEqual(result.ideas.first?.id, "speed")
        XCTAssertEqual(vm.lastSuggestions, result)
        assertLegacyTelemetry(vm, response: response)
    }

    func testClaudePartialMessagesPreserveRewriteParsingAndLegacyTelemetry() async throws {
        let response = #"{"explanation":"Done","replacementSource":"/*{}*/\nvoid main(){ gl_FragColor = vec4(1.0); }","changedLines":[2]}"#
        let vm = ShaderAssistViewModel(providerOverride: try claudeRunner(response: response))
        let ideas = [AIIdea(id: "g1", title: "Add motion", detail: "animate it",
                            kind: "design", lines: nil, impact: nil)]
        vm.applySelectedGoals(ideas, source: "/*{}*/\nvoid main(){}", diagnostics: [])
        await settle()
        guard case .applyPreview(let result) = vm.state else {
            return XCTFail("expected applyPreview, got \(vm.state)")
        }
        XCTAssertEqual(result.explanation, "Done")
        assertLegacyTelemetry(vm, response: response)
    }

    func testClaudePartialMessagesPreserveDiagnoseParsingAndLegacyTelemetry() async throws {
        let response = #"{"explanation":"Fix it","edits":[{"fromLine":2,"toLine":2,"replacement":"void main(){}","rationale":"repair"}]}"#
        let vm = ShaderAssistViewModel(providerOverride: try claudeRunner(response: response))
        vm.run(.diagnoseAndFix, source: "/*{}*/\nvoid main(){}", diagnostics: [])
        await settle()
        guard case .fix(let result) = vm.state else {
            return XCTFail("expected fix, got \(vm.state)")
        }
        XCTAssertEqual(result.explanation, "Fix it")
        XCTAssertEqual(result.edits.first?.fromLine, 2)
        assertLegacyTelemetry(vm, response: response)
    }

    func testClaudePartialMessagesPreserveResearchParsingAndLegacyTelemetry() async throws {
        let response = #"{"goal":"analog decay","ideas":[{"id":"phosphor","title":"Phosphor lag","detail":"Decay","kind":"technique","lines":[12],"impact":"High"}]}"#
        let vm = ShaderAssistViewModel(providerOverride: try claudeRunner(response: response))
        vm.researchUpgrades(request: "analog decay", source: "/*{}*/\nvoid main(){}", diagnostics: [])
        await settle()
        guard case .suggestions(let result) = vm.state else {
            return XCTFail("expected suggestions, got \(vm.state)")
        }
        XCTAssertEqual(result.ideas.first?.id, "phosphor")
        assertLegacyTelemetry(vm, response: response)
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

    /// M33 — dismissing the goal sheet must cancel ITS running goals call (which burns a ~30s CLI
    /// run and keeps the main buttons disabled) …
    func testCancelSuggestionGoalsIfRunning_cancelsTheGoalsCall() async {
        let vm = ShaderAssistViewModel(providerOverride: HangingAssistProvider())
        vm.requestSuggestionGoals(source: "/*{}*/\nvoid main(){}", diagnostics: [])
        if case .running(.suggestionGoals) = vm.state {} else {
            return XCTFail("precondition: expected running(.suggestionGoals), got \(vm.state)")
        }
        vm.cancelSuggestionGoalsIfRunning()
        if case .idle = vm.state {} else { XCTFail("expected idle after cancel, got \(vm.state)") }
    }

    /// … but must NOT touch any other state (e.g. the rewrite the user just started via Apply).
    func testCancelSuggestionGoalsIfRunning_isNoOpForOtherStates() async {
        let vm = ShaderAssistViewModel(providerOverride: nil)
        vm.cancelSuggestionGoalsIfRunning()
        if case .idle = vm.state {} else { XCTFail("idle must stay idle") }
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

    // MARK: A3 — fix-flow fingerprint + document-switch reset

    func testFixResultCarriesSourceFingerprint() async {
        let provider = FakeAssistProvider([.success(#"{"explanation":"E","edits":[{"fromLine":1,"toLine":1,"replacement":"x","rationale":"r"}]}"#)])
        let vm = ShaderAssistViewModel(providerOverride: provider)
        let src = "/*{}*/\nvoid main(){}"
        vm.run(.diagnoseAndFix, source: src, diagnostics: [])
        await settle()
        XCTAssertEqual(vm.fixSourceFingerprint, ShaderAssistViewModel.sourceFingerprint(src))
    }

    func testResetForDocumentSwitchClearsFixAndRetry() async {
        let provider = FakeAssistProvider([.success(#"{"explanation":"E","edits":[]}"#)])
        let vm = ShaderAssistViewModel(providerOverride: provider)
        vm.run(.diagnoseAndFix, source: "/*{}*/\nvoid main(){}", diagnostics: [])
        await settle()
        vm.resetForDocumentSwitch()
        if case .idle = vm.state {} else { XCTFail("expected idle, got \(vm.state)") }
        XCTAssertNil(vm.fixSourceFingerprint)
        XCTAssertFalse(vm.canRetry)
    }

    // MARK: Research tab

    func testResearchUpgradesLandsInSuggestionsState() async {
        let provider = FakeAssistProvider([.success(#"{"goal":"analog decay","ideas":[{"id":"phosphor","title":"Phosphor-lag feedback","detail":"Per-channel decay in PASS 2","kind":"technique","lines":[12],"impact":"High"}]}"#)])
        let vm = ShaderAssistViewModel(providerOverride: provider)
        vm.researchUpgrades(request: "  analog decay  ", source: "/*{}*/\nvoid main(){}", diagnostics: [])
        await settle()
        XCTAssertEqual(vm.activeSuggestionGoal, "analog decay")   // trimmed
        if case .suggestions(let r) = vm.state {
            XCTAssertEqual(r.ideas[0].id, "phosphor")
            XCTAssertEqual(vm.lastSuggestions, r)
        } else {
            XCTFail("expected suggestions, got \(vm.state)")
        }
        XCTAssertTrue(provider.prompts[0].contains("analog decay"))
        XCTAssertTrue(provider.prompts[0].contains("Research upgrade directions"))
    }

    func testResearchUpgradesBlankRequestIsNoOp() async {
        let vm = ShaderAssistViewModel(providerOverride: nil)
        vm.researchUpgrades(request: "   ", source: "/*{}*/\nvoid main(){}", diagnostics: [])
        await settle()
        if case .idle = vm.state {} else { XCTFail("expected idle, got \(vm.state)") }
        XCTAssertNil(vm.activeSuggestionGoal)
    }

    // MARK: Timeout resilience

    /// The 240s cap discarded a COMPLETED 239.3s suggestions rewrite; the run timeout must stay at
    /// the Remix-proven 420s margin and reach the provider.
    func testRunPassesRaisedTimeoutToProvider() async {
        XCTAssertEqual(ShaderAssistViewModel.runTimeout, 420)
        let provider = FakeAssistProvider([.success(#"{"goals":[]}"#)])
        let vm = ShaderAssistViewModel(providerOverride: provider)
        vm.requestSuggestionGoals(source: "/*{}*/\nvoid main(){}", diagnostics: [])
        await settle()
        XCTAssertEqual(provider.lastTimeout, 420)
    }

    func testRetryLastRunRerunsSameRequestAfterError() async {
        let provider = FakeAssistProvider([
            .failure(AssistRunError.timedOut(partialStdout: "")),
            .success(#"{"goal":"Expose controls","ideas":[{"id":"speed","title":"Speed","detail":"d","kind":"perf","lines":null,"impact":null}]}"#),
        ])
        let vm = ShaderAssistViewModel(providerOverride: provider)
        vm.chooseSuggestionGoal("Expose controls", source: "/*{}*/\nvoid main(){}", diagnostics: [])
        await settle()
        if case .error(let m) = vm.state { XCTAssertTrue(m.contains("timed out")) }
        else { return XCTFail("expected error, got \(vm.state)") }
        XCTAssertTrue(vm.canRetry)
        vm.retryLastRun()
        await settle()
        if case .suggestions(let r) = vm.state { XCTAssertEqual(r.ideas[0].id, "speed") }
        else { XCTFail("expected suggestions after retry, got \(vm.state)") }
        XCTAssertEqual(provider.prompts.count, 2)
        XCTAssertEqual(provider.prompts[0], provider.prompts[1])   // identical re-run
    }

    func testRetryIsNoOpBeforeAnyRun() {
        let vm = ShaderAssistViewModel(providerOverride: nil)
        XCTAssertFalse(vm.canRetry)
        vm.retryLastRun()
        if case .idle = vm.state {} else { XCTFail("expected idle") }
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

    // MARK: Run liveness

    func testRunResetsAndCountsStreamEvents() async {
        let provider = FakeAssistProvider(
            [
                .success(#"{"goals":[]}"#),
                .success(#"{"goals":[]}"#),
            ],
            eventsPerRun: [["raw event one", "raw event two", "raw event three"], []]
        )
        let vm = ShaderAssistViewModel(providerOverride: provider)

        vm.run(.suggestionGoals, source: "/*{}*/\nvoid main(){}", diagnostics: [])
        XCTAssertNotNil(vm.runStartDate)
        XCTAssertEqual(vm.eventCount, 0)
        XCTAssertNil(vm.lastEventDate)

        await settle()
        XCTAssertEqual(vm.eventCount, 3)
        XCTAssertNotNil(vm.lastEventDate)

        vm.run(.suggestionGoals, source: "/*{}*/\nvoid main(){}", diagnostics: [])
        XCTAssertNotNil(vm.runStartDate)
        XCTAssertEqual(vm.eventCount, 0)
        XCTAssertNil(vm.lastEventDate)
    }

    func testClockString() {
        XCTAssertEqual(AssistProgressStrip.clock(0), "0s")
        XCTAssertEqual(AssistProgressStrip.clock(45), "45s")
        XCTAssertEqual(AssistProgressStrip.clock(134), "2m 14s")
        XCTAssertEqual(AssistProgressStrip.clock(3701), "61m 41s")
    }

    func testQuietDurationUsesRunStartUntilFirstEvent() {
        let start = Date(timeIntervalSince1970: 100)
        let event = Date(timeIntervalSince1970: 125)
        let now = Date(timeIntervalSince1970: 141)

        XCTAssertEqual(
            AssistProgressStrip.quietDuration(runStartDate: start, lastEventDate: nil, now: now),
            41
        )
        XCTAssertEqual(
            AssistProgressStrip.quietDuration(runStartDate: start, lastEventDate: event, now: now),
            16
        )
    }

    func testCancelledRunCannotReportLateEventsIntoNextRun() async {
        let provider = ControllableAssistProvider()
        let vm = ShaderAssistViewModel(providerOverride: provider)

        vm.run(.suggestionGoals, source: "/*{}*/\nvoid main(){}", diagnostics: [])
        await waitForEventSinks(1, provider: provider)

        vm.run(.suggestionGoals, source: "/*{}*/\nvoid main(){}", diagnostics: [])
        await waitForEventSinks(2, provider: provider)

        provider.eventSinks[0]("late event from cancelled run")
        provider.eventSinks[1]("current run event")
        await settle()

        XCTAssertEqual(vm.eventCount, 1)
        XCTAssertNotNil(vm.lastEventDate)
        vm.cancel()
    }

    func testCancelledRunIgnoresLateEvents() async {
        let provider = ControllableAssistProvider()
        let vm = ShaderAssistViewModel(providerOverride: provider)

        vm.run(.suggestionGoals, source: "/*{}*/\nvoid main(){}", diagnostics: [])
        await waitForEventSinks(1, provider: provider)
        vm.cancel()

        provider.eventSinks[0]("late event after explicit cancel")
        await settle()

        XCTAssertEqual(vm.eventCount, 0)
        XCTAssertNil(vm.lastEventDate)
        if case .idle = vm.state {} else { XCTFail("expected idle after cancel") }
    }
}

@MainActor
/// Never returns until cancelled — simulates a long CLI run for cancellation tests.
private final class HangingAssistProvider: AssistProvider {
    func run(prompt: String, system: String, model: String?, timeout: TimeInterval,
             onEvent: @escaping @Sendable (String) -> Void) async throws -> String {
        try await Task.sleep(nanoseconds: 60_000_000_000)
        throw CancellationError()
    }
}

private final class FakeAssistProvider: AssistProvider {
    var scripts: [Result<String, Error>]
    var eventsPerRun: [[String]]
    private(set) var prompts: [String] = []
    private(set) var systems: [String] = []
    private(set) var lastTimeout: TimeInterval = 0

    init(_ scripts: [Result<String, Error>], eventsPerRun: [[String]] = []) {
        self.scripts = scripts
        self.eventsPerRun = eventsPerRun
    }

    func run(prompt: String, system: String, model: String?, timeout: TimeInterval,
             onEvent: @escaping @Sendable (String) -> Void) async throws -> String {
        prompts.append(prompt)
        systems.append(system)
        lastTimeout = timeout
        if !eventsPerRun.isEmpty {
            eventsPerRun.removeFirst().forEach(onEvent)
        }
        let result = scripts.removeFirst()
        switch result {
        case .success(let text):
            return text
        case .failure(let error):
            throw error
        }
    }
}

@MainActor
private final class ControllableAssistProvider: AssistProvider {
    private(set) var eventSinks: [@Sendable (String) -> Void] = []

    func run(prompt: String, system: String, model: String?, timeout: TimeInterval,
             onEvent: @escaping @Sendable (String) -> Void) async throws -> String {
        eventSinks.append(onEvent)
        try await Task.sleep(nanoseconds: 60_000_000_000)
        return #"{"goals":[]}"#
    }
}

@MainActor
private func waitForEventSinks(_ count: Int, provider: ControllableAssistProvider) async {
    for _ in 0..<100 where provider.eventSinks.count < count {
        await Task.yield()
        try? await Task.sleep(nanoseconds: 1_000_000)
    }
    XCTAssertGreaterThanOrEqual(provider.eventSinks.count, count)
}

private func settle() async {
    await Task.yield()
    try? await Task.sleep(nanoseconds: 20_000_000)
}
