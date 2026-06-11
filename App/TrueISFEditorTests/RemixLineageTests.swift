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
}
