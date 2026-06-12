import Foundation

/// One row of the flattened lineage tree (the right rail renders these in order).
struct RemixTreeRow: Identifiable, Equatable {
    let id: String                  // node id
    let depth: Int                  // indent level
    let secondaryParentID: String?  // parents[1] for crossover children → ⚭ badge
}

/// Flattens the lineage DAG into displayable rows. Each node renders exactly once, under
/// `parents.first`, so traversal is a true tree even though crossover children have two parents
/// (the second parent surfaces as `secondaryParentID`). Failed and still-generating nodes are
/// hidden — the gallery owns in-flight/failed visibility; the tree is the album of what worked.
enum RemixTreeBuilder {
    static func flatten(_ lineage: RemixLineage,
                        collapsed: Set<String>,
                        favoritesOnly: Bool) -> [RemixTreeRow] {
        let visible = lineage.order.compactMap { lineage.node($0) }.filter { $0.status == .compiled }
        if favoritesOnly {
            return visible.filter { lineage.isFavorite($0.id) }
                .map { RemixTreeRow(id: $0.id, depth: 0, secondaryParentID: secondary($0)) }
        }
        var rows: [RemixTreeRow] = []
        func emit(_ node: RemixNode, depth: Int) {
            rows.append(RemixTreeRow(id: node.id, depth: depth, secondaryParentID: secondary(node)))
            guard !collapsed.contains(node.id) else { return }
            for child in visible where child.parents.first == node.id { emit(child, depth: depth + 1) }
        }
        for root in visible where root.parents.isEmpty { emit(root, depth: 0) }
        return rows
    }

    /// True when a node has at least one compiled child that RENDERS under it (parents.first) —
    /// drives the view's disclosure triangle. Children where this node is only the secondary
    /// parent render elsewhere and don't count.
    static func hasRenderedChildren(_ lineage: RemixLineage, id: String) -> Bool {
        lineage.order.compactMap { lineage.node($0) }
            .contains { $0.parents.first == id && $0.status == .compiled }
    }

    private static func secondary(_ n: RemixNode) -> String? {
        n.parents.count >= 2 ? n.parents[1] : nil
    }
}
