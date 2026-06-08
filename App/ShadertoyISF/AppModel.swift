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

    func saveKey(_ key: String) {
        apiKey = key
        KeychainStore.save(key)
    }

    func convert() async {
        warnings = []; isfOutput = ""; importedCode = ""; statusMessage = ""
        guard !apiKey.isEmpty else { statusMessage = "Set your Shadertoy API key in Settings first."; return }
        guard let id = ShadertoyURL.shaderID(from: urlText) else {
            statusMessage = "That doesn't look like a Shadertoy URL or ID."; return
        }
        isBusy = true; defer { isBusy = false }
        do {
            let client = ShadertoyClient(key: apiKey)
            let shader = try await client.fetchShader(id: id)
            importedCode = shader.renderpass
                .map { "// ===== \($0.name) (\($0.type.rawValue)) =====\n\($0.code)" }
                .joined(separator: "\n\n")
            let (doc, w) = ISFConverter.convert(shader)
            isfOutput = doc.fileText
            warnings = w
            statusMessage = w.isEmpty ? "Converted cleanly." : "Converted with \(w.count) warning(s)."
        } catch ShadertoyClientError.shaderNotAccessible {
            statusMessage = "Shadertoy returned no data — the shader's author must set visibility to 'public + API'."
        } catch ShadertoyClientError.httpError(let code) {
            statusMessage = "Network error (HTTP \(code))."
        } catch {
            statusMessage = "Conversion failed: \(error.localizedDescription)"
        }
    }
}
