import Foundation

/// Shared scanner for top-level GLSL function definitions. Used by both GLSLFunctionDedup
/// (remove byte-identical duplicates) and GLSLPassNamespace (rename cross-pass collisions).
/// Centralizes the header regex + brace matching so the two rewriters can't drift.
enum GLSLFunctionScanner {
    /// A top-level function definition: its name and the UTF-16 range of the whole `…name(…){ … }`
    /// block (`end` is exclusive, just past the matching `}`).
    struct Def { let name: String; let start: Int; let end: Int }

    /// Function-definition header at line start: <return type(+qualifiers)> <name>(<params>) {.
    /// `[^;{}]*` params + requiring two+ words before `(` excludes control flow (`if (`, `for (`).
    private static let headerPattern =
        "(?m)^[ \\t]*[A-Za-z_]\\w*(?:[ \\t]+[A-Za-z_]\\w*)*[ \\t]+[A-Za-z_]\\w*[ \\t]*\\([^;{}]*\\)[ \\t]*\\{"

    /// All top-level function definitions in `code`, in source order.
    static func defs(in code: String) -> [Def] {
        let re = try! NSRegularExpression(pattern: headerPattern)
        let s = code as NSString
        var out: [Def] = []
        for m in re.matches(in: code, range: NSRange(location: 0, length: s.length)) {
            let bracePos = m.range.location + m.range.length - 1   // the `{`
            guard let end = braceMatchEnd(s, openBrace: bracePos) else { continue }
            let header = s.substring(with: m.range)
            guard let name = lastIdentifierBeforeParen(header) else { continue }
            out.append(Def(name: name, start: m.range.location, end: end))
        }
        return out
    }

    /// Key on CODE only: strip // and /* */ comments and collapse whitespace, so two tab copies
    /// that differ only in comments/formatting compare equal (identical code → safe to treat as one).
    static func normalize(_ block: String) -> String {
        block
            .replacingOccurrences(of: "//[^\\n]*", with: "", options: .regularExpression)
            .replacingOccurrences(of: "/\\*[\\s\\S]*?\\*/", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    /// The function name = the last identifier immediately before the `(` in a definition header.
    private static func lastIdentifierBeforeParen(_ header: String) -> String? {
        guard let paren = header.firstIndex(of: "(") else { return nil }
        let ids = header[..<paren].split(whereSeparator: { !($0.isLetter || $0.isNumber || $0 == "_") })
        return ids.last.map(String.init)
    }

    /// Index just past the `}` matching the `{` at `openBrace`, skipping // and /* */ comments.
    static func braceMatchEnd(_ s: NSString, openBrace: Int) -> Int? {
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
