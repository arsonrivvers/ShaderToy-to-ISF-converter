import SwiftUI

/// The TrueISFEditor main window: library sidebar | editor + warnings | preview + controls.
struct EditorScreen: View {
    @ObservedObject var library: LibraryModel
    @ObservedObject var vm: EditorViewModel
    @StateObject private var output = OutputWindowManager()

    var body: some View {
        NavigationSplitView {
            LibraryView(library: library, vm: vm, addFolder: addFolder)
                .navigationSplitViewColumnWidth(min: 200, ideal: 240)
        } detail: {
            HSplitView {
                // Center: editor over warnings.
                VStack(spacing: 0) {
                    CodeEditorView(controller: vm.editor)
                        .frame(minWidth: 360)
                    Divider()
                    WarningsView(warnings: vm.conversionWarnings,
                                 previewError: vm.preview.compileValid ? nil : vm.preview.compileError,
                                 previewErrorLine: vm.preview.compileErrorLine)
                        .frame(height: 150)
                        .padding(6)
                }
                // Right: preview + input controls.
                VStack(spacing: 0) {
                    HStack {
                        Text(vm.file.displayName).font(.headline)
                        if vm.file.isDirty { Text("•").foregroundStyle(.secondary) }
                        Spacer()
                        Button { output.show(source: vm.file.source); applyResolution() } label: {
                            Image(systemName: "rectangle.portrait.and.arrow.forward")
                        }
                        .help("Pop out the output into its own window")
                    }
                    .padding(6)
                    renderControlsBar
                        .padding(.horizontal, 6)
                        .padding(.bottom, 4)
                    ISFPreviewView(coordinator: vm.preview)
                        .frame(minHeight: 220)
                    Divider()
                    PreviewControlsView(coordinator: vm.preview)
                        .frame(height: 170)
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
        .sheet(isPresented: $vm.requestImport) {
            ShadertoyImportSheet { isf, warnings, name in
                vm.loadImported(isf: isf, warnings: warnings, suggestedName: name)
            }
        }
    }

    private var renderControlsBar: some View {
        HStack(spacing: 6) {
            Toggle("Fit", isOn: $vm.fitToWindow).toggleStyle(.checkbox)
            TextField("W", value: $vm.renderWidth, format: .number)
                .frame(width: 52).disabled(vm.fitToWindow)
            Text("×").foregroundStyle(.secondary)
            TextField("H", value: $vm.renderHeight, format: .number)
                .frame(width: 52).disabled(vm.fitToWindow)
            Button("÷2") { vm.halveRenderSize() }
            Button("×2") { vm.doubleRenderSize() }
            Spacer()
            Picker("Renderer", selection: Binding(get: { vm.preview.active }, set: { vm.preview.active = $0 })) {
                Text("Metal").tag(PreviewCoordinator.Engine.metal)
                Text("WebKit").tag(PreviewCoordinator.Engine.webkit)
            }
            .pickerStyle(.segmented)
            .frame(width: 160)
            .help("Metal = VDMX-fidelity (ES3). WebKit = legacy WebGL1 fallback.")
        }
        .font(.caption)
        .textFieldStyle(.roundedBorder)
    }

    /// Push the current output dimensions to both the inline preview and the pop-out window.
    private func applyResolution() {
        let w: Int? = vm.fitToWindow ? nil : vm.renderWidth
        let h: Int? = vm.fitToWindow ? nil : vm.renderHeight
        vm.preview.setRenderSize(width: w, height: h)
        output.setRenderSize(width: w, height: h)
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
