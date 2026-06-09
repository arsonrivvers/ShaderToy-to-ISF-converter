import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var draftKey: String = ""
    @State private var draftAnthropicKey: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {

            // MARK: Shadertoy API Key
            VStack(alignment: .leading, spacing: 6) {
                Text("Shadertoy API Key (optional — Advanced)").font(.headline)
                Text("Leave blank to fetch via the built-in browser (no account needed). An API key is only for Shadertoy Silver/Gold members.").font(.caption).foregroundStyle(.secondary)
                SecureField("API key", text: $draftKey)
            }

            Divider()

            // MARK: Anthropic API Key
            VStack(alignment: .leading, spacing: 6) {
                Text("Anthropic API Key (optional)").font(.headline)
                SecureField("Anthropic API key", text: $draftAnthropicKey)
                Text("Used only for the optional 'Explain with AI' button on compile errors. Each use makes one paid Anthropic API call.").font(.caption).foregroundStyle(.secondary)
            }

            // MARK: Actions
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") {
                    model.saveKey(draftKey)
                    model.saveAnthropicKey(draftAnthropicKey)
                    dismiss()
                }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20).frame(width: 420)
        .onAppear {
            draftKey = model.apiKey
            draftAnthropicKey = model.anthropicKey
        }
    }
}
