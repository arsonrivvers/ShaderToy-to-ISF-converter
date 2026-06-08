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
        panel.nameFieldStringValue = "converted.fs"
        if let fsType = UTType(filenameExtension: "fs") { panel.allowedContentTypes = [fsType] }
        if panel.runModal() == .OK, let url = panel.url {
            try? model.isfOutput.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
