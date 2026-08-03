import XCTest
@testable import TrueISFEditor

final class RemixLineageTests: XCTestCase {
    private func node(_ id: String, parents: [String] = []) -> RemixNode {
        RemixNode(id: id, isfSource: "/*{}*/", parents: parents, mode: .crossover,
                  steer: "", directive: "", round: 0, status: .compiled)
    }
    func test_insert_recordsParents_andChildrenLookup() {
        var g = RemixLineage()
        g.insert(node("a")); g.insert(node("b"))
        g.insert(node("c", parents: ["a", "b"]))
        XCTAssertEqual(g.node("c")?.parents, ["a", "b"])
        XCTAssertEqual(Set(g.children(of: "a").map(\.id)), ["c"])
    }
    func test_favorites_toggle() {
        var g = RemixLineage(); g.insert(node("a"))
        g.toggleFavorite("a"); XCTAssertTrue(g.isFavorite("a"))
        g.toggleFavorite("a"); XCTAssertFalse(g.isFavorite("a"))
    }

    func test_retainingArtifactsKeepsSeedsAndOnlyReadyGeneratedArtifactIDs() {
        var lineage = RemixLineage()
        lineage.insert(node("seed-0"))
        lineage.insert(node("r1-0", parents: ["seed-0"]))
        lineage.insert(node("r1-1", parents: ["seed-0"]))
        lineage.toggleFavorite("r1-0")
        lineage.toggleFavorite("r1-1")

        let retained = lineage.retainingArtifacts(withIDs: ["r1-1"])

        XCTAssertEqual(retained.allNodes.map(\.id), ["seed-0", "r1-1"])
        XCTAssertFalse(retained.isFavorite("r1-0"))
        XCTAssertTrue(retained.isFavorite("r1-1"))
    }
}
