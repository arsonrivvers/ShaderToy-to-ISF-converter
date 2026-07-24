import XCTest
@testable import TrueISFEditor

final class RemixSplitLayoutTests: XCTestCase {
    func test_pointerDrag_recordsClampedWidth_andRestoredLayoutReappliesIt() {
        var layout = RemixSplitLayout(state: RemixWorkspaceState())

        layout.recordPointerWidth(900, zone: .breedingBay)
        XCTAssertEqual(layout.appliedWidth(for: .breedingBay), 420)

        let restored = RemixSplitLayout(state: layout.state)
        XCTAssertEqual(restored.appliedWidth(for: .breedingBay), 420)
    }

    func test_keyboardResize_usesBoundedTwentyPointSteps() {
        var layout = RemixSplitLayout(state: RemixWorkspaceState())

        layout.resizeByKeyboard(.lineage, direction: 1)
        XCTAssertEqual(layout.appliedWidth(for: .lineage), 320)

        for _ in 0..<20 {
            layout.resizeByKeyboard(.lineage, direction: -1)
        }
        XCTAssertEqual(layout.appliedWidth(for: .lineage), 260)
    }

    func test_eachZoneUsesItsOwnWidthBounds() {
        var layout = RemixSplitLayout(state: RemixWorkspaceState())

        layout.recordPointerWidth(0, zone: .breedingBay)
        layout.recordPointerWidth(1_000, zone: .lineage)
        layout.recordPointerWidth(0, zone: .activity)

        XCTAssertEqual(layout.appliedWidth(for: .breedingBay), 240)
        XCTAssertEqual(layout.appliedWidth(for: .lineage), 420)
        XCTAssertEqual(layout.appliedWidth(for: .activity), 120)
    }
}
