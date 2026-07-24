import XCTest
@testable import TrueISFEditor

final class RemixWorkspaceStateTests: XCTestCase {
    func test_defaultState_isGridWithNoSelection() {
        let state = RemixWorkspaceState()

        XCTAssertEqual(state.canvasMode, .grid)
        XCTAssertNil(state.focusedChildID)
        XCTAssertEqual(state.comparedChildIDs, [])
    }

    func test_comparison_isStableOrderedAndCappedAtTwo() {
        var state = RemixWorkspaceState()

        state.toggleComparison("a")
        state.toggleComparison("b")
        state.toggleComparison("c")

        XCTAssertEqual(state.comparedChildIDs, ["b", "c"])
        XCTAssertEqual(state.canvasMode, .comparison)
    }

    func test_comparisonToggle_removesExistingChildAndReturnsToGridWhenEmpty() {
        var state = RemixWorkspaceState()
        state.toggleComparison("a")

        state.toggleComparison("a")

        XCTAssertEqual(state.comparedChildIDs, [])
        XCTAssertEqual(state.canvasMode, .grid)
    }

    func test_focusMode_restoresExactZoneState() {
        var state = RemixWorkspaceState()
        state.resize(.breedingBay, to: 312)
        state.collapse(.lineage)

        state.enterFocusMode()

        XCTAssertTrue(state.collapsedZones.contains(.breedingBay))
        XCTAssertTrue(state.collapsedZones.contains(.lineage))
        state.exitFocusMode()
        XCTAssertEqual(state.zoneWidths[.breedingBay], 312)
        XCTAssertTrue(state.collapsedZones.contains(.lineage))
        XCTAssertFalse(state.collapsedZones.contains(.breedingBay))
    }

    func test_narrowLayout_collapsesLineageThenBreedingBay_neverCanvas() {
        var state = RemixWorkspaceState()

        state.applyNarrowLayout(availableWidth: 850)
        XCTAssertTrue(state.collapsedZones.contains(.lineage))
        XCTAssertFalse(state.collapsedZones.contains(.breedingBay))

        state.applyNarrowLayout(availableWidth: 620)
        XCTAssertTrue(state.collapsedZones.contains(.breedingBay))
    }

    func test_gridMovement_clampsWithoutLosingFocus() {
        var state = RemixWorkspaceState()
        let childIDs = ["a", "b", "c", "d", "e"]
        state.focus("e")

        state.moveFocus(.moveRight, columns: 3, childIDs: childIDs)
        XCTAssertEqual(state.focusedChildID, "e")

        state.moveFocus(.moveDown, columns: 3, childIDs: childIDs)
        XCTAssertEqual(state.focusedChildID, "e")

        state.moveFocus(.moveLeft, columns: 3, childIDs: childIDs)
        XCTAssertEqual(state.focusedChildID, "d")

        state.moveFocus(.moveUp, columns: 3, childIDs: childIDs)
        XCTAssertEqual(state.focusedChildID, "a")
    }

    func test_gridMovement_downWithoutSameColumnCellKeepsFocus() {
        var state = RemixWorkspaceState()
        let childIDs = ["a", "b", "c", "d", "e"]
        state.focus("c")

        state.moveFocus(.moveDown, columns: 3, childIDs: childIDs)

        XCTAssertEqual(state.focusedChildID, "c")
    }

    func test_nonMovementCommandWithNoFocusDoesNotInitializeFocus() {
        var state = RemixWorkspaceState()

        state.moveFocus(.favorite, columns: 3, childIDs: ["a", "b", "c"])

        XCTAssertNil(state.focusedChildID)
    }

    func test_accessibilitySummary_namesStatusPositionDirectiveAndActions() {
        let summary = RemixWorkspaceState.accessibilitySummary(
            name: "Child 3",
            status: "Compiled",
            position: 3,
            total: 5,
            directive: "Increase motion",
            actions: ["Compare", "Promote to Parent A"]
        )

        XCTAssertEqual(
            summary,
            "Child 3. Compiled. 3 of 5. Directive: Increase motion. Actions: Compare, Promote to Parent A."
        )
    }
}
