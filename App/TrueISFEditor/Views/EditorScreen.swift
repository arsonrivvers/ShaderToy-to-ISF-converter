import SwiftUI
import ShadertoyISFKit

/// The TrueISFEditor main window: library sidebar | editor + warnings | preview + controls.
struct EditorScreen: View {
    @ObservedObject var library: LibraryModel
    @ObservedObject var vm: EditorViewModel
    @StateObject private var output = OutputWindowManager()
    @StateObject private var shaderAssist = ShaderAssistViewModel()
    @AppStorage("editorCollapsed") private var editorCollapsed = false
    @State private var showTerminal = true
    @State private var showSuggestionGoalSheet = false

    var body: some View {
        NavigationSplitView {
            LibraryView(library: library, vm: vm, addFolder: addFolder)
                .navigationSplitViewColumnWidth(min: 200, ideal: 240)
        } detail: {
            HSplitView {
                // Center: editor over warnings (collapsible — A1).
                if !editorCollapsed {
                    VStack(spacing: 0) {
                        if let reportTitle = vm.conversionReportTitle {
                            ConversionReportPanel(
                                title: reportTitle,
                                summary: ConversionReportSummary.line(
                                    source: "Shader", warnings: vm.conversionWarnings),
                                warnings: vm.conversionWarnings,
                                onDismiss: { vm.conversionReportTitle = nil })
                                .padding(6)
                            Divider()
                        }
                        CodeEditorView(controller: vm.editor)
                            .frame(minWidth: 360)
                        Divider()
                        DiagnosticsPanel(
                            diagnostics: vm.diagnostics.diagnostics,
                            sourceLines: vm.file.source.components(separatedBy: "\n"),
                            onJump: { vm.editor.revealLine($0) },
                            onApply: { vm.apply($0) })
                            .frame(height: 150)
                            .padding(6)
                        Divider()
                        shaderAssistSection
                            .padding(6)
                    }
                }
                // Right: preview + input controls.
                VStack(spacing: 0) {
                    HStack {
                        Button {
                            editorCollapsed.toggle()
                        } label: {
                            Image(systemName: editorCollapsed ? "sidebar.left" : "sidebar.squares.left")
                        }
                        .help(editorCollapsed ? "Show the code editor (⌘⌥E)" : "Hide the code editor (⌘⌥E)")
                        Text(vm.file.displayName).font(.headline)
                        if vm.file.isDirty { Text("•").foregroundStyle(.secondary) }
                        Spacer()
                        RenderStatsSlot(coordinator: vm.preview)
                        Button {
                            output.show(source: vm.file.source)
                            applyResolution()
                            output.syncSelections(from: vm.preview.imageSources)
                        } label: {
                            Image(systemName: "rectangle.portrait.and.arrow.forward")
                        }
                        .help("Pop out the output into its own window")
                    }
                    .padding(6)
                    renderControlsBar
                        .padding(.horizontal, 6)
                        .padding(.bottom, 4)
                    // Preview over controls with a user-draggable divider — the controls panel
                    // gets real vertical space (a fixed 210pt strip hid all but ~4 sliders).
                    VSplitView {
                        ISFPreviewView(coordinator: vm.preview)
                            .frame(minHeight: 200, maxHeight: .infinity)
                        HeaderPanelView(coordinator: vm.preview, model: vm.headerModel)
                            .frame(minHeight: 180, maxHeight: .infinity)
                    }
                }
                .frame(minWidth: 320)
            }
            .overlay(alignment: .bottom) {
                if !vm.statusMessage.isEmpty {
                    Text(vm.statusMessage)
                        .font(.caption).foregroundStyle(.secondary)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(.thinMaterial, in: Capsule())
                        .padding(.bottom, 6)
                }
            }
        }
        .frame(minWidth: 1120, minHeight: 700)
        .onAppear {
            if library.sources.isEmpty { library.loadStandardLibraries() }
            applyResolution()
        }
        .onChange(of: vm.file.source) { src in output.update(source: src) }
        .onChange(of: vm.fitToWindow) { _ in applyResolution() }
        .onChange(of: vm.renderWidth) { _ in applyResolution() }
        .onChange(of: vm.renderHeight) { _ in applyResolution() }
        .onReceive(vm.preview.imageSources.$selections) { _ in
            if output.isOpen { output.syncSelections(from: vm.preview.imageSources) }
        }
        .sheet(isPresented: $vm.requestImport) {
            ShadertoyImportSheet { isf, warnings, name in
                vm.loadImported(isf: isf, warnings: warnings, suggestedName: name)
            }
        }
        .sheet(isPresented: $showSuggestionGoalSheet) {
            SuggestionGoalSheet(model: shaderAssist,
                                source: vm.file.source,
                                diagnostics: vm.diagnostics.diagnostics) { ideas in
                shaderAssist.applySelectedGoals(ideas, source: vm.file.source,
                                                diagnostics: vm.diagnostics.diagnostics)
            }
        }
    }

