# Badge observation fix — report

## Defect

Reported on device 2026-08-02: recalling a slot onto a deck did not immediately light the slot
bank's live badge / coloured border. It only appeared when the operator toggled the unrelated
`RECALL TO` segmented control.

## Root cause (confirmed, matched the brief exactly)

`SlotBankStripView.liveDeck(for:)` and `MonitorTile.dragPayload` (via
`instrument.currentPreset(of:)`) both read `ShaderUnit.sourceURL` correctly, but neither view held
a Combine subscription to either deck's `ShaderUnit`. `Deck` is deliberately not `ObservableObject`
(its own doc comment: "views observe unit") — nothing in `SlotBankStripView` or `MonitorTile`
actually did. SwiftUI therefore had no dependency telling it either view was stale when a load
changed `sourceURL`; both only refreshed when something ELSE invalidated them (`RECALL TO`'s
`@State`, or `RenderStatsModel`'s ~2x/sec republish incidentally re-evaluating the tree).

Both symptoms — the badge and the ~500ms-late-draggable monitor tile — share this one cause and
are fixed by the same change.

## Mechanism chosen, and why

Added `@ObservedObject private var deckAUnit: ShaderUnit` / `deckBUnit: ShaderUnit` to both
`SlotBankStripView` and `MonitorTile`, initialized from `instrument.deck(.one).unit` /
`instrument.deck(.two).unit` in each `init`. `liveDeck(for:)` now reads `deckAUnit.sourceURL` /
`deckBUnit.sourceURL` instead of `instrument.deck($0).unit.sourceURL`.

This is not a novel pattern for this codebase — `InstrumentView.swift`'s `DeckStripView` already
hit and fixed the identical defect class on 2026-07-30 (its own doc comment: a sibling view
holding `@ObservedObject var unit: ShaderUnit` updated correctly while one built from a plain
`Deck` local froze on stale data). I matched that established, on-device-confirmed mechanism
rather than inventing a new one.

**Alternative considered and rejected:** publishing a `deckLoadGeneration` counter on `Instrument`
itself, bumped inside `Instrument.load`'s `attach()` completion closure. Rejected because
`attach()`'s `ongoing` closure is reinstalled permanently after the one-shot snapshot-apply fires
(see its own doc comment), and `InstrumentLoadTests.testTheOneShotIsClearedSoALaterLoadDoesNotReplayOldValues`
asserts `instrument.deck(.one).unit.onCompileFinished` is `nil` after a deck load specifically
*because* `.deck` targets pass `alsoRunning: nil` today. Wiring a generation-bump through that slot
would have flipped that assertion for a reason unrelated to what it actually tests, which is
exactly the kind of expanding, second-order change the brief said to stop and report rather than
push through. The `@ObservedObject`-on-the-unit approach touches none of `Instrument.swift`,
`Deck.swift`, or `ShaderUnit.swift` and carries zero risk to that invariant.

**Constraints satisfied:**
- Fires on load, not a timer: `ShaderUnit`'s own `@Published sourceURL`/`shaderName`/`compileError`/
  `compileErrorLine`/`inputs`/`isLoading` only change during `load()`/`apply()`/`unload()` — never
  per frame, never on a tick.
- No new per-frame or per-tick publish was added anywhere.
- No dependency on `RenderStatsModel` was added; the old incidental dependency on it is gone.
- macOS 13.0 deployment target: `@ObservedObject` has been available since SwiftUI's introduction,
  no issue.
- No retain cycle: `ShaderUnit` instances are already owned by `Deck`/`Instrument` for the life of
  the app; `@ObservedObject` holds a normal strong reference, same lifetime as the app itself, same
  shape as every other `@ObservedObject` already in this codebase (`bank`, `layout`, `elementStats`,
  `renderStats`, `DeckStripView.unit`, etc.).
- No "Publishing changes from within view updates" warning: the writes happen inside
  `ShaderUnit.apply()`/`load(url:)`'s failure branch, both driven by the compile-queue's completion
  hop to the main actor (`Task { @MainActor in ... }`), not from inside a `body` evaluation.

## What changed

- `App/ARShader/SlotBankStripView.swift`
  - Added `@ObservedObject private var deckAUnit: ShaderUnit` / `deckBUnit: ShaderUnit` (~line 124).
  - `init` now assigns them from `instrument.deck(.one).unit` / `instrument.deck(.two).unit`.
  - `liveDeck(for:)` (was `private`, now internal for the same "testable seam on the view struct"
    reason `wouldAccept`/`loadThumbnails` already use) reads `deckAUnit`/`deckBUnit` directly
    instead of `instrument.deck($0).unit.sourceURL` via `DeckID.allCases.first`.
- `App/ARShader/MonitorView.swift`
  - Added the identical `deckAUnit`/`deckBUnit` pair to `MonitorTile`, same reasoning. `.master`
    (PROGRAM) has no single deck behind it, so both are held unconditionally rather than derived
    from `source` — PROGRAM just redraws harmlessly on a deck load too, same order of magnitude of
    churn it already gets from `renderStats`. `dragPayload`'s signature and logic are untouched
    (still reads `instrument.currentPreset(of:)` fresh); the fix is purely that `body` now
    re-evaluates at the right moment so that fresh read actually happens on time.
- `App/ARShaderTests/DeckObservationSeamTests.swift` (new) — see Testing below.
- `App/TrueISFEditor.xcodeproj` regenerated via `xcodegen generate` so the new test file is part of
  the `ARShaderTests` target (the project's `sources:` entry for that folder is a scanned group,
  not a synced folder reference).

## Fixed both symptoms?

Yes — one mechanism, one root cause, both views. The badge (`SlotBankStripView`) and the
draggable-late monitor tile (`MonitorTile`) both depended on the same missing subscription; both
now hold it.

## Testing

SwiftUI rendering itself can't be driven from XCTest in this project (no ViewInspector/
SnapshotTesting, confirmed tree-wide by a prior reviewer per the brief). Two things CAN be proven
without a live render, and both are proven:

