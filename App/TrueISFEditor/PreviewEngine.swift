import AppKit
import Combine

/// Shared surface implemented by both preview engines. A later coordinator binds to
/// concrete engines (which keep their own @Published fields) and re-publishes state.
@MainActor
protocol PreviewEngine: AnyObject {
    var compileValid: Bool { get }
    var compileError: String? { get }
    var compileErrorLine: Int? { get }
    var inputs: [ISFPreviewInput] { get }
    var nsView: NSView { get }
    /// Per-image-input source routing for filter shaders. Only the Metal engine consults it when
    /// rendering; WebKit holds an inert one.
    var imageSources: SourceRouter { get }

    func load(isf: String)
    func setInput(_ name: String, _ jsonValue: String)
    /// `width`/`height` are always the target resolution (and thus the aspect ratio to preserve).
    /// `fitToWindow` true ⇒ render the largest W×H-aspect rect that fits the view (crisp, letterboxed);
    /// false ⇒ render at exactly width×height (also letterboxed into the view, never distorted).
    func setRenderSize(width: Int, height: Int, fitToWindow: Bool)

    /// Publisher the coordinator subscribes to so it can re-publish this engine's compile state.
    var compileStateWillChange: ObservableObjectPublisher { get }

    /// Live FPS / GPU-ms readout model, if this engine measures one (Metal does; WebKit doesn't).
    var liveRenderStats: RenderStatsModel? { get }

    /// Fire an ISF `event` input for one frame.
    func pulseEvent(_ name: String)

    /// B1c: called after a successful compile installs a fresh scene — the hook the ParamStore
    /// uses to replay user values (a new scene boots at header defaults).
    var onSceneInstalled: (() -> Void)? { get set }

    /// B2: restart shader time at 0 (document switch / explicit reset). Engines whose clock is
    /// per-load (WebKit) may no-op.
    func resetTimeline()

    /// D0: pause/resume this engine's live render loop (GPU work + clock). Engines without a
    /// pausable loop no-op.
    func setPaused(_ paused: Bool)
}

extension PreviewEngine {
    var liveRenderStats: RenderStatsModel? { nil }

    /// Default: engines with per-load clocks (WebKit resets on every load) have nothing to do.
    func resetTimeline() {}

    /// Default (WebKit path): no pausable loop to stop.
    func setPaused(_ paused: Bool) {}

    /// Default (WebKit path): JSON true now, false on the next main-actor turn. With a render loop
    /// that may not draw between those turns this can drop the pulse (M34) — engines with real
    /// momentary event values override.
    func pulseEvent(_ name: String) {
        setInput(name, "true")
        Task { @MainActor [weak self] in self?.setInput(name, "false") }
    }
}
