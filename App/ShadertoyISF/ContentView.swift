import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var model = AppModel()
    @State private var showSettings = false

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                TextField("Paste a Shadertoy URL or ID…", text: $model.urlText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { Task { await model.convert() } }
                Button("Convert") { Task { await model.convert() } }
                    .disabled(model.isBusy)
                Button { showSettings = true } label: { Image(systemName: "gearshape") }
            }
            if !model.statusMessage.isEmpty {
                Text(model.statusMessage).font(.callout).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            DisclosureGroup("Or paste shader code (Image tab) — works without fetching") {
                VStack(spacing: 6) {
                    TextEditor(text: $model.pastedCode)
                        .font(.system(.body, design: .monospaced))
                        .frame(height: 120)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(.quaternary))
                    HStack {
                        Spacer()
                        Button("Convert pasted code") { Task { await model.convertPastedCode() } }
                            .disabled(model.pastedCode.isEmpty)
                    }
                }
                .padding(.top, 4)
            }
            HSplitView {
                ImportedCodeView(code: model.importedCode)
                ISFOutputView(text: $model.isfOutput)
            }
            WarningsView(warnings: model.warnings).frame(height: 140)
            HStack {
                Spacer()
                Button("Copy") { copyOutput() }.disabled(model.isfOutput.isEmpty)
                Button("Save .fs") { saveOutput() }.disabled(model.isfOutput.isEmpty)
            }
        }
        .padding(12)
        .frame(minWidth: 900, minHeight: 600)
        .sheet(isPresented: $showSettings) { SettingsView(model: model) }
    }

    private func copyOutput() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(model.isfOutput, forType: .string)
    }

    private func saveOutput() {
        let panel = NSSavePanel()
        panel.title = "Save ISF Shader"
        panel.nameFieldStringValue = model.suggestedFileName
        panel.canCreateDirectories = true
        if let fsType = UTType(filenameExtension: "fs") { panel.allowedContentTypes = [fsType] }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try model.isfOutput.write(to: url, atomically: true, encoding: .utf8)
            model.statusMessage = "Saved to \(url.path)"
        } catch {
            model.statusMessage = "Save failed: \(error.localizedDescription)"
        }
    }
}
