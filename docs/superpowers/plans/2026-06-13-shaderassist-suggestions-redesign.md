# ShaderAssist Suggestions Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the main-editor ShaderAssist Suggestions redesign: tailored goals, scoped selectable suggestions, one coordinated apply call, and a user-gated in-memory editor diff.

**Architecture:** Extend the existing ShaderAssist stack rather than adding a new LLM subsystem. `ShadertoyISFKit` owns shared task/result types, prompts, and parsing; `ShaderAssistViewModel` owns workflow state and stale-source guards; SwiftUI views render the goal sheet, selectable suggestions, and apply preview; `EditorViewModel` owns the final in-memory source replacement.

**Tech Stack:** Swift 5/6, SwiftUI, XCTest, SwiftPM (`ShadertoyISFKit`), XcodeGen, native macOS app, existing Claude/Codex CLI runners.

---

## File Map

- Modify: `ShadertoyISFKit/Sources/ShadertoyISFKit/ShaderAssist/ShaderAssistTypes.swift`
  Add goal/apply result types, stable suggestion IDs, and associated `ShaderAssistTask` cases.
- Modify: `ShadertoyISFKit/Sources/ShadertoyISFKit/ShaderAssist/ShaderAssistPrompt.swift`
  Add goal, scoped suggestions, and apply prompt branches.
- Modify: `ShadertoyISFKit/Sources/ShadertoyISFKit/ShaderAssist/ShaderAssistResponseParser.swift`
  Add `suggestionGoals` and `applyResult` parse entry points.
- Modify tests:
  - `ShadertoyISFKit/Tests/ShadertoyISFKitTests/ShaderAssistTypesTests.swift`
  - `ShadertoyISFKit/Tests/ShadertoyISFKitTests/ShaderAssistPromptTests.swift`
  - `ShadertoyISFKit/Tests/ShadertoyISFKitTests/ShaderAssistResponseParserTests.swift`
- Modify: `App/TrueISFEditor/ShaderAssist/ShaderAssistViewModel.swift`
  Add workflow state, fake-provider injection, source fingerprints, selected IDs, apply preview handling.
- Modify: `App/TrueISFEditorTests/ShaderAssistViewModelTests.swift`
  Add fake-provider workflow tests.
- Modify: `App/TrueISFEditor/EditorViewModel.swift`
  Add full-source AI replacement method.
- Create: `App/TrueISFEditor/Views/SuggestionGoalSheet.swift`
  Focused first-run goal chooser.
- Modify: `App/TrueISFEditor/Views/SuggestionsPanel.swift`
  Convert flat advisory cards to selectable scoped suggestions.
- Create: `App/TrueISFEditor/Views/ApplyPreviewPanel.swift`
  User-gated before/after source review.
- Modify: `App/TrueISFEditor/Views/EditorScreen.swift`
  Wire sheet, active goal, rerun/change/start-over, selectable suggestions, and apply preview into ShaderAssist section.

---

## Task 1: Shared ShaderAssist Types

**Files:**
- Modify: `ShadertoyISFKit/Sources/ShadertoyISFKit/ShaderAssist/ShaderAssistTypes.swift`
- Modify: `ShadertoyISFKit/Tests/ShadertoyISFKitTests/ShaderAssistTypesTests.swift`

- [ ] **Step 1: Write failing type tests**

Replace `testDecodeSuggestions` in `ShaderAssistTypesTests.swift` with these tests while keeping `testDecodeFixResult`:

```swift
func testDecodeSuggestionGoals() throws {
    let json = #"{"goals":[{"id":"expose-controls","title":"Expose controls","detail":"Turn constants into INPUTS","kind":"make-interactive","whyThisShader":"The shader has hardcoded speed constants."}]}"#
    let r = try JSONDecoder().decode(AISuggestionGoalsResult.self, from: Data(json.utf8))
    XCTAssertEqual(r.goals.count, 1)
    XCTAssertEqual(r.goals[0].id, "expose-controls")
    XCTAssertEqual(r.goals[0].whyThisShader, "The shader has hardcoded speed constants.")
}

func testDecodeSuggestionsWithGoalStableIDsAndImpact() throws {
    let json = #"{"goal":"Expose controls","ideas":[{"id":"speed-slider","title":"Expose speed","detail":"Line 23 hardcodes rate","kind":"make-interactive","lines":[23],"impact":"Makes speed playable live."}]}"#
    let r = try JSONDecoder().decode(AISuggestionsResult.self, from: Data(json.utf8))
    XCTAssertEqual(r.goal, "Expose controls")
    XCTAssertEqual(r.ideas.count, 1)
    XCTAssertEqual(r.ideas[0].id, "speed-slider")
    XCTAssertEqual(r.ideas[0].impact, "Makes speed playable live.")
}

func testDecodeLegacySuggestionsStillWorks() throws {
    let json = #"{"ideas":[{"title":"Expose speed","detail":"line 23 hardcodes rate","kind":"make-interactive","lines":[23]}]}"#
    let r = try JSONDecoder().decode(AISuggestionsResult.self, from: Data(json.utf8))
    XCTAssertEqual(r.goal, "")
    XCTAssertEqual(r.ideas[0].id, "Expose speed")
    XCTAssertNil(r.ideas[0].impact)
}

func testDecodeApplyResult() throws {
    let json = #"{"explanation":"Added controls","replacementSource":"/*{}*/\nvoid main(){}","changedLines":[3,7]}"#
    let r = try JSONDecoder().decode(AIApplyResult.self, from: Data(json.utf8))
    XCTAssertEqual(r.explanation, "Added controls")
    XCTAssertTrue(r.replacementSource.contains("void main"))
    XCTAssertEqual(r.changedLines, [3, 7])
}
```