    /// Opens the app Settings scene. SettingsLink is macOS 14+; fall back to the AppKit selector on 13.
    @ViewBuilder private var settingsGearButton: some View {
        if #available(macOS 14.0, *) {
            SettingsLink { Image(systemName: "gearshape") }
        } else {
            Button {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            } label: { Image(systemName: "gearshape") }
        }
    }

    /// AI assistant controls + result panel, below the diagnostics list in the center column.
    private var shaderAssistSection: some View {
        let running: Bool = { if case .running = shaderAssist.state { return true } else { return false } }()
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Button("Diagnose & Fix") {
                    shaderAssist.run(.diagnoseAndFix, source: vm.file.source,
                                     diagnostics: vm.diagnostics.diagnostics)
                }.disabled(running)
                Button("Suggestions") {
                    showSuggestionGoalSheet = true
                }.disabled(running)
                if running {
                    ProgressView().controlSize(.small)
                    Button("Cancel") { shaderAssist.cancel() }
                }
                Spacer()
                settingsGearButton
                    .help("ShaderAssist settings — provider, model, login")
            }
            Text(shaderAssist.providerCaption.isEmpty
                 ? "Runs on your Claude or Codex subscription · ISF skills loaded"
                 : shaderAssist.providerCaption)
                .font(.caption2).foregroundStyle(.secondary)

            if running || !shaderAssist.transcript.isEmpty {
                DisclosureGroup(isExpanded: $showTerminal) {
                    AssistTerminalView(lines: shaderAssist.transcript)
                        .frame(height: 120)
                } label: {
                    Text("Activity").font(.caption2).foregroundStyle(.secondary)
                }
            }

            switch shaderAssist.state {
            case .idle, .running:
                EmptyView()
            case .fix(let r):
                DiffReviewPanel(result: r,
                                sourceLines: vm.file.source.components(separatedBy: "\n"),
                                handled: $shaderAssist.handledEdits) { edit in
                    vm.apply(ShaderAssistViewModel.textEdit(from: edit, source: vm.file.source))
                }
                .frame(maxHeight: 280)
            case .suggestionGoals:
                EmptyView()
            case .suggestions(let r):
                SuggestionsPanel(result: r,
                                 selectedIDs: shaderAssist.selectedIdeaIDs,
                                 onToggle: { shaderAssist.toggleIdeaSelection($0) },
                                 onJump: { vm.editor.revealLine($0) },
                                 onApply: { shaderAssist.applySelectedSuggestions(source: vm.file.source) },
                                 onRerun: {
                                     shaderAssist.rerunSuggestions(source: vm.file.source,
                                                                   diagnostics: vm.diagnostics.diagnostics)
                                 },
                                 onChangeGoal: { showSuggestionGoalSheet = true },
                                 onStartOver: {
                                     shaderAssist.startSuggestionFlowOver()
                                     showSuggestionGoalSheet = true
                                 })
                .frame(maxHeight: 280)
            case .applyPreview(let r):
                ApplyPreviewPanel(originalSource: vm.file.source,
                                  result: r,
                                  onApply: {
                                      shaderAssist.confirmApplyPreview(currentSource: vm.file.source) { replacement in
                                          vm.replaceSourceFromAssist(replacement)
                                      }
                                  },
                                  onDiscard: { shaderAssist.discardApplyPreview() })
                .frame(maxHeight: 320)
            case .rawAnswer(let s):
                ScrollView {
                    Text(s).font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }.frame(maxHeight: 280)
            case .error(let m):
                Text(m).font(.caption).foregroundStyle(.red).textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Responsive render toolbar (A2): one row when it fits, wraps to two rows when the preview column
    /// is narrow — nothing is ever clipped or hidden.
    private var renderControlsBar: some View {
        // ViewThatFits picks the FIRST child that fits the proposed width. The measured children must
        // NOT contain a flexible Spacer (a Spacer lets a row shrink to any width, so it always "fits"
        // and never wraps). So each variant has a definite content width; the bar is left-aligned and
        // wraps mobile-style as the column narrows.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) { sizeControls; sourceAndRenderer }            // one row when it fits
            VStack(alignment: .leading, spacing: 4) {                         // two rows when narrower
                HStack(spacing: 6) { sizeControls }
                HStack(spacing: 6) { sourceAndRenderer }
            }
            VStack(alignment: .leading, spacing: 4) {                         // three rows when narrowest
                HStack(spacing: 6) { sizeControls }
                SourceToolbarControl(router: vm.preview.imageSources, library: library)
                rendererPicker
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .font(.caption)
        .textFieldStyle(.roundedBorder)
    }

    @ViewBuilder private var sizeControls: some View {
        Toggle("Fit", isOn: $vm.fitToWindow).toggleStyle(.checkbox)
        TextField("W", value: $vm.renderWidth, format: .number)
            .frame(width: 52).disabled(vm.fitToWindow)
        Text("×").foregroundStyle(.secondary)
        TextField("H", value: $vm.renderHeight, format: .number)
            .frame(width: 52).disabled(vm.fitToWindow)
        Button("÷2") { vm.halveRenderSize() }
        Button("×2") { vm.doubleRenderSize() }
    }

    @ViewBuilder private var sourceAndRenderer: some View {
        SourceToolbarControl(router: vm.preview.imageSources, library: library)
        rendererPicker
    }

    @ViewBuilder private var rendererPicker: some View {
        Picker("Renderer", selection: Binding(get: { vm.preview.active }, set: { vm.preview.active = $0 })) {
            Text("Metal").tag(PreviewCoordinator.Engine.metal)
            Text("WebKit").tag(PreviewCoordinator.Engine.webkit)
        }
        .pickerStyle(.segmented)
        .fixedSize()
        .help("Metal = VDMX-fidelity (ES3). WebKit = legacy WebGL1 fallback.")
    }

    /// Push the current output dimensions (always W×H + fit flag) to the inline preview and pop-out.
    private func applyResolution() {
        vm.preview.setRenderSize(width: vm.renderWidth, height: vm.renderHeight, fitToWindow: vm.fitToWindow)
        output.setRenderSize(width: vm.renderWidth, height: vm.renderHeight, fitToWindow: vm.fitToWindow)
    }

    private func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Add Folder"
        if panel.runModal() == .OK, let url = panel.url { library.addFolder(url) }
    }
}
