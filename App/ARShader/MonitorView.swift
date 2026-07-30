import SwiftUI
import MetalKit

/// A live viewport onto one of the instrument's textures.
///
/// Draws a texture that already exists on the GPU — no readback, no encode, no budget, no cost
/// governor. That whole problem class, which made the browser cockpit expensive, does not exist in
/// this architecture.
///
/// `freeze` stops pulling new textures (the view keeps presenting whatever it last drew); `isOff`
/// withdraws the source entirely so the viewport goes black. Both are manual overrides and always
/// win over whatever the renderer is doing.
struct MonitorViewport: NSViewRepresentable {
    let instrument: Instrument
    let source: MonitorSource
    var isFrozen: Bool = false
    var isOff: Bool = false
    /// Exactly ONE viewport in the app drives the instrument clock — the PROGRAM tile.
    ///
    /// It renders the frame at the top of its own draw and is deliberately NOT registered as a
    /// monitor: `renderFrame()` draws every registered monitor, so a driver in that list would
    /// recurse (draw → renderFrame → draw → …). The other tiles are passive and registered.
    var drivesClock: Bool = false

    func makeNSView(context: Context) -> TexturePresentingView {
        let view = TexturePresentingView(device: instrument.device, queue: instrument.queue)
        view.enableSetNeedsDisplay = false
        view.preferredFramesPerSecond = 60
        context.coordinator.view = view

        let renderer = instrument.renderer
        let src = source
        // Runs on the display-link thread — see the Threading Model. No isolation wrapper: the
        // coordinator's flags and cached texture are behind its own lock, mirroring the way
        // SourceRouter guards `renderRoutes`.
        view.sourceTexture = { [weak coordinator = context.coordinator] () -> MTLTexture? in
            guard let coordinator else { return nil }
            return coordinator.currentTexture { renderer.monitorTexture(src) }
        }

        if drivesClock {
            // One tick = one instrument frame: produce it before this view samples anything.
            view.onWillDraw = { renderer.renderFrame() }
            context.coordinator.drivesClock = true
            DispatchQueue.main.async { renderer.attachClock(to: view) }
        } else {
            view.isPaused = true        // the instrument's clock drives it, not its own
            renderer.registerMonitor(view)
        }
        return view
    }

    func updateNSView(_ nsView: TexturePresentingView, context: Context) {
        let renderer = instrument.renderer
        let src = source
        // Freezing must CAPTURE pixels, not hold a reference. Done here on the main thread at the
        // moment the flag flips: it is a rare operator action, so one synchronous copy is fine and
        // keeps the per-frame path allocation-free.
        context.coordinator.setFrozen(isFrozen) { renderer.monitorTexture(src) }
        context.coordinator.isOff = isOff
    }

    static func dismantleNSView(_ nsView: TexturePresentingView, coordinator: Coordinator) {
        // The clock driver was never registered, so there is nothing to remove for it.
        if !coordinator.drivesClock { coordinator.renderer?.unregisterMonitor(nsView) }
    }

    func makeCoordinator() -> Coordinator {
        let c = Coordinator(device: instrument.device, queue: instrument.queue)
        c.renderer = instrument.renderer
        return c
    }

    /// Written from SwiftUI on main, READ from the display-link thread every frame — so every
    /// field is behind one lock. Not `@MainActor`: see the Threading Model.
    final class Coordinator: @unchecked Sendable {
        weak var view: TexturePresentingView?
        var renderer: InstrumentRenderer?
        /// True for the single clock-driving viewport, which is never registered as a monitor.
        var drivesClock = false

        private let device: MTLDevice
        private let queue: MTLCommandQueue
        private let copyPass: TextureCopyPass?

        private let lock = NSLock()
        private var _isFrozen = false
        private var _isOff = false
        /// An OWNED copy of the frame the operator froze.
        ///
        /// Must be a copy, not a reference. The master is a ping-pong pair and deck outputs are
        /// reused every frame, so holding the texture object kept the pointer valid while its
        /// CONTENTS were overwritten — freeze appeared to do nothing at all. (Reported on the
        /// Milestone 1 smoke, 2026-07-30. Same aliasing class the decks already guard against.)
        private var frozenCopy: MTLTexture?

        init(device: MTLDevice, queue: MTLCommandQueue) {
            self.device = device
            self.queue = queue
            self.copyPass = TextureCopyPass(device: device,
                                            destinationFormat: InstrumentRenderer.masterFormat)
        }

