import AppKit
import SwiftUI

/// Accessible ancestry inspector backed by the stable flattened lineage tree.
struct RemixLineageTreeView: View {
    @ObservedObject var model: RemixStudioModel
    let openInEditor: (String) -> Void

    @State private var collapsed: Set<String> = []
    @State private var favoritesOnly = false
    @FocusState private var focusedRowID: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            treeList
            if let id = model.selectedNodeID, let node = model.lineage.node(id) {
                Divider()
                actionStrip(node)
            }
            Divider()
            Button("Undo Parent Change") {
                model.undoParentChange()
            }
            .disabled(!model.canUndoParentChange)
            .help(model.undoParentChangeReason ?? "Restore the parent configuration used by the prior round.")
            if let reason = model.undoParentChangeReason {
                Text(reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
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
        .background(
            RemixLineageKeyCapture(active: focusedRowID != nil) { keyCode, modifiersPresent in
                handleKey(
                    keyCode: keyCode,
                    modifiersPresent: modifiersPresent,
                    visibleIDs: rows.map(\.id)
                )
            }
        )
    }

    private var emptyHint: String {
        if model.lineage.order.isEmpty { return "Add parents and Generate — the family tree grows here." }
        if favoritesOnly { return "No favorites yet — ★ a child to pin it here." }
        return "No compiled shaders yet."
    }

    private func treeRow(_ row: RemixTreeRow) -> some View {
        guard let node = model.lineage.node(row.id) else {
            return AnyView(EmptyView())
        }
        let isSelected = model.selectedNodeID == row.id
        let hasChildren = RemixTreeBuilder.hasRenderedChildren(model.lineage, id: row.id)
        let isCollapsed = collapsed.contains(row.id)
        let presentation = RemixLineagePresentation.row(
            row,
            node: node,
            lineage: model.lineage,
            selected: isSelected,
            collapsed: isCollapsed,
            hasChildren: hasChildren
        )
        let content = HStack(spacing: 4) {
            if hasChildren {
                Button {
                    toggleCollapsed(row.id)
                    focusedRowID = row.id
                } label: {
                    Label(
                        (isCollapsed
                            ? RemixLineagePresentation.RowAction.expand
                            : RemixLineagePresentation.RowAction.collapse).rawValue,
                        systemImage: isCollapsed ? "chevron.right" : "chevron.down"
                    )
                    .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                .font(.caption2)
                .frame(width: 20, height: 20)
                .help(
                    (isCollapsed
                        ? RemixLineagePresentation.RowAction.expand
                        : RemixLineagePresentation.RowAction.collapse).rawValue
                )
            } else {
                Spacer().frame(width: 20)
            }
            swatch(row.id)
            Text(node.label ?? row.id).font(.caption).lineLimit(1)
            if let sec = row.secondaryParentID, let secNode = model.lineage.node(sec) {
                Button {
                    model.selectedNodeID = sec
                    focusedRowID = sec
                } label: {
                    Text(
                        "\(RemixLineagePresentation.RowAction.selectSecondary.rawValue): "
                        + "\(secNode.label ?? sec)"
                    )
                    .font(.caption2)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help(
                    "\(RemixLineagePresentation.RowAction.selectSecondary.rawValue) "
                    + "\(secNode.label ?? sec)"
                )
            }
            if model.lineage.isFavorite(row.id) {
                Image(systemName: "star.fill")
                    .font(.caption2)
                    .foregroundStyle(.yellow)
                    .accessibilityHidden(true)
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, CGFloat(row.depth) * 12)
        .padding(.vertical, 2).padding(.horizontal, 4)
        .background(RoundedRectangle(cornerRadius: 4)
            .fill(isSelected ? Color.accentColor.opacity(0.18) : Color.clear))
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(
                    focusedRowID == row.id ? Color.accentColor : Color.clear,
                    lineWidth: 2
                )
        )
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { openInEditor(node.isfSource) }
        .onTapGesture {
            model.selectedNodeID = row.id
            focusedRowID = row.id
        }
        .focusable()
        .focused($focusedRowID, equals: row.id)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(presentation.label)
        .accessibilityValue(presentation.value)
        .accessibilityHint(presentation.help)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityActions {
            if hasChildren {
                Button(
                    (isCollapsed
                        ? RemixLineagePresentation.RowAction.expand
                        : RemixLineagePresentation.RowAction.collapse).rawValue
                ) {
                    toggleCollapsed(row.id)
                }
            }
            if let primaryID = node.parents.first {
                Button(RemixLineagePresentation.RowAction.selectPrimary.rawValue) {
                    model.selectedNodeID = primaryID
                }
            }
            if node.parents.count > 1 {
                Button(RemixLineagePresentation.RowAction.selectSecondary.rawValue) {
                    model.selectedNodeID = node.parents[1]
                }
            }
            Button(RemixLineagePresentation.RowAction.open.rawValue) {
                openInEditor(node.isfSource)
            }
            Button(RemixLineagePresentation.RowAction.promoteA.rawValue) {
                model.promoteToParent(.a, nodeID: row.id)
            }
            Button(RemixLineagePresentation.RowAction.promoteB.rawValue) {
                model.promoteToParent(.b, nodeID: row.id)
            }
            Button(
                (model.lineage.isFavorite(row.id)
                    ? RemixLineagePresentation.RowAction.removeFavorite
                    : RemixLineagePresentation.RowAction.favorite).rawValue
            ) {
                model.toggleFavorite(row.id)
            }
        }
        return AnyView(content)
    }

    private func toggleCollapsed(_ id: String) {
        if collapsed.contains(id) {
            collapsed.remove(id)
        } else {
            collapsed.insert(id)
        }
    }

    private func handleKey(
        keyCode: UInt16,
        modifiersPresent: Bool,
        visibleIDs: [String]
    ) -> Bool {
        switch RemixLineageKeyboardRoute.route(
            keyCode: keyCode,
            modifiersPresent: modifiersPresent,
            focusedID: focusedRowID,
            visibleIDs: visibleIDs
        ) {
        case .ignore:
            return false
        case .focus(let id):
            focusedRowID = id
            return true
        case .select(let id):
            model.selectedNodeID = id
            focusedRowID = id
            return true
        }
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
        let actions = RemixLineagePresentation.selectedNodeActions(
            favorite: model.lineage.isFavorite(node.id)
        )
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(node.label ?? node.id).font(.caption.bold()).lineLimit(1)
                Spacer()
                Button(RemixLineagePresentation.RowAction.deselect.rawValue) {
                    model.selectedNodeID = nil
                    focusedRowID = node.id
                }
                .buttonStyle(.borderless)
            }
            RemixThumbnailView(
                isf: node.isfSource,
                animating: model.shouldAnimate(
                    node.id,
                    on: .inspector,
                    reduceMotion: reduceMotion
                ),
                               onSnapshot: { img in model.storeSnapshot(id: node.id, image: img) }) { _, _ in }
                .frame(height: 90)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            Text(node.directive).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(actions.filter { $0 != .deselect }, id: \.rawValue) { action in
                    Button(action.rawValue) {
                        perform(action, node: node)
                    }
                }
            }
        }
    }

