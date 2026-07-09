import SwiftUI
import AppKit
import Combine
import CoreGraphics

/// A small Metal preview of one child ISF. Hosts a `MetalPreviewController`, loads the source once,
/// and reports the compile outcome back via `onCompile`. When `animating` is false it renders a single
/// frozen frame instead of running continuously (performance cap from the studio model).
struct RemixThumbnailView: NSViewRepresentable {
    let isf: String
    let animating: Bool
    /// Optional: receives one downscaled CGImage frame at first successful compile (tree swatches).
    var onSnapshot: ((CGImage) -> Void)? = nil
    /// Called on the main actor with (valid, errorMessage) once the engine finishes compiling.
    let onCompile: (Bool, String?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onCompile: onCompile, onSnapshot: onSnapshot) }

    func makeNSView(context: Context) -> NSView {
        let controller = context.coordinator.controller
        context.coordinator.loadedISF = isf
        controller.load(isf: isf)
        context.coordinator.observe(controller)
        return controller.nsView
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        let controller = context.coordinator.controller
        if context.coordinator.loadedISF != isf {
            context.coordinator.loadedISF = isf
            context.coordinator.sourceChanged()   // re-arm the compile report for the new source
            controller.load(isf: isf)
        }
        // Freeze when not animating: PAUSE the loop (so GPU work actually stops) and show one frame —
        // but only on the animating→frozen TRANSITION. `updateNSView` runs on every model republish
        // (per transcript line during generation), so an unconditional draw forced one GPU frame per
        // paused card per line. (A frozen card's post-compile frame is pushed by the observe sink.)
        let wasAnimating = context.coordinator.animating
        context.coordinator.animating = animating
        controller.setPaused(!animating)
        if Self.shouldPushFrozenFrame(wasAnimating: wasAnimating, animating: animating) {
            controller.drawOneFrame()
        }
    }

    static func shouldPushFrozenFrame(wasAnimating: Bool, animating: Bool) -> Bool {
        wasAnimating && !animating
    }

    @MainActor
    final class Coordinator {
        let controller = MetalPreviewController()
        let onCompile: (Bool, String?) -> Void
        let onSnapshot: ((CGImage) -> Void)?
        var loadedISF: String?
        var animating = true
        private var bag = Set<AnyCancellable>()
        private(set) var reported = false

        init(onCompile: @escaping (Bool, String?) -> Void, onSnapshot: ((CGImage) -> Void)?) {
            self.onCompile = onCompile
            self.onSnapshot = onSnapshot
        }

        /// SwiftUI recycles coordinators across node changes (LazyVGrid, tree slots) — re-arm the
        /// fire-once compile report so the NEW source's result and snapshot are delivered.
        func sourceChanged() { reported = false }

        func observe(_ c: MetalPreviewController) {
            // Fire once when compile resolves (valid true, or an error string appears).
            c.$compileValid
                .combineLatest(c.$compileError)
                .sink { [weak self] valid, error in
                    guard let self, !self.reported else { return }
                    if valid {
                        self.reported = true
                        self.onCompile(true, nil)
                        // A frozen (paused) card won't redraw on its own — push one on-screen frame so
                        // it shows the compiled result rather than the pre-compile black frame.
                        if !self.animating { self.controller.drawOneFrame() }
                        // renderOnce() commits without waiting for GPU completion — intentional:
                        // CoreImage on the same MTLDevice serializes against it, and a blocking
                        // wait here would stall the main thread for a cosmetic 24×16 swatch.
                        if let onSnapshot = self.onSnapshot,
                           let tex = self.controller.renderOnce(),
                           let img = TextureSnapshot.cgImage(from: tex) {
                            onSnapshot(img)
                        }
                    } else if let error, !error.isEmpty {
                        self.reported = true
                        self.onCompile(false, error)
                    }
                }
                .store(in: &bag)
        }
    }
}
