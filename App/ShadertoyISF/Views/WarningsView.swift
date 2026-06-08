import SwiftUI
import ShadertoyISFKit

struct WarningsView: View {
    let warnings: [ConversionWarning]
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Warnings (\(warnings.count))").font(.headline)
            if warnings.isEmpty {
                Text("None").foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(warnings.enumerated()), id: \.offset) { _, w in
                            HStack(alignment: .top, spacing: 6) {
                                Image(systemName: w.severity == .error ? "xmark.octagon" : "exclamationmark.triangle")
                                    .foregroundStyle(w.severity == .error ? .red : .yellow)
                                VStack(alignment: .leading) {
                                    Text(w.message)
                                    if !w.context.isEmpty { Text(w.context).font(.caption).foregroundStyle(.secondary) }
                                }
                            }
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}
