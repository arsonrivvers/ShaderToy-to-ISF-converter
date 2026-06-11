import XCTest
@testable import TrueISFEditor

final class RemixDomainTests: XCTestCase {
    func test_node_defaults_andEquatable() {
        let n = RemixNode(id: "x", isfSource: "/*{}*/", parents: ["a","b"],
                          mode: .crossover, steer: "wavy", directive: "chaotic", round: 1)
        XCTAssertEqual(n.status, .generating)
        XCTAssertEqual(n.parents, ["a","b"])
        XCTAssertEqual(n.mode, .crossover)
    }
}
