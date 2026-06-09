# TrueISFEditor P3 — In-App AI Co-Pilot Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** In-app **Diagnose & Fix** and **Suggestions** buttons that invoke headless Claude Code (`claude -p`) on the user's subscription, returning structured JSON that drives a per-edit diff-review (reusing P2's guarded `applyTextEdit`).

**Architecture:** Pure, testable `ShaderAssistPrompt` + `ShaderAssistResponseParser` + result types in `ShadertoyISFKit`. App-side `ClaudeCodeRunner` spawns `claude -p --output-format json …` behind a `ProcessRunning` protocol (testable with a fake — no real CLI calls in tests). `ShaderAssistViewModel` drives run state; `DiffReviewPanel`/`SuggestionsPanel` present results.

**Tech Stack:** Swift / SwiftUI, Foundation `Process`, XCTest + `swift test`, the Claude Code CLI (`~/.local/bin/claude`, v2.1.170) as the inference backend.

**Reference docs (read first):**
- Spec: `docs/superpowers/specs/2026-06-09-trueisfeditor-p3-ai-copilot-design.md`
- Memory `claude-subscription-auth-for-third-party-app` (why headless `claude -p`, not the API)

**Build/verify conventions:**
- Engine: `cd ShadertoyISFKit && swift test --filter <Class> 2>&1 | tail -8` (full: `swift test`)
- App build: `cd App && xcodegen generate && xcodebuild -project TrueISFEditor.xcodeproj -scheme TrueISFEditor -configuration Debug -derivedDataPath ./ddata-build ARCHS=arm64 ONLY_ACTIVE_ARCH=YES build 2>&1 | tail -3`
- App tests: `cd App && xcodebuild test -project TrueISFEditor.xcodeproj -scheme TrueISFEditor -destination 'platform=macOS,arch=arm64' -derivedDataPath ./ddata-build 2>&1 | grep -E "Executed|TEST (SUCCEEDED|FAILED)|error:" | tail -6`
- **Test target is a STANDALONE bundle** (`TEST_HOST: ""`): app-target tests use plain `import XCTest` + `import ShadertoyISFKit`, NO `@testable import TrueISFEditor`; add app sources under test to the `TrueISFEditorTests` `sources` in `App/project.yml`. Package tests use `@testable import ShadertoyISFKit`.
- `.xcodeproj` is gitignored & xcodegen-regenerated — never git-add it; run `xcodegen generate` after touching `project.yml`/adding files.
- SourceKit/LSP diagnostics are STALE — trust `xcodebuild`/`swift test` only.
- Commit convention: conventional commits; end every body with `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`.

**Reused from P2 (do not redefine):** `Diagnostic` (line/severity/message/source), `TextEdit {fromLine,toLine,replacement,expectedContains}`, `EditorViewModel.apply(_ edit: TextEdit)` (guarded), `EditorViewModel.file.source`, `EditorViewModel.diagnostics.diagnostics`.

---

## File Structure

**New (ShadertoyISFKit — pure, swift-test-able)**
- `Sources/ShadertoyISFKit/ShaderAssist/ShaderAssistTypes.swift` — `ShaderAssistTask`, `AIEdit`, `AIFixResult`, `AIIdea`, `AISuggestionsResult`, `ShaderAssistParseError`.
- `Sources/ShadertoyISFKit/ShaderAssist/ShaderAssistResponseParser.swift`
- `Sources/ShadertoyISFKit/ShaderAssist/ShaderAssistPrompt.swift`
- `Tests/ShadertoyISFKitTests/ShaderAssistResponseParserTests.swift`, `ShaderAssistPromptTests.swift`

**New (app)**
- `App/TrueISFEditor/ShaderAssist/ClaudeCodeRunner.swift` (+ `ProcessRunning` protocol + `ClaudeRunError`)
- `App/TrueISFEditor/ShaderAssist/ShaderAssistViewModel.swift`
- `App/TrueISFEditor/Views/DiffReviewPanel.swift`, `Views/SuggestionsPanel.swift`
- `App/TrueISFEditorTests/ClaudeCodeRunnerTests.swift`

**Modified**
- `App/TrueISFEditor/Views/EditorScreen.swift` (AI buttons + panels)
- `App/TrueISFEditor/AppModel.swift` + `SettingsView.swift` (Claude Code binary path)
- `App/project.yml` (new sources/tests)

---

## Phase A — Engine: types, parser, prompt (ShadertoyISFKit)

### Task 1: ShaderAssist result types

**Files:**
- Create: `ShadertoyISFKit/Sources/ShadertoyISFKit/ShaderAssist/ShaderAssistTypes.swift`
- Create: `ShadertoyISFKit/Tests/ShadertoyISFKitTests/ShaderAssistTypesTests.swift`

