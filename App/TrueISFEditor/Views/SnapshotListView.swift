import SwiftUI

/// D1: the versions list — history left, selected-version diff right, one Restore action.
struct SnapshotListView: View {
    @ObservedObject var vm: EditorViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var versions: [Snapshot] = []
    @State private var selectedID: String?

    private var selected: Snapshot? { versions.first { $0.id == selectedID } }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Versions — \(vm.file.displayName)").font(.headline)
                Spacer()
                Button("Close") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            .padding(10)
            Divider()
            HSplitView {
                List(selection: $selectedID) {
                    ForEach(versions) { s in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(s.label).font(.callout)
                            Text(s.date.formatted(date: .abbreviated, time: .standard))
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        .tag(s.id)
                    }
                }
                .frame(minWidth: 190, idealWidth: 230)
                VStack(alignment: .leading, spacing: 8) {
                    if let s = selected {
                        HStack {
                            Text("Selected version → current source")
                                .font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Button("Restore This Version") { vm.restore(s); dismiss() }
                                .buttonStyle(.borderedProminent).controlSize(.small)
                        }
                        DiffView(old: s.source, new: vm.file.source)
                    } else {
                        Text(versions.isEmpty
                             ? "No versions yet — versions are captured when a shader is opened and before every AI apply."
                             : "Select a version to compare and restore.")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .padding(10)
                .frame(minWidth: 420)
            }
        }
        .frame(minWidth: 720, minHeight: 440)
        .onAppear { versions = vm.snapshots.snapshots(for: vm.file) }
    }
}
