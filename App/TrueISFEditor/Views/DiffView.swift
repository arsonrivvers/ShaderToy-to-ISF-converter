import SwiftUI

/// Unified colored line diff (D2): old → new, folded to changes + context by default.
struct DiffView: View {
    let old: String
    let new: String
    @State private var showUnchanged = false

    var body: some View {
        let diff = LineDiff.diff(old: old, new: new)
        VStack(alignment: .leading, spacing: 4) {
            Toggle("Show unchanged lines", isOn: $showUnchanged)
                .toggleStyle(.checkbox).font(.caption).foregroundStyle(.secondary)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(showUnchanged ? diff.map { DiffRow.line($0) } : LineDiff.displayRows(diff)) { row in
                        rowView(row)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
            }
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
        }
    }

    @ViewBuilder private func rowView(_ row: DiffRow) -> some View {
        switch row {
        case .fold(let count, _):
            Text("··· \(count) unchanged lines ···")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 2)
        case .line(let line):
            HStack(alignment: .top, spacing: 0) {
                Text(line.oldLine.map(String.init) ?? "")
                    .frame(width: 34, alignment: .trailing).foregroundStyle(.secondary)
                Text(line.newLine.map(String.init) ?? "")
                    .frame(width: 34, alignment: .trailing).foregroundStyle(.secondary)
                Text(marker(line.kind)).frame(width: 16)
                Text(line.text.isEmpty ? " " : line.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .font(.system(size: 10, design: .monospaced))
            .padding(.horizontal, 4)
            .background(background(line.kind))
        }
    }

    private func marker(_ kind: DiffLine.Kind) -> String {
        switch kind {
        case .same: return " "
        case .removed: return "−"
        case .added: return "+"
        }
    }

    private func background(_ kind: DiffLine.Kind) -> Color {
        switch kind {
        case .same: return .clear
        case .removed: return .red.opacity(0.14)
        case .added: return .green.opacity(0.16)
        }
    }
}
