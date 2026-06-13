import XCTest
@testable import TrueISFEditor

final class RemixCrossoverSettingsTests: XCTestCase {
    private func lines(_ s: RemixCrossoverSettings, _ mode: RemixMode) -> String {
        s.promptLines(mode: mode).joined(separator: "\n").lowercased()
    }

    func test_defaults_balancedAndAllDirectivesEnabled() {
        let s = RemixCrossoverSettings()
        XCTAssertEqual(s.balance, 0.5, accuracy: 0.0001)
        XCTAssertEqual(s.enabledDirectives, Set(RemixDirectives.catalog))
        XCTAssertTrue(s.traitSources.isEmpty)
    }

    func test_balanced_emitsEqualWeightLine_crossover() {
        let l = lines(RemixCrossoverSettings(), .crossover)
        XCTAssertTrue(l.contains("equally"))
        XCTAssertFalse(l.contains("toward parent b"))
    }

    func test_leaned_emitsPercentLine_crossover() {
        var s = RemixCrossoverSettings(); s.balance = 0.7
        let l = lines(s, .crossover)
        XCTAssertTrue(l.contains("70%"))
        XCTAssertTrue(l.contains("toward parent b"))
        XCTAssertTrue(l.contains("30%"))
    }

    func test_traitRouting_emitsPerPinnedTrait_inTraitOrder() {
        var s = RemixCrossoverSettings()
        s.setSource(.b, for: .motion)
        s.setSource(.a, for: .structure)
        let pieces = s.promptLines(mode: .crossover)
        let joined = pieces.joined(separator: "\n")
        XCTAssertTrue(joined.contains("Take the structure primarily from Parent A"))
        XCTAssertTrue(joined.contains("Take the motion primarily from Parent B"))
        // structure precedes motion (RemixTrait.allCases order)
        XCTAssertLessThan(joined.range(of: "structure")!.lowerBound,
                          joined.range(of: "motion")!.lowerBound)
    }

    func test_routedTrait_andBalance_coexist() {
        var s = RemixCrossoverSettings(); s.balance = 0.7; s.setSource(.a, for: .structure)
        let l = lines(s, .crossover)
        XCTAssertTrue(l.contains("structure primarily from parent a"))  // routing line
        XCTAssertTrue(l.contains("70%"))                                // balance line (for auto traits)
    }

    func test_variationBands() {
        func band(_ v: Double) -> String { var s = RemixCrossoverSettings(); s.variation = v; return lines(s, .crossover) }
        XCTAssertTrue(band(0.1).contains("faithful"))
        XCTAssertTrue(band(0.4).contains("balance"))
        XCTAssertTrue(band(0.6).contains("adventurous"))
        XCTAssertTrue(band(0.9).contains("wild"))
    }

    func test_mutate_omitsBalanceAndRouting_keepsVariation() {
        var s = RemixCrossoverSettings(); s.balance = 0.7; s.setSource(.a, for: .structure); s.variation = 0.9
        let l = lines(s, .mutate)
        XCTAssertFalse(l.contains("parent b"))
        XCTAssertFalse(l.contains("primarily from parent"))
        XCTAssertTrue(l.contains("wild"))            // variation still present in mutate
    }

    func test_summary_reflectsState() {
        var s = RemixCrossoverSettings()
        XCTAssertTrue(s.summary.lowercased().contains("balanced"))
        s.balance = 0.7; s.setSource(.a, for: .structure)
        XCTAssertTrue(s.summary.contains("70% B"))
        XCTAssertTrue(s.summary.lowercased().contains("1 trait"))
    }

    func test_codableRoundTrip() throws {
        var s = RemixCrossoverSettings(); s.balance = 0.7; s.variation = 0.8
        s.setSource(.b, for: .color); s.enabledDirectives = ["lean minimal and restrained"]
        let data = try JSONEncoder().encode(s)
        let back = try JSONDecoder().decode(RemixCrossoverSettings.self, from: data)
        XCTAssertEqual(s, back)
    }
}
