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

    func test_directives_pickN_areDistinct_andStable() {
        let a = RemixDirectives.pick(3, seed: 0)
        XCTAssertEqual(a.count, 3)
        XCTAssertEqual(Set(a).count, 3)            // distinct
        XCTAssertEqual(RemixDirectives.pick(3, seed: 0), a)   // deterministic for a given seed
    }
    func test_directives_pickMoreThanCatalog_wrapsWithoutCrash() {
        XCTAssertEqual(RemixDirectives.pick(99, seed: 1).count, 99)
    }
}
