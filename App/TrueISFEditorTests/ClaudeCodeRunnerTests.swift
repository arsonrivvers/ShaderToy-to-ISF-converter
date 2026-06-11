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
    func testAlwaysPinsSafetyFlags() async throws {
        let fake = FakeProcess(stdout: "{\"type\":\"result\",\"result\":\"ok\"}", exitCode: 0, stderr: "")
        let runner = ClaudeCodeRunner(binary: URL(fileURLWithPath: "/x/claude"), process: { fake })
        _ = try await runner.run(prompt: "P", system: "S", model: "sonnet")
        let args = runner.lastArgsForTest
        XCTAssertTrue(args.contains("--permission-mode"))
        XCTAssertTrue(args.contains("plan"))
        XCTAssertTrue(args.contains("--allowedTools"))
        XCTAssertTrue(args.contains("--strict-mcp-config"))
        XCTAssertTrue(args.contains("--disable-slash-commands"))
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
}

/// Thread-safe collector for streamed event lines.
final class EventBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _lines: [String] = []
    func append(_ s: String) { lock.lock(); _lines.append(s); lock.unlock() }
    var lines: [String] { lock.lock(); defer { lock.unlock() }; return _lines }
}