        var isOff: Bool {
            get { lock.lock(); defer { lock.unlock() }; return _isOff }
            set { lock.lock(); _isOff = newValue; lock.unlock() }
        }

        var isFrozen: Bool {
            lock.lock(); defer { lock.unlock() }
            return _isFrozen
        }

        /// Apply a freeze/unfreeze. On the rising edge it CAPTURES the current frame into an owned
        /// texture; on the falling edge it drops back to live. Idempotent — repeated calls with
        /// the same value do nothing, so SwiftUI's update churn cannot re-capture every pass.
        func setFrozen(_ frozen: Bool, pull: () -> MTLTexture?) {
            lock.lock()
            let wasFrozen = _isFrozen
            lock.unlock()
            guard frozen != wasFrozen else { return }

            if frozen, let source = pull(), let copyPass {
                let owned = ensureCopyTarget(like: source)
                if let owned, let cb = queue.makeCommandBuffer() {
                    copyPass.encode(from: source, to: owned, in: cb)
                    cb.commit()
                    cb.waitUntilCompleted()
                    lock.lock(); frozenCopy = owned; _isFrozen = true; lock.unlock()
                    return
                }
            }
            // Unfreezing, or nothing to capture (an empty deck) — go live / stay black.
            lock.lock()
            _isFrozen = frozen
            if !frozen { frozenCopy = nil }
            lock.unlock()
        }

        private func ensureCopyTarget(like source: MTLTexture) -> MTLTexture? {
            lock.lock()
            let existing = frozenCopy
            lock.unlock()
            if let existing, existing.width == source.width, existing.height == source.height {
                return existing
            }
            let desc = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: InstrumentRenderer.masterFormat,
                width: source.width, height: source.height, mipmapped: false)
            desc.usage = [.renderTarget, .shaderRead]
            desc.storageMode = .private
            return device.makeTexture(descriptor: desc)
        }

        /// The texture this monitor should present, applying off/freeze. `pull` is only called
        /// when a live texture is actually wanted.
        func currentTexture(_ pull: () -> MTLTexture?) -> MTLTexture? {
            lock.lock()
            let off = _isOff, frozen = _isFrozen, held = frozenCopy
            lock.unlock()
            if off { return nil }
            if frozen { return held }
            return pull()
        }
    }
}

/// One labelled monitor tile with its freeze / off controls.
struct MonitorTile: View {
    let instrument: Instrument
    let source: MonitorSource
    let label: String
    /// Set on exactly one tile (PROGRAM) — see `MonitorViewport.drivesClock`.
    var drivesClock: Bool = false
    @State private var isFrozen = false
    @State private var isOff = false
    @ObservedObject private var elementStats: ElementStatsModel

    init(instrument: Instrument, source: MonitorSource, label: String,
         drivesClock: Bool = false) {
        self.instrument = instrument
        self.source = source
        self.label = label
        self.drivesClock = drivesClock
        self.elementStats = instrument.elementStats
    }

    /// This tile's own GPU cost, or nil when metering is off. Absent, not zero — the tile shows
    /// nothing rather than claiming an element measured as free.
    private var gpuMs: Double? { elementStats.gpuMs[source.element] }

    var body: some View {
        VStack(spacing: 4) {
            MonitorViewport(instrument: instrument, source: source,
                            isFrozen: isFrozen, isOff: isOff, drivesClock: drivesClock)
                .aspectRatio(16.0 / 9.0, contentMode: .fit)
                .background(.black)
                .overlay(alignment: .topLeading) {
                    Text(label)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(.black.opacity(0.6), in: Capsule())
                        .padding(4)
                }
                .overlay(alignment: .topTrailing) {
                    if let gpuMs {
                        Text(String(format: "%.1f ms", gpuMs))
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(gpuMs >= 8 ? .orange : .primary)
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(.black.opacity(0.6), in: Capsule())
                            .padding(4)
                            .help(source == .master
                                  ? "GPU time for the composite and master FX only — the decks "
                                    + "are counted on their own tiles, so these add up to the "
                                    + "frame without double-counting."
                                  : "GPU time for this deck: its shader render, its copy, and its "
                                    + "FX chain.")
                    }
                }
            HStack(spacing: 6) {
                Toggle("Freeze", isOn: $isFrozen).toggleStyle(.button).controlSize(.small)
                Toggle("Off", isOn: $isOff).toggleStyle(.button).controlSize(.small)
            }
            .font(.system(size: 11))
        }
    }
}
