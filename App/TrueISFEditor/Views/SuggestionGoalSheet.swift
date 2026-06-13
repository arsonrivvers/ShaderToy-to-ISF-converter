import SwiftUI
import ShadertoyISFKit

struct SuggestionGoalSheet: View {
    @ObservedObject var model: ShaderAssistViewModel
    let source: String
    let diagnostics: [Diagnostic]
    let onChoose: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var customGoal = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("What do you want to improve?")
                        .font(.title3.bold())
                    Text("ShaderAssist will tailor suggestions to the current shader.")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel") { dismiss() }
            }

            content

            Divider()
            HStack(spacing: 8) {
                TextField("Custom goal", text: $customGoal)
                    .textFieldStyle(.roundedBorder)
                Button("Use Custom Goal") {
                    let goal = trimmedCustomGoal
                    guard !goal.isEmpty else { return }
                    onChoose(goal)
                    dismiss()
                }
                .disabled(trimmedCustomGoal.isEmpty)
            }
        }
        .padding(18)
        .frame(width: 560)
        .frame(minHeight: 360)
        .onAppear {
            model.requestSuggestionGoals(source: source, diagnostics: diagnostics)
        }
    }

    @ViewBuilder private var content: some View {
        switch model.state {
        case .running(.suggestionGoals):
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Reading the shader...")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .suggestionGoals(let result):
            if result.goals.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(result.goals) { goal in
                            goalButton(goal)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        case .error(let message):
            VStack(alignment: .leading, spacing: 8) {
                Text(message)
                    .font(.system(size: 14))
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
                Button("Retry") { model.requestSuggestionGoals(source: source, diagnostics: diagnostics) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .rawAnswer(let answer):
            ScrollView {
                Text(answer)
                    .font(.system(size: 12, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        default:
            Button("Generate Goals") {
                model.requestSuggestionGoals(source: source, diagnostics: diagnostics)
            }
        }
    }

    private func goalButton(_ goal: AISuggestionGoal) -> some View {
        Button {
            onChoose(goal.title)
            dismiss()
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(goal.title)
                        .font(.system(size: 15, weight: .semibold))
                    Text(goal.kind)
                        .font(.system(size: 14))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                }
                Text(goal.detail)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                Text(goal.whyThisShader)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("No tailored goals came back.")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
            Button("Retry") { model.requestSuggestionGoals(source: source, diagnostics: diagnostics) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var trimmedCustomGoal: String {
        customGoal.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
