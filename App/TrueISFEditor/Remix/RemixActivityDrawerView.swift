import AppKit
import SwiftUI

enum RemixAccessibilityAnnouncement {
    @discardableResult
    static func post(_ message: String, application: NSApplication?) -> Bool {
        guard let application else { return false }
        NSAccessibility.post(
            element: application,
            notification: .announcementRequested,
            userInfo: [
                .announcement: message,
                .priority: NSAccessibilityPriorityLevel.medium.rawValue,
            ]
        )
        return true
    }
}

struct RemixActivityDrawerView: View {
    @ObservedObject var model: RemixStudioModel
    let openInEditor: (String) -> Void

    @AccessibilityFocusState private var headerFocused: Bool
    @State private var compileSummary: String?
    @State private var announcedActivity = RemixActivityState.idle
    @State private var announcedRunSummary = RemixRunSummary(records: [])

    private var collapsed: Bool {
        model.workspace.collapsedZones.contains(.activity)
    }

    private var failures: [RemixActivityFailurePresentation] {
        RemixLineagePresentation.failureRows(records: model.currentRuns)
    }

    private var aggregateSummary: RemixActivitySummary {
        model.currentRuns.isEmpty
            ? model.activity.summary
            : model.runSummary.activitySummary(
                activeProviderCount: model.activeProviderChildIDs.count
            )
    }

    private var aggregateActions: [String] {
        model.currentRuns.isEmpty
            ? RemixLineagePresentation.activityActions(for: model.activity)
            : RemixLineagePresentation.activityActions(
                for: model.runSummary,
                canStop: model.canStopGeneration
            )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Button(collapsed ? "Expand Activity" : "Collapse Activity") {
                    if collapsed {
                        model.workspace.expand(.activity)
                    } else {
                        model.workspace.collapse(.activity)
                    }
                    headerFocused = true
                }
                .accessibilityFocused($headerFocused)
                Text(aggregateSummary.compactStatus)
                    .font(RemixAccessibleTextLayout.bodyFont)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(aggregateSummary.accessibilityAnnouncement)
                Spacer()
                activityButtons
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 44)

            if !collapsed {
                Divider()
                if model.runSummary.totalCount > 0 {
                    ProgressView(value: model.runSummary.terminalProgress)
                        .padding(.horizontal, 12)
                        .accessibilityLabel("Terminal children")
                        .accessibilityValue(
                            "\(model.runSummary.terminalCount) of \(model.runSummary.totalCount)"
                        )
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if !failures.isEmpty {
                            ForEach(failures) { failureRow($0) }
                            Divider()
                        }
                        if model.transcript.isEmpty {
                            Text("No activity messages yet.")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(
                                Array(model.transcript.enumerated()),
                                id: \.offset
                            ) { _, line in
                                Text(line)
                                    .font(
                                        .system(
                                            size: RemixTextPolicy.basePointSize,
                                            design: .monospaced
                                        )
                                    )
                                    .textSelection(.enabled)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                }
                .frame(height: model.workspace.zoneWidths[.activity] ?? 180)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Activity")
        .onAppear {
            announcedActivity = model.activity
            announcedRunSummary = model.runSummary
        }
        .onChange(of: model.activity) { activity in
            guard model.currentRuns.isEmpty else {
                announcedActivity = activity
                return
            }
            if let message = RemixLineagePresentation.announcement(
                from: announcedActivity,
                to: activity
            ) {
                RemixAccessibilityAnnouncement.post(message, application: NSApp)
            }
            announcedActivity = activity
        }
        .onChange(of: model.runSummary) { summary in
            guard !model.currentRuns.isEmpty else {
                announcedRunSummary = summary
                return
            }
            if let message = RemixLineagePresentation.announcement(
                from: announcedRunSummary,
                to: summary
            ) {
                RemixAccessibilityAnnouncement.post(message, application: NSApp)
            }
            announcedRunSummary = summary
        }
        .sheet(isPresented: Binding(
            get: { compileSummary != nil },
            set: { if !$0 { compileSummary = nil } }
        )) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Compile Summary").font(.title2.bold())
                Text(compileSummary ?? "").textSelection(.enabled)
                HStack {
                    Spacer()
                    Button("Close") { compileSummary = nil }
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(24)
            .frame(minWidth: 480, minHeight: 240)
        }
    }

    @ViewBuilder
    private var activityButtons: some View {
        if aggregateActions.contains("Stop") {
            Button("Stop") { model.cancelGeneration() }
        }
        if aggregateActions.contains("Retry All Failed") {
            Button("Retry All Failed") {
                Task { await model.retryFailed() }
            }
        }
        if aggregateActions.contains("Retry Interrupted Batch") {
            Button("Retry Interrupted Batch") {
                Task { await model.retryInterruptedBatch() }
            }
        }
        Button("Copy Activity") {
            copy(
                ([aggregateSummary.accessibilityAnnouncement] + model.transcript)
                    .joined(separator: "\n")
            )
        }
    }

    private func failureRow(_ failure: RemixActivityFailurePresentation) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(failure.title).font(.headline)
            Text(failure.message)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            HStack {
                if failure.actions.contains("View Compile Summary") {
                    Button("View Compile Summary") {
                        compileSummary = model.compileSummary(for: failure.id)
                    }
                }
                if failure.actions.contains("Copy Diagnostic") {
                    Button("Copy Diagnostic") {
                        if let diagnostic = model.compileDiagnostic(for: failure.id) {
                            copy(diagnostic)
                        }
                    }
                }
                if failure.actions.contains("Open Source in Editor to Fix"),
                   let source = model.currentRuns.first(where: { $0.id == failure.id })?
                    .candidateSource {
                    Button("Open Source in Editor to Fix") {
                        openInEditor(source)
                    }
                }
                Button("Retry This Child") {
                    Task { await model.retryChild(id: failure.id) }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(failure.title). \(failure.message)")
        .accessibilityHint("Available actions: \(failure.actions.joined(separator: ", ")).")
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
