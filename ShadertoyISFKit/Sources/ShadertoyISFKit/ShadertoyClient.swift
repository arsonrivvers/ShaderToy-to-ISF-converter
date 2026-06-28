import Foundation

public protocol DataFetching: Sendable {
    /// Returns (body, httpStatusCode).
    func fetch(_ url: URL) async throws -> (Data, Int)
}

public struct URLSessionFetcher: DataFetching {
    public init() {}
    public func fetch(_ url: URL) async throws -> (Data, Int) {
        let (data, response) = try await URLSession.shared.data(from: url)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        return (data, status)
    }
}

public enum ShadertoyClientError: Error, Equatable {
    case shaderNotAccessible   // private, or not "public + API"
    case httpError(Int)
    case decodingFailed
    case invalidShaderID       // id not a well-formed Shadertoy id (alphanumeric)
}

private struct ShadertoyAPIError: Decodable { let error: String
    enum CodingKeys: String, CodingKey { case error = "Error" } }

public struct ShadertoyClient {
    private let key: String
    private let fetcher: DataFetching

    public init(key: String, fetcher: DataFetching = URLSessionFetcher()) {
        self.key = key
        self.fetcher = fetcher
    }

    /// Builds the shader-fetch URL. `id` is untrusted (pasted URL / manual entry); Shadertoy ids are
    /// alphanumeric, so reject anything else rather than force-unwrapping a URL built from arbitrary
    /// text (a malformed paste used to crash here). The key is carried as a query item, which
    /// percent-encodes its value safely.
    public static func apiURL(id: String, key: String) throws -> URL {
        guard !id.isEmpty, id.allSatisfy({ $0.isLetter || $0.isNumber }),
              var c = URLComponents(string: "https://www.shadertoy.com/api/v1/shaders/\(id)") else {
            throw ShadertoyClientError.invalidShaderID
        }
        c.queryItems = [URLQueryItem(name: "key", value: key)]
        guard let url = c.url else { throw ShadertoyClientError.invalidShaderID }
        return url
    }

    /// Fetches a shader, retrying once on a *transient* failure (network error, HTTP 429, or 5xx).
    /// Definitive outcomes (not-accessible, decode failure, other 4xx) are surfaced immediately.
    public func fetchShader(id: String, maxAttempts: Int = 2) async throws -> Shader {
        var attempt = 0
        while true {
            attempt += 1
            do {
                return try await attemptFetch(id: id)
            } catch let e as ShadertoyClientError where Self.isTransient(e) && attempt < maxAttempts {
                continue
            } catch let e where !(e is ShadertoyClientError) && attempt < maxAttempts {
                continue   // network-layer error → retry
            }
        }
    }

    private func attemptFetch(id: String) async throws -> Shader {
        let (data, status) = try await fetcher.fetch(Self.apiURL(id: id, key: key))   // throws .invalidShaderID
        guard status == 200 else { throw ShadertoyClientError.httpError(status) }
        // Shadertoy returns {"Error": "..."} (HTTP 200) for inaccessible shaders.
        if (try? JSONDecoder().decode(ShadertoyAPIError.self, from: data)) != nil {
            throw ShadertoyClientError.shaderNotAccessible
        }
        do {
            return try JSONDecoder().decode(ShadertoyResponse.self, from: data).shader
        } catch {
            throw ShadertoyClientError.decodingFailed
        }
    }

    private static func isTransient(_ e: ShadertoyClientError) -> Bool {
        if case .httpError(let s) = e { return s == 429 || s >= 500 }
        return false
    }
}