- [ ] **Step 1: Write the failing test**
```swift
import XCTest
@testable import ShadertoyISFKit

final class ShaderAssistTypesTests: XCTestCase {
    func testDecodeFixResult() throws {
        let json = #"{"explanation":"texture2D unavailable","edits":[{"fromLine":11,"toLine":11,"replacement":"IMG_PIXEL(a,b)","rationale":"use ISF sampler"}]}"#
        let r = try JSONDecoder().decode(AIFixResult.self, from: Data(json.utf8))
        XCTAssertEqual(r.explanation, "texture2D unavailable")
        XCTAssertEqual(r.edits.count, 1)
        XCTAssertEqual(r.edits[0].fromLine, 11)
        XCTAssertEqual(r.edits[0].rationale, "use ISF sampler")
    }
    func testDecodeSuggestions() throws {
        let json = #"{"ideas":[{"title":"Expose speed","detail":"line 23 hardcodes rate","kind":"make-interactive","lines":[23]}]}"#
        let r = try JSONDecoder().decode(AISuggestionsResult.self, from: Data(json.utf8))
        XCTAssertEqual(r.ideas.count, 1)
        XCTAssertEqual(r.ideas[0].kind, "make-interactive")
        XCTAssertEqual(r.ideas[0].lines, [23])
    }
}
```

- [ ] **Step 2: Run (expect FAIL — types missing)** — `cd ShadertoyISFKit && swift test --filter ShaderAssistTypesTests 2>&1 | tail -8`

- [ ] **Step 3: Implement `ShaderAssistTypes.swift`**
```swift
import Foundation

public enum ShaderAssistTask: Sendable { case diagnoseAndFix, suggestions }

public struct AIEdit: Codable, Equatable, Sendable {
    public let fromLine: Int
    public let toLine: Int
    public let replacement: String
    public let rationale: String
}

public struct AIFixResult: Codable, Equatable, Sendable {
    public let explanation: String
    public let edits: [AIEdit]
}

public struct AIIdea: Codable, Equatable, Sendable, Identifiable {
    public var id: String { title }
    public let title: String
    public let detail: String
    public let kind: String        // make-interactive | design | technique | perf
    public let lines: [Int]?
}

public struct AISuggestionsResult: Codable, Equatable, Sendable {
    public let ideas: [AIIdea]
}

public enum ShaderAssistParseError: Error, Equatable {
    case unparseable(raw: String)
}
```

- [ ] **Step 4: Run (expect PASS)** — 2 tests pass.

- [ ] **Step 5: Commit**
```bash
cd ShadertoyISFKit && git add Sources Tests && git commit -m "feat(P3): ShaderAssist result types (TDD)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

### Task 2: ShaderAssistResponseParser (envelope + inner-JSON extraction)

**Files:**
- Create: `ShadertoyISFKit/Sources/ShadertoyISFKit/ShaderAssist/ShaderAssistResponseParser.swift`
- Create: `ShadertoyISFKit/Tests/ShadertoyISFKitTests/ShaderAssistResponseParserTests.swift`

Context: `claude -p --output-format json` prints an envelope object whose `result` field is the assistant's text. The parser reads `result`, then extracts our inner JSON from it (bare object, ```json fence, or object embedded in prose). If the envelope doesn't decode, it falls back to scanning the whole stdout.

- [ ] **Step 1: Write the failing tests**
```swift
import XCTest
@testable import ShadertoyISFKit

final class ShaderAssistResponseParserTests: XCTestCase {
    private let inner = #"{"explanation":"e","edits":[{"fromLine":1,"toLine":1,"replacement":"x","rationale":"r"}]}"#

    func testEnvelopeWithBareJSON() throws {
        let env = #"{"type":"result","subtype":"success","is_error":false,"result":"\#(escaped(inner))"}"#
        let r = try ShaderAssistResponseParser.fixResult(fromClaudeStdout: env)
        XCTAssertEqual(r.explanation, "e"); XCTAssertEqual(r.edits.count, 1)
    }
    func testEnvelopeWithFencedJSON() throws {
        let fenced = "Here is the fix:\n```json\n\(inner)\n```"
        let env = #"{"type":"result","is_error":false,"result":"\#(escaped(fenced))"}"#
        let r = try ShaderAssistResponseParser.fixResult(fromClaudeStdout: env)
        XCTAssertEqual(r.edits[0].replacement, "x")
    }
    func testRawInnerNoEnvelope() throws {   // fallback: stdout is the inner JSON directly
        let r = try ShaderAssistResponseParser.fixResult(fromClaudeStdout: inner)
        XCTAssertEqual(r.explanation, "e")
    }
    func testMalformedThrowsUnparseable() {
        XCTAssertThrowsError(try ShaderAssistResponseParser.fixResult(fromClaudeStdout: "no json here")) { err in
            guard case ShaderAssistParseError.unparseable = err else { return XCTFail("wrong error") }
        }
    }
    func testSuggestionsParse() throws {
        let s = #"{"ideas":[{"title":"t","detail":"d","kind":"design","lines":null}]}"#
        let env = #"{"is_error":false,"result":"\#(escaped(s))"}"#
        let r = try ShaderAssistResponseParser.suggestions(fromClaudeStdout: env)
        XCTAssertEqual(r.ideas[0].kind, "design")
    }

    // JSON-escape a string for embedding inside a JSON string literal in these fixtures.
    private func escaped(_ s: String) -> String {
        let data = try! JSONEncoder().encode(s)               // -> "\"...\""
        return String(String(data: data, encoding: .utf8)!.dropFirst().dropLast())
    }
}
```

