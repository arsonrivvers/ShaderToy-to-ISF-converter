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

    public static func apiURL(id: String, key: String) -> URL {
        var c = URLComponents(string: "https://www.shadertoy.com/api/v1/shaders/\(id)")!
        c.queryItems = [URLQueryItem(name: "key", value: key)]
        return c.url!
    }

    public func fetchShader(id: String) async throws -> Shader {
        let (data, status) = try await fetcher.fetch(Self.apiURL(id: id, key: key))
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
}
