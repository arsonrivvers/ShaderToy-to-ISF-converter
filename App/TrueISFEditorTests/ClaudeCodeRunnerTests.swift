import XCTest

@MainActor
final class ClaudeCodeRunnerTests: XCTestCase {
    /// Streaming fake: emits canned stdout line-by-line via onLine, then returns the full output.
    final class FakeProcess: ProcessRunning, @unchecked Sendable {
        var stdout: String; var exitCode: Int32; var stderr: String
        init(stdout: String, exitCode: Int32, stderr: String) { self.stdout = stdout; self.exitCode = exitCode; self.stderr = stderr }
        func run(executable: URL, args: [String], timeout: TimeInterval,
                 onLine: @escaping @Sendable (String) -> Void) throws -> ProcessOutput {
            for line in stdout.split(separator: "\n", omittingEmptySubsequences: false) { onLine(String(line)) }
            return ProcessOutput(stdout: stdout, stderr: stderr, exitCode: exitCode)
        }
    }

    func testBuildsStreamJsonArgv() async throws {
        let fake = FakeProcess(stdout: "{\"type\":\"result\",\"result\":\"ok\"}", exitCode: 0, stderr: "")
        let runner = ClaudeCodeRunner(binary: URL(fileURLWithPath: "/x/claude"), process: { fake })
        _ = try await runner.run(prompt: "P", system: "S", model: "sonnet")
        let args = runner.lastArgsForTest
        XCTAssertEqual(args.first, "-p")
        XCTAssertTrue(args.contains("--output-format")); XCTAssertTrue(args.contains("stream-json"))
        XCTAssertTrue(args.contains("--verbose"))
        XCTAssertTrue(args.contains("--include-partial-messages"))
        XCTAssertTrue(args.contains("--model")); XCTAssertTrue(args.contains("sonnet"))
        XCTAssertTrue(args.contains("--append-system-prompt")); XCTAssertTrue(args.contains("S"))
        XCTAssertTrue(args.contains("P"))
    }

    /// CSO CRITICAL-1/HIGH-1 regression guard: the tool-restriction flags must always be present so a
    /// prompt-injected shader can't reach Bash/Edit/MCP, regardless of the host's settings.json.
    /// `--tools ""` strips the ENTIRE built-in toolset (stronger than the old plan mode, which also
    /// broke generation: the model planned + called ExitPlanMode instead of emitting the shader).
    func testAlwaysPinsSafetyFlags() async throws {
        let fake = FakeProcess(stdout: "{\"type\":\"result\",\"result\":\"ok\"}", exitCode: 0, stderr: "")
        let runner = ClaudeCodeRunner(binary: URL(fileURLWithPath: "/x/claude"), process: { fake })
        _ = try await runner.run(prompt: "P", system: "S", model: "sonnet")
        let args = runner.lastArgsForTest
        let toolsIdx = args.firstIndex(of: "--tools")
        XCTAssertNotNil(toolsIdx)
        XCTAssertEqual(args[toolsIdx! + 1], "")              // empty toolset, structurally
        let disallowIdx = args.firstIndex(of: "--disallowedTools")
        XCTAssertNotNil(disallowIdx)
        XCTAssertEqual(args[disallowIdx! + 1], "LSP")        // --tools "" alone still leaks LSP
        XCTAssertTrue(args.contains("--allowedTools"))
        XCTAssertTrue(args.contains("--strict-mcp-config"))
        XCTAssertTrue(args.contains("--disable-slash-commands"))
        // plan mode must STAY GONE: it made the model answer with a plan, not the artifact
        // (3/3 remix children failed "No ISF in reply" on 2026-06-12).
        XCTAssertFalse(args.contains("--permission-mode"))
    }

