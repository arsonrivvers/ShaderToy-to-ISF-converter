# TrueISF Remix Pipeline Reliability Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make every Remix child move through a durable, observable provider-to-Metal pipeline that recovers the August 1 empty-result responses, survives Stop races, and never reports parser or provider failures as compiler failures.

**Architecture:** Add typed provider events and a lock-safe response assembler behind the existing text-returning ShaderAssist contract. Replace placeholder `RemixNode` execution state with versioned `RemixChildRunRecord` values, then run extraction and serialized native compilation before creating a lineage artifact. A launch-gated scheduler cancels provider work without cancelling already-authoritative local extraction or compilation.

**Tech Stack:** Swift 5, Swift Concurrency, Foundation `Process`, XCTest, XcodeGen, ISFMSLKit through `ISFSceneLoader`, SwiftUI only at the presentation boundary, macOS 13 or newer.

## Global Constraints

- Keep `AssistProvider.run(prompt:system:model:timeout:onEvent:) async throws -> String` behavior stable for ShaderAssist.
- Keep Claude tool removal, explicit LSP denial, strict MCP mode, slash-command disabling, and the neutral temporary working directory unchanged.
- Keep Codex in `read-only` with network disabled and never add a metered API or `--bare` path.
- Treat an empty successful Claude `result` as terminal for teardown grace, but not as authoritative response text.
- A Ready child must have passed the real crash-safe `ISFSceneLoader.load` path. Parsing alone never means Ready.
- Stop closes the launch gate first. It cancels incomplete provider work but lets authoritative responses finish extraction and compilation.
- Apply first-terminal-transition-wins to every child.
- Bound stored diagnostic response text to 256 KB per child and keep the existing 20-batch and 2,000-line session bounds.
- Schema-v1 sessions must decode and migrate deterministically without quarantine.
- No live provider call is part of an automated test.
- Every new Swift file used by the app tests must be added to `App/project.yml`, followed by `cd App && xcodegen generate`.
- Do not touch the unrelated ARShader dossier or other concurrent work.
- Do not push any TrueISFEditor commit until the standing null_signal colleague heads-up is confirmed. **CLOSED 2026-08-03 — the heads-up was given and the colleague confirmed go-ahead (operator, this session).**

---

### Task 1: Typed provider events and authoritative response assembly

**Files:**
- Create: `App/TrueISFEditor/ShaderAssist/AssistRunEvent.swift`
- Create: `App/TrueISFEditor/ShaderAssist/AssistResponseAssembler.swift`
- Create: `App/TrueISFEditorTests/AssistResponseAssemblerTests.swift`
- Create: `App/TrueISFEditorTests/Fixtures/claude-empty-result-complete-assistant.jsonl`
- Modify: `App/project.yml`

**Interfaces:**
- Consumes: Claude `stream-json` and Codex `exec --json` JSONL lines.
- Produces: `AssistRunEvent`, `AssistRunResult`, `AssistDetailedProvider`, `AssistResponseAssembler.consume(_:)`, and `AssistResponseAssembler.resolve(processExitSucceeded:)`.

- [ ] **Step 1: Write the failing response-precedence and deduplication tests**

Add tests with these binding assertions:

```swift
@MainActor
final class AssistResponseAssemblerTests: XCTestCase {
    func test_emptySuccessfulResultFallsBackToCompleteAssistant() throws {
        var subject = AssistResponseAssembler(provider: .claude)
        subject.consume(.assistantMessage(
            messageID: "m1",
            stopReason: "end_turn",
            blocks: [AssistTextBlock(index: 0, text: "/*{\"ISFVSN\":\"2.0\"}*/\nvoid main(){}")]
        ))
        subject.consume(.successfulResult(""))

        let result = try subject.resolve(processExitSucceeded: true)

        XCTAssertEqual(result.source, .assistantMessage)
        XCTAssertTrue(result.response.contains("ISFVSN"))
        XCTAssertTrue(result.observedSuccessfulResult)
    }

    func test_nonEmptySuccessfulResultWins() throws {
        var subject = AssistResponseAssembler(provider: .claude)
        subject.consume(.assistantMessage(
            messageID: "m1", stopReason: "end_turn",
            blocks: [AssistTextBlock(index: 0, text: "assistant")]
        ))
        subject.consume(.successfulResult("result"))
        XCTAssertEqual(try subject.resolve(processExitSucceeded: true).response, "result")
    }

    func test_errorResultNeverPromotesAssistantText() {
        var subject = AssistResponseAssembler(provider: .claude)
        subject.consume(.assistantMessage(
            messageID: "m1", stopReason: "end_turn",
            blocks: [AssistTextBlock(index: 0, text: "shader-looking text")]
        ))
        subject.consume(.errorResult("rate limited"))
        XCTAssertThrowsError(try subject.resolve(processExitSucceeded: false)) {
            XCTAssertEqual($0 as? AssistAssemblyError, .providerFailed("rate limited"))
        }
    }

    func test_completeSnapshotReplacesItsDeltasInsteadOfDuplicatingThem() throws {
        var subject = AssistResponseAssembler(provider: .claude)
        subject.consume(.textDelta(messageID: "m1", blockIndex: 0, text: "ABC"))
        subject.consume(.assistantMessage(
            messageID: "m1", stopReason: "end_turn",
            blocks: [AssistTextBlock(index: 0, text: "ABC")]
        ))
        subject.consume(.successfulResult(""))
        XCTAssertEqual(try subject.resolve(processExitSucceeded: true).response, "ABC")
    }
}
```

The fixture must contain one complete assistant event with a fenced ISF followed by `{"type":"result","is_error":false,"result":""}`. Use a short synthetic shader, not the user's full parent sources.

- [ ] **Step 2: Run the new tests and verify they fail**

Run:

```bash
cd App
xcodegen generate
xcodebuild test -project TrueISFEditor.xcodeproj -scheme TrueISFEditor \
  -destination 'platform=macOS,arch=arm64' ARCHS=arm64 ONLY_ACTIVE_ARCH=YES \
  -derivedDataPath ./ddata-remix-pipeline \
  -only-testing:TrueISFEditorTests/AssistResponseAssemblerTests
```

Expected: build failure because the new event and assembler types do not exist.

- [ ] **Step 3: Add the typed event and result model**

Implement these exact public-to-the-target shapes in `AssistRunEvent.swift`:

```swift
import Foundation

enum AssistProviderIdentity: String, Codable, Sendable, Equatable {
    case claude
    case codex
}

struct AssistTextBlock: Sendable, Equatable {
    let index: Int
    let text: String
}

enum AssistRunEvent: Sendable, Equatable {
    case sessionStarted(id: String?)
    case processStarted(pid: Int32)
    case thinking
    case textDelta(messageID: String?, blockIndex: Int, text: String)
    case assistantMessage(messageID: String, stopReason: String?, blocks: [AssistTextBlock])
    case apiRetry(attempt: Int?, message: String)
    case successfulResult(String)
    case errorResult(String)
    case timedOut
    case cancelled
    case processExited(Int32)
}

enum AssistResponseSource: String, Codable, Sendable, Equatable {
    case result
    case assistantMessage
    case agentMessage
}

struct AssistRunResult: Sendable, Equatable {
    let provider: AssistProviderIdentity
    let response: String
    let source: AssistResponseSource
    let observedSuccessfulResult: Bool
    let completeAssistantResponse: String?
    let successfulResultText: String?
    let receivedBytes: Int
    let eventCount: Int
}

enum AssistAssemblyError: Error, Sendable, Equatable {
    case providerFailed(String)
    case noAuthoritativeResponse
}

@MainActor
protocol AssistDetailedProvider: AnyObject {
    func runDetailed(
        prompt: String,
        system: String,
        model: String?,
        timeout: TimeInterval,
        onEvent: @escaping @Sendable (AssistRunEvent) -> Void,
        onRawLine: @escaping @Sendable (String) -> Void
    ) async throws -> AssistRunResult
}
```

- [ ] **Step 4: Implement the assembler with result-presence separate from result text**

`AssistResponseAssembler` must store complete assistant snapshots by message ID and replace delta buffers when a matching complete snapshot arrives. `resolve` must apply this exact order:

```swift
mutating func resolve(processExitSucceeded: Bool) throws -> AssistRunResult {
    if let providerError { throw AssistAssemblyError.providerFailed(providerError) }

    if let resultText, !resultText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        return makeResult(response: resultText, source: .result)
    }

    if observedSuccessfulResult,
       let assistant = lastCompleteAssistant,
       !assistant.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        return makeResult(response: assistant.text, source: provider == .codex ? .agentMessage : .assistantMessage)
    }

    if processExitSucceeded,
       let assistant = lastCompleteAssistant,
       assistant.stopReason == "end_turn",
       !assistant.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        return makeResult(response: assistant.text, source: provider == .codex ? .agentMessage : .assistantMessage)
    }

    throw AssistAssemblyError.noAuthoritativeResponse
}
```

Protect mutable stream state with a separate `AssistRunAccumulator` class using `NSLock`, because `RealProcess.onLine` runs on a background reader queue.

- [ ] **Step 5: Run the focused tests and verify they pass**

Run the command from Step 2. Expected: `TEST SUCCEEDED` and all `AssistResponseAssemblerTests` pass.

- [ ] **Step 6: Commit the typed assembly foundation**

```bash
git add App/TrueISFEditor/ShaderAssist/AssistRunEvent.swift \
  App/TrueISFEditor/ShaderAssist/AssistResponseAssembler.swift \
  App/TrueISFEditorTests/AssistResponseAssemblerTests.swift \
  App/TrueISFEditorTests/Fixtures/claude-empty-result-complete-assistant.jsonl \
  App/project.yml App/TrueISFEditor.xcodeproj
git commit -m "feat(assist): assemble authoritative streamed responses"
```

### Task 2: Typed Claude and Codex runners with ShaderAssist compatibility

**Files:**
- Create: `App/TrueISFEditor/ShaderAssist/AssistProviderCompatibilityAdapter.swift`
- Modify: `App/TrueISFEditor/ShaderAssist/ClaudeCodeRunner.swift:48-220`
- Modify: `App/TrueISFEditor/ShaderAssist/CodexRunner.swift:5-113`
- Modify: `App/TrueISFEditor/ShaderAssist/AssistProviderFactory.swift:19-35`
- Modify: `App/TrueISFEditorTests/ClaudeCodeRunnerTests.swift`
- Modify: `App/TrueISFEditorTests/AssistRunnersTests.swift`
- Modify: `App/TrueISFEditorTests/ShaderAssistViewModelTests.swift`
- Modify: `App/TrueISFEditorTests/LaunchPackTests.swift`
- Modify: `App/project.yml`

**Interfaces:**
- Consumes: Task 1's `AssistDetailedProvider`, event decoder, accumulator, and result.
- Produces: `ClaudeCodeRunner.runDetailed`, `CodexRunner.runDetailed`, and an old-contract `run` path that returns only `AssistRunResult.response` while forwarding the same humanizable raw lines as before.

- [ ] **Step 1: Add failing runner regressions for the August 1 stream and partial-message flag**

Add these assertions to `ClaudeCodeRunnerTests`:

```swift
func testEmptyResultReturnsCompleteAssistantText() async throws {
    let assistant = "/*{\"ISFVSN\":\"2.0\"}*/\nvoid main(){}"
    let assistantObject: [String: Any] = [
        "type": "assistant",
        "message": [
            "id": "m1", "stop_reason": "end_turn",
            "content": [["type": "text", "text": assistant]]
        ]
    ]
    let assistantLine = String(
        data: try JSONSerialization.data(withJSONObject: assistantObject), encoding: .utf8
    )!
    let json = assistantLine + "\n{\"type\":\"result\",\"is_error\":false,\"result\":\"\"}"
    let runner = ClaudeCodeRunner(
        binary: URL(fileURLWithPath: "/x/claude"),
        process: { FakeProcess(stdout: json, exitCode: 0, stderr: "") }
    )
    XCTAssertEqual(try await runner.run(prompt: "P", system: "S", model: "m"), assistant)
    XCTAssertTrue(runner.lastArgsForTest.contains("--include-partial-messages"))
}

func testEmptyResultStillArmsTeardownGrace() async throws {
    let process = EmptyResultLingeringProcess()
    let runner = ClaudeCodeRunner(
        binary: URL(fileURLWithPath: "/x/claude"), process: { process }, teardownGrace: 0.01
    )
    _ = try await runner.run(prompt: "P", system: "S", model: "m")
    XCTAssertTrue(process.cancelCalled)
}
```