- [ ] **Step 2: Run focused tests and verify they fail**

Run:

```bash
cd ShadertoyISFKit
swift test --filter ShaderAssistTypesTests
```

Expected: compile failures for missing `AISuggestionGoalsResult`, `AIApplyResult`, `AIIdea.id`, `AIIdea.impact`, and `AISuggestionsResult.goal`.

- [ ] **Step 3: Implement the shared types**

Replace `ShaderAssistTypes.swift` with:

```swift
import Foundation

public enum ShaderAssistTask: Sendable, Equatable {
    case diagnoseAndFix
    case suggestionGoals
    case suggestions(goal: String)
    case applySuggestions(goal: String, selectedIdeas: [AIIdea])
}

public struct AIEdit: Codable, Equatable, Sendable {
    public let fromLine: Int
    public let toLine: Int
    public let replacement: String
    public let rationale: String

    public init(fromLine: Int, toLine: Int, replacement: String, rationale: String) {
        self.fromLine = fromLine
        self.toLine = toLine
        self.replacement = replacement
        self.rationale = rationale
    }
}

public struct AIFixResult: Codable, Equatable, Sendable {
    public let explanation: String
    public let edits: [AIEdit]
}

public struct AISuggestionGoal: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let detail: String
    public let kind: String
    public let whyThisShader: String

    public init(id: String, title: String, detail: String, kind: String, whyThisShader: String) {
        self.id = id
        self.title = title
        self.detail = detail
        self.kind = kind
        self.whyThisShader = whyThisShader
    }
}

public struct AISuggestionGoalsResult: Codable, Equatable, Sendable {
    public let goals: [AISuggestionGoal]

    public init(goals: [AISuggestionGoal]) {
        self.goals = goals
    }
}

public struct AIIdea: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let detail: String
    public let kind: String
    public let lines: [Int]?
    public let impact: String?

    public init(id: String, title: String, detail: String, kind: String, lines: [Int]?, impact: String?) {
        self.id = id
        self.title = title
        self.detail = detail
        self.kind = kind
        self.lines = lines
        self.impact = impact
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, detail, kind, lines, impact
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = try c.decode(String.self, forKey: .title)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? title
        detail = try c.decode(String.self, forKey: .detail)
        kind = try c.decode(String.self, forKey: .kind)
        lines = try c.decodeIfPresent([Int].self, forKey: .lines)
        impact = try c.decodeIfPresent(String.self, forKey: .impact)
    }
}

public struct AISuggestionsResult: Codable, Equatable, Sendable {
    public let goal: String
    public let ideas: [AIIdea]

    public init(goal: String, ideas: [AIIdea]) {
        self.goal = goal
        self.ideas = ideas
    }

    private enum CodingKeys: String, CodingKey {
        case goal, ideas
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        goal = try c.decodeIfPresent(String.self, forKey: .goal) ?? ""
        ideas = try c.decode([AIIdea].self, forKey: .ideas)
    }
}

public struct AIApplyResult: Codable, Equatable, Sendable {
    public let explanation: String
    public let replacementSource: String
    public let changedLines: [Int]

    public init(explanation: String, replacementSource: String, changedLines: [Int]) {
        self.explanation = explanation
        self.replacementSource = replacementSource
        self.changedLines = changedLines
    }
}

public enum ShaderAssistParseError: Error, Equatable {
    case unparseable(raw: String)
}
```

- [ ] **Step 4: Run focused tests and verify they pass**

Run:

```bash
cd ShadertoyISFKit
swift test --filter ShaderAssistTypesTests
```

Expected: all `ShaderAssistTypesTests` pass.

- [ ] **Step 5: Commit**

```bash
git add ShadertoyISFKit/Sources/ShadertoyISFKit/ShaderAssist/ShaderAssistTypes.swift \
        ShadertoyISFKit/Tests/ShadertoyISFKitTests/ShaderAssistTypesTests.swift
git commit -m "feat(shaderassist): add goal and apply suggestion types"
```

---

## Task 2: Prompt Branches For Goals, Scoped Suggestions, And Apply

