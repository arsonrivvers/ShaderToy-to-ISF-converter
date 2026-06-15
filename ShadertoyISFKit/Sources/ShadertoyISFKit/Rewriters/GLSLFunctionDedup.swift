import Foundation

/// Removes byte-identical duplicate top-level function definitions.
///
/// Why: a multipass Shadertoy shader with no Common tab often copies the same helper into each tab.
/// Shadertoy compiles passes separately, so that's fine there — but the converter merges every pass
/// into one GLSL file (PASSINDEX dispatch), so the duplicated helper becomes a redeclaration
/// ("ERR: 'hash' : function already has a body"). Removing an exact-duplicate definition is
/// semantically safe; definitions that share a name but differ in body are LEFT alone (the conflict
/// stays visible rather than silently dropping one).
public enum GLSLFunctionDedup {
    public static func dedup(_ code: String) -> String {
        let s = code as NSString
        var seen = Set<String>()
        var removals: [(start: Int, end: Int)] = []   // UTF-16 ranges to delete
        for d in GLSLFunctionScanner.defs(in: code) {
            let block = s.substring(with: NSRange(location: d.start, length: d.end - d.start))
            let key = GLSLFunctionScanner.normalize(block)
            if seen.contains(key) { removals.append((d.start, d.end)) }
            else { seen.insert(key) }
        }
        guard !removals.isEmpty else { return code }
        let out = NSMutableString(string: code)
        for r in removals.sorted(by: { $0.start > $1.start }) {   // last → first keeps offsets valid
            out.deleteCharacters(in: NSRange(location: r.start, length: r.end - r.start))
        }
        return out as String
    }
}
