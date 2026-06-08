import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var model = AppModel()
    @StateObject private var preview = ISFPreviewController()
    @State private var showSettings = false
    @State private var renderTask: Task<Void, Never>?

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

            // Compile status banner
            if preview.compileError != nil && !preview.compileValid {
                let firstLine = preview.compileError!.components(separatedBy: "\n").first ?? preview.compileError!
                Text("Preview: \(firstLine) (line \(preview.compileErrorLine ?? -1))")
                    .font(.caption)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.red.opacity(0.85))
                    .cornerRadius(4)
            } else if preview.compileValid {
                Text("Preview: compiles ✓")
                    .font(.caption)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.green.opacity(0.75))
                    .cornerRadius(4)
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
                VStack(spacing: 0) {
                    Text("Preview").font(.headline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.bottom, 4)
                    ISFPreviewView(webView: preview.webView)
                        .frame(minHeight: 200)
                    Divider()
                    PreviewControlsView(controller: preview)
                        .frame(height: 120)
                }
                .padding(4)
            }
            WarningsView(warnings: model.warnings).frame(height: 140)
            HStack {
                Spacer()
                Button("Copy") { copyOutput() }.disabled(model.isfOutput.isEmpty)
                Button("Save .fs") { saveOutput() }.disabled(model.isfOutput.isEmpty)
            }
        }
        .padding(12)
        .frame(minWidth: 1200, minHeight: 700)
        .sheet(isPresented: $showSettings) { SettingsView(model: model) }
        .onChange(of: model.isfOutput) { _ in scheduleRender() }
        .onAppear {
            if !model.isfOutput.isEmpty { preview.load(isf: model.isfOutput) }
        }
    }

    private func scheduleRender() {
        renderTask?.cancel()
        let isf = model.isfOutput
        guard !isf.isEmpty else { return }
        renderTask = Task {
            try? await Task.sleep(nanoseconds: 400_000_000)
            if Task.isCancelled { return }
            preview.load(isf: isf)
        }
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
