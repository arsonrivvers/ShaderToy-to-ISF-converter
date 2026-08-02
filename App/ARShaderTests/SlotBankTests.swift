import XCTest
@testable import ARShader

@MainActor
final class SlotBankTests: XCTestCase {

    private func preset(_ path: String = "/tmp/a.fs", speed: Double = 0.5) -> Preset {
        Preset.capturing(url: URL(fileURLWithPath: path),
                         snapshot: ParamSnapshot(params: ["speed": .float(speed)]))
    }

    /// A file that really exists, so availability is tested against the filesystem rather than a stub.
    private func realFileURL() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("slotbank-\(UUID().uuidString).fs")
        try "// present".write(to: url, atomically: true, encoding: .utf8)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    func testAFreshBankHasExactlySlotCountEmptySlots() {
        let bank = SlotBank()
        XCTAssertEqual(bank.slots.count, SlotBank.slotCount)
        XCTAssertTrue(bank.slots.allSatisfy { $0 == nil })
    }

    func testCaptureFillsOnlyTheGivenIndex() {
        let bank = SlotBank()
        bank.capture(preset(), into: 3)
        XCTAssertNotNil(bank.slots[3])
        XCTAssertEqual(bank.slots.compactMap { $0 }.count, 1,
                       "Capture must not disturb neighbouring slots")
    }

    func testRecallOfAnEmptySlotReturnsNil() {
        XCTAssertNil(SlotBank().recall(0))
    }

    func testRecallReturnsTheCapturedValuesIntact() throws {
        let bank = SlotBank()
        bank.capture(Preset.capturing(url: try realFileURL(),
                                      snapshot: ParamSnapshot(params: ["speed": .float(0.9)])),
                     into: 2)
        let got = try XCTUnwrap(bank.recall(2))
        XCTAssertEqual(got.snapshot.params["speed"], .float(0.9),
                       "The dialled values must survive capture and come back on recall")
    }

    func testClearEmptiesOneSlotAndLeavesItsNeighboursAlone() {
        let bank = SlotBank()
        bank.capture(preset(), into: 0)
        bank.capture(preset(), into: 1)
        bank.clear(0)
        XCTAssertNil(bank.slots[0])
        XCTAssertNotNil(bank.slots[1], "Clearing one slot must not clear the bank")
    }

    func testASlotWhoseFileHasGoneIsUnavailableAndRecallsNilButStaysOccupied() {
        let bank = SlotBank()
        bank.capture(preset("/tmp/definitely-not-here-\(UUID().uuidString).fs"), into: 4)
        XCTAssertFalse(bank.isAvailable(4))
        XCTAssertNil(bank.recall(4), "Firing an unavailable slot does nothing")
        XCTAssertNotNil(bank.slots[4],
                        "It is NOT cleared — external drives come back, and auto-clearing would "
                        + "destroy the operator's bank on a bad mount")
    }

    func testASlotWhoseFileExistsIsAvailable() throws {
        let bank = SlotBank()
        bank.capture(Preset.capturing(url: try realFileURL(),
                                      snapshot: ParamSnapshot(params: [:])), into: 5)
        XCTAssertTrue(bank.isAvailable(5))
    }

    func testAnEmptySlotIsNotReportedAvailable() {
        XCTAssertFalse(SlotBank().isAvailable(0), "Nothing to fire is not the same as ready to fire")
    }

    /// Every index-taking method must survive a bad index rather than trap. A MIDI pad or a future
    /// larger grid can address a slot this bank does not have.
    func testOutOfRangeIndicesAreIgnoredRatherThanTrapping() {
        let bank = SlotBank()
        bank.capture(preset(), into: 99)
        bank.clear(-1)
        XCTAssertNil(bank.recall(99))
        XCTAssertFalse(bank.isAvailable(-1))
        XCTAssertEqual(bank.slots.count, SlotBank.slotCount)
    }

