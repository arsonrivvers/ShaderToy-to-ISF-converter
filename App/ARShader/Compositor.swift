import Metal
import simd

/// Blends one layer onto a backdrop and writes the result to a destination texture.
///
/// Hand-written Metal, not an ISF filter (spec §7): the mixer is load-bearing, and an ISF mixer
/// that failed to compile would leave the instrument with no output at all. A compiled Metal
/// pipeline cannot fail at shader-load time.
///
/// Reads the backdrop as a TEXTURE and writes to a separate destination rather than using
/// framebuffer fetch. Fixed-function Metal blending cannot express multiply/overlay/soft-light —
/// those need the backdrop value in the fragment shader — and programmable blending
/// (`[[color(0)]]` fragment input) is an Apple-GPU feature. Ping-pong is universal.
///
/// The MSL below is a transcription of `BlendMath`. `CompositorTests` asserts the two agree for
/// every mode at three opacities; change one without the other and that test fails.
final class Compositor: @unchecked Sendable {
    private let pipeline: MTLRenderPipelineState

    /// Must match the `blendMode` case order pinned by `BlendMathTests`.
    private struct Uniforms {
        var opacity: Float
        var mode: Int32
    }

    init?(device: MTLDevice) {
        guard let lib = try? device.makeLibrary(source: Self.shaderSource, options: nil) else {
            return nil
        }
        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = lib.makeFunction(name: "ar_composite_v")
        desc.fragmentFunction = lib.makeFunction(name: "ar_composite_f")
        desc.colorAttachments[0].pixelFormat = InstrumentRenderer.masterFormat
        guard let p = try? device.makeRenderPipelineState(descriptor: desc) else { return nil }
        pipeline = p
    }

    /// Encode one layer. `backdrop` and `destination` must be different textures — a render target
    /// cannot also be sampled in the same pass.
    func encodeLayer(source: MTLTexture,
                     backdrop: MTLTexture,
                     destination: MTLTexture,
                     opacity: Double,
                     mode: BlendMode,
                     in cb: MTLCommandBuffer) {
        let rpd = MTLRenderPassDescriptor()
        rpd.colorAttachments[0].texture = destination
        rpd.colorAttachments[0].loadAction = .dontCare   // every pixel is written
        rpd.colorAttachments[0].storeAction = .store
        guard let enc = cb.makeRenderCommandEncoder(descriptor: rpd) else { return }
        var uniforms = Uniforms(opacity: Float(min(max(opacity, 0), 1)), mode: mode.shaderIndex)
        enc.setRenderPipelineState(pipeline)
        enc.setFragmentTexture(source, index: 0)
        enc.setFragmentTexture(backdrop, index: 1)
        enc.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
        enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        enc.endEncoding()
    }

    private static let shaderSource = """
    #include <metal_stdlib>
    using namespace metal;

    struct VOut { float4 pos [[position]]; float2 uv; };

    struct Uniforms { float opacity; int mode; };

    vertex VOut ar_composite_v(uint vid [[vertex_id]]) {
        float2 corner = float2(float(vid & 1), float((vid >> 1) & 1));
        VOut o;
        o.pos = float4(corner * 2.0 - 1.0, 0.0, 1.0);
        o.uv = float2(corner.x, 1.0 - corner.y);
        return o;
    }

    // W3C Compositing and Blending Level 1, separable blend modes.
    // Transcribed from BlendMath.swift. Per-channel; callers pass float3.

    inline float3 b_multiply(float3 cb, float3 cs) { return cb * cs; }
    inline float3 b_screen(float3 cb, float3 cs)   { return cb + cs - cb * cs; }

    inline float3 b_hardlight(float3 cb, float3 cs) {
        float3 lo = b_multiply(cb, 2.0 * cs);
        float3 hi = b_screen(cb, 2.0 * cs - 1.0);
        return select(hi, lo, cs <= 0.5);
    }

    // Special cases are applied AFTER the general formula so they overwrite it, and cb == 0 is
    // applied LAST because W3C evaluates the backdrop test first.
    inline float3 b_colordodge(float3 cb, float3 cs) {
        float3 r = min(float3(1.0), cb / max(1.0 - cs, 1e-7));
        r = select(r, float3(1.0), cs >= 1.0);
        r = select(r, float3(0.0), cb <= 0.0);
        return r;
    }

    inline float3 b_colorburn(float3 cb, float3 cs) {
        float3 r = 1.0 - min(float3(1.0), (1.0 - cb) / max(cs, 1e-7));
        r = select(r, float3(0.0), cs <= 0.0);
        r = select(r, float3(1.0), cb >= 1.0);
        return r;
    }

    inline float3 b_softlight(float3 cb, float3 cs) {
        float3 d = select(sqrt(cb), ((16.0 * cb - 12.0) * cb + 4.0) * cb, cb <= 0.25);
        float3 lo = cb - (1.0 - 2.0 * cs) * cb * (1.0 - cb);
        float3 hi = cb + (2.0 * cs - 1.0) * (d - cb);
        return select(hi, lo, cs <= 0.5);
    }

    inline float3 apply_blend(int mode, float3 cb, float3 cs) {
        switch (mode) {
            case 0:  return cs;                                  // normal
            case 1:  return b_multiply(cb, cs);                  // multiply
            case 2:  return b_screen(cb, cs);                    // screen
            case 3:  return b_hardlight(cs, cb);                 // overlay (args swapped)
            case 4:  return min(cb, cs);                         // darken
            case 5:  return max(cb, cs);                         // lighten
            case 6:  return b_colordodge(cb, cs);                // colorDodge
            case 7:  return b_colorburn(cb, cs);                 // colorBurn
            case 8:  return b_hardlight(cb, cs);                 // hardLight
            case 9:  return b_softlight(cb, cs);                 // softLight
            case 10: return abs(cb - cs);                        // difference
            case 11: return cb + cs - 2.0 * cb * cs;             // exclusion
            default: return cs;
        }
    }

    fragment float4 ar_composite_f(VOut v [[stage_in]],
                                   texture2d<float> srcTex [[texture(0)]],
                                   texture2d<float> backTex [[texture(1)]],
                                   constant Uniforms& u [[buffer(0)]]) {
        constexpr sampler s(filter::linear, address::clamp_to_edge);
        float4 src = srcTex.sample(s, v.uv);
        float3 cb = backTex.sample(s, v.uv).rgb;
        // Layer alpha = the source pixel's own alpha times the layer's effective opacity.
        float a = clamp(src.a * u.opacity, 0.0, 1.0);
        float3 blended = apply_blend(u.mode, clamp(cb, 0.0, 1.0), clamp(src.rgb, 0.0, 1.0));
        // Source-over onto an OPAQUE backdrop: Co = (1 - a)*Cb + a*B(Cb, Cs).
        float3 co = mix(cb, blended, a);
        // The master is opaque by contract. Never propagate a layer's alpha into it.
        return float4(co, 1.0);
    }
    """
}
