import SwiftUI
import Combine
import ShadertoyISFKit

/// Orchestrates the open document, the code editor, and the live preview.
/// Open/edit → (debounced) recompile → {preview render, input controls, gutter diagnostics}.
@MainActor
final class EditorViewModel: ObservableObject {
    @Published var file: ISFFile
    @Published var conversionWarnings: [ConversionWarning] = []
    /// Post-import conversion report (shown once over the editor). nil = no report to show.
    @Published var conversionReportTitle: String?
    @Published var statusMessage: String = ""
    /// Set by the "New from Shadertoy…" command; the editor screen presents the sheet.
    @Published var requestImport = false
    /// Bumped every time a DIFFERENT document replaces the current one (open/new/import/example) —
    /// NOT on recompiles of the same document. EditorScreen keys the controls panel's identity on
    /// this (M30): per-input control state must reset when the shader changes (same-named inputs
    /// on the new shader otherwise show the previous shader's stale values), but must SURVIVE the
    /// per-keystroke recompiles of normal editing.
    @Published private(set) var documentGeneration = 0

    // Output dimensions. `fitToWindow` = render at the preview pane size (default);
    // otherwise render at renderWidth × renderHeight (becomes RENDERSIZE).
    // 1920×1080 default: VJ-standard 16:9 — in fit mode the ASPECT is what shows on load.
    @Published var fitToWindow = true
    @Published var renderWidth = 1920
    @Published var renderHeight = 1080

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
    /// Drives the Inputs/Passes authoring tabs; kept in sync with `file.source` both ways.
    let headerModel = HeaderAuthoringModel()

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
        // GUI authoring (Inputs/Passes) writes the header back through `applyHeaderRewrite`; the
        // editor.setText it does NOT re-fire onChange, so there's no sync feedback loop.
        headerModel.onRewrite = { [weak self] newSource in self?.applyHeaderRewrite(newSource) }
        // Feed declared input names to the editor so autocomplete offers the shader's own uniforms.
        headerModel.$header
            .map { $0.inputs.map(\.name) }
            .removeDuplicates()
            .sink { [weak self] names in self?.editor.setInputNames(names) }
            .store(in: &cancellables)
        editor.setText(self.file.source)
        headerModel.syncFromText(self.file.source)
        recompile(immediate: true)
    }

    /// A header-authoring GUI edit produced new full source: adopt it, push it to the editor (no echo),
    /// and recompile. The header model already holds the matching parsed header.
    private func applyHeaderRewrite(_ newSource: String) {
        file.source = newSource
        editor.setText(newSource)
        recompile(immediate: false)
    }

    // MARK: document lifecycle

    /// Asked before anything replaces a dirty document (the library list is selection-driven, so a
    /// single stray click would otherwise destroy unsaved edits). Injectable for tests.
    var confirmDiscardIfDirty: () -> Bool = { EditorViewModel.askDiscardUnsavedChanges() }

    /// The one choke point every document-replacing path goes through.
    private func canReplaceDocument() -> Bool {
        if !file.isDirty { return true }
        if confirmDiscardIfDirty() { return true }
        statusMessage = "Kept unsaved changes"
        return false
    }

    private static func askDiscardUnsavedChanges() -> Bool {
        let alert = NSAlert()
        alert.messageText = "Discard unsaved changes?"
        alert.informativeText = "The current shader has unsaved edits. Replacing it will lose them."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Discard Changes")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    func open(_ entry: LibraryEntry) {
        guard canReplaceDocument() else { return }
        do {
            file = try ISFFile(contentsOf: entry.url)
            documentGeneration += 1
            conversionWarnings = []
            conversionReportTitle = nil
            statusMessage = "Opened \(file.displayName)"
            editor.setText(file.source)
            headerModel.syncFromText(file.source)
            recompile(immediate: true)
        } catch {
            statusMessage = "Couldn't open \(entry.name): \(error.localizedDescription)"
        }
    }

    func newUntitled() {
        guard canReplaceDocument() else { return }
        file = .untitled(source: Self.blankTemplate)
        documentGeneration += 1
        conversionWarnings = []
        conversionReportTitle = nil
        statusMessage = "New shader"
        editor.setText(file.source)
        headerModel.syncFromText(file.source)
        recompile(immediate: true)
    }

    /// Called by the Shadertoy import sheet on a successful conversion.
    func loadImported(isf: String, warnings: [ConversionWarning], suggestedName: String) {
        guard canReplaceDocument() else { return }
        file = .untitled(source: isf, suggestedName: suggestedName)
        documentGeneration += 1
        conversionWarnings = warnings
        conversionReportTitle = "Imported \(suggestedName)"
        statusMessage = "Imported \(suggestedName)"
        editor.setText(isf)
        headerModel.syncFromText(isf)
        // No pre-compile applyDiagnostics here: the source just changed, so preview's compile state is
        // stale. recompile(immediate:) below triggers a fresh compile whose result flows back through
        // the compileError/compileValid sink → applyDiagnostics with the new conversionWarnings merged.
        recompile(immediate: true)
    }

    /// Open a bundled example shader as a fresh untitled document (no conversion report).
    func loadExample(name: String, source: String) {
        guard canReplaceDocument() else { return }
        file = .untitled(source: source, suggestedName: name)
        documentGeneration += 1
        conversionWarnings = []
        conversionReportTitle = nil
        statusMessage = "Opened example: \(name)"
        editor.setText(source)
        headerModel.syncFromText(source)
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

    // MARK: fix apply

    /// Apply a fix-suggestion's edit through the editor, guarded so a stale edit can't corrupt the file.
    func apply(_ edit: TextEdit) {
        let lines = file.source.components(separatedBy: "\n")
        if let expect = edit.expectedContains {
            let idx = edit.fromLine - 1
            guard idx >= 0, idx < lines.count, lines[idx].contains(expect) else {
                statusMessage = "Couldn't apply automatically — the shader changed. Apply the fix manually."
                return
            }
        }
        editor.applyTextEdit(fromLine: edit.fromLine, toLine: edit.toLine, edit.replacement)
        statusMessage = "Applied fix"
    }

    /// Replace the full editor source after a user-approved ShaderAssist diff.
    func replaceSourceFromAssist(_ source: String, status: String = "Applied ShaderAssist suggestions") {
        file.source = source
        editor.setText(source)
        headerModel.syncFromText(source)
        recompile(immediate: true)
        statusMessage = status
    }

    // MARK: recompile loop

    private func sourceEdited(_ text: String) {
        file.source = text          // marks dirty
        headerModel.syncFromText(text)   // reflect hand edits into the Inputs/Passes tabs
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
