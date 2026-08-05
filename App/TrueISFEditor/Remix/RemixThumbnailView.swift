import SwiftUI
import AppKit
import Combine
import CoreGraphics

/// A small Metal preview of one child ISF. Hosts a `MetalPreviewController`, loads the source once,
/// and reports the compile outcome back via `onCompile`. When `animating` is false it renders a single
/// frozen frame instead of running continuously (performance cap from the studio model).
struct RemixThumbnailView: NSViewRepresentable {
    enum PausePolicy: Equatable {
        case renderLoopOnly
        case renderLoopAndClock
    }

    enum InputMutation: Equatable {
        case set(String, RemixParameterValue)
        case remove(String)
    }
    enum Report: Equatable {
        case pending
        case compileSuccess
        case compileFailure(String)
        case previewFailure(String)
    }

    let isf: String
    let animating: Bool
    var sharedClock: RenderClock? = nil
    var renderSize: RemixRenderSize? = nil
    var inputValues: [String: RemixParameterValue] = [:]
    var reloadAttempt: Int = 0
    /// Optional: receives one downscaled CGImage frame at first successful compile (tree swatches).
    var onSnapshot: ((CGImage) -> Void)? = nil
    var onPreviewFailure: ((String) -> Void)? = nil
    /// Called on the main actor with (valid, errorMessage) once the engine finishes compiling.
    let onCompile: (Bool, String?) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onCompile: onCompile,
            onSnapshot: onSnapshot,
            onPreviewFailure: onPreviewFailure,
            sharedClock: sharedClock
        )
    }

    func makeNSView(context: Context) -> NSView {
        let controller = context.coordinator.controller
        if let renderSize {
            controller.setRenderSize(width: renderSize.width, height: renderSize.height, fitToWindow: true)
        }
        context.coordinator.applyInputValues(inputValues, to: controller)
        context.coordinator.loadedISF = isf
        context.coordinator.loadedAttempt = reloadAttempt
        controller.load(isf: isf)
        context.coordinator.observe(controller)
        return controller.nsView
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        let controller = context.coordinator.controller
        context.coordinator.applyInputValues(inputValues, to: controller)
        let sourceChanged = context.coordinator.loadedISF != isf
        if Self.shouldReloadPreview(
            previousAttempt: context.coordinator.loadedAttempt,
            newAttempt: reloadAttempt,
            sourceChanged: sourceChanged
        ) {
            context.coordinator.loadedISF = isf
            context.coordinator.loadedAttempt = reloadAttempt
            context.coordinator.sourceChanged()   // re-arm the compile report for the new source
            controller.load(isf: isf)
        }
        // Freeze when not animating: PAUSE the loop (so GPU work actually stops) and show one frame —
        // but only on the animating→frozen TRANSITION. `updateNSView` runs on every model republish
        // (per transcript line during generation), so an unconditional draw forced one GPU frame per
        // paused card per line. (A frozen card's post-compile frame is pushed by the observe sink.)
        let wasAnimating = context.coordinator.animating
        context.coordinator.animating = animating
        switch Self.pausePolicy(hasSharedClock: sharedClock != nil) {
        case .renderLoopOnly:
            controller.setRenderLoopPaused(!animating)
        case .renderLoopAndClock:
            controller.setPaused(!animating)
        }
        if Self.shouldPushFrozenFrame(wasAnimating: wasAnimating, animating: animating) {
            controller.drawOneFrame()
        }
    }

    static func shouldPushFrozenFrame(wasAnimating: Bool, animating: Bool) -> Bool {
        wasAnimating && !animating
    }

    static func shouldReloadPreview(
        previousAttempt: Int,
        newAttempt: Int,
        sourceChanged: Bool
    ) -> Bool {
        sourceChanged || previousAttempt != newAttempt
    }

    static func pausePolicy(hasSharedClock: Bool) -> PausePolicy {
        hasSharedClock ? .renderLoopOnly : .renderLoopAndClock
    }

    static func classifyReport(hasCompiled: Bool, valid: Bool, error: String?) -> Report {
        if valid { return .compileSuccess }
        guard let error, !error.isEmpty else { return .pending }
        return hasCompiled ? .previewFailure(error) : .compileFailure(error)
    }

    @MainActor
    final class Coordinator {
        let controller: MetalPreviewController
        let onCompile: (Bool, String?) -> Void
        let onSnapshot: ((CGImage) -> Void)?
        let onPreviewFailure: ((String) -> Void)?
        var loadedISF: String?
        var loadedAttempt = 0
        var animating = true
        private var bag = Set<AnyCancellable>()
        private(set) var reported = false
        private var hasCompiled = false
        private var reportedPreviewFailure = false
        private var appliedInputValues: [String: RemixParameterValue] = [:]

        init(
            onCompile: @escaping (Bool, String?) -> Void,
            onSnapshot: ((CGImage) -> Void)?,
            onPreviewFailure: ((String) -> Void)? = nil,
            sharedClock: RenderClock? = nil
        ) {
            controller = MetalPreviewController(renderClock: sharedClock)
            self.onCompile = onCompile
            self.onSnapshot = onSnapshot
            self.onPreviewFailure = onPreviewFailure
        }

        /// SwiftUI recycles coordinators across node changes (LazyVGrid, tree slots) — re-arm the
        /// fire-once compile report so the NEW source's result and snapshot are delivered.
        func sourceChanged() {
            reported = false
            hasCompiled = false
            reportedPreviewFailure = false
        }

        func inputMutations(
            for newValues: [String: RemixParameterValue]
        ) -> [InputMutation] {
            let removed = appliedInputValues.keys
                .filter { newValues[$0] == nil }
                .sorted()
                .map(InputMutation.remove)
            let changed = newValues.keys
                .filter { appliedInputValues[$0] != newValues[$0] }
                .sorted()
                .compactMap { name in
                    newValues[name].map { InputMutation.set(name, $0) }
                }
            appliedInputValues = newValues
            return removed + changed
        }

        func applyInputValues(
            _ newValues: [String: RemixParameterValue],
            to sink: RemixPreviewInputApplying
        ) {
            inputMutations(for: newValues).forEach { mutation in
                switch mutation {
                case .set(let name, let value): sink.setRemixInput(name, value: value)
                case .remove(let name): sink.resetRemixInput(name)
                }
            }
        }

        func observe(_ c: MetalPreviewController) {
            // Fire once when compile resolves (valid true, or an error string appears).
            c.$compileValid
                .combineLatest(c.$compileError)
                .sink { [weak self] valid, error in
                    guard let self else { return }
                    switch RemixThumbnailView.classifyReport(
                        hasCompiled: self.hasCompiled,
                        valid: valid,
                        error: error
                    ) {
                    case .compileSuccess:
                        guard !self.reported else { return }
                        self.reported = true
                        self.hasCompiled = true
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
                    case .compileFailure(let message):
                        guard !self.reported else { return }
                        self.reported = true
                        self.onCompile(false, message)
                    case .previewFailure(let message):
                        guard !self.reportedPreviewFailure else { return }
                        self.reportedPreviewFailure = true
                        self.onPreviewFailure?(message)
                    case .pending:
                        break
                    }
                }
                .store(in: &bag)
        }
    }
}
