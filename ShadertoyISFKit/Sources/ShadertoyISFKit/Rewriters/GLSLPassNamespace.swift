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
        // 1. Collect each pass's top-level definitions — functions AND file-scope globals — as
        //    (name + normalized body key). Both can collide across passes and are renamed identically.
        var defsPerPass: [[(name: String, key: String)]] = []
        for body in passBodies {
            let s = body as NSString
            var entries: [(name: String, key: String)] = []
            for d in GLSLFunctionScanner.defs(in: body) where d.name != "mainImage" {
                let block = s.substring(with: NSRange(location: d.start, length: d.end - d.start))
                entries.append((d.name, GLSLFunctionScanner.normalize(block)))
            }
            for d in GLSLGlobalScanner.defs(in: body) {
                let block = s.substring(with: NSRange(location: d.start, length: d.end - d.start))
                entries.append((d.name, GLSLFunctionScanner.normalize(block)))
            }
            defsPerPass.append(entries)
        }

        // 2. For each name: which passes define it, how many DISTINCT bodies exist, and the set of
        //    identifiers its body references (for the transitive step below).
        var passesByName: [String: Set<Int>] = [:]
        var keysByName: [String: Set<String>] = [:]
        var tokensByName: [String: Set<String>] = [:]
        for (idx, defs) in defsPerPass.enumerated() {
            for d in defs {
                passesByName[d.name, default: []].insert(idx)
                keysByName[d.name, default: []].insert(d.key)
                tokensByName[d.name, default: []].formUnion(identifiers(in: d.key))
            }
        }

        // 3. Seed: namespace a name defined in 2+ passes whose bodies DIFFER (identical collisions are
        //    dedup's job). Then take the transitive closure: an identical-bodied helper defined in 2+
        //    passes must ALSO be namespaced if it references a name already in the set — once that
        //    callee is renamed per-pass (p{idx}_…), the identical copies diverge and dedup can no
        //    longer collapse them (tXlfzr's calcNormal calls the per-pass-differing `map`).
        var toNamespace = Set(passesByName.keys.filter {
            (passesByName[$0]?.count ?? 0) >= 2 && (keysByName[$0]?.count ?? 0) >= 2
        })
        let identicalMultiPass = passesByName.keys.filter {
            (passesByName[$0]?.count ?? 0) >= 2 && (keysByName[$0]?.count ?? 0) == 1
        }
        var changed = true
        while changed {
            changed = false
            for name in identicalMultiPass where !toNamespace.contains(name) {
                if let toks = tokensByName[name],
                   toks.contains(where: { $0 != name && toNamespace.contains($0) }) {
                    toNamespace.insert(name); changed = true
                }
            }
        }
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

    /// All identifier tokens in a (normalized) body — used to detect which helper names a body calls.
    private static func identifiers(in code: String) -> Set<String> {
        let re = try! NSRegularExpression(pattern: "[A-Za-z_]\\w*")
        let s = code as NSString
        var out: Set<String> = []
        for m in re.matches(in: code, range: NSRange(location: 0, length: s.length)) {
            out.insert(s.substring(with: m.range))
        }
        return out
    }
}
