import Foundation

/// Expands a Common-tab "header macro" that hides the `mainImage` entry-point signature.
///
/// Why: some shaders write `#define Main void mainImage(out vec4 Q, in vec2 U)` in the Common tab and
/// then `Main { … }` in each pass. The literal `mainImage` only exists inside the macro, so
/// GLSLBodyBuilder's per-pass `mainImage` → `passN_mainImage` rename never sees it. At glslang
/// preprocess time the macro expands to `void mainImage(…)` in EVERY pass → duplicate definition
/// ("function already has a body").
///
/// Fix: substitute the macro into each pass body (so the literal `mainImage` is present and the per-pass
/// rename can make it unique) and strip the `#define` from Common. Only OBJECT-LIKE macros whose body
/// contains `mainImage` are touched; function-like macros (`#define X(a) …`) are left alone.
enum HeaderMacroExpander {
    struct Result { let commonCode: String; let passBodies: [String] }

    static func expand(commonCode: String, passBodies: [String]) -> Result {
        // Object-like `#define NAME BODY` whose BODY mentions `mainImage`. `(?m)` line-anchored;
        // `NAME` not immediately followed by `(` (that would be function-like). LineContinuation has
        // already joined `\`-continued defines, so BODY is the whole single line.
        let re = try! NSRegularExpression(
            pattern: "(?m)^[ \\t]*#define[ \\t]+([A-Za-z_]\\w*)[ \\t]+([^\\n]*\\bmainImage\\b[^\\n]*)$")
        let ns = commonCode as NSString
        let matches = re.matches(in: commonCode, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return Result(commonCode: commonCode, passBodies: passBodies) }

        var common = commonCode
        var bodies = passBodies
        // Apply last → first so removing one #define line doesn't shift the others' ranges.
        for m in matches.reversed() {
            let name = ns.substring(with: m.range(at: 1))
            let expansion = ns.substring(with: m.range(at: 2)).trimmingCharacters(in: .whitespaces)
            // Substitute NAME (whole word) → expansion in every pass body.
            let wordRe = try! NSRegularExpression(
                pattern: "\\b" + NSRegularExpression.escapedPattern(for: name) + "\\b")
            bodies = bodies.map { body in
                let r = NSRange(body.startIndex..<body.endIndex, in: body)
                return wordRe.stringByReplacingMatches(in: body, range: r,
                    withTemplate: NSRegularExpression.escapedTemplate(for: expansion))
            }
            // Drop the #define line (including its trailing newline if present).
            var delete = m.range
            if delete.location + delete.length < ns.length,
               ns.character(at: delete.location + delete.length) == 10 {   // '\n'
                delete.length += 1
            }
            common = (common as NSString).replacingCharacters(in: delete, with: "")
        }
        return Result(commonCode: common, passBodies: bodies)
    }
}
