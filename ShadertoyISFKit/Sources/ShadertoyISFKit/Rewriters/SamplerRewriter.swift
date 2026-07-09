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
            return normSample(args[1], b)
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
                return normSample(args[1], b)
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
                return normSample(args[1], b)
            }
        }

        // Sampler builtins with no ISF mapping pass through textually (the bare rename below still
        // rewrites their sampler arg) — whether the leftover call compiles depends entirely on the
        // host's sampler declaration, so make the gap loud instead of silent.
        for fn in ["textureSize", "texelFetchOffset", "textureGrad", "textureProj"] {
            if out.range(of: "\\b\(fn)\\s*\\(\\s*iChannel\\d", options: .regularExpression) != nil {
                warnings.append(ConversionWarning(severity: .warning,
                    message: "\(fn)() has no ISF equivalent and was left as-is (its sampler is renamed to the bound input) — the shader may not compile; rewrite this call manually.",
                    context: ""))
            }
        }

        // Any bare `iChannelN` identifier that survives the call rewrites above is a value use —
        // e.g. the sampler passed as a function argument (`ups(..., iChannel0, ...)`), a pattern
        // some Shadertoy authors use to thread the channel through helper functions. Rewrite it to
        // the bound sampler name so it isn't left as an undeclared identifier. Runs per-pass with
        // this pass's bindings; the shared Common code (helper-function bodies whose `sampler2D
        // iChannelN` *parameters* must stay) is never routed through SamplerRewriter, so those are
        // untouched. Word boundaries keep `iChannel1` from matching `iChannel1img`/`iChannel10`.
        for (n, b) in bindings.sorted(by: { $0.key < $1.key }) {
            let pattern = "\\biChannel\(n)\\b"
            guard out.range(of: pattern, options: .regularExpression) != nil else { continue }
            // A bare identifier can only carry ONE sampler name — audio loses its waveform half,
            // cubemap loses the equirect projection. Rewrite anyway (undeclared is worse) but warn.
            if b.kind == .audio, b.auxName != nil {
                warnings.append(ConversionWarning(severity: .warning,
                    message: "iChannel\(n) (audio) is passed as a bare value — only the FFT sampler '\(b.glslName)' is bound; the waveform half is dropped. Verify audio-reactive behavior.",
                    context: ""))
            } else if b.kind == .cubemap {
                warnings.append(ConversionWarning(severity: .warning,
                    message: "iChannel\(n) (cubemap) is passed as a bare value — bound to the 2D stub '\(b.glslName)' with no direction projection. Verify sampling.",
                    context: ""))
            }
            out = out.replacingOccurrences(of: pattern, with: b.glslName,
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
        GLSLCallParser.channelIndex(forArg: arg).flatMap { bindings[$0] }
    }

    /// The sample coordinate for a binding: cubemap channels are sampled with a vec3 direction, so
    /// project it to 2D via `_dirToEquirect` (ISF has no cubemap; the helper is injected by
    /// GLSLCompat when present). All other (2D) channels pass the coordinate through unchanged.
    private static func coord(_ raw: String, _ b: ChannelBinding.Binding) -> String {
        b.kind == .cubemap ? "_dirToEquirect(\(raw.trimmed))" : raw.trimmed
    }

    /// A normalized (`IMG_NORM_PIXEL`) sample of `b` at `rawCoord`. Audio channels read FFT below the
    /// halfway row and waveform above it (Shadertoy's 512×2 layout); ISF splits these into two
    /// samplers, so select between them by the read's y at runtime with `step` (a vector ternary is
    /// unreliable on Metal). Cubemap projects via `_dirToEquirect`; everything else samples directly.
    private static func normSample(_ rawCoord: String, _ b: ChannelBinding.Binding) -> String {
        let c = rawCoord.trimmed
        if b.kind == .audio, let wave = b.auxName {
            let fftS  = "IMG_NORM_PIXEL(\(b.glslName), vec2((\(c)).x, 0.5))"
            let waveS = "IMG_NORM_PIXEL(\(wave), vec2((\(c)).x, 0.5))"
            return "mix(\(fftS), \(waveS), step(0.5, (\(c)).y))"
        }
        return "IMG_NORM_PIXEL(\(b.glslName), \(coord(rawCoord, b)))"
    }

    /// Replaces `fn(arg0, arg1, ...)` with `transform(args)`, respecting nested parens.
    /// Only replaces calls with exactly `arity` top-level comma-separated args.
    private static func replaceCall(in code: String, fn: String, arity: Int,
                                    transform: ([String]) -> String?) -> String {
        GLSLCallParser.replaceCall(in: code, fn: fn, arity: arity, transform: transform)
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
