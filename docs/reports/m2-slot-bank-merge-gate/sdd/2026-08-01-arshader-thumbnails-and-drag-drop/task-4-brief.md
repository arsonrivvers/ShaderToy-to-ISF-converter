### Task 4: `RECALL TO: A | B`, and slot recall constrained to decks

**Files:**
- Modify: `App/ARShader/SlotBankStripView.swift` — RECALL TO becomes `DeckID`; SOURCE picker removed
- Modify: `App/ARShader/InstrumentView.swift` — the shared `libraryTarget` binding is no longer shared
- Test: `App/ARShaderTests/SlotRecallTargetTests.swift` (new)

**Interfaces:**
- Consumes: `Instrument.load(_:onto:thenApply:)` (`Instrument.swift:90`), unchanged.
- Produces: `SlotBankStripView` no longer takes a `LibraryTarget` binding; it owns `@State private var recallTarget: DeckID`.

`LibraryTarget` keeps all five `allCases` entries — Task 5's drag-and-drop still needs FX
destinations. What changes is that **slot recall can no longer express them.** The constraint is at
the type level: the strip's picker binds `DeckID`, so `MST FX` is not a value it can hold, and the
phase 3b hazard (a slot click silently appending an unbounded FX stage) stops being reachable rather
than being merely avoided.

The SOURCE picker is removed in this task; Task 6 replaces it with the deck-monitor drag. **Between
task 4 and task 6 there is no way to capture a look** — that is a real gap, and the two tasks
therefore land in the same review cycle, not weeks apart.

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import ARShader

@MainActor
final class SlotRecallTargetTests: XCTestCase {
    /// The type-level constraint, asserted as a type-level fact: recall takes a DeckID, and there
    /// is no LibraryTarget case it can be handed. Phase 3b's hazard was that RECALL TO could hold
    /// `.masterFX`, so every slot click appended an unbounded FX stage to the master chain.
    func testRecallTargetsAreDecksOnly() {
        let targets = SlotBankStripView.recallTargets
        XCTAssertEqual(targets, DeckID.allCases)
        XCTAssertEqual(targets.count, 2, "A slot loads a deck. There is no third answer.")
    }

    /// Falsifiable companion: if someone widens the picker back to LibraryTarget, this catches it.
    func testNoRecallTargetIsAnFXChain() {
        for deck in SlotBankStripView.recallTargets {
            let asLibraryTarget = LibraryTarget.deck(deck)
            if case .deck = asLibraryTarget { continue }
            XCTFail("\(deck) mapped to a non-deck LibraryTarget")
        }
    }
}
```

- [ ] **Step 2: Run it — expect a compile failure** (`recallTargets` does not exist).

- [ ] **Step 3: Change the strip**

Remove the `@Binding var target: LibraryTarget` and the `@State private var source: DeckID`. Add:

```swift
    /// Where a recall WRITES. Two answers, because a slot holds a shader and shaders go on decks —
    /// "they will always be shaders not fx". Typed as `DeckID` rather than `LibraryTarget` so the
    /// phase 3b hazard is unreachable: there is no value of this picker that appends an FX stage.
    @State private var recallTarget: DeckID = .one

    static var recallTargets: [DeckID] { DeckID.allCases }
```

Delete the SOURCE `VStack` (lines 104-115) entirely. Change the RECALL TO picker (117-128) to
iterate `Self.recallTargets`, and `recall(_:)` (214-217) to:

```swift
    private func recall(_ index: Int) {
        guard let preset = bank.recall(index) else { return }
        instrument.load(preset.shaderURL, onto: .deck(recallTarget), thenApply: preset.snapshot)
    }
```

- [ ] **Step 4: Update the call site.** `InstrumentView` constructs `SlotBankStripView(instrument:target:layout:)`; drop the `target:` argument. The `@State private var libraryTarget` it still feeds to `LibraryPanelView` stays until Task 5 removes that too.

- [ ] **Step 5: Run the tests — expect PASS.** Also run `SurfaceGeometryTests`: the strip lost a control and is narrower, so `SurfaceMetrics.stripsMinWidth` may now be wrong in the other direction. See the Known Issues section.

- [ ] **Step 6: Mutation-prove.** Change `recallTargets` to return `DeckID.allCases + DeckID.allCases`. Expected: `testRecallTargetsAreDecksOnly` FAILS on the count. Revert.

- [ ] **Step 7: Commit**

```bash
git add App/ARShader/SlotBankStripView.swift App/ARShader/InstrumentView.swift \
        App/ARShaderTests/SlotRecallTargetTests.swift
git commit -m "feat(3c): RECALL TO is A|B, typed as DeckID so FX targets are unreachable"
```

---

