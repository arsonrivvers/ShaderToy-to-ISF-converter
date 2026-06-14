import Foundation

public enum ShadertoyInternalParserError: Error, Equatable {
    /// The endpoint returned an empty array, an `{"Error":...}` object, or non-array garbage —
    /// i.e. the shader genuinely isn't there / isn't accessible.
    case shaderNotFound
    /// The endpoint returned a shader payload we couldn't decode into `Shader` (an unsupported
    /// shape). `detail` carries the underlying decode error for diagnostics. Distinct from
    /// `shaderNotFound` so a public-but-unparseable shader isn't mislabeled "not found/private".
    case malformed(detail: String)
}

/// Parses the response from Shadertoy's internal `/shadertoy` endpoint, which returns
/// a JSON array `[{ver,info,renderpass}]` (no `Shader` wrapper).
public enum ShadertoyInternalParser {
    public static func parse(_ data: Data) throws -> Shader {
        // First decide WHAT kind of payload this is, so a decode failure on a real shader array
        // isn't conflated with "not found". A genuine not-found is an empty array, an error
        // object, or non-array garbage; anything else that's a populated array but won't decode
        // is `.malformed` (a shape we don't handle yet), which the UI reports honestly.
        let top = try? JSONSerialization.jsonObject(with: data)
        guard let array = top as? [Any] else {
            // Object (e.g. {"Error":"..."}) or non-JSON → treat as not found.
            throw ShadertoyInternalParserError.shaderNotFound
        }
        guard !array.isEmpty else { throw ShadertoyInternalParserError.shaderNotFound }

        do {
            let shaders = try JSONDecoder().decode([Shader].self, from: data)
            guard let first = shaders.first else { throw ShadertoyInternalParserError.shaderNotFound }
            return first
        } catch let decodeError {
            throw ShadertoyInternalParserError.malformed(detail: String(describing: decodeError))
        }
    }
}
