import Foundation

/// Removes byte-identical duplicate top-level definitions — functions AND file-scope globals.
///
/// Why: a multipass Shadertoy shader with no Common tab often copies the same helper (or the same
/// top-level constant / palette array) into each tab. Shadertoy compiles passes separately, so that's
/// fine there — but the converter merges every pass into one GLSL file (PASSINDEX dispatch), so the
/// duplicate becomes a redeclaration ("ERR: 'hash' : function already has a body" /
/// "'palAppleII' : redeclaration of array with size"). Removing an exact-duplicate definition is
/// semantically safe — and keeping ONE shared file-scope copy is what lets a pass that merely
/// references it (without redefining) still resolve. Definitions that share a name but differ in body
/// are LEFT alone (the conflict stays visible; GLSLPassNamespace renames those per-pass instead).
public enum GLSLFunctionDedup {
    public static func dedup(_ code: String) -> String {
        let s = code as NSString
        var seen = Set<String>()
        var removals: [(start: Int, end: Int)] = []   // UTF-16 ranges to delete
        var removedStarts = Set<Int>()                // a multi-declarator statement deletes ONCE
        // Functions and globals interleave in source — walk them together in source order so the
        // FIRST occurrence of each is the one kept. Global keys carry the declarator NAME (M2:
        // `float a, b;` yields Defs a and b sharing one statement — same text, distinct keys, so
        // the first statement's own b isn't a "duplicate" of its a); function keys never collide
        // with them (different syntax).
        let defs: [(name: String?, start: Int, end: Int)] =
            (GLSLFunctionScanner.defs(in: code).map { (name: String?.none, start: $0.start, end: $0.end) }
             + GLSLGlobalScanner.defs(in: code).map { (name: .some($0.name), start: $0.start, end: $0.end) })
            .sorted { $0.start < $1.start }
        for d in defs {
            let block = s.substring(with: NSRange(location: d.start, length: d.end - d.start))
            let key = (d.name.map { $0 + "\u{1F}" } ?? "") + GLSLFunctionScanner.normalize(block)
            if seen.contains(key) {
                if removedStarts.insert(d.start).inserted { removals.append((d.start, d.end)) }
            } else { seen.insert(key) }
        }
        guard !removals.isEmpty else { return code }
        let out = NSMutableString(string: code)
        for r in removals.sorted(by: { $0.start > $1.start }) {   // last → first keeps offsets valid
            out.deleteCharacters(in: NSRange(location: r.start, length: r.end - r.start))
        }
        return out as String
    }
}
