### Task 2: `SlotBank`

**Files:**
- Create: `App/ARShader/SlotBank.swift`
- Test: `App/ARShaderTests/SlotBankTests.swift`

**Interfaces:**
- Consumes: `Preset` from Task 1.
- Produces: `SlotBank.slotCount`, `SlotBank(slots:)`, `.slots`, `capture(_:into:)`, `recall(_:)`, `clear(_:)`, `isAvailable(_:)`, `var onChange: (() -> Void)?`.

- [ ] **Step 1: Write the failing test**

```swift
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
        bank.capture(preset(speed: 0.9), into: 2)
        let got = try XCTUnwrap(bank.recall(2))
        XCTAssertEqual(got.snapshot.params["speed"], .float(0.9))
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
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test ... -only-testing:ARShaderTests/SlotBankTests ...`
Expected: FAIL — `cannot find 'SlotBank' in scope`.

- [ ] **Step 3: Write minimal implementation**

```swift
import Foundation

/// The eight slots and what is in them.
///
/// No SwiftUI import and no `Instrument` reference, following `SurfaceLayout`'s doctrine from phase
/// 3a: every invariant below is then testable with no view and no GPU in play, which is the only
/// kind of test that has been cheap on this surface.
///
/// `capture` takes a finished `Preset` rather than a `DeckID`, because reading a deck's live values
/// requires the `Instrument` — and a bank that holds one is no longer testable without one. Reading
/// the deck is `Instrument.currentPreset(of:)`'s job; this type only stores what it is handed.
@MainActor
final class SlotBank: ObservableObject {
    /// One row of an APC40 MkII. The full 8x5 grid is a change of this constant plus a layout,
    /// never a change of model.
    static let slotCount = 8

    @Published private(set) var slots: [Preset?]

    /// Fired after any mutation, so the owner can persist. Not a `sink` on `$slots`, because the
    /// owner needs to know a WRITE happened — a recall republishes nothing and must not cause a
    /// disk write mid-set.
    var onChange: (() -> Void)?

    init(slots: [Preset?] = []) {
        var padded = slots.prefix(Self.slotCount).map { $0 }
        padded.append(contentsOf: Array(repeating: nil, count: Self.slotCount - padded.count))
        self.slots = padded
    }

    private func isValid(_ index: Int) -> Bool { slots.indices.contains(index) }

    func capture(_ preset: Preset, into index: Int) {
        guard isValid(index) else { return }
        slots[index] = preset
        onChange?()
    }

    /// Returns what to apply; applying is the caller's job. Nil when the slot is empty OR its file
    /// has gone — firing an unavailable slot is a no-op, not a crash and not a silent partial load.
    func recall(_ index: Int) -> Preset? {
        guard isValid(index), isAvailable(index) else { return nil }
        return slots[index]
    }

    func clear(_ index: Int) {
        guard isValid(index) else { return }
        slots[index] = nil
        onChange?()
    }

    /// False for an empty slot and for one whose shader file is no longer on disk. The slot is
    /// deliberately NOT cleared in the second case: an unmounted drive comes back, and destroying
    /// the operator's bank over a bad mount is worse than a dark cell.
    func isAvailable(_ index: Int) -> Bool {
        guard isValid(index), let preset = slots[index] else { return false }
        return FileManager.default.fileExists(atPath: preset.shaderURL.path)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Expected: PASS, 12 tests.

- [ ] **Step 5: Mutation-prove the two rules that protect the operator**

1. Make `isAvailable` return `true` unconditionally. Expected: `testASlotWhoseFileHasGoneIsUnavailableAndRecallsNilButStaysOccupied` and `testAnEmptySlotIsNotReportedAvailable` FAIL. Restore.
2. Make `recall` call `onChange?()`. Expected: `testRecallDoesNotNotifyBecauseItChangesNothing` FAILS. Restore.
3. Make `clear` set `slots = Array(repeating: nil, count: Self.slotCount)`. Expected: `testClearEmptiesOneSlotAndLeavesItsNeighboursAlone` FAILS. Restore.

Confirm PASS after each restore.

- [ ] **Step 6: Commit**

```bash
git add App/ARShader/SlotBank.swift App/ARShaderTests/SlotBankTests.swift
git commit -m "feat(3b): SlotBank — eight slots, no view and no Instrument in sight"
```

Expected ARShader count: **222**.

---

