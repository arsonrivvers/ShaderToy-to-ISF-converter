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

    /// Image-input names on the current shader, in declaration order (drives the UI).
    @Published private(set) var imageInputNames: [String] = []
    @Published private(set) var selections: [String: SourceSelection] = [:]
    private var sources: [String: ImageSource] = [:]

    init(device: MTLDevice, queue: MTLCommandQueue) {
        self.device = device
        self.queue = queue
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
            return defaultPatternSource()   // Slice 3 replaces this with the shared CameraSource.
        }
    }

    /// Fallback source — never black-screen. The default SMPTE test pattern, or NoneSource only if
    /// even that fails to build (should never happen; catalog tests guard the bundled patterns).
    private func defaultPatternSource() -> ImageSource {
        let p = TestPatternCatalog.default
        return ISFSceneSource(displayName: p.name, sourceText: p.sourceText, device: device, queue: queue) ?? NoneSource()
    }
}
