import Foundation
import ShadertoyISFKit

/// Where a parent shader comes from.
enum ParentSpec: Equatable {
    case pastedISF(String)
    case libraryFile(URL)
    case shadertoyLink(String)   // pasted URL or bare id
    case currentEditor
}

enum RemixParentError: Error, Equatable {
    case noEditorShader
    case badShadertoyURL
}

/// Resolves a `ParentSpec` to an ISF source string. Network/editor access is injected so the
/// non-network paths are unit-testable and the Shadertoy path can be faked.
struct RemixParentResolver {
    /// Returns the main editor's current shader source, or nil if there isn't one.
    var currentEditorSource: () -> String?
    /// Fetches + converts a Shadertoy URL/id to ISF source. Default wires the real importer chain.
    var fetchShadertoy: (
        String,
        @MainActor (WebKitShaderFetcher.State) -> Void
    ) async throws -> String

    init(
        currentEditorSource: @escaping () -> String?,
        fetchShadertoy: @escaping (String) async throws -> String
    ) {
        self.currentEditorSource = currentEditorSource
        self.fetchShadertoy = { input, _ in try await fetchShadertoy(input) }
    }

    init(
        currentEditorSource: @escaping () -> String?,
        fetchShadertoy: @escaping (
            String,
            @MainActor (WebKitShaderFetcher.State) -> Void
        ) async throws -> String
    ) {
        self.currentEditorSource = currentEditorSource
        self.fetchShadertoy = fetchShadertoy
    }

    func resolve(_ spec: ParentSpec) async throws -> String {
        try await resolve(spec, onFetchState: { _ in })
    }

    func resolve(
        _ spec: ParentSpec,
        onFetchState: @escaping @MainActor (WebKitShaderFetcher.State) -> Void
    ) async throws -> String {
        switch spec {
        case .pastedISF(let s):
            return s
        case .currentEditor:
            guard let s = currentEditorSource(), !s.isEmpty else { throw RemixParentError.noEditorShader }
            return s
        case .libraryFile(let url):
            return try String(contentsOf: url, encoding: .utf8)
        case .shadertoyLink(let urlText):
            return try await fetchShadertoy(urlText, onFetchState)
        }
    }

    /// The real importer chain used in production (exercised on-device, faked in unit tests).
    /// `apiKey` reads the user's Shadertoy API key (empty -> WebKit fetch path).
    static func liveFetch(apiKey: @escaping () -> String) -> (
        String,
        @MainActor (WebKitShaderFetcher.State) -> Void
    ) async throws -> String {
        { urlText, onState in
            guard let id = ShadertoyURL.shaderID(from: urlText) else { throw RemixParentError.badShadertoyURL }
            let key = apiKey()
            let shader: Shader
            switch FetchStrategy.select(hasKey: !key.isEmpty) {
            case .api:     shader = try await ShadertoyClient(key: key).fetchShader(id: id)
            case .webView:
                shader = try await WebKitShaderFetcher().fetchShader(id: id, onState: onState)
            }
            let (doc, _) = ISFConverter.convert(shader)
            return doc.fileText
        }
    }
}
