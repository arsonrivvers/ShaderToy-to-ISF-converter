import SwiftUI
import ShadertoyISFKit

/// Liveness strip for a running assist task: honest elapsed/last-activity stats, no fake percent.
struct AssistProgressStrip: View {
    @ObservedObject var model: ShaderAssistViewModel
    let onCancel: () -> Void

    static func clock(_ seconds: TimeInterval) -> String {
        let seconds = max(0, Int(seconds))
        return seconds < 60 ? "\(seconds)s" : "\(seconds / 60)m \(seconds % 60)s"
    }

    /// Before the first event, the run start is the only honest activity reference.
    static func quietDuration(runStartDate: Date?, lastEventDate: Date?, now: Date) -> TimeInterval {
        guard let reference = lastEventDate ?? runStartDate else { return 0 }
        return max(0, now.timeIntervalSince(reference))
    }

    var body: some View {
        if case .running(let task) = model.state {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let elapsed = model.runStartDate.map { context.date.timeIntervalSince($0) } ?? 0
                let quiet = Self.quietDuration(runStartDate: model.runStartDate,
                                               lastEventDate: model.lastEventDate,
                                               now: context.date)
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small).fixedSize()
                    VStack(alignment: .leading, spacing: 1) {
                        Text(Self.title(for: task)).bold().lineLimit(1)
                        HStack(spacing: 5) {
                            Text("\(Self.clock(elapsed)) · \(model.eventCount) events")
                                .lineLimit(1)
                            if model.lastEventDate != nil || quiet > 30 {
                                Text(quiet > 30
                                     ? "quiet \(Self.clock(quiet)) — still running"
                                     : "active \(Self.clock(quiet)) ago")
                                    .foregroundStyle(quiet > 30 ? Color.orange : Color.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                    .layoutPriority(-1)
                            } else {
                                Text("starting…").lineLimit(1)
                            }
                        }
                        .foregroundStyle(.secondary)
                    }
                    .layoutPriority(1)
                    Spacer(minLength: 0)
                    Button("Cancel", action: onCancel)
                        .controlSize(.small)
                        .fixedSize()
                        .layoutPriority(2)
                }
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(.quaternary.opacity(0.5))
            }
        }
    }

    static func title(for task: ShaderAssistTask) -> String {
        switch task {
        case .diagnoseAndFix: return "Diagnosing & fixing"
        case .suggestionGoals: return "Reading the shader"
        case .suggestions: return "Generating suggestions"
        case .applySuggestions: return "Rewriting shader"
        case .research: return "Researching upgrades"
        }
    }
}

/// Compact twin for the always-visible preview header while the editor pane is collapsed.
/// Tap to restore the editor pane.
struct AssistRunBadge: View {
    @ObservedObject var model: ShaderAssistViewModel
    let onTap: () -> Void

    var body: some View {
        if case .running = model.state {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let elapsed = model.runStartDate.map { context.date.timeIntervalSince($0) } ?? 0
                let quiet = AssistProgressStrip.quietDuration(runStartDate: model.runStartDate,
                                                              lastEventDate: model.lastEventDate,
                                                              now: context.date)
                Button(action: onTap) {
                    HStack(spacing: 4) {
                        ProgressView().controlSize(.small)
                        Text(AssistProgressStrip.clock(elapsed))
                            .foregroundStyle(quiet > 30 ? Color.orange : Color.secondary)
                    }
                }
                .buttonStyle(.plain)
                .help("ShaderAssist is running — click to show the editor pane")
            }
        }
    }
}
