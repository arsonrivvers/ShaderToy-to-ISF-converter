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
    /// `\)[ \t\r\n]*\{` allows the opening brace on its own line (Allman style — WdtXzs, t3ycDR);
    /// the params class already spans newlines, so multi-line signatures are covered too.
    private static let headerPattern =
        "(?m)^[ \\t]*[A-Za-z_]\\w*(?:[ \\t]+[A-Za-z_]\\w*)*[ \\t]+[A-Za-z_]\\w*[ \\t]*\\([^;{}]*\\)[ \\t\\r\\n]*\\{"

    /// GLSL reserved control-flow keywords. A two-word construct like `else if (...)` would otherwise
    /// be mis-read as a function whose name is `if` — and (post Allman-brace support) renaming or
    /// deduping that "function" would corrupt the keyword. None are valid function names.
    private static let controlKeywords: Set<String> = ["if", "for", "while", "switch", "do", "else", "return"]

    /// A top-level function definition with its parameter NAMES — the C5/M20 scope model.
    struct FunctionDef { let name: String; let paramNames: [String]; let start: Int; let end: Int }

    /// All top-level function definitions in `code`, in source order. Header matching runs on
    /// comment-masked text (M14: a commented-out function can't become a Def); ranges index into
    /// the original, which is offset-identical.
    static func functionDefs(in code: String) -> [FunctionDef] {
        let re = try! NSRegularExpression(pattern: headerPattern)
        let masked = GLSLScanner.strip(code)
        let ms = masked as NSString
        var out: [FunctionDef] = []
        for m in re.matches(in: masked, range: NSRange(location: 0, length: ms.length)) {
            let bracePos = m.range.location + m.range.length - 1   // the `{`
            guard let end = GLSLScanner.braceMatchEnd(code, openBrace: bracePos) else { continue }
            let header = ms.substring(with: m.range)               // masked: params are comment-free
            guard let name = lastIdentifierBeforeParen(header) else { continue }
            if controlKeywords.contains(name) { continue }   // `else if (...)` etc. — not a function
            out.append(FunctionDef(name: name, paramNames: paramNames(inHeader: header),
                                   start: m.range.location, end: end))
        }
        return out
    }

    /// All top-level function definitions (legacy shape for Dedup/Namespace).
    static func defs(in code: String) -> [Def] {
        functionDefs(in: code).map { Def(name: $0.name, start: $0.start, end: $0.end) }
    }

    /// Key on CODE only: blank comment content (shared scanner) and collapse whitespace plus the
    /// kept delimiter tokens, so two copies differing only in comments/formatting compare equal.
    static func normalize(_ block: String) -> String {
        GLSLScanner.strip(block)
            .replacingOccurrences(of: "//", with: " ")
            .replacingOccurrences(of: "/*", with: " ")
            .replacingOccurrences(of: "*/", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    /// Parameter NAMES from a (masked) definition header: text between the first `(` and last `)`,
    /// split on commas (GLSL params contain no parens), each param's name = its last identifier
    /// before any `[` array suffix. `()`/`(void)` → [].
    private static func paramNames(inHeader header: String) -> [String] {
        guard let open = header.firstIndex(of: "("), let close = header.lastIndex(of: ")"),
              open < close else { return [] }
        let inner = header[header.index(after: open)..<close]
        let idRe = try! NSRegularExpression(pattern: "[A-Za-z_]\\w*")
        var names: [String] = []
        for piece in inner.split(separator: ",") {
            let text = String(piece)
            let beforeArray = text.firstIndex(of: "[").map { String(text[..<$0]) } ?? text
            let ns = beforeArray as NSString
            let ids = idRe.matches(in: beforeArray, range: NSRange(location: 0, length: ns.length))
                .map { ns.substring(with: $0.range) }
            if let last = ids.last, last != "void" { names.append(last) }
        }
        return names
    }

    /// The function name = the last identifier immediately before the `(` in a definition header.
    private static func lastIdentifierBeforeParen(_ header: String) -> String? {
        guard let paren = header.firstIndex(of: "(") else { return nil }
        let ids = header[..<paren].split(whereSeparator: { !($0.isLetter || $0.isNumber || $0 == "_") })
        return ids.last.map(String.init)
    }

}
