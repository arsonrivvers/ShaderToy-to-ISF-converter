import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var draftKey: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Shadertoy API Key").font(.headline)
            Text("Create a free key at shadertoy.com → Profile → Apps.").font(.caption).foregroundStyle(.secondary)
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
