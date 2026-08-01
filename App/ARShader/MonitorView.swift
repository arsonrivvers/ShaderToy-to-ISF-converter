import AppKit      // NSEvent.modifierFlags — SwiftUI alone does not guarantee it
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
    /// Set while a compatible drag hovers a deck tile. Never used for PROGRAM — see
    /// `dropDestinationIfDeck`.
    @State private var isDropTargeted = false
    @ObservedObject private var elementStats: ElementStatsModel
    @ObservedObject private var renderStats: RenderStatsModel

    init(instrument: Instrument, source: MonitorSource, label: String,
         drivesClock: Bool = false) {
        self.instrument = instrument
        self.source = source
        self.label = label
        self.drivesClock = drivesClock
        self.elementStats = instrument.elementStats
        self.renderStats = instrument.renderStats
    }

    /// This tile's own GPU cost. Absent, not zero — a tile shows nothing rather than claiming an
    /// element measured as free.
    private var gpuMs: Double? { elementStats.gpuMs[source.element] }

    /// The readout for this tile: the instrument's frame rate and THIS element's GPU time.
    ///
    /// The FPS figure is deliberately the same on every tile, and that is not a fudge — one
    /// display link drives one frame for the whole instrument, so every pane updates at exactly
    /// this rate. Showing three different numbers would be inventing a distinction that does not
    /// exist in the architecture. The GPU figure is what actually differs per tile.
    private var readout: String? {
        guard let gpuMs else { return nil }
        guard let fps = renderStats.stats?.fps else { return String(format: "%.1f ms", gpuMs) }
        return String(format: "%.0f FPS · %.1f ms", fps, gpuMs)
    }

    var body: some View {
        VStack(spacing: 4) {
            draggableIfCapturable(dropDestinationIfDeck(
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
                    if let readout, let gpuMs {
                        Text(readout)
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(gpuMs >= 8 ? .orange : .primary)
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(.black.opacity(0.6), in: Capsule())
                            .padding(4)
                            .help(source == .master
                                  ? "The instrument's frame rate, and the GPU time for the "
                                    + "composite and master FX alone — not the decks feeding it, "
                                    + "which are timed on their own tiles.\n\nThe tiles do NOT "
                                    + "sum to the frame: independent buffers overlap on the GPU, "
                                    + "so the frame total is smaller than their sum."
                                  : "The instrument's frame rate, and the GPU time for this deck: "
                                    + "its shader render, its copy, and its FX chain.\n\nFPS is "
                                    + "the same on every tile by construction — one clock drives "
                                    + "one frame for the whole instrument.")
                    }
                }
                // An outline, because a black tile showing a black frame has no visible bounds at
                // all — the labels and readouts float in an unbroken field and the operator cannot
                // tell where one preview ends and the next begins (operator, 2026-07-31, from the
                // first look at phase 3a). PROGRAM reads brighter: it is what reaches the audience.
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .strokeBorder(source == .master
                                      ? Color.white.opacity(0.35)
                                      : Color.white.opacity(0.15),
                                      lineWidth: 1)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .strokeBorder(isDropTargeted ? Color.accentColor : Color.clear,
                                      lineWidth: 2)
                )
            ))
            HStack(spacing: 6) {
                Toggle("Freeze", isOn: $isFrozen).toggleStyle(.button).controlSize(.small)
                Toggle("Off", isOn: $isOff).toggleStyle(.button).controlSize(.small)
            }
            .font(.system(size: 11))
        }
    }

    /// What a deck tile's drag would carry, or nil when the tile is not a legal drag source.
    ///
    /// Pulled out of `draggableIfCapturable` as a plain, `View`-free function for the same reason
    /// `ShaderDrag.accepts` has no SwiftUI import: a mutation of the ONE line that matters here —
    /// which `snapshot` actually goes into the payload — must be reachable by a test with no view
    /// in play. Left inline inside `draggableIfCapturable`, that line is a `.draggable(_:)`
    /// modifier argument SwiftUI gives no way to read back, which is exactly the "tests that
    /// cannot fail" trap this phase has hit three times before; this is the second half of Task 6
    /// Step 5, not restructuring beyond the task.
    ///
    /// Deck tiles ONLY — never PROGRAM: `Instrument.currentPreset(of:)` takes a `DeckID`, and
    /// there is no such thing as the master's shader. The program feed is a composite of two
    /// decks and an FX chain; a "look" of it is not a `Preset`, and `currentPreset` is not widened
    /// to pretend otherwise.
    static func dragPayload(for source: MonitorSource, instrument: Instrument) -> ShaderDrag? {
        guard case .deck(let id) = source, let preset = instrument.currentPreset(of: id) else {
            return nil
        }
        return ShaderDrag(source: .deck(id), url: preset.shaderURL, snapshot: preset.snapshot)
    }

    /// Gates the `.draggable` modifier itself, rather than always attaching one with a sentinel
    /// payload for the empty case — a sentinel would still let the drag START (and read like a
    /// legitimate one to the operator) only to be rejected wherever it lands. An empty deck simply
    /// is not a drag source.
    @ViewBuilder
    private func draggableIfCapturable<V: View>(_ view: V) -> some View {
        if let payload = Self.dragPayload(for: source, instrument: instrument) {
            view.draggable(payload)
        } else {
            view
        }
    }

    /// A deck tile accepts a library drag (fills the deck) or a deck drag (never — see
    /// `ShaderDrag.accepts`'s `.deck` branch, which only ever allows `.slot`). PROGRAM is not
    /// wrapped at all: `ShaderDrag.Destination` has no case for the master composite, because it
    /// is not a `Preset` — a blend of two decks and an FX chain has no single shader URL to load.
    @ViewBuilder
    private func dropDestinationIfDeck<V: View>(_ view: V) -> some View {
        if case .deck(let id) = source {
            view.dropDestination(for: ShaderDrag.self) { items, _ in
                guard let drag = items.first,
                      ShaderDrag.accepts(drag, on: .deck(id), isSlotFilled: false,
                                         withOption: NSEvent.modifierFlags.contains(.option))
                else { return false }
                instrument.load(drag.url, onto: .deck(id), thenApply: drag.snapshot)
                return true
            // Accepted limitation, not an oversight (fix-round-1, F2 — operator ruling: keep the
            // modern API, do not fix). `isTargeted` receives only a `Bool`; SwiftUI resolves the
            // hovering item's VALUE only inside `action`, at drop time. A deck-sourced drag onto
            // a DIFFERENT deck is rejected by `ShaderDrag.accepts` (a deck may only be dropped on
            // a slot — see the `.deck` branch), but this highlight cannot ask "which source is
            // this?" before the drop lands, so it lights up for another deck's drag too —
            // correctly rejected a moment later when `action` runs, never loaded. `DropDelegate`'s
            // `DropInfo.itemProviders(for:)` (macOS 11+) could answer this at
            // `dropEntered`/`validateDrop`, but every such fix is an API rollback off
            // `Transferable`/`.dropDestination`, which the brief specified deliberately (see
            // `ShaderDrag.swift`'s own doc comment). Slots — the one destination that can
            // actually destroy a dialled-in look — ARE filtered correctly; see
            // `SlotBankStripView.wouldHighlight(at:)`.
            } isTargeted: { isDropTargeted = $0 }
        } else {
            view
        }
    }
}
