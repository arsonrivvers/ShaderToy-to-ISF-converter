import SwiftUI
import ShadertoyISFKit

/// "New from Shadertoy…" — wraps the existing convert flow (URL fetch / paste, incl. multipass
/// markers). On a successful conversion it hands the ISF back to the editor as an untitled file.
struct ShadertoyImportSheet: View {
    var onImport: (_ isf: String, _ warnings: [ConversionWarning], _ suggestedName: String) -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = AppModel()
    @State private var showSettings = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("New from Shadertoy").font(.headline)
                Spacer()
                Button { showSettings = true } label: { Image(systemName: "gearshape") }
                    .help("Optional API key")
                Button("Close") { dismiss() }
            }

            HStack {
                TextField("Shadertoy URL or ID…", text: $model.urlText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { Task { await model.convert(); finishIfConverted() } }
                Button("Fetch & Convert") { Task { await model.convert(); finishIfConverted() } }
                    .disabled(model.isBusy)
            }

            Text("Fetching is best-effort (Cloudflare bot check). The reliable path is pasting the Image tab — for multipass, paste each tab under `// [Common]`, `// [Buffer A]`…`// [Image]` markers.")
                .font(.caption).foregroundStyle(.secondary)

            TextEditor(text: $model.pastedCode)
                .font(.system(.body, design: .monospaced))
                .frame(height: 170)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(.quaternary))

            HStack {
                if !model.statusMessage.isEmpty {
                    Text(model.statusMessage).font(.caption).foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer()
                Button("Convert pasted code") { Task { await model.convertPastedCode(); finishIfConverted() } }
                    .disabled(model.pastedCode.isEmpty)
            }
        }
        .padding(16)
        .frame(width: 640, height: 440)
        .sheet(isPresented: $showSettings) { SettingsView(model: model) }
    }

    private func finishIfConverted() {
        guard !model.isfOutput.isEmpty else { return }   // failed conversions leave isfOutput empty
        onImport(model.isfOutput, model.warnings, model.suggestedFileName)
        dismiss()
    }
}
