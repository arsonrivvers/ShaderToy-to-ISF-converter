import Foundation

/// Shared identifier/call-site parsing for GLSL rewriters. Replaces `fn(arg0, arg1, …)` with a
/// caller-supplied transform, respecting nested parentheses and word boundaries. Used by
/// SamplerRewriter (per-pass sampling) and CommonChannelRewriter (Common-tab PASSINDEX dispatch).
enum GLSLCallParser {
    /// Replaces every `fn(...)` whose top-level arg count equals `arity` with `transform(args)`.
    /// Returning nil from `transform` leaves that call untouched.
    static func replaceCall(in code: String, fn: String, arity: Int,
                            transform: ([String]) -> String?) -> String {
        var result = ""
        let chars = Array(code)
        var i = 0
        let fnChars = Array(fn)
        var inLine = false, inBlock = false   // never match/rewrite a call sitting inside a comment
        while i < chars.count {
            let c = chars[i]
            let next = i + 1 < chars.count ? chars[i + 1] : " "
            if inLine {
                result.append(c); if c == "\n" { inLine = false }; i += 1; continue
            }
            if inBlock {
                result.append(c)
                if c == "*" && next == "/" { result.append(next); inBlock = false; i += 2; continue }
                i += 1; continue
            }
            if c == "/" && next == "/" { inLine = true; result.append(c); i += 1; continue }
            if c == "/" && next == "*" { inBlock = true; result.append(c); i += 1; continue }
            if matchesIdentifier(chars, at: i, fn: fnChars) {
                let openIdx = i + fnChars.count
                if openIdx < chars.count, chars[openIdx] == "(" {
                    if let (args, endIdx) = parseArgs(chars, openParen: openIdx), args.count == arity {
                        // Rewrite calls nested inside the args first (texture-inside-texture is the
                        // standard distortion/feedback idiom) — skipping past the outer match would
                        // otherwise leave the inner call raw.
                        let nested = args.map { replaceCall(in: $0, fn: fn, arity: arity,
                                                            transform: transform) }
                        if let replacement = transform(nested) {
                            result += replacement
                            i = endIdx + 1
                            continue
                        }
                    }
                }
            }
            result.append(chars[i]); i += 1
        }
        return result
    }

    /// True if `fn` occurs at `i` as a standalone identifier (not a substring of a longer one).
    static func matchesIdentifier(_ chars: [Character], at i: Int, fn: [Character]) -> Bool {
        guard i + fn.count <= chars.count else { return false }
        for k in 0..<fn.count where chars[i + k] != fn[k] { return false }
        if i > 0, isIdentChar(chars[i - 1]) { return false }              // left boundary
        let after = i + fn.count
        if after < chars.count, isIdentChar(chars[after]) { return false } // right boundary
        return true
    }

    static func isIdentChar(_ c: Character) -> Bool { c.isLetter || c.isNumber || c == "_" }

    /// Parses comma-separated args starting at the open paren; returns (args, indexOfCloseParen).
    static func parseArgs(_ chars: [Character], openParen: Int) -> (args: [String], end: Int)? {
        var depth = 0, i = openParen
        var current = "", args: [String] = []
        var inLine = false, inBlock = false   // parens/commas inside comments are not arg structure
        while i < chars.count {
            let c = chars[i]
            let next = i + 1 < chars.count ? chars[i + 1] : " "
            if inLine {
                current.append(c); if c == "\n" { inLine = false }; i += 1; continue
            }
            if inBlock {
                current.append(c)
                if c == "*" && next == "/" { current.append(next); inBlock = false; i += 2; continue }
                i += 1; continue
            }
            if c == "/" && next == "/" { inLine = true; current.append(c); i += 1; continue }
            if c == "/" && next == "*" { inBlock = true; current.append(c); i += 1; continue }
            if c == "(" { depth += 1; if depth == 1 { i += 1; continue } }
            if c == ")" { depth -= 1; if depth == 0 { args.append(current); return (args, i) } }
            if c == "," && depth == 1 { args.append(current); current = ""; i += 1; continue }
            current.append(c); i += 1
        }
        return nil
    }
}
