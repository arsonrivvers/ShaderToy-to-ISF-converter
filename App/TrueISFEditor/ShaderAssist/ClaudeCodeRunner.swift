import Foundation

struct ProcessOutput: Sendable { let stdout: String; let stderr: String; let exitCode: Int32 }

/// Streaming subprocess seam. `onLine` is called for each stdout line as it arrives (live terminal);
/// the full stdout/stderr/exit are still returned for final parsing + error mapping. Injected in tests.
protocol ProcessRunning: Sendable {
    func run(executable: URL, args: [String], timeout: TimeInterval,
             onLine: @escaping @Sendable (String) -> Void) throws -> ProcessOutput
    /// Terminate the in-flight process (if any). Called when the owning Swift Task is cancelled so a
    /// user "Stop" actually kills the CLI instead of orphaning it. Safe to call from any thread.
    func cancel()
}

extension ProcessRunning {
    /// Default no-op: synchronous test doubles complete instantly and have nothing to terminate.
    func cancel() {}
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
    private let versionOutput: (@Sendable () -> String?)?
    private(set) var lastArgsForTest: [String] = []

    init(binary: URL?, process: @escaping () -> ProcessRunning = { RealProcess() },
         versionOutput: (@Sendable () -> String?)? = nil) {
        self.binary = binary
        self.makeProcess = process
        self.versionOutput = versionOutput
    }

    // CSO M12: the tool-restriction flags below (`--tools ""`, `--disallowedTools LSP`, …) are only
    // known to remove tool capability on claude CLI ≥ this version (the `--tools ""`-alone-leaks-LSP
    // fix landed in 2.1.175). The user's CLI auto-updates outside our control, so a future flag-
    // semantics change could silently re-arm tools. We can't pin the user's binary, but we can warn
    // when it's CONFIDENTLY older than the verified floor.
    static let minVerifiedVersion = (major: 2, minor: 1, patch: 175)

