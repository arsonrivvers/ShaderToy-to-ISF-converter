import Foundation

public enum ShadertoyInternalParserError: Error, Equatable {
    case shaderNotFound
    case malformed
}

/// Parses the response from Shadertoy's internal `/shadertoy` endpoint, which returns
/// a JSON array `[{ver,info,renderpass}]` (no `Shader` wrapper).
public enum ShadertoyInternalParser {
    public static func parse(_ data: Data) throws -> Shader {
        let decoder = JSONDecoder()
        if let shaders = try? decoder.decode([Shader].self, from: data) {
            guard let first = shaders.first else { throw ShadertoyInternalParserError.shaderNotFound }
            return first
        }
        // Not an array → likely an error object like {"Error":"..."} or empty/garbage.
        throw ShadertoyInternalParserError.shaderNotFound
    }
}
