import Foundation

/// Persisted user settings: the Shadertoy API key (Keychain) and the ShaderAssist provider/model/CLI
/// preferences (UserDefaults). Split out of `AppModel` so settings persistence is a separate concern
/// from the fetch/convert pipeline. Provider/model values are also read straight from UserDefaults at
/// point of use (`AssistProviderSelection`, `AssistProviderFactory`); this store drives the Settings UI.
@MainActor
final class SettingsStore: ObservableObject {
    @Published var apiKey: String = KeychainStore.load() ?? ""
    /// Optional explicit path to the `claude` CLI for ShaderAssist (blank = auto-detect).
    @Published var claudeBinaryPath: String = UserDefaults.standard.string(forKey: "claudeBinaryPath") ?? ""
    /// Optional explicit path to the `codex` CLI (blank = auto-detect).
    @Published var codexBinaryPath: String = UserDefaults.standard.string(forKey: "codexBinaryPath") ?? ""
    /// ShaderAssist provider + per-provider model selection.
    @Published var assistProvider: String = UserDefaults.standard.string(forKey: "assistProvider") ?? "claude"
    @Published var assistClaudeModel: String = UserDefaults.standard.string(forKey: "assistClaudeModel") ?? "sonnet"
    @Published var assistCodexModel: String = UserDefaults.standard.string(forKey: "assistCodexModel") ?? ""

    func saveKey(_ key: String) {
        apiKey = key
        KeychainStore.save(key)
    }

    func saveClaudeBinaryPath(_ p: String) {
        claudeBinaryPath = p
        UserDefaults.standard.set(p, forKey: "claudeBinaryPath")
    }

    /// Persist the ShaderAssist provider/model/path settings.
    func saveAssistSettings(provider: String, claudeModel: String, codexModel: String, codexPath: String) {
        assistProvider = provider; assistClaudeModel = claudeModel
        assistCodexModel = codexModel; codexBinaryPath = codexPath
        let d = UserDefaults.standard
        d.set(provider, forKey: "assistProvider")
        d.set(claudeModel, forKey: "assistClaudeModel")
        d.set(codexModel, forKey: "assistCodexModel")
        d.set(codexPath, forKey: "codexBinaryPath")
    }

    /// Whether each provider's CLI is resolvable on this machine (honest "CLI found" status — actual
    /// login is verified by running the CLI, which the live terminal will surface).
    static func claudeCLIFound(override: String?) -> Bool { ClaudeCodeRunner.locateBinary(override: override) != nil }
    static func codexCLIFound(override: String?) -> Bool { CodexRunner.locateBinary(override: override) != nil }
}
