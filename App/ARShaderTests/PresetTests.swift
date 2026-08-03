import XCTest
@testable import ARShader

final class PresetTests: XCTestCase {

    private func snapshot() -> ParamSnapshot {
        ParamSnapshot(params: ["speed": .float(0.75), "on": .bool(true)])
    }

    // MARK: - Slot cell label (2026-08-03 Client Success review, F6)

    /// The corpus is nine consecutive `AR_Beautiful_Kaleido…` entries, and the cell truncates in
    /// the MIDDLE — so the shared head and tail are exactly the characters that survive while the
    /// discriminating token is deleted. Two slots rendered byte-identical labels because of it.
    func testTheSlotLabelDropsThePartsEveryEntryShares() {
        let p = Preset.capturing(url: URL(fileURLWithPath: "/tmp/AR_Beautiful_KaleidoAlt_v03.fs"),
                                 snapshot: snapshot())
        XCTAssertEqual(p.shortLabel, "Beautiful_KaleidoAlt_v03")
        XCTAssertEqual(p.name, "AR_Beautiful_KaleidoAlt_v03.fs",
                       "the stored name is untouched — this is a display concern only")
    }

    /// Two names that differ ONLY in the middle must still differ after shortening, or the fix
    /// moved the collision rather than removing it.
    func testTwoNamesDifferingInTheMiddleStayDistinct() {
        let a = Preset.capturing(url: URL(fileURLWithPath: "/tmp/AR_Beautiful_KaleidoAlt_v03.fs"),
                                 snapshot: snapshot())
        let b = Preset.capturing(url: URL(fileURLWithPath: "/tmp/AR_Beautiful_KaleidoPolar_v03.fs"),
                                 snapshot: snapshot())
        XCTAssertNotEqual(a.shortLabel, b.shortLabel)
    }

    func testANameWithoutTheSharedPrefixKeepsAllOfIt() {
        let p = Preset.capturing(url: URL(fileURLWithPath: "/tmp/3d Rotate.fs"),
                                 snapshot: snapshot())
        XCTAssertEqual(p.shortLabel, "3d Rotate", "only the extension is shared here")
    }

    /// A cell showing nothing is worse than a cell showing noise — the operator cannot tell it
    /// apart from an empty slot.
    func testANameMadeEntirelyOfSharedPartsIsLeftAlone() {
        var p = Preset.capturing(url: URL(fileURLWithPath: "/tmp/AR_.fs"), snapshot: snapshot())
        p.name = "AR_.fs"
        XCTAssertEqual(p.shortLabel, "AR_.fs", "stripping would leave the cell blank")
    }

    func testCapturingNamesThePresetAfterItsShaderFile() {
        let p = Preset.capturing(url: URL(fileURLWithPath: "/tmp/AR_Genuary_17.fs"),
                                 snapshot: snapshot())
        XCTAssertEqual(p.name, "AR_Genuary_17.fs",
                       "3b derives the name from the file; 3c makes it editable")
    }

    func testTwoPresetsOfTheSameShaderAreDistinctThings() {
        let url = URL(fileURLWithPath: "/tmp/same.fs")
        let a = Preset.capturing(url: url, snapshot: snapshot())
        let b = Preset.capturing(url: url, snapshot: snapshot())
        XCTAssertNotEqual(a.id, b.id,
                          "Capturing the same shader twice with different values must produce two "
                          + "slots that can differ, not one identity shared between them")
    }

    func testAPresetSurvivesAJSONRoundTripWithItsValuesIntact() throws {
        let original = Preset.capturing(url: URL(fileURLWithPath: "/tmp/x.fs"), snapshot: snapshot())
        let decoded = try JSONDecoder().decode(
            Preset.self, from: try JSONEncoder().encode(original))
        XCTAssertEqual(decoded, original)
        XCTAssertEqual(decoded.snapshot.params["speed"], .float(0.75),
                       "The dialled values are the whole point of a preset")
    }
}
