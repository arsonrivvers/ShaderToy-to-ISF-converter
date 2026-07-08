import Foundation

public enum GLSLBodyBuilder {
    public struct Result { public let code: String; public let warnings: [ConversionWarning] }

    /// Stage 9 of the `ISFConverter` pipeline (see its header comment for the full ordered list).
    /// NOTE: two ordered conversion stages live HERE rather than in `ISFConverter`, so they aren't
    /// visible in that function's body: 9a `GLSLPassNamespace.namespace`, then 9b
    /// `GLSLPassMacroScoper.scope`, then 9c the per-pass `mainImage` rename + PASSINDEX dispatch.
    public static func build(passBodies: [String], commonCode: String) -> Result {
        var warnings: [ConversionWarning] = []
        var functions: [String] = []
        var dispatch: [String] = []

        // Rename helpers that collide across passes with differing bodies (Shadertoy compiles passes
        // separately; the merge into one file would otherwise hit "function already has a body").
        let namespaced = GLSLPassNamespace.namespace(passBodies)

        // Scope each pass's `#define`s with a trailing `#undef` — preprocessor macros are file-global
        // once passes are concatenated, so a pass macro otherwise leaks into later passes (rewriting a
        // same-named declaration → FLOATCONSTANT, or colliding as a redefinition). Restores Shadertoy's
        // per-pass isolation.
        let scoped = GLSLPassMacroScoper.scope(namespaced)

        for (idx, body) in scoped.enumerated() {
            let fnName = "pass\(idx)_mainImage"
            functions.append(renameMainImage(body, to: fnName))
            if containsVectorTernary(body) {
                warnings.append(ConversionWarning(severity: .warning,
                    message: "Possible vector ternary (a ? b : c) — unreliable on Metal/macOS ISF; rewrite as if/else.",
                    context: "pass \(idx)"))
            }
            // The dispatch temp is deliberately not a short name like `c`: a golfed pass's
            // object-like `#define c ...` stays live at main() and would expand the declaration.
            let isLast = idx == passBodies.count - 1
            if isLast {
                dispatch.append("    if (PASSINDEX == \(idx)) { vec4 _isf_passColor; \(fnName)(_isf_passColor, gl_FragCoord.xy); gl_FragColor = _isf_passColor; }")
            } else {
                dispatch.append("    if (PASSINDEX == \(idx)) { vec4 _isf_passColor; \(fnName)(_isf_passColor, gl_FragCoord.xy); gl_FragColor = _isf_passColor; return; }")
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
