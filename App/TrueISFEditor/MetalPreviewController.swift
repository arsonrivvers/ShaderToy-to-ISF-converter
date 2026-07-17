import AppKit
import Combine
import Metal
import MetalKit
import QuartzCore
import ISFMSLKit
import VVMetalKit

@MainActor
final class MetalPreviewController: NSObject, ObservableObject, PreviewEngine {
    @Published private(set) var compileValid = false
    @Published private(set) var compileError: String?
    @Published private(set) var compileErrorLine: Int?
    @Published private(set) var inputs: [ISFPreviewInput] = []

    /// Live FPS / GPU-ms readout (Task 1.6). Snapshots publish ~2×/sec from the render core.
    /// Stored as concrete + witnessed as optional: the protocol wants `RenderStatsModel?`, and a
    /// same-name non-optional stored property would NOT witness it — protocol dispatch would fall
    /// through to the extension default (nil) and the readout would silently never appear.
    private let statsModel = RenderStatsModel()
    var liveRenderStats: RenderStatsModel? { statsModel }

    private let mtkView = HostAwareMTKView()
    var nsView: NSView { mtkView }
    var compileStateWillChange: ObservableObjectPublisher { objectWillChange }

    let imageSources: SourceRouter

    private let device: MTLDevice
    private let renderQueue: MTLCommandQueue
    /// Owns the scene + everything `draw(in:)` touches; the MTKView's delegate. All scene access
    /// (frames on the display-link thread, edits/gates on main) serializes through its lock.
    private let core: MetalRenderCore
    /// Drives `mtkView.draw()` off the main thread (the OffspringEngine pattern) so SwiftUI/AppKit
    /// layout during slider drags can't starve the render loop. Nil ⇒ CVDisplayLink creation
    /// failed and the view self-drives on main (functional fallback, with the known drag-lag).
    private var displayDriver: DisplayLinkDriver?
    private let transpileQueue = DispatchQueue(label: "isfmsl.transpile", qos: .userInitiated)
    private let tempURL: URL
    private var lastLoadedSource: String?

    override init() {
        let props = RenderProperties.global()
        self.device = props.device
        self.renderQueue = props.renderQueue
        self.imageSources = SourceRouter(device: props.device, queue: props.renderQueue)
        self.core = MetalRenderCore(device: props.device, renderQueue: props.renderQueue)
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
        core.imageRouter = imageSources
        core.callbacks = MetalRenderCore.Callbacks(
            renderError: { [weak self] message in
                Task { @MainActor in self?.handleRenderError(message) }
            },
            statsUpdate: { [weak self] snapshot in
                Task { @MainActor in self?.statsModel.stats = snapshot }
            })
        mtkView.device = props.device
        mtkView.enableSetNeedsDisplay = false
        mtkView.framebufferOnly = false
        mtkView.delegate = core
        // Off-main render loop: the view never self-drives; the display link calls mtkView.draw()
        // on its own thread. If link creation fails, fall back to the classic main-thread loop.
        displayDriver = DisplayLinkDriver(view: mtkView)
        mtkView.isPaused = (displayDriver != nil)
        // The link runs ONLY while the view sits in a window (and isn't user-paused). Starting it
        // at init let the link thread call view.draw() on an unhosted view during app launch —
        // off-main AppKit layer setup that intermittently deadlocked startup (caught as the test
        // host hanging "before establishing connection"). Windowless controllers (import pixel
        // gate, tests) now never tick at all.
        mtkView.onWindowChange = { [weak self] _ in self?.updateDriverRunning() }
        observeOcclusion()   // B4: pause the loop while minimized/covered
    }

    /// Single decision point for whether the render loop runs: in a window, not user-paused, and
    /// (B4) not occluded — a minimized/covered window was burning GPU at full display cadence.
    /// Called on window membership changes, occlusion changes, and setPaused. Fallback (no link):
    /// the MTKView self-drives on main and manages window visibility itself, so only user-pause
    /// applies.
    private func updateDriverRunning() {
        guard let displayDriver else {
            mtkView.isPaused = userPaused
            return
        }
        let occluded = mtkView.window.map { !$0.occlusionState.contains(.visible) } ?? false
        let shouldRun = !userPaused && mtkView.window != nil && !occluded
        shouldRun ? displayDriver.start() : displayDriver.pause()
    }
    private var userPaused = false

