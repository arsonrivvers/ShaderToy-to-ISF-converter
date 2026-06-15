import Foundation

/// Per-pass function namespacing.
///
/// Why: Shadertoy compiles each render pass separately, so two passes may each define a top-level
/// helper with the SAME name but DIFFERENT bodies (e.g. flcSzr's `vec4 Po(int,int)` — one pass reads
/// bufA, another reads bufB). The converter merges every pass into one GLSL file (PASSINDEX dispatch),
/// where those two definitions collide: "function already has a body". GLSLFunctionDedup only removes
/// BYTE-IDENTICAL copies, so it can't resolve a real body difference.
///
/// Fix: when a top-level helper name is defined in 2+ passes with non-identical bodies, rename that
/// helper — its definition AND its call sites within the SAME pass — to a per-pass-unique `p{idx}_<name>`.
/// Names defined in only one pass, or identically across passes (dedup handles those), are left
/// untouched, so the overwhelming majority of shaders convert byte-for-byte as before.
///
/// `mainImage` is excluded — GLSLBodyBuilder renames it per pass downstream. Common-tab helpers are
/// never passed in here (they live in `commonCode`), so they stay shared; a pass that merely CALLS a
/// common helper (without defining it) is not in that name's defining set, so its call is left intact.
enum GLSLPassNamespace {
    static func namespace(_ passBodies: [String]) -> [String] {
        // 1. Collect each pass's top-level function definitions (name + normalized body key).
        var defsPerPass: [[(name: String, key: String)]] = []
        for body in passBodies {
            let s = body as NSString
            let defs = GLSLFunctionScanner.defs(in: body).filter { $0.name != "mainImage" }
            defsPerPass.append(defs.map { d in
                let block = s.substring(with: NSRange(location: d.start, length: d.end - d.start))
                return (d.name, GLSLFunctionScanner.normalize(block))
            })
        }

        // 2. For each name: which passes define it, and how many DISTINCT bodies exist.
        var passesByName: [String: Set<Int>] = [:]
        var keysByName: [String: Set<String>] = [:]
        for (idx, defs) in defsPerPass.enumerated() {
            for d in defs {
                passesByName[d.name, default: []].insert(idx)
                keysByName[d.name, default: []].insert(d.key)
            }
        }

        // 3. Namespace a name only if it's defined in 2+ passes AND the bodies aren't all identical
        //    (identical collisions are dedup's job — leave them so the output stays unchanged).
        let toNamespace = Set(passesByName.keys.filter {
            (passesByName[$0]?.count ?? 0) >= 2 && (keysByName[$0]?.count ?? 0) >= 2
        })
        guard !toNamespace.isEmpty else { return passBodies }

        // 4. In each pass that DEFINES a to-namespace name, rename whole-word occurrences (def + calls)
        //    to p{idx}_<name>. New names carry a `p{idx}_` prefix so they never re-match another rename.
        var out = passBodies
        for (idx, defs) in defsPerPass.enumerated() {
            let names = Set(defs.map { $0.name }).intersection(toNamespace)
            guard !names.isEmpty else { continue }
            var body = out[idx]
            for name in names {
                let re = try! NSRegularExpression(
                    pattern: "\\b" + NSRegularExpression.escapedPattern(for: name) + "\\b")
                let range = NSRange(body.startIndex..<body.endIndex, in: body)
                body = re.stringByReplacingMatches(in: body, range: range,
                    withTemplate: NSRegularExpression.escapedTemplate(for: "p\(idx)_\(name)"))
            }
            out[idx] = body
        }
        return out
    }
}
