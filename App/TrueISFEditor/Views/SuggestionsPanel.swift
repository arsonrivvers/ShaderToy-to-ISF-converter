import SwiftUI
import ShadertoyISFKit

struct SuggestionsPanel: View {
    let result: AISuggestionsResult
    let onJump: (Int) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Claude — Suggestions").font(.headline)
            if result.ideas.isEmpty { Text("No suggestions.").foregroundStyle(.secondary) }
            else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(result.ideas) { idea in
                            VStack(alignment: .leading, spacing: 3) {
                                HStack {
                                    Text(idea.title).font(.callout).bold()
                                    Text(idea.kind).font(.caption2).padding(.horizontal, 5).padding(.vertical, 1)
                                        .background(.quaternary, in: Capsule())
                                }
                                Text(idea.detail).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                                if let lines = idea.lines, let first = lines.first {
                                    Button("line \(first)") { onJump(first) }.buttonStyle(.link).font(.caption2)
                                }
                            }.padding(6).background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                             .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
        }
    }
}