**Files:**
- Modify: `ShadertoyISFKit/Sources/ShadertoyISFKit/ShaderAssist/ShaderAssistPrompt.swift`
- Modify: `ShadertoyISFKit/Tests/ShadertoyISFKitTests/ShaderAssistPromptTests.swift`

- [ ] **Step 1: Write failing prompt tests**

Append these tests to `ShaderAssistPromptTests.swift`:

```swift
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
```

Update the existing `testSuggestionsSystemHasIdeasSchema` to call `.suggestions(goal: "Improve motion")`.

- [ ] **Step 2: Run prompt tests and verify they fail**

Run:

```bash
cd ShadertoyISFKit
swift test --filter ShaderAssistPromptTests
```

Expected: failures because `suggestionGoals`, scoped goal text, and apply JSON details are not implemented.

- [ ] **Step 3: Implement prompt branching**

Replace `ShaderAssistPrompt.swift` with:

```swift
import Foundation

public enum ShaderAssistPrompt {
    public static func system(for task: ShaderAssistTask) -> String {
        let common = """
        You are an ISF/GLSL shader co-pilot inside the TrueISFEditor app. The shader targets ISFMSLKit / \
        VDMX6 (Metal, GLSL ES 3.0 transpiled via SPIR-V). Use the `isf-shader-development` and `shader-dev` \
        skills and their knowledge. Line numbers are 1-based exactly as shown in the user message. \
        Respond with ONLY a single JSON object matching the schema below — no prose, no markdown fences.
        """

        switch task {
        case .diagnoseAndFix:
            return common + "\n" + """
            Schema: {"explanation": string (1-3 sentences), "edits": [ {"fromLine": int, "toLine": int, \
            "replacement": string (the full replacement text for those lines), "rationale": string} ]}. \
            If nothing needs fixing, return an empty "edits" array and explain why.
            """
        case .suggestionGoals:
            return common + "\n" + """
            Before suggesting edits, identify 4-5 useful goals tailored to THIS shader. Mix practical \
            performability goals and creative evolution goals when the source supports them. \
            Schema: {"goals": [ {"id": string, "title": string, "detail": string, "kind": string, \
            "whyThisShader": string} ]}. The "whyThisShader" field must cite a concrete property of the \
            provided shader, not generic advice.
            """
        case .suggestions:
            return common + "\n" + """
            Suggest creative evolutions scoped ONLY to the selected goal. Identify hardcoded constants that \
            could become interactive ISF INPUTS when relevant, and ways the visual design could develop. \
            Schema: {"goal": string, "ideas": [ {"id": string, "title": string, "detail": string, \
            "kind": string (one of: make-interactive, design, technique, perf), "lines": [int] or null, \
            "impact": string or null} ]}.
            """
        case .applySuggestions:
            return common + "\n" + """
            Implement the selected suggestions as ONE coordinated shader rewrite. Return a complete valid ISF \
            source file in "replacementSource"; do not return line patches. Preserve valid ISF JSON header \
            syntax, existing inputs, passes, and image inputs unless the selected suggestions require a change. \
            Preserve the shader's visual identity unless the selected goal explicitly asks for transformation. \
            Schema: {"explanation": string, "replacementSource": string, "changedLines": [int]}.
            """
        }
    }

    public static func user(task: ShaderAssistTask, source: String, diagnostics: [Diagnostic]) -> String {
        let numbered = source.components(separatedBy: "\n").enumerated()
            .map { "\($0.offset + 1): \($0.element)" }.joined(separator: "\n")
        let diagText = diagnostics.isEmpty ? "(none)" :
            diagnostics.map { d in
                let loc = d.line.map { "line \($0)" } ?? "—"
                return "[\(d.severity)] \(loc): \(d.message)"
            }.joined(separator: "\n")

        let header: String
        switch task {
        case .diagnoseAndFix:
            header = "Diagnose and fix the compile/diagnostic issues in this ISF shader."
        case .suggestionGoals:
            header = "Suggest 4-5 improvement goals tailored to this ISF shader before proposing edits."
        case .suggestions(let goal):
            header = "Suggest actionable changes for this ISF shader.\nGoal: \(goal)"
        case .applySuggestions(let goal, let selectedIdeas):
            let ideasJSON = selectedIdeasJSON(selectedIdeas)
            header = """
            Implement the selected ShaderAssist suggestions in one coordinated rewrite.
            Goal: \(goal)
            Selected suggestions JSON:
            \(ideasJSON)
            Return the full replacement source in "replacementSource".
            """
        }

        return """
        \(header)

        SHADER (numbered, 1-based):
        \(numbered)

        CURRENT DIAGNOSTICS:
        \(diagText)
        """
    }

    private static func selectedIdeasJSON(_ ideas: [AIIdea]) -> String {
        guard let data = try? JSONEncoder().encode(ideas),
              let json = String(data: data, encoding: .utf8) else { return "[]" }
        return json
    }
}
```

- [ ] **Step 4: Run prompt tests and verify they pass**

Run:

