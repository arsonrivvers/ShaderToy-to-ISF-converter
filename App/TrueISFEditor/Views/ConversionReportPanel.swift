import SwiftUI
import ShadertoyISFKit

/// A reusable "what happened" report. Built first for Shadertoy import (what converted, what was
/// assumed, what couldn't be translated), but the model is generic — ShaderAssist/remix can pass their
/// own title + warnings to reuse it. Groups entries by severity so the user sees blockers first.
struct ConversionReportPanel: View {
    let title: String
    let summary: String
    let warnings: [ConversionWarning]
    let onDismiss: () -> Void

    private var errors: [ConversionWarning] { warnings.filter { $0.severity == .error } }
    private var warns: [ConversionWarning] { warnings.filter { $0.severity == .warning } }
    private var infos: [ConversionWarning] { warnings.filter { $0.severity == .info } }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: errors.isEmpty ? "checkmark.seal" : "exclamationmark.triangle")
                    .foregroundStyle(errors.isEmpty ? .green : .orange)
                Text(title).font(.headline)
                Spacer()
                Button("Dismiss", action: onDismiss).controlSize(.small)
            }
            Text(summary).font(.system(size: 13)).foregroundStyle(.secondary)

            if warnings.isEmpty {
                Text("Converted cleanly — nothing needed adjusting.")
                    .font(.system(size: 13)).foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        section("Errors", errors, "xmark.octagon.fill", .red)
                        section("Warnings", warns, "exclamationmark.triangle.fill", .orange)
                        section("Notes", infos, "info.circle.fill", .secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 180)
            }
        }
        .padding(10)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func section(_ heading: String, _ items: [ConversionWarning],
                         _ symbol: String, _ tint: Color) -> some View {
        if !items.isEmpty {
            Text("\(heading) (\(items.count))")
                .font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
            ForEach(Array(items.enumerated()), id: \.offset) { _, w in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: symbol).foregroundStyle(tint).font(.system(size: 11))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(w.message).font(.system(size: 13)).textSelection(.enabled)
                        if !w.context.isEmpty {
                            Text(w.context).font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }
}