Also assert that enabling partial messages does not change the legacy callback count: `stream_event` partial-only JSONL is available to `runDetailed` as typed deltas but is suppressed from the old `run(...onEvent:)` callback. The legacy `ShaderAssistViewModel.eventCount`, transcript, suggestions, rewrite, diagnose, research, and Quick Goals parsing must remain byte-for-byte compatible for the same complete-event fixture. Add detailed-run tests for `.timedOut` and `.cancelled` delivery before process exit.

- [ ] **Step 2: Run the runner and ShaderAssist tests and verify the empty-result test fails**

```bash
cd App
xcodebuild test -project TrueISFEditor.xcodeproj -scheme TrueISFEditor \
  -destination 'platform=macOS,arch=arm64' ARCHS=arm64 ONLY_ACTIVE_ARCH=YES \
  -derivedDataPath ./ddata-remix-pipeline \
  -only-testing:TrueISFEditorTests/ClaudeCodeRunnerTests \
  -only-testing:TrueISFEditorTests/CodexRunnerTests \
  -only-testing:TrueISFEditorTests/ShaderAssistViewModelTests \
  -only-testing:TrueISFEditorTests/LaunchPackTests
```

Expected: the empty result currently wins and produces an empty string.

- [ ] **Step 3: Implement provider-specific JSONL decoders**

Add nonisolated `decodeEvent(from:)` helpers. Claude must decode:

- `system` init to `.sessionStarted`
- complete `assistant.message.content` snapshots to `.assistantMessage`
- `stream_event.content_block_delta.delta.text` to `.textDelta`
- retry or rate-limit system events to `.apiRetry`
- successful `result` even when its text is empty to `.successfulResult`
- `is_error == true` results to `.errorResult`

Codex must decode completed `agent_message` items as complete `.assistantMessage` values with `stopReason: "end_turn"`, plus `error` and `turn.failed` as `.errorResult`.

- [ ] **Step 4: Implement detailed runs and the text compatibility adapter**

`AssistProviderCompatibilityAdapter.swift` must contain:

```swift
enum AssistProviderCompatibilityAdapter {
    static func text(from result: AssistRunResult) -> String { result.response }
    static func legacyRawLine(_ line: String, envelopeType: String?) -> String? {
        if envelopeType == "stream_event" { return nil }
        return line
    }
}
```

Both runners keep conforming directly to `AssistProvider` so `AssistProviderFactory.make` and its concrete-type tests remain valid. Each old `run` calls its new `runDetailed`, passes every decoded event to the typed accumulator, forwards only lines accepted by `legacyRawLine` to the old `onEvent`, and returns `AssistProviderCompatibilityAdapter.text(from:)`. Suppress the entire Claude `stream_event` envelope family from the legacy callback, including start, delta, and stop envelopes, even when a particular partial envelope has no typed event. Do not let the newly enabled `--include-partial-messages` inflate legacy line counts or transcripts.

Claude arguments become:

```swift
var args = [
    "-p", "--output-format", "stream-json", "--verbose", "--include-partial-messages",
    "--tools", "", "--disallowedTools", "LSP", "--allowedTools", "",
    "--strict-mcp-config", "--disable-slash-commands"
]
```

Do not change any other safety or working-directory argument.

Add an optional lifecycle seam without changing existing `ProcessRunning` test doubles:

```swift
enum ProcessLifecycleEvent: Sendable, Equatable {
    case started(pid: Int32)
    case exited(status: Int32)
}

protocol ProcessLifecycleReporting: ProcessRunning {
    func setLifecycleHandler(_ handler: @escaping @Sendable (ProcessLifecycleEvent) -> Void)
}
```

`RealProcess` conforms and emits `.started` immediately after `Process.run()` and `.exited` immediately after `waitUntilExit()`. Detailed runners translate these to typed process events. Legacy fakes and providers remain valid because the seam is an optional downcast.

- [ ] **Step 5: Preserve timeout, nonzero-exit, and cancellation behavior**

Use the accumulator's `observedSuccessfulResult` to arm teardown grace even if response text is empty. Timeout and nonzero-exit salvage may call `resolve` only when a successful result was observed. Assistant text without a successful result still throws on timeout for legacy ShaderAssist. An error result always maps to `AssistRunError.processFailed`. Detailed runners emit `.timedOut` or `.cancelled` before teardown and always follow with `.processExited` when an exit status is observed; legacy callbacks remain unchanged.

- [ ] **Step 6: Run all focused compatibility tests**

Run the Step 2 command. Expected: all provider and ShaderAssist compatibility tests pass, including safety flag assertions.

- [ ] **Step 7: Commit the typed runner compatibility layer**

```bash
git add App/TrueISFEditor/ShaderAssist App/TrueISFEditorTests/ClaudeCodeRunnerTests.swift \
  App/TrueISFEditorTests/AssistRunnersTests.swift \
  App/TrueISFEditorTests/ShaderAssistViewModelTests.swift \
  App/TrueISFEditorTests/LaunchPackTests.swift App/project.yml App/TrueISFEditor.xcodeproj
git commit -m "fix(assist): preserve complete assistant responses"
```

### Task 3: Complete ISF extraction and child-scoped legacy recovery

**Files:**
- Create: `App/TrueISFEditor/Remix/RemixLegacyRecovery.swift`
- Modify: `App/TrueISFEditor/Remix/RemixResponseParser.swift:3-26`
- Modify: `App/TrueISFEditorTests/RemixResponseParserTests.swift`
- Create: `App/TrueISFEditorTests/RemixLegacyRecoveryTests.swift`
- Create: `App/TrueISFEditorTests/Fixtures/remix-2026-08-01-empty-result-session-v1.json`
- Modify: `App/project.yml`

**Interfaces:**
- Consumes: one authoritative provider response or one exact `[childID]` humanized transcript entry.
- Produces: `RemixResponseParser.extractCandidate(_:) -> Result<String, RemixResponseError>` and `RemixLegacyRecovery.candidate(childID:transcript:)`.

- [ ] **Step 1: Write failing extraction and child-isolation tests**

Cover all of these cases:

