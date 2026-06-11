import Foundation

struct ProcessOutput: Sendable { let stdout: String; let stderr: String; let exitCode: Int32 }

/// Streaming subprocess seam. `onLine` is called for each stdout line as it arrives (live terminal);
/// the full stdout/stderr/exit are still returned for final parsing + error mapping. Injected in tests.
protocol ProcessRunning: Sendable {
    func run(executable: URL, args: [String], timeout: TimeInterval,
             onLine: @escaping @Sendable (String) -> Void) throws -> ProcessOutput
}

/// Maps a non-zero CLI exit to an AssistRunError (auth vs generic failure).
enum AssistErrorMapper {
    static func error(stderr: String, stdout: String) -> AssistRunError {
        let lower = (stderr + stdout).lowercased()
        if lower.contains("login") || lower.contains("not authenticated") ||
           lower.contains("api key") || lower.contains("auth") || lower.contains("sign in") {
            return .notAuthenticated
        }
        return .processFailed(stderr.isEmpty ? stdout : stderr)
    }
}

@MainActor
final class ClaudeCodeRunner: AssistProvider {
    private let binary: URL?
    private let makeProcess: () -> ProcessRunning
    private(set) var lastArgsForTest: [String] = []

    init(binary: URL?, process: @escaping () -> ProcessRunning = { RealProcess() }) {
        self.binary = binary
        self.makeProcess = process
    }

    /// Resolve the claude binary: explicit override → known paths → login-shell `command -v`.
    static func locateBinary(override: String?) -> URL? {
        BinaryLocator.locate(name: "claude", override: override,
                             extraPaths: ["\(NSHomeDirectory())/.local/bin/claude"])
    }

    func run(prompt: String, system: String, model: String?, timeout: TimeInterval = 180,
             onEvent: @escaping @Sendable (String) -> Void = { _ in }) async throws -> String {
        guard let binary else { throw AssistRunError.binaryNotFound }
        // stream-json gives line-by-line events for the live terminal; --verbose is required with it.
        // SECURITY (CSO CRITICAL-1): the shader source is untrusted (opened from the web/others) and
        // goes into the prompt — a prompt-injection sink. This task is pure text analysis, so we strip
        // ALL tool/action capability structurally rather than rely on the model refusing:
        //   --permission-mode plan : read/think-only, cannot take mutating actions
        //   --allowedTools ""       : no tool is grantable (closes Bash/Edit/WebFetch sinks)
        //   --strict-mcp-config     : ignore ambient MCP servers (we pass no --mcp-config)
        //   --disable-slash-commands: no skill/command execution from injected text
        // These are pinned here so the app's safety never depends on the host's settings.json
        // (which defaults to bypassPermissions). Verified: injection blocked, subscription auth intact.
        var args = ["-p", "--output-format", "stream-json", "--verbose",
                    "--permission-mode", "plan", "--allowedTools", "",
                    "--strict-mcp-config", "--disable-slash-commands"]
        if let model, !model.isEmpty { args += ["--model", model] }
        if !system.isEmpty { args += ["--append-system-prompt", system] }
        args.append(prompt)
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
        return Self.finalMessage(fromStreamJSON: out.stdout)
    }

    /// Extract the final assistant text from a claude `stream-json` stream: prefer the `result` event;
    /// fall back to concatenated assistant text blocks.
    static func finalMessage(fromStreamJSON stdout: String) -> String {
        var resultText: String?
        var assistantText = ""
        for line in stdout.split(separator: "\n") {
            guard let data = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = obj["type"] as? String else { continue }
            if type == "result", let r = obj["result"] as? String {
                resultText = r
            } else if type == "assistant", let msg = obj["message"] as? [String: Any],
                      let content = msg["content"] as? [[String: Any]] {
                for block in content where (block["type"] as? String) == "text" {
                    if let t = block["text"] as? String { assistantText += t }
                }
            }
        }
        return resultText ?? assistantText
    }
}

/// Shared binary resolver for the assist CLIs.
enum BinaryLocator {
    static func locate(name: String, override: String?, extraPaths: [String] = []) -> URL? {
        if let o = override, !o.isEmpty, FileManager.default.isExecutableFile(atPath: o) {
            return URL(fileURLWithPath: o)
        }
        let candidates = extraPaths + ["/opt/homebrew/bin/\(name)", "/usr/local/bin/\(name)"]
        for c in candidates where FileManager.default.isExecutableFile(atPath: c) {
            return URL(fileURLWithPath: c)
        }
        if let path = try? RealProcess().run(
            executable: URL(fileURLWithPath: "/bin/zsh"),
            args: ["-lc", "command -v \(name)"], timeout: 5, onLine: { _ in }).stdout
            .trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty,
           FileManager.default.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return nil
    }
}

/// Real streaming Process implementation (not exercised in unit tests).
struct RealProcess: ProcessRunning {
    private final class Box: @unchecked Sendable { var value = Data() }

    func run(executable: URL, args: [String], timeout: TimeInterval,
             onLine: @escaping @Sendable (String) -> Void) throws -> ProcessOutput {
        let p = Process()
        p.executableURL = executable
        p.arguments = args
        // Run from a neutral temp dir so the CLIs never scan the app's launch directory (e.g. the
        // user's Desktop) — that scan triggers a repeated macOS TCC "access your Desktop" prompt.
        p.currentDirectoryURL = URL(fileURLWithPath: NSTemporaryDirectory())
        let outPipe = Pipe(); let errPipe = Pipe()
        p.standardOutput = outPipe
        p.standardError = errPipe
        p.standardInput = FileHandle.nullDevice   // never block waiting on stdin
        try p.run()

        let outBox = Box(); let errBox = Box()
        let group = DispatchGroup()
        let q = DispatchQueue(label: "assist.pipe", attributes: .concurrent)

        group.enter()
        q.async {
            let h = outPipe.fileHandleForReading
            var pending = Data(); var full = Data()
            while true {
                let chunk = h.availableData
                if chunk.isEmpty { break }
                full.append(chunk); pending.append(chunk)
                while let nl = pending.firstIndex(of: 0x0A) {
                    let lineData = pending.subdata(in: pending.startIndex..<nl)
                    pending.removeSubrange(pending.startIndex...nl)
                    if let s = String(data: lineData, encoding: .utf8) { onLine(s) }
                }
            }
            if !pending.isEmpty, let s = String(data: pending, encoding: .utf8) { onLine(s) }
            outBox.value = full
            group.leave()
        }
        group.enter()
        q.async { errBox.value = errPipe.fileHandleForReading.readDataToEndOfFile(); group.leave() }

        let exited = DispatchSemaphore(value: 0)
        DispatchQueue(label: "assist.wait").async { p.waitUntilExit(); exited.signal() }
        if exited.wait(timeout: .now() + timeout) == .timedOut {
            // CSO MEDIUM-2: SIGTERM, brief grace, then SIGKILL so a wedged agent (or a child that
            // ignores SIGTERM) can't outlive the timeout still holding resources.
            p.terminate()
            if exited.wait(timeout: .now() + 2) == .timedOut {
                kill(p.processIdentifier, SIGKILL)
                _ = exited.wait(timeout: .now() + 1)
            }
            throw AssistRunError.timedOut
        }
        group.wait()
        return ProcessOutput(stdout: String(decoding: outBox.value, as: UTF8.self),
                             stderr: String(decoding: errBox.value, as: UTF8.self),
                             exitCode: p.terminationStatus)
    }
}
