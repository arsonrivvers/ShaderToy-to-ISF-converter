import SwiftUI
import AppKit

/// Live raw-stream terminal for a ShaderAssist run (B3): monospaced, dark, auto-scrolling. Shows the
/// provider CLI's JSONL events as they arrive so the diagnosis isn't a black box. The whole transcript
/// is one selectable text block (drag-select / ⌘A) plus a Copy button, so errors can be grabbed whole.
struct AssistTerminalView: View {
    let lines: [String]

    private var text: String { lines.joined(separator: "\n") }

    var body: some View {
        VStack(spacing: 2) {
            HStack(spacing: 8) {
                Text("\(lines.count) line\(lines.count == 1 ? "" : "s")")
                    .font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .controlSize(.small)
                .disabled(lines.isEmpty)
                .help("Copy the entire activity log to the clipboard")
            }

            ScrollViewReader { proxy in
                ScrollView {
                    // One selectable Text block so the user can drag-select / ⌘A the whole log.
                    Text(text.isEmpty ? " " : text)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.green.opacity(0.92))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(6)
                    Color.clear.frame(height: 1).id("bottom")
                }
                .background(Color.black.opacity(0.88))
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .onChange(of: lines.count) { _ in
                    withAnimation(.linear(duration: 0.1)) { proxy.scrollTo("bottom", anchor: .bottom) }
                }
            }
        }
    }
}
