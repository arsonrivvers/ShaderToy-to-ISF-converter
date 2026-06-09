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
        let fixed = src.replacingOccurrences(of: "texture2D(", with: "IMG_PIXEL(")
        return [FixSuggestion(
            title: "Replace texture2D with IMG_PIXEL",
            explanation: "ISF (and the Metal/VDMX engine) don't provide GLSL ES 1.00 'texture2D'. Use the ISF image sampler IMG_PIXEL(image, pixelCoord) (or IMG_NORM_PIXEL for normalized coords).",
            edit: TextEdit(fromLine: line, toLine: line, replacement: fixed, expectedContains: "texture2D("))]
    }

    private static func reservedWordRule(_ d: Diagnostic, _ src: String?) -> [FixSuggestion] {
        guard let r = d.message.range(of: #"'([A-Za-z_][A-Za-z0-9_]*)' : Reserved word"#, options: .regularExpression) else { return [] }
        let name = String(d.message[r].drop(while: { $0 != "'" }).dropFirst().prefix(while: { $0 != "'" }))
        guard let line = d.line, let src else { return [] }
        let renamed = src.replacingOccurrences(of: name, with: name + "_")
        return [FixSuggestion(
            title: "Rename reserved word '\(name)'",
            explanation: "'\(name)' is reserved in Metal Shading Language, so the shader won't compile. Rename it (e.g. '\(name)_'). Check other lines that use '\(name)' too — this fix only edits the reported line.",
            edit: TextEdit(fromLine: line, toLine: line, replacement: renamed, expectedContains: name))]
    }

    private static func tanhRule(_ d: Diagnostic, _ src: String?) -> [FixSuggestion] {
        guard d.message.contains("'tanh'"), let line = d.line, let src else { return [] }
        let polyfill = "float tanh_(float x){ float e=exp(2.0*x); return (e-1.0)/(e+1.0); }"
        let rewritten = src.replacingOccurrences(of: "tanh(", with: "tanh_(")
        return [FixSuggestion(
            title: "Add a tanh polyfill",
            explanation: "GLSL ES 1.00 / this target lacks 'tanh'. Insert a polyfill and call it instead. (For vec types, add matching overloads.)",
            edit: TextEdit(fromLine: line, toLine: line, replacement: polyfill + "\n" + rewritten, expectedContains: "tanh("))]
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
