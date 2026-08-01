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

enum ProcessLifecycleEvent: Sendable, Equatable {
    case started(pid: Int32)
    case exited(status: Int32)
}

protocol ProcessLifecycleReporting: ProcessRunning {
    func setLifecycleHandler(_ handler: @escaping @Sendable (ProcessLifecycleEvent) -> Void)
}

/// Maps a non-zero CLI exit to an AssistRunError (auth vs generic failure).
enum AssistErrorMapper {
    /// Known CLI sign-in phrasings only — a bare substring like "auth" also matched "author" in
    /// shader text echoed to output, misreporting real failures as "isn't signed in".
    private static let signInSignals = [
        "not authenticated", "please run /login", "please log in", "please sign in", "sign in",
        "not logged in", "invalid api key", "api key not", "oauth token", "codex login",
    ]

    static func error(stderr: String, stdout: String) -> AssistRunError {
        let lower = (stderr + stdout).lowercased()
        if signInSignals.contains(where: lower.contains) { return .notAuthenticated }
        return .processFailed(stderr.isEmpty ? stdout : stderr)
    }
}

/// Once-only latch for the teardown grace timer (armed from the pipe-reader thread).
final class OnceFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var isSet = false
    func trySet() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if isSet { return false }
        isSet = true
        return true
    }
}

/// Process exit can race the runner's timeout/cancellation catch. Buffer only the exit so the
/// terminal cause is delivered first; process start remains live and immediate.
final class ProcessExitEventBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var exitStatus: Int32?
    private var didFlush = false

    func capture(
        _ event: ProcessLifecycleEvent,
        emit: @escaping @Sendable (AssistRunEvent) -> Void
    ) {
        switch event {
        case let .started(pid):
            emit(.processStarted(pid: pid))
        case let .exited(status):
            lock.lock(); exitStatus = status; lock.unlock()
        }
    }

    func flush(emit: @escaping @Sendable (AssistRunEvent) -> Void) {
        lock.lock()
        guard !didFlush, let status = exitStatus else { lock.unlock(); return }
        didFlush = true
        lock.unlock()
        emit(.processExited(status))
    }
}

@MainActor
final class ClaudeCodeRunner: AssistProvider, AssistDetailedProvider {
    private let binary: URL?
    private let makeProcess: () -> ProcessRunning
    private let versionOutput: (@Sendable () -> String?)?
    /// Teardown grace (Quick Goals hang, 2026-07-17): once the CLI's terminal `result` event has
    /// streamed, the answer is complete — a process still alive this long after is a teardown
    /// straggler and gets terminated; the run then completes from the streamed result instead of
    /// waiting out the 420s timer (or forever, when a CLI child inherited the pipes).
    private let teardownGrace: TimeInterval
    private(set) var lastArgsForTest: [String] = []

