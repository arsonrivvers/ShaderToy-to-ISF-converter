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

    func testForwardsStreamLinesAsEvents() async throws {
        let json = "{\"type\":\"system\"}\n{\"type\":\"assistant\",\"message\":{\"content\":[{\"type\":\"text\",\"text\":\"hi\"}]}}\n{\"type\":\"result\",\"result\":\"DONE\"}"
        let fake = FakeProcess(stdout: json, exitCode: 0, stderr: "")
        let runner = ClaudeCodeRunner(binary: URL(fileURLWithPath: "/x/claude"), process: { fake })
        let box = EventBox()
        let final = try await runner.run(prompt: "P", system: "S", model: "m") { line in box.append(line) }
        XCTAssertEqual(final, "DONE")                       // result event preferred
        XCTAssertEqual(box.lines.count, 3)                  // every line streamed to the terminal
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