    func testMutationsNotifyTheOwnerSoItCanPersist() {
        let bank = SlotBank()
        var changes = 0
        bank.onChange = { changes += 1 }
        bank.capture(preset(), into: 0)
        bank.clear(0)
        XCTAssertEqual(changes, 2, "Capture and clear each persist; recall does not mutate")
        bank.onChange = nil
    }

    func testRecallDoesNotNotifyBecauseItChangesNothing() {
        let bank = SlotBank()
        bank.capture(preset(), into: 0)
        var changes = 0
        bank.onChange = { changes += 1 }
        _ = bank.recall(0)
        XCTAssertEqual(changes, 0, "Firing a slot must not rewrite the bank to disk mid-set")
        bank.onChange = nil
    }

    // MARK: One-deep undo (final-review F3)

    /// The gesture this exists for: right-click, reflexive second click, a dialled-in look gone and
    /// persisted before the menu finished dismissing. There was no way back at all.
    func testClearingASlotCanBeUndoneWithTheLookIntact() throws {
        let bank = SlotBank()
        bank.capture(preset(speed: 0.77), into: 4)
        bank.clear(4)
        XCTAssertNil(bank.slots[4])

        bank.undo()
        XCTAssertEqual(bank.slots[4]?.snapshot.params["speed"], .float(0.77),
                       "the restored look must carry its dialled values, not just its URL")
        XCTAssertNil(bank.undoable, "one deep, never a redo stack")
    }

    /// The ⌥-drop half, which falls out of the same one-deep slot. A drop onto a filled slot is the
    /// other way a dialled-in look leaves the bank.
    func testAnOverwritingCaptureCanBeUndoneBackToTheReplacedLook() throws {
        let bank = SlotBank()
        bank.capture(preset("/tmp/original.fs", speed: 0.1), into: 2)
        bank.capture(preset("/tmp/replacement.fs", speed: 0.9), into: 2)

        bank.undo()
        XCTAssertEqual(bank.slots[2]?.shaderURL.lastPathComponent, "original.fs")
        XCTAssertEqual(bank.slots[2]?.snapshot.params["speed"], .float(0.1))
    }

    /// Undo must never be the thing that destroys a look. A capture into the armed index supersedes
    /// whatever was armed there, so restoring cannot silently overwrite what was just captured.
    func testACaptureIntoTheClearedSlotDisarmsTheUndoRatherThanArmingItToOverwrite() {
        let bank = SlotBank()
        bank.capture(preset("/tmp/old.fs"), into: 1)
        bank.clear(1)
        bank.capture(preset("/tmp/new.fs"), into: 1)
        XCTAssertNil(bank.undoable,
                     "the cleared look at index 1 has been superseded by a fresh capture there")

        bank.undo()
        XCTAssertEqual(bank.slots[1]?.shaderURL.lastPathComponent, "new.fs",
                       "undo must be a no-op here, not a way to destroy the new capture")
    }

    func testAFreshBankHasNothingToUndoAndUndoIsANoOp() {
        let bank = SlotBank()
        XCTAssertNil(bank.undoable, "nothing has been destroyed, so no menu item may appear")
        var changes = 0
        bank.onChange = { changes += 1 }
        bank.undo()
        XCTAssertEqual(changes, 0, "an empty undo must not rewrite the bank to disk mid-set")
        XCTAssertTrue(bank.slots.allSatisfy { $0 == nil })
        bank.onChange = nil
    }

    /// Clearing an ALREADY-empty slot must not arm anything: an undo offering to restore nothing is
    /// a menu item that lies.
    func testClearingAnEmptySlotArmsNothing() {
        let bank = SlotBank()
        bank.clear(0)
        XCTAssertNil(bank.undoable)
    }

