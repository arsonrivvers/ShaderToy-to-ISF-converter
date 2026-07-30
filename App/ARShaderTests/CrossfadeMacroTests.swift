import XCTest

final class CrossfadeMacroTests: XCTestCase {
    private let acc = 1e-12

    func testFullyLeftGivesDeckOneEverythingAndDeckTwoNothing() {
        XCTAssertEqual(CrossfadeMacro.weight(forLayerIndex: 0, layerCount: 2, position: 0),
                       1.0, accuracy: acc)
        XCTAssertEqual(CrossfadeMacro.weight(forLayerIndex: 1, layerCount: 2, position: 0),
                       0.0, accuracy: acc)
    }

    func testFullyRightGivesDeckTwoEverything() {
        XCTAssertEqual(CrossfadeMacro.weight(forLayerIndex: 0, layerCount: 2, position: 1),
                       0.0, accuracy: acc)
        XCTAssertEqual(CrossfadeMacro.weight(forLayerIndex: 1, layerCount: 2, position: 1),
                       1.0, accuracy: acc)
    }

    func testCentreGivesBothHalf() {
        XCTAssertEqual(CrossfadeMacro.weight(forLayerIndex: 0, layerCount: 2, position: 0.5),
                       0.5, accuracy: acc)
        XCTAssertEqual(CrossfadeMacro.weight(forLayerIndex: 1, layerCount: 2, position: 0.5),
                       0.5, accuracy: acc)
    }

    func testPositionIsClampedToTheUnitInterval() {
        XCTAssertEqual(CrossfadeMacro.weight(forLayerIndex: 0, layerCount: 2, position: -3),
                       1.0, accuracy: acc)
        XCTAssertEqual(CrossfadeMacro.weight(forLayerIndex: 1, layerCount: 2, position: 99),
                       1.0, accuracy: acc)
    }

    func testASingleLayerIgnoresTheCrossfader() {
        // The model must extend past two decks without redesign (spec §7.1). With one layer there
        // is nothing to fade between, so the fader cannot silently mute it.
        for x in [0.0, 0.25, 0.5, 1.0] {
            XCTAssertEqual(CrossfadeMacro.weight(forLayerIndex: 0, layerCount: 1, position: x),
                           1.0, accuracy: acc)
        }
    }

    func testThreeLayersEachPeakAtTheirOwnSlot() {
        // Proves the generalisation is real rather than a two-deck special case.
        XCTAssertEqual(CrossfadeMacro.weight(forLayerIndex: 0, layerCount: 3, position: 0.0),
                       1.0, accuracy: acc)
        XCTAssertEqual(CrossfadeMacro.weight(forLayerIndex: 1, layerCount: 3, position: 0.5),
                       1.0, accuracy: acc)
        XCTAssertEqual(CrossfadeMacro.weight(forLayerIndex: 2, layerCount: 3, position: 1.0),
                       1.0, accuracy: acc)
        XCTAssertEqual(CrossfadeMacro.weight(forLayerIndex: 2, layerCount: 3, position: 0.0),
                       0.0, accuracy: acc)
    }

    func testEffectiveOpacityIsTheProductOfBothValues() {
        XCTAssertEqual(CrossfadeMacro.effectiveOpacity(userOpacity: 0.8, weight: 0.5),
                       0.4, accuracy: acc)
        XCTAssertEqual(CrossfadeMacro.effectiveOpacity(userOpacity: 1.0, weight: 1.0),
                       1.0, accuracy: acc)
        XCTAssertEqual(CrossfadeMacro.effectiveOpacity(userOpacity: 0.0, weight: 1.0),
                       0.0, accuracy: acc)
    }

    func testEffectiveOpacityClampsBothInputs() {
        XCTAssertEqual(CrossfadeMacro.effectiveOpacity(userOpacity: 2.0, weight: 2.0),
                       1.0, accuracy: acc)
        XCTAssertEqual(CrossfadeMacro.effectiveOpacity(userOpacity: -1.0, weight: 0.5),
                       0.0, accuracy: acc)
    }
}
