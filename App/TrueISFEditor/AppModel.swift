import Foundation
import ShadertoyISFKit

@MainActor
final class AppModel: ObservableObject {
    @Published var urlText: String = ""
    @Published var importedCode: String = ""
    @Published var isfOutput: String = ""
    @Published var warnings: [ConversionWarning] = []
    @Published var statusMessage: String = ""
    @Published var isBusy: Bool = false
    @Published var apiKey: String = KeychainStore.load() ?? ""
    /// Optional explicit path to the `claude` CLI for the ShaderAssist AI feature (blank = auto-detect).
    @Published var claudeBinaryPath: String = UserDefaults.standard.string(forKey: "claudeBinaryPath") ?? ""
    /// Optional explicit path to the `codex` CLI (blank = auto-detect).
    @Published var codexBinaryPath: String = UserDefaults.standard.string(forKey: "codexBinaryPath") ?? ""
    /// ShaderAssist provider + per-provider model selection (B2).
    @Published var assistProvider: String = UserDefaults.standard.string(forKey: "assistProvider") ?? "claude"
    @Published var assistClaudeModel: String = UserDefaults.standard.string(forKey: "assistClaudeModel") ?? "sonnet"
    @Published var assistCodexModel: String = UserDefaults.standard.string(forKey: "assistCodexModel") ?? ""
    @Published var pastedCode: String = ""
    /// Default filename offered in the Save panel (derived from the shader name).
    @Published var suggestedFileName: String = "converted.fs"

    private lazy var webFetcher = WebKitShaderFetcher()

    /// Turns a shader name into a safe `.fs` filename.
    static func safeFileName(_ name: String) -> String {
        let illegal = CharacterSet(charactersIn: "/\\:?%*|\"<>").union(.newlines)
        let cleaned = name.components(separatedBy: illegal).joined(separator: "-")
            .trimmingCharacters(in: .whitespaces)
        return (cleaned.isEmpty ? "shader" : cleaned) + ".fs"
    }

    func saveKey(_ key: String) {
        apiKey = key
        KeychainStore.save(key)
    }

    func saveClaudeBinaryPath(_ p: String) {
        claudeBinaryPath = p
        UserDefaults.standard.set(p, forKey: "claudeBinaryPath")
    }

    /// Persist the ShaderAssist provider/model/path settings (B2).
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

    func convert() async {
        warnings = []; isfOutput = ""; importedCode = ""; statusMessage = ""
        guard let id = ShadertoyURL.shaderID(from: urlText) else {
            statusMessage = "That doesn't look like a Shadertoy URL or ID."; return
        }
        isBusy = true; defer { isBusy = false }

        let strategy = FetchStrategy.select(hasKey: !apiKey.isEmpty)
        do {
            let shader: Shader
            switch strategy {
            case .api:
                shader = try await ShadertoyClient(key: apiKey).fetchShader(id: id)
            case .webView:
                statusMessage = "Fetching via browser (clearing Cloudflare)…"
                shader = try await webFetcher.fetchShader(id: id)
            }
            importedCode = shader.renderpass
                .map { "// ===== \($0.name) (\($0.type.rawValue)) =====\n\($0.code)" }
                .joined(separator: "\n\n")
            let (doc, w) = ISFConverter.convert(shader)
            isfOutput = doc.fileText
            warnings = w
            suggestedFileName = Self.safeFileName(shader.info.name)
            statusMessage = w.isEmpty ? "Converted cleanly." : "Converted with \(w.count) warning(s)."
        } catch ShadertoyClientError.shaderNotAccessible {
            statusMessage = "API: the shader's author must enable 'public + API'. Remove your key in Settings to use the browser path instead."
        } catch ShadertoyClientError.httpError(let status) {
            statusMessage = Self.httpMessage(status, source: "Shadertoy API")
        } catch ShadertoyClientError.decodingFailed {
            statusMessage = "Shadertoy returned data in an unexpected format. Try again, or paste the code below."
        } catch WebFetchError.httpError(let status) {
            statusMessage = Self.httpMessage(status, source: "Shadertoy")
        } catch WebFetchError.noData {
            statusMessage = "Shadertoy returned no data. Try again in a moment, or paste the code below."
        } catch WebFetchError.challengeTimeout {
            statusMessage = "Couldn't fetch automatically (Cloudflare bot check). Paste the shader's Image-tab code below and use 'Convert pasted code'."
        } catch ShadertoyInternalParserError.shaderNotFound {
            statusMessage = "Shader not found, or it isn't public."
        } catch ShadertoyInternalParserError.malformed(let detail) {
            // The shader exists and is public, but its data uses a shape this version can't parse
            // yet. Say so honestly instead of the misleading "not found" — and let the user paste.
            statusMessage = "This shader loaded but uses a format this version can't convert yet. Paste the Image-tab code below and use 'Convert pasted code'. (\(detail.prefix(140)))"
        } catch {
            statusMessage = "Fetch/convert failed: \(error.localizedDescription)"
        }
    }

    /// Friendly, actionable copy for an HTTP failure status.
    static func httpMessage(_ status: Int, source: String) -> String {
        switch status {
        case 429: return "\(source) is rate-limiting requests. Wait a minute and try again."
        case 404: return "Shader not found (404). Check the URL or ID."
        case 401, 403: return "\(source) refused the request (HTTP \(status)). If you set an API key, verify it in Settings."
        case 500...599: return "\(source) server error (HTTP \(status)). Try again shortly."
        default: return "\(source) request failed (HTTP \(status))."
        }
    }

    func convertPastedCode() async {
        warnings = []; isfOutput = ""; importedCode = ""; statusMessage = ""
        let code = pastedCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else { statusMessage = "Paste the shader's Image-tab GLSL first."; return }

        let isMultipass = ShaderFactory.pasteContainsBuffers(code)
        let shader = ShaderFactory.fromPaste(
            code, name: isMultipass ? "Pasted Multipass Shader" : "Pasted Shader")
        importedCode = shader.renderpass
            .map { "// ===== \($0.name) (\($0.type.rawValue)) =====\n\($0.code)" }
            .joined(separator: "\n\n")

        let (doc, baseWarnings) = ISFConverter.convert(shader)
        var w = baseWarnings
        if isMultipass {
            // Paste carries no channel-routing metadata; tell the user what we assumed.
            w.insert(ConversionWarning(severity: .warning,
                message: "Channel routing was assumed (iChannelN → Buffer N). Pasted code has no routing metadata — verify against the original shader's channel setup.",
                context: "multipass paste"), at: 0)
        }
        isfOutput = doc.fileText
        warnings = w
        suggestedFileName = isMultipass ? "pasted-multipass.fs" : "pasted-shader.fs"
        statusMessage = w.isEmpty ? "Converted pasted code cleanly." : "Converted pasted code with \(w.count) warning(s)."
    }
}
