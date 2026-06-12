import XCTest
@testable import TrueISFEditor

final class RemixTreeBuilderTests: XCTestCase {
    /// Build a node quickly. Defaults: compiled, no parents.
    private func node(_ id: String, parents: [String] = [],
                      status: RemixNode.Status = .compiled, label: String? = nil) -> RemixNode {
        RemixNode(id: id, isfSource: "/*{}*/", parents: parents, mode: .crossover,
                  steer: "", directive: "d", round: 0, status: status, label: label)
    }
    private func lineage(_ nodes: [RemixNode], favorites: [String] = []) -> RemixLineage {
        var l = RemixLineage()
        nodes.forEach { l.insert($0) }
        favorites.forEach { l.toggleFavorite($0) }
        return l
    }

    func test_roots_areParentlessNodes_inInsertionOrder_atDepth0() {
        let l = lineage([node("seed-0"), node("seed-1")])
        let rows = RemixTreeBuilder.flatten(l, collapsed: [], favoritesOnly: false)
        XCTAssertEqual(rows.map(\.id), ["seed-0", "seed-1"])
        XCTAssertEqual(rows.map(\.depth), [0, 0])
    }

    func test_children_nestUnderFirstParent_depthIncrements() {
        let l = lineage([node("s"), node("r1-0", parents: ["s"]), node("r2-0", parents: ["r1-0"])])
        let rows = RemixTreeBuilder.flatten(l, collapsed: [], favoritesOnly: false)
        XCTAssertEqual(rows.map(\.id), ["s", "r1-0", "r2-0"])
        XCTAssertEqual(rows.map(\.depth), [0, 1, 2])
    }

    func test_crossoverChild_rendersOnce_underParentA_withSecondaryBadge() {
        let l = lineage([node("a"), node("b"), node("r1-0", parents: ["a", "b"])])
        let rows = RemixTreeBuilder.flatten(l, collapsed: [], favoritesOnly: false)
        XCTAssertEqual(rows.map(\.id), ["a", "r1-0", "b"])   // child under a, NOT duplicated under b
        XCTAssertEqual(rows[1].depth, 1)
        XCTAssertEqual(rows[1].secondaryParentID, "b")
        XCTAssertNil(rows[0].secondaryParentID)
    }

    func test_failed_andGenerating_areHidden() {
        let l = lineage([node("s"),
                         node("bad", parents: ["s"], status: .failed("x")),
                         node("pending", parents: ["s"], status: .generating),
                         node("ok", parents: ["s"])])
        let rows = RemixTreeBuilder.flatten(l, collapsed: [], favoritesOnly: false)
        XCTAssertEqual(rows.map(\.id), ["s", "ok"])
    }

    func test_collapse_prunesAllDescendants() {
        let l = lineage([node("s"), node("r1-0", parents: ["s"]),
                         node("r2-0", parents: ["r1-0"]), node("r1-1", parents: ["s"])])
        let rows = RemixTreeBuilder.flatten(l, collapsed: ["r1-0"], favoritesOnly: false)
        XCTAssertEqual(rows.map(\.id), ["s", "r1-0", "r1-1"])   // r2-0 pruned, r1-0 itself stays
        let rows2 = RemixTreeBuilder.flatten(l, collapsed: ["s"], favoritesOnly: false)
        XCTAssertEqual(rows2.map(\.id), ["s"])                  // whole subtree pruned
    }

    func test_favoritesOnly_returnsFlatStarredList_inInsertionOrder() {
        let l = lineage([node("s"), node("r1-0", parents: ["s"]), node("r1-1", parents: ["s"])],
                        favorites: ["r1-1", "s"])
        let rows = RemixTreeBuilder.flatten(l, collapsed: [], favoritesOnly: true)
        XCTAssertEqual(rows.map(\.id), ["s", "r1-1"])           // insertion order, not toggle order
        XCTAssertEqual(rows.map(\.depth), [0, 0])
    }

    func test_flatten_isStable_acrossCalls() {
        let l = lineage([node("s"), node("r1-0", parents: ["s"])])
        XCTAssertEqual(RemixTreeBuilder.flatten(l, collapsed: [], favoritesOnly: false),
                       RemixTreeBuilder.flatten(l, collapsed: [], favoritesOnly: false))
    }

    func test_hasRenderedChildren_countsOnlyFirstParentCompiledChildren() {
        let l = lineage([node("a"), node("b"),
                         node("r1-0", parents: ["a", "b"]),
                         node("bad", parents: ["b"], status: .failed("x"))])
        XCTAssertTrue(RemixTreeBuilder.hasRenderedChildren(l, id: "a"))
        XCTAssertFalse(RemixTreeBuilder.hasRenderedChildren(l, id: "b"))  // secondary + failed don't count
    }
}
