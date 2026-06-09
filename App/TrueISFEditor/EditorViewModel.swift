import SwiftUI
import Combine
import ShadertoyISFKit

/// Orchestrates the open document, the code editor, and the live preview.
/// Open/edit → (debounced) recompile → {preview render, input controls, gutter diagnostics}.
@MainActor
final class EditorViewModel: ObservableObject {
    @Published var file: ISFFile
    @Published var conversionWarnings: [ConversionWarning] = []
    @Published var statusMessage: String = ""
    /// Set by the "New from Shadertoy…" command; the editor screen presents the sheet.
    @Published var requestImport = false

    // Output dimensions. `fitToWindow` = render at the preview pane size (default);
    // otherwise render at renderWidth × renderHeight (becomes RENDERSIZE).
    @Published var fitToWindow = true
    @Published var renderWidth = 640
    @Published var renderHeight = 480

    func halveRenderSize() {
        renderWidth = max(1, renderWidth / 2); renderHeight = max(1, renderHeight / 2)
        fitToWindow = false
    }
    func doubleRenderSize() {
        renderWidth *= 2; renderHeight *= 2
        fitToWindow = false
    }

    let preview = PreviewCoordinator(metal: MetalPreviewController(), webkit: WebKitPreviewController())
    let editor = CodeEditorController()
    let diagnostics = DiagnosticsModel()

    private var debounceTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    static let blankTemplate = """
    /*{
      "DESCRIPTION": "New ISF shader",
      "CATEGORIES": ["Generator"],
      "INPUTS": []
    }*/

    void main() {
        gl_FragColor = vec4(isf_FragNormCoord, 0.0, 1.0);
    }
    """

    init(file: ISFFile? = nil) {
        self.file = file ?? .untitled(source: Self.blankTemplate)
        editor.onChange = { [weak self] text in self?.sourceEdited(text) }
        // Nested ObservableObject: forward its changes so the diagnostics panel re-renders.
        diagnostics.objectWillChange
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &cancellables)
        // Preview compile result → inline editor diagnostics. (Inputs flow to the controls
        // panel automatically via preview.inputs / @ObservedObject.)
        preview.$compileError
            .combineLatest(preview.$compileErrorLine, preview.$compileValid)
            .receive(on: RunLoop.main)
            .sink { [weak self] err, line, valid in self?.applyDiagnostics(error: err, line: line, valid: valid) }
            .store(in: &cancellables)
        editor.setText(self.file.source)
        recompile(immediate: true)
    }

    // MARK: document lifecycle

    func open(_ entry: LibraryEntry) {
        do {
            file = try ISFFile(contentsOf: entry.url)
            conversionWarnings = []
            statusMessage = "Opened \(file.displayName)"
            editor.setText(file.source)
            recompile(immediate: true)
        } catch {
            statusMessage = "Couldn't open \(entry.name): \(error.localizedDescription)"
        }
    }

    func newUntitled() {
        file = .untitled(source: Self.blankTemplate)
        conversionWarnings = []
        statusMessage = "New shader"
        editor.setText(file.source)
        recompile(immediate: true)
    }

    /// Called by the Shadertoy import sheet on a successful conversion.
    func loadImported(isf: String, warnings: [ConversionWarning], suggestedName: String) {
        file = .untitled(source: isf)
        conversionWarnings = warnings
        statusMessage = "Imported \(suggestedName)"
        editor.setText(isf)
        applyDiagnostics(error: preview.compileError, line: preview.compileErrorLine, valid: preview.compileValid)
        recompile(immediate: true)
    }

    // MARK: save

    var needsSaveAs: Bool { file.needsSaveAs }
    func saveInPlace() {
        do { try file.save(); statusMessage = "Saved \(file.displayName)" }
        catch { statusMessage = "Save failed: \(error.localizedDescription)" }
    }
    func saveAs(_ url: URL) {
        do { try file.save(to: url); statusMessage = "Saved \(file.displayName)" }
        catch { statusMessage = "Save failed: \(error.localizedDescription)" }
    }

    // MARK: recompile loop

    private func sourceEdited(_ text: String) {
        file.source = text          // marks dirty
        recompile(immediate: false)
    }

    private func recompile(immediate: Bool) {
        debounceTask?.cancel()
        let src = file.source
        if immediate { preview.load(isf: src); return }
        debounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            if Task.isCancelled { return }
            self?.preview.load(isf: src)
        }
    }

    private func applyDiagnostics(error: String?, line: Int?, valid: Bool) {
        diagnostics.update(converterWarnings: conversionWarnings,
                           compileError: valid ? nil : error, compileErrorLine: line)
        editor.setDiagnostics(diagnostics.editorDiagnostics)
    }
}
