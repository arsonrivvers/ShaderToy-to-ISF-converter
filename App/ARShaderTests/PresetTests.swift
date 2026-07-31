import XCTest
@testable import ARShader

final class PresetTests: XCTestCase {

    private func snapshot() -> ParamSnapshot {
        ParamSnapshot(params: ["speed": .float(0.75), "on": .bool(true)])
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
