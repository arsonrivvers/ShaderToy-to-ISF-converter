import Foundation

public enum SamplerRewriter {
    public struct Result { public let code: String; public let warnings: [ConversionWarning] }

    public static func rewrite(_ code: String,
                               bindings: [Int: ChannelBinding.Binding]) -> Result {
        var out = code
        var warnings: [ConversionWarning] = []

        // textureLod(iChannelN, COORD, LOD)  ->  IMG_NORM_PIXEL(name, COORD)  (+warn)
        out = replaceCall(in: out, fn: "textureLod", arity: 3) { args in
            guard let b = binding(forChannelArg: args[0], bindings: bindings) else { return nil }
            warnings.append(ConversionWarning(severity: .info,
                message: "textureLod LOD argument dropped (\(args[2].trimmed)); ISF has no per-sample LOD.",
                context: ""))
            return "IMG_NORM_PIXEL(\(b.glslName), \(coord(args[1], b)))"
        }

        // texelFetch(iChannelN, COORD, LOD) -> IMG_PIXEL(name, vec2(COORD))
        out = replaceCall(in: out, fn: "texelFetch", arity: 3) { args in
            guard let name = name(forChannelArg: args[0], bindings: bindings) else { return nil }
            return "IMG_PIXEL(\(name), vec2(\(args[1].trimmed)))"
        }

        // texture / texture2D (arity 2) -> IMG_NORM_PIXEL(name, COORD)
        for fn in ["texture2D", "texture"] {
            out = replaceCall(in: out, fn: fn, arity: 2) { args in
                guard let b = binding(forChannelArg: args[0], bindings: bindings) else { return nil }
                return "IMG_NORM_PIXEL(\(b.glslName), \(coord(args[1], b)))"
            }
        }

        // texture / texture2D with bias (arity 3) -> IMG_NORM_PIXEL(name, COORD) (+warn).
        // texture(sampler, coord, bias) is valid GLSL ES 3.00; ISF has no per-sample bias, so drop it
        // (mirrors textureLod). Without this the 3-arg call would pass through and fail to compile.
        for fn in ["texture2D", "texture"] {
            out = replaceCall(in: out, fn: fn, arity: 3) { args in
                guard let b = binding(forChannelArg: args[0], bindings: bindings) else { return nil }
                warnings.append(ConversionWarning(severity: .info,
                    message: "texture() bias argument dropped (\(args[2].trimmed)); ISF has no per-sample bias.",
                    context: ""))
                return "IMG_NORM_PIXEL(\(b.glslName), \(coord(args[1], b)))"
            }
        }

        // Any bare `iChannelN` identifier that survives the call rewrites above is a value use —
        // e.g. the sampler passed as a function argument (`ups(..., iChannel0, ...)`), a pattern
        // some Shadertoy authors use to thread the channel through helper functions. Rewrite it to
        // the bound sampler name so it isn't left as an undeclared identifier. Runs per-pass with
        // this pass's bindings; the shared Common code (helper-function bodies whose `sampler2D
        // iChannelN` *parameters* must stay) is never routed through SamplerRewriter, so those are
        // untouched. Word boundaries keep `iChannel1` from matching `iChannel1img`/`iChannel10`.
        for (n, b) in bindings {
            out = out.replacingOccurrences(of: "\\biChannel\(n)\\b", with: b.glslName,
                                           options: .regularExpression)
        }
        return Result(code: out, warnings: warnings)
    }

    private static func name(forChannelArg arg: String,
                             bindings: [Int: ChannelBinding.Binding]) -> String? {
        binding(forChannelArg: arg, bindings: bindings)?.glslName
    }

    private static func binding(forChannelArg arg: String,
                                bindings: [Int: ChannelBinding.Binding]) -> ChannelBinding.Binding? {
        let t = arg.trimmed
        guard t.hasPrefix("iChannel"), let n = Int(t.dropFirst("iChannel".count)) else { return nil }
        return bindings[n]
    }

    /// The sample coordinate for a binding: cubemap channels are sampled with a vec3 direction, so
    /// project it to 2D via `_dirToEquirect` (ISF has no cubemap; the helper is injected by
    /// GLSLCompat when present). All other (2D) channels pass the coordinate through unchanged.
    private static func coord(_ raw: String, _ b: ChannelBinding.Binding) -> String {
        b.kind == .cubemap ? "_dirToEquirect(\(raw.trimmed))" : raw.trimmed
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