    init(binary: URL?, process: @escaping () -> ProcessRunning = { RealProcess() },
         versionOutput: (@Sendable () -> String?)? = nil,
         teardownGrace: TimeInterval = 5) {
        self.binary = binary
        self.makeProcess = process
        self.versionOutput = versionOutput
        self.teardownGrace = teardownGrace
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
    /// nonisolated: pure filesystem/process work, callable off the main actor (Settings probes async).
    nonisolated static func locateBinary(override: String?) -> URL? {
        BinaryLocator.locate(name: "claude", override: override,
                             extraPaths: ["\(NSHomeDirectory())/.local/bin/claude"])
    }

    func run(prompt: String, system: String, model: String?, timeout: TimeInterval = 180,
             onEvent: @escaping @Sendable (String) -> Void = { _ in }) async throws -> String {
        let result = try await runDetailed(
            prompt: prompt,
            system: system,
            model: model,
            timeout: timeout,
            onEvent: { _ in },
            onRawLine: { line in
                let type = Self.envelopeType(from: line)
                if let legacy = AssistProviderCompatibilityAdapter.legacyRawLine(line, envelopeType: type) {
                    onEvent(legacy)
                }
            }
        )
        return AssistProviderCompatibilityAdapter.text(from: result)
    }

    func runDetailed(
        prompt: String,
        system: String,
        model: String?,
        timeout: TimeInterval = 180,
        onEvent: @escaping @Sendable (AssistRunEvent) -> Void,
        onRawLine: @escaping @Sendable (String) -> Void
    ) async throws -> AssistRunResult {
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
        var args = ["-p", "--output-format", "stream-json", "--verbose", "--include-partial-messages",
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
                onRawLine("⚠️ SECURITY: your `claude` CLI is older than v\(m.major).\(m.minor).\(m.patch), " +
                          "where ShaderAssist's tool-restriction flags were verified. Tool-blocking may be " +
                          "ineffective on this version — update the `claude` CLI.")
            }
        }
        let proc = makeProcess()
        let assembler = AssistResponseAssembler(provider: .claude)
        let emit: @Sendable (AssistRunEvent) -> Void = { event in
            assembler.consume(event)
            onEvent(event)
        }
        let exits = ProcessExitEventBuffer()
        let reportsLifecycle = proc is ProcessLifecycleReporting
        if let lifecycle = proc as? ProcessLifecycleReporting {
            lifecycle.setLifecycleHandler { event in exits.capture(event, emit: emit) }
        }
        // Grace-kill: the stream-json `result` event IS protocol completion. Arm a short timer
        // when it streams; if the process outlives its own answer, terminate it — the completed
        // result is then returned via the rescue below. Firing after a clean exit is a no-op
        // (the process is already gone).
        let graceArmed = OnceFlag()
        let cancellationReported = OnceFlag()
        let grace = teardownGrace
        let onLine: @Sendable (String) -> Void = { line in
            onRawLine(line)
            if let event = Self.decodeEvent(from: line) { emit(event) }
            if assembler.observedSuccessfulResult, graceArmed.trySet() {
                DispatchQueue.global().asyncAfter(deadline: .now() + grace) { proc.cancel() }
            }
        }
        let out: ProcessOutput
        do {
            // withTaskCancellationHandler so a parent-Task cancel (user Stop) terminates the CLI —
            // a detached task is otherwise immune to cancellation and would orphan the process.
            out = try await withTaskCancellationHandler {
                try await Task.detached(priority: .userInitiated) {
                    try proc.run(executable: binary, args: args, timeout: timeout, onLine: onLine)
                }.value
            } onCancel: {
                if cancellationReported.trySet() { emit(.cancelled) }
                proc.cancel()
            }
        }
        catch AssistRunError.timedOut(let partial) {
            if Task.isCancelled {
                exits.flush(emit: emit)
                throw CancellationError()
            }
            emit(.timedOut)
            exits.flush(emit: emit)
            if assembler.observedSuccessfulResult {
                do {
                    let result = try Self.resolve(assembler, processExitSucceeded: false)
                    onRawLine("⏱️ Timed out during teardown, but the completed answer was salvaged.")
                    return result
                } catch AssistAssemblyError.noAuthoritativeResponse {
                    // A success marker without complete response text is not salvageable.
                }
            }
            throw AssistRunError.timedOut(partialStdout: partial)
        }
        catch let e as AssistRunError {
            exits.flush(emit: emit)
            if Task.isCancelled { throw CancellationError() }
            throw e
        }
        catch {
            exits.flush(emit: emit)
            if Task.isCancelled { throw CancellationError() }
            throw AssistRunError.processFailed("\(error)")
        }
        if reportsLifecycle {
            exits.flush(emit: emit)
        } else {
            emit(.processExited(out.exitCode))
        }
        // A cancel-terminated process exits non-zero; don't surface that as a real failure.
        if Task.isCancelled { throw CancellationError() }
        if assembler.observedSuccessfulResult {
            return try Self.resolve(assembler, processExitSucceeded: false)
        }
        if out.exitCode != 0 {
            do { return try Self.resolve(assembler, processExitSucceeded: false) }
            catch AssistAssemblyError.noAuthoritativeResponse {
                throw AssistErrorMapper.error(stderr: out.stderr, stdout: out.stdout)
            }
        }
        return try Self.resolve(assembler, processExitSucceeded: true)
    }

    nonisolated static func envelopeType(from line: String) -> String? {
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return object["type"] as? String
    }

    nonisolated static func decodeEvent(from line: String) -> AssistRunEvent? {
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = object["type"] as? String else { return nil }

        switch type {
        case "system":
            let subtype = (object["subtype"] as? String) ?? ""
            if subtype == "init" {
                return .sessionStarted(id: (object["session_id"] as? String) ?? (object["id"] as? String))
            }
            let normalized = subtype.lowercased()
            if normalized.contains("retry") || normalized.contains("rate_limit") || normalized.contains("rate-limit") {
                let message = (object["message"] as? String) ?? subtype
                return .apiRetry(attempt: object["attempt"] as? Int, message: message)
            }

        case "assistant":
            guard let message = object["message"] as? [String: Any],
                  let content = message["content"] as? [[String: Any]] else { return nil }
            let blocks = content.enumerated().compactMap { index, block -> AssistTextBlock? in
                guard (block["type"] as? String) == "text", let text = block["text"] as? String else {
                    return nil
                }
                return AssistTextBlock(index: index, text: text)
            }
            let messageID = (message["id"] as? String) ?? (object["uuid"] as? String) ?? "assistant"
            return .assistantMessage(
                messageID: messageID,
                stopReason: message["stop_reason"] as? String,
                blocks: blocks
            )

        case "stream_event":
            guard let event = object["event"] as? [String: Any],
                  (event["type"] as? String) == "content_block_delta",
                  let delta = event["delta"] as? [String: Any],
                  let text = delta["text"] as? String else { return nil }
            let messageID = (object["message_id"] as? String) ?? (event["message_id"] as? String)
            return .textDelta(messageID: messageID, blockIndex: event["index"] as? Int ?? 0, text: text)

        case "result":
            let text = object["result"] as? String ?? ""
            if object["is_error"] as? Bool == true {
                return .errorResult(text.isEmpty ? "Claude reported an error." : text)
            }
            return .successfulResult(text)

        default:
            break
        }
        return nil
    }

