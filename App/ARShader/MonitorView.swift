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

    func makeNSView(context: Context) -> TexturePresentingView {
        let view = TexturePresentingView(device: instrument.device, queue: instrument.queue)
        view.isPaused = true            // the instrument's clock drives it, not its own
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
        renderer.registerMonitor(view)
        return view
    }

    func updateNSView(_ nsView: TexturePresentingView, context: Context) {
        context.coordinator.isFrozen = isFrozen
        context.coordinator.isOff = isOff
    }

    static func dismantleNSView(_ nsView: TexturePresentingView, coordinator: Coordinator) {
        coordinator.renderer?.unregisterMonitor(nsView)
    }

    func makeCoordinator() -> Coordinator {
        let c = Coordinator()
        c.renderer = instrument.renderer
        return c
    }

    /// Written from SwiftUI on main, READ from the display-link thread every frame — so every
    /// field is behind one lock. Not `@MainActor`: see the Threading Model.
    final class Coordinator: @unchecked Sendable {
        weak var view: TexturePresentingView?
        var renderer: InstrumentRenderer?

        private let lock = NSLock()
        private var _isFrozen = false
        private var _isOff = false
        /// The last texture pulled before freezing. Held so a frozen monitor keeps showing the
        /// frame the operator froze rather than going black.
        private var frozenTexture: MTLTexture?

        var isFrozen: Bool {
            get { lock.lock(); defer { lock.unlock() }; return _isFrozen }
            set { lock.lock(); _isFrozen = newValue; lock.unlock() }
        }
        var isOff: Bool {
            get { lock.lock(); defer { lock.unlock() }; return _isOff }
            set { lock.lock(); _isOff = newValue; lock.unlock() }
        }

        /// The texture this monitor should present, applying off/freeze. `pull` is only called
        /// when a live texture is actually wanted.
        func currentTexture(_ pull: () -> MTLTexture?) -> MTLTexture? {
            lock.lock(); defer { lock.unlock() }
            if _isOff { return nil }
            if _isFrozen { return frozenTexture }
            let tex = pull()
            frozenTexture = tex
            return tex
        }
    }
}

/// One labelled monitor tile with its freeze / off controls.
struct MonitorTile: View {
    let instrument: Instrument
    let source: MonitorSource
    let label: String
    @State private var isFrozen = false
    @State private var isOff = false

    var body: some View {
        VStack(spacing: 4) {
            MonitorViewport(instrument: instrument, source: source,
                            isFrozen: isFrozen, isOff: isOff)
                .aspectRatio(16.0 / 9.0, contentMode: .fit)
                .background(.black)
                .overlay(alignment: .topLeading) {
                    Text(label)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(.black.opacity(0.6), in: Capsule())
                        .padding(4)
                }
            HStack(spacing: 6) {
                Toggle("Freeze", isOn: $isFrozen).toggleStyle(.button).controlSize(.small)
                Toggle("Off", isOn: $isOff).toggleStyle(.button).controlSize(.small)
            }
            .font(.system(size: 11))
        }
    }
}
