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
}
