import Metal

/// A format-converting full-target copy: samples a source texture into a destination render target.
///
/// Not a blit. `MTLBlitCommandEncoder.copy` requires matching pixel formats, and ISF scenes return
/// whatever format their last pass used (8-bit unorm, 16-bit float, 32-bit float). Sampling
/// converts, so any engine output lands in the instrument's fixed master format.
///
/// Why the instrument needs an owned copy at all: engine output textures come from `VVMTLPool`,
/// which recycles them. Anything that reads a deck texture in a LATER command buffer (the deck
/// monitors) could otherwise sample memory the pool has already handed to another render — the
/// same aliasing bug `ISFSceneSource` fixed with its own owned last-good texture.
final class TextureCopyPass: @unchecked Sendable {
    private let pipeline: MTLRenderPipelineState

    init?(device: MTLDevice, destinationFormat: MTLPixelFormat) {
        let src = """
        #include <metal_stdlib>
        using namespace metal;
        struct VOut { float4 pos [[position]]; float2 uv; };
        vertex VOut ar_copy_v(uint vid [[vertex_id]]) {
            float2 corner = float2(float(vid & 1), float((vid >> 1) & 1));
            VOut o;
            o.pos = float4(corner * 2.0 - 1.0, 0.0, 1.0);
            o.uv = float2(corner.x, 1.0 - corner.y);
            return o;
        }
        fragment float4 ar_copy_f(VOut v [[stage_in]], texture2d<float> tex [[texture(0)]]) {
            constexpr sampler s(filter::linear, address::clamp_to_edge);
            return tex.sample(s, v.uv);
        }
        """
        guard let lib = try? device.makeLibrary(source: src, options: nil) else { return nil }
        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = lib.makeFunction(name: "ar_copy_v")
        desc.fragmentFunction = lib.makeFunction(name: "ar_copy_f")
        desc.colorAttachments[0].pixelFormat = destinationFormat
        guard let p = try? device.makeRenderPipelineState(descriptor: desc) else { return nil }
        pipeline = p
    }

    func encode(from source: MTLTexture, to destination: MTLTexture, in cb: MTLCommandBuffer) {
        let rpd = MTLRenderPassDescriptor()
        rpd.colorAttachments[0].texture = destination
        rpd.colorAttachments[0].loadAction = .dontCare
        rpd.colorAttachments[0].storeAction = .store
        guard let enc = cb.makeRenderCommandEncoder(descriptor: rpd) else { return }
        enc.setRenderPipelineState(pipeline)
        enc.setFragmentTexture(source, index: 0)
        enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        enc.endEncoding()
    }
}