```bash
cd ShadertoyISFKit
swift test --filter ShaderAssistPromptTests
```

Expected: all prompt tests pass.

- [ ] **Step 5: Commit**

```bash
git add ShadertoyISFKit/Sources/ShadertoyISFKit/ShaderAssist/ShaderAssistPrompt.swift \
        ShadertoyISFKit/Tests/ShadertoyISFKitTests/ShaderAssistPromptTests.swift
git commit -m "feat(shaderassist): prompt goal scoped suggestion and apply flows"
```

---

## Task 3: Response Parser Entry Points

**Files:**
- Modify: `ShadertoyISFKit/Sources/ShadertoyISFKit/ShaderAssist/ShaderAssistResponseParser.swift`
- Modify: `ShadertoyISFKit/Tests/ShadertoyISFKitTests/ShaderAssistResponseParserTests.swift`

- [ ] **Step 1: Write failing parser tests**

Append these tests to `ShaderAssistResponseParserTests.swift`:

```swift
func testSuggestionGoalsParse() throws {
    let s = #"{"goals":[{"id":"motion","title":"Add motion","detail":"Animate the field","kind":"design","whyThisShader":"The current shader is static."}]}"#
    let env = #"{"is_error":false,"result":"\#(escaped(s))"}"#
    let r = try ShaderAssistResponseParser.suggestionGoals(fromClaudeStdout: env)
    XCTAssertEqual(r.goals[0].id, "motion")
}

func testApplyResultParse() throws {
    let s = #"{"explanation":"Added input","replacementSource":"/*{}*/\nvoid main(){}","changedLines":[2]}"#
    let env = #"{"is_error":false,"result":"\#(escaped(s))"}"#
    let r = try ShaderAssistResponseParser.applyResult(fromClaudeStdout: env)
    XCTAssertEqual(r.changedLines, [2])
    XCTAssertTrue(r.replacementSource.contains("void main"))
}
```

Update `testSuggestionsParse` JSON to include `goal`, `id`, and `impact`:

```swift
let s = #"{"goal":"Design","ideas":[{"id":"palette","title":"t","detail":"d","kind":"design","lines":null,"impact":"i"}]}"#
```

- [ ] **Step 2: Run parser tests and verify they fail**

Run:

```bash
cd ShadertoyISFKit
swift test --filter ShaderAssistResponseParserTests
```

Expected: compile failures for missing `suggestionGoals` and `applyResult`.

- [ ] **Step 3: Implement parser functions**

Add two public functions beside the existing parser entry points:

```swift
public static func suggestionGoals(fromClaudeStdout s: String) throws -> AISuggestionGoalsResult {
    try decode(AISuggestionGoalsResult.self, from: candidateJSON(s))
}

public static func applyResult(fromClaudeStdout s: String) throws -> AIApplyResult {
    try decode(AIApplyResult.self, from: candidateJSON(s))
}
```

The top of `ShaderAssistResponseParser.swift` should read:

```swift
import Foundation

public enum ShaderAssistResponseParser {
    public static func fixResult(fromClaudeStdout s: String) throws -> AIFixResult {
        try decode(AIFixResult.self, from: candidateJSON(s))
    }
    public static func suggestions(fromClaudeStdout s: String) throws -> AISuggestionsResult {
        try decode(AISuggestionsResult.self, from: candidateJSON(s))
    }
    public static func suggestionGoals(fromClaudeStdout s: String) throws -> AISuggestionGoalsResult {
        try decode(AISuggestionGoalsResult.self, from: candidateJSON(s))
    }
    public static func applyResult(fromClaudeStdout s: String) throws -> AIApplyResult {
        try decode(AIApplyResult.self, from: candidateJSON(s))
    }

    // Keep the existing Envelope, candidateJSON, extractObject, and decode helpers unchanged.
```

- [ ] **Step 4: Run parser tests and verify they pass**

Run:

```bash
cd ShadertoyISFKit
swift test --filter ShaderAssistResponseParserTests
```

Expected: all parser tests pass.

- [ ] **Step 5: Commit**

```bash
git add ShadertoyISFKit/Sources/ShadertoyISFKit/ShaderAssist/ShaderAssistResponseParser.swift \
        ShadertoyISFKit/Tests/ShadertoyISFKitTests/ShaderAssistResponseParserTests.swift
git commit -m "feat(shaderassist): parse goal and apply results"
```

---

## Task 4: ShaderAssistViewModel Workflow State

**Files:**
- Modify: `App/TrueISFEditor/ShaderAssist/ShaderAssistViewModel.swift`
- Modify: `App/TrueISFEditorTests/ShaderAssistViewModelTests.swift`

- [ ] **Step 1: Add failing fake-provider tests**

Add this fake provider and helper to `ShaderAssistViewModelTests.swift`:

```swift
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
        case .success(let text): return text
        case .failure(let error): throw error
        }
    }
}

private func settle() async {
    await Task.yield()
    try? await Task.sleep(nanoseconds: 20_000_000)
}
```