- [ ] **Step 2: Run (expect FAIL — parser missing).**

- [ ] **Step 3: Implement `ShaderAssistResponseParser.swift`**
```swift
import Foundation

public enum ShaderAssistResponseParser {
    public static func fixResult(fromClaudeStdout s: String) throws -> AIFixResult {
        try decode(AIFixResult.self, from: candidateJSON(s))
    }
    public static func suggestions(fromClaudeStdout s: String) throws -> AISuggestionsResult {
        try decode(AISuggestionsResult.self, from: candidateJSON(s))
    }

    private struct Envelope: Decodable { let result: String?; let is_error: Bool? }

    /// Returns the inner JSON text: unwrap the claude envelope's `result` if present, else use stdout;
    /// then extract a JSON object (fenced or outermost balanced braces).
    private static func candidateJSON(_ stdout: String) -> String {
        let trimmed = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        var text = trimmed
        if let data = trimmed.data(using: .utf8),
           let env = try? JSONDecoder().decode(Envelope.self, from: data) {
            if env.is_error == true { return "" }     // forces unparseable downstream
            if let r = env.result { text = r }
        }
        return extractObject(from: text) ?? text
    }

    /// Pull a JSON object out of arbitrary text: prefer a ```json fence, else the outermost {...}.
    private static func extractObject(from text: String) -> String? {
        if let fence = text.range(of: #"```json\s*(\{[\s\S]*?\})\s*```"#, options: .regularExpression) {
            let block = String(text[fence])
            if let inner = block.range(of: #"\{[\s\S]*\}"#, options: .regularExpression) {
                return String(block[inner])
            }
        }
        guard let start = text.firstIndex(of: "{") else { return nil }
        var depth = 0
        var i = start
        while i < text.endIndex {
            let c = text[i]
            if c == "{" { depth += 1 }
            else if c == "}" { depth -= 1; if depth == 0 { return String(text[start...i]) } }
            i = text.index(after: i)
        }
        return nil
    }

    private static func decode<T: Decodable>(_ type: T.Type, from json: String) throws -> T {
        guard let data = json.data(using: .utf8), !json.isEmpty,
              let value = try? JSONDecoder().decode(T.self, from: data) else {
            throw ShaderAssistParseError.unparseable(raw: json)
        }
        return value
    }
}
```

- [ ] **Step 4: Run (expect PASS — 5 tests).**

- [ ] **Step 5: Commit**
```bash
cd ShadertoyISFKit && git add Sources Tests && git commit -m "feat(P3): ShaderAssistResponseParser — envelope unwrap + JSON extraction (TDD)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

### Task 3: ShaderAssistPrompt

**Files:**
- Create: `ShadertoyISFKit/Sources/ShadertoyISFKit/ShaderAssist/ShaderAssistPrompt.swift`
- Create: `ShadertoyISFKit/Tests/ShadertoyISFKitTests/ShaderAssistPromptTests.swift`

- [ ] **Step 1: Write the failing test**
```swift
import XCTest
@testable import ShadertoyISFKit

final class ShaderAssistPromptTests: XCTestCase {
    func testUserPromptHasNumberedSourceAndDiagnostics() {
        let src = "void main(){\n  gl_FragColor = vec4(1.0);\n}"
        let diags = [Diagnostic.compiler(message: "ERROR: 2: bad", line: 2)]
        let p = ShaderAssistPrompt.user(task: .diagnoseAndFix, source: src, diagnostics: diags)
        XCTAssertTrue(p.contains("1: void main(){"))   // 1-based numbering
        XCTAssertTrue(p.contains("ERROR: 2: bad"))
    }
    func testSystemNamesBothSkillsAndJSONOnly() {
        let s = ShaderAssistPrompt.system(for: .diagnoseAndFix)
        XCTAssertTrue(s.contains("isf-shader-development"))
        XCTAssertTrue(s.contains("shader-dev"))
        XCTAssertTrue(s.lowercased().contains("json"))
        XCTAssertTrue(s.contains("\"edits\""))         // fix schema present
    }
    func testSuggestionsSystemHasIdeasSchema() {
        XCTAssertTrue(ShaderAssistPrompt.system(for: .suggestions).contains("\"ideas\""))
    }
}
```

