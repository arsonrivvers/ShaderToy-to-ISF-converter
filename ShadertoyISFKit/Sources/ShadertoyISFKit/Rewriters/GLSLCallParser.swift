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
                // GLSL permits whitespace between the function name and its paren.
                var openIdx = i + fnChars.count
                while openIdx < chars.count, chars[openIdx] == " " || chars[openIdx] == "\t" {
                    openIdx += 1
                }
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

    /// The channel index of an `iChannelN` argument, or nil. The arg may carry a trailing comment
    /// (`iChannel0 /* src */`), so match the LEADING identifier rather than requiring the whole
    /// trimmed token to parse — and the digits must end the identifier (`iChannel0img` is not
    /// channel 0). Single shared parser so per-pass and Common rewrites can't disagree.
    static func channelIndex(forArg arg: String) -> Int? {
        let t = arg.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.hasPrefix("iChannel") else { return nil }
        let rest = t.dropFirst("iChannel".count)
        let digits = rest.prefix { $0.isNumber }
        guard !digits.isEmpty, let n = Int(digits) else { return nil }
        if let after = rest.dropFirst(digits.count).first, after.isLetter || after == "_" { return nil }
        return n
    }

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
