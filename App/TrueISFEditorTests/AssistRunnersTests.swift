import XCTest

@MainActor
final class CodexRunnerTests: XCTestCase {
    func testBuildsCodexExecArgv() async throws {
        let fake = ClaudeCodeRunnerTests.FakeProcess(
            stdout: "{\"type\":\"item.completed\",\"item\":{\"type\":\"agent_message\",\"text\":\"ok\"}}",
            exitCode: 0, stderr: "")
        let runner = CodexRunner(binary: URL(fileURLWithPath: "/x/codex"), process: { fake })
        _ = try await runner.run(prompt: "P", system: "S", model: "gpt-5-codex")
        let args = runner.lastArgsForTest
        XCTAssertEqual(args.first, "exec")
        XCTAssertTrue(args.contains("--json"))
        XCTAssertTrue(args.contains("-s")); XCTAssertTrue(args.contains("read-only"))
        XCTAssertTrue(args.contains("--skip-git-repo-check"))
        // CSO trifecta guard: user's global hooks/config must never re-enter the codex run.
        XCTAssertTrue(args.contains("--ignore-user-config"))
        XCTAssertTrue(args.contains("-m")); XCTAssertTrue(args.contains("gpt-5-codex"))
        // system is prepended to the prompt (codex has no --append-system-prompt)
        XCTAssertTrue(args.last?.contains("S") == true && args.last?.contains("P") == true)
    }

    // CSO M11 invariant: the Codex sandbox must stay `read-only` and never escalate to a
    // write/network-enabling mode — a higher mode would open a live prompt-injection exfil path
    // (read-only ≠ no-file-read; only the network-off default stops exfiltration).
    func testCodexSandboxIsPinnedReadOnlyAndNeverEscalated() async throws {
        XCTAssertEqual(CodexRunner.sandboxMode, "read-only")
        let fake = ClaudeCodeRunnerTests.FakeProcess(
            stdout: #"{"type":"item.completed","item":{"type":"agent_message","text":"ok"}}"#,
            exitCode: 0, stderr: "")
        let runner = CodexRunner(binary: URL(fileURLWithPath: "/x/codex"), process: { fake })
        _ = try await runner.run(prompt: "P", system: "S", model: nil)
        let args = runner.lastArgsForTest
        let sIdx = try XCTUnwrap(args.firstIndex(of: "-s"))
        XCTAssertEqual(args[sIdx + 1], "read-only")
        for forbidden in ["workspace-write", "danger-full-access", "--dangerously-bypass-approvals-and-sandbox"] {
            XCTAssertFalse(args.contains(forbidden), "must never launch with \(forbidden)")
        }
    }

    /// Timeout salvage (Codex analog): a completed agent_message in the partial stream is the
    /// answer — return it instead of discarding the run.
    func testCodexTimeoutSalvagesCompletedAgentMessage() async throws {
        let partial = "{\"type\":\"item.completed\",\"item\":{\"type\":\"agent_message\",\"text\":\"DONE\"}}"
        let runner = CodexRunner(binary: URL(fileURLWithPath: "/x/codex"),
                                 process: { ClaudeCodeRunnerTests.TimingOutProcess(partial: partial) })
        let final = try await runner.run(prompt: "P", system: "S", model: nil)
        XCTAssertEqual(final, "DONE")
    }

    func testCodexDetailedAgentMessageIsSuccessfulAgentMessageResponse() async throws {
        let stream = """
        {"type":"item.completed","item":{"id":"item_0","type":"agent_message","text":"DONE"}}
        """
        let runner = CodexRunner(
            binary: URL(fileURLWithPath: "/x/codex"),
            process: { ClaudeCodeRunnerTests.FakeProcess(stdout: stream, exitCode: 0, stderr: "") }
        )
        guard let detailed = runner as? AssistDetailedProvider else {
            return XCTFail("Codex runner must expose the typed detailed contract")
        }
        let events = AssistEventBox()
        let result = try await detailed.runDetailed(
            prompt: "P", system: "S", model: nil, timeout: 1,
            onEvent: { events.append($0) }, onRawLine: { _ in }
        )
        XCTAssertEqual(result.response, "DONE")
        XCTAssertEqual(result.source, .agentMessage)
        XCTAssertTrue(result.observedSuccessfulResult)
        XCTAssertEqual(events.events, [
            .assistantMessage(
                messageID: "item_0", stopReason: "end_turn",
                blocks: [AssistTextBlock(index: 0, text: "DONE")]
            ),
            .successfulResult(""),
            .processExited(0),
        ])
    }