    func testPartialStreamEventsDoNotInflateLegacyCallbackCount() async throws {
        let json = """
        {"type":"system","subtype":"init"}
        {"type":"stream_event","event":{"type":"content_block_start","index":0}}
        {"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"hi"}},"message_id":"m1"}
        {"type":"stream_event","event":{"type":"content_block_stop","index":0}}
        {"type":"assistant","message":{"id":"m1","stop_reason":"end_turn","content":[{"type":"text","text":"hi"}]}}
        {"type":"result","is_error":false,"result":"DONE"}
        """
        let fake = FakeProcess(stdout: json, exitCode: 0, stderr: "")
        let runner = ClaudeCodeRunner(binary: URL(fileURLWithPath: "/x/claude"), process: { fake })
        let box = EventBox()
        let final = try await runner.run(prompt: "P", system: "S", model: "m") { line in box.append(line) }
        XCTAssertEqual(final, "DONE")                       // result event preferred
        XCTAssertEqual(box.lines.count, 3)                  // same system/assistant/result legacy contract
        XCTAssertFalse(box.lines.contains { $0.contains("stream_event") })
    }

    func testDetailedRunDecodesPartialDeltaAndKeepsAllRawLines() async throws {
        let json = """
        {"type":"system","subtype":"init","session_id":"s1"}
        {"type":"system","subtype":"api_retry","attempt":2,"message":"Rate limit reached"}
        {"type":"stream_event","message_id":"m1","event":{"type":"content_block_delta","index":2,"delta":{"type":"text_delta","text":"hi"}}}
        {"type":"assistant","message":{"id":"m1","stop_reason":"end_turn","content":[{"type":"text","text":"hi"}]}}
        {"type":"result","is_error":false,"result":""}
        """
        let runner = ClaudeCodeRunner(
            binary: URL(fileURLWithPath: "/x/claude"),
            process: { FakeProcess(stdout: json, exitCode: 0, stderr: "") }
        )
        guard let detailed = runner as? AssistDetailedProvider else {
            return XCTFail("Claude runner must expose the typed detailed contract")
        }
        let events = AssistEventBox()
        let raw = EventBox()
        let result = try await detailed.runDetailed(
            prompt: "P", system: "S", model: "m", timeout: 1,
            onEvent: { events.append($0) }, onRawLine: { raw.append($0) }
        )
        XCTAssertEqual(result.response, "hi")
        XCTAssertEqual(result.source, .assistantMessage)
        XCTAssertTrue(events.events.contains(.sessionStarted(id: "s1")))
        XCTAssertTrue(events.events.contains(.apiRetry(attempt: 2, message: "Rate limit reached")))
        XCTAssertTrue(events.events.contains(.textDelta(messageID: "m1", blockIndex: 2, text: "hi")))
        XCTAssertEqual(raw.lines.count, 5)
    }

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
        let response = try await runner.run(prompt: "P", system: "S", model: "m")
        XCTAssertEqual(response, assistant)
        XCTAssertTrue(runner.lastArgsForTest.contains("--include-partial-messages"))
    }

    func testClaudeFinalFallsBackToAssistantTextWhenNoResult() {
        let json = "{\"type\":\"assistant\",\"message\":{\"content\":[{\"type\":\"text\",\"text\":\"AB\"}]}}"
        XCTAssertEqual(ClaudeCodeRunner.finalMessage(fromStreamJSON: json), "AB")
    }

    func testAuthErrorMapsToNotAuthenticated() async {
        let fake = FakeProcess(stdout: "", exitCode: 1, stderr: "Invalid API key · Please run /login")
        let runner = ClaudeCodeRunner(binary: URL(fileURLWithPath: "/x/claude"), process: { fake })
        do { _ = try await runner.run(prompt: "P", system: "S", model: "m"); XCTFail("expected throw") }
        catch let e as AssistRunError { XCTAssertEqual(e, .notAuthenticated) }
        catch { XCTFail("wrong error \(error)") }
    }

    func testNilBinaryThrowsBinaryNotFound() async {
        let runner = ClaudeCodeRunner(binary: nil, process: { FakeProcess(stdout: "", exitCode: 0, stderr: "") })
        do { _ = try await runner.run(prompt: "P", system: "S", model: "m"); XCTFail("expected throw") }
        catch let e as AssistRunError { XCTAssertEqual(e, .binaryNotFound) }
        catch { XCTFail("wrong error") }
    }

    // MARK: M12 — CLI version floor for the tool-restriction flags

    func testParseVersionExtractsTriple() {
        XCTAssertTrue(ClaudeCodeRunner.parseVersion("2.1.175 (Claude Code)").map { $0 == (2,1,175) } ?? false)
        XCTAssertTrue(ClaudeCodeRunner.parseVersion("claude 10.2.3").map { $0 == (10,2,3) } ?? false)
        XCTAssertNil(ClaudeCodeRunner.parseVersion("no version here"))
    }

    func testIsBelowVerifiedFloor() {
        XCTAssertTrue(ClaudeCodeRunner.isBelowVerifiedFloor(versionOutput: "2.1.174"))   // patch below
        XCTAssertTrue(ClaudeCodeRunner.isBelowVerifiedFloor(versionOutput: "2.0.999"))   // minor below
        XCTAssertTrue(ClaudeCodeRunner.isBelowVerifiedFloor(versionOutput: "1.9.9"))     // major below
        XCTAssertFalse(ClaudeCodeRunner.isBelowVerifiedFloor(versionOutput: "2.1.175"))  // exactly floor
        XCTAssertFalse(ClaudeCodeRunner.isBelowVerifiedFloor(versionOutput: "2.2.0"))    // above
        XCTAssertFalse(ClaudeCodeRunner.isBelowVerifiedFloor(versionOutput: "weird"))    // unknown → no warning
        XCTAssertFalse(ClaudeCodeRunner.isBelowVerifiedFloor(versionOutput: nil))
    }

    func testRunWarnsWhenCLIBelowVerifiedFloor() async throws {
        let fake = FakeProcess(stdout: "{\"type\":\"result\",\"result\":\"ok\"}", exitCode: 0, stderr: "")
        let runner = ClaudeCodeRunner(binary: URL(fileURLWithPath: "/x/claude"),
                                      process: { fake }, versionOutput: { "2.1.100" })
        let box = EventBox()
        _ = try await runner.run(prompt: "P", system: "S", model: "m") { box.append($0) }
        XCTAssertTrue(box.lines.contains { $0.contains("SECURITY") && $0.contains("tool-restriction") },
                      "expected a version warning, got: \(box.lines)")
    }

    func testRunDoesNotWarnWhenCLIAtOrAboveFloor() async throws {
        let fake = FakeProcess(stdout: "{\"type\":\"result\",\"result\":\"ok\"}", exitCode: 0, stderr: "")
        let runner = ClaudeCodeRunner(binary: URL(fileURLWithPath: "/x/claude"),
                                      process: { fake }, versionOutput: { "2.1.175" })
        let box = EventBox()
        _ = try await runner.run(prompt: "P", system: "S", model: "m") { box.append($0) }
        XCTAssertFalse(box.lines.contains { $0.contains("SECURITY") }, "should not warn at/above floor")
    }

    /// Streams its canned stdout, then times out — stands in for a run whose answer landed before
    /// the timer fired (the real 239.3s incident) or one that genuinely wedged.
    final class TimingOutProcess: ProcessRunning, @unchecked Sendable {
        let partial: String
        init(partial: String) { self.partial = partial }
        func run(executable: URL, args: [String], timeout: TimeInterval,
                 onLine: @escaping @Sendable (String) -> Void) throws -> ProcessOutput {
            for line in partial.split(separator: "\n", omittingEmptySubsequences: false) { onLine(String(line)) }
            throw AssistRunError.timedOut(partialStdout: partial)
        }
    }

    /// Timeout salvage: a `result` event in the partial stream means the run FINISHED — the timer
    /// only beat the CLI's teardown. The completed answer must be returned, not discarded (a real
    /// 239.3s suggestions rewrite was lost this way at the old 240s cap).
    func testTimeoutSalvagesCompletedResultEvent() async throws {
        let partial = "{\"type\":\"assistant\",\"message\":{\"content\":[{\"type\":\"text\",\"text\":\"working\"}]}}\n"
            + "{\"type\":\"result\",\"result\":\"DONE\"}"
        let runner = ClaudeCodeRunner(binary: URL(fileURLWithPath: "/x/claude"),
                                      process: { TimingOutProcess(partial: partial) })
        let final = try await runner.run(prompt: "P", system: "S", model: "m")
        XCTAssertEqual(final, "DONE")
    }

    /// No `result` event → the run genuinely didn't finish; assistant text alone must NOT be
    /// salvaged (it's a mid-stream truncation, not an answer). Stays a timeout.
    func testTimeoutWithoutResultEventStillThrows() async {
        let partial = "{\"type\":\"assistant\",\"message\":{\"content\":[{\"type\":\"text\",\"text\":\"half an ans\"}]}}"
        let runner = ClaudeCodeRunner(binary: URL(fileURLWithPath: "/x/claude"),
                                      process: { TimingOutProcess(partial: partial) })
        do { _ = try await runner.run(prompt: "P", system: "S", model: "m"); XCTFail("expected timeout") }
        catch AssistRunError.timedOut { /* expected */ }
        catch { XCTFail("wrong error \(error)") }
    }

    func testTimeoutWithErrorResultSurfacesProviderFailure() async {
        let partial = #"{"type":"result","is_error":true,"result":"provider rejected it"}"#
        let runner = ClaudeCodeRunner(binary: URL(fileURLWithPath: "/x/claude"),
                                      process: { TimingOutProcess(partial: partial) })
        do {
            _ = try await runner.run(prompt: "P", system: "S", model: "m")
            XCTFail("expected provider failure")
        } catch let AssistRunError.processFailed(message) {
            XCTAssertEqual(message, "provider rejected it")
        } catch {
            XCTFail("wrong error \(error)")
        }
    }

    func testTimeoutWithEmptySuccessfulResultButNoAssistantStillThrows() async {
        let partial = #"{"type":"result","is_error":false,"result":""}"#
        let runner = ClaudeCodeRunner(binary: URL(fileURLWithPath: "/x/claude"),
                                      process: { TimingOutProcess(partial: partial) })
        do {
            _ = try await runner.run(prompt: "P", system: "S", model: "m")
            XCTFail("expected timeout")
        } catch AssistRunError.timedOut {
            // Successful completion evidence alone cannot manufacture a response.
        } catch {
            XCTFail("wrong error \(error)")
        }
    }

    func testResultEventExtractorIgnoresAssistantText() {
        XCTAssertNil(ClaudeCodeRunner.resultEvent(fromStreamJSON:
            "{\"type\":\"assistant\",\"message\":{\"content\":[{\"type\":\"text\",\"text\":\"AB\"}]}}"))
        XCTAssertEqual(ClaudeCodeRunner.resultEvent(fromStreamJSON:
            "{\"type\":\"result\",\"result\":\"R\"}"), "R")
    }

    // MARK: Quick Goals hang (2026-07-17) — the result event is completion; teardown is not

    /// Streams its result line, then blocks like a CLI that never exits after answering. Only
    /// cancel() (the grace-kill) unblocks it — it then returns a killed process's exit code.
    final class LingeringProcess: ProcessRunning, @unchecked Sendable {
        private let sema = DispatchSemaphore(value: 0)
        private(set) var cancelCalled = false
        func run(executable: URL, args: [String], timeout: TimeInterval,
                 onLine: @escaping @Sendable (String) -> Void) throws -> ProcessOutput {
            onLine("{\"type\":\"result\",\"result\":\"ok\"}")
            sema.wait()
            return ProcessOutput(stdout: "{\"type\":\"result\",\"result\":\"ok\"}",
                                 stderr: "", exitCode: 15)
        }
        func cancel() { cancelCalled = true; sema.signal() }
    }

    final class EmptyResultLingeringProcess: ProcessRunning, @unchecked Sendable {
        private let sema = DispatchSemaphore(value: 0)
        private let lock = NSLock()
        private var _cancelCalled = false
        var cancelCalled: Bool { lock.lock(); defer { lock.unlock() }; return _cancelCalled }
        private let stdout = """
        {"type":"assistant","message":{"id":"m1","stop_reason":"end_turn","content":[{"type":"text","text":"ok"}]}}
        {"type":"result","is_error":false,"result":""}
        """

        func run(executable: URL, args: [String], timeout: TimeInterval,
                 onLine: @escaping @Sendable (String) -> Void) throws -> ProcessOutput {
            stdout.split(separator: "\n").forEach { onLine(String($0)) }
            sema.wait()
            return ProcessOutput(stdout: stdout, stderr: "", exitCode: 15)
        }

        func cancel() {
            lock.lock(); _cancelCalled = true; lock.unlock()
            sema.signal()
        }
    }

    func testEmptyResultStillArmsTeardownGrace() async throws {
        let process = EmptyResultLingeringProcess()
        let runner = ClaudeCodeRunner(
            binary: URL(fileURLWithPath: "/x/claude"), process: { process }, teardownGrace: 0.01
        )
        let response = try await runner.run(prompt: "P", system: "S", model: "m")
        XCTAssertEqual(response, "ok")
        XCTAssertTrue(process.cancelCalled)
    }

    /// The hang Conner hit: goals JSON streamed ("done in 160.4s" in the Activity pane) but the
    /// CLI process lingered, so run() sat in .running for up to 260 more seconds (or forever on
    /// an inherited-fd pipe). The result event IS protocol completion — the runner must grace-kill
    /// the straggler and return the streamed answer.
    func testGraceKillCompletesRunWhenProcessOutlivesItsResult() async throws {
        let fake = LingeringProcess()
        let runner = ClaudeCodeRunner(binary: URL(fileURLWithPath: "/x/claude"),
                                      process: { fake }, teardownGrace: 0.2)
        let start = Date()
        let final = try await runner.run(prompt: "P", system: "S", model: "m")
        XCTAssertEqual(final, "ok")
        XCTAssertTrue(fake.cancelCalled, "the straggler must be terminated")
        XCTAssertLessThan(Date().timeIntervalSince(start), 5,
                          "must complete at the grace, not the 420s timer")
    }

    /// A non-zero exit AFTER a streamed result event is teardown noise (our own grace-kill, or a
    /// CLI crash-on-exit) — the completed answer must be returned, not mapped to an error.
    func testNonZeroExitAfterResultEventReturnsResult() async throws {
        let fake = FakeProcess(stdout: "{\"type\":\"result\",\"result\":\"ok\"}",
                               exitCode: 15, stderr: "terminated")
        let runner = ClaudeCodeRunner(binary: URL(fileURLWithPath: "/x/claude"), process: { fake })
        let final = try await runner.run(prompt: "P", system: "S", model: "m")
        XCTAssertEqual(final, "ok")
    }

    func testNonZeroExitAfterEmptySuccessfulResultSalvagesCompleteAssistant() async throws {
        let json = """
        {"type":"assistant","message":{"id":"m1","stop_reason":"end_turn","content":[{"type":"text","text":"ok"}]}}
        {"type":"result","is_error":false,"result":""}
        """
        let runner = ClaudeCodeRunner(
            binary: URL(fileURLWithPath: "/x/claude"),
            process: { FakeProcess(stdout: json, exitCode: 15, stderr: "terminated") }
        )
        let response = try await runner.run(prompt: "P", system: "S", model: "m")
        XCTAssertEqual(response, "ok")
    }

    func testTimeoutAfterEmptySuccessfulResultSalvagesCompleteAssistant() async throws {
        let partial = """
        {"type":"assistant","message":{"id":"m1","stop_reason":"end_turn","content":[{"type":"text","text":"ok"}]}}
        {"type":"result","is_error":false,"result":""}
        """
        let runner = ClaudeCodeRunner(
            binary: URL(fileURLWithPath: "/x/claude"),
            process: { TimingOutProcess(partial: partial) }
        )
        let response = try await runner.run(prompt: "P", system: "S", model: "m")
        XCTAssertEqual(response, "ok")
    }

    func testErrorResultOverridesEarlierSuccessfulResponse() async {
        let json = """
        {"type":"assistant","message":{"id":"m1","stop_reason":"end_turn","content":[{"type":"text","text":"looks valid"}]}}
        {"type":"result","is_error":false,"result":"looks valid"}
        {"type":"result","is_error":true,"result":"provider rejected it"}
        """
        let runner = ClaudeCodeRunner(
            binary: URL(fileURLWithPath: "/x/claude"),
            process: { FakeProcess(stdout: json, exitCode: 0, stderr: "") }
        )
        do {
            _ = try await runner.run(prompt: "P", system: "S", model: "m")
            XCTFail("expected provider failure")
        } catch let AssistRunError.processFailed(message) {
            XCTAssertEqual(message, "provider rejected it")
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    /// An is_error result is a FAILED run — it must never be treated as a completed answer
    /// (neither by the timeout salvage nor by the non-zero-exit rescue).
    func testErrorResultEventIsNeverTreatedAsCompletion() {
        XCTAssertNil(ClaudeCodeRunner.resultEvent(fromStreamJSON:
            "{\"type\":\"result\",\"result\":\"boom\",\"is_error\":true}"))
    }

    /// RealProcess regression: pipe EOF needs every fd holder gone — a CLI child that inherited
    /// our pipes kept the post-exit drain blocked with a finished answer on screen. The drain must
    /// be bounded: /bin/sh exits instantly here but its backgrounded sleep holds stdout for 30s.
    func testRealProcessBoundsPipeDrainWhenChildHoldsFDs() throws {
        let start = Date()
        let out = try RealProcess().run(
            executable: URL(fileURLWithPath: "/bin/sh"),
            args: ["-c", "echo READY; sleep 30 &"], timeout: 60, onLine: { _ in })
        XCTAssertEqual(out.exitCode, 0)
        XCTAssertTrue(out.stdout.contains("READY"))
        XCTAssertLessThan(Date().timeIntervalSince(start), 10,
                          "post-exit pipe drain must be bounded, not wait out the orphan")
    }

    /// Production regression (2026-08-03): Claude emitted its complete terminal result object
    /// without a trailing newline, then kept the pipe open. Newline-only delivery hid completion
    /// from the runner until the 420-second timeout forced EOF. A complete JSON frame must stream
    /// immediately so the runner can arm its short teardown grace.
    func testRealProcessStreamsCompleteJSONWithoutTrailingNewlineWhilePipeStaysOpen() throws {
        let process = RealProcess()
        let lines = EventBox()
        let start = Date()
        let out = try process.run(
            executable: URL(fileURLWithPath: "/bin/sh"),
            args: ["-c", #"printf '{\"type\":\"result\",\"result\":\"ok\"}'; sleep 30"#],
            timeout: 2,
            onLine: { line in
                lines.append(line)
                process.cancel()
            }
        )

        XCTAssertEqual(lines.lines, [#"{"type":"result","result":"ok"}"#])
        XCTAssertNotEqual(out.exitCode, 0)
        XCTAssertLessThan(Date().timeIntervalSince(start), 5,
                          "complete JSON must stream before the timeout; RealProcess may then use its bounded 3s pipe drain")
    }

    /// If the CLI later finishes its delimiter as CRLF in separate writes, the eagerly emitted
    /// terminal frame must not be followed by a synthetic raw `"\r"` event.
    func testRealProcessConsumesSplitCRLFAfterUnterminatedTerminalFrame() throws {
        let lines = EventBox()
        _ = try RealProcess().run(
            executable: URL(fileURLWithPath: "/bin/sh"),
            args: ["-c", #"printf '{\"type\":\"result\",\"result\":\"ok\"}'; sleep 0.1; printf '\r'; sleep 0.1; printf '\n'"#],
            timeout: 2,
            onLine: { lines.append($0) }
        )

        XCTAssertEqual(lines.lines, [#"{"type":"result","result":"ok"}"#])
    }

    /// Blocks in run() until cancel() fires — stands in for a long-running CLI that the user stops.
    /// `hasStarted` is a thread-safe flag (not a semaphore) so the test can await it without blocking
    /// the main actor that the @MainActor runner body needs to execute.
    final class BlockingProcess: ProcessRunning, @unchecked Sendable {
        private let release = DispatchSemaphore(value: 0)
        private let lock = NSLock()
        private var _started = false
        private var _cancelCalled = false
        var hasStarted: Bool { lock.lock(); defer { lock.unlock() }; return _started }
        var cancelCalled: Bool { lock.lock(); defer { lock.unlock() }; return _cancelCalled }
        func run(executable: URL, args: [String], timeout: TimeInterval,
                 onLine: @escaping @Sendable (String) -> Void) throws -> ProcessOutput {
            lock.lock(); _started = true; lock.unlock()
            release.wait()   // unblocked only by cancel(); simulates the CLI being terminated
            return ProcessOutput(stdout: "", stderr: "", exitCode: 15)   // SIGTERM-style nonzero exit
        }
        func cancel() { lock.lock(); _cancelCalled = true; lock.unlock(); release.signal() }
    }

    final class LifecycleTimingOutProcess: ProcessLifecycleReporting, @unchecked Sendable {
        private let lock = NSLock()
        private var lifecycleHandler: (@Sendable (ProcessLifecycleEvent) -> Void)?
        private let partial = """
        {"type":"assistant","message":{"id":"m1","stop_reason":"end_turn","content":[{"type":"text","text":"ok"}]}}
        {"type":"result","is_error":false,"result":""}
        """

        func setLifecycleHandler(_ handler: @escaping @Sendable (ProcessLifecycleEvent) -> Void) {
            lock.lock(); lifecycleHandler = handler; lock.unlock()
        }

        func run(executable: URL, args: [String], timeout: TimeInterval,
                 onLine: @escaping @Sendable (String) -> Void) throws -> ProcessOutput {
            lock.lock(); let handler = lifecycleHandler; lock.unlock()
            handler?(.started(pid: 42))
            partial.split(separator: "\n").forEach { onLine(String($0)) }
            handler?(.exited(status: 15))
            throw AssistRunError.timedOut(partialStdout: partial)
        }
    }

    final class LifecycleBlockingProcess: ProcessLifecycleReporting, @unchecked Sendable {
        private let release = DispatchSemaphore(value: 0)
        private let lock = NSLock()
        private var lifecycleHandler: (@Sendable (ProcessLifecycleEvent) -> Void)?
        private var _started = false
        var hasStarted: Bool { lock.lock(); defer { lock.unlock() }; return _started }

        func setLifecycleHandler(_ handler: @escaping @Sendable (ProcessLifecycleEvent) -> Void) {
            lock.lock(); lifecycleHandler = handler; lock.unlock()
        }

        func run(executable: URL, args: [String], timeout: TimeInterval,
                 onLine: @escaping @Sendable (String) -> Void) throws -> ProcessOutput {
            lock.lock(); _started = true; let handler = lifecycleHandler; lock.unlock()
            handler?(.started(pid: 43))
            release.wait()
            handler?(.exited(status: 15))
            return ProcessOutput(stdout: "", stderr: "", exitCode: 15)
        }

        func cancel() { release.signal() }
    }

    final class LateExitTimingOutProcess: ProcessLifecycleReporting, @unchecked Sendable {
        private let lock = NSLock()
        private let releaseExit = DispatchSemaphore(value: 0)
        private var lifecycleHandler: (@Sendable (ProcessLifecycleEvent) -> Void)?

        func setLifecycleHandler(_ handler: @escaping @Sendable (ProcessLifecycleEvent) -> Void) {
            lock.lock(); lifecycleHandler = handler; lock.unlock()
        }

        func run(executable: URL, args: [String], timeout: TimeInterval,
                 onLine: @escaping @Sendable (String) -> Void) throws -> ProcessOutput {
            lock.lock(); let handler = lifecycleHandler; lock.unlock()
            handler?(.started(pid: 44))
            DispatchQueue.global().async { [releaseExit] in
                releaseExit.wait()
                handler?(.exited(status: 15))
            }
            throw AssistRunError.timedOut(partialStdout: "")
        }

        func allowLateExit() { releaseExit.signal() }
    }

    func testDetailedTimeoutPrecedesObservedProcessExit() async throws {
        let runner = ClaudeCodeRunner(
            binary: URL(fileURLWithPath: "/x/claude"), process: { LifecycleTimingOutProcess() }
        )
        guard let detailed = runner as? AssistDetailedProvider else {
            return XCTFail("Claude runner must expose the typed detailed contract")
        }
        let events = AssistEventBox()
        let result = try await detailed.runDetailed(
            prompt: "P", system: "S", model: nil, timeout: 1,
            onEvent: { events.append($0) }, onRawLine: { _ in }
        )
        XCTAssertEqual(result.response, "ok")
        let timedOut = try XCTUnwrap(events.events.firstIndex(of: .timedOut))
        let exited = try XCTUnwrap(events.events.firstIndex(of: .processExited(15)))
        XCTAssertLessThan(timedOut, exited)
    }

    func testDetailedCancellationPrecedesObservedProcessExit() async throws {
        let process = LifecycleBlockingProcess()
        let runner = ClaudeCodeRunner(
            binary: URL(fileURLWithPath: "/x/claude"), process: { process }
        )
        guard let detailed = runner as? AssistDetailedProvider else {
            return XCTFail("Claude runner must expose the typed detailed contract")
        }
        let events = AssistEventBox()
        let task = Task {
            try await detailed.runDetailed(
                prompt: "P", system: "S", model: nil, timeout: 1,
                onEvent: { events.append($0) }, onRawLine: { _ in }
            )
        }
        for _ in 0..<300 where !process.hasStarted {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertTrue(process.hasStarted)
        task.cancel()
        do { _ = try await task.value; XCTFail("expected cancellation") }
        catch is CancellationError { /* expected */ }
        catch { XCTFail("wrong error: \(error)") }
        let cancelled = try XCTUnwrap(events.events.firstIndex(of: .cancelled))
        let exited = try XCTUnwrap(events.events.firstIndex(of: .processExited(15)))
        XCTAssertLessThan(cancelled, exited)
    }

    func testDetailedTimeoutDeliversExitThatArrivesAfterEarlyFlushExactlyOnce() async throws {
        let process = LateExitTimingOutProcess()
        let runner = ClaudeCodeRunner(
            binary: URL(fileURLWithPath: "/x/claude"), process: { process }
        )
        guard let detailed = runner as? AssistDetailedProvider else {
            return XCTFail("Claude runner must expose the typed detailed contract")
        }
        let events = AssistEventBox()
        do {
            _ = try await detailed.runDetailed(
                prompt: "P", system: "S", model: nil, timeout: 1,
                onEvent: { events.append($0) }, onRawLine: { _ in }
            )
            XCTFail("expected timeout")
        } catch AssistRunError.timedOut {
            // Release the lifecycle exit only after the timeout catch has requested an early flush.
        } catch {
            return XCTFail("wrong error \(error)")
        }

        process.allowLateExit()
        for _ in 0..<300 where !events.events.contains(.processExited(15)) {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        let timedOut = try XCTUnwrap(events.events.firstIndex(of: .timedOut))
        let exited = try XCTUnwrap(events.events.firstIndex(of: .processExited(15)))
        XCTAssertLessThan(timedOut, exited)
        XCTAssertEqual(events.events.filter { $0 == .processExited(15) }.count, 1)
    }

    /// M6: cancelling the surrounding Task must terminate the CLI (proc.cancel()) and surface as a
    /// CancellationError — NOT as a processFailed from the nonzero exit of the killed process.
    func testCancellationTerminatesProcessAndDoesNotReportFailure() async throws {
        let proc = BlockingProcess()
        let runner = ClaudeCodeRunner(binary: URL(fileURLWithPath: "/usr/bin/true"), process: { proc })
        let task = Task { try await runner.run(prompt: "P", system: "S", model: nil) }
        var waited = 0
        while !proc.hasStarted && waited < 300 {      // await (not block) so run()'s main-actor body runs
            try await Task.sleep(nanoseconds: 10_000_000); waited += 1
        }
        XCTAssertTrue(proc.hasStarted, "run() never started")
        task.cancel()
        do { _ = try await task.value; XCTFail("expected the cancelled run to throw") }
        catch is CancellationError { /* expected */ }
        catch { XCTFail("expected CancellationError, got \(error)") }
        XCTAssertTrue(proc.cancelCalled, "cancel() must reach the process")
    }
}

/// Thread-safe collector for streamed event lines.
final class EventBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _lines: [String] = []
    func append(_ s: String) { lock.lock(); _lines.append(s); lock.unlock() }
    var lines: [String] { lock.lock(); defer { lock.unlock() }; return _lines }
}

final class AssistEventBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _events: [AssistRunEvent] = []
    func append(_ event: AssistRunEvent) { lock.lock(); _events.append(event); lock.unlock() }
    var events: [AssistRunEvent] { lock.lock(); defer { lock.unlock() }; return _events }
}
