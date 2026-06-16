import Foundation

/// Per-pass preprocessor-macro scoping.
///
/// Why: Shadertoy compiles each render pass as a SEPARATE translation unit, so a pass's `#define` is
/// invisible to every other pass. The converter merges all passes into ONE ISF `.fs` file, where
/// preprocessor macros are file-global and leak forward from their definition to end-of-file. Two
/// real failure classes result:
///   1. **Declaration shadowing** (FLOATCONSTANT — 4ldGDB/4XXGDl/ftGXzz/Ndc3zj): Buf A `#define _G0
///      0.25` then Buf B `const float _G0 = 0.25;`. The live macro rewrites the declaration into
///      `const float 0.25 = 0.25;` → "syntax error, unexpected FLOATCONSTANT".
///   2. **Redefinition** (M3cGW2 `bb`, tlX3zs `A`): two passes each `#define` the same macro. The
///      bodies are identical in source but SamplerRewriter rewrites the `iChannelN` inside each to a
///      per-pass sampler → glslang sees "Macro redefined; different substitutions".
///
/// Fix: restore the per-pass isolation by emitting `#undef NAME` at the END of every pass that defines
/// a macro whose name ALSO appears in another pass (as a redefinition or as a real identifier). A macro
/// used only within its own pass collides with nothing and is left byte-for-byte unchanged — like
/// GLSLPassNamespace, the overwhelming majority of shaders are untouched. Common-tab macros are never
/// seen here (they live in `commonCode`), so genuinely shared macros stay shared.
enum GLSLPassMacroScoper {
    static func scope(_ passBodies: [String]) -> [String] {
        // 1. Each pass's own macro definitions (object- and function-like), in definition order.
        //    `(?m)^…#define NAME` captures the name up to the word boundary — the `(` of a
        //    function-like macro is excluded, which is exactly what `#undef` wants (bare name).
        let defineRe = try! NSRegularExpression(
            pattern: "(?m)^[ \\t]*#define[ \\t]+([A-Za-z_]\\w*)")
        var definedPerPass: [[String]] = []
        for body in passBodies {
            let s = body as NSString
            var names: [String] = []
            var seen = Set<String>()
            for m in defineRe.matches(in: body, range: NSRange(location: 0, length: s.length)) {
                let name = s.substring(with: m.range(at: 1))
                if seen.insert(name).inserted { names.append(name) }
            }
            definedPerPass.append(names)
        }

        // 2. For each defined name, the set of passes whose text mentions it as a whole word — a macro
        //    is in-collision iff that set extends beyond its own defining pass.
        var passesMentioning: [String: Set<Int>] = [:]
        let allNames = Set(definedPerPass.flatMap { $0 })
        for name in allNames {
            let wordRe = try! NSRegularExpression(
                pattern: "\\b" + NSRegularExpression.escapedPattern(for: name) + "\\b")
            for (idx, body) in passBodies.enumerated() {
                let s = body as NSString
                if wordRe.firstMatch(in: body, range: NSRange(location: 0, length: s.length)) != nil {
                    passesMentioning[name, default: []].insert(idx)
                }
            }
        }

        // 3. Append `#undef NAME` (in definition order) to each pass for the macros it defines that
        //    also appear in some OTHER pass. Trailing — so the macro stays live for its own pass's code.
        var out = passBodies
        for (idx, names) in definedPerPass.enumerated() {
            let colliding = names.filter { name in
                passesMentioning[name]?.contains(where: { $0 != idx }) ?? false
            }
            guard !colliding.isEmpty else { continue }
            let undefs = colliding.map { "#undef \($0)" }.joined(separator: "\n")
            out[idx] = out[idx] + "\n" + undefs
        }
        return out
    }
}
