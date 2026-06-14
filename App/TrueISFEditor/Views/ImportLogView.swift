import SwiftUI
import AppKit

struct ImportLogView: View {
    @ObservedObject private var log = ImportLog.shared

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Import Log").font(.headline)
                Spacer()
                Button("Reveal Log") { NSWorkspace.shared.activateFileViewerSelecting([log.fileURL]) }
                Button("Clear") { log.clear() }
            }
            .padding(8)
            Divider()
            if log.events.isEmpty {
                Spacer(); Text("No imports recorded").foregroundStyle(.secondary); Spacer()
            } else {
                List(log.events.reversed()) { ImportRow(event: $0) }
            }
        }
        .frame(minWidth: 480, minHeight: 360)
    }
}

private struct ImportRow: View {
    let event: ImportEvent
    @State private var expanded = false

    private var icon: String {
        switch event.outcome {
        case .success: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.octagon.fill"
        }
    }
    private var tint: Color {
        switch event.outcome {
        case .success: return .green
        case .warning: return .orange
        case .error: return .red
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Image(systemName: icon).foregroundStyle(tint)
                Text(event.query).font(.callout).bold().lineLimit(1)
                Spacer()
                Text(event.timestamp, style: .time).font(.caption2).foregroundStyle(.secondary)
            }
            Text(event.message).font(.caption).foregroundStyle(.secondary).lineLimit(expanded ? nil : 2)
            DisclosureGroup("Details", isExpanded: $expanded) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Source: \(event.fetchSource.rawValue)\(event.httpStatus.map { " · HTTP \($0)" } ?? "") · stage: \(event.stage.rawValue)")
                        .font(.caption2).foregroundStyle(.secondary)
                    if let snip = event.responseSnippet, !snip.isEmpty {
                        Text("Response (first 300):").font(.caption2).bold()
                        Text(snip).font(.system(.caption2, design: .monospaced)).textSelection(.enabled)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(.caption2)
        }
        .padding(.vertical, 2)
    }
}

/// Opens the Import Log window from a menu command (mirrors CrashLogMenuButton).
struct ImportLogMenuButton: View {
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Button("Import Log") { openWindow(id: "import-log") }
            .keyboardShortcut("i", modifiers: [.command, .shift])
    }
}
