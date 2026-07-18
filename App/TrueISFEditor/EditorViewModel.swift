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
    /// Set by the Versions… command / toolbar button; EditorScreen opens the embedded Versions tab.
    @Published var requestVersions = false
    /// Set after an AI rewrite until the user saves, edits, starts another run, or dismisses it.
    @Published private(set) var assistApplied = false

    func clearAssistNudge() { assistApplied = false }

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
    /// B4: capped — repeated doubling reached 30K×17K fixed-size renders and exhausted GPU memory
    /// (the texture pool retains every size ever used).
    static let maxRenderAxis = 8192
    func doubleRenderSize() {
        renderWidth = min(renderWidth * 2, Self.maxRenderAxis)
        renderHeight = min(renderHeight * 2, Self.maxRenderAxis)
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

    /// D1: version history. Injectable so tests point it at a temp directory.
    let snapshots: SnapshotStore
    /// Snapshot keys whose Save As migration could not finish. Kept only for the active document
    /// and retried after each later successful shader save; true document switches clear the queue
    /// so an old shader's timeline can never leak into the new one.
    private var pendingHistorySources: [ISFFile] = []

    init(file: ISFFile? = nil, snapshots: SnapshotStore? = nil) {
        self.snapshots = snapshots ?? SnapshotStore()
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
        // B1: param values live in the store; the store forwards to every render sink.
        paramStore.onSet = { [weak self] name, json in
            self?.preview.setInput(name, json)
            self?.outputParamSink?(name, json)
        }
        // B1c: a freshly installed scene boots at header defaults — resync + replay user values.
        // Engine inputs are read directly (the coordinator's mirror lands a turn later). Also the
        // pop-out feed point (B3): only compile-VALIDATED sources reach the output window, so it
        // never wastes a transpile on broken intermediate states.
        preview.onSceneInstalled = { [weak self] in
            guard let self else { return }
            self.paramStore.syncInputs(self.preview.activeEngine.inputs)
            self.paramStore.replayAll()
            self.onValidatedSource?(self.file.source)
        }
        editor.setText(self.file.source)
        headerModel.syncFromText(self.file.source)
        recompile(immediate: true)
        refreshVersionState()
    }

    // MARK: params (B1)

    /// The one store between the param UI and the render engines. Values survive recompiles and
    /// are replayed into freshly installed scenes (see the onSceneInstalled wiring).
    let paramStore = ParamStore()
    /// Set by EditorScreen when the pop-out window is open — the second render sink.
    var outputParamSink: ((String, String) -> Void)?
    var outputPulseSink: ((String) -> Void)?
    /// B3: fired with the source text whenever the inline compile succeeds — the pop-out's feed.
    var onValidatedSource: ((String) -> Void)?

    /// Momentary event pulse, forwarded to every open render window (events aren't stored).
    func pulseEvent(_ name: String) {
        preview.pulseEvent(name)
        outputPulseSink?(name)
    }

    // MARK: pop-out editing mode (D0)

    /// True while the output window is popped out: the inline preview pauses (GPU + clock) and
    /// EditorScreen collapses the preview pane so Adjust/Inputs/Passes gets the freed space.
    /// Intended use: output on a second monitor, laptop screen becomes a pure editing surface.
    @Published private(set) var popOutEditing = false

    /// Driven by EditorScreen from the output window's published isOpen.
    func setPopOutOpen(_ open: Bool) {
        guard popOutEditing != open else { return }
        popOutEditing = open
        preview.setPaused(open)
    }

    /// A header-authoring GUI edit produced new full source: adopt it, push it to the editor (no echo),
    /// and recompile. The header model already holds the matching parsed header.
    private func applyHeaderRewrite(_ newSource: String) {
        assistApplied = false
        file.source = newSource
        editor.setText(newSource)
        recompile(immediate: false)
    }

    // MARK: document lifecycle

    // Launch-readiness TODO: restore data-loss protection with a nonblocking sheet. The synchronous
    // discard-confirm modal was intentionally retired because it could deadlock the app and tests.

    func open(_ entry: LibraryEntry) {
        do {
            let currentDocumentKey = SnapshotStore.documentKey(for: file)
            let openedFile = try ISFFile(contentsOf: entry.url)
            file = openedFile
            if SnapshotStore.documentKey(for: openedFile) != currentDocumentKey {
                pendingHistorySources.removeAll()
            }
            assistApplied = false
            documentGeneration += 1
            conversionWarnings = []
            conversionReportTitle = nil
            // No "Opened <name>" toast — the filename is already in the header, and the toast
            // overlay was covering sliders. Clear any stale message instead.
            statusMessage = ""
            paramStore.resetAll(); preview.resetTimeline(); editor.resetText(file.source)
            headerModel.syncFromText(file.source)
            snapshots.capture(file: file, params: paramStore.exportSnapshot(), label: "Opened", kind: .safety)
            recompile(immediate: true)
            refreshVersionState()
        } catch {
            statusMessage = "Couldn't open \(entry.name): \(error.localizedDescription)"
        }
    }

    func newUntitled() {
        file = .untitled(source: Self.blankTemplate)
        pendingHistorySources.removeAll()
        assistApplied = false
        documentGeneration += 1
        conversionWarnings = []
        conversionReportTitle = nil
        statusMessage = "New shader"
        paramStore.resetAll(); preview.resetTimeline(); editor.resetText(file.source)
        headerModel.syncFromText(file.source)
        recompile(immediate: true)
        refreshVersionState()
    }

    /// Called by the Shadertoy import sheet on a successful conversion.
    func loadImported(isf: String, warnings: [ConversionWarning], suggestedName: String) {
        file = .untitled(source: isf, suggestedName: suggestedName)
        pendingHistorySources.removeAll()
        assistApplied = false
        documentGeneration += 1
        conversionWarnings = warnings
        conversionReportTitle = "Imported \(suggestedName)"
        statusMessage = "Imported \(suggestedName)"
        paramStore.resetAll(); preview.resetTimeline(); editor.resetText(isf)
        headerModel.syncFromText(isf)
        snapshots.capture(file: file, params: paramStore.exportSnapshot(), label: "Imported", kind: .safety)
        // No pre-compile applyDiagnostics here: the source just changed, so preview's compile state is
        // stale. recompile(immediate:) below triggers a fresh compile whose result flows back through
        // the compileError/compileValid sink → applyDiagnostics with the new conversionWarnings merged.
        recompile(immediate: true)
        refreshVersionState()
    }

    /// Open a bundled example shader as a fresh untitled document (no conversion report).
    func loadExample(name: String, source: String) {
        file = .untitled(source: source, suggestedName: name)
        pendingHistorySources.removeAll()
        assistApplied = false
        documentGeneration += 1
        conversionWarnings = []
        conversionReportTitle = nil
        statusMessage = ""   // name is in the header; no toast (it covered sliders)
        paramStore.resetAll(); preview.resetTimeline(); editor.resetText(source)
        headerModel.syncFromText(source)
        snapshots.capture(file: file, params: paramStore.exportSnapshot(), label: "Opened", kind: .safety)
        recompile(immediate: true)
        refreshVersionState()
    }

    // MARK: save

    var needsSaveAs: Bool { file.needsSaveAs }

    private func enqueueHistoryMigration(from sourceFile: ISFFile) {
        let sourceKey = SnapshotStore.documentKey(for: sourceFile)
        guard sourceKey != SnapshotStore.documentKey(for: file),
              !pendingHistorySources.contains(where: {
                  SnapshotStore.documentKey(for: $0) == sourceKey
              }) else { return }
        pendingHistorySources.append(sourceFile)
    }

    private func retryPendingHistoryMigrations() {
        let destinationFile = file
        pendingHistorySources = pendingHistorySources.filter { sourceFile in
            !snapshots.migrateHistory(from: sourceFile, to: destinationFile)
        }
    }

    func saveInPlace() {
        guard !file.needsSaveAs else { return }   // App routes untitled to Save As
        do {
            try file.save()
            retryPendingHistoryMigrations()
            mintSaveVersion()
        }
        catch { presentSaveError(error) }
    }
    func saveAs(_ url: URL) {
        let previousFile = file
        do {
            try file.save(to: url)
            enqueueHistoryMigration(from: previousFile)
            retryPendingHistoryMigrations()
            mintSaveVersion()
        }
        catch { presentSaveError(error) }
    }

    /// A4: a failed save is data loss pending — a 5s auto-clearing toast is not enough. Injectable
    /// for tests; normal app runs show a modal, while the XCTest host must never block on one.
    static func shouldPresentSaveErrorAlert(testHarnessActive: Bool = TestHarness.isActive) -> Bool {
        !testHarnessActive
    }

    var presentSaveErrorAlert: (Error) -> Void = { error in
        guard EditorViewModel.shouldPresentSaveErrorAlert() else { return }
        let alert = NSAlert()
        alert.messageText = "Save failed"
        alert.informativeText = "\(error.localizedDescription)\n\nYour changes are still in the editor. Try Save As… to a writable location."
        alert.alertStyle = .critical
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
    private func presentSaveError(_ error: Error) {
        statusMessage = "Save failed: \(error.localizedDescription)"
        presentSaveErrorAlert(error)
    }

    // MARK: versions (D1)

    // MARK: version state (cached — snapshots(for:) reads disk; never call it per-render)

    /// v-number the next save mints (drives the "⌘S saves vNN" pill).
    @Published private(set) var nextSaveVersion = 1
    /// Timeline length (drives the Versions tab badge).
    @Published private(set) var versionCount = 0
    /// Source of the newest `save` version — the change-gutter baseline (nil = no saves yet).
    private(set) var lastSaveSource: String?

    /// Re-read version state from the store. Call after anything that captures or switches document.
    func refreshVersionState() {
        let snaps = snapshots.snapshots(for: file)
        versionCount = snaps.count
        nextSaveVersion = (snaps.compactMap { snap -> Int? in
            if case .save(let n) = snap.kind { return n } else { return nil }
        }.max() ?? 0) + 1
        lastSaveSource = snaps.first { if case .save = $0.kind { return true } else { return false } }?.source
        updateChangeMarks()
    }

    /// Recompute gutter bars vs the last save. No saves yet ⇒ clear.
    private func updateChangeMarks() {
        guard let baseline = lastSaveSource else {
            editor.setChangeMarks(added: [], changed: [])
            return
        }
        let m = LineDiff.changeMarks(old: baseline, new: file.source)
        editor.setChangeMarks(added: m.added, changed: m.changed)
    }

    /// Pin the current editor state as a named version (Versions panel + button).
    func pin(name: String?) {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let clean = (trimmed?.isEmpty ?? true) ? nil : trimmed
        snapshots.capture(file: file, params: paramStore.exportSnapshot(),
                          label: clean ?? "Pinned", kind: .pin(name: clean))
        refreshVersionState()
        statusMessage = "Pinned \(clean ?? "current version")"
    }

    /// Successful save → mint the numbered version (dedup-aware status).
    private func mintSaveVersion() {
        let n = snapshots.nextSaveNumber(for: file)
        if let snap = snapshots.capture(file: file, params: paramStore.exportSnapshot(),
                                        label: String(format: "v%02d", n), kind: .save(number: n)) {
            statusMessage = "Saved \(file.displayName) — \(snap.displayTitle)"
        } else {
            statusMessage = "Saved \(file.displayName)"
        }
        assistApplied = false
        refreshVersionState()
    }

    /// Restore a snapshot: source + params. No discard confirmation — the current state is
    /// itself captured first, so restore is always undoable via the same list.
    func restore(_ snapshot: Snapshot) {
        snapshots.capture(file: file, params: paramStore.exportSnapshot(), label: "Before restore", kind: .safety)
        assistApplied = false
        file.source = snapshot.source
        editor.setText(snapshot.source)
        headerModel.syncFromText(snapshot.source)
        paramStore.applySnapshot(snapshot.params)
        recompile(immediate: true)
        statusMessage = "Restored version — \(snapshot.label), \(snapshot.date.formatted(date: .abbreviated, time: .shortened))"
        refreshVersionState()
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
        // D1: every AI mutation is preceded by a restorable version.
        snapshots.capture(file: file, params: paramStore.exportSnapshot(), label: "Before AI fix", kind: .aiApply)
        editor.applyTextEdit(fromLine: edit.fromLine, toLine: edit.toLine, edit.replacement)
        statusMessage = "Applied fix"
        refreshVersionState()
    }

    /// Replace the full editor source after a user-approved ShaderAssist diff.
    func replaceSourceFromAssist(_ source: String, status: String = "Applied ShaderAssist suggestions") {
        // D1: capture the PRE-apply state — every AI mutation is preceded by a restorable version.
        snapshots.capture(file: file, params: paramStore.exportSnapshot(), label: "Before AI rewrite", kind: .aiApply)
        file.source = source
        assistApplied = true
        editor.setText(source)
        headerModel.syncFromText(source)
        recompile(immediate: true)
        statusMessage = status
        refreshVersionState()
    }

    // MARK: recompile loop

    private func sourceEdited(_ text: String) {
        assistApplied = false
        file.source = text          // marks dirty
        headerModel.syncFromText(text)   // reflect hand edits into the Inputs/Passes tabs
        recompile(immediate: false)
    }

    /// Unit tests exercise document state, not the native transpiler. The XCTest app host creates
    /// many short-lived view models whose background compiles can outlive their tests and contend
    /// with the process-global ISFMSL cache. Dedicated native-preview tests call the controller
    /// directly, so they remain live while view-model tests stay isolated.
    static func shouldCompilePreview(testHarnessActive: Bool = TestHarness.isActive) -> Bool {
        !testHarnessActive
    }

    private func recompile(immediate: Bool) {
        debounceTask?.cancel()
        let src = file.source
        if immediate {
            if Self.shouldCompilePreview() { preview.load(isf: src) }
            return
        }
        let shouldCompilePreview = Self.shouldCompilePreview()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            if Task.isCancelled { return }
            if shouldCompilePreview { self?.preview.load(isf: src) }
            self?.updateChangeMarks()
        }
    }

    private func applyDiagnostics(error: String?, line: Int?, valid: Bool) {
        diagnostics.update(converterWarnings: conversionWarnings,
                           compileError: valid ? nil : error, compileErrorLine: line)
        editor.setDiagnostics(diagnostics.editorDiagnostics)
    }
}
