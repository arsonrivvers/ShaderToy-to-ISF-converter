import Foundation

/// THE shared GLSL character scanner (DESLOPPIFY M3). One state machine tracking comment /
/// preprocessor-directive state and brace/paren depth over a string's UTF-16 units; every
/// consumer needing "am I in a comment / what's the depth here" builds on `scan` or a helper
/// below. Do NOT hand-roll another `inLine`/`inBlock` walker — extend this one.
///
/// Semantics (locked by GLSLScannerTests):
/// - `braceDepth`/`parenDepth` are the depth BEFORE the current unit's own effect: an opening
///   `{` is reported at its OUTER depth, a closing `}` at its inner one.
/// - Comment flags cover the ENTIRE comment INCLUDING delimiters; `isCommentDelimiter` is true
///   exactly for the two units of `//`, `/*`, `*/`.
/// - `inDirective` spans a `#` line (first non-blank unit on the line) up to just before its
///   newline. Comments still open inside directives (`#define X 1 // note`). Depth is never
///   counted inside comments OR directives (a `#define Main …{` must not desync brace depth —
///   the ssjyWc header-macro class that CommonUniformRewriter.walkRuns pioneered handling).
/// - No `\` line-continuation handling: GLSLLineContinuation.splice runs before every scanner
///   consumer (ISFConverter stages 1/5), so directives are single-line here.
/// - Totality: no throws; an unterminated block comment stays open to end-of-string; unbalanced
///   closers never push depth below 0.
enum GLSLScanner {
    struct State {
        var inLineComment = false
        var inBlockComment = false
        /// True for the two units of a `//`, `/*` or `*/` token (strip keeps these, blanks content).
        var isCommentDelimiter = false
        var inDirective = false
        var braceDepth = 0
        var parenDepth = 0
        var inComment: Bool { inLineComment || inBlockComment }
    }

    /// Walks every UTF-16 unit of `code`, calling `body(index, unit, state)`. Return false from
    /// `body` to stop early. Every other helper in this enum is a query over this one machine.
    static func scan(_ code: String, _ body: (Int, unichar, State) -> Bool) {
        let s = code as NSString
        let slash: unichar = 47, star: unichar = 42, nl: unichar = 10, hash: unichar = 35
        let ob: unichar = 123, cb: unichar = 125, op: unichar = 40, cp: unichar = 41
        let sp: unichar = 32, tab: unichar = 9
        var st = State()
        var atLineStart = true
        var i = 0
        while i < s.length {
            let c = s.character(at: i)
            let n: unichar? = i + 1 < s.length ? s.character(at: i + 1) : nil
            st.isCommentDelimiter = false

            if st.inLineComment {
                if c == nl {
                    st.inLineComment = false
                    st.inDirective = false
                    if !body(i, c, st) { return }
                    atLineStart = true
                    i += 1; continue
                }
                if !body(i, c, st) { return }
                i += 1; continue
            }
            if st.inBlockComment {
                if c == star, n == slash {
                    st.isCommentDelimiter = true
                    if !body(i, c, st) { return }
                    if !body(i + 1, slash, st) { return }
                    st.inBlockComment = false
                    atLineStart = false
                    i += 2; continue
                }
                if !body(i, c, st) { return }
                if c == nl { atLineStart = true } else if c != sp, c != tab { atLineStart = false }
                i += 1; continue
            }
            if c == slash, n == slash {
                st.inLineComment = true
                st.isCommentDelimiter = true
                if !body(i, c, st) { return }
                if !body(i + 1, slash, st) { return }
                atLineStart = false
                i += 2; continue
            }
            if c == slash, n == star {
                st.inBlockComment = true
                st.isCommentDelimiter = true
                if !body(i, c, st) { return }
                if !body(i + 1, star, st) { return }
                atLineStart = false
                i += 2; continue
            }
            if c == nl { st.inDirective = false }
            else if atLineStart, c == hash { st.inDirective = true }
            if !body(i, c, st) { return }
            if !st.inDirective {
                switch c {
                case ob: st.braceDepth += 1
                case cb: if st.braceDepth > 0 { st.braceDepth -= 1 }
                case op: st.parenDepth += 1
                case cp: if st.parenDepth > 0 { st.parenDepth -= 1 }
                default: break
                }
            }
            if c == nl { atLineStart = true }
            else if c != sp, c != tab { atLineStart = false }
            i += 1
        }
    }

