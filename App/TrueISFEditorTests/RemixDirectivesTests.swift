import XCTest
@testable import TrueISFEditor

final class RemixDirectivesTests: XCTestCase {
    func test_pick_default_usesFullCatalog() {
        let got = RemixDirectives.pick(3, seed: 0)
        XCTAssertEqual(got.count, 3)
        XCTAssertTrue(got.allSatisfy(RemixDirectives.catalog.contains))
    }

    func test_pick_from_restrictsToPool() {
        let pool = ["lean minimal and restrained", "emphasize bold color and palette shifts"]
        let got = RemixDirectives.pick(4, seed: 1, from: pool)
        XCTAssertEqual(got.count, 4)
        XCTAssertTrue(got.allSatisfy(pool.contains))
    }

    func test_pick_emptyPool_fallsBackToCatalog() {
        let got = RemixDirectives.pick(2, seed: 0, from: [])
        XCTAssertEqual(got.count, 2)
        XCTAssertTrue(got.allSatisfy(RemixDirectives.catalog.contains))
    }

    func test_pick_deterministicBySeed() {
        XCTAssertEqual(RemixDirectives.pick(5, seed: 3, from: RemixDirectives.catalog),
                       RemixDirectives.pick(5, seed: 3, from: RemixDirectives.catalog))
    }
}