1. **The properties are genuinely `@ObservedObject`-wrapped**, not a plain reference that compiles
   identically at every call site but never subscribes to anything. Proven via `Mirror` inspecting
   the compiler-synthesized `_deckAUnit`/`_deckBUnit` backing storage and asserting its runtime
   type is `ObservedObject<ShaderUnit>`. A plain `let`/`var` produces a stored property literally
   named `deckAUnit`, never `_deckAUnit` — this is a genuine mutation gate for "was the property
   wrapper removed," which an object-identity check alone cannot see (the reference is identical
   either way).
2. **`liveDeck(for:)` is correct against a real load through the real production call site** —
   `Instrument.load(_:onto:thenApply:)`, the same path every production call site (library click,
   slot recall) uses — not a reimplementation of it.

`App/ARShaderTests/DeckObservationSeamTests.swift`, 6 tests:
- `testSlotBankStripViewWrapsDeckAUnitInObservedObject` / `...DeckBUnit...`
- `testMonitorTileWrapsDeckAUnitInObservedObject` / `...DeckBUnit...`
- `testLiveDeckReflectsARealDeckALoadThroughTheProductionLoadPath`
- `testLiveDeckDistinguishesDeckAFromDeckB`

### Mutation proof (RED confirmed, then reverted)

**SlotBankStripView** — changed `@ObservedObject private var deckAUnit/deckBUnit: ShaderUnit` to
`private let deckAUnit/deckBUnit: ShaderUnit`, ran the suite:

```
Test Case '-[ARShaderTests.DeckObservationSeamTests testSlotBankStripViewWrapsDeckAUnitInObservedObject]' started.
.../DeckObservationSeamTests.swift:42: error: ... XCTAssertNotNil failed - deckAUnit must be an @ObservedObject-wrapped property (backing storage `_deckAUnit`) so a deck load invalidates this view
.../DeckObservationSeamTests.swift:45: error: ... XCTAssertTrue failed - must be wrapped as ObservedObject<ShaderUnit>, not merely present under some other type
Test Case '...testSlotBankStripViewWrapsDeckAUnitInObservedObject]' failed (0.110 seconds).
Test Case '...testSlotBankStripViewWrapsDeckBUnitInObservedObject]' started.
.../DeckObservationSeamTests.swift:54: error: ... XCTAssertNotNil failed - deckBUnit must be @ObservedObject-wrapped ...
.../DeckObservationSeamTests.swift:57: error: ... XCTAssertTrue failed
Test Case '...testSlotBankStripViewWrapsDeckBUnitInObservedObject]' failed (0.002 seconds).
Test Suite 'DeckObservationSeamTests' failed ... Executed 6 tests, with 4 failures (0 unexpected)
```

Reverted (`cp` from a pre-mutation backup). Re-ran: green.

**MonitorTile** — same mutation applied to `MonitorTile.deckAUnit`/`deckBUnit`, ran the suite:

```
Test Case '-[ARShaderTests.DeckObservationSeamTests testMonitorTileWrapsDeckAUnitInObservedObject]' started.
.../DeckObservationSeamTests.swift:66: error: ... XCTAssertNotNil failed - MonitorTile.deckAUnit must be @ObservedObject-wrapped so a deck load makes `dragPayload` draggable immediately rather than up to ~500ms late, riding the next renderStats republish
.../DeckObservationSeamTests.swift:70: error: ... XCTAssertTrue failed
Test Case '...testMonitorTileWrapsDeckAUnitInObservedObject]' failed (0.147 seconds).
Test Case '...testMonitorTileWrapsDeckBUnitInObservedObject]' started.
.../DeckObservationSeamTests.swift:77: error: ... XCTAssertNotNil failed - MonitorTile.deckBUnit must be @ObservedObject-wrapped ...
.../DeckObservationSeamTests.swift:79: error: ... XCTAssertTrue failed
Test Case '...testMonitorTileWrapsDeckBUnitInObservedObject]' failed (0.002 seconds).
Test Suite 'DeckObservationSeamTests' failed ... Executed 6 tests, with 4 failures (0 unexpected)
```

(The other four tests in the file — the two `SlotBankStripView` wrapper checks and the two
`liveDeck` functional tests — correctly stayed green under this mutation, since they exercise
`SlotBankStripView`, not `MonitorTile`.)

Reverted. Re-ran: green, confirmed below.

## Suite totals (via `xcrun xcresulttool`, not the console tail — per the brief's warning about a
post-restart summary line lying)

Full run, foreground, `xcodebuild test -project TrueISFEditor.xcodeproj -scheme ARShader
-destination 'platform=macOS' -derivedDataPath /tmp/arshader-ddata-bank`:

```json
{
  "failedTests" : 0,
  "passedTests" : 333,
  "result" : "Passed",
  "skippedTests" : 0,
  "totalTestCount" : 333
}
```

333 = the stated baseline of 327 + the 6 new tests in `DeckObservationSeamTests.swift`. The known
intermittent `testSteadyStateAllocatesNoNewTextures` hang was not encountered (0 failures,
0 skipped). All runs were foreground; no backgrounding.

## Files touched

- `App/ARShader/SlotBankStripView.swift`
- `App/ARShader/MonitorView.swift`
- `App/ARShaderTests/DeckObservationSeamTests.swift` (new)
- `App/TrueISFEditor.xcodeproj` (regenerated by `xcodegen generate`; gitignored, not part of the
  committed diff)

## On-device gate

Not yet re-confirmed on device — this is a code fix with a passing suite, matching this
codebase's own established precedent (`DeckStripView`'s identical fix was likewise never
independently unit-tested for the SwiftUI-invalidation half, only proven live). Per the project's
on-device gate doctrine, this should be flagged STAGED until the operator confirms the badge now
lights immediately on recall and the monitor tile is draggable right after a load, with no other
redraw needed first.
