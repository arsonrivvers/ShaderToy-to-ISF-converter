import SwiftUI

/// Live raw-stream terminal for a ShaderAssist run (B3): monospaced, dark, auto-scrolling. Shows the
/// provider CLI's JSONL events as they arrive so the diagnosis isn't a black box.
struct AssistTerminalView: View {
    let lines: [String]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { idx, line in
                        Text(line.isEmpty ? " " : line)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.green.opacity(0.92))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(idx)
                    }
                }
                .padding(6)
            }
            .background(Color.black.opacity(0.88))
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .onChange(of: lines.count) { _ in
                if let last = lines.indices.last {
                    withAnimation(.linear(duration: 0.1)) { proxy.scrollTo(last, anchor: .bottom) }
                }
            }
        }
    }
}
