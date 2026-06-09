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
                        Button { output.show(source: vm.file.source) } label: {
                            Image(systemName: "rectangle.portrait.and.arrow.forward")
                        }
                        .help("Pop out the output into its own window")
                    }
                    .padding(6)
                    ISFPreviewView(webView: vm.preview.webView)
                        .frame(minHeight: 220)
                    Divider()
                    PreviewControlsView(controller: vm.preview)
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
        .onAppear { if library.sources.isEmpty { library.loadStandardLibraries() } }
        .onChange(of: vm.file.source) { src in output.update(source: src) }
        .sheet(isPresented: $vm.requestImport) {
            ShadertoyImportSheet { isf, warnings, name in
                vm.loadImported(isf: isf, warnings: warnings, suggestedName: name)
            }
        }
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
