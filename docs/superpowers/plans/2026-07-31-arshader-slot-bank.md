# ARShader Phase 3b — Slot Bank Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Eight slots, each holding a shader plus the parameter values dialled when it was captured, recalled onto whatever the load-target picker names.

**Architecture:** `Preset` (shader URL + existing `ParamSnapshot`) is the primitive. `SlotBank` is a plain `@MainActor ObservableObject` with **no SwiftUI import and no `Instrument` reference**, so every invariant is unit-testable with no view in play — the doctrine `SurfaceLayout` established in phase 3a. Applying a preset needs the instrument and the target, so it lives on `Instrument.load(_:onto:thenApply:)`, one call shared by library clicks, slot recalls, and a later MIDI handler.

**Tech Stack:** Swift 5.9 / SwiftUI / AppKit, macOS 13 deployment target, XCTest. Xcode 26.

**Spec:** `docs/superpowers/specs/2026-07-31-arshader-slot-bank-design.md` (PM-reviewed; REWRITE findings folded at `6e0ec5f`).

## Global Constraints

- **Build:** `xcodebuild -project App/TrueISFEditor.xcodeproj -scheme ARShader -derivedDataPath /tmp/arshader-ddata-bank ARCHS=arm64 ONLY_ACTIVE_ARCH=YES`. **Use `/tmp/arshader-ddata-bank` and no other path** — `/tmp/arshader-ddata` belongs to another live session and `/tmp/arshader-ddata-panel` to the merged phase 3a.
- **`xcodebuild test` launches an ARShader window on every run.** That is the test host, not a hang. Do not quit it.
- **Baseline suite counts before any change: ARShader 207, TrueISFEditor 514 (3 skipped), ShadertoyISFKit 312.** Every task states its expected new ARShader count. A count that does not match means a test was silently lost.
- **macOS 13 deployment target.** Do not use macOS 14+ API. Phase 3a had a review finding for exactly this.
- **No `print()`.** This codebase has no logger; failures surface as `assertionFailure` in debug or as visible UI state.
- **Never rename or repurpose `SurfaceLayout`, `PanelID.library`, or `PanelID.settings`.** Phase 3a shipped and signed them.
- **Every test must be mutation-proven.** After a test passes, break the production behaviour it names, confirm that test goes red, restore. A test whose mutation was not demonstrated does not count as coverage. Phase 3a shipped a layout gate that could not fail; its own mutation evidence had been run against a stub that was later rewritten.
- **`ParamSnapshot`, `ParamStore.exportSnapshot()`, `ParamStore.applySnapshot(_:)` already exist** in `App/ISFRuntime/ParamStore.swift`. Do not reimplement or modify them.

---

## File Structure

| File | Responsibility |
|---|---|
| `App/ARShader/Preset.swift` (create) | The `Preset` value type. Nothing else. |
| `App/ARShader/SlotBank.swift` (create) | Eight slots; capture / recall / clear / availability. No SwiftUI, no `Instrument`. |
| `App/ARShader/SlotBankStore.swift` (create) | `UserDefaults` persistence for the bank, mirroring `SurfaceLayoutStore`. |
| `App/ARShader/SlotBankPanelView.swift` (create) | The rail panel. Cells, SOURCE control, gestures. |
| `App/ARShader/ShaderUnit.swift` (modify) | Gains `sourceURL`, set in `load(url:)`. |
| `App/ARShader/Instrument.swift` (modify) | Gains `load(_:onto:thenApply:)`, `currentPreset(of:)`, and owns the `SlotBank`. |
| `App/ARShader/LibraryPanelView.swift` (modify) | Its private `load`/`append` move to `Instrument`; it calls the new method. |
| `App/ARShader/SurfaceLayout.swift` (modify) | `PanelID` gains `.bank`. |
| `App/ARShader/InstrumentView.swift` (modify) | `panelContent` gains the `.bank` case. |
| `App/ARShaderTests/PresetTests.swift` (create) | `Preset` codability and identity. |
| `App/ARShaderTests/SlotBankTests.swift` (create) | Every bank invariant. |
| `App/ARShaderTests/SlotBankStoreTests.swift` (create) | Round-trip and corruption tolerance. |
| `App/ARShaderTests/InstrumentLoadTests.swift` (create) | The load seam: replace vs append, snapshot timing, one-shot clearing, show mode. |

Task order is dependency order. Tasks 1–3 are pure model with no `Instrument`; Task 4 changes `ShaderUnit`; Task 5 builds the seam; Tasks 6–7 are UI.

---

### Task 1: `Preset`

**Files:**
- Create: `App/ARShader/Preset.swift`
- Test: `App/ARShaderTests/PresetTests.swift`

**Interfaces:**
- Consumes: `ParamSnapshot` from `App/ISFRuntime/ParamStore.swift`.
- Produces: `Preset(id:name:shaderURL:snapshot:)`, `Preset.capturing(url:snapshot:)`.

- [ ] **Step 1: Write the failing test**

```swift
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project App/TrueISFEditor.xcodeproj -scheme ARShader -derivedDataPath /tmp/arshader-ddata-bank -only-testing:ARShaderTests/PresetTests ARCHS=arm64 ONLY_ACTIVE_ARCH=YES`
Expected: FAIL — compile error, `cannot find 'Preset' in scope`.

