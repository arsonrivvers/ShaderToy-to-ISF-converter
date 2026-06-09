import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var draftKey: String = ""
    @State private var draftClaudePath: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("API Key (optional — Advanced)").font(.headline)
            Text("Leave blank to fetch via the built-in browser (no account needed). An API key is only for Shadertoy Silver/Gold members.").font(.caption).foregroundStyle(.secondary)
            SecureField("API key", text: $draftKey)

            Divider()

            Text("Claude Code path (optional)").font(.headline)
            Text("Leave blank to auto-detect (~/.local/bin/claude, Homebrew). Used by the ShaderAssist AI feature, which runs Claude Code on your subscription.").font(.caption).foregroundStyle(.secondary)
            TextField("/path/to/claude", text: $draftClaudePath)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") {
                    model.saveKey(draftKey)
                    model.saveClaudeBinaryPath(draftClaudePath.trimmingCharacters(in: .whitespaces))
                    dismiss()
                }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20).frame(width: 460)
        .onAppear { draftKey = model.apiKey; draftClaudePath = model.claudeBinaryPath }
    }
}
