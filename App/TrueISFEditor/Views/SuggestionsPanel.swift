import SwiftUI
import ShadertoyISFKit

struct SuggestionsPanel: View {
    let result: AISuggestionsResult
    let selectedIDs: Set<String>
    let onToggle: (String) -> Void
    let onJump: (Int) -> Void
    let onApply: () -> Void
    let onRerun: () -> Void
    let onChangeGoal: () -> Void
    let onStartOver: () -> Void

    init(result: AISuggestionsResult, onJump: @escaping (Int) -> Void) {
        self.init(result: result,
                  selectedIDs: [],
                  onToggle: { _ in },
                  onJump: onJump,
                  onApply: {},
                  onRerun: {},
                  onChangeGoal: {},
                  onStartOver: {})
    }

    init(result: AISuggestionsResult,
         selectedIDs: Set<String>,
         onToggle: @escaping (String) -> Void,
         onJump: @escaping (Int) -> Void,
         onApply: @escaping () -> Void,
         onRerun: @escaping () -> Void,
         onChangeGoal: @escaping () -> Void,
         onStartOver: @escaping () -> Void) {
        self.result = result
        self.selectedIDs = selectedIDs
        self.onToggle = onToggle
        self.onJump = onJump
        self.onApply = onApply
        self.onRerun = onRerun
        self.onChangeGoal = onChangeGoal
        self.onStartOver = onStartOver
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("ShaderAssist Suggestions")
                        .font(.headline)
                    Text(result.goal.isEmpty ? "Goal-driven suggestions" : result.goal)
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Rerun", action: onRerun).controlSize(.small)
                Button("Change Goal", action: onChangeGoal).controlSize(.small)
                Button("Start Over", action: onStartOver).controlSize(.small)
            }

            if result.ideas.isEmpty {
                Text("No suggestions for this goal. Try rerunning or changing the goal.")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(result.ideas) { idea in
                            suggestionRow(idea)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            HStack {
                Text("\(selectedIDs.count) selected")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Apply Selected", action: onApply)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(selectedIDs.isEmpty)
            }
        }
    }

    private func suggestionRow(_ idea: AIIdea) -> some View {
        let selected = selectedIDs.contains(idea.id)
        return HStack(alignment: .top, spacing: 8) {
            Toggle("", isOn: Binding(get: { selected }, set: { _ in onToggle(idea.id) }))
                .labelsHidden()
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(idea.title)
                        .font(.system(size: 15, weight: .semibold))
                    Text(idea.kind)
                        .font(.system(size: 14))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(.quaternary, in: Capsule())
                }
                Text(idea.detail)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                if let impact = idea.impact, !impact.isEmpty {
                    Text(impact)
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                if let lines = idea.lines, let first = lines.first {
                    Button("line \(first)") { onJump(first) }
                        .buttonStyle(.link)
                        .font(.system(size: 14))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(8)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
    }
}
