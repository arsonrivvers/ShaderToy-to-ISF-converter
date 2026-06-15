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

        func chan(_ arg: String) -> Int? {
            let t = arg.trimmingCharacters(in: .whitespacesAndNewlines)
            guard t.hasPrefix("iChannel"), let n = Int(t.dropFirst("iChannel".count)) else { return nil }
            return n
        }
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
    private static func makeDispatcher(channel n: Int, texel: Bool,
                                       perPass: [Int: ChannelBinding.Binding], passCount: Int,
                                       warnings: inout [ConversionWarning]) -> String {
        let name = texel ? "_ch\(n)_texel" : "_ch\(n)_tex"
        let param = texel ? "ivec2 U" : "vec2 uv"
        var body = ""
        for p in 0..<passCount {
            guard let b = perPass[p] else { continue }
            // A cubemap binding maps to a 2D image (iChannelNimg); the equirect projection only makes
            // sense with a vec3 direction, which we don't have here, so sample the 2D image directly.
            let sample = texel ? "IMG_PIXEL(\(b.glslName), vec2(U))"
                               : "IMG_NORM_PIXEL(\(b.glslName), uv)"
            body += "    if (PASSINDEX == \(p)) { return \(sample); }\n"
        }
        if body.isEmpty {
            warnings.append(ConversionWarning(severity: .warning,
                message: "iChannel\(n) is sampled in the Common tab but no render pass binds it — Common reads return 0. Bind it or supply an input.",
                context: ""))
        }
        return "vec4 \(name)(\(param)) {\n\(body)    return vec4(0.0);\n}"
    }
}
