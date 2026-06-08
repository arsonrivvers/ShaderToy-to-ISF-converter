import Foundation

public enum GLSLBodyBuilder {
    public struct Result { public let code: String; public let warnings: [ConversionWarning] }

    public static func build(passBodies: [String], commonCode: String) -> Result {
        var warnings: [ConversionWarning] = []
        var functions: [String] = []
        var dispatch: [String] = []

        for (idx, body) in passBodies.enumerated() {
            let fnName = "pass\(idx)_mainImage"
            functions.append(renameMainImage(body, to: fnName))
            if containsVectorTernary(body) {
                warnings.append(ConversionWarning(severity: .warning,
                    message: "Possible vector ternary (a ? b : c) — unreliable on Metal/macOS ISF; rewrite as if/else.",
                    context: "pass \(idx)"))
            }
            let isLast = idx == passBodies.count - 1
            if isLast {
                dispatch.append("    if (PASSINDEX == \(idx)) { vec4 c; \(fnName)(c, gl_FragCoord.xy); gl_FragColor = c; }")
            } else {
                dispatch.append("    if (PASSINDEX == \(idx)) { vec4 c; \(fnName)(c, gl_FragCoord.xy); gl_FragColor = c; return; }")
            }
        }

        var parts: [String] = []
        if !commonCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append(commonCode)
        }
        parts.append(contentsOf: functions)
        parts.append("void main() {\n" + dispatch.joined(separator: "\n") + "\n}")
        return Result(code: parts.joined(separator: "\n\n"), warnings: warnings)
    }

    /// Renames the `mainImage` identifier to `newName` (first occurrence, word-boundary safe).
    private static func renameMainImage(_ body: String, to newName: String) -> String {
        let pattern = "\\bmainImage\\b"
        let regex = try! NSRegularExpression(pattern: pattern)
        let range = NSRange(body.startIndex..<body.endIndex, in: body)
        return regex.stringByReplacingMatches(in: body, range: range,
            withTemplate: NSRegularExpression.escapedTemplate(for: newName))
    }

    /// Heuristic: a `?` followed later by `:` on the same line, with a vec/mat type nearby on the LHS.
    private static func containsVectorTernary(_ body: String) -> Bool {
        for line in body.components(separatedBy: .newlines) {
            guard line.contains("?"), line.contains(":") else { continue }
            if line.range(of: #"\b(vec2|vec3|vec4|mat2|mat3|mat4)\b"#, options: .regularExpression) != nil {
                return true
            }
        }
        return false
    }
}
