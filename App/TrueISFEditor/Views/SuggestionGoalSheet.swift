import SwiftUI
import ShadertoyISFKit

struct SuggestionGoalSheet: View {
    @ObservedObject var model: ShaderAssistViewModel
    let source: String
    let diagnostics: [Diagnostic]
    /// All selected ideas (AI goals + custom goals on the quick tab, research ideas on the research
    /// tab), in menu order, to implement directly.
    let onApply: ([AIIdea]) -> Void

    enum AssistTab: String, CaseIterable, Identifiable {
        case quickGoals = "Quick Goals"
        case research = "Research"
        var id: String { rawValue }
    }

    @Environment(\.dismiss) private var dismiss
    @State private var tab: AssistTab = .quickGoals
    @State private var customGoal = ""
    /// Selected goal strings — AI goal titles and custom goal text share this set (quick tab).
    @State private var selected: Set<String> = []
    /// Custom goals the user added, in the order they were added.
    @State private var customGoals: [String] = []
    /// Free-text request for the research tab.
    @State private var researchRequest = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(tab == .quickGoals ? "What do you want to improve?" : "Research an upgrade")
                        .font(.title3.bold())
                    Text(tab == .quickGoals
                         ? "Pick as many as you like — add your own too. ShaderAssist rewrites the shader to implement all of them, then shows you a preview before applying."
                         : "Describe a direction. ShaderAssist digs through its shader skills and technique catalog and proposes concrete upgrades for this shader — pick the ones you like.")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel") { dismiss() }
            }

            Picker("", selection: $tab) {
                ForEach(AssistTab.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if tab == .quickGoals {
                quickGoalsContent
            } else {
                researchContent
            }

            Divider()
            HStack {
                Text("\(selectedCount) selected")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Apply Selected") {
                    let ideas = tab == .quickGoals ? orderedSelectedIdeas : selectedResearchIdeas
                    guard !ideas.isEmpty else { return }
                    onApply(ideas)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedCount == 0)
            }
        }
        .padding(18)
        .frame(width: 560)
        .frame(minHeight: 360)
        .onAppear {
            model.requestSuggestionGoals(source: source, diagnostics: diagnostics)
        }
        // Dismissing mid-run abandons the sheet's goals call — kill the CLI instead of letting it
        // burn a ~30s subscription run and keep the main-screen buttons disabled until it finishes.
        // A research run is NOT cancelled: its result lands in the main-screen SuggestionsPanel, so
        // closing the sheet never throws a long run away.
        .onDisappear { model.cancelSuggestionGoalsIfRunning() }
    }

    private var selectedCount: Int {
        tab == .quickGoals ? selected.count : selectedResearchIdeas.count
    }

    // MARK: - Quick Goals tab (existing flow)

    private var quickGoalsContent: some View {
        Group {
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

    /// Selected goals as ideas in menu order: AI goals first (carrying their detail/kind so the rewrite
    /// has the full spec), then custom goals in add order. The detail is what tells the LLM exactly what
    /// to implement.
    private var orderedSelectedIdeas: [AIIdea] {
        var ideas: [AIIdea] = []
        if case .suggestionGoals(let result) = model.state {
            for g in result.goals where selected.contains(g.title) {
                ideas.append(AIIdea(id: g.id, title: g.title, detail: g.detail,
                                    kind: g.kind, lines: nil, impact: nil))
            }
        }
        for c in customGoals where selected.contains(c) {
            ideas.append(AIIdea(id: c, title: c, detail: "", kind: "custom", lines: nil, impact: nil))
        }
        return ideas
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

    // MARK: - Research tab

    private var researchRunning: Bool {
        if case .running(.research) = model.state { return true }
        return false
    }

    private var selectedResearchIdeas: [AIIdea] {
        guard let s = model.lastSuggestions else { return [] }
        return s.ideas.filter { model.selectedIdeaIDs.contains($0.id) }
    }

    private var researchContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("e.g. make the trails feel like analog video decay",
                      text: $researchRequest, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(2...5)
                .onSubmit(startResearch)
            HStack(spacing: 10) {
                Button("Research Upgrades", action: startResearch)
                    .buttonStyle(.borderedProminent)
                    .disabled(trimmedResearchRequest.isEmpty || researchRunning)
                if researchRunning {
                    ProgressView().controlSize(.small)
                    Text("Digging through the shader skills...")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                    Button("Cancel") { model.cancel() }
                }
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    researchResults
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @ViewBuilder private var researchResults: some View {
        switch model.state {
        case .suggestions(let result):
            if result.ideas.isEmpty {
                Text("Nothing concrete came back for that request. Try rephrasing it.")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(result.ideas) { idea in
                    researchIdeaRow(idea)
                }
            }
        case .error(let message):
            VStack(alignment: .leading, spacing: 8) {
                Text(message)
                    .font(.system(size: 14))
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
                if model.canRetry {
                    Button("Try Again") { model.retryLastRun() }
                }
            }
        case .rawAnswer(let answer):
            Text(answer)
                .font(.system(size: 12, design: .monospaced))
                .textSelection(.enabled)
        default:
            EmptyView()
        }
    }

    private func researchIdeaRow(_ idea: AIIdea) -> some View {
        let isSelected = model.selectedIdeaIDs.contains(idea.id)
        return HStack(alignment: .top, spacing: 8) {
            Toggle("", isOn: Binding(get: { isSelected },
                                     set: { _ in model.toggleIdeaSelection(idea.id) }))
                .labelsHidden()
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(idea.title)
                        .font(.system(size: 15, weight: .semibold))
                    Text(idea.kind)
                        .font(.system(size: 14))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
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
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(8)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
    }

    private func startResearch() {
        guard !trimmedResearchRequest.isEmpty, !researchRunning else { return }
        model.researchUpgrades(request: trimmedResearchRequest,
                               source: source, diagnostics: diagnostics)
    }

    private var trimmedResearchRequest: String {
        researchRequest.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
