import Metal
import MetalKit
import QuartzCore
import VVMetalKit

/// What a viewport is looking at.
enum MonitorSource: Equatable, Sendable {
    case deck(DeckID)
    /// The program feed. Taps POST-blackout: when the room is dark, this monitor is dark.
    case master

    /// The frame element whose GPU cost this viewport is looking at.
    var element: RenderElement {
        switch self {
        case .deck(let id): return .deck(id)
        case .master:       return .master
        }
    }
}

/// Which part of the frame a GPU-time sample belongs to.
enum RenderElement: Hashable, Sendable {
    case deck(DeckID)
    /// The composite and the master FX chain — NOT the decks feeding it, which are already counted
    /// on their own tiles. Adding the tiles up therefore gives the frame, without double-counting.
    case master
}

/// Observable slot for per-element GPU figures, mirroring `RenderStatsModel`. Separate from the
/// renderer so a monitor tile can watch its own cost without observing the whole frame graph.
@MainActor
final class ElementStatsModel: ObservableObject {
    /// Mean GPU ms per element over the last window. **Empty means "not measured"** — a tile shows
    /// nothing rather than a zero, because "free" and "unmeasured" are different claims.
    @Published var gpuMs: [RenderElement: Double] = [:]
}

/// Windowed per-element GPU time.
///
/// Lives here rather than beside `RenderStatsAccumulator` because the shared runtime's
/// `RenderStats` cannot know what a deck is — `ISFRuntime` compiles into the editor too.
struct ElementStatsAccumulator {
    private var seconds: [RenderElement: Double] = [:]
    private var samples: [RenderElement: Int] = [:]

    /// Record one completed command buffer's GPU duration against the element it rendered.
    mutating func add(_ element: RenderElement, seconds value: Double) {
        guard value > 0 else { return }   // gpuStart/EndTime are 0 on some failure paths
        seconds[element, default: 0] += value
        samples[element, default: 0] += 1
    }

    /// Mean milliseconds per element over the window, clearing it. Elements with no completed
    /// sample are absent rather than zero: "not measured" and "measured as free" are different
    /// claims, and only one of them is honest to display.
    mutating func drain() -> [RenderElement: Double] {
        var out: [RenderElement: Double] = [:]
        for (element, total) in seconds where (samples[element] ?? 0) > 0 {
            out[element] = (total / Double(samples[element]!)) * 1000.0
        }
        seconds.removeAll()
        samples.removeAll()
        return out
    }

    mutating func reset() {
        seconds.removeAll()
        samples.removeAll()
    }
}

/// The instrument's single clock and frame graph.
///
/// One `DisplayLinkDriver` drives ONE frame for everything — decks, compositor, monitors, program
/// output. This is the deliberate departure from the editor, where each MTKView owns its own
/// display link (correct for N independent previews, wrong for one instrument).
///
/// **Deliberately NOT `@MainActor`.** `renderFrame()` is called from the CVDisplayLink thread, and
/// the display link exists precisely so SwiftUI/AppKit layout during a control drag cannot starve
/// the render loop. Marking this main-actor and reaching for `MainActor.assumeIsolated` in the
/// render closure is not a workaround — `assumeIsolated` is a runtime ASSERTION, and it traps
/// (`dispatch_assert_queue_fail`) on the very first tick. Measured 2026-07-30.
///
/// So this follows the pattern `MetalRenderCore` already proves: `@unchecked Sendable` with one
/// coarse lock guarding every field the render thread touches. Main-thread callers (attach, UI
/// reads) take the same lock, so access is strictly serialized.
///
/// Master textures ping-pong: the compositor reads one and writes the other, so each layer sees the
/// backdrop the previous layer produced. Both are allocated once at 1920×1080; the steady-state
/// frame allocates nothing.
final class InstrumentRenderer: @unchecked Sendable {
    /// The size textures are allocated at before the operator picks anything.
    static let masterWidth = RenderSize.default.width
    static let masterHeight = RenderSize.default.height
    /// 16-bit float: ISF scenes commonly output float formats, and blending in a wider space than
    /// the 8-bit drawable avoids banding on repeated composites.
    static let masterFormat: MTLPixelFormat = .rgba16Float

    /// Test seam: forces the "compositor could not be built" branch without a broken GPU.
    enum CompositorOverride { case failed }

    private let device: MTLDevice
    private let queue: MTLCommandQueue
    let clock: RenderClock
    private let mixer: MixerState
    private let compositor: Compositor?
    private(set) var decks: [DeckID: Deck] = [:]

