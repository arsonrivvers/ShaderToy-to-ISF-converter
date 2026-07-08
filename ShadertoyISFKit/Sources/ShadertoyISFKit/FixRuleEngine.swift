import Foundation

public enum FixRuleEngine {
    public static func suggestions(for d: Diagnostic, sourceLine: String?) -> [FixSuggestion] {
        var out: [FixSuggestion] = []
        for rule in rules { out += rule(d, sourceLine) }
        return out
    }

    private typealias Rule = (Diagnostic, String?) -> [FixSuggestion]
    private static var rules: [Rule] { [texture2DRule, reservedWordRule, tanhRule, undeclaredRule] }

    private static func texture2DRule(_ d: Diagnostic, _ src: String?) -> [FixSuggestion] {
        guard let src, src.contains("texture2D("), let line = d.line else { return [] }
        // Use IMG_NORM_PIXEL (normalized coords) to match the batch SamplerRewriter — Shadertoy's
        // texture2D takes normalized UV. (Was IMG_PIXEL, i.e. pixel coords — the opposite space,
        // which sampled wrong vs. what the converter itself emits.)
        let fixed = src.replacingOccurrences(of: "texture2D(", with: "IMG_NORM_PIXEL(")
        return [FixSuggestion(
            title: "Replace texture2D with IMG_NORM_PIXEL",
            explanation: "ISF (and the Metal/VDMX engine) don't provide GLSL ES 1.00 'texture2D'. Use the ISF image sampler IMG_NORM_PIXEL(image, normalizedCoord) — Shadertoy's texture2D uses normalized UV. (Use IMG_PIXEL only if the coordinate is in pixels.)",
            edit: TextEdit(fromLine: line, toLine: line, replacement: fixed, expectedContains: "texture2D("))]
    }

    private static func reservedWordRule(_ d: Diagnostic, _ src: String?) -> [FixSuggestion] {
        guard let r = d.message.range(of: #"'([A-Za-z_][A-Za-z0-9_]*)' : Reserved word"#, options: .regularExpression) else { return [] }
        let name = String(d.message[r].drop(while: { $0 != "'" }).dropFirst().prefix(while: { $0 != "'" }))
        guard let line = d.line, let src else { return [] }
        // Word-boundary rename to the SAME alias the batch GLSLReservedIdentifierRewriter uses
        // (`usr_<name>`). The old unbounded `replacingOccurrences(of: name)` rewrote the word inside
        // other identifiers (`inside` → `_inside`) for short reserved words, corrupting the line.
        let alias = GLSLReservedIdentifierRewriter.prefix + name
        let re = try! NSRegularExpression(pattern: "\\b" + NSRegularExpression.escapedPattern(for: name) + "\\b")
        let renamed = re.stringByReplacingMatches(in: src, range: NSRange(src.startIndex..<src.endIndex, in: src),
            withTemplate: NSRegularExpression.escapedTemplate(for: alias))
        return [FixSuggestion(
            title: "Rename reserved word '\(name)'",
            explanation: "'\(name)' is reserved in Metal Shading Language, so the shader won't compile. Rename it to '\(alias)'. Check other lines that use '\(name)' too — this fix only edits the reported line.",
            edit: TextEdit(fromLine: line, toLine: line, replacement: renamed, expectedContains: name))]
    }

    // Guidance-only: the diagnostic line is by definition inside a function body, so a one-line
    // edit inserting the polyfill there would nest a function definition — invalid GLSL, a
    // guaranteed second compile error presented as a "fix". TextEdit can't express "insert at file
    // top AND rewrite this line", so until it can, hand the user the recipe instead of a bad edit.
    // (The batch path is unaffected: GLSLCompat prepends a guarded global tanh overload set.)
    private static func tanhRule(_ d: Diagnostic, _ src: String?) -> [FixSuggestion] {
        guard d.message.contains("'tanh'"), d.line != nil, src != nil else { return [] }
        let polyfill = "float tanh_(float x){ float e=exp(2.0*x); return (e-1.0)/(e+1.0); }"
        return [FixSuggestion(
            title: "Add a tanh polyfill",
            explanation: "GLSL ES 1.00 / this target lacks 'tanh'. Add this polyfill at the TOP of the file, outside any function: \(polyfill) — then rename this line's call to tanh_(…). (For vec types, add matching overloads.)",
            edit: nil)]
    }

    private static func undeclaredRule(_ d: Diagnostic, _ src: String?) -> [FixSuggestion] {
        guard let r = d.message.range(of: #"'([A-Za-z_][A-Za-z0-9_]*)' : undeclared identifier"#, options: .regularExpression) else { return [] }
        let token = String(d.message[r].drop(while: { $0 != "'" }).dropFirst().prefix(while: { $0 != "'" }))
        return [FixSuggestion(
            title: "Undeclared identifier '\(token)'",
            explanation: "'\(token)' isn't declared. Common causes: a typo, a missing variable/uniform declaration, or an ISF builtin spelled differently (hover ISF builtins in the editor to check names like RENDERSIZE, isf_FragNormCoord, IMG_PIXEL).",
            edit: nil)]
    }
}
