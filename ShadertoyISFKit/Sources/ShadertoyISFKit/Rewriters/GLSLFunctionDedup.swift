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
        // Function-definition header at line start: <return type(+qualifiers)> <name>(<params>) {.
        // `[^;{}]*` params + requiring two+ words before `(` excludes control flow (`if (`, `for (`).
        let re = try! NSRegularExpression(
            pattern: "(?m)^[ \\t]*[A-Za-z_]\\w*(?:[ \\t]+[A-Za-z_]\\w*)*[ \\t]+[A-Za-z_]\\w*[ \\t]*\\([^;{}]*\\)[ \\t]*\\{")
        let s = code as NSString
        let matches = re.matches(in: code, range: NSRange(location: 0, length: s.length))

        var seen = Set<String>()
        var removals: [(start: Int, end: Int)] = []   // UTF-16 ranges to delete
        for m in matches {
            let bracePos = m.range.location + m.range.length - 1   // the `{`
            guard let endExclusive = braceMatchEnd(s, openBrace: bracePos) else { continue }
            let block = s.substring(with: NSRange(location: m.range.location, length: endExclusive - m.range.location))
            // Key on CODE only: strip // and /* */ comments and collapse whitespace, so two tab
            // copies that differ only in comments/formatting still dedup (identical code → safe).
            let key = block
                .replacingOccurrences(of: "//[^\\n]*", with: "", options: .regularExpression)
                .replacingOccurrences(of: "/\\*[\\s\\S]*?\\*/", with: "", options: .regularExpression)
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)
            if seen.contains(key) { removals.append((m.range.location, endExclusive)) }
            else { seen.insert(key) }
        }
        guard !removals.isEmpty else { return code }
        let out = NSMutableString(string: code)
        for r in removals.sorted(by: { $0.start > $1.start }) {   // last → first keeps offsets valid
            out.deleteCharacters(in: NSRange(location: r.start, length: r.end - r.start))
        }
        return out as String
    }

    /// Index just past the `}` matching the `{` at `openBrace`, skipping // and /* */ comments.
    private static func braceMatchEnd(_ s: NSString, openBrace: Int) -> Int? {
        let slash: unichar = 47, star: unichar = 42, nl: unichar = 10
        let open: unichar = 123, close: unichar = 125
        var depth = 0, i = openBrace, mode = 0   // 0 normal, 1 line comment, 2 block comment
        while i < s.length {
            let c = s.character(at: i)
            let n: unichar? = i + 1 < s.length ? s.character(at: i + 1) : nil
            switch mode {
            case 1: if c == nl { mode = 0 }
            case 2: if c == star, n == slash { mode = 0; i += 2; continue }
            default:
                if c == slash, n == slash { mode = 1 }
                else if c == slash, n == star { mode = 2 }
                else if c == open { depth += 1 }
                else if c == close { depth -= 1; if depth == 0 { return i + 1 } }
            }
            i += 1
        }
        return nil
    }
}
