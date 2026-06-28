import Foundation

/// Renames user identifiers that are valid in GLSL but RESERVED in Metal Shading Language (C++14).
///
/// Shadertoy code compiles as GLSL ES 3.00, where `char`, `coord`, `class`, … are ordinary names.
/// The ISFMSLKit transpiler lowers to MSL, where they are keywords or `metal::` builtins, and the
/// Metal compile then fails — e.g. `float char = …` → "cannot combine with previous 'float'
/// declaration specifier" (7l3yz4, Nl3czM); a user `coord(…)` → "reference to 'coord' is ambiguous"
/// against `metal::coord` (wXffDH). None of the listed words is a GLSL builtin, so any WHOLE-WORD
/// occurrence is necessarily a user identifier and is safe to rename to a prefixed alias; `\b`
/// boundaries leave substrings like `chars` and `gl_FragCoord` untouched.
public enum GLSLReservedIdentifierRewriter {
    /// MSL / C++14 reserved words that are legal GLSL identifiers (so a Shadertoy shader may use one
    /// as a variable or function name). Deliberately EXCLUDES anything that is also a GLSL
    /// builtin/keyword (`texture`, `sampler`, `mix`, `mat`, …). Extend as new clashes surface.
    static let reserved: [String] = [
        "char", "coord",                                       // demonstrated: 7l3yz4/Nl3czM ; wXffDH
        "class", "template", "typename", "namespace", "using",
        "this", "new", "delete", "operator", "friend", "virtual",
        "private", "public", "protected", "union", "enum",
        "signed", "unsigned", "short", "long", "register", "goto",
    ]
    /// The alias prefix for a renamed reserved word. Internal so the interactive FixRuleEngine
    /// suggestion uses the SAME convention as this batch rewriter (was divergent: `name_` suffix).
    static let prefix = "usr_"

    public static func rewrite(_ code: String) -> String {
        var out = code
        for name in reserved {
            let re = try! NSRegularExpression(
                pattern: "\\b" + NSRegularExpression.escapedPattern(for: name) + "\\b")
            let range = NSRange(out.startIndex..<out.endIndex, in: out)
            out = re.stringByReplacingMatches(in: out, range: range,
                withTemplate: NSRegularExpression.escapedTemplate(for: prefix + name))
        }
        return out
    }
}