    private func perform(
        _ action: RemixLineagePresentation.RowAction,
        node: RemixNode
    ) {
        switch action {
        case .promoteA:
            model.promoteToParent(.a, nodeID: node.id)
        case .promoteB:
            model.promoteToParent(.b, nodeID: node.id)
        case .favorite, .removeFavorite:
            model.toggleFavorite(node.id)
        case .open:
            openInEditor(node.isfSource)
        case .deselect:
            model.selectedNodeID = nil
        case .expand, .collapse:
            toggleCollapsed(node.id)
        case .selectPrimary:
            if let id = node.parents.first { model.selectedNodeID = id }
        case .selectSecondary:
            if node.parents.count > 1 { model.selectedNodeID = node.parents[1] }
        }
    }
}

private struct RemixLineageKeyCapture: NSViewRepresentable {
    let active: Bool
    let handler: (UInt16, Bool) -> Bool

    func makeNSView(context: Context) -> KeyView {
        KeyView(handler: handler)
    }

    func updateNSView(_ view: KeyView, context: Context) {
        view.active = active
        view.handler = handler
    }

    final class KeyView: NSView {
        var active = false
        var handler: (UInt16, Bool) -> Bool
        private var monitor: Any?

        init(handler: @escaping (UInt16, Bool) -> Bool) {
            self.handler = handler
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard window != nil, monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self,
                      self.active,
                      event.window === self.window
                else {
                    return event
                }
                let modifiers: NSEvent.ModifierFlags = [.command, .option, .control, .shift]
                return self.handler(
                    event.keyCode,
                    !event.modifierFlags.intersection(modifiers).isEmpty
                ) ? nil : event
            }
        }

        deinit {
            if let monitor { NSEvent.removeMonitor(monitor) }
        }
    }
}