    private static func resolve(
        _ assembler: AssistResponseAssembler,
        processExitSucceeded: Bool
    ) throws -> AssistRunResult {
        do {
            return try assembler.resolve(processExitSucceeded: processExitSucceeded)
        } catch let AssistAssemblyError.providerFailed(message) {
            throw AssistRunError.processFailed(message)
        }
    }

    /// The `result` event's text, ONLY if one is present — unlike `finalMessage`, no fallback to
    /// assistant text (a mid-stream kill leaves assistant text without a result; that's not a
    /// completed run and must stay a timeout). An `is_error` result is a FAILED run, never a
    /// completed answer — excluded here so neither the salvage nor the exit-code rescue keep it.
    nonisolated static func resultEvent(fromStreamJSON stdout: String) -> String? {
        var resultText: String?
        for line in stdout.split(separator: "\n") {
            guard let data = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  (obj["type"] as? String) == "result",
                  (obj["is_error"] as? Bool) != true,
                  let r = obj["result"] as? String else { continue }
            resultText = r
        }
        return resultText
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
final class RealProcess: ProcessLifecycleReporting, @unchecked Sendable {
    /// Lock-guarded so the bounded post-exit drain can snapshot while a reader thread (kept alive
    /// by an orphan holding the pipe) may still be appending.
    private final class Box: @unchecked Sendable {
        private let lock = NSLock()
        private var data = Data()
        func append(_ chunk: Data) { lock.lock(); data.append(chunk); lock.unlock() }
        func set(_ d: Data) { lock.lock(); data = d; lock.unlock() }
        var value: Data { lock.lock(); defer { lock.unlock() }; return data }
    }

    // Live-process tracking so `cancel()` (called off the run thread, from the Task cancellation
    // handler) can terminate a CLI that's still running.
    private let liveLock = NSLock()
    private var liveProcess: Process?
    private var cancelled = false
    private let lifecycleLock = NSLock()
    private var lifecycleHandler: (@Sendable (ProcessLifecycleEvent) -> Void)?

    func setLifecycleHandler(_ handler: @escaping @Sendable (ProcessLifecycleEvent) -> Void) {
        lifecycleLock.lock(); lifecycleHandler = handler; lifecycleLock.unlock()
    }

    private func reportLifecycle(_ event: ProcessLifecycleEvent) {
        lifecycleLock.lock(); let handler = lifecycleHandler; lifecycleLock.unlock()
        handler?(event)
    }

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
        reportLifecycle(.started(pid: p.processIdentifier))
        if alreadyCancelled { p.terminate() }
        defer { liveLock.lock(); liveProcess = nil; liveLock.unlock() }

        let outBox = Box(); let errBox = Box()
        let group = DispatchGroup()
        let q = DispatchQueue(label: "assist.pipe", attributes: .concurrent)

        group.enter()
        q.async {
            let h = outPipe.fileHandleForReading
            var pending = Data()
            while true {
                let chunk = h.availableData
                if chunk.isEmpty { break }
                outBox.append(chunk); pending.append(chunk)
                while let nl = pending.firstIndex(of: 0x0A) {
                    let lineData = pending.subdata(in: pending.startIndex..<nl)
                    pending.removeSubrange(pending.startIndex...nl)
                    if let s = String(data: lineData, encoding: .utf8) { onLine(s) }
                }
            }
            if !pending.isEmpty, let s = String(data: pending, encoding: .utf8) { onLine(s) }
            group.leave()
        }
        group.enter()
        q.async { errBox.set(errPipe.fileHandleForReading.readDataToEndOfFile()); group.leave() }

        let exited = DispatchSemaphore(value: 0)
        DispatchQueue(label: "assist.wait").async { [self] in
            p.waitUntilExit()
            reportLifecycle(.exited(status: p.terminationStatus))
            exited.signal()
        }
        if exited.wait(timeout: .now() + timeout) == .timedOut {
            // CSO MEDIUM-2: SIGTERM, brief grace, then SIGKILL so a wedged agent (or a child that
            // ignores SIGTERM) can't outlive the timeout still holding resources.
            p.terminate()
            if exited.wait(timeout: .now() + 2) == .timedOut {
                kill(p.processIdentifier, SIGKILL)
                _ = exited.wait(timeout: .now() + 1)
            }
            // The kill closes the pipes, so the readers EOF promptly; bounded wait, then hand the
            // collected stdout to the caller — the answer may have completed before the timer fired.
            _ = group.wait(timeout: .now() + 2)
            throw AssistRunError.timedOut(partialStdout: String(decoding: outBox.value, as: UTF8.self))
        }
        // Bounded drain (Quick Goals hang, 2026-07-17): pipe EOF requires EVERY fd holder to exit.
        // A CLI child that inherited our pipes kept an unbounded wait here blocked forever with a
        // finished answer on screen. 3s after exit, return what's collected — bytes after that
        // belong to the orphan, not this run (the reader thread ends on its own at the real EOF).
        _ = group.wait(timeout: .now() + 3)
        return ProcessOutput(stdout: String(decoding: outBox.value, as: UTF8.self),
                             stderr: String(decoding: errBox.value, as: UTF8.self),
                             exitCode: p.terminationStatus)
    }
}
