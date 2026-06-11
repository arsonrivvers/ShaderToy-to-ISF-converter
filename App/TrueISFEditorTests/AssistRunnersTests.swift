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
        XCTAssertTrue(args.contains("-m")); XCTAssertTrue(args.contains("gpt-5-codex"))
        // system is prepended to the prompt (codex has no --append-system-prompt)
        XCTAssertTrue(args.last?.contains("S") == true && args.last?.contains("P") == true)
    }

    func testCodexDefaultModelOmitsDashM() async throws {
        let fake = ClaudeCodeRunnerTests.FakeProcess(stdout: "{}", exitCode: 0, stderr: "")
        let runner = CodexRunner(binary: URL(fileURLWithPath: "/x/codex"), process: { fake })
        _ = try await runner.run(prompt: "P", system: "", model: nil)
        XCTAssertFalse(runner.lastArgsForTest.contains("-m"))
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

    func testCodexBinaryNotFound() async {
        let runner = CodexRunner(binary: nil)
        do { _ = try await runner.run(prompt: "P", system: "S", model: nil); XCTFail("expected throw") }
        catch let e as AssistRunError { XCTAssertEqual(e, .binaryNotFound) }
        catch { XCTFail("wrong error") }
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
}