Append these tests:

```swift
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
```

- [ ] **Step 2: Run app view-model tests and verify they fail**

Run:

```bash
cd App
xcodegen generate
xcodebuild test -project TrueISFEditor.xcodeproj -scheme TrueISFEditor \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath ./ddata-build \
  -only-testing:TrueISFEditorTests/ShaderAssistViewModelTests
```

Expected: compile failures for missing `providerOverride`, workflow methods, public workflow state, and `sourceFingerprint`.

- [ ] **Step 3: Implement view-model workflow**

Modify `ShaderAssistViewModel.swift`:

1. Extend `State`:

```swift
case suggestionGoals(AISuggestionGoalsResult)
case applyPreview(AIApplyResult)
```

2. Add published workflow state:

```swift
@Published var activeSuggestionGoal: String?
@Published var suggestionSourceFingerprint: String?
@Published var applyPreviewSourceFingerprint: String?
@Published var selectedIdeaIDs: Set<String> = []
@Published var lastSuggestions: AISuggestionsResult?
```

3. Add provider injection storage and update the initializer:

```swift
private let providerOverride: AssistProvider?

init(binaryOverride: @escaping () -> String?,
     defaults: UserDefaults = .standard,
     providerOverride: AssistProvider? = nil) {
    self.binaryOverride = binaryOverride
    self.defaults = defaults
    self.providerOverride = providerOverride
}
```

4. Make `makeProvider()` return the override first:

```swift
private func makeProvider() -> AssistProvider {
    if let providerOverride { return providerOverride }
    switch providerKind {
    case .claude:
        return ClaudeCodeRunner(binary: ClaudeCodeRunner.locateBinary(override: binaryOverride()))
    case .codex:
        return CodexRunner(binary: CodexRunner.locateBinary(
            override: defaults.string(forKey: "codexBinaryPath")))
    }
}
```

5. Add helpers:

```swift
nonisolated static func sourceFingerprint(_ source: String) -> String {
    String(source.hashValue)
}

func requestSuggestionGoals(source: String, diagnostics: [Diagnostic]) {
    activeSuggestionGoal = nil
    selectedIdeaIDs = []
    lastSuggestions = nil
    suggestionSourceFingerprint = Self.sourceFingerprint(source)
    run(.suggestionGoals, source: source, diagnostics: diagnostics)
}

func chooseSuggestionGoal(_ goal: String, source: String, diagnostics: [Diagnostic]) {
    activeSuggestionGoal = goal
    selectedIdeaIDs = []
    lastSuggestions = nil
    suggestionSourceFingerprint = Self.sourceFingerprint(source)
    run(.suggestions(goal: goal), source: source, diagnostics: diagnostics)
}

func rerunSuggestions(source: String, diagnostics: [Diagnostic]) {
    guard let goal = activeSuggestionGoal else { return }
    chooseSuggestionGoal(goal, source: source, diagnostics: diagnostics)
}

func startSuggestionFlowOver() {
    activeSuggestionGoal = nil
    suggestionSourceFingerprint = nil
    applyPreviewSourceFingerprint = nil
    selectedIdeaIDs = []
    lastSuggestions = nil
    state = .idle
}

func toggleIdeaSelection(_ id: String) {
    if selectedIdeaIDs.contains(id) { selectedIdeaIDs.remove(id) }
    else { selectedIdeaIDs.insert(id) }
}

func applySelectedSuggestions(source: String) {
    guard let goal = activeSuggestionGoal, let suggestions = lastSuggestions else {
        state = .error("Generate suggestions before applying.")
        return
    }
    guard suggestionSourceFingerprint == Self.sourceFingerprint(source) else {
        state = .error("Shader changed since these suggestions were generated. Rerun suggestions.")
        return
    }
    let selected = suggestions.ideas.filter { selectedIdeaIDs.contains($0.id) }
    guard !selected.isEmpty else {
        state = .error("Select at least one suggestion to apply.")
        return
    }
    run(.applySuggestions(goal: goal, selectedIdeas: selected), source: source, diagnostics: [])
}

func confirmApplyPreview(currentSource: String, apply: (String) -> Void) {
    guard case .applyPreview(let result) = state else { return }
    guard applyPreviewSourceFingerprint == Self.sourceFingerprint(currentSource) else {
        state = .error("Shader changed since this diff was generated. Rerun apply.")
        return
    }
    apply(result.replacementSource)
    state = .idle
}

func discardApplyPreview() {
    if let lastSuggestions { state = .suggestions(lastSuggestions) }
    else { state = .idle }
}
```

6. Extend the parse switch in `run`:

```swift
case .diagnoseAndFix:
    if let r = try? ShaderAssistResponseParser.fixResult(fromClaudeStdout: final) { self?.state = .fix(r) }
    else { self?.state = .rawAnswer(final) }
case .suggestionGoals:
    if let r = try? ShaderAssistResponseParser.suggestionGoals(fromClaudeStdout: final) { self?.state = .suggestionGoals(r) }
    else { self?.state = .rawAnswer(final) }
case .suggestions:
    if let r = try? ShaderAssistResponseParser.suggestions(fromClaudeStdout: final) {
        self?.lastSuggestions = r
        self?.selectedIdeaIDs = []
        self?.state = .suggestions(r)
    } else { self?.state = .rawAnswer(final) }
case .applySuggestions:
    if let r = try? ShaderAssistResponseParser.applyResult(fromClaudeStdout: final) {
        guard r.replacementSource.contains("/*{") else {
            self?.state = .error("Claude did not return a valid ISF replacement source.")
            return
        }
        self?.applyPreviewSourceFingerprint = Self.sourceFingerprint(source)
        self?.state = .applyPreview(r)
    } else { self?.state = .rawAnswer(final) }
```

7. Update `cancel()`:

```swift
func cancel() {
    task?.cancel()
    if let lastSuggestions { state = .suggestions(lastSuggestions) }
    else { state = .idle }
}
```

- [ ] **Step 4: Run app view-model tests and verify they pass**

Run:

```bash
cd App
xcodebuild test -project TrueISFEditor.xcodeproj -scheme TrueISFEditor \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath ./ddata-build \
  -only-testing:TrueISFEditorTests/ShaderAssistViewModelTests
```

Expected: `ShaderAssistViewModelTests` pass.

- [ ] **Step 5: Commit**

```bash
git add App/TrueISFEditor/ShaderAssist/ShaderAssistViewModel.swift \
        App/TrueISFEditorTests/ShaderAssistViewModelTests.swift
git commit -m "feat(shaderassist): add suggestions workflow state"
```

---

## Task 5: Editor Full-Source Replacement

**Files:**
- Modify: `App/TrueISFEditor/EditorViewModel.swift`

- [ ] **Step 1: Add the replacement method**

Add this method under the existing `// MARK: fix apply` section, after `apply(_:)`:

```swift
/// Replace the full editor source after a user-approved ShaderAssist diff.
func replaceSourceFromAssist(_ source: String, status: String = "Applied ShaderAssist suggestions") {
    file.source = source
    editor.setText(source)
    headerModel.syncFromText(source)
    recompile(immediate: true)
    statusMessage = status
}
```

- [ ] **Step 2: Build the app target**

Run:

```bash
cd App
xcodegen generate
xcodebuild -project TrueISFEditor.xcodeproj -scheme TrueISFEditor \
  -configuration Debug -derivedDataPath ./ddata-build \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=YES build
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: Commit**

```bash
git add App/TrueISFEditor/EditorViewModel.swift
git commit -m "feat(shaderassist): add approved source replacement hook"
```

---

## Task 6: Goal Sheet And Selectable Suggestions UI

**Files:**
- Create: `App/TrueISFEditor/Views/SuggestionGoalSheet.swift`
- Modify: `App/TrueISFEditor/Views/SuggestionsPanel.swift`

- [ ] **Step 1: Create `SuggestionGoalSheet.swift`**

Add:

```swift
import SwiftUI
import ShadertoyISFKit

