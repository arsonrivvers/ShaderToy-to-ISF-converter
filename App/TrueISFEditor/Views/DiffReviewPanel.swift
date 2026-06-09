import SwiftUI
import ShadertoyISFKit

struct DiffReviewPanel: View {
    let result: AIFixResult
    let sourceLines: [String]
    @Binding var handled: Set<Int>
    let onApply: (AIEdit) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Claude — Diagnose & Fix").font(.headline)
            Text(result.explanation).font(.callout).textSelection(.enabled)
            if result.edits.isEmpty {
                Text("No fixes suggested.").foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(result.edits.enumerated()), id: \.offset) { i, e in editCard(i, e) }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
    @ViewBuilder private func editCard(_ i: Int, _ e: AIEdit) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Lines \(e.fromLine)–\(e.toLine)").font(.caption).bold()
            Text(e.rationale).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            HStack(alignment: .top, spacing: 8) {
                labeled("before", before(e), .red)
                labeled("after", e.replacement, .green)
            }
            if handled.contains(i) {
                Text("✓ handled").font(.caption2).foregroundStyle(.secondary)
            } else {
                HStack {
                    Button("Apply") { onApply(e); handled.insert(i) }.buttonStyle(.borderedProminent).controlSize(.small)
                    Button("Skip") { handled.insert(i) }.buttonStyle(.bordered).controlSize(.small)
                }
            }
        }.padding(6).background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
    }
    private func before(_ e: AIEdit) -> String {
        let lo = max(1, e.fromLine), hi = min(sourceLines.count, e.toLine)
        guard lo <= hi else { return "" }
        return sourceLines[(lo-1)...(hi-1)].joined(separator: "\n")
    }
    private func labeled(_ t: String, _ body: String, _ c: Color) -> some View {
        VStack(alignment: .leading) {
            Text(t).font(.caption2).foregroundStyle(c)
            Text(body).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