    /// The item's own copy, since the strip's context menu is the only way to invoke it and the
    /// operator fires this bank by position.
    func testTheUndoMenuTitleNamesTheSlotAndTheGestureBeingUndone() {
        let bank = SlotBank()
        bank.capture(preset(), into: 6)
        bank.clear(6)
        XCTAssertEqual(bank.undoable?.menuTitle, "Undo clear slot 7")

        bank.capture(preset(), into: 0)
        bank.capture(preset(), into: 0)
        XCTAssertEqual(bank.undoable?.menuTitle, "Undo replace slot 1")
    }

    func testUndoPersistsLikeEveryOtherWrite() {
        let bank = SlotBank()
        bank.capture(preset(), into: 0)
        bank.clear(0)
        var changes = 0
        bank.onChange = { changes += 1 }
        bank.undo()
        XCTAssertEqual(changes, 1,
                       "a restored look that is not persisted comes back only until relaunch")
        bank.onChange = nil
    }

    // MARK: Task 7R — the model has no concept of rows at all

    /// `slotCount` is derived from `perRow * maxRows`, not an independent literal — if either
    /// constant changes, `slotCount` moves with it rather than silently drifting out of sync.
    func testSlotCountIsExactlyPerRowTimesMaxRows() {
        XCTAssertEqual(SlotBank.slotCount, SlotBank.perRow * SlotBank.maxRows)
        XCTAssertEqual(SlotBank.perRow, 8)
        XCTAssertEqual(SlotBank.maxRows, 5)
    }

    /// The bank has no idea what a "row" is. Capturing into an index that would sit in row 5 (the
    /// last row a 5-row strip can draw) must work exactly like any other index — there is no
    /// row-aware validation anywhere in this type for a resize to accidentally trip.
    func testCaptureAndRecallWorkAcrossTheFullSlotRangeIncludingTheLastRow() throws {
        let bank = SlotBank()
        let lastIndex = SlotBank.slotCount - 1
        bank.capture(Preset.capturing(url: try realFileURL(),
                                      snapshot: ParamSnapshot(params: ["speed": .float(0.42)])),
                     into: lastIndex)
        let got = try XCTUnwrap(bank.recall(lastIndex))
        XCTAssertEqual(got.snapshot.params["speed"], .float(0.42),
                       "The last slot in the full grid behaves identically to any other slot")
    }

    func testHiddenFilledCountCountsOnlyFilledSlotsBeyondTheDrawnRows() {
        let bank = SlotBank()
        bank.capture(preset(), into: 0)                     // row 1, drawn at one row
        bank.capture(preset(), into: SlotBank.perRow)       // row 2
        bank.capture(preset(), into: SlotBank.perRow * 2)   // row 3

        XCTAssertEqual(bank.hiddenFilledCount(drawnRows: 1), 2)
        XCTAssertEqual(bank.hiddenFilledCount(drawnRows: 2), 1)
        XCTAssertEqual(bank.hiddenFilledCount(drawnRows: 3), 0)
    }

    /// The collapse defect, at the model seam. Collapsed draws ZERO rows, so every filled slot is
    /// hidden — a count derived from the row setting alone reports the collapsed strip as hiding
    /// nothing, and the operator's looks vanish with no marker saying they still exist.
    func testDrawingZeroRowsHidesEveryFilledSlot() {
        let bank = SlotBank()
        bank.capture(preset(), into: 0)
        bank.capture(preset(), into: 5)

        XCTAssertEqual(bank.hiddenFilledCount(drawnRows: 0), 2,
                       "With nothing drawn, every captured look is hidden")
    }

    /// Row counts outside the grid must not trap on a slice bound.
    func testHiddenFilledCountToleratesOutOfRangeRowCounts() {
        let bank = SlotBank()
        bank.capture(preset(), into: 0)

        XCTAssertEqual(bank.hiddenFilledCount(drawnRows: SlotBank.maxRows + 4), 0)
        XCTAssertEqual(bank.hiddenFilledCount(drawnRows: -1), 1,
                       "A negative row count draws nothing, so nothing is visible")
    }
}
