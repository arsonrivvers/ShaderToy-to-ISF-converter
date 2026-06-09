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
        } catch WebFetchError.challengeTimeout {
            statusMessage = "Couldn't fetch automatically (Cloudflare bot check). Paste the shader's Image-tab code below and use 'Convert pasted code'."
        } catch is ShadertoyInternalParserError {
            statusMessage = "Shader not found, or it isn't public."
        } catch {
            statusMessage = "Fetch/convert failed: \(error.localizedDescription)"
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
