import Foundation

public enum FixRuleEngine {
    public static func suggestions(for d: Diagnostic, sourceLine: String?) -> [FixSuggestion] {
        var out: [FixSuggestion] = []
        for rule in rules { out += rule(d, sourceLine) }
        return out
    }

    private typealias Rule = (Diagnostic, String?) -> [FixSuggestion]
    private static var rules: [Rule] { [texture2DRule] }

    private static func texture2DRule(_ d: Diagnostic, _ src: String?) -> [FixSuggestion] {
        guard let src, src.contains("texture2D("), let line = d.line else { return [] }
        let fixed = src.replacingOccurrences(of: "texture2D(", with: "IMG_PIXEL(")
        return [FixSuggestion(
            title: "Replace texture2D with IMG_PIXEL",
            explanation: "ISF (and the Metal/VDMX engine) don't provide GLSL ES 1.00 'texture2D'. Use the ISF image sampler IMG_PIXEL(image, pixelCoord) (or IMG_NORM_PIXEL for normalized coords).",
            edit: TextEdit(fromLine: line, toLine: line, replacement: fixed, expectedContains: "texture2D("))]
    }
}