- [ ] **Step 3: Write minimal implementation**

```swift
import Foundation

/// A shader together with the parameter values that were dialled when it was captured.
///
/// The unit a slot holds, and — once phase 3c adds naming and browsing, and a later phase adds
/// randomisation — the unit those operate on too. `ParamSnapshot` does the heavy lifting: it is
/// already `Codable`, already survives one corrupt entry without failing the whole decode, and
/// `ParamStore.applySnapshot` already validate-and-clamps it against the LIVE header range, so a
/// preset captured under an older, wider range clamps in rather than replaying out of range.
struct Preset: Codable, Equatable, Identifiable {
    let id: UUID
    /// 3b derives this from the filename and nothing edits it. Stored anyway: adding a property to
    /// a persisted Codable type later is a migration, and adding it now is free.
    var name: String
    let shaderURL: URL
    let snapshot: ParamSnapshot

    /// Capture always mints a NEW identity. Two captures of the same shader are two presets that
    /// happen to share a URL, not one preset in two slots — otherwise editing one would silently
    /// edit the other.
    static func capturing(url: URL, snapshot: ParamSnapshot) -> Preset {
        Preset(id: UUID(), name: url.lastPathComponent, shaderURL: url, snapshot: snapshot)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run the same command. Expected: PASS, 3 tests.

- [ ] **Step 5: Mutation-prove the identity test**

Change `capturing` to derive a stable id from the URL:
```swift
static func capturing(url: URL, snapshot: ParamSnapshot) -> Preset {
    Preset(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
           name: url.lastPathComponent, shaderURL: url, snapshot: snapshot)
}
```
Run the tests. Expected: `testTwoPresetsOfTheSameShaderAreDistinctThings` FAILS. **Restore the real implementation** and confirm PASS again.

- [ ] **Step 6: Add the file to the project and commit**

`App/project.yml` uses directory globs, so a new file in `App/ARShader/` needs no manifest edit — but run `xcodegen generate` from `App/` if the build cannot see it.

```bash
git add App/ARShader/Preset.swift App/ARShaderTests/PresetTests.swift
git commit -m "feat(3b): Preset — a shader plus the values dialled when it was captured"
```

Expected ARShader count after this task: **210**.

---

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
        // Uses a REAL file: recall() returns nil for an unavailable slot by design, so a preset
        // pointing at a path nothing creates would make this test fail for the wrong reason.
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

Expected: PASS, 11 tests.

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

Expected ARShader count: **221**.

---

### Task 3: `SlotBankStore`

**Files:**
- Create: `App/ARShader/SlotBankStore.swift`
- Test: `App/ARShaderTests/SlotBankStoreTests.swift`

**Interfaces:**
- Consumes: `Preset` (Task 1), `SlotBank` (Task 2).
- Produces: `SlotBankStore(defaults:)`, `.load() -> [Preset?]`, `.save(_ slots: [Preset?])`.

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import ARShader

@MainActor
final class SlotBankStoreTests: XCTestCase {

    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        // A private suite so tests never read or clobber the real bank.
        defaults = UserDefaults(suiteName: "SlotBankStoreTests-\(UUID().uuidString)")
    }

    private func preset(_ speed: Double) -> Preset {
        Preset.capturing(url: URL(fileURLWithPath: "/tmp/a.fs"),
                         snapshot: ParamSnapshot(params: ["speed": .float(speed)]))
    }

    func testAnEmptyStoreLoadsAnEmptyBankRatherThanFailing() {
        let loaded = SlotBankStore(defaults: defaults).load()
        XCTAssertEqual(loaded.count, SlotBank.slotCount)
        XCTAssertTrue(loaded.allSatisfy { $0 == nil })
    }

    func testAPopulatedBankRoundTripsWithItsValuesAndPositions() throws {
        let store = SlotBankStore(defaults: defaults)
        var slots = [Preset?](repeating: nil, count: SlotBank.slotCount)
        slots[0] = preset(0.1)
        slots[7] = preset(0.9)
        store.save(slots)

        let loaded = store.load()
        XCTAssertEqual(loaded[0]?.snapshot.params["speed"], .float(0.1))
        XCTAssertEqual(loaded[7]?.snapshot.params["speed"], .float(0.9))
        XCTAssertNil(loaded[3], "Empty slots stay empty and positions are preserved")
    }

    func testCorruptStoredDataLoadsAnEmptyBankRatherThanThrowing() {
        defaults.set(Data("not json".utf8), forKey: SlotBankStore.key)
        let loaded = SlotBankStore(defaults: defaults).load()
        XCTAssertEqual(loaded.count, SlotBank.slotCount)
        XCTAssertTrue(loaded.allSatisfy { $0 == nil },
                      "A corrupt bank must never stop the instrument launching")
    }

    func testAStoredBankOfTheWrongLengthIsNormalisedToSlotCount() throws {
        // A bank saved by a future build with a bigger grid, opened by this one.
        let tooMany = [Preset?](repeating: preset(0.5), count: SlotBank.slotCount + 4)
        defaults.set(try JSONEncoder().encode(tooMany), forKey: SlotBankStore.key)
        XCTAssertEqual(SlotBankStore(defaults: defaults).load().count, SlotBank.slotCount,
                       "Loading must always yield exactly slotCount entries, whatever is on disk")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Expected: FAIL — `cannot find 'SlotBankStore' in scope`.

- [ ] **Step 3: Write minimal implementation**

```swift
import Foundation

