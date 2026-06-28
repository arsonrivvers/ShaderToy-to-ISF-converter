import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: SettingsStore
    @Environment(\.dismiss) private var dismiss
    @State private var draftKey: String = ""
    @State private var draftClaudePath: String = ""
    @State private var draftCodexPath: String = ""
    @State private var draftProvider: String = "claude"
    @State private var draftClaudeModel: String = "sonnet"
    @State private var draftCodexModel: String = ""

    private let claudeModels = ["opus", "sonnet", "haiku"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("ShaderAssist (AI)").font(.headline)
                Picker("Provider", selection: $draftProvider) {
                    Text("Claude (subscription)").tag("claude")
                    Text("OpenAI · Codex (subscription)").tag("codex")
                }
                .pickerStyle(.radioGroup)

                if draftProvider == "claude" {
                    Picker("Claude model", selection: $draftClaudeModel) {
                        ForEach(claudeModels, id: \.self) { Text($0.capitalized).tag($0) }
                    }
                    statusRow(found: SettingsStore.claudeCLIFound(override: draftClaudePath),
                              cli: "claude", hint: "Run `claude` once in Terminal to sign in.")
                    TextField("/path/to/claude (blank = auto-detect)", text: $draftClaudePath)
                } else {
                    HStack {
                        Text("Codex model")
                        TextField("default (recommended)", text: $draftCodexModel).frame(width: 200)
                    }
                    Text("Leave blank to use your Codex default model.").font(.caption2).foregroundStyle(.secondary)
                    statusRow(found: SettingsStore.codexCLIFound(override: draftCodexPath),
                              cli: "codex", hint: "Run `codex login` in Terminal to sign in with ChatGPT.")
                    TextField("/path/to/codex (blank = auto-detect)", text: $draftCodexPath)
                }
                Text("Both providers run on your existing subscription via their CLI — no API key, no per-call cost. The ISF authoring skills are loaded into each session.")
                    .font(.caption2).foregroundStyle(.secondary)

                Divider()

                Text("API Key (optional — Advanced)").font(.headline)
                Text("Leave blank to fetch via the built-in browser (no account needed). An API key is only for Shadertoy Silver/Gold members.").font(.caption).foregroundStyle(.secondary)
                SecureField("Shadertoy API key", text: $draftKey)

                HStack {
                    Spacer()
                    Button("Cancel") { dismiss() }
                    Button("Save") {
                        store.saveKey(draftKey)
                        store.saveClaudeBinaryPath(draftClaudePath.trimmingCharacters(in: .whitespaces))
                        store.saveAssistSettings(
                            provider: draftProvider,
                            claudeModel: draftClaudeModel,
                            codexModel: draftCodexModel.trimmingCharacters(in: .whitespaces),
                            codexPath: draftCodexPath.trimmingCharacters(in: .whitespaces))
                        dismiss()
                    }.keyboardShortcut(.defaultAction)
                }
            }
            .padding(20).frame(width: 480)
        }
        .frame(width: 480, height: 520)
        .onAppear {
            draftKey = store.apiKey
            draftClaudePath = store.claudeBinaryPath
            draftCodexPath = store.codexBinaryPath
            draftProvider = store.assistProvider
            draftClaudeModel = store.assistClaudeModel.isEmpty ? "sonnet" : store.assistClaudeModel
            draftCodexModel = store.assistCodexModel
        }
    }

    @ViewBuilder private func statusRow(found: Bool, cli: String, hint: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: found ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(found ? .green : .orange)
            Text(found ? "`\(cli)` CLI found" : "`\(cli)` CLI not found — \(hint)")
                .font(.caption)
        }
    }
}