    private let lock = NSLock()
    // ── lock-guarded state ──
    /// Ping-pong pair. `masterIndex` names the texture holding the CURRENT composited result.
    private var masters: [MTLTexture] = []
    private var masterIndex = 0
    private var driver: DisplayLinkDriver?
    private var deckOutputs: [DeckID: MTLTexture] = [:]
    /// The size each deck was actually asked to RASTERISE last frame — as opposed to the size of
    /// its owned texture, which is fixed at the live size so a fade never reallocates.
    ///
    /// Observability, not decoration: "a live deck follows the render scale" is the whole claim of
    /// this feature, and without this it is not assertable — the owned texture is the same size
    /// either way, so a test reading `deckTexture` would pass even if the scale never reached the
    /// rasteriser.
    private var deckRasterSizes: [DeckID: MTLSize] = [:]
    /// Test observability: how many command buffers this renderer has committed.
    private var committedBuffers = 0
    /// Program-output resolution. Changing it reallocates both masters — rare, operator-driven,
    /// and never in the steady-state frame.
    private var masterResolution: RenderSize = .default
    /// What live decks AND the master composite rasterise at, as a fraction of the output
    /// resolution. The instrument's one real GPU lever: the ISF render is where essentially all
    /// the cost lives (monitors just sample a texture that already exists, which is nearly free).
    private var renderScale: RenderScale = .defaultRender
    /// What a deck rasterises at while it is NOT contributing to program, as a fraction of the
    /// LIVE render size — the two scales compose.
    ///
    /// A cued deck feeds only a small monitor, so rasterising it at the live size is pure waste.
    /// It is also the only saving still available while the projector is open, since the preview
    /// scale cannot drop below full output resolution without softening the projection.
    private var cueScale: RenderScale = .defaultCue
    private var stats = RenderStatsAccumulator()
    private var statsWereLive = false
    /// Per-element GPU metering.
    ///
    /// OFF by default, and off is the shipping invariant: the whole frame is ONE command buffer.
    /// ON splits the frame into one buffer per element so `gpuStartTime`/`gpuEndTime` — the same
    /// measurement the global readout already trusts — attributes cleanly to each one.
    ///
    /// **Measuring perturbs the measurement, and the UI says so.** Separate buffers execute in
    /// commit order and cannot overlap on the GPU, so the frame total while metering is slightly
    /// higher than while not. That is the price of an unambiguous per-element number, and it is
    /// the same price the counter-sampling alternative would have charged via `barrier: true` —
    /// which this machine cannot do anyway (`atBlitBoundary` is false on Apple M5 Max).
    private var meteringEnabled = false
    private var elementStats = ElementStatsAccumulator()
    /// Views presenting instrument textures. Weak: a closed panel's view must deallocate, and a
    /// strong list would hold a window's worth of Metal state alive forever.
    private let monitors = NSHashTable<MTKView>.weakObjects()

    /// Called after each frame's command buffer is committed, on the render thread.
    var onFrameRendered: (@Sendable () -> Void)?
    /// A fresh FPS / GPU-ms snapshot ~2x per second, or nil when the loop stops producing frames.
    /// Fires on the render thread; the UI hops to main.
    var onStats: (@Sendable (RenderStats?) -> Void)?
    /// Per-element mean GPU ms, published on the same window as `onStats`. Empty while metering is
    /// off. Fires on the render thread.
    var onElementStats: (@Sendable ([RenderElement: Double]) -> Void)?

    @MainActor
    init(device: MTLDevice, queue: MTLCommandQueue, mixer: MixerState,
         compositorOverride: CompositorOverride? = nil) {
        self.device = device
        self.queue = queue
        self.mixer = mixer
        self.clock = RenderClock()
        // ISFMSLKit needs its global pool before any scene work; harmless if already set.
        if VVMTLPool.global == nil { VVMTLPool.global = VVMTLPool(device: device) }
        masters = Self.makeMasterPair(
            device: device, resolution: RenderScale.defaultRender.applied(to: .default))
        // A nil compositor is a survivable state, not a crash: renderFrame falls back to a black
        // master and the instrument still starts (spec §8).
        self.compositor = compositorOverride == .failed ? nil : Compositor(device: device)
        // Every deck shares the ONE clock, so a swap on deck A cannot restart deck B's animation.
        for id in DeckID.allCases {
            decks[id] = Deck(id: id, device: device, queue: queue, clock: clock)
        }
    }