- [ ] **Step 2: Run (expect FAIL).**

- [ ] **Step 3: Implement `ShaderAssistPrompt.swift`**
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
        case .suggestions:
            return common + "\n" + """
            Suggest creative evolutions of this working shader. Identify hardcoded constants that could \
            become interactive ISF INPUTS, and ways the visual design could develop. \
            Schema: {"ideas": [ {"title": string, "detail": string, "kind": string \
            (one of: make-interactive, design, technique, perf), "lines": [int] or null} ]}.
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
        let header = task == .diagnoseAndFix
            ? "Diagnose and fix the compile/diagnostic issues in this ISF shader."
            : "Suggest how this ISF shader could evolve (interactivity + visual design)."
        return """
        \(header)

        SHADER (numbered, 1-based):
        \(numbered)

        CURRENT DIAGNOSTICS:
        \(diagText)
        """
    }
}
```

- [ ] **Step 4: Run (expect PASS — 3 tests).** Then full package `swift test` for no regressions.

- [ ] **Step 5: Commit**
```bash
cd ShadertoyISFKit && git add Sources Tests && git commit -m "feat(P3): ShaderAssistPrompt — system rules + numbered-source task prompt (TDD)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Phase B — App: ClaudeCodeRunner + Settings

### Task 4: ClaudeCodeRunner (behind a testable ProcessRunning protocol)

**Files:**
- Create: `App/TrueISFEditor/ShaderAssist/ClaudeCodeRunner.swift`
- Create: `App/TrueISFEditorTests/ClaudeCodeRunnerTests.swift`
- Modify: `App/project.yml` (add both to `TrueISFEditorTests` sources)

- [ ] **Step 1: Write the failing test**
```swift
import XCTest

@MainActor
final class ClaudeCodeRunnerTests: XCTestCase {
    struct FakeProcess: ProcessRunning {
        var stdout: String; var exitCode: Int32; var stderr: String
        var lastArgs: [String] = []
        mutating func run(executable: URL, args: [String], timeout: TimeInterval) throws -> ProcessOutput {
            lastArgs = args
            return ProcessOutput(stdout: stdout, stderr: stderr, exitCode: exitCode)
        }
    }

    func testBuildsExpectedArgv() async throws {
        var fake = FakeProcess(stdout: "{\"result\":\"ok\"}", exitCode: 0, stderr: "")
        let runner = ClaudeCodeRunner(binary: URL(fileURLWithPath: "/x/claude"), process: { fake })
        _ = try await runner.run(prompt: "P", system: "S", model: "claude-sonnet-4-6")
        let args = runner.lastArgsForTest
        XCTAssertEqual(args[0], "-p")
        XCTAssertTrue(args.contains("--output-format")); XCTAssertTrue(args.contains("json"))
        XCTAssertTrue(args.contains("--model")); XCTAssertTrue(args.contains("claude-sonnet-4-6"))
        XCTAssertTrue(args.contains("--append-system-prompt")); XCTAssertTrue(args.contains("S"))
        XCTAssertTrue(args.contains("P"))
    }
    func testAuthErrorMapsToNotAuthenticated() async {
        let fake = FakeProcess(stdout: "", exitCode: 1, stderr: "Invalid API key · Please run /login")
        let runner = ClaudeCodeRunner(binary: URL(fileURLWithPath: "/x/claude"), process: { fake })
        do { _ = try await runner.run(prompt: "P", system: "S", model: "m"); XCTFail("expected throw") }
        catch let e as ClaudeRunError { XCTAssertEqual(e, .notAuthenticated) }
        catch { XCTFail("wrong error \(error)") }
    }
}
```
> Note: the test reads `runner.lastArgsForTest` — expose a `private(set) var lastArgsForTest: [String] = []` on the runner set in `run`. The `process:` init param is a factory returning a `ProcessRunning` so the fake can be injected.

- [ ] **Step 2: Add sources to test target + run (expect FAIL).** In `App/project.yml` under `TrueISFEditorTests` `sources` add `TrueISFEditor/ShaderAssist/ClaudeCodeRunner.swift`. `xcodegen generate` then run `-only-testing:TrueISFEditorTests/ClaudeCodeRunnerTests` → FAIL (no `ClaudeCodeRunner`).

- [ ] **Step 3: Implement `ClaudeCodeRunner.swift`**
```swift
import Foundation

struct ProcessOutput { let stdout: String; let stderr: String; let exitCode: Int32 }

protocol ProcessRunning {
    mutating func run(executable: URL, args: [String], timeout: TimeInterval) throws -> ProcessOutput
}

enum ClaudeRunError: Error, Equatable {
    case binaryNotFound, notAuthenticated, timedOut, processFailed(String)
}

@MainActor
final class ClaudeCodeRunner {
    private let binary: URL?
    private let makeProcess: () -> ProcessRunning
    private(set) var lastArgsForTest: [String] = []

    init(binary: URL?, process: @escaping () -> ProcessRunning = { RealProcess() }) {
        self.binary = binary
        self.makeProcess = process
    }

    /// Resolve the claude binary: explicit override → known paths → login-shell `command -v`.
    static func locateBinary(override: String?) -> URL? {
        if let o = override, !o.isEmpty, FileManager.default.isExecutableFile(atPath: o) {
            return URL(fileURLWithPath: o)
        }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = ["\(home)/.local/bin/claude", "/opt/homebrew/bin/claude", "/usr/local/bin/claude"]
        for c in candidates where FileManager.default.isExecutableFile(atPath: c) {
            return URL(fileURLWithPath: c)
        }
        // login-shell fallback (GUI apps don't inherit PATH)
        if let path = try? RealProcess().run(
            executable: URL(fileURLWithPath: "/bin/zsh"),
            args: ["-lc", "command -v claude"], timeout: 5).stdout
            .trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty,
           FileManager.default.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return nil
    }

    func run(prompt: String, system: String, model: String, timeout: TimeInterval = 120) async throws -> String {
        guard let binary else { throw ClaudeRunError.binaryNotFound }
        let args = ["-p", "--output-format", "json", "--model", model,
                    "--append-system-prompt", system, prompt]
        lastArgsForTest = args
        var proc = makeProcess()
        let out: ProcessOutput
        do { out = try proc.run(executable: binary, args: args, timeout: timeout) }
        catch { throw ClaudeRunError.timedOut }
        if out.exitCode != 0 {
            let lower = (out.stderr + out.stdout).lowercased()
            if lower.contains("login") || lower.contains("api key") || lower.contains("auth") {
                throw ClaudeRunError.notAuthenticated
            }
            throw ClaudeRunError.processFailed(out.stderr.isEmpty ? out.stdout : out.stderr)
        }
        return out.stdout
    }
}

/// Real Process implementation (not exercised in unit tests).
struct RealProcess: ProcessRunning {
    func run(executable: URL, args: [String], timeout: TimeInterval) throws -> ProcessOutput {
        let p = Process(); p.executableURL = executable; p.arguments = args
        let outPipe = Pipe(); let errPipe = Pipe()
        p.standardOutput = outPipe; p.standardError = errPipe
        try p.run()
        // Simple timeout watchdog.
        let deadline = Date().addingTimeInterval(timeout)
        while p.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
        if p.isRunning { p.terminate(); throw ClaudeRunError.timedOut }
        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        return ProcessOutput(stdout: String(decoding: outData, as: UTF8.self),
                             stderr: String(decoding: errData, as: UTF8.self),
                             exitCode: p.terminationStatus)
    }
}
```
> The `run` returns the raw stdout (the envelope); `ShaderAssistResponseParser` (Task 2) parses it. Keep `run` off the main thread in real use by calling it inside a `Task.detached` from the view model (Task 6) — the `@MainActor` annotation here is for `lastArgsForTest`/state; the `RealProcess` blocking happens on the detached task.

- [ ] **Step 4: Run (expect PASS — 2 tests).**

- [ ] **Step 5: Commit**
```bash
cd App && git add -A && cd .. && git add ShadertoyISFKit 2>/dev/null; cd App
git commit -m "feat(P3): ClaudeCodeRunner (subprocess behind ProcessRunning; binary resolution) — TDD

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

### Task 5: Settings — Claude Code binary path

**Files:**
- Modify: `App/TrueISFEditor/AppModel.swift`, `App/TrueISFEditor/SettingsView.swift`

- [ ] **Step 1: Add a persisted path to `AppModel`.** Add `@Published var claudeBinaryPath: String` seeded from `UserDefaults.standard.string(forKey: "claudeBinaryPath") ?? ""`, and `func saveClaudeBinaryPath(_ p: String) { claudeBinaryPath = p; UserDefaults.standard.set(p, forKey: "claudeBinaryPath") }`. (Mirror the existing settings pattern in the file; UserDefaults is fine — it's a path, not a secret.)

- [ ] **Step 2: Add a field to `SettingsView`.** A `TextField("Claude Code binary path (optional)", text: $draftPath)` seeded on appear from `model.claudeBinaryPath`, saved via `model.saveClaudeBinaryPath` on commit, with help text: "Leave blank to auto-detect (~/.local/bin/claude, Homebrew). Used by the AI co-pilot."

- [ ] **Step 3: Build.** `xcodegen generate` + app build → BUILD SUCCEEDED; Settings shows the field.

- [ ] **Step 4: Commit**
```bash
cd App && git add -A
git commit -m "feat(P3): Settings field for Claude Code binary path

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Phase C — App: ShaderAssistViewModel + Diagnose & Fix + DiffReviewPanel

### Task 6: ShaderAssistViewModel (run state + AIEdit→TextEdit)

**Files:**
- Create: `App/TrueISFEditor/ShaderAssist/ShaderAssistViewModel.swift`
- Create: `App/TrueISFEditorTests/ShaderAssistViewModelTests.swift`
- Modify: `App/project.yml` (add both to test sources)

- [ ] **Step 1: Write the failing test** (the pure mapping is the testable part):
```swift
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
        // expectedContains = a stable substring of the current line 2 (so a stale apply no-ops)
        XCTAssertTrue("  vec4 c = texture2D(a, b);".contains(te.expectedContains ?? "∅"))
    }
}
```

- [ ] **Step 2: Add sources to test target + run (expect FAIL).**

- [ ] **Step 3: Implement `ShaderAssistViewModel.swift`**
```swift
import Foundation
import ShadertoyISFKit

@MainActor
final class ShaderAssistViewModel: ObservableObject {
    enum State: Equatable {
        case idle
        case running(ShaderAssistTask)
        case fix(AIFixResult)
        case suggestions(AISuggestionsResult)
        case rawAnswer(String)          // parse failed — show verbatim
        case error(String)
    }
    @Published private(set) var state: State = .idle
    /// Per-edit apply/skip tracking keyed by edit index.
    @Published var handledEdits: Set<Int> = []

    private let binaryOverride: () -> String?
    private var task: Task<Void, Never>?

    init(binaryOverride: @escaping () -> String?) { self.binaryOverride = binaryOverride }

    /// Map an AIEdit to a guarded P2 TextEdit, deriving expectedContains from the current source line.
    static func textEdit(from edit: AIEdit, source: String) -> TextEdit {
        let lines = source.components(separatedBy: "\n")
        let idx = edit.fromLine - 1
        let current = (idx >= 0 && idx < lines.count) ? lines[idx] : ""
        let expect = current.trimmingCharacters(in: .whitespaces)
        return TextEdit(fromLine: edit.fromLine, toLine: edit.toLine,
                        replacement: edit.replacement,
                        expectedContains: expect.isEmpty ? nil : String(expect.prefix(40)))
    }

    func run(_ t: ShaderAssistTask, source: String, diagnostics: [Diagnostic]) {
        task?.cancel(); handledEdits = []
        state = .running(t)
        let binary = ClaudeCodeRunner.locateBinary(override: binaryOverride())
        let runner = ClaudeCodeRunner(binary: binary)
        let system = ShaderAssistPrompt.system(for: t)
        let prompt = ShaderAssistPrompt.user(task: t, source: source, diagnostics: diagnostics)
        task = Task { [weak self] in
            do {
                let stdout = try await Task.detached { try await runner.run(prompt: prompt, system: system, model: "claude-sonnet-4-6") }.value
                if Task.isCancelled { return }
                switch t {
                case .diagnoseAndFix:
                    if let r = try? ShaderAssistResponseParser.fixResult(fromClaudeStdout: stdout) { self?.state = .fix(r) }
                    else { self?.state = .rawAnswer(stdout) }
                case .suggestions:
                    if let r = try? ShaderAssistResponseParser.suggestions(fromClaudeStdout: stdout) { self?.state = .suggestions(r) }
                    else { self?.state = .rawAnswer(stdout) }
                }
            } catch let e as ClaudeRunError {
                self?.state = .error(Self.message(for: e))
            } catch { self?.state = .error("\(error)") }
        }
    }

    func cancel() { task?.cancel(); state = .idle }

    private static func message(for e: ClaudeRunError) -> String {
        switch e {
        case .binaryNotFound: return "Couldn't find the `claude` CLI. Set its path in Settings, or install Claude Code."
        case .notAuthenticated: return "Claude Code isn't signed in. Run `claude` once in Terminal to log in."
        case .timedOut: return "Claude timed out. Try again."
        case .processFailed(let m): return "Claude failed: \(m)"
        }
    }
}
```
> `ClaudeCodeRunner` is `@MainActor`; calling `runner.run` inside `Task.detached` still hops to the main actor for the `@MainActor` method — acceptable since the heavy `RealProcess` blocking is inside `run`. If the implementer finds the detached/main-actor hop awkward, make `ClaudeCodeRunner.run` `nonisolated` and only `lastArgsForTest` main-actor; either way keep the UI responsive (state changes on main).

- [ ] **Step 4: Run (expect PASS — mapping test).**

- [ ] **Step 5: Commit**
```bash
cd App && git add -A
git commit -m "feat(P3): ShaderAssistViewModel — run state + AIEdit→TextEdit mapping (TDD)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

### Task 7: DiffReviewPanel + AI buttons (Diagnose & Fix end-to-end)

**Files:**
- Create: `App/TrueISFEditor/Views/DiffReviewPanel.swift`
- Modify: `App/TrueISFEditor/Views/EditorScreen.swift`, `App/TrueISFEditor/EditorViewModel.swift`

- [ ] **Step 1: Implement `DiffReviewPanel.swift`**
```swift
import SwiftUI
import ShadertoyISFKit

struct DiffReviewPanel: View {
    let result: AIFixResult
    let sourceLines: [String]
    @Binding var handled: Set<Int>
    let onApply: (AIEdit) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Claude — Diagnose & Fix").font(.headline)
            Text(result.explanation).font(.callout).textSelection(.enabled)
            if result.edits.isEmpty {
                Text("No fixes suggested.").foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(result.edits.enumerated()), id: \.offset) { i, e in
                            editCard(i, e)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder private func editCard(_ i: Int, _ e: AIEdit) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Lines \(e.fromLine)–\(e.toLine)").font(.caption).bold()
            Text(e.rationale).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            HStack(alignment: .top, spacing: 8) {
                labeled("before", before(e), .red)
                labeled("after", e.replacement, .green)
            }
            if handled.contains(i) {
                Text("✓ handled").font(.caption2).foregroundStyle(.secondary)
            } else {
                HStack { Button("Apply") { onApply(e); handled.insert(i) }.buttonStyle(.borderedProminent).controlSize(.small)
                         Button("Skip") { handled.insert(i) }.buttonStyle(.bordered).controlSize(.small) }
            }
        }.padding(6).background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
    }

    private func before(_ e: AIEdit) -> String {
        let lo = max(1, e.fromLine), hi = min(sourceLines.count, e.toLine)
        guard lo <= hi else { return "" }
        return sourceLines[(lo-1)...(hi-1)].joined(separator: "\n")
    }
    private func labeled(_ t: String, _ body: String, _ c: Color) -> some View {
        VStack(alignment: .leading) { Text(t).font(.caption2).foregroundStyle(c)
            Text(body).font(.system(.caption, design: .monospaced)).textSelection(.enabled) }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
```

- [ ] **Step 2: Wire AI buttons + panel into `EditorScreen.swift`.** Add a `@StateObject var copilot = ShaderAssistViewModel(binaryOverride: { settingsModel.claudeBinaryPath })` (pass the settings model in, or read it where available — match how EditorScreen accesses models). Add a small "AI" control row with a **Diagnose & Fix** button:
```swift
Button("Diagnose & Fix") {
    copilot.run(.diagnoseAndFix, source: vm.file.source, diagnostics: vm.diagnostics.diagnostics)
}.disabled(isRunning)
```
Render based on `copilot.state`: `.running` → ProgressView + Cancel (`copilot.cancel()`); `.fix(r)` → `DiffReviewPanel(result: r, sourceLines: vm.file.source.components(separatedBy: "\n"), handled: $copilot.handledEdits) { edit in vm.apply(ShaderAssistViewModel.textEdit(from: edit, source: vm.file.source)) }`; `.rawAnswer(s)` → a scrollable monospaced text view of `s`; `.error(m)` → the message in red. Place it near the diagnostics panel (a tab or a section).

- [ ] **Step 3: Add a one-line cost note** near the AI buttons: `Text("Uses your Claude subscription").font(.caption2).foregroundStyle(.secondary)`.

- [ ] **Step 4: Build + run the full app test suite.** Expect BUILD SUCCEEDED + all tests pass. (No new automated test this task — UI; the mapping/runner/parser are already covered.)

- [ ] **Step 5: On-device smoke (manual).** Launch; load a shader with `texture2D`; click Diagnose & Fix; confirm an explanation + edit card render, Apply rewrites the line and recompiles. Requires `claude` logged in. `.debug.dylib` freshness grep before claiming relaunch.

- [ ] **Step 6: Commit**
```bash
cd App && git add -A
git commit -m "feat(P3): Diagnose & Fix button + DiffReviewPanel (per-edit gated apply)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Phase D — App: Suggestions

### Task 8: Suggestions button + SuggestionsPanel

**Files:**
- Create: `App/TrueISFEditor/Views/SuggestionsPanel.swift`
- Modify: `App/TrueISFEditor/Views/EditorScreen.swift`

- [ ] **Step 1: Implement `SuggestionsPanel.swift`**
```swift
import SwiftUI
import ShadertoyISFKit

struct SuggestionsPanel: View {
    let result: AISuggestionsResult
    let onJump: (Int) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Claude — Suggestions").font(.headline)
            if result.ideas.isEmpty { Text("No suggestions.").foregroundStyle(.secondary) }
            else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(result.ideas) { idea in
                            VStack(alignment: .leading, spacing: 3) {
                                HStack { Text(idea.title).font(.callout).bold()
                                         Text(idea.kind).font(.caption2).padding(.horizontal, 5).padding(.vertical, 1)
                                            .background(.quaternary, in: Capsule()) }
                                Text(idea.detail).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                                if let lines = idea.lines, let first = lines.first {
                                    Button("line \(first)") { onJump(first) }.buttonStyle(.link).font(.caption2)
                                }
                            }.padding(6).background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                        }
                    }
                }
            }
        }
    }
}
```

- [ ] **Step 2: Add the Suggestions button + render** in `EditorScreen.swift`: a **Suggestions** button calling `copilot.run(.suggestions, source: vm.file.source, diagnostics: vm.diagnostics.diagnostics)`; render `.suggestions(r)` → `SuggestionsPanel(result: r) { vm.editor.revealLine($0) }`.

- [ ] **Step 3: Build + full test suite.** Expect green.

- [ ] **Step 4: On-device smoke (manual).** Suggestions on a working shader → idea cards with kind chips; line links jump.

- [ ] **Step 5: Commit**
```bash
cd App && git add -A
git commit -m "feat(P3): Suggestions button + SuggestionsPanel (advisory ideas)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Phase E — Final

### Task 9: Final integration + review

- [ ] **Step 1: Full gates.** `cd ShadertoyISFKit && swift test` (engine green; paste count); app build + app tests green (paste count).
- [ ] **Step 2: On-device end-to-end (user's hands).** Diagnose & Fix applies real fixes; Suggestions renders; binary-not-found / not-authenticated states show correct guidance (temporarily blank the Settings path / rename the binary to test). `.debug.dylib` freshness grep before any "relaunch".
- [ ] **Step 3: Manual inline Mechanic review** (native Swift/SwiftUI): the `Task.detached` + `@MainActor` hop in `ShaderAssistViewModel.run` (no data races; state mutations on main), `RealProcess` timeout/termination + pipe draining (no deadlock on large output — read pipes before waitUntilExit if needed), retain cycles in the `copilot` task closure (`[weak self]` present), and that `claudeBinaryPath` is read fresh each run.
- [ ] **Step 4: Refresh the repo-root `TrueISFEditor.app`** from the build for the user's test.

---

## Self-Review (spec coverage)

- Spec §2 architecture (ShaderAssistPrompt/Parser/types in kit; Runner/VM/panels in app) → Tasks 1–8. ✔
- §3 ClaudeCodeRunner (binary resolution, argv, auth detection, ProcessRunning fake) → Task 4. ✔
- §4 prompt + schema → Task 3. §5 parser (envelope + extraction + raw fallback) → Task 2. ✔
- §6 UI (AI buttons, DiffReviewPanel per-edit apply, SuggestionsPanel, cost note, Settings path, failure states) → Tasks 5,7,8. ✔
- §7 error handling (typed errors → messages; unparseable → raw; stale-edit guard via P2) → Tasks 6,7. ✔
- §8 testing (parser, prompt, runner argv/auth, edit mapping; on-device) → Tasks 1–4,6,7,9. ✔
- §10 build sequence honored (engine → runner/settings → fix → suggestions → final). ✔
- §11 open questions: model flag honored (verify on-device Task 9); skills explicitly named (Task 3 system prompt). ✔

**Type consistency:** `AIFixResult/AIEdit/AISuggestionsResult/AIIdea/ShaderAssistParseError` (Task 1) used identically in Tasks 2,6,7,8. `ShaderAssistResponseParser.fixResult/suggestions(fromClaudeStdout:)` (Task 2) used in Task 6. `ShaderAssistPrompt.system(for:)/user(task:source:diagnostics:)` (Task 3) used in Task 6. `ProcessRunning`/`ProcessOutput`/`ClaudeRunError`/`ClaudeCodeRunner(binary:process:)`/`locateBinary(override:)`/`run(prompt:system:model:)` (Task 4) used in Task 6. `ShaderAssistViewModel.textEdit(from:source:)`/`run(_:source:diagnostics:)`/`state`/`handledEdits` (Task 6) used in Tasks 7,8. `TextEdit`/`EditorViewModel.apply` are P2's. ✔

**Standalone test-bundle note:** every app source under test (`ClaudeCodeRunner.swift`, `ShaderAssistViewModel.swift`) is added to `TrueISFEditorTests` `sources` in `project.yml`; tests use plain `import XCTest` + `import ShadertoyISFKit`. Engine tests use `@testable import ShadertoyISFKit`.
