import Foundation

/// Best-effort detection of shader patterns that compile but may misbehave in ISF and
/// aren't auto-fixable — surfaced as warnings so the user knows what to check.
public enum GLSLLint {
    public static func check(_ code: String) -> [ConversionWarning] {
        uninitializedOutputAccumulator(code)
    }

    /// Detects the "code-golf" pattern where an `out vec4` is modified with a compound
    /// assignment (O *= / O += / …) before it is ever plainly assigned — relying on
    /// zero-initialization, which GLSL/ISF does not guarantee (common in @XorDev shaders).
    private static func uninitializedOutputAccumulator(_ code: String) -> [ConversionWarning] {
        var warnings: [ConversionWarning] = []
        let ns = code as NSString
        let sig = try! NSRegularExpression(pattern: "out\\s+vec4\\s+(\\w+)")
        var checked = Set<String>()
        for m in sig.matches(in: code, range: NSRange(location: 0, length: ns.length)) {
            let name = ns.substring(with: m.range(at: 1))
            if !checked.insert(name).inserted { continue }
            guard let compoundIdx = firstMatchIndex(code, "\\b\(name)\\s*[*+/\\-]=") else { continue }
            let plainIdx = firstMatchIndex(code, "(?<![*+/<>=!\\-])\\b\(name)\\s*=(?!=)")
            if plainIdx == nil || compoundIdx < plainIdx! {
                warnings.append(ConversionWarning(severity: .warning,
                    message: "Output '\(name)' is accumulated (\(name) *= / +=) before being initialized — this relies on zero-initialization, which GLSL/ISF does not guarantee. If the result is black or garbage, add '\(name) = vec4(0.0);' before the loop.",
                    context: ""))
            }
        }
        return warnings
    }

    private static func firstMatchIndex(_ code: String, _ pattern: String) -> Int? {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = code as NSString
        return re.firstMatch(in: code, range: NSRange(location: 0, length: ns.length)).map { $0.range.location }
    }
}
