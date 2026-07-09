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
    @Published var pastedCode: String = ""
    /// Default filename offered in the Save panel (derived from the shader name).
    @Published var suggestedFileName: String = "converted.fs"
    /// The most recent import attempt, for the inline summary in the import sheet.
    @Published var lastImport: ImportEvent?

    private lazy var webFetcher = WebKitShaderFetcher()

    /// The imported GLSL with each render pass prefixed by a `// ===== name (type) =====` banner.
    static func annotatedSource(_ shader: Shader) -> String {
        shader.renderpass
            .map { "// ===== \($0.name) (\($0.type.rawValue)) =====\n\($0.code)" }
            .joined(separator: "\n\n")
    }

    /// Turns a shader name into a safe `.fs` filename.
    static func safeFileName(_ name: String) -> String {
        let illegal = CharacterSet(charactersIn: "/\\:?%*|\"<>").union(.newlines)
        let cleaned = name.components(separatedBy: illegal).joined(separator: "-")
            .trimmingCharacters(in: .whitespaces)
        return (cleaned.isEmpty ? "shader" : cleaned) + ".fs"
    }

    func convert() async {
        warnings = []; isfOutput = ""; importedCode = ""; statusMessage = ""
        guard let id = ShadertoyURL.shaderID(from: urlText) else {
            statusMessage = "That doesn't look like a Shadertoy URL or ID."
            recordImport(stage: .urlInvalid, outcome: .error, id: nil, source: .webView,
                         httpStatus: nil, snippet: nil, warnings: 0)
            return
        }
        isBusy = true; defer { isBusy = false }

        // Read the key fresh from the Keychain (the source of truth set in Settings) rather than
        // caching it — see SettingsStore. Empty key → the WebKit fetch path.
        let apiKey = KeychainStore.load() ?? ""
        let strategy = FetchStrategy.select(hasKey: !apiKey.isEmpty)
        let source: ImportEvent.FetchSource = strategy == .api ? .api : .webView
        // Tracked across the do/catch so a single record point at the end captures the outcome.
        var stage: ImportEvent.Stage = .fetched
        var outcome: ImportEvent.Outcome = .error
        var snippet: String? = nil
        var warningCount = 0
        defer {
            // Only touch the (lazy) web fetcher on the webView path, so the API path doesn't
            // needlessly spin up a WKWebView just to read diagnostics.
            var httpStatus: Int? = nil
            if source == .webView, webFetcher.lastResponseStatus != -1 {
                httpStatus = webFetcher.lastResponseStatus
            }
            recordImport(stage: stage, outcome: outcome, id: id, source: source,
                         httpStatus: httpStatus, snippet: snippet, warnings: warningCount)
        }
        do {
            let shader: Shader
            switch strategy {
            case .api:
                shader = try await ShadertoyClient(key: apiKey).fetchShader(id: id)
            case .webView:
                statusMessage = "Fetching via browser (clearing Cloudflare)…"
                shader = try await webFetcher.fetchShader(id: id)
            }
            importedCode = Self.annotatedSource(shader)
            let (doc, w) = ISFConverter.convert(shader)
            isfOutput = doc.fileText
            warnings = w
            suggestedFileName = Self.safeFileName(shader.info.name)
            statusMessage = w.isEmpty ? "Converted cleanly." : "Converted with \(w.count) warning(s)."
            stage = .converted; outcome = w.isEmpty ? .success : .warning; warningCount = w.count
            runPixelGateAndRecord(isfText: doc.fileText, shaderID: id, source: source)
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
            snippet = String(webFetcher.lastResponseBody.prefix(300))
        } catch {
            statusMessage = "Fetch/convert failed: \(error.localizedDescription)"
        }
    }

    private func recordImport(stage: ImportEvent.Stage, outcome: ImportEvent.Outcome,
                              id: String?, source: ImportEvent.FetchSource,
                              httpStatus: Int?, snippet: String?, warnings: Int) {
        let event = ImportEvent(query: urlText, shaderID: id, fetchSource: source,
                                httpStatus: httpStatus, stage: stage, outcome: outcome,
                                message: statusMessage, responseSnippet: snippet, warningCount: warnings)
        lastImport = event
        ImportLog.shared.record(event)
    }

    /// Dedicated headless Metal controller for the post-import pixel gate — deliberately NOT the
    /// live preview (which may be showing another document or toggled to WebKit). One shared
    /// instance; `load()`'s generation counter makes rapid re-imports supersede cleanly.
    private static let gatePreview = MetalPreviewController()

    /// Post-conversion pixel-truth check (spec §C): compile the converted ISF headlessly, render
    /// 3 frames, and record a `.rendered` ImportEvent when the result is not OK. Fire-and-forget;
    /// an OK verdict records nothing (the `converted` event already said ✓), and compile failures
    /// record nothing here either — the editor preview reports those in context.
    private func runPixelGateAndRecord(isfText: String, shaderID: String?,
                                       source: ImportEvent.FetchSource) {
        let query = urlText
        Task { @MainActor in
            let preview = Self.gatePreview
            preview.load(isf: isfText)
            for _ in 0..<200 {                       // ≤10 s; typical transpile ≪ 1 s
                if preview.compileValid || preview.compileError != nil { break }
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
            guard preview.compileValid else { return }
            let verdict = preview.runPixelGate()
            guard let (severity, message) = PixelGate.importOutcome(verdict) else { return }
            let outcome: ImportEvent.Outcome = severity == .warning ? .warning : .error
            ImportLog.shared.record(ImportEvent(
                query: query, shaderID: shaderID, fetchSource: source, httpStatus: nil,
                stage: .rendered, outcome: outcome, message: message,
                responseSnippet: nil, warningCount: 0))
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
        importedCode = Self.annotatedSource(shader)

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
        runPixelGateAndRecord(isfText: doc.fileText, shaderID: nil, source: .webView)
    }
}
