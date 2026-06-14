import SwiftUI
import ShadertoyISFKit

/// "New from Shadertoy…" — wraps the existing convert flow (URL fetch / paste, incl. multipass
/// markers). On a successful conversion it hands the ISF back to the editor as an untitled file.
struct ShadertoyImportSheet: View {
    var onImport: (_ isf: String, _ warnings: [ConversionWarning], _ suggestedName: String) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openWindow) private var openWindow
    @StateObject private var model = AppModel()
    @State private var showSettings = false
    @State private var showPasteHelp = false

    private static let multipassTemplate = """
    // [Common]
    // (optional) shared helper functions used by every tab

    // [Buffer A]
    // paste Shadertoy "Buffer A" tab code here

    // [Image]
    // paste Shadertoy "Image" tab code here
    """

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

            HStack(spacing: 6) {
                Text("Fetching is best-effort (Cloudflare bot check). The reliable path is pasting the Image tab — for multipass, use tab markers.")
                    .font(.caption).foregroundStyle(.secondary)
                Button { showPasteHelp = true } label: { Image(systemName: "questionmark.circle") }
                    .buttonStyle(.borderless)
                    .help("Show the multipass paste format")
                    .popover(isPresented: $showPasteHelp, arrowEdge: .bottom) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Multipass paste format").font(.headline)
                            Text("Paste each Shadertoy tab under a marker line. iChannelN maps to Buffer N.")
                                .font(.caption).foregroundStyle(.secondary)
                            Text(Self.multipassTemplate)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .padding(8)
                                .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
                            Button("Insert template") {
                                if model.pastedCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    model.pastedCode = Self.multipassTemplate
                                }
                                showPasteHelp = false
                            }
                        }
                        .padding(12).frame(width: 360)
                    }
            }

            TextEditor(text: $model.pastedCode)
                .font(.system(.body, design: .monospaced))
                .frame(height: 170)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(.quaternary))

            HStack {
                if !model.statusMessage.isEmpty {
                    Text(model.statusMessage).font(.caption).foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                if let last = model.lastImport {
                    Text(last.summaryLine)
                        .font(.caption).bold()
                        .foregroundStyle(last.outcome == .error ? .red : .green)
                    Button("Import Log ▸") { openWindow(id: "import-log") }
                        .buttonStyle(.link).font(.caption)
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