/// Reads and writes the slot bank as one JSON blob, shaped exactly like `SurfaceLayoutStore`.
///
/// One key rather than one per slot: the slots are restored together or the restore is wrong, and
/// per-slot keys can drift out of sync across app versions.
struct SlotBankStore {
    static let key = "ARShader.slotBank"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    /// Any failure — absent, truncated, from a future schema, the wrong length — yields an empty
    /// bank. A corrupt bank must never be able to stop the instrument launching.
    func load() -> [Preset?] {
        guard let data = defaults.data(forKey: Self.key),
              let decoded = try? JSONDecoder().decode([Preset?].self, from: data)
        else { return Self.empty }
        return Self.normalised(decoded)
    }

    func save(_ slots: [Preset?]) {
        guard let data = try? JSONEncoder().encode(Self.normalised(slots)) else {
            // Phase 3a's branch review found SurfaceLayoutStore swallowing exactly this: an
            // unencodable value ended persistence for the session with no symptom until the next
            // launch. Loud in debug, still non-fatal in release.
            assertionFailure("Slot bank could not be encoded — persistence is now silently off")
            return
        }
        defaults.set(data, forKey: Self.key)
    }

    private static var empty: [Preset?] { Array(repeating: nil, count: SlotBank.slotCount) }

    /// Always exactly `slotCount` entries, whatever was on disk.
    private static func normalised(_ slots: [Preset?]) -> [Preset?] {
        var out = slots.prefix(SlotBank.slotCount).map { $0 }
        out.append(contentsOf: Array(repeating: nil, count: SlotBank.slotCount - out.count))
        return out
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Expected: PASS, 4 tests.

- [ ] **Step 5: Mutation-prove the corruption tolerance**

Change `load()`'s guard to `let decoded = try! JSONDecoder().decode([Preset?].self, from: data)`.
Expected: `testCorruptStoredDataLoadsAnEmptyBankRatherThanThrowing` CRASHES the test run (a trap, not a failure — that is the point: the shipped code must not do this). Restore and confirm PASS.

Then remove the `normalised` call from `load()`. Expected: `testAStoredBankOfTheWrongLengthIsNormalisedToSlotCount` FAILS. Restore.

- [ ] **Step 6: Commit**

```bash
git add App/ARShader/SlotBankStore.swift App/ARShaderTests/SlotBankStoreTests.swift
git commit -m "feat(3b): SlotBankStore — one blob, and it never blocks launch"
```

Expected ARShader count: **225**.

---

### Task 4: `ShaderUnit.sourceURL`

**Files:**
- Modify: `App/ARShader/ShaderUnit.swift` (add stored property; set it in `load(url:)` at line ~64)
- Test: `App/ARShaderTests/InstrumentLoadTests.swift` (create — first two tests)

**Interfaces:**
- Produces: `ShaderUnit.sourceURL: URL?`.

**Why this exists:** `load(url:)` currently reads the file and forwards only `url.lastPathComponent`; the `URL` is discarded on the same line. Capture cannot build a `Preset` without it, and reverse-lookup by filename is unsafe — the library truncates names in the middle precisely because long `AR_Genuary` names differ at the END, and a shader may be loaded from outside the scanned corpus.

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import ARShader

@MainActor
final class InstrumentLoadTests: XCTestCase {

    /// A real, compilable ISF file on disk. The unit reads the file, so a fake path will not do.
    func makeShaderFile(_ name: String = "probe") throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(name)-\(UUID().uuidString).fs")
        try """
        /*{ "DESCRIPTION": "test", "ISFVSN": "2", "INPUTS": [
            { "NAME": "speed", "TYPE": "float", "MIN": 0.0, "MAX": 1.0, "DEFAULT": 0.5 }
        ] }*/
        void main() { gl_FragColor = vec4(speed, 0.0, 0.0, 1.0); }
        """.write(to: url, atomically: true, encoding: .utf8)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    func testAFreshUnitHasNoSourceURL() {
        let instrument = Instrument()
        XCTAssertNil(instrument.deck(.one).unit.sourceURL,
                     "Nothing has been loaded, so there is no file behind the deck")
    }

    func testLoadingFromAURLRetainsIt() throws {
        let instrument = Instrument()
        let url = try makeShaderFile()
        instrument.deck(.one).unit.load(url: url)
        XCTAssertEqual(instrument.deck(.one).unit.sourceURL, url,
                       "Capture needs the URL, and lastPathComponent is not enough — filenames "
                       + "are not unique across the corpus")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Expected: FAIL — `value of type 'ShaderUnit' has no member 'sourceURL'`.

- [ ] **Step 3: Write minimal implementation**

In `App/ARShader/ShaderUnit.swift`, add next to `shaderName`:

```swift
    /// The file this unit was loaded from, when there was one.
    ///
    /// `shaderName` is only `lastPathComponent` and cannot be reversed into a URL: filenames are
    /// not unique across the corpus, and a shader can be loaded from outside the scanned folders.
    /// The slot bank captures this; without it a `Preset` cannot name its own shader.
    /// Nil for the `load(source:name:)` path, which has no file behind it.
    @Published private(set) var sourceURL: URL?
```

Then in `load(url:)`, immediately before the existing `load(source:name:)` call:

```swift
        sourceURL = url
```

Leave `load(source:name:)` setting `sourceURL = nil` at its start, so a source-loaded unit never
claims a file it does not have.

- [ ] **Step 4: Run test to verify it passes**

Expected: PASS, 2 tests.

- [ ] **Step 5: Mutation-prove it**

Remove the `sourceURL = url` line. Expected: `testLoadingFromAURLRetainsIt` FAILS. Restore.
Then make `load(source:name:)` NOT clear it, load from a URL and then from source, and confirm the nil-ing matters — if no existing test covers that, it is fine; the clear is defensive.

- [ ] **Step 6: Commit**

```bash
git add App/ARShader/ShaderUnit.swift App/ARShaderTests/InstrumentLoadTests.swift
git commit -m "feat(3b): ShaderUnit retains the URL it loaded

Capture cannot build a Preset without it, and lastPathComponent cannot be
reversed — the library truncates names in the middle precisely because long
AR_Genuary names differ at the end."
```

Expected ARShader count: **227**.

---

### Task 5: The load seam — `Instrument.load(_:onto:thenApply:)`

**Files:**
- Modify: `App/ARShader/Instrument.swift` (add `load`, `currentPreset`, own the `SlotBank`)
- Modify: `App/ARShader/LibraryPanelView.swift:53-72` (delete private `load`/`append`, call the instrument)
- Test: `App/ARShaderTests/InstrumentLoadTests.swift` (extend)

**Interfaces:**
- Consumes: `Preset` (Task 1), `SlotBank` (Task 2), `SlotBankStore` (Task 3), `ShaderUnit.sourceURL` (Task 4), existing `LibraryTarget` and `FXChain`.
- Produces: `Instrument.load(_ url: URL, onto target: LibraryTarget, thenApply snapshot: ParamSnapshot? = nil)`, `Instrument.currentPreset(of deck: DeckID) -> Preset?`, `Instrument.slotBank: SlotBank`.

**This is the task the PM review said was mis-sized.** It is not a same-behaviour lift. `ShaderUnit.onCompileFinished` is a **single-owner optional closure**, and `LibraryPanelView.append` already claims it on every FX stage for `chain?.stageDidChangeScene()`. Layering snapshot-apply on the same hook means whoever assigns second silently drops the first — across three of the picker's five segments. And for FX targets the unit is created *inside* `load`, so a `Void`-returning `load` leaves the caller nothing to hook. `load` therefore owns the composition itself.

- [ ] **Step 1: Write the failing tests**

Add to `InstrumentLoadTests`:

```swift
    /// Awaits one compile, which is asynchronous — the unit compiles on a background queue and
    /// fires `onCompileFinished` back on the main actor.
    private func loadAndWait(_ instrument: Instrument, _ url: URL,
                             onto target: LibraryTarget,
                             thenApply snapshot: ParamSnapshot? = nil) async {
        await withCheckedContinuation { continuation in
            var resumed = false
            instrument.onLoadSettledForTesting = {
                guard !resumed else { return }
                resumed = true
                continuation.resume()
            }
            instrument.load(url, onto: target, thenApply: snapshot)
        }
        instrument.onLoadSettledForTesting = nil
    }

    func testADeckTargetReplacesTheShader() async throws {
        let instrument = Instrument()
        await loadAndWait(instrument, try makeShaderFile("first"), onto: .deck(.one))
        await loadAndWait(instrument, try makeShaderFile("second"), onto: .deck(.one))
        XCTAssertEqual(instrument.deck(.one).unit.sourceURL?.lastPathComponent.hasPrefix("second"),
                       true, "A deck REPLACES; it does not accumulate")
    }

    func testAnFXTargetAppendsAStage() async throws {
        let instrument = Instrument()
        let before = instrument.renderer.masterFX.stages.count
        await loadAndWait(instrument, try makeShaderFile(), onto: .masterFX)
        XCTAssertEqual(instrument.renderer.masterFX.stages.count, before + 1,
                       "An FX target APPENDS a stage; it does not replace the chain")
    }

    func testASnapshotIsAppliedAfterTheCompileLands() async throws {
        let instrument = Instrument()
        await loadAndWait(instrument, try makeShaderFile(), onto: .deck(.one),
                          thenApply: ParamSnapshot(params: ["speed": .float(0.25)]))
        XCTAssertEqual(instrument.deck(.one).unit.params.exportSnapshot().params["speed"],
                       .float(0.25),
                       "Applied before the compile lands, the parameters would not exist to receive it")
    }

    /// The collision the PM review caught. Assign only the snapshot handler and this goes red.
    func testAnFXLoadWithASnapshotStillRepublishesTheChain() async throws {
        let instrument = Instrument()
        var republishes = 0
        instrument.renderer.masterFX.onStagesChangedForTesting = { republishes += 1 }
        await loadAndWait(instrument, try makeShaderFile(), onto: .masterFX,
                          thenApply: ParamSnapshot(params: ["speed": .float(0.3)]))
        XCTAssertGreaterThan(republishes, 0,
                             "onCompileFinished is single-owner: a snapshot handler that replaces "
                             + "the chain republish silently stops the FX stage updating")
        instrument.renderer.masterFX.onStagesChangedForTesting = nil
    }

    /// The stale one-shot. Without the clear, the second load replays the first preset's values.
    func testTheOneShotIsClearedSoALaterLoadDoesNotReplayOldValues() async throws {
        let instrument = Instrument()
        await loadAndWait(instrument, try makeShaderFile(), onto: .deck(.one),
                          thenApply: ParamSnapshot(params: ["speed": .float(0.25)]))
        await loadAndWait(instrument, try makeShaderFile(), onto: .deck(.one))
        XCTAssertNotEqual(instrument.deck(.one).unit.params.exportSnapshot().params["speed"],
                          .float(0.25),
                          "A later library load must not inherit a preset's values from an earlier "
                          + "slot recall onto the same deck")
    }

    /// Falsifiable because Instrument OWNS surfaceLayout and load() could therefore reach it.
    func testLoadingDoesNotEndShowMode() async throws {
        let instrument = Instrument()
        instrument.surfaceLayout.toggleShowMode()
        XCTAssertTrue(instrument.surfaceLayout.showMode)
        await loadAndWait(instrument, try makeShaderFile(), onto: .deck(.one))
        XCTAssertTrue(instrument.surfaceLayout.showMode,
                      "Loading a shader is a performance action. Only deliberate LAYOUT actions "
                      + "end a show.")
    }

    func testCurrentPresetIsNilUntilSomethingIsLoaded() {
        XCTAssertNil(Instrument().currentPreset(of: .one))
    }

    func testCurrentPresetCapturesTheLiveValues() async throws {
        let instrument = Instrument()
        await loadAndWait(instrument, try makeShaderFile(), onto: .deck(.one))
        instrument.deck(.one).unit.params.set("speed", .float(0.8))
        let preset = try XCTUnwrap(instrument.currentPreset(of: .one))
        XCTAssertEqual(preset.snapshot.params["speed"], .float(0.8),
                       "Capture takes what is dialled NOW, not the header defaults")
    }
```

**Note for the implementer:** `onLoadSettledForTesting` and `FXChain.onStagesChangedForTesting` are test seams you are adding. Keep them `internal var` with a `ForTesting` suffix and a comment saying why they exist. If `ParamStore.set` has a different signature, use the real one — check `App/ISFRuntime/ParamStore.swift` and adjust the test, not the store.

- [ ] **Step 2: Run tests to verify they fail**

Expected: FAIL — no `load(_:onto:thenApply:)` on `Instrument`.

- [ ] **Step 3: Write the implementation**

In `Instrument.swift`:

```swift
    /// The slot bank, restored from the last launch, persisting itself on every write.
    let slotBank: SlotBank

    // in init(), after surfaceLayout is set up:
    let bankStore = SlotBankStore()
    self.slotBank = SlotBank(slots: bankStore.load())
    self.slotBank.onChange = { [weak self] in
        guard let self else { return }
        bankStore.save(self.slotBank.slots)
    }

    /// Fired after a load has compiled and any snapshot has been applied. Test seam only — the app
    /// has no use for it, but the compile is asynchronous and a test otherwise has nothing to await.
    var onLoadSettledForTesting: (() -> Void)?

    /// The ONE place a shader becomes loaded. Library clicks, slot recalls and (later) MIDI pads
    /// all arrive here, so the mapping from "a URL plus a target" to "replace a deck / append a
    /// stage" exists once rather than inside a view's private method.
    ///
    /// `thenApply` exists because `ShaderUnit.onCompileFinished` is a SINGLE-OWNER closure that the
    /// FX path already claims for `stageDidChangeScene()`. If the caller set it to apply a
    /// snapshot, whichever assignment ran second would silently drop the other. So this method owns
    /// the composition — and for FX targets it is also the only code that ever sees the freshly
    /// created stage, so the caller could not hook it even if the hook were free.
    func load(_ url: URL, onto target: LibraryTarget, thenApply snapshot: ParamSnapshot? = nil) {
        switch target {
        case .deck(let id):
            let unit = deck(id).unit
            attach(snapshot, to: unit, alsoRunning: nil)
            unit.load(url: url)
        case .deckFX(let id):
            append(url, to: deck(id).fx, snapshot: snapshot)
        case .masterFX:
            append(url, to: renderer.masterFX, snapshot: snapshot)
        }
    }

    private func append(_ url: URL, to chain: FXChain, snapshot: ParamSnapshot?) {
        let stage = FXStage(device: device, queue: queue, clock: renderer.clock)
        attach(snapshot, to: stage.unit, alsoRunning: { [weak chain] in chain?.stageDidChangeScene() })
        chain.append(stage)
        stage.unit.load(url: url)
    }

    /// Installs a compile handler that runs the chain's ongoing concern AND the one-shot snapshot,
    /// then CLEARS the one-shot. Without the clear, a later unrelated load onto the same unit would
    /// re-fire it and replay an old preset's values onto a shader they were never captured from.
    private func attach(_ snapshot: ParamSnapshot?, to unit: ShaderUnit,
                        alsoRunning ongoing: (() -> Void)?) {
        unit.onCompileFinished = { [weak self, weak unit] in
            ongoing?()
            if let snapshot, let unit { unit.params.applySnapshot(snapshot) }
            // One-shot: reinstall the ongoing concern alone, or nothing.
            unit?.onCompileFinished = ongoing.map { fn in { fn() } }
            self?.onLoadSettledForTesting?()
        }
    }

    /// What is on a deck right now, as a capturable preset. Nil when the deck has no file behind it.
    func currentPreset(of id: DeckID) -> Preset? {
        let unit = deck(id).unit
        guard let url = unit.sourceURL else { return nil }
        return Preset.capturing(url: url, snapshot: unit.params.exportSnapshot())
    }
```

In `FXChain.swift`, add next to the existing republish path:

```swift
    /// Test seam: lets a test observe that a stage change was republished. Nil in the app.
    var onStagesChangedForTesting: (() -> Void)?
```
and call `onStagesChangedForTesting?()` inside `stageDidChangeScene()`.

In `LibraryPanelView.swift`, **delete** the private `load(_:)` and `append(_:to:)` methods entirely and change the list's button action to:

```swift
                Button {
                    instrument.load(entry.url, onto: target)
                } label: {
```

- [ ] **Step 4: Run tests to verify they pass**

Expected: PASS. Then run the FULL ARShader suite — the library path changed, so anything that exercised it must still be green.

- [ ] **Step 5: Mutation-prove the three that matter**

1. In `attach`, drop `ongoing?()` from the closure. Expected: `testAnFXLoadWithASnapshotStillRepublishesTheChain` FAILS. Restore.
2. In `attach`, remove the one-shot reinstall line. Expected: `testTheOneShotIsClearedSoALaterLoadDoesNotReplayOldValues` FAILS. Restore.
3. Add `surfaceLayout.toggleShowMode()` at the top of `load`. Expected: `testLoadingDoesNotEndShowMode` FAILS. Restore.

- [ ] **Step 6: Commit**

```bash
git add App/ARShader/Instrument.swift App/ARShader/FXChain.swift App/ARShader/LibraryPanelView.swift App/ARShaderTests/InstrumentLoadTests.swift
git commit -m "feat(3b): one load seam for library clicks, slot recalls and later MIDI

Not a pure lift. onCompileFinished is single-owner and the FX path already
claims it, so load() owns the composition and clears the one-shot after firing."
```

Expected ARShader count: **235**.

---

### Task 6: `PanelID.bank`

**Files:**
- Modify: `App/ARShader/SurfaceLayout.swift` (add the case, its `systemImage`, its `title`)
- Modify: `App/ARShader/InstrumentView.swift` — add a case to `panelContent` for the bank panel
- Create: `App/ARShader/SlotBankPanelView.swift` (placeholder body — Task 7 fills it)
- Test: `App/ARShaderTests/SurfaceLayoutTests.swift` (extend)

**Interfaces:**
- Produces: `PanelID.bank`, `SlotBankPanelView(instrument:)`.

**This is the deliberate test of phase 3a's central claim** that adding a tool costs one enum case. If it costs more, say so in the task report — that is a finding about the framework, not a nuisance.

- [ ] **Step 1: Write the failing test**

Add to `SurfaceLayoutTests`:

```swift
    func testTheBankIsTheThirdRailPanelAndBindsCommandOptionThree() {
        XCTAssertEqual(PanelID.allCases.count, 3, "library, settings, bank")
        XCTAssertEqual(PanelID.bank.shortcutNumber, 3,
                       "The rail's premise is that a new tool costs one case and inherits ⌘⌥N")
        XCTAssertFalse(PanelID.bank.title.isEmpty)
    }

    func testOpeningTheBankSwapsRatherThanStacking() {
        let layout = SurfaceLayout()
        layout.select(panel: .library)
        layout.select(panel: .bank)
        XCTAssertEqual(layout.openPanel, .bank, "The rail swaps one panel; it never shows two")
    }
```

- [ ] **Step 2: Run test to verify it fails**

Expected: FAIL — `type 'PanelID' has no member 'bank'`.

- [ ] **Step 3: Write minimal implementation**

In `SurfaceLayout.swift`, extend `PanelID`:
```swift
enum PanelID: String, CaseIterable, Codable, Identifiable, Sendable {
    case library, settings, bank
```
and add to both switches:
```swift
        case .bank:     return "square.grid.3x3"     // systemImage
        case .bank:     return "Bank"                // title
```

Create `App/ARShader/SlotBankPanelView.swift`:
```swift
import SwiftUI

/// The slot bank as a rail panel. Task 7 builds the cells; this is the seam.
struct SlotBankPanelView: View {
    let instrument: Instrument

    var body: some View {
        Text("Bank").font(.system(size: 12, design: .monospaced))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
```

In `InstrumentView.swift`'s `panelContent`, add:
```swift
        case .bank:
            SlotBankPanelView(instrument: instrument)
```

- [ ] **Step 4: Run test to verify it passes**

Expected: PASS. Run the FULL suite — `PanelID.allCases` grew, so anything iterating it is affected.

- [ ] **Step 5: Commit**

```bash
git add App/ARShader/SurfaceLayout.swift App/ARShader/SlotBankPanelView.swift App/ARShader/InstrumentView.swift App/ARShaderTests/SurfaceLayoutTests.swift
git commit -m "feat(3b): the bank is the third rail panel — one enum case, as advertised"
```

Expected ARShader count: **237**.

---

### Task 7: The bank panel

**Files:**
- Modify: `App/ARShader/SlotBankPanelView.swift` (the real view)
- Test: `App/ARShaderTests/SlotBankTests.swift` (extend — gesture-routing tests only)

**Interfaces:**
- Consumes: everything above.
- Produces: no new public API.

**The safety property this task exists to protect:** *no code path may call `capture` on an occupied slot without an explicit user act.* That is a code-review item, not a unit test — the reviewer must trace every call site of `capture` in the view and confirm each is behind a distinct gesture.

- [ ] **Step 1: Write the implementation**

```swift
import AppKit      // NSEvent.modifierFlags — SwiftUI alone does not guarantee it
import SwiftUI

/// The slot bank: eight cells, a SOURCE deck picker, and nothing else.
///
/// Recall fires into the load-target picker the library already owns — one answer to "load onto
/// what", shared by library clicks and slot hits. SOURCE is separate and means the opposite
/// direction: which deck a capture READS from. Sending library clicks to master FX while capturing
/// deck A is a normal state, so one control could not carry both meanings.
struct SlotBankPanelView: View {
    let instrument: Instrument
    @Binding var target: LibraryTarget
    @ObservedObject private var bank: SlotBank
    @State private var source: DeckID = .one

    init(instrument: Instrument, target: Binding<LibraryTarget>) {
        self.instrument = instrument
        self._target = target
        self.bank = instrument.slotBank
    }

    var body: some View {
        VStack(spacing: 6) {
            Picker("Capture from", selection: $source) {
                ForEach(DeckID.allCases) { Text($0.displayName).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityLabel("Capture from")

            ForEach(0..<SlotBank.slotCount, id: \.self) { index in
                SlotCell(index: index,
                         preset: bank.slots[index],
                         isAvailable: bank.isAvailable(index),
                         onRecall: { recall(index) },
                         onCapture: { capture(into: index) },
                         onClear: { bank.clear(index) })
            }
            Spacer(minLength: 0)
        }
        .padding(8)
    }

    private func recall(_ index: Int) {
        guard let preset = bank.recall(index) else { return }
        instrument.load(preset.shaderURL, onto: target, thenApply: preset.snapshot)
    }

    /// The ONLY call site of `capture` in this view. Both gestures that reach it — clicking an
    /// empty cell, and Replace on a filled one — are explicit user acts. A plain click on a filled
    /// cell routes to `recall`, never here: losing a dialled-in look to a one-cell mis-click is
    /// unrecoverable and would happen exactly once before the bank stopped being trusted.
    private func capture(into index: Int) {
        guard let preset = instrument.currentPreset(of: source) else { return }
        bank.capture(preset, into: index)
    }
}

/// One cell. Empty cells invite capture; filled ones recall and hide their destructive actions
/// behind hover.
private struct SlotCell: View {
    let index: Int
    let preset: Preset?
    let isAvailable: Bool
    let onRecall: () -> Void
    let onCapture: () -> Void
    let onClear: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 6) {
            Text("\(index + 1)")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 14)

            if let preset {
                Text(preset.name)
                    .font(.system(size: 11, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)   // long AR_Genuary names differ at the END
                    .foregroundStyle(isAvailable ? .primary : .secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if isHovering {
                    Button("Replace", action: onCapture).buttonStyle(.plain)
                        .font(.system(size: 10))
                    Button("Clear", action: onClear).buttonStyle(.plain)
                        .font(.system(size: 10))
                }
            } else {
                Text("empty")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.vertical, 5).padding(.horizontal, 6)
        .frame(minHeight: 28)
        .background(preset == nil ? Color.clear : Color.white.opacity(0.06))
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        // EXACTLY ONE tap gesture. Two `.onTapGesture` modifiers on the same view both fire,
        // so a second one for ⌥-click would make an option-click recall AND capture — breaking
        // the one safety property this cell exists to protect. The modifier check lives inside
        // the single handler instead.
        .onTapGesture {
            if preset == nil {
                onCapture()                       // empty: nothing can be lost
            } else if NSEvent.modifierFlags.contains(.option) {
                onCapture()                       // ⌥-click: the deliberate overwrite
            } else {
                onRecall()                        // plain click on a filled cell: ALWAYS recall
            }
        }
        .help(helpText)
        .accessibilityLabel(preset.map { "Slot \(index + 1), \($0.name)" } ?? "Slot \(index + 1), empty")
    }

    private var helpText: String {
        guard let preset else { return "Click to capture the SOURCE deck into slot \(index + 1)" }
        if !isAvailable { return "\(preset.name) — file not found" }
        return "\(preset.name) — click to recall, ⌥-click to replace"
    }
}

```

Update `InstrumentView.panelContent`:
```swift
        case .bank:
            SlotBankPanelView(instrument: instrument, target: $libraryTarget)
```

- [ ] **Step 2: Build and run the full suite**

Expected: 237 tests, 0 failures. No new tests in this task — the view's logic is routing, and the model beneath it is fully covered.

- [ ] **Step 3: Verify the safety property by inspection**

Grep every call: `grep -n "\.capture(" App/ARShader/*.swift`. Confirm the only call in view code is inside `SlotBankPanelView.capture(into:)`, and that the only paths reaching it are the empty-cell tap, the Replace button, and ⌥-click. **Write the result of this grep into the task report.**

- [ ] **Step 4: Commit**

```bash
git add App/ARShader/SlotBankPanelView.swift App/ARShader/InstrumentView.swift
git commit -m "feat(3b): the bank panel — a filled slot can only ever recall"
```

---

### Task 8: Full regression, install, and the smoke report

**Files:**
- Create: `docs/reports/live-smoke-instrument-m2-phase3b.md`

- [ ] **Step 1: Run all three suites**

```bash
xcodebuild test -project App/TrueISFEditor.xcodeproj -scheme ARShader -derivedDataPath /tmp/arshader-ddata-bank ARCHS=arm64 ONLY_ACTIVE_ARCH=YES
xcodebuild test -project App/TrueISFEditor.xcodeproj -scheme TrueISFEditor -derivedDataPath /tmp/arshader-ddata-bank ARCHS=arm64 ONLY_ACTIVE_ARCH=YES
swift test --package-path ShadertoyISFKit --scratch-path /tmp/stkit-build-bank
```

Expected: ARShader **237**, TrueISFEditor **514 (3 skipped)**, ShadertoyISFKit **312**. Any other ARShader number means a test was lost — find it before continuing.

- [ ] **Step 2: Write the smoke report with legs UNRUN**

Legs to write (hypotheses stated so they can fail):

1. The rail shows a third icon; clicking it opens the bank; `⌘⌥3` does the same
2. Capturing into an empty slot names it after the loaded shader
3. Clicking a filled slot recalls it — the shader loads AND the dialled values come back
4. **Clicking a filled slot NEVER overwrites it**, however many times you click
5. ⌥-click replaces; hover ▸ Replace replaces; hover ▸ Clear empties
6. SOURCE A/B captures from the deck you chose, independent of where the load-target picker points
7. Recall honours the load-target picker — set it to MST FX and a slot appends an FX stage
8. Quit and relaunch: the bank is exactly as left
9. Rename a captured shader's file on disk, relaunch: the slot shows unavailable, clicking does nothing, and **the slot is still there**
10. Eight cells are legible at the panel's 260pt floor
11. Recalling the same slot twice in a row does not black-frame (the accepted recompile window)

- [ ] **Step 3: Do NOT install**

Installing quits the operator's running ARShader. The controller announces first and installs on the operator's word. Leave the report `PENDING`.

- [ ] **Step 4: Commit**

```bash
git add docs/reports/live-smoke-instrument-m2-phase3b.md
git commit -m "docs(3b): live smoke report — suites green, legs PENDING"
```

---

## Self-Review

**Spec coverage.** `Preset` → Task 1. `SlotBank` → Task 2. `SlotBankStore` → Task 3. `ShaderUnit.sourceURL` → Task 4. Load seam with the `onCompileFinished` collision and one-shot clearing → Task 5. `PanelID.bank` → Task 6. Gestures, SOURCE control, the never-overwrite rule → Task 7. Show mode handled where it is falsifiable (Task 5), and explicitly NOT tested at the `SlotBank` level. Missing-file behaviour → Task 2 + leg 9. Accepted recompile trade-off → leg 11. FX-chain capture, MIDI, naming/browsing, randomisation all remain out of scope and no task touches them.

**Placeholder scan.** No TBD/TODO. Every code step carries real code. Task 7 has no new tests by design, and says why.

**Type consistency.** `capture(_:into:)`, `recall(_:)`, `clear(_:)`, `isAvailable(_:)` used identically in Tasks 2, 3 and 7. `load(_:onto:thenApply:)` identical in Tasks 5 and 7. `Preset.capturing(url:snapshot:)` identical in Tasks 1, 2, 3 and 5. `SlotBank.slotCount` used in Tasks 2, 3, 6, 7.

**Symbols verified against the tree before this plan was committed** — none of these are assumed:

| Symbol | Confirmed at |
|---|---|
| `libraryTarget` (the `@Binding` Task 7 needs) | `InstrumentView.swift:149`, `@State private var libraryTarget: LibraryTarget = .deck(.one)` |
| `ParamStore.set(_:_:)` | `ParamStore.swift:124` — matches `params.set("speed", .float(0.8))` |
| `FXChain.stageDidChangeScene()` | `FXChain.swift:75` |
| `FXChain.stages` | `FXChain.swift:23`, `@Published private(set) var stages: [FXStage]` |
| `renderer.clock` | `InstrumentRenderer.swift:109` |
| `Instrument.deck(_:)` | `Instrument.swift:48` |
| `ParamStore.exportSnapshot()` / `applySnapshot(_:)` | `ParamStore.swift:191` / `:201` |

**One signature changes between tasks, deliberately:** Task 6 creates `SlotBankPanelView(instrument:)` as a placeholder; Task 7 changes it to `SlotBankPanelView(instrument:target:)` and updates the single call site in `InstrumentView.panelContent`. An implementer working Task 6 in isolation should not "fix" this by adding the binding early — Task 6's gate is that the rail grew by one case, and nothing more.
