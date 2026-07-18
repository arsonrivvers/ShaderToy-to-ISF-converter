import SwiftUI
import ShadertoyISFKit

struct DiagnosticsPanel: View {
    let diagnostics: [Diagnostic]
    let sourceLines: [String]            // current editor lines (1-based via index+1) for rule context
    let onJump: (Int) -> Void
    let onApply: (TextEdit) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if diagnostics.isEmpty {
                Text("No diagnostics").foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(diagnostics) { d in row(d) }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    @ViewBuilder private func row(_ d: Diagnostic) -> some View {
        let suggestions = FixRuleEngine.suggestions(for: d, sourceLine: d.line.flatMap { lineText($0) })
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: d.severity == .error ? "xmark.octagon" : (d.severity == .warning ? "exclamationmark.triangle" : "info.circle"))
                .foregroundStyle(d.severity == .error ? .red : (d.severity == .warning ? .yellow : .secondary))
            VStack(alignment: .leading, spacing: 3) {
                Text(d.message).textSelection(.enabled)
                if let line = d.line {
                    Button("line \(line)") { onJump(line) }.buttonStyle(.link).font(.caption)
                }
                ForEach(suggestions) { s in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(s.title).font(.caption).bold()
                        Text(s.explanation).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                        if let edit = s.edit {
                            Button("Apply") { onApply(edit) }.buttonStyle(.bordered).controlSize(.small)
                        }
                    }
                    .padding(.leading, 4)
                }
            }
        }
    }

    private func lineText(_ line: Int) -> String? {
        guard line >= 1, line <= sourceLines.count else { return nil }
        return sourceLines[line - 1]
    }
}
