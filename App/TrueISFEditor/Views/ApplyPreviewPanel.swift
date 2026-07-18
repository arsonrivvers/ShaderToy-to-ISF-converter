import SwiftUI
import ShadertoyISFKit

struct ApplyPreviewPanel: View {
    let originalSource: String
    let result: AIApplyResult
    let onApply: () -> Void
    let onDiscard: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Review ShaderAssist Rewrite")
                    .font(.headline)
                Spacer()
                Button("Discard", action: onDiscard)
                    .controlSize(.small)
                Button("Apply to Editor", action: onApply)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
            // The explanation can be many paragraphs — it scrolls in a bounded strip so it can
            // never overrun the changed-lines caption or the diff below (overlap bug, 2026-07-18).
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    Text(result.explanation)
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    if !result.changedLines.isEmpty {
                        Text("Changed lines: \(LineDiff.rangeSummary(result.changedLines))")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 110)
            DiffView(old: originalSource, new: result.replacementSource)
        }
    }
}
