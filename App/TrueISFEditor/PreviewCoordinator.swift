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
    private var currentRenderSize: (Int?, Int?) = (nil, nil)
    private var sub: AnyCancellable?

    init(metal: PreviewEngine, webkit: PreviewEngine) {
        self.metal = metal; self.webkit = webkit
        subscribe()
    }

    var activeEngine: PreviewEngine { active == .metal ? metal : webkit }
    var nsView: NSView { activeEngine.nsView }
    var imageSources: SourceRouter { activeEngine.imageSources }

    func load(isf: String) { currentSource = isf; activeEngine.load(isf: isf) }
    func setInput(_ name: String, _ jsonValue: String) { activeEngine.setInput(name, jsonValue) }
    func setRenderSize(width: Int?, height: Int?) {
        currentRenderSize = (width, height)
        activeEngine.setRenderSize(width: width, height: height)
    }

    private func subscribe() {
        sub = activeEngine.compileStateWillChange
            .sink { [weak self] _ in self?.mirror() }
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
        activeEngine.setRenderSize(width: currentRenderSize.0, height: currentRenderSize.1)
        if let s = currentSource { activeEngine.load(isf: s) }
        objectWillChange.send()
    }
}
