import XCTest

final class SymbolsResourceTests: XCTestCase {
    struct Sym: Decodable { let name: String; let kind: String; let signature: String; let summary: String }
    func testSymbolsJSONValid() throws {
        let url = try XCTUnwrap(
            Bundle(for: Self.self).url(forResource: "symbols", withExtension: "json")
            ?? Bundle.main.url(forResource: "symbols", withExtension: "json"))
        let syms = try JSONDecoder().decode([Sym].self, from: Data(contentsOf: url))
        XCTAssertGreaterThan(syms.count, 30)
        XCTAssertEqual(Set(syms.map { $0.name }).count, syms.count, "no duplicate names")
        for core in ["IMG_PIXEL","RENDERSIZE","isf_FragNormCoord","smoothstep"] {
            XCTAssertTrue(syms.contains { $0.name == core }, "missing core symbol \(core)")
        }
        for s in syms { XCTAssertFalse(s.signature.isEmpty); XCTAssertFalse(s.summary.isEmpty) }
    }
}