    /// Blanks comment CONTENT (a space per non-newline unit), keeping `//` `/*` `*/` delimiters
    /// and all newlines — UTF-16 offsets are EXACTLY preserved (an astral char in a comment
    /// becomes two spaces), so match ranges found on the masked text index straight into the
    /// original. Detection scans and structure parsing run on this; rewrites edit the original.
    static func strip(_ code: String) -> String {
        var units: [unichar] = []
        units.reserveCapacity((code as NSString).length)
        let nl: unichar = 10, sp: unichar = 32
        scan(code) { _, c, st in
            units.append(st.inComment && !st.isCommentDelimiter && c != nl ? sp : c)
            return true
        }
        return String(utf16CodeUnits: units, count: units.count)
    }

    /// Brace depth immediately before UTF-16 position `pos` (0 = file scope).
    /// Precondition: `pos` < the string's UTF-16 length.
    static func braceDepth(_ code: String, before pos: Int) -> Int {
        var depth = 0
        scan(code) { i, _, st in
            if i >= pos { depth = st.braceDepth; return false }
            return true
        }
        return depth
    }

    /// Brace AND paren depth immediately before UTF-16 position `pos` — for callers that must
    /// exclude both function bodies and parameter lists (GLSLGlobalScanner: a line-leading param
    /// in a multi-line signature sits at brace 0 but paren 1). Same precondition as `braceDepth`.
    static func depths(_ code: String, before pos: Int) -> (brace: Int, paren: Int) {
        var result = (brace: 0, paren: 0)
        scan(code) { i, _, st in
            if i >= pos { result = (st.braceDepth, st.parenDepth); return false }
            return true
        }
        return result
    }

    /// Index just past the first `;` at or after `from` outside comments and directives
    /// (a `;` in a `#define` body does not end a declaration statement).
    static func statementEnd(_ code: String, from: Int) -> Int? {
        let semi: unichar = 59
        var result: Int? = nil
        scan(code) { i, c, st in
            if i < from { return true }
            if c == semi, !st.inComment, !st.inDirective { result = i + 1; return false }
            return true
        }
        return result
    }

    /// Index just past the `}` matching the `{` at `openBrace` (which must sit outside comments).
    static func braceMatchEnd(_ code: String, openBrace: Int) -> Int? {
        let ob: unichar = 123, cb: unichar = 125
        var depth = 0
        var result: Int? = nil
        scan(code) { i, c, st in
            if i < openBrace { return true }
            if st.inComment || st.inDirective { return true }
            if c == ob { depth += 1 }
            else if c == cb { depth -= 1; if depth == 0 { result = i + 1; return false } }
            return true
        }
        return result
    }

    /// Splits the args of a call whose `(` sits at `openParen` (outside comments). Returns the
    /// UTF-16 range of each top-level arg (comment text inside args is covered by the ranges —
    /// callers slice the ORIGINAL so comments survive verbatim) and the index of the matching
    /// `)`. Commas/parens inside comments are not structure. nil when the list never closes.
    static func splitArgs(_ code: String, openParen: Int) -> (argRanges: [NSRange], close: Int)? {
        let op: unichar = 40, cp: unichar = 41, comma: unichar = 44
        var depth = 0
        var argStart = openParen + 1
        var ranges: [NSRange] = []
        var close: Int? = nil
        scan(code) { i, c, st in
            if i < openParen || st.inComment { return true }
            if c == op { depth += 1; if depth == 1 { argStart = i + 1 }; return true }
            if c == cp {
                depth -= 1
                if depth == 0 {
                    ranges.append(NSRange(location: argStart, length: i - argStart))
                    close = i
                    return false
                }
                return true
            }
            if c == comma, depth == 1 {
                ranges.append(NSRange(location: argStart, length: i - argStart))
                argStart = i + 1
            }
            return true
        }
        guard let c = close else { return nil }
        return (ranges, c)
    }
}
