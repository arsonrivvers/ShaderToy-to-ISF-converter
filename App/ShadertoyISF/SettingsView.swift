import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var draftKey: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("API Key (optional — Advanced)").font(.headline)
            Text("Leave blank to fetch via the built-in browser (no account needed). An API key is only for Shadertoy Silver/Gold members.").font(.caption).foregroundStyle(.secondary)
            SecureField("API key", text: $draftKey)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") { model.saveKey(draftKey); dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20).frame(width: 420)
        .onAppear { draftKey = model.apiKey }
    }
}