```swift
XCTAssertSuccess(RemixResponseParser.extractCandidate("prose\n```text\nno shader\n```\n```glsl\n\(isf)\n```"), equals: isf)
XCTAssertFailure(RemixResponseParser.extractCandidate("```glsl\n/*{\"ISFVSN\":\"2.0\"}*/"), equals: .incompleteFence)
XCTAssertFailure(RemixResponseParser.extractCandidate("/*{not json}*/\nvoid main(){}"), equals: .invalidHeader)
XCTAssertNil(RemixLegacyRecovery.candidate(childID: "r1-0", transcript: ["[r1-1] ```glsl\n\(isf)\n```"]))
XCTAssertEqual(RemixLegacyRecovery.candidate(childID: "r1-0", transcript: ["[r1-0] ```glsl\n\(isf)\n```"]), isf)
```

Header validation must use the existing ISF header parser available to the app target. Do not accept only a `/*{` substring.

Create a redacted copy of the real August 1 session shape containing the exact child-tagged complete assistant responses for r1-0, r1-1, and r1-3, with their legacy source fields empty and unrelated children retained only as minimal structural records. Assert all three candidates recover independently, no child can consume another child's block, and incomplete r1-2 or r1-4 data is not promoted.

- [ ] **Step 2: Run the parser and recovery tests and verify they fail**

```bash
cd App
xcodegen generate
xcodebuild test -project TrueISFEditor.xcodeproj -scheme TrueISFEditor \
  -destination 'platform=macOS,arch=arm64' ARCHS=arm64 ONLY_ACTIVE_ARCH=YES \
  -derivedDataPath ./ddata-remix-pipeline \
  -only-testing:TrueISFEditorTests/RemixResponseParserTests \
  -only-testing:TrueISFEditorTests/RemixLegacyRecoveryTests
```

- [ ] **Step 3: Implement complete-fence scanning and raw-source extraction**

Scan every fenced block in order, choose the first complete block containing a valid ISF header, and otherwise inspect the raw text from the first valid `/*{` header. Distinguish `.noISFFound`, `.incompleteFence`, `.invalidHeader(String)`, and `.incompleteSource`.

- [ ] **Step 4: Implement exact child-tagged transcript recovery**

Strip only the exact prefix `"[\(childID)] "` from each entry. Never concatenate another child's entry. Try each matching entry independently and return the first valid candidate. This path performs no provider call.

- [ ] **Step 5: Run the focused tests and commit**

Run the Step 2 command. Expected: all tests pass.

```bash
git add App/TrueISFEditor/Remix/RemixResponseParser.swift \
  App/TrueISFEditor/Remix/RemixLegacyRecovery.swift \
  App/TrueISFEditorTests/RemixResponseParserTests.swift \
  App/TrueISFEditorTests/RemixLegacyRecoveryTests.swift \
  App/TrueISFEditorTests/Fixtures/remix-2026-08-01-empty-result-session-v1.json \
  App/project.yml App/TrueISFEditor.xcodeproj
git commit -m "feat(remix): validate and recover complete ISF responses"
```

### Task 4: Versioned durable child run records and v1 migration

**Files:**
- Create: `App/TrueISFEditor/Remix/RemixChildRunRecord.swift`
- Create: `App/TrueISFEditor/Remix/LegacyRemixSessionV1.swift`
- Modify: `App/TrueISFEditor/Remix/RemixNode.swift:5-20`
- Modify: `App/TrueISFEditor/Remix/RemixSession.swift:3-133`
- Modify: `App/TrueISFEditor/Remix/RemixSessionStore.swift:24-60`
- Modify: `App/TrueISFEditorTests/RemixSessionTests.swift`
- Modify: `App/TrueISFEditorTests/RemixSessionStoreTests.swift`
- Create: `App/TrueISFEditorTests/RemixChildRunRecordTests.swift`
- Create: `App/TrueISFEditorTests/Fixtures/remix-schema-v2-mid-batch.json`
- Modify: `App/project.yml`

**Interfaces:**
- Consumes: immutable `RemixGenerationRequestSnapshot`, legacy nodes, compile diagnostics, and legacy transcript.
- Produces: schema version 2 sessions with ordered `currentRuns`, run-based batch history, and lineage containing seeds plus native-compiled artifacts only.

- [ ] **Step 1: Write failing transition and migration tests**

Tests must assert:

- queued to starting to thinking to receiving to extracting to compiling to ready is accepted
- thinking or receiving to retrying and retrying back to thinking, receiving, or extracting is accepted for provider API retries
- a transition after ready is rejected and leaves the record unchanged
- diagnostics truncate to at most 262,144 UTF-8 bytes
- API retries increment `apiRetryCount`, retain only a bounded human-readable `lastProviderNotice`, and enter Retrying until the next provider activity or authoritative response
- all v1 live `.generating` copies migrate to Interrupted
- a v1 `.compiled` generated child becomes Compiling with its candidate source and does not enter lineage as Ready until recompilation
- a v1 failed child with a compile diagnostic becomes Compile Failed
- `No ISF in reply` plus a same-child recoverable transcript becomes Extracting with the recovered candidate
- `No ISF in reply` without a complete candidate becomes Response Incomplete
- v1 seeds remain lineage artifacts
- a literal schema-v2 mid-batch fixture decodes without losing any live-stage or candidate evidence for Task 7 restoration policy
- decoding, encoding, and decoding the migrated session is idempotent

- [ ] **Step 2: Run the persistence tests and verify they fail**

```bash
cd App
xcodegen generate
xcodebuild test -project TrueISFEditor.xcodeproj -scheme TrueISFEditor \
  -destination 'platform=macOS,arch=arm64' ARCHS=arm64 ONLY_ACTIVE_ARCH=YES \
  -derivedDataPath ./ddata-remix-pipeline \
  -only-testing:TrueISFEditorTests/RemixChildRunRecordTests \
  -only-testing:TrueISFEditorTests/RemixSessionTests \
  -only-testing:TrueISFEditorTests/RemixSessionStoreTests
```

- [ ] **Step 3: Implement the run record as the execution source of truth**

Use this exact core shape:

```swift
struct RemixChildRunRecord: Identifiable, Codable, Equatable {
    enum Stage: String, Codable, CaseIterable, Hashable {
        case queued, starting, thinking, receiving, retrying, extracting, compiling
        case ready, failed, cancelled, interrupted

        var isTerminal: Bool {
            [.ready, .failed, .cancelled, .interrupted].contains(self)
        }
    }

    enum FailureBoundary: String, Codable, Equatable {
        case provider, response, extraction, compile
    }

    let id: String
    let round: Int
    let slot: Int
    let request: RemixGenerationRequestSnapshot
    var stage: Stage
    var queuedAt: Date
    var startedAt: Date?
    var lastEventAt: Date?
    var providerCompletedAt: Date?
    var terminalAt: Date?
    var provider: AssistProviderIdentity?
    var model: String?
    var workerLabel: String?
    var queuePosition: Int?
    var receivedBytes: Int
    var apiRetryCount: Int
    var lastProviderNotice: String?
    var candidateSource: String?
    var diagnosticResponse: String?
    var failureBoundary: FailureBoundary?
    var failureMessage: String?
    var compileDiagnostic: String?
    var artifactID: String?
}
```

Add methods `transition(to:at:) -> Bool`, `recordProviderActivity(bytes:at:)`, `recordAPIRetry(attempt:message:at:)`, `recordDiagnosticResponse(_:)`, `fail(boundary:message:at:)`, and `finishReady(artifactID:at:)`. Every method returns without mutation after a terminal stage. API retry notice text follows the same bounded-diagnostic rule.

- [ ] **Step 4: Add an exact legacy decoder and deterministic precedence**

`LegacyRemixSessionV1` mirrors schema 1 exactly. Migration precedence for duplicate copies is:

1. seed lineage nodes remain compiled seed artifacts
2. a generated child candidate source from current batch wins over history, then lineage
3. compile diagnostic classification wins over a generic failure string
4. exact same-child transcript recovery may fill an empty candidate only for `No ISF in reply`
5. any legacy live state becomes Interrupted unless a complete candidate can enter local Extracting or Compiling

`RemixSession.init(from:)` reads `schemaVersion` first and delegates to v1 migration or v2 decoding. Because `apiRetryCount` and `lastProviderNotice` are later additions to schema 2, the v2 run-record decoder uses `decodeIfPresent`, defaulting to zero and nil. Include both a literal pre-change schema-v2 fixture and `remix-schema-v2-mid-batch.json`; prove decode, encode, decode is idempotent without losing live-stage or candidate evidence. Task 7 owns restoration normalization and local resume so this persistence task remains independently buildable. `encode(to:)` writes only schema 2 fields.

- [ ] **Step 5: Keep `RemixNode` backward-decodable but artifact-only in new code**

Retain legacy status cases solely so schema 1 can decode. Add a constructor for new artifacts that always sets `.compiled`; no new provider, extraction, or failure state may be stored in `RemixNode`.

- [ ] **Step 6: Run persistence tests twice and prove idempotence**

Run the Step 2 command twice. Expected: both runs pass and no session fixture is quarantined.

- [ ] **Step 7: Commit schema v2**

```bash
git add App/TrueISFEditor/Remix/RemixChildRunRecord.swift \
  App/TrueISFEditor/Remix/LegacyRemixSessionV1.swift \
  App/TrueISFEditor/Remix/RemixNode.swift App/TrueISFEditor/Remix/RemixSession.swift \
  App/TrueISFEditor/Remix/RemixSessionStore.swift \
  App/TrueISFEditorTests/RemixChildRunRecordTests.swift \
  App/TrueISFEditorTests/RemixSessionTests.swift \
  App/TrueISFEditorTests/RemixSessionStoreTests.swift \
  App/TrueISFEditorTests/Fixtures/remix-schema-v2-mid-batch.json \
  App/project.yml App/TrueISFEditor.xcodeproj
git commit -m "feat(remix): persist durable child run records"
```

### Task 5: Pipeline-owned serialized native compilation

**Files:**
- Create: `App/TrueISFEditor/Remix/RemixCompiler.swift`
- Create: `App/TrueISFEditorTests/RemixCompilerTests.swift`
- Modify: `App/project.yml`

**Interfaces:**
- Consumes: candidate ISF source validated by Task 3.
- Produces: `RemixCompileResult` through `RemixCompiling.compile(_:) async`, backed in production by a single serial `ISFSceneLoader.load` queue.

- [ ] **Step 1: Write fake-seam and real-native compile tests**

Use a fake compiler for orchestration tests and one opt-in native integration test:

```swift
struct RemixCompileResult: Sendable, Equatable {
    let isValid: Bool
    let diagnostic: String?
    let errorLine: Int?
}

@MainActor
protocol RemixCompiling {
    func compile(_ source: String) async -> RemixCompileResult
}
```

The integration test calls `NativeRemixCompiler.compile` directly with one valid generator and one syntactically invalid shader. It must not construct `RemixThumbnailView`.

- [ ] **Step 2: Run the compiler tests and verify the new types are missing**

```bash
cd App
xcodegen generate
xcodebuild test -project TrueISFEditor.xcodeproj -scheme TrueISFEditor \
  -destination 'platform=macOS,arch=arm64' ARCHS=arm64 ONLY_ACTIVE_ARCH=YES \
  -derivedDataPath ./ddata-remix-pipeline \
  -only-testing:TrueISFEditorTests/RemixCompilerTests
```

- [ ] **Step 3: Implement a serial native compiler adapter**

`NativeRemixCompiler` creates one Metal device at initialization and uses one dedicated serial queue. Inside the queue call `ISFSceneLoader.load(source:device:)`, convert the result to `RemixCompileResult`, and resume the continuation with only scalar Sendable values. Never pass `ISFMSLScene` across the concurrency boundary.

If no Metal device exists, return `RemixCompileResult(isValid: false, diagnostic: "No Metal device is available.", errorLine: nil)`.

- [ ] **Step 4: Run the native compiler test and commit**

Run the Step 2 command. Expected: valid source passes and invalid source returns a compiler diagnostic.

```bash
git add App/TrueISFEditor/Remix/RemixCompiler.swift \
  App/TrueISFEditorTests/RemixCompilerTests.swift App/project.yml App/TrueISFEditor.xcodeproj
git commit -m "feat(remix): compile candidates before lineage insertion"
```

### Task 6: Launch-gated scheduler and Stop race semantics

**Files:**
- Create: `App/TrueISFEditor/Remix/RemixBatchRunController.swift`
- Rewrite: `App/TrueISFEditor/Remix/RemixGenerator.swift:3-188`
- Rewrite tests: `App/TrueISFEditorTests/RemixGeneratorTests.swift`
- Create: `App/TrueISFEditorTests/RemixBatchRunControllerTests.swift`
- Modify: `App/project.yml`

**Interfaces:**
- Consumes: detailed provider, response parser, native compiler, immutable child run records, max worker count.
- Produces: ordered `RemixPipelineUpdate` callbacks and a `RemixBatchRunController.stop()` that closes launches before cancelling registered provider tasks.

- [ ] **Step 1: Write deterministic scheduler tests for every Stop boundary**

Use continuations in fakes so tests control exact timing. Cover:

- Stop before initial launch creates no provider call and terminalizes every run as Cancelled
- Stop with two active and three queued cancels two provider tasks, launches none of the queued three, and terminalizes all five
- Stop after an authoritative result but before extraction lets that child reach Ready
- Stop during extraction lets that child finish local work
- Stop during compilation lets that child finish local work
- one provider failure does not block sibling backfill while the gate is open
- first terminal transition wins when Stop and completion callbacks race

Every test ends with:

```swift
XCTAssertTrue(updates.finalRecords.allSatisfy(\.stage.isTerminal))
XCTAssertFalse(updates.finalRecords.contains { $0.stage == .queued || $0.stage == .starting })
```

- [ ] **Step 2: Run the scheduler tests and verify current cancellation behavior fails**

```bash
cd App
xcodegen generate
xcodebuild test -project TrueISFEditor.xcodeproj -scheme TrueISFEditor \
  -destination 'platform=macOS,arch=arm64' ARCHS=arm64 ONLY_ACTIVE_ARCH=YES \
  -derivedDataPath ./ddata-remix-pipeline \
  -only-testing:TrueISFEditorTests/RemixGeneratorTests \
  -only-testing:TrueISFEditorTests/RemixBatchRunControllerTests
```

- [ ] **Step 3: Implement the controller and typed pipeline updates**

Use these shapes:

```swift
enum RemixPipelineUpdate: Equatable {
    case record(RemixChildRunRecord)
    case artifact(RemixNode, record: RemixChildRunRecord)
    case processLiveness(childID: String, isAlive: Bool)
}

@MainActor
final class RemixBatchRunController {
    private(set) var launchGateClosed = false
    private(set) var activeProviderChildIDs: Set<String> = []
    private var providerTasks: [String: Task<AssistRunResult, Error>] = [:]

    var canLaunch: Bool { !launchGateClosed }

    func registerProviderTask(_ task: Task<AssistRunResult, Error>, childID: String) {
        guard !launchGateClosed else { task.cancel(); return }
        providerTasks[childID] = task
    }

    func providerFinished(childID: String) {
        providerTasks.removeValue(forKey: childID)
        activeProviderChildIDs.remove(childID)
    }

    func providerProcessStarted(childID: String) {
        guard providerTasks[childID] != nil else { return }
        activeProviderChildIDs.insert(childID)
    }

    func providerProcessExited(childID: String) {
        activeProviderChildIDs.remove(childID)
    }

    func stop() {
        launchGateClosed = true
        providerTasks.values.forEach { $0.cancel() }
        providerTasks.removeAll()
        activeProviderChildIDs.removeAll()
    }
}
```

The outer scheduler task remains alive after `stop()`. Only registered provider tasks are cancelled. Once a provider task has produced an authoritative `AssistRunResult`, unregister it before extraction. Local extraction and compilation then continue even if Stop arrives.

Translate typed `processStarted`, `processExited`, `timedOut`, and `cancelled` events into `processLiveness` updates and the controller's `activeProviderChildIDs`. A registered Swift task is not proof that its provider process is alive. Tests must prove a child enters the set only after `processStarted`, leaves on exit, timeout, failure, cancellation, and Stop, and can never remain live after its record becomes terminal.

- [ ] **Step 4: Emit truthful ordered stages and boundary failures**

`runChild` emits Starting, Thinking or Receiving events, Retrying for a provider API retry, Extracting, Compiling, then either Ready with an artifact or Failed with `.provider`, `.response`, `.extraction`, or `.compile`. It increments `apiRetryCount` and stores a bounded `lastProviderNotice` on `.apiRetry`. A subsequent provider activity event returns Retrying to Thinking or Receiving, and a completed authoritative response may advance it directly to Extracting. Provider text and candidate source are retained through the run record. It never returns a `.compiled` node before native compile.

- [ ] **Step 5: Run scheduler tests and commit**

Run the Step 2 command. Expected: all Stop boundary tests pass with zero stranded records.

```bash
git add App/TrueISFEditor/Remix/RemixBatchRunController.swift \
  App/TrueISFEditor/Remix/RemixGenerator.swift \
  App/TrueISFEditorTests/RemixGeneratorTests.swift \
  App/TrueISFEditorTests/RemixBatchRunControllerTests.swift App/project.yml App/TrueISFEditor.xcodeproj
git commit -m "feat(remix): make batch scheduling stop-safe"
```

### Task 7: Studio integration, recovery, retry, and truthful aggregate activity

**Files:**
- Create: `App/TrueISFEditor/Remix/RemixPreviewState.swift`
- Modify: `App/TrueISFEditor/Remix/RemixStudioModel.swift:24-870`
- Modify: `App/TrueISFEditor/Remix/RemixSession.swift`
- Modify: `App/TrueISFEditor/Remix/RemixActivity.swift:3-112`
- Modify: `App/TrueISFEditor/Remix/RemixLineage.swift:5-24`
- Modify: `App/TrueISFEditor/Remix/RemixTreeBuilder.swift:14-43`
- Modify: `App/TrueISFEditor/Remix/RemixChildrenCanvasView.swift`
- Modify: `App/TrueISFEditor/Remix/RemixChildCardView.swift`
- Modify: `App/TrueISFEditor/Remix/RemixActivityDrawerView.swift`
- Modify: `App/TrueISFEditor/Remix/RemixLineagePresentation.swift`
- Modify: `App/TrueISFEditor/Remix/RemixThumbnailView.swift:6-201`
- Modify: `App/TrueISFEditorTests/RemixStudioModelTests.swift`
- Modify: `App/TrueISFEditorTests/RemixActivityTests.swift`
- Modify: `App/TrueISFEditorTests/RemixLineageTests.swift`
- Modify: `App/TrueISFEditorTests/RemixThumbnailTests.swift`
- Modify: `App/TrueISFEditorTests/RemixSessionTests.swift`
- Create: `App/TrueISFEditorTests/RemixPreviewStateTests.swift`
- Modify: `App/project.yml`

**Interfaces:**
- Consumes: run records and pipeline updates from Tasks 4 through 6.
- Produces: `currentRuns`, derived aggregate summaries, immediate Ready artifacts, local recovery on restore, and scoped retry with the original immutable request.

- [ ] **Step 1: Write failing model tests for stable slots, recovery, first payoff, and Stop**

Required assertions:

```swift
XCTAssertEqual(model.currentRuns.map(\.id), ["r1-0", "r1-1", "r1-2", "r1-3", "r1-4"])
XCTAssertEqual(model.runSummary.stageCounts[.queued], 3)
XCTAssertEqual(model.runSummary.stageCounts[.receiving], 2)
XCTAssertTrue(model.lineage.node("r1-0") == nil) // before native compile
XCTAssertTrue(model.isGenerating)                // when first sibling reaches Ready
XCTAssertEqual(model.currentRuns.first?.stage, .ready)
XCTAssertNotNil(model.lineage.node("r1-0"))
XCTAssertTrue(model.currentRuns.allSatisfy(\.stage.isTerminal)) // after Stop settles
```

Add a restore test using `remix-2026-08-01-empty-result-session-v1.json`, with r1-0, r1-1, and r1-3 empty sources plus their exact child-tagged complete transcript candidates. The fake compiler must receive all three sources in stable-slot order, all three must become independently recoverable artifacts, and the fake provider call count must remain zero.

Add a separate literal schema-v2 mid-batch restore test: queued, starting, thinking, receiving, and retrying records become Interrupted; Extracting and Compiling records with complete candidates resume only parser/compiler work; no provider call occurs; and no restored record remains live. Add liveness tests proving only `processLiveness(..., true)` adds a child to the transient live set and exit, timeout, cancellation, or any terminal record removes it.

Add preview-state tests proving a pipeline Ready artifact starts preview Pending, preview success becomes Available, a later renderer error becomes Preview Failed without changing the run's Ready stage or removing the artifact, Retry Preview increments only that artifact's attempt and returns it to Pending, and no provider or native pipeline compile is rerun. A literal earlier schema-v2 session without preview state defaults to an empty map.

- [ ] **Step 2: Run focused model tests and verify they fail**

```bash
cd App
xcodebuild test -project TrueISFEditor.xcodeproj -scheme TrueISFEditor \
  -destination 'platform=macOS,arch=arm64' ARCHS=arm64 ONLY_ACTIVE_ARCH=YES \
  -derivedDataPath ./ddata-remix-pipeline \
  -only-testing:TrueISFEditorTests/RemixStudioModelTests \
  -only-testing:TrueISFEditorTests/RemixActivityTests \
  -only-testing:TrueISFEditorTests/RemixLineageTests \
  -only-testing:TrueISFEditorTests/RemixThumbnailTests \
  -only-testing:TrueISFEditorTests/RemixSessionTests \
  -only-testing:TrueISFEditorTests/RemixPreviewStateTests
```

- [ ] **Step 3: Publish run records and derive aggregate activity**

Replace `@Published currentBatch: [RemixNode]` with ordered `@Published currentRuns: [RemixChildRunRecord]`. Aggregate activity is computed from records and reports stage counts, terminal count, active worker count, queue count, earliest start, and latest provider activity. `appendLog` records last activity before humanized transcript filtering.

Add `@Published private(set) var activeProviderChildIDs: Set<String> = []`. Apply `.processLiveness` only to a matching nonterminal child, and remove the ID whenever that child becomes terminal. This set is transient and is the sole source for UI claims that a provider process is alive; never restore or infer it from a task, spinner, stage, or timestamp.

Expose that data as `var runSummary: RemixRunSummary`, where `RemixRunSummary` is a pure Equatable value with `stageCounts`, `terminalCount`, `totalCount`, `activeWorkerCount`, `queueCount`, `earliestStart`, and `latestProviderActivity`.

```swift
struct RemixRunSummary: Equatable {
    let stageCounts: [RemixChildRunRecord.Stage: Int]
    let terminalCount: Int
    let totalCount: Int
    let activeWorkerCount: Int
    let queueCount: Int
    let earliestStart: Date?
    let latestProviderActivity: Date?
}
```

Expose stable view input without recreating execution state in `RemixNode`:

```swift
struct RemixChildViewItem: Identifiable, Equatable {
    let run: RemixChildRunRecord
    let artifact: RemixNode?
    let preview: RemixPreviewState?
    var id: String { run.id }
}

var childViewItems: [RemixChildViewItem] {
    currentRuns.map { run in
        let artifact = run.artifactID.flatMap { lineage.node($0) }
        return RemixChildViewItem(
            run: run,
            artifact: artifact,
            preview: artifact.flatMap { previewStates[$0.id] }
        )
    }
}
```

Do not map unequal stages to a percentage. Determinate progress is terminal child count divided by total child count only.

- [ ] **Step 4: Apply pipeline updates with first-terminal-transition-wins**

Add internal `func applyPipelineUpdate(_ update: RemixPipelineUpdate)`. When `.record` arrives, replace only the matching stable slot if its existing record is not terminal. When `.artifact` arrives, insert the artifact into lineage and apply the Ready record in one main-actor operation. The first Ready child appears while `isGenerating` remains true for active siblings.

- [ ] **Step 5: Replace parent-task cancellation with controller Stop**

`cancelGeneration()` calls the active batch controller's `stop()`, immediately marks unlaunched queued records Cancelled, and lets the generator settle active provider and local tasks. It does not cancel the outer generation task. Completion derives the final batch state from terminal records.

- [ ] **Step 6: Run local recovery and scoped retry through the same pipeline**

On schema-v1 or schema-v2 restore, records in Extracting or Compiling with complete candidates run through parser and compiler without a provider. Normalize every restored provider-owned or queued live stage to Interrupted, clear transient process-liveness state, and never auto-launch provider work. A user-triggered Retry uses the stored request, stable child ID, and optional explicit steer override. It clears only that child's diagnostics, source, and terminal fields, then replaces the terminal record with a fresh Queued record in the same stable slot. Keep that separate from the durable Retrying stage, which means only that the provider reported an internal API retry or rate-limit wait.

- [ ] **Step 7: Remove view-owned compilation as execution truth**

Create this separate persisted view-state seam:

```swift
struct RemixPreviewState: Codable, Equatable {
    enum Stage: String, Codable { case pending, available, failed }
    var stage: Stage
    var attempt: Int
    var diagnostic: String?
    var updatedAt: Date
}
```

Store `previewStates: [String: RemixPreviewState]` by artifact ID in `RemixSession` with `decodeIfPresent` defaulting to an empty map. On restore, a Ready artifact missing from the map is initialized lazily as Pending without changing its run. `RemixThumbnailView` reports pending, available, or renderer failure after Ready through model methods that update only this map. Remove `markCompileResult` from `RemixStudioModel`; no preview callback changes execution stage or lineage insertion. A preview failure keeps the native-compiled artifact and Ready run intact. `retryPreview(artifactID:)` increments `attempt`, clears the bounded diagnostic, returns to Pending, and causes only that thumbnail controller to reload.

- [ ] **Step 8: Bridge existing views to stable run items so this plan builds independently**

Make the canvas iterate `model.childViewItems`; make cards accept `run` plus optional `artifact`; make Activity derive from `runSummary`; and make Lineage render only actual artifacts. Keep the existing layout and action density for this task. The canvas workspace plan will simplify those surfaces, but the reliability plan must compile, test, and show queued through terminal slots on its own.

- [ ] **Step 9: Run focused model tests and commit**

Run the Step 2 command. Expected: all focused tests pass.

```bash
git add App/TrueISFEditor/Remix/RemixStudioModel.swift \
  App/TrueISFEditor/Remix/RemixPreviewState.swift \
  App/TrueISFEditor/Remix/RemixSession.swift \
  App/TrueISFEditor/Remix/RemixActivity.swift App/TrueISFEditor/Remix/RemixLineage.swift \
  App/TrueISFEditor/Remix/RemixTreeBuilder.swift \
  App/TrueISFEditor/Remix/RemixChildrenCanvasView.swift \
  App/TrueISFEditor/Remix/RemixChildCardView.swift \
  App/TrueISFEditor/Remix/RemixActivityDrawerView.swift \
  App/TrueISFEditor/Remix/RemixLineagePresentation.swift \
  App/TrueISFEditor/Remix/RemixThumbnailView.swift \
  App/TrueISFEditorTests/RemixStudioModelTests.swift \
  App/TrueISFEditorTests/RemixActivityTests.swift \
  App/TrueISFEditorTests/RemixLineageTests.swift \
  App/TrueISFEditorTests/RemixThumbnailTests.swift \
  App/TrueISFEditorTests/RemixSessionTests.swift \
  App/TrueISFEditorTests/RemixPreviewStateTests.swift App/project.yml App/TrueISFEditor.xcodeproj
git commit -m "feat(remix): drive studio from durable child runs"
```

### Task 8: Reliability verification and shared-runner live smoke gate

**Files:**
- Modify only if a regression is found: files changed in Tasks 1 through 7.

**Interfaces:**
- Consumes: complete reliability implementation.
- Produces: evidence that the August 1 stream is recovered, all deterministic tests pass, the app builds, and ShaderAssist behavior is unchanged.

- [ ] **Step 1: Run the complete focused reliability suite**

```bash
cd App
xcodebuild test -project TrueISFEditor.xcodeproj -scheme TrueISFEditor \
  -destination 'platform=macOS,arch=arm64' ARCHS=arm64 ONLY_ACTIVE_ARCH=YES \
  -derivedDataPath ./ddata-remix-pipeline \
  -only-testing:TrueISFEditorTests/AssistResponseAssemblerTests \
  -only-testing:TrueISFEditorTests/ClaudeCodeRunnerTests \
  -only-testing:TrueISFEditorTests/CodexRunnerTests \
  -only-testing:TrueISFEditorTests/ShaderAssistViewModelTests \
  -only-testing:TrueISFEditorTests/RemixResponseParserTests \
  -only-testing:TrueISFEditorTests/RemixLegacyRecoveryTests \
  -only-testing:TrueISFEditorTests/RemixChildRunRecordTests \
  -only-testing:TrueISFEditorTests/RemixSessionTests \
  -only-testing:TrueISFEditorTests/RemixSessionStoreTests \
  -only-testing:TrueISFEditorTests/RemixCompilerTests \
  -only-testing:TrueISFEditorTests/RemixGeneratorTests \
  -only-testing:TrueISFEditorTests/RemixBatchRunControllerTests \
  -only-testing:TrueISFEditorTests/RemixStudioModelTests \
  -only-testing:TrueISFEditorTests/RemixActivityTests \
  -only-testing:TrueISFEditorTests/RemixLineageTests \
  -only-testing:TrueISFEditorTests/RemixThumbnailTests \
  -only-testing:TrueISFEditorTests/RemixPreviewStateTests
```

Expected: `TEST SUCCEEDED` with zero failures.

- [ ] **Step 2: Run the full app and kit suites**

```bash
cd App
xcodebuild test -project TrueISFEditor.xcodeproj -scheme TrueISFEditor \
  -destination 'platform=macOS,arch=arm64' ARCHS=arm64 ONLY_ACTIVE_ARCH=YES \
  -derivedDataPath ./ddata-remix-pipeline

cd ..
swift test --package-path ShadertoyISFKit
```

Expected: both suites pass with zero failures.

- [ ] **Step 3: Build arm64 Debug**

```bash
cd App
xcodebuild -project TrueISFEditor.xcodeproj -scheme TrueISFEditor \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=YES -derivedDataPath ./ddata-remix-pipeline build
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 4: Stop for approval, then run the mandatory live ShaderAssist compatibility smoke**

First run timeout salvage with a deterministic local fixture; it uses zero provider sessions. Before any live smoke, calculate the actual input size of each planned prompt, disclose the token and shared-subscription estimate to Conner, and stop for explicit approval. The live packet is capped at exactly six ordinary provider sessions: Suggestions, Apply Preview, Diagnose and Fix, Research, Quick Goals, and one cancellation run. It is separate from the 10, 15, and 45-session Remix qualification gates but draws from the same subscription pool.

After approval and staging with `./scripts/run-latest.sh`, run only those six sessions. Confirm final-message parsing, humanized transcript, editor mutation behavior, and cancellation match the prior app. If an environmental failure consumes a session, report the consumed count and obtain approval before adding a replacement; never silently exceed six.

- [ ] **Step 5: Run the CSO provider-boundary review**

Verify typed event parsing cannot execute provider text, all safety flags remain pinned, raw output remains bounded, and no error result becomes success. Fix any blocker before staging the UI plan.

- [ ] **Step 6: Commit verification-only fixes if any**

Stage only reliability files, inspect `git diff --cached --name-only`, and commit with:

```bash
git commit -m "test(remix): verify reliable provider pipeline"
```

Do not push.
