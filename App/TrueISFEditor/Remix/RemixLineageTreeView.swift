import SwiftUI

/// The right rail: flattened lineage tree (snapshot swatches, ⚭ secondary-parent badges, ★),
/// a [★ only] filter, the selected node's action strip — the rail's ONLY live Metal engine —
/// and Step Back. Rows come from RemixTreeBuilder via model.treeRows.
struct RemixLineageTreeView: View {
    @ObservedObject var model: RemixStudioModel
    let openInEditor: (String) -> Void

    @State private var collapsed: Set<String> = []
    @State private var favoritesOnly = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            treeList
            if let id = model.selectedNodeID, let node = model.lineage.node(id) {
                Divider()
                actionStrip(node)
            }
            Divider()
            Button { model.stepBack() } label: { Label("Step Back", systemImage: "arrow.uturn.backward") }
            Text("Lineage: \(model.lineage.order.count) nodes").font(.caption2).foregroundStyle(.secondary)
        }
        .padding(10)
    }

    private var header: some View {
        HStack {
            Text("Lineage").font(.headline)
            Spacer()
            Toggle("★ only", isOn: $favoritesOnly)
                .toggleStyle(.button).font(.caption).controlSize(.small)
        }
    }

    private var treeList: some View {
        let rows = model.treeRows(collapsed: collapsed, favoritesOnly: favoritesOnly)
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                if rows.isEmpty {
                    Text(emptyHint)
                        .font(.caption).foregroundStyle(.tertiary)
                        .padding(.top, 8)
                } else {
                    ForEach(rows) { row in treeRow(row) }
                }
            }
        }
    }

    private var emptyHint: String {
        if model.lineage.order.isEmpty { return "Add parents and Generate — the family tree grows here." }
        if favoritesOnly { return "No favorites yet — ★ a child to pin it here." }
        return "No compiled shaders yet."
    }

    private func treeRow(_ row: RemixTreeRow) -> some View {
        let node = model.lineage.node(row.id)
        let isSelected = model.selectedNodeID == row.id
        return HStack(spacing: 4) {
            if RemixTreeBuilder.hasRenderedChildren(model.lineage, id: row.id) {
                Button {
                    if collapsed.contains(row.id) { collapsed.remove(row.id) }
                    else { collapsed.insert(row.id) }
                } label: {
                    Image(systemName: collapsed.contains(row.id) ? "chevron.right" : "chevron.down")
                }
                .buttonStyle(.borderless).font(.caption2).frame(width: 14)
            } else {
                Spacer().frame(width: 14)
            }
            swatch(row.id)
            Text(node?.label ?? row.id).font(.caption).lineLimit(1)
            if let sec = row.secondaryParentID, let secNode = model.lineage.node(sec) {
                Button { model.selectedNodeID = sec } label: {
                    Text("⚭\(secNode.label ?? sec)").font(.caption2)
                }
                .buttonStyle(.borderless).foregroundStyle(.secondary)
                .help("Second parent — click to select it")
            }
            if model.lineage.isFavorite(row.id) {
                Image(systemName: "star.fill").font(.caption2).foregroundStyle(.yellow)
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, CGFloat(row.depth) * 12)
        .padding(.vertical, 2).padding(.horizontal, 4)
        .background(RoundedRectangle(cornerRadius: 4)
            .fill(isSelected ? Color.accentColor.opacity(0.18) : Color.clear))
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { if let n = node { openInEditor(n.isfSource) } }
        .onTapGesture { model.selectedNodeID = row.id }
    }

    private func swatch(_ id: String) -> some View {
        Group {
            if let img = model.snapshots[id] {
                Image(decorative: img, scale: 1).resizable().aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: "photo").font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .frame(width: 24, height: 16)
        .clipShape(RoundedRectangle(cornerRadius: 3))
    }

    /// Compact actions for the selected node. Hosts the rail's only live Metal preview.
    private func actionStrip(_ node: RemixNode) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(node.label ?? node.id).font(.caption.bold()).lineLimit(1)
                Spacer()
                Button { model.selectedNodeID = nil } label: { Image(systemName: "xmark.circle") }
                    .buttonStyle(.borderless).help("Deselect")
            }
            RemixThumbnailView(isf: node.isfSource, animating: true,
                               onSnapshot: { img in model.storeSnapshot(id: node.id, image: img) }) { _, _ in }
                .frame(height: 90)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            Text(node.directive).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
            HStack(spacing: 10) {
                Button { model.promoteToParent(.a, nodeID: node.id) } label: {
                    Label("A", systemImage: "arrow.up.circle")
                }.help("Promote to Parent A")
                Button { model.promoteToParent(.b, nodeID: node.id) } label: {
                    Label("B", systemImage: "arrow.up.circle")
                }.help("Promote to Parent B")
                Button { model.toggleFavorite(node.id) } label: {
                    Image(systemName: model.lineage.isFavorite(node.id) ? "star.fill" : "star")
                }.help("Favorite")
                Button { openInEditor(node.isfSource) } label: {
                    Image(systemName: "square.and.pencil")
                }.help("Open in editor")
            }
            .buttonStyle(.borderless)
        }
    }
}
