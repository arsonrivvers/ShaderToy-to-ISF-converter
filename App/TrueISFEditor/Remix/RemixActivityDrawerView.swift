import AppKit
import SwiftUI

struct RemixActivityDrawerView: View {
    @ObservedObject var model: RemixStudioModel
    let openInEditor: (String) -> Void

    @AccessibilityFocusState private var headerFocused: Bool
    @State private var compileSummary: String?
    @State private var announcedActivity = RemixActivityState.idle

    private var collapsed: Bool {
        model.workspace.collapsedZones.contains(.activity)
    }

    private var failures: [RemixActivityFailurePresentation] {
        RemixLineagePresentation.failureRows(
            nodes: model.currentBatch,
            compileDiagnosticsByNodeID: model.compileDiagnosticsByNodeID
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
                Text(RemixLineagePresentation.compactActivityStatus(for: model.activity))
                    .font(RemixAccessibleTextLayout.bodyFont)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(model.activity.summary.accessibilityAnnouncement)
                Spacer()
                activityButtons
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 44)

            if !collapsed {
                Divider()
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
                                    .font(.system(.caption, design: .monospaced))
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
        }
        .onChange(of: model.activity) { activity in
            if let message = RemixLineagePresentation.announcement(
                from: announcedActivity,
                to: activity
            ) {
                NSAccessibility.post(
                    element: NSApp!,
                    notification: .announcementRequested,
                    userInfo: [
                        .announcement: message,
                        .priority: NSAccessibilityPriorityLevel.medium.rawValue,
                    ]
                )
            }
            announcedActivity = activity
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
        let actions = RemixLineagePresentation.activityActions(for: model.activity)
        if actions.contains("Stop") {
            Button("Stop") { model.cancelGeneration() }
        }
        if actions.contains("Retry All Failed") {
            Button("Retry All Failed") {
                Task { await model.retryFailed() }
            }
        }
        if actions.contains("Retry Interrupted Batch") {
            Button("Retry Interrupted Batch") {
                Task { await model.retryInterruptedBatch() }
            }
        }
        Button("Copy Activity") {
            copy(
                ([model.activity.summary.accessibilityAnnouncement] + model.transcript)
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
                   let node = model.lineage.node(failure.id) {
                    Button("Open Source in Editor to Fix") {
                        openInEditor(node.isfSource)
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
