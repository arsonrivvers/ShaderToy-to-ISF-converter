import Foundation

struct ProcessOutput { let stdout: String; let stderr: String; let exitCode: Int32 }

protocol ProcessRunning {
    func run(executable: URL, args: [String], timeout: TimeInterval) throws -> ProcessOutput
}

enum ClaudeRunError: Error, Equatable {
    case binaryNotFound, notAuthenticated, timedOut, processFailed(String)
}

@MainActor
final class ClaudeCodeRunner {
    private let binary: URL?
    private let makeProcess: () -> ProcessRunning
    private(set) var lastArgsForTest: [String] = []

    init(binary: URL?, process: @escaping () -> ProcessRunning = { RealProcess() }) {
        self.binary = binary
        self.makeProcess = process
    }

    /// Resolve the claude binary: explicit override → known paths → login-shell `command -v`.
    static func locateBinary(override: String?) -> URL? {
        if let o = override, !o.isEmpty, FileManager.default.isExecutableFile(atPath: o) {
            return URL(fileURLWithPath: o)
        }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = ["\(home)/.local/bin/claude", "/opt/homebrew/bin/claude", "/usr/local/bin/claude"]
        for c in candidates where FileManager.default.isExecutableFile(atPath: c) {
            return URL(fileURLWithPath: c)
        }
        if let path = try? RealProcess().run(
            executable: URL(fileURLWithPath: "/bin/zsh"),
            args: ["-lc", "command -v claude"], timeout: 5).stdout
            .trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty,
           FileManager.default.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return nil
    }

    func run(prompt: String, system: String, model: String, timeout: TimeInterval = 120) async throws -> String {
        guard let binary else { throw ClaudeRunError.binaryNotFound }
        let args = ["-p", "--output-format", "json", "--model", model,
                    "--append-system-prompt", system, prompt]
        lastArgsForTest = args
        let proc = makeProcess()
        let out: ProcessOutput
        do { out = try proc.run(executable: binary, args: args, timeout: timeout) }
        catch { throw ClaudeRunError.timedOut }
        if out.exitCode != 0 {
            let lower = (out.stderr + out.stdout).lowercased()
            if lower.contains("login") || lower.contains("api key") || lower.contains("auth") {
                throw ClaudeRunError.notAuthenticated
            }
            throw ClaudeRunError.processFailed(out.stderr.isEmpty ? out.stdout : out.stderr)
        }
        return out.stdout
    }
}

/// Real Process implementation (not exercised in unit tests).
struct RealProcess: ProcessRunning {
    func run(executable: URL, args: [String], timeout: TimeInterval) throws -> ProcessOutput {
        let p = Process(); p.executableURL = executable; p.arguments = args
        let outPipe = Pipe(); let errPipe = Pipe()
        p.standardOutput = outPipe; p.standardError = errPipe
        try p.run()
        // Drain pipes on background queues so a large output can't deadlock the wait.
        var outData = Data(); var errData = Data()
        let group = DispatchGroup()
        let q = DispatchQueue(label: "claude.pipe", attributes: .concurrent)
        group.enter(); q.async { outData = outPipe.fileHandleForReading.readDataToEndOfFile(); group.leave() }
        group.enter(); q.async { errData = errPipe.fileHandleForReading.readDataToEndOfFile(); group.leave() }
        let deadline = Date().addingTimeInterval(timeout)
        while p.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
        if p.isRunning { p.terminate(); throw ClaudeRunError.timedOut }
        group.wait()
        return ProcessOutput(stdout: String(decoding: outData, as: UTF8.self),
                             stderr: String(decoding: errData, as: UTF8.self),
                             exitCode: p.terminationStatus)
    }
}
