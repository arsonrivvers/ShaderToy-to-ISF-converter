import Metal
import Combine
import ShadertoyISFKit

/// The user's chosen source for one image input. `.library` carries a file URL (Slice 2);
/// `.camera` (Slice 3) selects the shared camera source.
enum SourceSelection: Equatable {
    case none
    case testPattern(id: String)
    case library(url: URL)
    case camera
}

/// Owns the `[imageInputName: ImageSource]` map for the edited filter. Rebuilt when the shader's
/// image-input set changes. Lives in the Metal engine; views mutate it via `setSelection`.
@MainActor
final class SourceRouter: ObservableObject {
    private let device: MTLDevice
    private let queue: MTLCommandQueue
    private let injectedCamera: ImageSource?
    /// Prefer an injected camera (DI/tests); otherwise the process-wide shared capture session so
    /// inline preview and pop-out window share ONE AVCaptureSession.
    private lazy var sharedCamera: ImageSource? = injectedCamera ?? SharedCamera.make(device: device)

    /// Image-input names on the current shader, in declaration order (drives the UI).
    @Published private(set) var imageInputNames: [String] = []
    @Published private(set) var selections: [String: SourceSelection] = [:]
    private var sources: [String: ImageSource] = [:] {
        didSet {
            routesLock.lock()
            renderRoutes = sources
            routesLock.unlock()
        }
    }

    /// Lock-protected mirror of `sources` for the render thread. Kept in sync by `sources.didSet`
    /// (all writes are main-thread; the mirror exists so reads don't touch main-actor state).
    private let routesLock = NSLock()
    nonisolated(unsafe) private var renderRoutes: [String: ImageSource] = [:]

    /// Render-thread accessor: the live source for an input, or nil if unrouted. Called per frame
    /// by MetalRenderCore on the display-link thread.
    nonisolated func renderSource(for name: String) -> ImageSource? {
        routesLock.lock(); defer { routesLock.unlock() }
        return renderRoutes[name]
    }

    /// `camera` lets a single shared capture session be injected so inline + pop-out share one
    /// AVCaptureSession (and tests can inject a fake). Defaults to a per-router camera.
    init(device: MTLDevice, queue: MTLCommandQueue, camera: ImageSource? = nil) {
        self.device = device
        self.queue = queue
        self.injectedCamera = camera
    }

    /// Copy another router's selections onto this one (pop-out mirrors the inline preview's sources).
    func applySelections(from other: SourceRouter) {
        for (name, sel) in other.selections {
            setSelection(sel, for: name)
        }
    }

    /// Called by the engine on each successful compile. Adds defaults for new image inputs and
    /// prunes routes for inputs that no longer exist.
    func updateInputs(_ inputs: [ISFPreviewInput]) {
        let names = inputs.filter { $0.type == "image" }.map { $0.name }
        imageInputNames = names
        let nameSet = Set(names)
        selections = selections.filter { nameSet.contains($0.key) }
        sources = sources.filter { nameSet.contains($0.key) }
        for n in names where selections[n] == nil {
            selections[n] = SourceSelection.none
            sources[n] = NoneSource()
        }
    }

    func selection(for name: String) -> SourceSelection { selections[name] ?? .none }

    func setSelection(_ sel: SourceSelection, for name: String) {
        selections[name] = sel
        sources[name] = makeSource(sel)
    }

    /// The live source for an input (NoneSource if unrouted).
    func source(for name: String) -> ImageSource { sources[name] ?? NoneSource() }

    private func makeSource(_ sel: SourceSelection) -> ImageSource {
        switch sel {
        case .none:
            return NoneSource()   // user explicitly chose nothing — correct to leave unbound
        case .testPattern(let id):
            guard let p = TestPatternCatalog.pattern(id: id),
                  let s = ISFSceneSource(displayName: p.name, sourceText: p.sourceText, device: device, queue: queue)
            else { return defaultPatternSource() }
            return s
        case .library(let url):
            // Slice 2 wires the picker; a bad pick falls back to the default test pattern (never black).
            guard let text = try? String(contentsOf: url, encoding: .utf8),
                  let s = ISFSceneSource(displayName: url.lastPathComponent, sourceText: text, device: device, queue: queue)
            else { return defaultPatternSource() }
            return s
        case .camera:
            return sharedCamera ?? defaultPatternSource()   // camera unavailable ⇒ default pattern, never black
        }
    }

    /// Fallback source — never black-screen. The default SMPTE test pattern, or NoneSource only if
    /// even that fails to build (should never happen; catalog tests guard the bundled patterns).
    private func defaultPatternSource() -> ImageSource {
        let p = TestPatternCatalog.default
        return ISFSceneSource(displayName: p.name, sourceText: p.sourceText, device: device, queue: queue) ?? NoneSource()
    }
}
