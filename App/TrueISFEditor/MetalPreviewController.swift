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

    private let device: MTLDevice
    private let renderQueue: MTLCommandQueue
    private var scene: ISFMSLScene?
    private var renderSize: MTLSize?
    private let transpileQueue = DispatchQueue(label: "isfmsl.transpile", qos: .userInitiated)
    private let tempURL: URL

    override init() {
        let props = RenderProperties.global()
        self.device = props.device
        self.renderQueue = props.renderQueue
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
        let url = tempURL
        let device = self.device
        transpileQueue.async { [weak self] in
            guard let self else { return }
            do { try isf.write(to: url, atomically: true, encoding: .utf8) } catch { return }
            guard let s = ISFMSLScene(device: device) else { return }
            s.load(url)
            let hadError = s.compilerError
            // If error, capture detail off-main too (building the transpiler error can be slow).
            var msg: String? = nil
            if hadError {
                let te = ISFMSLTranspilerError(url: url, device: device)
                msg = te.fragGLSLErrString ?? te.fragSPIRVErrString ?? te.fragMSLErrString
                    ?? te.vertGLSLErrString ?? te.generateStringForLogFile()
            }
            Task { @MainActor in self.applyCompile(scene: s, hadError: hadError, message: msg) }
        }
    }

    private func applyCompile(scene s: ISFMSLScene, hadError: Bool, message: String?) {
        if hadError {
            scene = nil
            compileValid = false
            compileError = (message?.isEmpty == false ? message : "Shader failed to compile.")
            compileErrorLine = Self.parseLine(from: message)
        } else {
            scene = s
            compileValid = true
            compileError = nil
            compileErrorLine = nil
            inputs = Self.mapInputs(s.inputs)
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
            default:       return nil   // image/audio/cube: unsupported in P1.5 controls
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
    func setRenderSize(width: Int?, height: Int?) {
        if let w = width, let h = height, w > 0, h > 0 {
            renderSize = MTLSize(width: w, height: h, depth: 1)
        } else {
            renderSize = nil
        }
    }

    private func targetSize() -> MTLSize {
        if let r = renderSize { return r }
        let s = mtkView.drawableSize
        return MTLSize(width: max(Int(s.width), 1), height: max(Int(s.height), 1), depth: 1)
    }

    /// Test hook: render one frame into an offscreen texture and return it. No drawable involved.
    @discardableResult
    func renderOnce() -> MTLTexture? {
        guard let scene = scene, let cb = renderQueue.makeCommandBuffer() else { return nil }
        let size = targetSize()
        let img = scene.createAndRender(
            toTextureSized: NSSize(width: size.width, height: size.height), in: cb)
        cb.commit()
        return img.texture
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
        let img = scene.createAndRender(
            toTextureSized: NSSize(width: size.width, height: size.height), in: cb)
        let srcTex = img.texture

        let dstTex = drawable.texture
        // 1:1 blit of the overlapping region (clamp to the min extent of both textures).
        let w = min(srcTex.width, dstTex.width)
        let h = min(srcTex.height, dstTex.height)
        if let blit = cb.makeBlitCommandEncoder() {
            blit.copy(
                from: srcTex,
                sourceSlice: 0, sourceLevel: 0,
                sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                sourceSize: MTLSize(width: w, height: h, depth: 1),
                to: dstTex,
                destinationSlice: 0, destinationLevel: 0,
                destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0))
            blit.endEncoding()
        }
        cb.present(drawable)
        cb.commit()
    }
}
