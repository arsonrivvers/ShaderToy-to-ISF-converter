import Foundation

/// Resolves `iChannelN` SAMPLING inside Common-tab code, which SamplerRewriter can't handle.
///
/// Why: SamplerRewriter runs per-pass with that pass's bindings. Common code is shared across passes,
/// and in many multipass shaders the same channel index maps to a DIFFERENT buffer in each pass
/// (e.g. XftGRj's `#define A(U) texelFetch(iChannel0,ivec2(U),0)` — iChannel0 is bufB in one pass,
/// bufA in another). A GLSL macro is file-global, so no single textual rewrite of Common can be
/// per-pass-correct, and an un-rewritten `iChannel0` is an undeclared identifier → black screen.
///
/// Fix: replace each `texelFetch`/`texture`/`textureLod(iChannelN, …)` in Common with a call to a
/// generated dispatcher function `_chN_texel`/`_chN_tex` that branches on `PASSINDEX` and samples the
/// binding for the current pass. Consistent-binding channels collapse to identical branches (still
/// correct). Bare `iChannelN` identifiers (a sampler threaded as a value) are NOT handled — GLSL can't
/// return a sampler from the dispatcher; those stay for a future pass.
enum CommonChannelRewriter {
    struct Result {
        let dispatchers: String      // generated dispatcher fn definitions; prepend ahead of Common
        let rewrittenCommon: String  // Common with iChannelN sampling calls routed to dispatchers
        let warnings: [ConversionWarning]
    }

    static func rewrite(commonCode: String,
                        perChannelPerPass: [Int: [Int: ChannelBinding.Binding]],
                        passCount: Int) -> Result {
        var code = commonCode
        var warnings: [ConversionWarning] = []
        var needTexel = Set<Int>()
        var needTex = Set<Int>()

        // Shared with SamplerRewriter (tolerates a trailing comment in the channel arg) so the
        // per-pass and Common paths can't disagree on what counts as an iChannelN argument.
        func chan(_ arg: String) -> Int? { GLSLCallParser.channelIndex(forArg: arg) }
        func coord(_ arg: String) -> String { arg.trimmingCharacters(in: .whitespacesAndNewlines) }

        // texelFetch(iChannelN, COORD, LOD) -> _chN_texel(COORD)  (pixel-coord access)
        code = GLSLCallParser.replaceCall(in: code, fn: "texelFetch", arity: 3) { args in
            guard let n = chan(args[0]) else { return nil }
            needTexel.insert(n)
            return "_ch\(n)_texel(\(coord(args[1])))"
        }
        // textureLod(iChannelN, COORD, LOD) -> _chN_tex(COORD)  (LOD dropped — ISF has no per-sample LOD)
        code = GLSLCallParser.replaceCall(in: code, fn: "textureLod", arity: 3) { args in
            guard let n = chan(args[0]) else { return nil }
            needTex.insert(n)
            return "_ch\(n)_tex(\(coord(args[1])))"
        }
        // texture / texture2D(iChannelN, COORD) -> _chN_tex(COORD)  (normalized access)
        for fn in ["texture2D", "texture"] {
            code = GLSLCallParser.replaceCall(in: code, fn: fn, arity: 2) { args in
                guard let n = chan(args[0]) else { return nil }
                needTex.insert(n)
                return "_ch\(n)_tex(\(coord(args[1])))"
            }
        }

        var defs: [String] = []
        for n in needTexel.sorted() {
            defs.append(makeDispatcher(channel: n, texel: true,
                                       perPass: perChannelPerPass[n] ?? [:], passCount: passCount,
                                       warnings: &warnings))
        }
        for n in needTex.sorted() {
            defs.append(makeDispatcher(channel: n, texel: false,
                                       perPass: perChannelPerPass[n] ?? [:], passCount: passCount,
                                       warnings: &warnings))
        }
        return Result(dispatchers: defs.joined(separator: "\n\n"), rewrittenCommon: code, warnings: warnings)
    }

    /// One dispatcher: `vec4 _chN_(texel|tex)(...) { if (PASSINDEX==p) { return IMG_*; } … return vec4(0.0); }`.
    /// The per-branch sampling mirrors SamplerRewriter's binding semantics: audio bindings split the
    /// read between the FFT and waveform samplers by the read's y (Shadertoy's 512×2 layout — flat
    /// FFT sampling would silently return spectrum data for waveform reads), and a cubemap-bound
    /// channel's tex dispatcher takes the vec3 direction its Common call sites actually pass,
    /// projecting via `_dirToEquirect` (a vec2 signature was a guaranteed type-mismatch).
    private static func makeDispatcher(channel n: Int, texel: Bool,
                                       perPass: [Int: ChannelBinding.Binding], passCount: Int,
                                       warnings: inout [ConversionWarning]) -> String {
        let name = texel ? "_ch\(n)_texel" : "_ch\(n)_tex"
        let isCube = !texel && perPass.values.contains { $0.kind == .cubemap }
        let param = texel ? "ivec2 U" : (isCube ? "vec3 dir" : "vec2 uv")
        var body = ""
        for p in 0..<passCount {
            guard let b = perPass[p] else { continue }
            body += "    if (PASSINDEX == \(p)) { return \(sample(b, texel: texel, isCube: isCube, channel: n, warnings: &warnings)); }\n"
        }
        if body.isEmpty {
            warnings.append(ConversionWarning(severity: .warning,
                message: "iChannel\(n) is sampled in the Common tab but no render pass binds it — Common reads return 0. Bind it or supply an input.",
                context: ""))
        }
        return "vec4 \(name)(\(param)) {\n\(body)    return vec4(0.0);\n}"
    }

    private static func sample(_ b: ChannelBinding.Binding, texel: Bool, isCube: Bool,
                               channel n: Int, warnings: inout [ConversionWarning]) -> String {
        if texel {
            if b.kind == .audio, let wave = b.auxName {
                let fft  = "IMG_PIXEL(\(b.glslName), vec2(vec2(U).x, 0.5))"
                let wav  = "IMG_PIXEL(\(wave), vec2(vec2(U).x, 0.5))"
                return "mix(\(fft), \(wav), step(0.5, float(U.y)))"
            }
            return "IMG_PIXEL(\(b.glslName), vec2(U))"
        }
        if isCube {
            if b.kind == .cubemap {
                return "IMG_NORM_PIXEL(\(b.glslName), _dirToEquirect(dir))"
            }
            // Mixed cubemap/2D binding across passes: the vec3-direction dispatcher can only guess
            // a uv for the 2D pass. Sample dir.xy and say so.
            warnings.append(ConversionWarning(severity: .warning,
                message: "iChannel\(n) binds a cubemap in one pass and a 2D input in another; the Common dispatcher samples the 2D input at dir.xy — verify.",
                context: ""))
            return "IMG_NORM_PIXEL(\(b.glslName), (dir).xy)"
        }
        if b.kind == .audio, let wave = b.auxName {
            let fft  = "IMG_NORM_PIXEL(\(b.glslName), vec2((uv).x, 0.5))"
            let wav  = "IMG_NORM_PIXEL(\(wave), vec2((uv).x, 0.5))"
            return "mix(\(fft), \(wav), step(0.5, (uv).y))"
        }
        return "IMG_NORM_PIXEL(\(b.glslName), uv)"
    }
}