    /// B4: re-evaluate the render loop when OUR window's occlusion changes (minimize/cover/expose).
    private var occlusionObserver: NSObjectProtocol?
    private func observeOcclusion() {
        occlusionObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeOcclusionStateNotification, object: nil, queue: .main
        ) { [weak self] note in
            MainActor.assumeIsolated {
                guard let self, let w = note.object as? NSWindow, w === self.mtkView.window else { return }
                self.updateDriverRunning()
            }
        }
    }

    deinit {
        displayDriver?.invalidate()   // stop the link thread + release its self-retain
        // Block-based observers are NOT auto-removed; remix thumbnails create a controller each,
        // so leaking one observer per instance would accumulate in NotificationCenter forever.
        if let o = occlusionObserver { NotificationCenter.default.removeObserver(o) }
        try? FileManager.default.removeItem(at: tempURL)
    }

    /// Render-thread render failure, marshalled to main by the core callback: publish the error
    /// and log it. The core has already dropped the scene (next frame clears to black).
    private func handleRenderError(_ message: String?) {
        compileValid = false
        compileError = message?.isEmpty == false ? message : "Render error."
        CrashLog.shared.record(CrashEvent(kind: .render,
            message: message?.isEmpty == false ? message! : "render error",
            context: Self.shaderName(from: lastLoadedSource)))
    }

    /// B1c: fired after a successful compile installs a fresh scene (which boots at header
    /// defaults) — the ParamStore's replay hook.
    var onSceneInstalled: (() -> Void)?

    /// Monotonic load counter: a compile finishing for anything but the CURRENT generation is a
    /// superseded source and must be dropped, not published (its scene/inputs/diagnostics would
    /// briefly show as the new shader's).
    private var loadGeneration = 0

    func load(isf: String) {
        lastLoadedSource = isf
        loadGeneration += 1
        let generation = loadGeneration
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
            Task { @MainActor in
                self.applyCompile(scene: s, hadError: hadError, message: msg, generation: generation)
            }
        }
    }

    private func applyCompile(scene s: ISFMSLScene?, hadError: Bool, message: String?,
                              generation: Int) {
        guard generation == loadGeneration else { return }   // superseded by a newer load()
        if let s, !hadError {
            compileValid = true
            compileError = nil
            compileErrorLine = nil
            inputs = Self.mapInputs(s.inputs)
            imageSources.updateInputs(inputs)
            core.setScene(s, imageInputNames: inputs.filter { $0.type == "image" }.map(\.name))
            // B4 NOTE: VVMTLPool.global.housekeeping() was tried here and on setRenderSize to stop
            // the pool's memory ratchet, but trimming the SHARED pool while other live controllers'
            // render threads hold in-flight pooled textures crashed the full test suite (and would
            // crash production: inline + pop-out + nested-ISF sources render concurrently). Pool
            // housekeeping needs a globally-quiescent hook — deferred; see ROADMAP B4.
            // B1c: a fresh scene boots at header defaults — let the ParamStore replay user values.
            onSceneInstalled?()
        } else {
            core.setScene(nil, imageInputNames: inputs.filter { $0.type == "image" }.map(\.name))
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
            // Field-proven ISFMSLScene semantics (OffspringEngine): setValue while the render
            // thread draws the same scene is safe; the lock here only guards the scene REFERENCE
            // against a concurrent swap, and is held for just the setValue call.
            core.withScene { $0?.setValue(val, forInputNamed: name) }
        }
    }
    func setRenderSize(width: Int, height: Int, fitToWindow: Bool) {
        core.setRenderSize(width: width, height: height, fitToWindow: fitToWindow)
    }

    /// M34 override: ISFMSL event values are momentary by design (OffspringEngine precedent) —
    /// one setValue latches until the next rendered frame consumes it, so a pulse can no longer
    /// fall between frames the way the JSON true-then-false default could.
    func pulseEvent(_ name: String) {
        core.withScene { $0?.setValue(ISFMSLSceneVal.createWithEvent(), forInputNamed: name) }
    }

    /// B2: restart shader time at 0. Called on document switches (a new document gets fresh time);
    /// recompiles of the SAME document keep the clock running — that's the point.
    func resetTimeline() {
        core.resetClock()
    }

    /// Pause/resume the live render loop. Pausing stops the display-link ticks entirely (or, in
    /// the no-link fallback, the MTKView's own loop), so this is what actually halts GPU work for
    /// off-screen-cap previews — `renderOnce()` alone never stopped the continuous loop.
    func setPaused(_ paused: Bool) {
        userPaused = paused
        updateDriverRunning()
        core.setClockPaused(paused)   // B2: pausing the loop also freezes TIME
        if paused {
            // A paused loop stops producing frames; a stale readout would report the old rate.
            core.resetStats()
            statsModel.stats = nil
        }
    }

    /// Force one on-screen frame through the normal `draw(in:)` path. Used to show a single frozen
    /// frame on a paused preview (e.g. after its shader finishes compiling) without resuming the
    /// loop. Only valid while paused — the core's lock serializes the draw itself, but concurrent
    /// `MTKView.draw()` from two threads is not a supported MTKView pattern.
    func drawOneFrame() {
        mtkView.draw()
    }

    /// Test hook: render one frame into an offscreen texture and return it. No drawable involved.
    @discardableResult
    func renderOnce() -> MTLTexture? {
        core.renderOnce(drawableSize: mtkView.drawableSize)
    }

    /// Pixel-truth render gate: renders `times.count` frames offscreen at explicit times on the
    /// current scene and analyzes the pixels. Frames render sequentially on the SAME scene so
    /// persistent/feedback buffers accumulate — multipass shaders warm up honestly. Synchronous
    /// (~ms for 3 small frames); callers are the headless corpus harness and the post-import hook.
    /// See docs/superpowers/specs/2026-07-09-pixel-truth-render-gate-design.md.
    func runPixelGate(size: CGSize = CGSize(width: 320, height: 180),
                      times: [Double] = [0.0, 0.5, 1.5]) -> PixelVerdict {
        // The whole gate runs inside withScene: the render lock is held across all probe frames,
        // so the display-link thread can't interleave live frames (which would advance persistent
        // buffers between probes) or swap the scene mid-gate. ~ms for 3 small frames.
        core.withScene { scene in
            guard let scene else { return .renderError }
            // Bind the deterministic pattern to every image input (offscreen renders bind nothing,
            // so texture-sampling shaders would false-fail as black).
            if inputs.contains(where: { $0.type == "image" }) {
                guard let pattern = GateInputPattern.makeTexture(device: device) else {
                    return .renderError   // don't silently render unbound
                }
                for input in inputs where input.type == "image" {
                    if let val = ISFMSLSceneVal.create(with: pattern) as? ISFMSLSceneVal {
                        scene.setValue(val, forInputNamed: input.name)
                    }
                }
            }
            var frames: [FramePixelStats?] = []
            for t in times {
                guard let cb = renderQueue.makeCommandBuffer() else { return .renderError }
                var err: NSString?
                guard let tex = ISFMSLSafeRenderAtTime(
                    scene, NSSize(width: size.width, height: size.height), t, cb, &err) else {
                    return .renderError
                }
                guard FramePixelStats.supports(tex.pixelFormat) else {
                    cb.commit()
                    return .unsupported
                }
                // Blit into a CPU-readable copy — pool textures aren't guaranteed CPU-accessible.
                let desc = MTLTextureDescriptor.texture2DDescriptor(
                    pixelFormat: tex.pixelFormat, width: tex.width, height: tex.height, mipmapped: false)
                desc.storageMode = .managed
                guard let readback = device.makeTexture(descriptor: desc),
                      let blit = cb.makeBlitCommandEncoder() else {
                    cb.commit()
                    return .renderError
                }
                blit.copy(from: tex, to: readback)
                blit.synchronize(resource: readback)
                blit.endEncoding()
                cb.commit()
                cb.waitUntilCompleted()
                frames.append(FramePixelStats.analyze(texture: readback))
            }
            return PixelGate.verdict(frames)
        }
    }
}

/// MTKView that reports window membership to its owner. The display link must run only while the
/// view is actually hosted — ticking an unhosted view did off-main AppKit layer setup at launch.
final class HostAwareMTKView: MTKView {
    /// Called on the main thread whenever the view enters (true) or leaves (false) a window.
    var onWindowChange: ((Bool) -> Void)?
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        onWindowChange?(window != nil)
    }
}
