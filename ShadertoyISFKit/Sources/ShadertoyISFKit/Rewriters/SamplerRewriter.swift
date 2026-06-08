import Foundation

public enum SamplerRewriter {
    public struct Result { public let code: String; public let warnings: [ConversionWarning] }

    public static func rewrite(_ code: String,
                               bindings: [Int: ChannelBinding.Binding]) -> Result {
        var out = code
        var warnings: [ConversionWarning] = []

        // textureLod(iChannelN, COORD, LOD)  ->  IMG_NORM_PIXEL(name, COORD)  (+warn)
        out = replaceCall(in: out, fn: "textureLod", arity: 3) { args in
            guard let name = name(forChannelArg: args[0], bindings: bindings) else { return nil }
            warnings.append(ConversionWarning(severity: .info,
                message: "textureLod LOD argument dropped (\(args[2].trimmed)); ISF has no per-sample LOD.",
                context: ""))
            return "IMG_NORM_PIXEL(\(name), \(args[1].trimmed))"
        }

        // texelFetch(iChannelN, COORD, LOD) -> IMG_PIXEL(name, vec2(COORD))
        out = replaceCall(in: out, fn: "texelFetch", arity: 3) { args in
            guard let name = name(forChannelArg: args[0], bindings: bindings) else { return nil }
            return "IMG_PIXEL(\(name), vec2(\(args[1].trimmed)))"
        }

        // texture / texture2D (arity 2) -> IMG_NORM_PIXEL(name, COORD)
        for fn in ["texture2D", "texture"] {
            out = replaceCall(in: out, fn: fn, arity: 2) { args in
                guard let name = name(forChannelArg: args[0], bindings: bindings) else { return nil }
                return "IMG_NORM_PIXEL(\(name), \(args[1].trimmed))"
            }
        }
        return Result(code: out, warnings: warnings)
    }

    private static func name(forChannelArg arg: String,
                             bindings: [Int: ChannelBinding.Binding]) -> String? {
        let t = arg.trimmed
        guard t.hasPrefix("iChannel"), let n = Int(t.dropFirst("iChannel".count)) else { return nil }
        return bindings[n]?.glslName
    }

    /// Replaces `fn(arg0, arg1, ...)` with `transform(args)`, respecting nested parens.
    /// Only replaces calls with exactly `arity` top-level comma-separated args.
    private static func replaceCall(in code: String, fn: String, arity: Int,
                                    transform: ([String]) -> String?) -> String {
        var result = ""
        let chars = Array(code)
        var i = 0
        let fnChars = Array(fn)
        while i < chars.count {
            if matchesIdentifier(chars, at: i, fn: fnChars) {
                let openIdx = i + fnChars.count
                if openIdx < chars.count, chars[openIdx] == "(" {
                    if let (args, endIdx) = parseArgs(chars, openParen: openIdx), args.count == arity,
                       let replacement = transform(args) {
                        result += replacement
                        i = endIdx + 1
                        continue
                    }
                }
            }
            result.append(chars[i]); i += 1
        }
        return result
    }

    private static func matchesIdentifier(_ chars: [Character], at i: Int, fn: [Character]) -> Bool {
        guard i + fn.count <= chars.count else { return false }
        for k in 0..<fn.count where chars[i + k] != fn[k] { return false }
        if i > 0, isIdentChar(chars[i - 1]) { return false }   // left boundary
        let after = i + fn.count
        if after < chars.count, isIdentChar(chars[after]) { return false }  // right boundary (e.g. textureLod vs texture)
        return true
    }

    private static func isIdentChar(_ c: Character) -> Bool { c.isLetter || c.isNumber || c == "_" }

    /// Parses comma-separated args starting at the open paren; returns (args, indexOfCloseParen).
    private static func parseArgs(_ chars: [Character], openParen: Int) -> (args: [String], end: Int)? {
        var depth = 0, i = openParen
        var current = "", args: [String] = []
        while i < chars.count {
            let c = chars[i]
            if c == "(" { depth += 1; if depth == 1 { i += 1; continue } }
            if c == ")" { depth -= 1; if depth == 0 { args.append(current); return (args, i) } }
            if c == "," && depth == 1 { args.append(current); current = ""; i += 1; continue }
            current.append(c); i += 1
        }
        return nil
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
