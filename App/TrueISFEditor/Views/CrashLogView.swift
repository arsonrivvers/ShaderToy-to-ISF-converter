import SwiftUI
import AppKit

struct CrashLogView: View {
    @ObservedObject private var log = CrashLog.shared

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Crash Log").font(.headline)
                Spacer()
                Button("Reveal Log") {
                    NSWorkspace.shared.activateFileViewerSelecting([log.fileURL])
                }
                Button("Clear") { log.clear() }
            }
            .padding(8)
            Divider()
            if log.events.isEmpty {
                Spacer()
                Text("No crashes recorded").foregroundStyle(.secondary)
                Spacer()
            } else {
                List(log.events.reversed()) { event in
                    CrashRow(event: event)
                }
            }
        }
        .frame(minWidth: 480, minHeight: 360)
    }
}

private struct CrashRow: View {
    let event: CrashEvent
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(event.kind.rawValue.uppercased())
                    .font(.caption2).bold()
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(badgeColor.opacity(0.25))
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                Text(event.timestamp.formatted(date: .abbreviated, time: .standard))
                    .font(.caption2).foregroundStyle(.secondary)
                if let c = event.context, !c.isEmpty {
                    Text(c).font(.caption2).foregroundStyle(.secondary)
                }
            }
            Text(event.message)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
            if let d = event.detail, !d.isEmpty {
                Text(d)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(8)
                    .textSelection(.enabled)
            }
        }
        .padding(.vertical, 2)
    }

    private var badgeColor: Color {
        switch event.kind {
        case .compile:   return .orange
        case .render:    return .red
        case .exception: return .purple
        case .signal:    return .pink
        }
    }
}

/// Menu command that opens the Crash Log window; shows a ⚠ marker when last session crashed.
struct CrashLogMenuButton: View {
    @Environment(\.openWindow) private var openWindow
    @ObservedObject private var log = CrashLog.shared
    var body: some View {
        Button(log.crashedLastSession ? "Crash Log ⚠\u{FE0E}" : "Crash Log") {
            openWindow(id: "crash-log")
        }
        .keyboardShortcut("l", modifiers: [.command, .shift])
    }
}
