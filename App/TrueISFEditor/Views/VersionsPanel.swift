import SwiftUI

/// The Versions tab of the bottom panel: timeline left, selected-version diff right.
/// Replaces the old ⌘⌥V sheet with version history embedded beside the editor.
struct VersionsPanel: View {
    @ObservedObject var vm: EditorViewModel
    @State private var versions: [Snapshot] = []
    @State private var selectedID: String?
    @State private var pinName = ""
    @State private var showPinField = false

    private var selected: Snapshot? { versions.first { $0.id == selectedID } }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Spacer(minLength: 0)
                if showPinField {
                    TextField("Pin name", text: $pinName)
                        .textFieldStyle(.roundedBorder)
                        .frame(minWidth: 80, idealWidth: 110, maxWidth: 130)
                        .onSubmit { commitPin() }
                    Button("Pin") { commitPin() }
                        .controlSize(.small)
                    Button("Cancel") { cancelPin() }
                        .controlSize(.small)
                } else {
                    Button {
                        showPinField = true
                    } label: {
                        Label("Pin", systemImage: "pin")
                    }
                    .controlSize(.small)
                    .help("Pin the current editor state as a named version")
                }
            }

            if versions.isEmpty {
                Text("No versions yet — saves (⌘S), AI applies, and pins land here.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HSplitView {
                    List(selection: $selectedID) {
                        ForEach(versions) { snapshot in
                            row(snapshot).tag(snapshot.id)
                        }
                    }
                    .frame(minWidth: 110, idealWidth: 135)

                    VStack(alignment: .leading, spacing: 6) {
                        if let snapshot = selected {
                            HStack(spacing: 6) {
                                Text("\(snapshot.displayTitle) → current")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                                Button("Restore") { vm.restore(snapshot) }
                                    .buttonStyle(.borderedProminent)
                                    .controlSize(.small)
                            }
                            DiffView(old: snapshot.source, new: vm.file.source)
                        } else {
                            Text("Select a version to compare and restore.")
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                    .padding(.leading, 4)
                    .frame(minWidth: 190)
                }
            }
        }
        .onAppear(perform: reload)
        .onReceive(vm.snapshots.$revision) { _ in reload() }
        .onChange(of: vm.documentGeneration) { _ in
            selectedID = nil
            reload()
        }
    }

    private func commitPin() {
        vm.pin(name: pinName)
        pinName = ""
        showPinField = false
    }

    private func cancelPin() {
        pinName = ""
        showPinField = false
    }

    /// Keep an intentional selection across captures, but never leave the diff blank after reload.
    private func reload() {
        versions = vm.snapshots.snapshots(for: vm.file)
        if !versions.contains(where: { $0.id == selectedID }) {
            selectedID = versions.first?.id
        }
    }

    @ViewBuilder private func row(_ snapshot: Snapshot) -> some View {
        HStack(spacing: 6) {
            Image(systemName: glyph(snapshot.kind))
                .foregroundStyle(tint(snapshot.kind))
                .frame(width: 14)
            VStack(alignment: .leading, spacing: 1) {
                Text(snapshot.displayTitle)
                    .font(.callout)
                    .lineLimit(1)
                Text(snapshot.date, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func glyph(_ kind: SnapshotKind) -> String {
        switch kind {
        case .save: return "internaldrive"
        case .aiApply: return "wand.and.stars"
        case .pin: return "pin.fill"
        case .safety, .legacy: return "clock.arrow.circlepath"
        }
    }

    private func tint(_ kind: SnapshotKind) -> Color {
        switch kind {
        case .save: return .blue
        case .aiApply: return .orange
        case .pin: return .yellow
        case .safety, .legacy: return .secondary
        }
    }
}
