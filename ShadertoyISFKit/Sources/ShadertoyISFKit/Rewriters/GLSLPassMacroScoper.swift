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
    static func scope(_ passBodies: [String], commonCode: String) -> [String] {
        // All detection runs on comment-masked text (offsets identical to the originals): a
        // `#define` inside a comment is not a definition, and a name mentioned only in a comment
        // is not a collision (M18's comment-awareness — was: spurious #undef).
        let strippedBodies = passBodies.map { GLSLScanner.strip($0) }
        let strippedCommon = GLSLScanner.strip(commonCode)

        // 0. Common macros: name → the full original #define line, for restore-after-shadowing
        //    (M18: a pass redefining a Common macro must not destroy its meaning for later passes).
        var commonDefineLine: [String: String] = [:]
        let lineRe = try! NSRegularExpression(pattern: "(?m)^[ \\t]*#define[ \\t]+([A-Za-z_]\\w*).*$")
        let scn = strippedCommon as NSString
        for m in lineRe.matches(in: strippedCommon, range: NSRange(location: 0, length: scn.length)) {
            let name = scn.substring(with: m.range(at: 1))
            if commonDefineLine[name] == nil {
                commonDefineLine[name] = (commonCode as NSString).substring(with: m.range)
            }
        }

        // 1. Each pass's own macro definitions (object- and function-like), in definition order,
        //    with the match location of the first defining line. `(?m)^…#define NAME` captures the
        //    name up to the word boundary — the `(` of a function-like macro is excluded, which is
        //    exactly what `#undef` wants (bare name).
        let defineRe = try! NSRegularExpression(
            pattern: "(?m)^[ \\t]*#define[ \\t]+([A-Za-z_]\\w*)")
        var definedPerPass: [[(name: String, at: Int)]] = []
        for body in strippedBodies {
            let s = body as NSString
            var defs: [(String, Int)] = []
            var seen = Set<String>()
            for m in defineRe.matches(in: body, range: NSRange(location: 0, length: s.length)) {
                let name = s.substring(with: m.range(at: 1))
                if seen.insert(name).inserted { defs.append((name, m.range.location)) }
            }
            definedPerPass.append(defs)
        }

        // 2. For each defined name, the set of passes whose CODE mentions it as a whole word — a
        //    macro is in-collision iff that set extends beyond its own defining pass.
        var passesMentioning: [String: Set<Int>] = [:]
        let allNames = Set(definedPerPass.flatMap { $0.map(\.name) })
        for name in allNames {
            let wordRe = try! NSRegularExpression(
                pattern: "\\b" + NSRegularExpression.escapedPattern(for: name) + "\\b")
            for (idx, body) in strippedBodies.enumerated() {
                let s = body as NSString
                if wordRe.firstMatch(in: body, range: NSRange(location: 0, length: s.length)) != nil {
                    passesMentioning[name, default: []].insert(idx)
                }
            }
        }

        var out = passBodies
        for (idx, defs) in definedPerPass.enumerated() {
            var body = out[idx]
            // 3a. Common shadowing (M18): `#undef` right BEFORE the pass's own redefinition (code
            //     above it legitimately uses the Common meaning), and the Common definition
            //     restored after the pass body.
            let shadowingCommon = defs.filter { commonDefineLine[$0.name] != nil }
            for def in shadowingCommon.sorted(by: { $0.at > $1.at }) {   // back-to-front insert
                let ns = body as NSString
                body = ns.substring(to: def.at) + "#undef \(def.name)\n" + ns.substring(from: def.at)
            }
            if !shadowingCommon.isEmpty {
                let restores = shadowingCommon.map { "#undef \($0.name)\n\(commonDefineLine[$0.name]!)" }
                body = body + "\n" + restores.joined(separator: "\n")
            }
            // 3b. Pass-vs-pass collisions (pre-existing behavior): trailing #undef for macros this
            //     pass defines that another pass mentions. Common-shadowing names already got theirs.
            let shadowNames = Set(shadowingCommon.map(\.name))
            let colliding = defs.map(\.name).filter { name in
                !shadowNames.contains(name)
                    && (passesMentioning[name]?.contains(where: { $0 != idx }) ?? false)
            }
            if !colliding.isEmpty {
                body = body + "\n" + colliding.map { "#undef \($0)" }.joined(separator: "\n")
            }
            out[idx] = body
        }
        return out
    }
}
