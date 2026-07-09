import XCTest
@testable import ShadertoyISFKit

final class TestPatternCatalogTests: XCTestCase {
    func test_allPatternsPresent() {
        XCTAssertEqual(TestPatternCatalog.all.count, 13)
    }

    func test_defaultIsSMPTE() {
        XCTAssertEqual(TestPatternCatalog.default.id, "smpte_bars")
    }

    func test_everyPatternHasValidISFHeader() {
        for p in TestPatternCatalog.all {
            XCTAssertFalse(p.sourceText.isEmpty, "\(p.id) is empty")
            guard let open = p.sourceText.range(of: "/*{"),
                  let close = p.sourceText.range(of: "}*/") else {
                return XCTFail("\(p.id) missing ISF header block")
            }
            let json = "{" + p.sourceText[open.upperBound..<close.lowerBound] + "}"
            let data = Data(json.utf8)
            let obj = try? JSONSerialization.jsonObject(with: data)
            XCTAssertNotNil(obj, "\(p.id) header is not valid JSON")
            XCTAssertTrue(p.sourceText.contains("gl_FragColor"), "\(p.id) has no fragment output")
        }
    }

    /// N12 — `default` must never trap, even with an empty/broken resource bundle: there is an
    /// inline builtin fallback that needs no resources at all.
    func test_builtinFallback_isSelfContained() {
        let p = TestPatternCatalog.builtinFallback
        XCTAssertTrue(p.sourceText.contains("gl_FragColor"))
        XCTAssertFalse(TestPatternCatalog.default.id.isEmpty)
    }

}
