import Foundation

/// OpenAI provider via the `codex` CLI (ChatGPT subscription). Mirrors ClaudeCodeRunner: streams
/// `codex exec --json` events for the live terminal and returns the final agent message.
@MainActor
final class CodexRunner: AssistProvider {
    private let binary: URL?
    private let makeProcess: () -> ProcessRunning
    private(set) var lastArgsForTest: [String] = []

    init(binary: URL?, process: @escaping () -> ProcessRunning = { RealProcess() }) {
        self.binary = binary
        self.makeProcess = process
    }

    static func locateBinary(override: String?) -> URL? {
        BinaryLocator.locate(name: "codex", override: override)
    }

    func run(prompt: String, system: String, model: String?, timeout: TimeInterval = 180,
             onEvent: @escaping @Sendable (String) -> Void = { _ in }) async throws -> String {
        guard let binary else { throw AssistRunError.binaryNotFound }
        // read-only sandbox: the assist analyzes + proposes a diff; the app applies edits. Codex never
        // writes files. --ignore-user-config keeps the user's global hooks/config out of the run.
        var args = ["exec", "--json", "--color", "never",
                    "-s", "read-only", "--skip-git-repo-check", "--ignore-user-config"]
        if let model, !model.isEmpty { args += ["-m", model] }
        // Codex has no --append-system-prompt; prepend the preamble to the prompt.
        let full = system.isEmpty ? prompt : system + "\n\n---\n\n" + prompt
        args.append(full)
        lastArgsForTest = args
        let proc = makeProcess()
        let out: ProcessOutput
        do {
            out = try await Task.detached(priority: .userInitiated) {
                try proc.run(executable: binary, args: args, timeout: timeout, onLine: onEvent)
            }.value
        }
        catch let e as AssistRunError { throw e }
        catch { throw AssistRunError.processFailed("\(error)") }
        if out.exitCode != 0 { throw AssistErrorMapper.error(stderr: out.stderr, stdout: out.stdout) }
        return Self.finalMessage(fromCodexJSON: out.stdout)
    }

    /// Extract the last `agent_message` text from a `codex exec --json` JSONL stream.
    static func finalMessage(fromCodexJSON stdout: String) -> String {
        var text = ""
        for line in stdout.split(separator: "\n") {
            guard let data = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  (obj["type"] as? String) == "item.completed",
                  let item = obj["item"] as? [String: Any],
                  (item["type"] as? String) == "agent_message",
                  let t = item["text"] as? String else { continue }
            text = t
        }
        return text
    }
}
