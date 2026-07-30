import Foundation
import AppKit
import Metal
import Combine
import ISFMSLKit

enum DeckID: String, CaseIterable, Identifiable, Sendable {
    case one = "1"
    case two = "2"
    var id: String { rawValue }
    /// What the operator sees. Decks are "A" and "B" on the surface, 1 and 2 in the layer stack.
    var displayName: String { self == .one ? "A" : "B" }
}

/// One deck: a loaded ISF shader, its parameter values, its image-input routing, and one owned
/// output texture.
///
/// **Compile first, swap only on success.** A failed compile leaves the running shader playing and
/// reports the error. This is the opposite of the editor's behavior (which drops the scene so the
/// author sees their mistake) and it is deliberate: on stage, the shader that is already up is the
/// one thing you cannot afford to lose. Ported from Phase A rather than rediscovered.
///
/// `@MainActor` covers the `@Published` UI state ONLY. `render(in:)` is `nonisolated` because the
/// frame graph calls it from the display-link thread; it touches only `MetalRenderCore` (already
/// lock-guarded), the copy pass (immutable after init), and `renderOwnedOutput`, which — like
/// `ISFSceneSource.lastGood` — is written and read by that single render-thread consumer alone.
@MainActor
final class Deck: ObservableObject {
    let id: DeckID
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
    private let core: MetalRenderCore
    private let compileQueue = DispatchQueue(label: "arshader.deck.compile", qos: .userInitiated)
    /// Built once in init, immutable after — a lazy var would not be safe to touch from the
    /// render thread.
    private let copyPass: TextureCopyPass?
    /// Touched ONLY by the render thread (see the class comment).
    nonisolated(unsafe) private var renderOwnedOutput: MTLTexture?
    /// Monotonic: a compile finishing for anything but the current generation is superseded.
    private var loadGeneration = 0

    init(id: DeckID, device: MTLDevice, queue: MTLCommandQueue, clock: RenderClock) {
        self.id = id
        self.device = device
        self.queue = queue
        self.imageSources = SourceRouter(device: device, queue: queue)
        self.core = MetalRenderCore(device: device, renderQueue: queue, clock: clock)
        self.copyPass = TextureCopyPass(device: device,
                                        destinationFormat: InstrumentRenderer.masterFormat)
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
        imageSources.updateInputs(result.inputs)
        params.syncInputs(result.inputs)
        core.setScene(scene, imageInputNames: result.inputs.filter { $0.type == "image" }.map(\.name))
        params.replayAll()
        onCompileFinished?()
    }

    /// Clear the deck back to no shader — the layer contributes nothing.
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

    /// Render this deck into the caller's command buffer and return the deck's OWNED output
    /// texture. Nil when no shader is loaded — the layer contributes nothing and the compositor
    /// skips it. Never returns a pool texture: monitors read this in a later buffer.
    nonisolated func render(in cb: MTLCommandBuffer) -> MTLTexture? {
        let size = MTLSize(width: InstrumentRenderer.masterWidth,
                           height: InstrumentRenderer.masterHeight, depth: 1)
        guard let engineTexture = core.renderOffscreen(size: size, in: cb) else { return nil }
        if renderOwnedOutput == nil { renderOwnedOutput = Self.makeOutputTexture(device: device) }
        guard let owned = renderOwnedOutput, let copyPass else { return nil }
        copyPass.encode(from: engineTexture, to: owned, in: cb)
        return owned
    }

    /// The deck's last rendered output, for monitors. Nil until the first successful render.
    nonisolated var currentOutput: MTLTexture? { renderOwnedOutput }

    nonisolated private static func makeOutputTexture(device: MTLDevice) -> MTLTexture? {
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: InstrumentRenderer.masterFormat,
            width: InstrumentRenderer.masterWidth,
            height: InstrumentRenderer.masterHeight, mipmapped: false)
        desc.usage = [.renderTarget, .shaderRead]
        desc.storageMode = .private
        return device.makeTexture(descriptor: desc)
    }
}
