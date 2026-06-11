import AppKit
import Combine
import Metal
import MetalKit
import ISFMSLKit
import VVMetalKit

@MainActor
final class MetalPreviewController: NSObject, ObservableObject, PreviewEngine {
    @Published private(set) var compileValid = false
    @Published private(set) var compileError: String?
    @Published private(set) var compileErrorLine: Int?
    @Published private(set) var inputs: [ISFPreviewInput] = []

    private let mtkView = MTKView()
    var nsView: NSView { mtkView }
    var compileStateWillChange: ObservableObjectPublisher { objectWillChange }

    let imageSources: SourceRouter

    private let device: MTLDevice
    private let renderQueue: MTLCommandQueue
    private var scene: ISFMSLScene?
    // Target resolution (also the aspect to preserve) + fit mode. See setRenderSize.
    private var renderWidth = 640
    private var renderHeight = 480
    private var fitToWindow = true
    private let transpileQueue = DispatchQueue(label: "isfmsl.transpile", qos: .userInitiated)
    private let tempURL: URL
    private var lastLoadedSource: String?
    /// Passthrough pipeline that displays the engine's output texture (any pixel format) by sampling
    /// it into the drawable. Built lazily on first frame.
    private var blitPipeline: MTLRenderPipelineState?

    override init() {
        let props = RenderProperties.global()
        self.device = props.device
        self.renderQueue = props.renderQueue
        self.imageSources = SourceRouter(device: props.device, queue: props.renderQueue)
        // Global singletons ISFMSLKit needs BEFORE any scene work:
        if VVMTLPool.global == nil { VVMTLPool.global = VVMTLPool(device: props.device) }
        if ISFMSLCache.primary == nil {
            let cacheDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("TrueISFEditor/ISFMSLCache")
            try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
            ISFMSLCache.primary = ISFMSLCache(directoryURL: cacheDir)
        }
        self.tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("trueisf-live-\(UUID().uuidString).fs")
        super.init()
        mtkView.device = props.device
        mtkView.isPaused = false
        mtkView.enableSetNeedsDisplay = false
        mtkView.framebufferOnly = false
        mtkView.delegate = self
    }

    func load(isf: String) {
        lastLoadedSource = isf
        // Invalidate prior compile state synchronously: a new source is transpiling, so the
        // previous shader's validity no longer applies (also clears stale state between loads).
        compileValid = false
        compileError = nil
        compileErrorLine = nil
        let url = tempURL
        let device = self.device
        transpileQueue.async { [weak self] in
            guard let self else { return }
            do { try isf.write(to: url, atomically: true, encoding: .utf8) } catch { return }
            // Crash-safe: ISFMSLSafeCreateAndLoad wraps scene create/load/error-read in a C++
            // try/catch, so a pathological shader (e.g. one that makes the transpiler throw an
            // uncaught nlohmann::json exception) reports a failure instead of terminating the app.
            var compileError: ObjCBool = false
            var message: NSString?
            let s = ISFMSLSafeCreateAndLoad(device, url, &compileError, &message)
            let hadError = compileError.boolValue || (s == nil)
            let msg = message as String?
            Task { @MainActor in self.applyCompile(scene: s, hadError: hadError, message: msg) }
        }
    }

    private func applyCompile(scene s: ISFMSLScene?, hadError: Bool, message: String?) {
        if let s, !hadError {
            scene = s
            compileValid = true
            compileError = nil
            compileErrorLine = nil
            inputs = Self.mapInputs(s.inputs)
            imageSources.updateInputs(inputs)
        } else {
            scene = nil
            compileValid = false
            compileError = (message?.isEmpty == false ? message : "Shader failed to compile.")
            compileErrorLine = Self.parseLine(from: message)
            CrashLog.shared.record(CrashEvent(kind: .compile,
                message: compileError ?? "compile error",
                context: Self.shaderName(from: lastLoadedSource)))
            imageSources.updateInputs(inputs)
        }
    }

    static func mapInputs(_ attribs: [any ISFMSLSceneAttrib]) -> [ISFPreviewInput] {
        attribs.compactMap { attrib in
            let typeStr: String
            switch attrib.type {
            case .event:   typeStr = "event"
            case .bool:    typeStr = "bool"
            case .long:    typeStr = "long"
            case .float:   typeStr = "float"
            case .point2D: typeStr = "point2D"
            case .color:   typeStr = "color"
            case .image:   typeStr = "image"
            default:       return nil   // audio/cube: still unsupported
            }

            // Read default/min/max via doubleValue — works for all scalar types.
            // For point2D and color, store as [Double] so controls can read them.
            let defaultValue: Any?
            let minVal: Any?
            let maxVal: Any?

            switch attrib.type {
            case .color:
                let d = attrib.defaultVal
                defaultValue = [d.colorValue(by: 0), d.colorValue(by: 1),
                                d.colorValue(by: 2), d.colorValue(by: 3)]
                minVal = nil; maxVal = nil
            case .point2D:
                let d = attrib.defaultVal
                defaultValue = [d.pointValue(by: 0), d.pointValue(by: 1)]
                let mn = attrib.minVal
                minVal = [mn.pointValue(by: 0), mn.pointValue(by: 1)]
                let mx = attrib.maxVal
                maxVal = [mx.pointValue(by: 0), mx.pointValue(by: 1)]
            case .bool:
                defaultValue = attrib.defaultVal.boolValue
                minVal = nil; maxVal = nil
            case .event:
                defaultValue = nil; minVal = nil; maxVal = nil
            case .image:
                defaultValue = nil; minVal = nil; maxVal = nil
            default:
                defaultValue = attrib.defaultVal.doubleValue
                minVal = attrib.minVal.doubleValue
                maxVal = attrib.maxVal.doubleValue
            }

            let labels: [String]? = attrib.labelArray.isEmpty ? nil : attrib.labelArray
            let values: [Double]? = attrib.valArray.isEmpty ? nil
                : attrib.valArray.map { $0.doubleValue }

            return ISFPreviewInput(name: attrib.name, type: typeStr,
                                   defaultValue: defaultValue,
                                   min: minVal, max: maxVal,
                                   labels: labels, values: values)
        }
    }

