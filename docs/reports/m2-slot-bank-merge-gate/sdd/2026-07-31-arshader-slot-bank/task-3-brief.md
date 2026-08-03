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

