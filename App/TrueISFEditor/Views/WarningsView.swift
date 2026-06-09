import SwiftUI
import ShadertoyISFKit

struct WarningsView: View {
    let warnings: [ConversionWarning]
    /// Live GL compile error from the preview pane, folded in as a top-of-list error row.
    var previewError: String? = nil
    var previewErrorLine: Int? = nil

    private var hasPreviewError: Bool { previewError != nil }
    private var totalCount: Int { warnings.count + (hasPreviewError ? 1 : 0) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Warnings (\(totalCount))").font(.headline)
            if totalCount == 0 {
                Text("None").foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        if let err = previewError {
                            row(icon: "xmark.octagon", color: .red,
                                message: "Preview won't compile: " + (err.components(separatedBy: "\n").first ?? err),
                                context: previewErrorLine.map { "line \($0)" } ?? "live GL preview")
                        }
                        ForEach(Array(warnings.enumerated()), id: \.offset) { _, w in
                            row(icon: w.severity == .error ? "xmark.octagon" : "exclamationmark.triangle",
                                color: w.severity == .error ? .red : .yellow,
                                message: w.message, context: w.context)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    @ViewBuilder
    private func row(icon: String, color: Color, message: String, context: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: icon).foregroundStyle(color)
            VStack(alignment: .leading) {
                Text(message)
                if !context.isEmpty { Text(context).font(.caption).foregroundStyle(.secondary) }
            }
        }
    }
}
