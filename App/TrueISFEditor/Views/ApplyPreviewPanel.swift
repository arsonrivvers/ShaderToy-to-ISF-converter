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
            Text(result.explanation)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            if !result.changedLines.isEmpty {
                Text("Changed lines: \(result.changedLines.map(String.init).joined(separator: ", "))")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            DiffView(old: originalSource, new: result.replacementSource)
        }
    }
}
