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

    /// The ONLY sandbox mode this runner may launch under. SECURITY (CSO M11): the shader source fed
    /// into the prompt is untrusted (opened from the web/others), so Codex is a prompt-injection sink.
    /// Unlike the Claude runner — which removes tool capability entirely (`--tools ""`) — Codex has no
    /// equivalent, so `read-only` is the strongest available. IMPORTANT: read-only constrains *writes*,
    /// not *reads* — an injected shader could still make Codex run shell that reads `~/.ssh`, `.env`,
    /// etc. The only thing preventing exfiltration of those reads is that Codex disables network in
    /// `read-only` by default. So this value must NEVER be raised to `workspace-write`/`danger-full-access`
    /// (which also enable network); doing so opens a live lethal-trifecta path. Pinned here as an
    /// invariant, asserted by AssistRunnersTests.
    static let sandboxMode = "read-only"

    func run(prompt: String, system: String, model: String?, timeout: TimeInterval = 180,
             onEvent: @escaping @Sendable (String) -> Void = { _ in }) async throws -> String {
        guard let binary else { throw AssistRunError.binaryNotFound }
        // --ignore-user-config keeps the user's global hooks/config out of the run. RealProcess also
        // pins the working directory to a throwaway temp dir, narrowing Codex's default file scope.
        var args = ["exec", "--json", "--color", "never",
                    "-s", Self.sandboxMode, "--skip-git-repo-check", "--ignore-user-config"]
        if let model, !model.isEmpty { args += ["-m", model] }
        // Codex has no --append-system-prompt; prepend the preamble to the prompt.
        let full = system.isEmpty ? prompt : system + "\n\n---\n\n" + prompt
        args.append(full)
        lastArgsForTest = args
        let proc = makeProcess()
        let out: ProcessOutput
        do {
            // withTaskCancellationHandler so a parent-Task cancel (user Stop) terminates the CLI —
            // a detached task is otherwise immune to cancellation and would orphan the process.
            out = try await withTaskCancellationHandler {
                try await Task.detached(priority: .userInitiated) {
                    try proc.run(executable: binary, args: args, timeout: timeout, onLine: onEvent)
                }.value
            } onCancel: { proc.cancel() }
        }
        catch let e as AssistRunError { throw e }
        catch { throw AssistRunError.processFailed("\(error)") }
        if Task.isCancelled { throw CancellationError() }   // cancel-terminated exit isn't a real failure
        if out.exitCode != 0 {
            // Codex reports real failures as JSON events on STDOUT (`error` / `turn.failed`); STDERR only
            // carries the benign "Reading additional input from stdin..." status line (codex always reads
            // stdin to append to the prompt arg). Surfacing stderr would mask the actual error, so read
            // the stream first and fall back to stderr only when no JSON error is present.
            if let codexMessage = Self.errorMessage(fromCodexJSON: out.stdout) {
                throw AssistErrorMapper.error(stderr: codexMessage, stdout: out.stdout)
            }
            throw AssistErrorMapper.error(stderr: out.stderr, stdout: out.stdout)
        }
        return Self.finalMessage(fromCodexJSON: out.stdout)
    }

    /// Extract the failure message from a `codex exec --json` JSONL stream, if any. Reads both the
    /// `{"type":"error","message":...}` and `{"type":"turn.failed","error":{"message":...}}` events;
    /// the last one wins. Returns nil when the stream carries no error event.
    static func errorMessage(fromCodexJSON stdout: String) -> String? {
        var message: String?
        for line in stdout.split(separator: "\n") {
            guard let data = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            switch obj["type"] as? String {
            case "error":
                if let m = obj["message"] as? String, !m.isEmpty { message = m }
            case "turn.failed":
                if let err = obj["error"] as? [String: Any],
                   let m = err["message"] as? String, !m.isEmpty { message = m }
            default:
                continue
            }
        }
        return message
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
