import AppKit
import Metal
import MetalKit
import QuartzCore
import ISFMSLKit

/// The render-thread half of the Metal preview: owns the ISFMSLScene and every piece of state
/// `draw(in:)` touches, all behind ONE coarse lock. `draw(in:)` arrives on the DisplayLinkDriver
/// thread; scene swaps, input edits, render-size changes, and the pixel gate arrive on the main
/// thread — each takes the same lock, so scene access is strictly serialized. Coarse-over-clever
/// on purpose: a main-thread caller blocks at most one frame's encode (~ms), and unlike the
/// pending-swap idiom this keeps a freshly loaded scene visible to the (main-thread, possibly
/// windowless-and-never-drawing) pixel gate immediately.
///
/// Main-thread-only side effects (publishing errors, stats) leave through `Callbacks`, which the
/// owning MetalPreviewController points back at itself.
final class MetalRenderCore: NSObject, @unchecked Sendable {
    struct Callbacks {
        /// Render-time C++ exception: the core has already dropped the scene; publish on main.
        var renderError: @Sendable (String?) -> Void = { _ in }
        /// A fresh FPS/GPU-ms snapshot, or nil when the loop stops producing shader frames.
        var statsUpdate: @Sendable (RenderStats?) -> Void = { _ in }
    }

    private let device: MTLDevice
    private let renderQueue: MTLCommandQueue
    /// Set once by the controller right after init, before any frame can draw.
    var callbacks = Callbacks()
    /// Router consulted per frame for image-input textures via its nonisolated, lock-protected
    /// `renderSource(for:)`. Weak: the controller owns both.
    weak var imageRouter: SourceRouter?

    private let lock = NSLock()
    // ── lock-guarded state ──
    private var scene: ISFMSLScene?
    private var imageInputNames: [String] = []
    private var renderWidth = 1920   // matches EditorViewModel's 16:9 default
    private var renderHeight = 1080
    private var fitToWindow = true
    private var statsAccumulator = RenderStatsAccumulator()
    private var statsWereLive = false   // avoid republishing nil every clear frame
    private var blitPipeline: MTLRenderPipelineState?
    private var blitPipelineFormat: MTLPixelFormat = .invalid

    init(device: MTLDevice, renderQueue: MTLCommandQueue) {
        self.device = device
        self.renderQueue = renderQueue
    }

    // MARK: main-thread API (each call serializes against the render thread via `lock`)

    /// Install a new compiled scene (or nil on compile failure) + its image-input names.
    func setScene(_ s: ISFMSLScene?, imageInputNames names: [String]) {
        lock.lock(); defer { lock.unlock() }
        scene = s
        imageInputNames = names
    }

    func setRenderSize(width: Int, height: Int, fitToWindow fit: Bool) {
        lock.lock(); defer { lock.unlock() }
        renderWidth = max(width, 1)
        renderHeight = max(height, 1)
        fitToWindow = fit
    }

    /// Run `body` with the current scene while holding the render lock — the render thread cannot
    /// touch the scene until `body` returns. Used for input edits and the (multi-frame) pixel gate.
    func withScene<T>(_ body: (ISFMSLScene?) -> T) -> T {
        lock.lock(); defer { lock.unlock() }
        return body(scene)
    }

    /// Drop the stats window (render loop paused / renderer switched).
    func resetStats() {
        lock.lock(); defer { lock.unlock() }
        statsAccumulator.reset()
        statsWereLive = false
    }

    /// Record one completed command buffer's GPU duration (arrives on a Metal completion thread).
    private func addGPUTime(seconds: Double) {
        lock.lock(); defer { lock.unlock() }
        statsAccumulator.addGPUTime(seconds: seconds)
    }

    /// Offscreen one-frame render at the current target size (test hook; no drawable involved).
    @discardableResult
    func renderOnce(drawableSize: CGSize) -> MTLTexture? {
        lock.lock(); defer { lock.unlock() }
        guard let scene, let cb = renderQueue.makeCommandBuffer() else { return nil }
        let size = targetSizeLocked(drawableSize: drawableSize)
        var err: NSString?
        let tex = ISFMSLSafeRender(scene, NSSize(width: size.width, height: size.height), cb, &err)
        cb.commit()
        return tex
    }

    // MARK: render path (display-link thread; also main via drawOneFrame while paused)

    /// Requires `lock` held.
    private func targetSizeLocked(drawableSize: CGSize) -> MTLSize {
        if fitToWindow {
            // Largest W×H-aspect rectangle that fits the drawable → crisp + aspect-locked.
            return BlitFit.inscribe(aspect: Double(renderWidth) / Double(renderHeight),
                                    in: drawableSize)
        }
        return MTLSize(width: renderWidth, height: renderHeight, depth: 1)
    }

