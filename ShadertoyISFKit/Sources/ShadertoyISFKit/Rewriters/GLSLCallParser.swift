import Foundation

/// Shared identifier/call-site parsing for GLSL rewriters. Replaces `fn(arg0, arg1, …)` with a
/// caller-supplied transform, respecting nested parentheses and word boundaries. Used by
/// SamplerRewriter (per-pass sampling) and CommonChannelRewriter (Common-tab PASSINDEX dispatch).
///
/// Structure (comment skipping, arg splitting) is computed on GLSLScanner-masked text; arg text
/// is sliced from the ORIGINAL at the same UTF-16 offsets, so comments inside args are preserved.
enum GLSLCallParser {
    /// Replaces every `fn(...)` whose top-level arg count equals `arity` with `transform(args)`.
    /// Returning nil from `transform` leaves that call untouched (its args are still scanned for
    /// nested matches on the next search iteration). Calls inside comments never match — their
    /// identifier is blanked in the masked text.
    static func replaceCall(in code: String, fn: String, arity: Int,
                            transform: ([String]) -> String?) -> String {
        let masked = GLSLScanner.strip(code)
        let ns = code as NSString
        let mns = masked as NSString
        // GLSL permits whitespace between the function name and its paren (M21).
        let re = try! NSRegularExpression(
            pattern: "\\b" + NSRegularExpression.escapedPattern(for: fn) + "\\b[ \\t]*\\(")
        var result = ""
        var cursor = 0     // UTF-16 read position in the original
        var searchAt = 0
        while searchAt < mns.length,
              let m = re.firstMatch(in: masked,
                                    range: NSRange(location: searchAt, length: mns.length - searchAt)) {
            let openParen = m.range.location + m.range.length - 1
            guard let (argRanges, close) = GLSLScanner.splitArgs(masked, openParen: openParen),
                  argRanges.count == arity else {
                searchAt = m.range.location + m.range.length
                continue
            }
            // Rewrite calls nested inside the args first (texture-inside-texture is the standard
            // distortion/feedback idiom) — skipping past the outer match would leave them raw.
            let args = argRanges.map { ns.substring(with: $0) }
            let nested = args.map { replaceCall(in: $0, fn: fn, arity: arity, transform: transform) }
            if let replacement = transform(nested) {
                result += ns.substring(with: NSRange(location: cursor, length: m.range.location - cursor))
                result += replacement
                cursor = close + 1
                searchAt = close + 1
            } else {
                searchAt = m.range.location + m.range.length
            }
        }
        result += ns.substring(from: cursor)
        return result
    }

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
}
