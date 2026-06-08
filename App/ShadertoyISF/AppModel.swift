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

    private lazy var webFetcher = WebKitShaderFetcher()

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
            statusMessage = w.isEmpty ? "Converted cleanly." : "Converted with \(w.count) warning(s)."
        } catch ShadertoyClientError.shaderNotAccessible {
            statusMessage = "API: the shader's author must enable 'public + API'. Remove your key in Settings to use the browser path instead."
        } catch WebFetchError.challengeTimeout {
            statusMessage = "Couldn't get past Shadertoy's bot check — try again, or add an API key in Settings (Advanced)."
        } catch is ShadertoyInternalParserError {
            statusMessage = "Shader not found, or it isn't public."
        } catch {
            statusMessage = "Fetch/convert failed: \(error.localizedDescription)"
        }
    }
}