struct SuggestionGoalSheet: View {
    @ObservedObject var model: ShaderAssistViewModel
    let source: String
    let diagnostics: [Diagnostic]
    let onChoose: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var customGoal = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("What do you want to improve?").font(.title3).bold()
                    Text("ShaderAssist will tailor suggestions to the current shader.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel") { dismiss() }
            }

            content

            Divider()
            HStack {
                TextField("Custom goal", text: $customGoal)
                Button("Use Custom Goal") {
                    let goal = customGoal.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !goal.isEmpty else { return }
                    onChoose(goal)
                    dismiss()
                }
                .disabled(customGoal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(18)
        .frame(width: 560, minHeight: 360)
        .onAppear {
            model.requestSuggestionGoals(source: source, diagnostics: diagnostics)
        }
    }

    @ViewBuilder private var content: some View {
        switch model.state {
        case .running(.suggestionGoals):
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Reading the shader...").foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .suggestionGoals(let result):
            if result.goals.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(result.goals) { goal in
                            Button {
                                onChoose(goal.title)
                                dismiss()
                            } label: {
                                VStack(alignment: .leading, spacing: 5) {
                                    HStack {
                                        Text(goal.title).font(.headline)
                                        Text(goal.kind).font(.caption2)
                                            .padding(.horizontal, 6).padding(.vertical, 2)
                                            .background(.quaternary, in: Capsule())
                                    }
                                    Text(goal.detail).font(.caption).foregroundStyle(.secondary)
                                    Text(goal.whyThisShader).font(.caption2).foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(8)
                                .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        case .error(let message):
            VStack(alignment: .leading, spacing: 8) {
                Text(message).font(.caption).foregroundStyle(.red).textSelection(.enabled)
                Button("Retry") { model.requestSuggestionGoals(source: source, diagnostics: diagnostics) }
            }
        case .rawAnswer(let answer):
            ScrollView {
                Text(answer).font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        default:
            Button("Generate Goals") { model.requestSuggestionGoals(source: source, diagnostics: diagnostics) }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("No tailored goals came back.").foregroundStyle(.secondary)
            Button("Retry") { model.requestSuggestionGoals(source: source, diagnostics: diagnostics) }
        }
    }
}
```

- [ ] **Step 2: Replace `SuggestionsPanel.swift`**

Replace the file with:

```swift
import SwiftUI
import ShadertoyISFKit

struct SuggestionsPanel: View {
    let result: AISuggestionsResult
    let selectedIDs: Set<String>
    let onToggle: (String) -> Void
    let onJump: (Int) -> Void
    let onApply: () -> Void
    let onRerun: () -> Void
    let onChangeGoal: () -> Void
    let onStartOver: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Claude — Suggestions").font(.headline)
                    Text(result.goal.isEmpty ? "Goal-driven suggestions" : result.goal)
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Rerun", action: onRerun).controlSize(.small)
                Button("Change Goal", action: onChangeGoal).controlSize(.small)
                Button("Start Over", action: onStartOver).controlSize(.small)
            }

            if result.ideas.isEmpty {
                Text("No suggestions for this goal. Try rerunning or changing the goal.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(result.ideas) { idea in
                            suggestionCard(idea)
                        }
                    }
                }
            }

            HStack {
                Text("\(selectedIDs.count) selected").font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Button("Apply Selected", action: onApply)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(selectedIDs.isEmpty)
            }
        }
    }

    private func suggestionCard(_ idea: AIIdea) -> some View {
        let selected = selectedIDs.contains(idea.id)
        return HStack(alignment: .top, spacing: 8) {
            Toggle("", isOn: Binding(get: { selected }, set: { _ in onToggle(idea.id) }))
                .labelsHidden()
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(idea.title).font(.callout).bold()
                    Text(idea.kind).font(.caption2)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(.quaternary, in: Capsule())
                }
                Text(idea.detail).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                if let impact = idea.impact, !impact.isEmpty {
                    Text(impact).font(.caption2).foregroundStyle(.secondary).textSelection(.enabled)
                }
                if let lines = idea.lines, let first = lines.first {
                    Button("line \(first)") { onJump(first) }.buttonStyle(.link).font(.caption2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(6)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
    }
}
```

- [ ] **Step 3: Build app target**

Run:

```bash
cd App
xcodegen generate
xcodebuild -project TrueISFEditor.xcodeproj -scheme TrueISFEditor \
  -configuration Debug -derivedDataPath ./ddata-build \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=YES build
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 4: Commit**

```bash
git add App/TrueISFEditor/Views/SuggestionGoalSheet.swift \
        App/TrueISFEditor/Views/SuggestionsPanel.swift
git commit -m "feat(shaderassist): add goal sheet and selectable suggestions"
```

---

## Task 7: Apply Preview Panel And EditorScreen Wiring

**Files:**
- Create: `App/TrueISFEditor/Views/ApplyPreviewPanel.swift`
- Modify: `App/TrueISFEditor/Views/EditorScreen.swift`

- [ ] **Step 1: Create `ApplyPreviewPanel.swift`**

Add:

```swift
import SwiftUI
import ShadertoyISFKit

struct ApplyPreviewPanel: View {
    let originalSource: String
    let result: AIApplyResult
    let onApply: () -> Void
    let onDiscard: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Review ShaderAssist Rewrite").font(.headline)
                Spacer()
                Button("Discard", action: onDiscard).controlSize(.small)
                Button("Apply to Editor", action: onApply)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
            Text(result.explanation).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            HStack(alignment: .top, spacing: 8) {
                sourceColumn("Current", originalSource)
                sourceColumn("Proposed", result.replacementSource)
            }
        }
    }

    private func sourceColumn(_ title: String, _ source: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption2).bold()
            ScrollView {
                Text(source)
                    .font(.system(size: 10, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6)
            }
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
```

- [ ] **Step 2: Wire goal sheet and new panels into `EditorScreen.swift`**

Add state near the other `@State` properties:

```swift
@State private var showSuggestionGoalSheet = false
```

In `body`, add this sheet modifier beside the existing import sheet:

```swift
.sheet(isPresented: $showSuggestionGoalSheet) {
    SuggestionGoalSheet(model: shaderAssist,
                        source: vm.file.source,
                        diagnostics: vm.diagnostics.diagnostics) { goal in
        shaderAssist.chooseSuggestionGoal(goal, source: vm.file.source,
                                          diagnostics: vm.diagnostics.diagnostics)
    }
}
```

Update the `Suggestions` button in `shaderAssistSection`:

```swift
Button("Suggestions") {
    if shaderAssist.activeSuggestionGoal == nil {
        showSuggestionGoalSheet = true
    } else {
        shaderAssist.rerunSuggestions(source: vm.file.source,
                                      diagnostics: vm.diagnostics.diagnostics)
    }
}.disabled(running)
```

Update the `.suggestions` case:

```swift
case .suggestions(let r):
    SuggestionsPanel(result: r,
                     selectedIDs: shaderAssist.selectedIdeaIDs,
                     onToggle: { shaderAssist.toggleIdeaSelection($0) },
                     onJump: { vm.editor.revealLine($0) },
                     onApply: { shaderAssist.applySelectedSuggestions(source: vm.file.source) },
                     onRerun: { shaderAssist.rerunSuggestions(source: vm.file.source,
                                                              diagnostics: vm.diagnostics.diagnostics) },
                     onChangeGoal: { showSuggestionGoalSheet = true },
                     onStartOver: { shaderAssist.startSuggestionFlowOver(); showSuggestionGoalSheet = true })
        .frame(maxHeight: 280)
```

Add a new switch case for apply preview:

```swift
case .applyPreview(let r):
    ApplyPreviewPanel(originalSource: vm.file.source, result: r,
                      onApply: {
                          shaderAssist.confirmApplyPreview(currentSource: vm.file.source) { replacement in
                              vm.replaceSourceFromAssist(replacement)
                          }
                      },
                      onDiscard: { shaderAssist.discardApplyPreview() })
        .frame(maxHeight: 320)
```

The `switch` must still handle `.idle`, `.running`, `.fix`, `.suggestionGoals`, `.suggestions`, `.applyPreview`, `.rawAnswer`, and `.error`. For `.suggestionGoals` in the main panel, render `EmptyView()` because goals live in the sheet.

- [ ] **Step 3: Build app target**

Run:

```bash
cd App
xcodegen generate
xcodebuild -project TrueISFEditor.xcodeproj -scheme TrueISFEditor \
  -configuration Debug -derivedDataPath ./ddata-build \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=YES build
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 4: Commit**

```bash
git add App/TrueISFEditor/Views/ApplyPreviewPanel.swift \
        App/TrueISFEditor/Views/EditorScreen.swift
git commit -m "feat(shaderassist): wire apply preview into editor"
```

---

## Task 8: Full Verification And Native Review Prep

**Files:**
- No intended source changes unless verification exposes a defect.

- [ ] **Step 1: Run ShadertoyISFKit tests**

Run:

```bash
cd ShadertoyISFKit
swift test
```

Expected: all package tests pass.

- [ ] **Step 2: Run full app test suite**

Run:

```bash
cd App
xcodebuild test -project TrueISFEditor.xcodeproj -scheme TrueISFEditor \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath ./ddata-review
```

Expected: all app tests pass.

- [ ] **Step 3: Build with review DerivedData**

Run:

```bash
cd App
xcodebuild -project TrueISFEditor.xcodeproj -scheme TrueISFEditor \
  -configuration Debug -derivedDataPath ./ddata-review \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=YES build
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 4: Verify staged binary freshness**

Check for strings added by this plan:

```bash
strings App/ddata-review/Build/Products/Debug/TrueISFEditor.app/Contents/MacOS/TrueISFEditor.debug.dylib | rg "Review ShaderAssist Rewrite|What do you want to improve"
```

Expected: at least one matching string from the new feature appears in the staged `.debug.dylib`.

- [ ] **Step 5: Manual review checklist before merge**

Native Swift projects do not dispatch Mechanic as a subagent here. Perform this manual checklist and record the results in the final build summary:

- ShaderAssist section handles every `ShaderAssistViewModel.State` case.
- No product code path applies model output without user confirmation.
- Existing Diagnose & Fix still maps `AIEdit` to guarded `TextEdit`.
- Claude runner still pins `--tools "" --disallowedTools LSP --allowedTools "" --strict-mcp-config --disable-slash-commands`.
- Codex runner still pins `-s read-only --ignore-user-config`.
- UI text is at or above the user's 14px minimum except monospaced code/log text where compact code display is intentional.
- No new env vars, crons, hosted routes, API keys, or recurring costs.

- [ ] **Step 6: Confirm final worktree state**

```bash
git status --short
```

Expected: no uncommitted source changes. If verification exposed a defect, return to the task that owns that file,
apply a focused fix there, rerun that task's verification command, and commit with that task's file-specific
`git add` command.

---

## Completion Gates

Before declaring the feature complete:

- `swift test` passes in `ShadertoyISFKit`.
- Full app `xcodebuild test` passes.
- App build succeeds with `-derivedDataPath ./ddata-review ARCHS=arm64 ONLY_ACTIVE_ARCH=YES`.
- Staged binary freshness grep confirms the implementation is in the built binary.
- Manual native Mechanic review is complete.
- CSO review is complete before merge/ship because model output reaches an editor sink.
- Client Success review is complete before presenting as ready for the user, because this is a new workflow UI.
- On-device smoke is complete: goal sheet, tailored goals, scoped suggestions, multi-select, apply preview, apply to editor, live recompile.