    private static func makeMaster(device: MTLDevice,
                                   resolution: RenderSize = .default) -> MTLTexture? {
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: masterFormat, width: resolution.width, height: resolution.height,
            mipmapped: false)
        desc.usage = [.renderTarget, .shaderRead]
        desc.storageMode = .private
        return device.makeTexture(descriptor: desc)
    }

    private static func makeMasterPair(device: MTLDevice, resolution: RenderSize) -> [MTLTexture] {
        (0..<2).compactMap { _ in makeMaster(device: device, resolution: resolution) }
    }

    /// The program-output resolution — what the projector shows and what the typed W×H means.
    /// Reallocates the master pair; a no-op if unchanged, so the UI can bind to it freely.
    var outputResolution: RenderSize {
        get { lock.lock(); defer { lock.unlock() }; return masterResolution }
        set {
            lock.lock()
            guard newValue != masterResolution else { lock.unlock(); return }
            masterResolution = newValue
            reallocateMastersLocked()
            lock.unlock()
        }
    }

    /// What live decks and the master composite rasterise at.
    ///
    /// Called **PREVIEW SCALE** on the surface, because that is what it governs in practice: with
    /// the program output closed — most of the operator's working time — the only consumers are
    /// three ~340px monitor tiles, so nothing needs full resolution and dropping this is free GPU
    /// with no visible cost. Measured 2026-07-30: 99.4 ms at 100%, 5.8 ms at 25%.
    ///
    /// It is NOT preview-only, and the name would be a lie if that went unsaid: while the projector
    /// is open this scales the projected image too. The scale is manual by the operator's choice
    /// and never snaps back on its own, so `OutputSharpness.isProjectingUpscaled` drives a visible
    /// warning for exactly that case.
    ///
    /// Reallocates the master pair (and, on the next frame, each deck's owned texture) — rare and
    /// operator-driven, never in a frame.
    var previewScale: RenderScale {
        get { lock.lock(); defer { lock.unlock() }; return renderScale }
        set {
            lock.lock()
            guard newValue != renderScale else { lock.unlock(); return }
            renderScale = newValue
            reallocateMastersLocked()
            lock.unlock()
        }
    }

    /// What a deck rasterises at while it is NOT contributing. Allocates NOTHING: the deck draws
    /// small and upscales into its existing owned texture, which is why it is safe to drop low.
    var cueRenderScale: RenderScale {
        get { lock.lock(); defer { lock.unlock() }; return cueScale }
        set { lock.lock(); cueScale = newValue; lock.unlock() }
    }

    /// Per-element GPU metering. See `meteringEnabled` for what turning it on costs.
    var isMeteringEnabled: Bool {
        get { lock.lock(); defer { lock.unlock() }; return meteringEnabled }
        set {
            lock.lock()
            guard newValue != meteringEnabled else { lock.unlock(); return }
            meteringEnabled = newValue
            elementStats.reset()    // never carry samples across a change of measurement regime
            lock.unlock()
            if !newValue { onElementStats?([:]) }
        }
    }

    /// Requires `lock` held. Only swaps if BOTH allocated: a half-resized pair would composite
    /// across mismatched targets, and the failure would look like a corrupted image rather than
    /// an error.
    private func reallocateMastersLocked() {
        let fresh = Self.makeMasterPair(device: device,
                                        resolution: renderScale.applied(to: masterResolution))
        if fresh.count == 2 {
            masters = fresh
            masterIndex = 0
        }
    }

    @MainActor
    func deck(_ id: DeckID) -> Deck {
        guard let d = decks[id] else {
            preconditionFailure("Deck \(id.rawValue) is created in init and cannot be missing")
        }
        return d
    }

    var committedBufferCount: Int {
        lock.lock(); defer { lock.unlock() }
        return committedBuffers
    }

    // MARK: textures

    /// The program feed. **Nil while blacked out** — and consumers render opaque black on nil.
    ///
    /// Blackout is a final gate (spec §8), not a stage: there is no pipeline, no shader and no
    /// extra state between the panic button and darkness. The same nil is what a failed compositor
    /// yields, so the failure floor and the panic button share one code path.
    func programTexture() -> MTLTexture? {
        guard !mixer.isBlackedOutForRender() else { return nil }
        return rawMasterTexture()
    }

    /// The master texture regardless of the blackout gate. For tests and the failure floor only —
    /// never call this from a display path.
    func rawMasterTexture() -> MTLTexture? {
        lock.lock(); defer { lock.unlock() }
        return masters.indices.contains(masterIndex) ? masters[masterIndex] : nil
    }

    /// The deck's own output, pre-opacity and pre-blend — what a deck monitor shows. Nil when the
    /// deck has no shader loaded.
    func deckTexture(_ id: DeckID) -> MTLTexture? {
        lock.lock(); defer { lock.unlock() }
        return deckOutputs[id]
    }

    /// The pixel size this deck rasterised at on the last frame — the number the render and cue
    /// scales actually control, and the one that predicts GPU cost.
    func deckRasterSize(_ id: DeckID) -> MTLSize? {
        lock.lock(); defer { lock.unlock() }
        return deckRasterSizes[id]
    }

    func monitorTexture(_ source: MonitorSource) -> MTLTexture? {
        switch source {
        case .deck(let id):
            // Cue monitors: the operator lines up the next shader while the room is dark, so these
            // deliberately do NOT tap post-blackout.
            return deckTexture(id)
        case .master:
            return programTexture()
        }
    }

    // MARK: the frame graph

    /// Render exactly one frame of the whole instrument into ONE command buffer.
    ///
    /// 1. each deck renders offscreen into its own texture
    /// 2. the master is cleared to OPAQUE BLACK — what a bottom-layer blend blends against
    /// 3. each contributing layer composites, ping-ponging between the two masters
    func renderFrame() {
        let layers = mixer.renderLayers()

        lock.lock()
        guard masters.count == 2, let cb = queue.makeCommandBuffer() else {
            lock.unlock()
            return
        }
        let metering = meteringEnabled
        let deckList = decks
        let outRes = masterResolution
        let liveRes = renderScale.applied(to: outRes)
        // Cue is a fraction of the LIVE render, not of the output. Applied to the output it could
        // exceed the live size — preview 25% with cue 50% rasterised a faded-out deck at 960px
        // against the live deck's 480, so the deck nobody can see cost four times the pixels of
        // the one on program. Composing them means the two scales multiply, which is what an
        // operator reading "25% preview, 50% cue" would expect.
        let cueRes = cueScale.applied(to: liveRes)
        lock.unlock()

        // 1. Decks render offscreen into their own textures. Deck.render is nonisolated and
        //    internally lock-guarded, so this is safe off the main actor.
        //
        //    A deck that is not contributing to program (faded out, or cued on the far side of the
        //    crossfader) rasterises at the CUE resolution: it is only feeding a small monitor, and
        //    the ISF render is where essentially all the GPU cost is. Its owned texture stays at
        //    the output size, so starting a fade costs no reallocation.
        // Extra buffers exist ONLY while metering. Off, everything shares `cb` and the frame is
        // one buffer, exactly as before. On, each deck gets its own so its GPU time is its own;
        // buffers on one queue execute in commit order, so ordering and cross-buffer texture
        // dependencies are unaffected.
        var meteredBuffers: [(RenderElement, MTLCommandBuffer)] = []
        var outputs: [DeckID: MTLTexture] = [:]
        var rasterSizes: [DeckID: MTLSize] = [:]
        for layer in layers {
            guard let deck = deckList[layer.deck] else { continue }
            let isLive = layer.effectiveOpacity > 0
            let renderSize = (isLive ? liveRes : cueRes).size
            var target = cb
            if metering, let own = queue.makeCommandBuffer() {
                target = own
                meteredBuffers.append((.deck(layer.deck), own))
            }
            if let tex = deck.render(in: target, renderSize: renderSize, ownedSize: liveRes.size) {
                outputs[layer.deck] = tex
                // Only on success: this reports what a deck ACTUALLY rasterised, not what it
                // would have been asked for had it held a shader.
                rasterSizes[layer.deck] = renderSize
            }
        }

        lock.lock()
        // 2. The master begins each frame as OPAQUE BLACK (spec §7). This is what a bottom-layer
        //    blend mode blends against, and what an empty instrument shows.
        var current = 0
        clearToOpaqueBlack(masters[current], in: cb)

        // 3. Composite each contributing layer, ping-ponging between the two masters.
        if let compositor {
            for layer in layers {
                guard let source = outputs[layer.deck], layer.effectiveOpacity > 0 else {
                    continue    // no shader, or faded out — the backdrop passes through untouched
                }
                let next = 1 - current
                compositor.encodeLayer(source: source,
                                       backdrop: masters[current],
                                       destination: masters[next],
                                       opacity: layer.effectiveOpacity,
                                       mode: layer.blendMode,
                                       in: cb)
                current = next
            }
        }
        // The result may be in either master depending on how many layers contributed — track it
        // rather than assuming parity from the deck count.
        masterIndex = current
        deckOutputs = outputs
        deckRasterSizes = rasterSizes
        committedBuffers += 1 + meteredBuffers.count
        let views = monitors.allObjects
        lock.unlock()

        // Deck buffers commit BEFORE the master buffer. Buffers on one queue execute in commit
        // order, so the master still samples deck outputs that have already been written — the
        // dependency the single-buffer version got from encode order.
        for (element, buffer) in meteredBuffers {
            buffer.addCompletedHandler { [weak self] buf in
                self?.addElementGPUTime(element, seconds: buf.gpuEndTime - buf.gpuStartTime)
            }
            buffer.commit()
        }

        // GPU frame time arrives on a Metal completion thread; addGPUTime is lock-protected, so no
        // main hop is needed. Must be attached before commit.
        //
        // While metering, `cb` carries ONLY the clear and the composite — the decks went to their
        // own buffers — so it is the master element's cost, not the frame's. The frame total then
        // comes from summing the elements, which is why `.master` deliberately excludes the decks
        // feeding it.
        cb.addCompletedHandler { [weak self] buf in
            let seconds = buf.gpuEndTime - buf.gpuStartTime
            self?.addGPUTime(seconds: seconds)
            if metering { self?.addElementGPUTime(.master, seconds: seconds) }
        }
        cb.commit()

        lock.lock()
        let snapshot = stats.frame(at: CACurrentMediaTime())
        if snapshot != nil { statsWereLive = true }
        // Per-element figures ride the SAME window as the global snapshot, so a tile and the
        // headline readout can never disagree about which half-second they describe.
        let elements = snapshot != nil && metering ? elementStats.drain() : nil
        lock.unlock()
        if let snapshot { onStats?(snapshot) }
        if let elements { onElementStats?(elements) }

        onFrameRendered?()

        // Monitors present textures produced by the buffer just committed. Each MTKView.draw()
        // manages its own drawable cycle and encodes its own (tiny) present buffer — the frame's
        // RENDER work is still one buffer; these are presents.
        for view in views { view.draw() }
    }

    /// The one operation that must never depend on a compiled pipeline: a render pass whose only
    /// job is a clear. This is the failure floor for the whole instrument (spec §8).
    func clearToOpaqueBlack(_ texture: MTLTexture, in cb: MTLCommandBuffer) {
        let rpd = MTLRenderPassDescriptor()
        rpd.colorAttachments[0].texture = texture
        rpd.colorAttachments[0].loadAction = .clear
        rpd.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        rpd.colorAttachments[0].storeAction = .store
        cb.makeRenderCommandEncoder(descriptor: rpd)?.endEncoding()
    }

    private func addElementGPUTime(_ element: RenderElement, seconds: Double) {
        lock.lock(); defer { lock.unlock() }
        elementStats.add(element, seconds: seconds)
    }

    private func addGPUTime(seconds: Double) {
        lock.lock(); defer { lock.unlock() }
        stats.addGPUTime(seconds: seconds)
    }

    /// Drop the stats window — a paused loop must not keep reporting the old rate.
    func resetStats() {
        lock.lock()
        stats.reset()
        elementStats.reset()
        let wasLive = statsWereLive
        statsWereLive = false
        lock.unlock()
        if wasLive {
            onStats?(nil)
            onElementStats?([:])   // a paused loop must not leave stale per-tile figures up
        }
    }

    // MARK: monitors

    func registerMonitor(_ view: MTKView) {
        lock.lock(); defer { lock.unlock() }
        monitors.add(view)
    }

    func unregisterMonitor(_ view: MTKView) {
        lock.lock(); defer { lock.unlock() }
        monitors.remove(view)
    }

    // MARK: clock control (main thread)

    func start() {
        lock.lock(); let d = driver; lock.unlock()
        d?.start()
    }

    func stop() {
        lock.lock(); let d = driver; lock.unlock()
        d?.pause()
    }

    /// Attach the display link to the view that owns the frame cadence (the program output).
    /// Called once, after the window exists.
    @MainActor
    func attachClock(to view: MTKView) {
        lock.lock()
        guard driver == nil else { lock.unlock(); return }
        let d = DisplayLinkDriver(view: view)
        driver = d
        lock.unlock()
        view.isPaused = (d != nil)
        d?.start()
    }

    deinit {
        driver?.invalidate()
    }
}
