import SwiftUI
import ShadertoyISFKit

struct SuggestionGoalSheet: View {
    @ObservedObject var model: ShaderAssistViewModel
    let source: String
    let diagnostics: [Diagnostic]
    /// All selected goals (AI goal titles + custom goals), in menu order.
    let onChoose: ([String]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var customGoal = ""
    /// Selected goal strings — AI goal titles and custom goal text share this set.
    @State private var selected: Set<String> = []
    /// Custom goals the user added, in the order they were added.
    @State private var customGoals: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("What do you want to improve?")
                        .font(.title3.bold())
                    Text("Pick as many goals as you like — add your own too. ShaderAssist tailors suggestions to all of them.")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel") { dismiss() }
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    aiGoals
                    // Custom goals always render — they must work even if the AI goals call fails.
                    ForEach(customGoals, id: \.self) { goal in
                        goalRow(title: goal, kind: "custom", detail: nil, why: nil)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            customGoalField

            Divider()
            HStack {
                Text("\(selected.count) selected")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Get Suggestions") {
                    let goals = orderedSelectedGoals
                    guard !goals.isEmpty else { return }
                    onChoose(goals)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(selected.isEmpty)
            }
        }
        .padding(18)
        .frame(width: 560)
        .frame(minHeight: 360)
        .onAppear {
            model.requestSuggestionGoals(source: source, diagnostics: diagnostics)
        }
    }

    /// The AI-suggested goals (or the loading / error / empty states for that call).
    @ViewBuilder private var aiGoals: some View {
        switch model.state {
        case .running(.suggestionGoals):
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Reading the shader...")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .suggestionGoals(let result):
            if result.goals.isEmpty && customGoals.isEmpty {
                emptyState
            } else {
                ForEach(result.goals) { goal in
                    goalRow(title: goal.title, kind: goal.kind,
                            detail: goal.detail, why: goal.whyThisShader)
                }
            }
        case .error(let message):
            VStack(alignment: .leading, spacing: 8) {
                Text(message)
                    .font(.system(size: 14))
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
                Text("You can still add your own goal below.")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                Button("Retry goals") { model.requestSuggestionGoals(source: source, diagnostics: diagnostics) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .rawAnswer(let answer):
            Text(answer)
                .font(.system(size: 12, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        default:
            Button("Generate Goals") {
                model.requestSuggestionGoals(source: source, diagnostics: diagnostics)
            }
        }
    }

    private func goalRow(title: String, kind: String, detail: String?, why: String?) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Toggle("", isOn: Binding(
                get: { selected.contains(title) },
                set: { on in if on { selected.insert(title) } else { selected.remove(title) } }))
            .labelsHidden()
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                    Text(kind)
                        .font(.system(size: 14))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                }
                if let detail, !detail.isEmpty {
                    Text(detail)
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                if let why, !why.isEmpty {
                    Text(why)
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(8)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
    }

    private var customGoalField: some View {
        HStack(spacing: 8) {
            TextField("Add your own goal", text: $customGoal)
                .textFieldStyle(.roundedBorder)
                .onSubmit(addCustomGoal)
            Button("Add", action: addCustomGoal)
                .disabled(trimmedCustomGoal.isEmpty)
        }
    }

    /// Append the typed custom goal as a checked menu item and clear the field. Re-adding an existing
    /// goal just re-checks it.
    private func addCustomGoal() {
        let goal = trimmedCustomGoal
        guard !goal.isEmpty else { return }
        if !customGoals.contains(goal) { customGoals.append(goal) }
        selected.insert(goal)
        customGoal = ""
    }

    /// Selected goals in menu order: AI goals first (as listed), then custom goals in add order.
    private var orderedSelectedGoals: [String] {
        var ordered: [String] = []
        if case .suggestionGoals(let result) = model.state {
            ordered += result.goals.map(\.title).filter { selected.contains($0) }
        }
        ordered += customGoals.filter { selected.contains($0) }
        return ordered
    }

    private var emptyState: some View {
        Text("No tailored goals came back. Add your own goal below.")
            .font(.system(size: 14))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var trimmedCustomGoal: String {
        customGoal.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
