import Foundation

/// A streaming AI backend for ShaderAssist. Both the Claude and Codex CLIs conform: each forwards raw
/// activity lines via `onEvent` (for the live terminal) and returns the final assistant message text
/// (which the existing ShaderAssistResponseParser turns into edits/suggestions).
@MainActor
protocol AssistProvider {
    /// - Parameters:
    ///   - prompt: the user task prompt.
    ///   - system: the system/preamble text (ISF skills + task framing).
    ///   - model: provider model id; nil = the provider's own default.
    ///   - onEvent: called for each raw output line as it streams (terminal display).
    /// - Returns: the final assistant message text.
    func run(prompt: String, system: String, model: String?, timeout: TimeInterval,
             onEvent: @escaping @Sendable (String) -> Void) async throws -> String
}

/// Shared error type for both CLI providers.
enum AssistRunError: Error, Equatable {
    case binaryNotFound, notAuthenticated, timedOut, processFailed(String)
}

/// The existing call sites + tests still refer to `ClaudeRunError`; keep it as an alias.
typealias ClaudeRunError = AssistRunError

/// Which AI provider ShaderAssist uses.
enum AssistProviderKind: String, CaseIterable, Identifiable {
    case claude
    case codex   // OpenAI via the `codex` CLI (ChatGPT subscription)
    var id: String { rawValue }
    var displayName: String { self == .claude ? "Claude (subscription)" : "OpenAI · Codex (subscription)" }
}
