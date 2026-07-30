import Foundation
import AppKit
import Metal
import Combine
import ISFMSLKit

/// One hosted ISF shader: the compiled scene, its parameter values, its image-input routing, and
/// its compile state. Shared by `Deck` and `FXStage` — a deck is a unit with an owned output
/// texture and a layer position; an FX stage is a unit with a mix and a blend mode.
///
/// **Compile first, swap only on success.** A failed compile leaves the running shader playing and
/// reports the error. This is the opposite of the editor's behavior (which drops the scene so the
/// author sees their mistake) and it is deliberate: on stage, the shader that is already up is the
/// one thing you cannot afford to lose. Ported from Phase A rather than rediscovered.
///
/// `@MainActor` covers the `@Published` UI state ONLY. `renderOffscreen` is `nonisolated` because
/// the frame graph calls it from the display-link thread; it touches only `MetalRenderCore`, which
/// is already lock-guarded.
///
/// Lives in `ARShader/`, NOT `ISFRuntime/`: `project.yml` excludes `ParamStore.swift` from the
/// `TrueISFEditorTests` target, so a shared unit referencing `ParamStore` would not compile there.
@MainActor
final class ShaderUnit: ObservableObject {
    let params = ParamStore()
    let imageSources: SourceRouter

    @Published private(set) var shaderName: String?
    @Published private(set) var compileError: String?
    @Published private(set) var compileErrorLine: Int?
    @Published private(set) var inputs: [ISFPreviewInput] = []
    @Published private(set) var isLoading = false

    /// Fired on the main actor after every load attempt, success or failure. Tests await it.
    var onCompileFinished: (() -> Void)?

    private let device: MTLDevice
    private let queue: MTLCommandQueue
    /// The render-thread half. `nonisolated` so the frame graph and `FXChain`'s snapshot can hold
    /// it without touching main-actor state; `MetalRenderCore` is `@unchecked Sendable` behind its
    /// own lock.
    nonisolated let core: MetalRenderCore
    private let compileQueue = DispatchQueue(label: "arshader.deck.compile", qos: .userInitiated)
    /// Monotonic: a compile finishing for anything but the current generation is superseded.
    private var loadGeneration = 0
    /// True when this unit's first image input is fed externally (an FX stage's chain feed) rather
    /// than routed. Decks are false: their shader's inputs are the operator's to route.
    /// Read by `ShaderControlsView` so that input is labelled rather than given a source picker.
    let reservesPrimaryInput: Bool

    init(device: MTLDevice, queue: MTLCommandQueue, clock: RenderClock,
         reservesPrimaryInput: Bool = false) {
        self.reservesPrimaryInput = reservesPrimaryInput
        self.device = device
        self.queue = queue
        self.imageSources = SourceRouter(device: device, queue: queue)
        self.core = MetalRenderCore(device: device, renderQueue: queue, clock: clock)
        core.imageRouter = imageSources
        // A fresh scene boots at header defaults; replay the operator's values over it.
        params.onSet = { [weak self] name, json in self?.applyInput(name, json) }
    }

    // MARK: loading

    func load(url: URL) {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            compileError = "Could not read \(url.lastPathComponent)."
            onCompileFinished?()
            return
        }
        load(source: text, name: url.lastPathComponent)
    }

    func load(source: String, name: String) {
        loadGeneration += 1
        let generation = loadGeneration
        isLoading = true
        let device = self.device
        compileQueue.async { [weak self] in
            let result = ISFSceneLoader.load(source: source, device: device)
            Task { @MainActor in self?.apply(result, name: name, generation: generation) }
        }
    }

    private func apply(_ result: ISFSceneLoader.Result, name: String, generation: Int) {
        guard generation == loadGeneration else { return }   // superseded by a newer load
        isLoading = false
        guard let scene = result.scene, result.isValid else {
            // FAILURE PATH: report, change nothing else. The previous scene keeps rendering.
            compileError = result.errorMessage ?? "Shader failed to compile."
            compileErrorLine = result.errorLine
            onCompileFinished?()
            return
        }
        compileError = nil
        compileErrorLine = nil
        shaderName = name
        inputs = result.inputs
        imageSources.updateInputs(result.inputs, reservePrimary: reservesPrimaryInput)
        params.syncInputs(result.inputs)
        core.setScene(scene, imageInputNames: result.inputs.filter { $0.type == "image" }.map(\.name))
        params.replayAll()
        onCompileFinished?()
    }

    /// Clear the unit back to no shader — it contributes nothing.
    func unload() {
        loadGeneration += 1
        core.setScene(nil, imageInputNames: [])
        shaderName = nil
        inputs = []
        compileError = nil
        params.resetAll()
    }

    // MARK: inputs

    private func applyInput(_ name: String, _ jsonValue: String) {
        guard let data = jsonValue.data(using: .utf8),
              let raw = try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed)
        else { return }
        var val: ISFMSLSceneVal?
        if let b = raw as? Bool {
            val = ISFMSLSceneVal.create(with: b) as? ISFMSLSceneVal
        } else if let arr = raw as? [Any] {
            let d = arr.compactMap { ($0 as? NSNumber)?.doubleValue }
            if d.count == 2 {
                val = ISFMSLSceneVal.create(withPoint2D: NSPoint(x: d[0], y: d[1])) as? ISFMSLSceneVal
            } else if d.count >= 4 {
                val = ISFMSLSceneVal.create(with: NSColor(red: d[0], green: d[1], blue: d[2],
                                                          alpha: d[3])) as? ISFMSLSceneVal
            }
        } else if let n = raw as? NSNumber {
            val = CFNumberIsFloatType(n as CFNumber)
                ? ISFMSLSceneVal.create(withFloat: n.doubleValue) as? ISFMSLSceneVal
                : ISFMSLSceneVal.create(withLong: n.int32Value) as? ISFMSLSceneVal
        }
        if let val { core.withScene { $0?.setValue(val, forInputNamed: name) } }
    }

    /// Fire an ISF `event` input for exactly one rendered frame.
    func pulseEvent(_ name: String) {
        core.withScene { $0?.setValue(ISFMSLSceneVal.createWithEvent(), forInputNamed: name) }
    }

    // MARK: rendering (display-link thread)

    /// Render this unit's scene into the caller's command buffer. Nil when nothing is loaded — the
    /// consumer treats that as "contributes nothing", never as black.
    ///
    /// `primaryInput` is an FX stage's chain feed: it overrides the router for the FIRST image
    /// input, so a stage processes what came before it rather than a routed camera frame.
    nonisolated func renderOffscreen(size: MTLSize, in cb: MTLCommandBuffer,
                                     primaryInput: MTLTexture? = nil) -> MTLTexture? {
        core.renderOffscreen(size: size, in: cb, primaryInput: primaryInput)
    }
}
