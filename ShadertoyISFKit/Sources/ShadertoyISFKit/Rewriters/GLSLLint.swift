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
        uninitializedAccumulatorOutputs(code).map { name in
            ConversionWarning(severity: .warning,
                message: "Output '\(name)' is accumulated (\(name) *= / +=) before being initialized — this relies on zero-initialization, which GLSL/ISF does not guarantee. If the result is black or garbage, add '\(name) = vec4(0.0);' before the loop.",
                context: "")
        }
    }

    /// Names of `out vec4` outputs that are compound-assigned (`O *= / += / …`) before any plain
    /// assignment — the auto-fixable subset handled by `OutputInitializer`. Shared so the linter and
    /// the fixer agree on detection.
    public static func uninitializedAccumulatorOutputs(_ code: String) -> [String] {
        let ns = code as NSString
        // `\b` so `inout vec4` never matches as `out vec4` — compound-assign-first is the normal
        // idiom for an inout accumulator, not an uninitialized output.
        let sig = try! NSRegularExpression(pattern: "\\bout\\s+vec4\\s+(\\w+)")
        var checked = Set<String>()
        var result: [String] = []
        for m in sig.matches(in: code, range: NSRange(location: 0, length: ns.length)) {
            let name = ns.substring(with: m.range(at: 1))
            if !checked.insert(name).inserted { continue }
            guard let compoundIdx = firstMatchIndex(code, "\\b\(name)\\s*[*+/\\-]=") else { continue }
            let plainIdx = firstMatchIndex(code, "(?<![*+/<>=!\\-])\\b\(name)\\s*=(?!=)")
            if plainIdx == nil || compoundIdx < plainIdx! { result.append(name) }
        }
        return result
    }

    private static func firstMatchIndex(_ code: String, _ pattern: String) -> Int? {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = code as NSString
        return re.firstMatch(in: code, range: NSRange(location: 0, length: ns.length)).map { $0.range.location }
    }
}
