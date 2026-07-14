import Foundation

/// Single source of truth for constructing an `AssistProvider` from a selected kind. Both AI surfaces
/// — the editor's ShaderAssist and the Remix generator — build providers through here so they can't
/// diverge on which runner a kind maps to or how each CLI binary path is resolved.
enum AssistProviderFactory {
    /// Claude-only v1 (product decision 2026-07-14): release builds ship without the Codex surface —
    /// smaller attack surface and support matrix (Codex's read-only sandbox still permits file READS;
    /// see M11). The runner + tests stay in the codebase; debug builds keep both for development.
    static var codexAvailable: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }

    @MainActor
    static func make(kind: AssistProviderKind, defaults: UserDefaults = .standard) -> AssistProvider {
        // A stale "codex" preference on a release build clamps to Claude rather than constructing
        // a provider the UI no longer exposes.
        let kind = codexAvailable ? kind : .claude
        switch kind {
        case .claude:
            let bin = ClaudeCodeRunner.locateBinary(override: defaults.string(forKey: "claudeBinaryPath"))
            // Best-effort `claude --version` probe so the runner can warn on a version that predates
            // the verified tool-restriction flags (M12). nil when no binary resolved.
            let probe: (@Sendable () -> String?)? = bin.map { b in
                { try? RealProcess().run(executable: b, args: ["--version"], timeout: 5, onLine: { _ in }).stdout }
            }
            return ClaudeCodeRunner(binary: bin, versionOutput: probe)
        case .codex:
            return CodexRunner(binary: CodexRunner.locateBinary(
                override: defaults.string(forKey: "codexBinaryPath")))
        }
    }
}