    static func parseLine(from msg: String?) -> Int? {
        guard let msg else { return nil }
        // glslang format: "ERROR: 0:NN:"
        if let r = msg.range(of: #"0:(\d+):"#, options: .regularExpression) {
            let digits = msg[r].dropFirst(2).dropLast()
            return Int(digits)
        }
        return nil
    }

    /// Pull the ISF header's DESCRIPTION for crash-log context, if present.
    static func shaderName(from source: String?) -> String? {
        guard let source,
              let open = source.range(of: "/*{"),
              let close = source.range(of: "}*/") else { return nil }
        let json = "{" + source[open.upperBound..<close.lowerBound] + "}"
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return obj["DESCRIPTION"] as? String
    }

    func setInput(_ name: String, _ jsonValue: String) {
        guard let scene else { return }
        // Parse the JSON fragment (bool/number/array).
        guard let data = jsonValue.data(using: .utf8),
              let raw = try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed) else { return }
        var val: ISFMSLSceneVal? = nil
        if let b = raw as? Bool {
            val = ISFMSLSceneVal.create(with: b) as? ISFMSLSceneVal
        } else if let arr = raw as? [Any] {
            let doubles = arr.compactMap { ($0 as? NSNumber)?.doubleValue }
            if doubles.count == 2 {
                val = ISFMSLSceneVal.create(withPoint2D: NSPoint(x: doubles[0], y: doubles[1])) as? ISFMSLSceneVal
            } else if doubles.count >= 4 {
                val = ISFMSLSceneVal.create(with: NSColor(red: doubles[0], green: doubles[1],
                                                          blue: doubles[2], alpha: doubles[3])) as? ISFMSLSceneVal
            }
        } else if let n = raw as? NSNumber {
            // Distinguish integer vs floating-point NSNumber.
            if CFNumberIsFloatType(n as CFNumber) {
                val = ISFMSLSceneVal.create(withFloat: n.doubleValue) as? ISFMSLSceneVal
            } else {
                val = ISFMSLSceneVal.create(withLong: n.int32Value) as? ISFMSLSceneVal
            }
        }
        if let val {
            scene.setValue(val, forInputNamed: name)
        }
    }
    func setRenderSize(width: Int, height: Int, fitToWindow: Bool) {
        renderWidth = max(width, 1)
        renderHeight = max(height, 1)
        self.fitToWindow = fitToWindow
    }

    private func targetSize() -> MTLSize {
        if fitToWindow {
            // Largest W×H-aspect rectangle that fits the drawable → crisp + aspect-locked.
            return BlitFit.inscribe(aspect: Double(renderWidth) / Double(renderHeight),
                                    in: mtkView.drawableSize)
        }
        return MTLSize(width: renderWidth, height: renderHeight, depth: 1)
    }

    /// Builds the passthrough display pipeline: a fullscreen triangle whose fragment shader samples
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

    /// Test hook: render one frame into an offscreen texture and return it. No drawable involved.
    @discardableResult
    func renderOnce() -> MTLTexture? {
        guard let scene = scene, let cb = renderQueue.makeCommandBuffer() else { return nil }
        let size = targetSize()
        var err: NSString?
        let tex = ISFMSLSafeRender(scene, NSSize(width: size.width, height: size.height), cb, &err)
        cb.commit()
        return tex
    }
}

extension MetalPreviewController: MTKViewDelegate {
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable else { return }

        // Compile-failure path: clear the drawable to opaque black and present.
        guard let scene = scene else {
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
        let size = targetSize()
        // Bind each image input's routed source (rendered into the same command buffer, so the
        // source render is encoded before the filter that reads it).
        for input in inputs where input.type == "image" {
            let src = imageSources.source(for: input.name)
            if let tex = src.texture(size: size, in: cb),
               let val = ISFMSLSceneVal.create(with: tex) as? ISFMSLSceneVal {
                scene.setValue(val, forInputNamed: input.name)
            }
        }
        var renderErr: NSString?
        guard let srcTex = ISFMSLSafeRender(
            scene, NSSize(width: size.width, height: size.height), cb, &renderErr) else {
            // Render-time C++ exception (a compiled-but-pathological shader threw mid-render).
            // Invalidate the scene so we stop retrying and surface the error; do NOT commit the
            // possibly-partially-encoded command buffer. Next frame hits the clear-on-fail path.
            self.scene = nil
            self.compileValid = false
            self.compileError = (renderErr as String?) ?? "Render error."
            CrashLog.shared.record(CrashEvent(kind: .render,
                message: (renderErr as String?) ?? "render error",
                context: Self.shaderName(from: lastLoadedSource)))
            return
        }

        // Display: sample the engine's output texture into the drawable via a passthrough pass.
        // This converts ANY source pixel format (incl. 32-bit float, which CAMetalLayer can't accept
        // as a drawable) and scales to fit — no colorPixelFormat juggling, no cross-format-blit
        // assert, no NSException abort.
        if blitPipeline == nil { blitPipeline = makeBlitPipeline(colorFormat: view.colorPixelFormat) }
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
        cb.commit()
    }
}
