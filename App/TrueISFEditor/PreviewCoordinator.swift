import AppKit
import Combine

@MainActor
final class PreviewCoordinator: ObservableObject {
    enum Engine { case metal, webkit }

    @Published var active: Engine = .metal { didSet { if oldValue != active { switchEngine() } } }
    @Published private(set) var compileValid = false
    @Published private(set) var compileError: String?
    @Published private(set) var compileErrorLine: Int?
    @Published private(set) var inputs: [ISFPreviewInput] = []

    private let metal: PreviewEngine
    private let webkit: PreviewEngine
    private var currentSource: String?
    private var currentRenderSize: (width: Int, height: Int, fit: Bool) = (640, 480, true)
    private var sub: AnyCancellable?

    init(metal: PreviewEngine, webkit: PreviewEngine) {
        self.metal = metal; self.webkit = webkit
        subscribe()
    }

    var activeEngine: PreviewEngine { active == .metal ? metal : webkit }
    var nsView: NSView { activeEngine.nsView }
    var imageSources: SourceRouter { activeEngine.imageSources }
    /// Live FPS/GPU-ms model of the active engine (nil when the engine doesn't measure — WebKit).
    var renderStats: RenderStatsModel? { activeEngine.liveRenderStats }

    /// B1c: scene-install hook, kept on BOTH engines so an engine switch preserves the replay path.
    var onSceneInstalled: (() -> Void)? {
        didSet {
            metal.onSceneInstalled = onSceneInstalled
            webkit.onSceneInstalled = onSceneInstalled
        }
    }

    func load(isf: String) { currentSource = isf; activeEngine.load(isf: isf) }
    func setInput(_ name: String, _ jsonValue: String) { activeEngine.setInput(name, jsonValue) }
    func pulseEvent(_ name: String) { activeEngine.pulseEvent(name) }
    func setRenderSize(width: Int, height: Int, fitToWindow: Bool) {
        currentRenderSize = (width, height, fitToWindow)
        activeEngine.setRenderSize(width: width, height: height, fitToWindow: fitToWindow)
    }

    private func subscribe() {
        sub = activeEngine.compileStateWillChange
            .sink { [weak self] _ in
                guard let self else { return }
                // The signal is `objectWillChange` — it fires BEFORE the engine stores the new
                // value. A synchronous mirror here reads pre-store (stale) state, which left the
                // Adjust panel empty after a programmatic load until the next compile. Mirror now
                // (covers engines that signal post-store) AND on the next main-actor turn (covers
                // real @Published will-change ordering, where the value lands right after).
                self.mirror()
                Task { @MainActor in self.mirror() }
            }
        mirror()
    }
    private func mirror() {
        compileValid = activeEngine.compileValid
        compileError = activeEngine.compileError
        compileErrorLine = activeEngine.compileErrorLine
        inputs = activeEngine.inputs
    }
    private func switchEngine() {
        subscribe()
        activeEngine.setRenderSize(width: currentRenderSize.width, height: currentRenderSize.height,
                                   fitToWindow: currentRenderSize.fit)
        if let s = currentSource { activeEngine.load(isf: s) }
        objectWillChange.send()
    }
}
