import SwiftUI
import MetalKit

/// Presents a source texture, aspect-fit, with an opaque-black clear behind it.
///
/// `sourceTexture` returning nil is the blackout / no-output path and MUST render black — never a
/// stale frame. That property is what makes blackout structurally independent of the compositor.
class TexturePresentingView: MTKView, MTKViewDelegate {
    /// Pulled once per draw. Nil ⇒ present opaque black.
    var sourceTexture: (() -> MTLTexture?)?
    /// Called at the top of every draw, before the source texture is pulled. The program view uses
    /// it to render the instrument's frame; monitors leave it nil.
    var onWillDraw: (() -> Void)?

    private var pipeline: MTLRenderPipelineState?
    private var pipelineFormat: MTLPixelFormat = .invalid
    private let presentQueue: MTLCommandQueue

    init(device: MTLDevice, queue: MTLCommandQueue) {
        self.presentQueue = queue
        super.init(frame: .zero, device: device)
        self.delegate = self
        self.enableSetNeedsDisplay = false
        self.framebufferOnly = false
        self.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
    }

    required init(coder: NSCoder) { fatalError("not supported") }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        onWillDraw?()
        guard let device = view.device,
              let drawable = view.currentDrawable,
              let rpd = view.currentRenderPassDescriptor,
              let cb = presentQueue.makeCommandBuffer() else { return }
        rpd.colorAttachments[0].loadAction = .clear
        rpd.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)

        // Rebuild if the drawable format changed; a pipeline built for the old format would render
        // through a mismatched attachment description.
        if pipeline == nil || pipelineFormat != view.colorPixelFormat {
            pipeline = Self.makePipeline(device: device, colorFormat: view.colorPixelFormat)
            pipelineFormat = view.colorPixelFormat
        }

        // Nil source, or no pipeline: the clear alone IS the frame. Opaque black, always.
        guard let tex = sourceTexture?(), let pipeline else {
            cb.makeRenderCommandEncoder(descriptor: rpd)?.endEncoding()
            cb.present(drawable)
            cb.commit()
            return
        }

        var fit = BlitFit.scale(
            textureSize: MTLSize(width: tex.width, height: tex.height, depth: 1),
            drawableSize: view.drawableSize)
        if let enc = cb.makeRenderCommandEncoder(descriptor: rpd) {
            enc.setRenderPipelineState(pipeline)
            enc.setVertexBytes(&fit, length: MemoryLayout<SIMD2<Float>>.stride, index: 0)
            enc.setFragmentTexture(tex, index: 0)
            enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
            enc.endEncoding()
        }
        cb.present(drawable)
        cb.commit()
    }

    /// Fullscreen quad at the ±fit corners. A quad (not a fullscreen triangle) so letterboxing
    /// cannot expose a hypotenuse as a diagonal cut.
    private static func makePipeline(device: MTLDevice,
                                     colorFormat: MTLPixelFormat) -> MTLRenderPipelineState? {
        let src = """
        #include <metal_stdlib>
        using namespace metal;
        struct VOut { float4 pos [[position]]; float2 uv; };
        vertex VOut ar_present_v(uint vid [[vertex_id]], constant float2& fit [[buffer(0)]]) {
            float2 corner = float2(float(vid & 1), float((vid >> 1) & 1));
            VOut o;
            o.pos = float4((corner * 2.0 - 1.0) * fit, 0.0, 1.0);
            o.uv = float2(corner.x, 1.0 - corner.y);
            return o;
        }
        fragment float4 ar_present_f(VOut v [[stage_in]], texture2d<float> tex [[texture(0)]]) {
            constexpr sampler s(filter::linear, address::clamp_to_edge);
            return float4(tex.sample(s, v.uv).rgb, 1.0);
        }
        """
        guard let lib = try? device.makeLibrary(source: src, options: nil) else { return nil }
        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = lib.makeFunction(name: "ar_present_v")
        desc.fragmentFunction = lib.makeFunction(name: "ar_present_f")
        desc.colorAttachments[0].pixelFormat = colorFormat
        return try? device.makeRenderPipelineState(descriptor: desc)
    }
}

/// SwiftUI host for the program output. Owns the clock attachment: the display link starts when
/// this view is in a window and drives the whole instrument.
struct ProgramOutputView: NSViewRepresentable {
    let instrument: Instrument

    func makeNSView(context: Context) -> TexturePresentingView {
        let view = TexturePresentingView(device: instrument.device, queue: instrument.queue)
        let renderer = instrument.renderer
        // These closures run on the CVDisplayLink thread. `InstrumentRenderer` is lock-guarded and
        // NOT main-actor precisely so they can — do not wrap them in `MainActor.assumeIsolated`,
        // which is a runtime assertion and traps off-main.
        //
        // The display link calls view.draw() once per tick. Producing the frame here — before the
        // present pass samples anything — is what makes ONE tick equal ONE instrument frame.
        view.onWillDraw = { renderer.renderFrame() }
        view.sourceTexture = { renderer.programTexture() }
        view.preferredFramesPerSecond = 60
        Task { @MainActor in renderer.attachClock(to: view) }
        return view
    }

    func updateNSView(_ nsView: TexturePresentingView, context: Context) {}
}