    func testCodexDetailedErrorOverridesEarlierAgentMessage() async {
        let stream = """
        {"type":"item.completed","item":{"id":"item_0","type":"agent_message","text":"DONE"}}
        {"type":"turn.failed","error":{"message":"quota exhausted"}}
        """
        let runner = CodexRunner(
            binary: URL(fileURLWithPath: "/x/codex"),
            process: { ClaudeCodeRunnerTests.FakeProcess(stdout: stream, exitCode: 0, stderr: "") }
        )
        guard let detailed = runner as? AssistDetailedProvider else {
            return XCTFail("Codex runner must expose the typed detailed contract")
        }
        do {
            _ = try await detailed.runDetailed(
                prompt: "P", system: "S", model: nil, timeout: 1,
                onEvent: { _ in }, onRawLine: { _ in }
            )
            XCTFail("expected provider failure")
        } catch let AssistRunError.processFailed(message) {
            XCTAssertEqual(message, "quota exhausted")
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    func testCodexTimeoutWithoutAgentMessageStillThrows() async {
        let partial = "{\"type\":\"item.started\",\"item\":{\"type\":\"agent_message\"}}"
        let runner = CodexRunner(binary: URL(fileURLWithPath: "/x/codex"),
                                 process: { ClaudeCodeRunnerTests.TimingOutProcess(partial: partial) })
        do { _ = try await runner.run(prompt: "P", system: "S", model: nil); XCTFail("expected timeout") }
        catch AssistRunError.timedOut { /* expected */ }
        catch { XCTFail("wrong error \(error)") }
    }

    func testCodexDefaultModelOmitsDashM() async throws {
        let fake = ClaudeCodeRunnerTests.FakeProcess(
            stdout: #"{"type":"item.completed","item":{"type":"agent_message","text":"ok"}}"#,
            exitCode: 0, stderr: "")
        let runner = CodexRunner(binary: URL(fileURLWithPath: "/x/codex"), process: { fake })
        _ = try await runner.run(prompt: "P", system: "", model: nil)
        XCTAssertFalse(runner.lastArgsForTest.contains("-m"))
    }

    func testCodexLaunchEnvironmentAddsExecutableDirectoryToPath() {
        let executable = URL(fileURLWithPath: "/Users/me/.nvm/versions/node/v22.0.0/bin/codex")
        let env = RealProcess.assistLaunchEnvironment(
            executable: executable,
            base: ["PATH": "/usr/bin:/bin"])
        let parts = env["PATH"]?.split(separator: ":").map(String.init) ?? []
        XCTAssertEqual(parts.first, "/Users/me/.nvm/versions/node/v22.0.0/bin")
        XCTAssertTrue(parts.contains("/opt/homebrew/bin"))
        XCTAssertTrue(parts.contains("/usr/local/bin"))
        XCTAssertTrue(parts.contains("/usr/bin"))
    }

    func testProviderSelectionUsesCodexModelOnlyWhenCodexSelected() {
        let suiteName = "AssistProviderSelectionTests-\(UUID().uuidString)"
        let suite = UserDefaults(suiteName: suiteName)!
        defer { suite.removePersistentDomain(forName: suiteName) }

        suite.set("codex", forKey: "assistProvider")
        suite.set("sonnet", forKey: "assistClaudeModel")
        suite.set("gpt-5-codex", forKey: "assistCodexModel")
        var selection = AssistProviderSelection.current(defaults: suite)
        XCTAssertEqual(selection.kind, .codex)
        XCTAssertEqual(selection.model, "gpt-5-codex")
        XCTAssertEqual(selection.caption, "Using OpenAI · Codex · gpt-5-codex")

        suite.set("", forKey: "assistCodexModel")
        selection = AssistProviderSelection.current(defaults: suite)
        XCTAssertNil(selection.model)
        XCTAssertEqual(selection.caption, "Using OpenAI · Codex · default")

        suite.set("claude", forKey: "assistProvider")
        selection = AssistProviderSelection.current(defaults: suite)
        XCTAssertEqual(selection.kind, .claude)
        XCTAssertEqual(selection.model, "sonnet")
    }

    func testCodexFinalMessageExtractsAgentMessage() {
        // Real captured codex --json schema.
        let stream = """
        {"type":"thread.started","thread_id":"x"}
        {"type":"turn.started"}
        {"type":"item.completed","item":{"id":"item_0","type":"agent_message","text":"FINAL"}}
        {"type":"turn.completed","usage":{}}
        """
        XCTAssertEqual(CodexRunner.finalMessage(fromCodexJSON: stream), "FINAL")
    }

    func testCodexErrorMessageExtractsFromStream() {
        let stream = """
        {"type":"thread.started","thread_id":"x"}
        {"type":"turn.started"}
        {"type":"error","message":"You've hit your usage limit. Try again at 3:09 PM."}
        {"type":"turn.failed","error":{"message":"You've hit your usage limit. Try again at 3:09 PM."}}
        """
        XCTAssertEqual(CodexRunner.errorMessage(fromCodexJSON: stream),
                       "You've hit your usage limit. Try again at 3:09 PM.")
    }

    func testCodexErrorMessageNilWhenNoErrorEvent() {
        let stream = """
        {"type":"turn.started"}
        {"type":"item.completed","item":{"type":"agent_message","text":"ok"}}
        {"type":"turn.completed","usage":{}}
        """
        XCTAssertNil(CodexRunner.errorMessage(fromCodexJSON: stream))
    }

    // Regression: codex puts the real failure in the STDOUT JSON stream while STDERR only carries the
    // benign "Reading additional input from stdin..." status line. The runner must surface the real
    // error, not the stdin status line. (Root-caused 2026-06-13 from a live usage-limit failure.)
    func testCodexSurfacesJSONErrorNotStdinStatusLine() async {
        let stream = """
        {"type":"turn.started"}
        {"type":"error","message":"You've hit your usage limit. Try again at 3:09 PM."}
        {"type":"turn.failed","error":{"message":"You've hit your usage limit. Try again at 3:09 PM."}}
        """
        let fake = ClaudeCodeRunnerTests.FakeProcess(
            stdout: stream, exitCode: 1, stderr: "Reading additional input from stdin...")
        let runner = CodexRunner(binary: URL(fileURLWithPath: "/x/codex"), process: { fake })
        do {
            _ = try await runner.run(prompt: "P", system: "S", model: nil)
            XCTFail("expected throw")
        } catch let AssistRunError.processFailed(msg) {
            XCTAssertTrue(msg.contains("usage limit"), "should surface the real error, got: \(msg)")
            XCTAssertFalse(msg.contains("Reading additional input"),
                           "must not surface the benign stdin status line")
        } catch { XCTFail("wrong error: \(error)") }
    }

    func testCodexBinaryNotFound() async {
        let runner = CodexRunner(binary: nil)
        do { _ = try await runner.run(prompt: "P", system: "S", model: nil); XCTFail("expected throw") }
        catch let e as AssistRunError { XCTAssertEqual(e, .binaryNotFound) }
        catch { XCTFail("wrong error") }
    }

    // N8 — the auth classifier must match known CLI sign-in phrasings, not bare substrings:
    // "auth" also matched "author" in shader text echoed to output, misreporting real failures
    // as "isn't signed in".
    func testAuthorInOutput_isNotMisclassifiedAsAuthFailure() {
        let e = AssistErrorMapper.error(stderr: "shader by author xyz: compile failed", stdout: "")
        guard case .processFailed = e else { return XCTFail("misclassified as auth: \(e)") }
    }
    func testKnownSignInPhrasings_classifyAsNotAuthenticated() {
        for out in ["Please run /login", "Not authenticated. Run codex login.",
                    "Invalid API key provided", "OAuth token has expired — please sign in"] {
            XCTAssertEqual(AssistErrorMapper.error(stderr: out, stdout: ""), .notAuthenticated,
                           "should classify as auth: \(out)")
        }
    }
}

// N6 — one bounded-append everywhere (transcripts, logs) instead of five hand-rolled copies.
final class BoundedAppendTests: XCTestCase {
    func testDropsFromTheFrontAtCap() {
        var a: [Int] = []
        for i in 0..<10 { a.appendBounded(i, max: 4) }
        XCTAssertEqual(a, [6, 7, 8, 9])
    }
    func testUnderCapKeepsEverything() {
        var a: [Int] = []
        for i in 0..<3 { a.appendBounded(i, max: 4) }
        XCTAssertEqual(a, [0, 1, 2])
    }
}

final class SkillPreambleTests: XCTestCase {
    private func tempFile(_ contents: String) throws -> String {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("skilltest-\(UUID().uuidString).md")
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url.path
    }

    func testLoadConcatenatesPresentSkillFiles() throws {
        let a = try tempFile("ALPHA BODY")
        let b = try tempFile("BETA BODY")
        let out = SkillPreamble.load(paths: [a, b], cap: 100_000)
        XCTAssertTrue(out.contains("ALPHA BODY"))
        XCTAssertTrue(out.contains("BETA BODY"))
    }

    func testLoadCapsLength() throws {
        let a = try tempFile(String(repeating: "x", count: 5000))
        let out = SkillPreamble.load(paths: [a], cap: 200)
        XCTAssertLessThanOrEqual(out.count, 200)
    }

    func testLoadFallsBackWhenNoFiles() {
        let out = SkillPreamble.load(paths: ["/nope/does/not/exist.md"], cap: 100_000)
        XCTAssertTrue(out.contains("ISF"))   // built-in primer
        XCTAssertFalse(out.isEmpty)
    }

    /// Regression (2026-07-08): the real skill set — isf-shader-development (~15.5K) + shader-dev
    /// (~16.7K) + the corpus catalog (~38K) ≈ 80K+ chars — must survive the DEFAULT cap. The prior
    /// default of 12,000 silently truncated it mid-file, so shader-dev and the catalog never reached
    /// the model. Exercises the default cap specifically (every other test pins an explicit cap).
    func testDefaultCapLoadsRealSizedSkillSetWithoutTruncation() throws {
        let a = String(repeating: "A", count: 43_000)
        let b = String(repeating: "B", count: 43_000)
        let out = SkillPreamble.load(paths: [try tempFile(a), try tempFile(b)])   // default cap
        XCTAssertTrue(out.contains(a), "first file truncated under the default cap")
        XCTAssertTrue(out.contains(b), "second file dropped under the default cap")
    }
}
