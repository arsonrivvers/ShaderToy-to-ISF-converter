import Foundation

/// Single source of truth for constructing an `AssistProvider` from a selected kind. Both AI surfaces
/// — the editor's ShaderAssist and the Remix generator — build providers through here so they can't
/// diverge on which runner a kind maps to or how each CLI binary path is resolved.
enum AssistProviderFactory {
    @MainActor
    static func make(kind: AssistProviderKind, defaults: UserDefaults = .standard) -> AssistProvider {
        switch kind {
        case .claude:
            return ClaudeCodeRunner(binary: ClaudeCodeRunner.locateBinary(
                override: defaults.string(forKey: "claudeBinaryPath")))
        case .codex:
            return CodexRunner(binary: CodexRunner.locateBinary(
                override: defaults.string(forKey: "codexBinaryPath")))
        }
    }
}
