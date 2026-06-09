import XCTest

@MainActor
final class ClaudeCodeRunnerTests: XCTestCase {
    final class FakeProcess: ProcessRunning, @unchecked Sendable {
        var stdout: String; var exitCode: Int32; var stderr: String
        init(stdout: String, exitCode: Int32, stderr: String) { self.stdout = stdout; self.exitCode = exitCode; self.stderr = stderr }
        func run(executable: URL, args: [String], timeout: TimeInterval) throws -> ProcessOutput {
            ProcessOutput(stdout: stdout, stderr: stderr, exitCode: exitCode)
        }
    }

    func testBuildsExpectedArgv() async throws {
        let fake = FakeProcess(stdout: "{\"result\":\"ok\"}", exitCode: 0, stderr: "")
        let runner = ClaudeCodeRunner(binary: URL(fileURLWithPath: "/x/claude"), process: { fake })
        _ = try await runner.run(prompt: "P", system: "S", model: "claude-sonnet-4-6")
        let args = runner.lastArgsForTest
        XCTAssertEqual(args.first, "-p")
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
    func testNilBinaryThrowsBinaryNotFound() async {
        let runner = ClaudeCodeRunner(binary: nil, process: { FakeProcess(stdout: "", exitCode: 0, stderr: "") })
        do { _ = try await runner.run(prompt: "P", system: "S", model: "m"); XCTFail("expected throw") }
        catch let e as ClaudeRunError { XCTAssertEqual(e, .binaryNotFound) }
        catch { XCTFail("wrong error") }
    }
}
