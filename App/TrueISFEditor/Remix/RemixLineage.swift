import Foundation

/// The evolution graph: every node keyed by id, with parent links recorded so the Phase-2 tree GUI can
/// render it directly. Also tracks the favorites set. Pure value type — the studio model owns one.
struct RemixLineage: Codable, Equatable {
    private(set) var nodes: [String: RemixNode] = [:]
    private(set) var order: [String] = []        // insertion order, for stable listing
    private(set) var favorites: Set<String> = []

    mutating func insert(_ n: RemixNode) {
        if nodes[n.id] == nil { order.append(n.id) }
        nodes[n.id] = n
    }
    func node(_ id: String) -> RemixNode? { nodes[id] }
    func children(of id: String) -> [RemixNode] {
        order.compactMap { nodes[$0] }.filter { $0.parents.contains(id) }
    }
    func isFavorite(_ id: String) -> Bool { favorites.contains(id) }
    mutating func toggleFavorite(_ id: String) {
        if favorites.contains(id) { favorites.remove(id) } else { favorites.insert(id) }
    }

    var allNodes: [RemixNode] {
        order.compactMap { nodes[$0] }
    }

    /// Seeds are durable inputs. Generated nodes are durable artifacts only when a Ready run names
    /// their ID, so restored placeholder or failed-node copies cannot leak into lineage UI.
    func retainingArtifacts(withIDs artifactIDs: Set<String>) -> RemixLineage {
        var retained = RemixLineage()
        for node in allNodes where node.id.hasPrefix("seed-") || artifactIDs.contains(node.id) {
            retained.insert(node)
            if isFavorite(node.id) {
                retained.toggleFavorite(node.id)
            }
        }
        return retained
    }

    var artifacts: [RemixNode] {
        allNodes.filter { $0.status == .compiled }
    }
}