    /// Builds the passthrough display pipeline: a fullscreen quad whose fragment shader samples
    /// the engine output. Sampling converts ANY source pixel format (float16/float32/unorm/sRGB) to
    /// the drawable format and scales to fit, so every shader displays without format juggling.
    private func makeBlitPipeline(colorFormat: MTLPixelFormat) -> MTLRenderPipelineState? {
        let src = """
        #include <metal_stdlib>
        using namespace metal;
        struct VOut { float4 pos [[position]]; float2 uv; };
        // Fullscreen QUAD (triangle-strip, 4 verts) at the ±fit corners. A scaled quad letterboxes
        // cleanly; a scaled fullscreen-triangle would expose its hypotenuse as a diagonal cut.
        vertex VOut tisf_blit_v(uint vid [[vertex_id]], constant float2& fit [[buffer(0)]]) {
            float2 corner = float2(float(vid & 1), float((vid >> 1) & 1)); // (0,0)(1,0)(0,1)(1,1)
            VOut o;
            o.pos = float4((corner * 2.0 - 1.0) * fit, 0.0, 1.0);
            o.uv = float2(corner.x, 1.0 - corner.y);
            return o;
        }
        fragment float4 tisf_blit_f(VOut v [[stage_in]], texture2d<float> tex [[texture(0)]]) {
            constexpr sampler s(filter::linear, address::clamp_to_edge);
            return tex.sample(s, v.uv);
        }
        """
        guard let lib = try? device.makeLibrary(source: src, options: nil) else { return nil }
        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = lib.makeFunction(name: "tisf_blit_v")
        desc.fragmentFunction = lib.makeFunction(name: "tisf_blit_f")
        desc.colorAttachments[0].pixelFormat = colorFormat
        return try? device.makeRenderPipelineState(descriptor: desc)
    }
}

extension MetalRenderCore: MTKViewDelegate {
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        lock.lock(); defer { lock.unlock() }
        guard let drawable = view.currentDrawable else { return }

        // Compile-failure path: clear the drawable to opaque black and present.
        guard let scene else {
            // Black clear frames aren't shader frames — don't report an FPS for them.
            if statsWereLive {
                statsAccumulator.reset()
                statsWereLive = false
                callbacks.statsUpdate(nil)
            }
            guard let rpd = view.currentRenderPassDescriptor,
                  let cb = renderQueue.makeCommandBuffer() else { return }
            rpd.colorAttachments[0].loadAction = .clear
            rpd.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
            let enc = cb.makeRenderCommandEncoder(descriptor: rpd)
            enc?.endEncoding()
            cb.present(drawable)
            cb.commit()
            return
        }

        // Single command buffer: scene render -> blit into drawable -> present -> commit.
        guard let cb = renderQueue.makeCommandBuffer() else { return }
        let size = targetSizeLocked(drawableSize: view.drawableSize)
        // Bind each image input's routed source (rendered into the same command buffer, so the
        // source render is encoded before the filter that reads it).
        for name in imageInputNames {
            if let src = imageRouter?.renderSource(for: name),
               let tex = src.texture(size: size, in: cb),
               let val = ISFMSLSceneVal.create(with: tex) as? ISFMSLSceneVal {
                scene.setValue(val, forInputNamed: name)
            }
        }
        var renderErr: NSString?
        guard let srcTex = ISFMSLSafeRender(
            scene, NSSize(width: size.width, height: size.height), cb, &renderErr) else {
            // Render-time C++ exception (a compiled-but-pathological shader threw mid-render).
            // Invalidate the scene so we stop retrying and surface the error; do NOT commit the
            // possibly-partially-encoded command buffer. Next frame hits the clear-on-fail path.
            self.scene = nil
            callbacks.renderError(renderErr as String?)
            return
        }

        // Display: sample the engine's output texture into the drawable via a passthrough pass.
        // This converts ANY source pixel format (incl. 32-bit float, which CAMetalLayer can't accept
        // as a drawable) and scales to fit — no colorPixelFormat juggling, no cross-format-blit
        // assert, no NSException abort.
        // Rebuild when the view's pixel format changes — a pipeline built for the first format
        // would render through a mismatched attachment description.
        if blitPipeline == nil || blitPipelineFormat != view.colorPixelFormat {
            blitPipeline = makeBlitPipeline(colorFormat: view.colorPixelFormat)
            blitPipelineFormat = view.colorPixelFormat
        }
        guard let pipeline = blitPipeline,
              let rpd = view.currentRenderPassDescriptor else { cb.commit(); return }
        rpd.colorAttachments[0].loadAction = .clear
        rpd.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        // Aspect-fit: letterbox/pillarbox the output texture into the drawable — never stretch.
        var fit = BlitFit.scale(textureSize: size, drawableSize: view.drawableSize)
        if let enc = cb.makeRenderCommandEncoder(descriptor: rpd) {
            enc.setRenderPipelineState(pipeline)
            enc.setVertexBytes(&fit, length: MemoryLayout<SIMD2<Float>>.stride, index: 0)
            enc.setFragmentTexture(srcTex, index: 0)
            enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
            enc.endEncoding()
        }
        cb.present(drawable)
        // GPU frame time: the handler fires on a Metal completion thread; addGPUTime is
        // lock-protected, so no main hop is needed. Must be attached before commit.
        cb.addCompletedHandler { [weak self] buf in
            self?.addGPUTime(seconds: buf.gpuEndTime - buf.gpuStartTime)
        }
        cb.commit()
        if let snapshot = statsAccumulator.frame(at: CACurrentMediaTime()) {
            statsWereLive = true
            callbacks.statsUpdate(snapshot)
        }
    }
}