    /// First `MAJOR.MINOR.PATCH` triple in `claude --version` output, or nil if none.
    static func parseVersion(_ output: String) -> (major: Int, minor: Int, patch: Int)? {
        guard let r = output.range(of: #"(\d+)\.(\d+)\.(\d+)"#, options: .regularExpression) else { return nil }
        let parts = output[r].split(separator: ".").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return (parts[0], parts[1], parts[2])
    }

    /// True only when the version parses AND is below the verified floor — so an unrecognized format
    /// never produces a spurious warning (this drives a non-gating notice, not a hard block).
    static func isBelowVerifiedFloor(versionOutput: String?) -> Bool {
        guard let out = versionOutput, let v = parseVersion(out) else { return false }
        let m = minVerifiedVersion
        if v.major != m.major { return v.major < m.major }
        if v.minor != m.minor { return v.minor < m.minor }
        return v.patch < m.patch
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
        //   --tools ""              : remove the built-in toolset (no Bash/Edit/WebFetch/ExitPlanMode)
        //   --disallowedTools LSP   : --tools "" alone STILL leaves the LSP code tool exposed (verified
        //                             empirically on CLI v2.1.175); deny it explicitly so the toolset is
        //                             genuinely empty — the call is a pure text→text transform
        //   --allowedTools ""       : belt-and-suspenders: nothing is grantable even if a tool existed
        //   --strict-mcp-config     : ignore ambient MCP servers (we pass no --mcp-config)
        //   --disable-slash-commands: no skill/command execution from injected text
        // NOTE: this used to be `--permission-mode plan`. Plan mode was actually WEAKER (it left read
        // tools available read-only) AND changed task semantics — on complex generation prompts the
        // model PLANNED and called ExitPlanMode instead of emitting the shader (3/3 remix children
        // failed "No ISF in reply", 2026-06-12). The --tools/--disallowedTools pair is strictly
        // stronger and keeps single-turn answer semantics.
        // These are pinned here so the app's safety never depends on the host's settings.json
        // (which defaults to bypassPermissions). Verified: injection blocked, subscription auth intact.
        var args = ["-p", "--output-format", "stream-json", "--verbose",
                    "--tools", "", "--disallowedTools", "LSP", "--allowedTools", "",
                    "--strict-mcp-config", "--disable-slash-commands"]
        if let model, !model.isEmpty { args += ["--model", model] }
        if !system.isEmpty { args += ["--append-system-prompt", system] }
        args.append(prompt)
        lastArgsForTest = args
        // M12: warn (once, non-blocking) if the CLI is confidently older than the version where the
        // tool-restriction flags were verified — the safety above silently weakens otherwise.
        if let versionOutput {
            let v = await Task.detached(priority: .utility) { versionOutput() }.value
            if Self.isBelowVerifiedFloor(versionOutput: v) {
                let m = Self.minVerifiedVersion
                onEvent("⚠️ SECURITY: your `claude` CLI is older than v\(m.major).\(m.minor).\(m.patch), " +
                        "where ShaderAssist's tool-restriction flags were verified. Tool-blocking may be " +
                        "ineffective on this version — update the `claude` CLI.")
            }
        }
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
        // A cancel-terminated process exits non-zero; don't surface that as a real failure.
        if Task.isCancelled { throw CancellationError() }
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
final class RealProcess: ProcessRunning, @unchecked Sendable {
    private final class Box: @unchecked Sendable { var value = Data() }

    // Live-process tracking so `cancel()` (called off the run thread, from the Task cancellation
    // handler) can terminate a CLI that's still running.
    private let liveLock = NSLock()
    private var liveProcess: Process?
    private var cancelled = false

    func cancel() {
        liveLock.lock(); cancelled = true; let p = liveProcess; liveLock.unlock()
        guard let p else { return }
        p.terminate()                                   // SIGTERM
        DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
            if p.isRunning { kill(p.processIdentifier, SIGKILL) }   // escalate if it ignores SIGTERM
        }
    }

    static func assistLaunchEnvironment(executable: URL,
                                        base: [String: String] = ProcessInfo.processInfo.environment) -> [String: String] {
        var env = base
        let existing = (base["PATH"] ?? "")
            .split(separator: ":")
            .map(String.init)
        let preferred = [
            executable.deletingLastPathComponent().path,
            "/opt/homebrew/bin",
            "/opt/homebrew/sbin",
            "/usr/local/bin",
            "/usr/local/sbin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin"
        ]
        var seen = Set<String>()
        let path = (preferred + existing).filter { part in
            guard !part.isEmpty, !seen.contains(part) else { return false }
            seen.insert(part)
            return true
        }
        env["PATH"] = path.joined(separator: ":")
        return env
    }

    func run(executable: URL, args: [String], timeout: TimeInterval,
             onLine: @escaping @Sendable (String) -> Void) throws -> ProcessOutput {
        let p = Process()
        p.executableURL = executable
        p.arguments = args
        p.environment = Self.assistLaunchEnvironment(executable: executable)
        // Run from a neutral temp dir so the CLIs never scan the app's launch directory (e.g. the
        // user's Desktop) — that scan triggers a repeated macOS TCC "access your Desktop" prompt.
        p.currentDirectoryURL = URL(fileURLWithPath: NSTemporaryDirectory())
        let outPipe = Pipe(); let errPipe = Pipe()
        p.standardOutput = outPipe
        p.standardError = errPipe
        p.standardInput = FileHandle.nullDevice   // never block waiting on stdin

        // Publish the process for cancel(); if a cancel already arrived in the launch window,
        // terminate immediately after starting so it can't outlive the Stop.
        liveLock.lock(); liveProcess = p; let alreadyCancelled = cancelled; liveLock.unlock()
        try p.run()
        if alreadyCancelled { p.terminate() }
        defer { liveLock.lock(); liveProcess = nil; liveLock.unlock() }

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
