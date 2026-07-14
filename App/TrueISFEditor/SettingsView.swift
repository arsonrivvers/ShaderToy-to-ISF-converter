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
    // Probed async (nil = checking): the sync locate can run a 5s login-shell `command -v`, and
    // calling it from `body` froze Settings on every keystroke in the path field.
    @State private var claudeFound: Bool?
    @State private var codexFound: Bool?

    private let claudeModels = ["opus", "sonnet", "haiku"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("ShaderAssist (AI)").font(.headline)
                // Claude-only v1: the Codex option ships only in debug builds (see
                // AssistProviderFactory.codexAvailable — release clamps a stale pref to claude).
                if AssistProviderFactory.codexAvailable {
                    Picker("Provider", selection: $draftProvider) {
                        Text("Claude (subscription)").tag("claude")
                        Text("OpenAI · Codex (subscription)").tag("codex")
                    }
                    .pickerStyle(.radioGroup)
                }

                if draftProvider == "claude" || !AssistProviderFactory.codexAvailable {
                    Picker("Claude model", selection: $draftClaudeModel) {
                        ForEach(claudeModels, id: \.self) { Text($0.capitalized).tag($0) }
                    }
                    statusRow(found: claudeFound,
                              cli: "claude", hint: "Run `claude` once in Terminal to sign in.")
                    TextField("/path/to/claude (blank = auto-detect)", text: $draftClaudePath)
                } else {
                    HStack {
                        Text("Codex model")
                        TextField("default (recommended)", text: $draftCodexModel).frame(width: 200)
                    }
                    Text("Leave blank to use your Codex default model.").font(.caption2).foregroundStyle(.secondary)
                    statusRow(found: codexFound,
                              cli: "codex", hint: "Run `codex login` in Terminal to sign in with ChatGPT.")
                    TextField("/path/to/codex (blank = auto-detect)", text: $draftCodexPath)
                }
                Text(AssistProviderFactory.codexAvailable
                     ? "Both providers run on your existing subscription via their CLI — no API key, no per-call cost. The ISF authoring skills are loaded into each session."
                     : "Runs on your existing Claude subscription via the `claude` CLI — no API key, no per-call cost. The ISF authoring skills are loaded into each session.")
                    .font(.caption2).foregroundStyle(.secondary)

                Divider()

                Text("API Key (optional — Advanced)").font(.headline)
                Text("Leave blank to fetch via the built-in browser (no account needed). An API key is only for Shadertoy Silver/Gold members.").font(.caption).foregroundStyle(.secondary)
                SecureField("Shadertoy API key", text: $draftKey)
                if let err = store.keySaveError {
                    Text(err).font(.caption).foregroundStyle(.red)
                }

                Divider()

                // Attribution for bundled components (BSD/Apache require reproducing the license
                // text in binary distributions). Content ships as a resource; see also the repo's
                // THIRD_PARTY_LICENSES directory.
                DisclosureGroup("Acknowledgements") {
                    ScrollView {
                        Text(Acknowledgements.text)
                            .font(.system(size: 10, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 180)
                }
                .font(.caption)

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
        // task(id:) cancels + restarts on each path edit; the short sleep debounces typing so a
        // login-shell probe isn't launched per keystroke.
        .task(id: draftClaudePath) {
            claudeFound = nil
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            claudeFound = await SettingsStore.claudeCLIFoundAsync(override: draftClaudePath)
        }
        .task(id: draftCodexPath) {
            codexFound = nil
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            codexFound = await SettingsStore.codexCLIFoundAsync(override: draftCodexPath)
        }
    }

    @ViewBuilder private func statusRow(found: Bool?, cli: String, hint: String) -> some View {
        HStack(spacing: 6) {
            switch found {
            case nil:
                ProgressView().controlSize(.mini)
                Text("Checking for `\(cli)` CLI…").font(.caption).foregroundStyle(.secondary)
            case true?:
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text("`\(cli)` CLI found").font(.caption)
            case false?:
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text("`\(cli)` CLI not found — \(hint)").font(.caption)
            }
        }
    }
}
