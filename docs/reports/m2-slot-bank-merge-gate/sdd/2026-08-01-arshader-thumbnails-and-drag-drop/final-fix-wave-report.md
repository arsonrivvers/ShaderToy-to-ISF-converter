# Final fix wave — m2-slot-bank (9b21ad4 → HEAD)

Single implementer. Every item from the merge-gate review's fix wave, plus the operator's two
in-session rulings (F3's undo shape, F12's inert library row).

**Suites:** ARShader **325** tests, 0 failures, 0 skipped (299 → 325: +27 added, 1 deleted).
TrueISFEditor **514** tests, 3 skipped, 0 failures — unchanged from the plan's baseline.

**Commit range:** `9b21ad4..HEAD` — 5 commits:

| SHA | Contents |
|---|---|
| `26cdbd7` | F1, F2 |
| `555dd70` | F3, F4, F9 |
| `df48a58` | F5, F6 |
| `0428584` | F7, F8, F10, F12, F13a–d (and F11's refusal) |
| (docs) | F12 plan legs, F14, stale-snippet annotations |

**Two items are NOT as the brief described them.** F11's premise does not hold (the race is
unreachable — the check is dead code), and F6's suggested assertion cannot fail. Both are detailed
below with evidence; neither was implemented as written.

---

## F1 — one undecodable slot destroys the whole bank — **ADDRESSED**

`App/ARShader/SlotBankStore.swift` (rewritten, `:34-150`).

- Per-element decode via a `FailablePreset` wrapper, the same shape as
  `ParamSnapshot.FailableParamValue` (`App/ISFRuntime/ParamStore.swift:88-93`) and the same
  motivation as `Arrangement`'s hand-written `init(from:)` (`App/ARShader/SurfaceLayout.swift:102-116`).
- **DEVIATION (small):** `map { $0?.value }`, not `compactMap` as the brief said. `compactMap` on an
  array of optionals drops the empty slots too, collapsing every later look one position to the
  left. `ParamSnapshot`'s precedent is `compactMapValues` on a DICTIONARY, where positions are keys
  and the hazard does not exist. Pinned by the "at its own index" assertion.
- `loadFailed` + `save()` refusing to overwrite; failure observable via
  `lastFailureReasonForTesting` (the `ThumbnailService` naming convention).
- `assertionFailure` removed; non-finite param values dropped before encoding.
- **`SlotBankStore` is now a `final class`.** `load()` runs inline in `Instrument.init` and `save()`
  from the `slotBank.onChange` closure; a struct captured by that closure would carry a copy taken
  before the flag was ever set. Recorded in the type's doc comment.

**Tests (5 new, `App/ARShaderTests/SlotBankStoreTests.swift`):**
`testOneUnreadableSlotCostsOneSlotAndNotTheWholeBank`,
`testALossyLoadTakesSaveOutOfServiceRatherThanOverwritingTheStoredBytes`,
`testWhollyCorruptStoredDataAlsoTakesSaveOutOfService`,
`testAFirstLaunchWithNothingStoredStillPersists`,
`testANonFiniteParamValueCostsThatParamAndNotThePersistenceOfTheBank`.

**Mutation proofs (3, all reverted):**

1. `FailablePreset.init(from:)` `try?` → `try` (restores all-or-nothing exactly):
   ```
   SlotBankStoreTests.swift:65: XCTAssertEqual failed: ("nil") is not equal to
     ("Optional(ParamValue.float(0.4))") - the readable slot before the bad one must survive
   SlotBankStoreTests.swift:68: ... - a readable slot AFTER the bad one must survive too
   → 2 failures
   ```
2. `save()`'s `guard !loadFailed` → `guard !false`:
   ```
   :85: XCTAssertEqual failed: ("Optional(364 bytes)") is not equal to ("Optional(19 bytes)")
        - 'we cannot read it' must never become 'it is gone'
   :88: XCTAssertNotNil failed - and the refusal has to be observable, not silent
   :100: XCTAssertEqual failed: ("Optional(364 bytes)") is not equal to ("Optional(8 bytes)")
   → 3 failures
   ```
3. Sanitiser removed from the encode call:
   ```
   :130: XCTAssertNil failed: "Slot bank could not be encoded: EncodingError.invalidValue:
         nan (Double). Path: [0].snapshot.params.speed.value."
   → 2 failures
   ```
   This third one also confirms the old `assertionFailure` path was genuinely reachable, not
   theoretical.

---

## F2 — `loadThumbnails` ignores cancellation — **ADDRESSED**

`App/ARShader/SlotBankStripView.swift:288` — `guard !Task.isCancelled else { return }` at the top of
the loop. `loadThumbnails` widened from `private` to internal, following the `wouldAccept`
precedent already in the file; the doc comment now states what the guard buys and why awaiting an
actor method is not a cancellation point.

**Test:** `SlotBankStripViewDropSeamTests.testACancelledThumbnailSweepStopsRatherThanRunningToCompletion`.
Deterministic by construction, not by hope: the test is `@MainActor`, `Task { }` inherits that
actor, so the child cannot start before the test suspends — `cancel()` on the next line always
lands first. Uses a real `solid_red.fs` fixture URL deliberately: an unreadable path fails before
the transpile, so `compileCountForTesting` would read 0 either way and the test could not fail.

**Mutation (reverted):** guard removed →
```
:99: XCTAssertEqual failed: ("1") is not equal to ("0") - a cancelled sweep must issue NO
     further requests
```

---

## F3 — right-click → Clear is a one-click permanent wipe — **ADDRESSED**

`App/ARShader/SlotBank.swift` (model), `App/ARShader/SlotBankStripView.swift` (invocation).

- `SlotBank.UndoableSlotChange` + `@Published private(set) var undoable`, armed by `clear()` and by
  a `capture()` that overwrote something (the ⌥-drop case, which fell out for free as the brief
  allowed). `undo()` restores and disarms — one deep, never a redo stack.
- **Safety rule the review did not specify:** any later write to the SAME index disarms the
  undoable. Without it, `clear(1)` → `capture(into: 1)` → `undo()` would silently destroy the look
  just captured. Proven by mutation (below).
- **Invocation path (required by the operator's ruling, absent from the review's proposal):** an
  "Undo clear slot N" / "Undo replace slot N" item in the strip's context menu, present only while
  something is restorable. Handed to EVERY cell, not just the affected one — after a clear that cell
  is empty and is the least likely one to be right-clicked next; the title names the slot so no cell
  can imply it is the one being restored.
- No dialog, no confirmation sheet, per the ruling.

**Tests (7 new, `SlotBankTests`):** undo-a-clear with values intact, undo-an-overwrite, the disarm
rule, a fresh bank's no-op, clearing an empty slot arming nothing, the menu titles, and that undo
persists like every other write.

**Mutation proofs (2, both reverted):**

1. `clear()` no longer arming the undoable:
   ```
   :121: XCTAssertEqual failed: ("nil") is not equal to ("Optional(ParamValue.float(0.77))")
   :178: XCTAssertEqual failed: ("nil") is not equal to ("Optional("Undo clear slot 7")")
   :192: XCTAssertEqual failed: ("0") is not equal to ("1") - a restored look that is not
         persisted comes back only until relaunch
   → 3 failures
   ```
2. The disarm rule (`undoable?.index == index` → `false`) — note the second line shows the mutation
   actually destroying the new capture:
   ```
   :145: XCTAssertNil failed: "UndoableSlotChange(index: 1, preset: ... name: "old.fs" ...)"
   :149: XCTAssertEqual failed: ("Optional("old.fs")") is not equal to ("Optional("new.fs")")
         - undo must be a no-op here, not a way to destroy the new capture
   → 2 failures
   ```

---

## F4 — one malformed program frame when the projector opens — **ADDRESSED**

`App/ARShader/InstrumentRenderer.swift:456-484`.

`liveResolutionLocked()` is re-read inside the SECOND lock region; on a mismatch with the value the
decks rasterised at, the master is cleared and the composite plus `masterFX.encode` are skipped.

**DEVIATION from the review's suggested outcome:** it says "the previous master stays up — one
repeated frame instead of one wrong one." That is not available. Every path that can move the live
size (`isProgramLive`, `previewScale`, `outputResolution`) calls `reallocateMastersLocked()`, so on
a genuine mismatch `masters` has already been replaced by a freshly allocated pair whose contents
are undefined. The clear is what makes the skipped frame black rather than garbage. Documented at
the call site.

**Why the lock ordering cannot deadlock:** no new lock is acquired. `liveResolutionLocked()` is a
`private` "requires lock held" reader of two stored properties (`programLive`, `masterResolution`,
`renderScale`) and takes no lock itself. This is the same single `lock`, already held by the caller,
doing one more read. There is no second lock anywhere in the frame path and therefore no ordering to
get wrong. The added test seam (`didRasteriseDecksForTesting`) fires in the UNLOCKED window, so a
test flipping `isProgramLive` from it acquires the lock cleanly.

**New production surface, both inert in production:** `didRasteriseDecksForTesting` (nil) and
`skippedStaleCompositeCountForTesting` (0). The seam exists because both halves of the race run
inside one synchronous `renderFrame()` on one thread — there is no other way to drive it, and I
would rather test the real race at the real call site than a re-derivation of it.

**Tests (2, `InstrumentRendererTests`):**
`testAFrameWhoseLiveSizeMovesMidRenderSkipsTheCompositeRatherThanDrawingItWrong` (which also asserts
the NEXT frame is normal — this skips one frame, it does not wedge) and
`testAnUndisturbedFrameNeverSkipsItsComposite`.

**Mutation (reverted):** `let compositeRes = liveResolutionLocked()` → `= liveRes`:
```
:60: XCTAssertEqual failed: ("0") is not equal to ("1") - the frame whose live size moved under
     it must be skipped
:66: XCTAssertEqual failed: ("0") is not equal to ("1")
→ 2 failures
```

---

## F5 — nothing gates the strip's HEIGHT — **ADDRESSED**

`App/ARShaderTests/SurfaceGeometryTests.swift` — `.measured("slots", in: Self.space)` on the real
`SlotBankStripView` inside `slotBankSurface`, plus
`testTheStripsHeightIsBoundedByTheCellCeilingAtAWideWindow`: at 2560pt the strip's height must be
≤ `maxCellWidth * 9/16 + slotStripChromeBudget`, and > one cell tall so a collapsed strip cannot
pass it either.

**DEVIATION (small):** the chrome constant is test-local (`slotStripChromeBudget = 56`), not a
`SurfaceMetrics` entry as the brief implied. Nothing in production would read it, and a production
constant with only a test consumer is coverage of dead code wearing the costume of a shared value —
the exact smell the review flagged at L77. Same treatment as the existing `knownCellOverflow`.
Measured chrome is **41pt** (131pt strip at 2560pt, of which 90pt is the cell); 56 leaves room for
text-metric drift and is nowhere near loose enough to hide the failure class, which is measured in
hundreds of points.

**Mutation proofs (2, both reverted):**

1. Ceiling removed from `cellWidth` (`min(max(…), maxCellWidth)` → `max(…)`) — task 3's actual
   shipped defect:
   ```
   :545: XCTAssertLessThanOrEqual failed: ("191.8203125") is greater than ("146.0")
   (and the pre-existing width gate at :493: "268.125" > "160.0")
   ```
2. **Height-ONLY mutation**, to prove the new gate is not merely riding the width gate — header
   `.padding(.vertical, 4→40)`:
   ```
   :545: XCTAssertLessThanOrEqual failed: ("203.0") is greater than ("146.0")
   → 1 failure, and NOTHING else in the suite failed.
   ```

---

## F6 — no test renders a FILLED cell — **ADDRESSED, with a correction to the brief**

`slotBankSurface(instrument:layout:isFilled:)` seeds slot 0 by default. Row 0 / column 0 is both the
seeded slot and the cell `RenderedCellWidthKey` reports from, so every rendered-geometry assertion in
the file now lays out a filled cell: the name plate, the 0.22 fill plate, the `state.borderColor`
overlay, the shake modifiers, `helpText` and the accessibility label.

**DEVIATION — the review's suggested assertion cannot fail, and was not written.** It asked to
"assert `measuredRenderedCellWidth` is unchanged from the empty case." `SlotCell` is sized by
`.frame(width: cellWidth, height: cellWidth * 9/16)` applied OUTSIDE it at the `ForEach` call site,
and `.frame(width:height:)` with both dimensions non-nil reports exactly that size to its parent
regardless of what the child does. No change inside `SlotCell` can move the number.

Verified by mutation rather than argued: I wrote the test, then applied
`.padding(preset == nil ? 0 : 20)` inside the cell — the textbook "a filled cell blows out its
neighbours" defect — and **all 15 tests stayed green**. I deleted the test rather than ship this
phase's seventh tests-that-cannot-fail. The reasoning is recorded in the file at the point where the
test would have been.

**What F6 actually buys, proven:** a `preconditionFailure` planted in `SlotCell.helpText`'s
filled-only path TRAPPED the geometry tests —
```
ARShaderTests/SlotBankStripView.swift:752: Fatal error: F6 mutation probe — the filled branch
was reached
💣 Program crashed: Signal 5 ... Thread 0 crashed
```
Before this change that line was never reached by any test in the branch. So: a crash or trap in the
filled branch is now caught; its GEOMETRY is structurally unobservable, which is a property of the
pinned frame rather than a gap in the suite. Both facts are written into the file.

---

## F7 — no loading state in the hover preview well — **ADDRESSED**

`App/ARShader/LibraryPanelView.swift` — `@State isResolvingPreview`, plus a named `WellState`
(`empty` / `settled` / `resolving`) that `hoverPreviewWell` calls for its `imageOpacity` and its
`ProgressView`. One rule, one call site, no second copy.

Fixed height in every state — the well's `.frame(height: 120)` is untouched and the spinner is an
overlay. The flag is set AFTER the dwell, not on hover-enter: a row merely swept past never requests
anything, so flagging earlier would flicker the well on every row the pointer crossed.

**Scope note, stated rather than glossed:** the pure MAPPING is what is tested. The `@State` flag's
lifecycle lives inside a `.task(id:)` closure with no seam a unit test can drive without hosting the
view; the mapping is the part that decides whether a stale still reads as settled, which is the
defect. Leg 28 remains the on-device gate.

**Tests (3, `LibraryPanelTests`):** stale-while-resolving, settled at full strength, and an empty
well still reporting an outstanding request.

**Mutation (reverted):** `wellState` losing its `resolving` case:
```
:88: XCTAssertEqual failed: ("settled") is not equal to ("resolving")
:107: XCTAssertEqual failed: ("empty") is not equal to ("resolving")
→ 2 failures
```

---

## F8 — `wouldAccept` reads `NSEvent.modifierFlags` inline — **ADDRESSED (cheap half only, as directed)**

`wouldAccept(_:at:withOption:)` and `wouldHighlight(at:withOption:)` take a defaulted parameter;
production call sites are unchanged and still sample live modifier state.

Also pinned the existing without-⌥ assertions to `withOption: false` explicitly — they previously
read the LIVE `NSEvent.modifierFlags`, so the never-overwrite invariant's own gate was
ambient-state-dependent.

**Hover-enter sampling NOT fixed**, per the brief — deferred to an operator device leg, and the
deferral is recorded in `wouldAccept`'s doc comment.

**Tests (3):** `testAFilledSlotAcceptsAnOverwriteWhenOptionIsHeld`,
`testAFilledSlotHighlightsWhenOptionIsHeld`, `testOptionDoesNotChangeAnEmptySlotsAnswer`.

**Mutation (reverted):** `withOption: option` → `withOption: false` at the `ShaderDrag.accepts` call:
```
:74: XCTAssertTrue failed - ⌥ held is the deliberate overwrite gesture
:84: XCTAssertTrue failed - the ring ... must track ⌥ as well as fill state
→ 2 failures
```

---

## F9 — 16 MB reallocated per keystroke — **ADDRESSED**

`InstrumentRenderer.reallocateMastersLocked()` now no-ops when the RESOLVED size is unchanged.
Guarding on the resolved size rather than on each setter's own input covers `previewScale`,
`outputResolution` and `isProgramLive` with one check and keeps `liveResolutionLocked()` the single
source of the preview/program rule, as the review suggested.

**Tests (2):** `testTypingIntoPreviewScaleWhileProjectingReallocatesNothing` (types "100" one
character at a time: 1, 10, 100) and `testPreviewScaleStillReallocatesWhenItActuallyChangesTheLiveSize`
— the second exists so the guard cannot break the case it lives inside.

**Mutation (reverted):** guard removed:
```
:94: XCTAssertTrue failed - a control that is inert while projecting must not churn the
     master pair
```

---

## F10 — `testNoRecallTargetIsAnFXChain` cannot fail — **ADDRESSED (deleted)**

Deleted from `SlotRecallTargetTests.swift`, with an in-file note recording why and why it was not
replaced. **Suite count drops by 1 from this item, as expected.** The review's suggested replacement
(extract `recallLibraryTarget(for:)` and pin it) would pin a mapping with exactly one production
call site inside `recall(_:)` — a re-derivation of that line, not a gate on it.

The plan's own copy of the test (`plans/…md:990`) is annotated SUPERSEDED in place so it cannot be
copied back.

---

## F11 — `ISFSceneLoader.ensureGlobals` data race — **NOT IMPLEMENTED. The brief's mechanism is wrong.**

**The check is dead code, so there is no check-then-set race to synchronise.**
`vendor/prebuilt/ISFMSLKit.framework/Headers/ISFMSLCache.h` declares
`@property (class,strong) ISFMSLCache * primary;` inside `NS_ASSUME_NONNULL_BEGIN` (`:15`/`:88`), so
Swift imports it as NON-optional. The compiler already says so, at HEAD, before any change of mine:

```
App/ISFRuntime/ISFSceneLoader.swift:26:29: warning: comparing non-optional value of type
  'VVMTLPool' to 'nil' always returns false
App/ISFRuntime/ISFSceneLoader.swift:27:32: warning: comparing non-optional value of type
  'ISFMSLCache' to 'nil' always returns false
```

Both `if … == nil` bodies are statically unreachable. Neither `VVMTLPool.global` nor
`ISFMSLCache.primary` is ever assigned by this function. Two threads cannot race to construct an
`ISFMSLCache` because no thread ever constructs one here. A lock would have been ceremony over code
that does not run — and the test I had drafted for it (a widened critical section plus a
construction counter) would have been a test of a code path production never enters.

I built and then reverted the lock, the counter and the test. `ISFSceneLoader.swift` is byte-identical
to HEAD; the TrueISFEditor suite is therefore untouched and was still run: **514, 3 skipped, 0
failures.**

**The real defect underneath is larger and hits the brief's STOP condition.** `ensureGlobals`'s doc
comment says `ISFMSLScene.loadURL:` "fails SILENTLY without these — no scene, no error message", and
this function is the thing that is supposed to guarantee them. It does not. It works today only
because `InstrumentRenderer.init` pre-sets `VVMTLPool.global`; `ISFMSLCache.primary` — the on-disk
MSL precompile cache — appears never to be installed at all. Making the checks live (a nullable
accessor, or `NS_ASSUME_NONNULL` corrections to the vendored header) would install `primary` for the
first time, in BOTH targets, changing on-disk MSL caching behaviour for the editor. The brief says:
"If the fix cannot be made without changing behaviour for the editor, STOP and report rather than
proceeding." That is what this is. **Filed for the operator, not fixed here.**

---

## F12 — the library-row click becomes INERT again — **ADDRESSED**

`App/ARShader/LibraryPanelView.swift`:

- `:170-177` — the `Button` is replaced by a plain `Text` row. `.draggable`, `.help`, `.onHover` and
  `.contentShape(Rectangle())` all kept.
- `:152-169` — the comment block that argued FOR the Button on a11y grounds is replaced by the new
  ruling. The prior ruling and its reasoning are recorded as SUPERSEDED, not deleted, along with the
  consequences accepted (no button trait, no activate action, no keyboard load path).
- `:180-181` — `.help` copy drops "click to load onto deck A"; the drag hint stays.
- Plan `:1524` — leg 35 reverts to "clicking a library row does NOTHING", marked **REWRITTEN AGAIN
  2026-08-02** with the superseding ruling.
- Plan `:1525` — leg 35b **STRUCK in place** (`~~35b~~`) with its reason, explicitly not renumbered.

I re-ran the brief's grep: nothing in `ARShaderTests` pinned the click→deck-A behaviour, so no test
was removed. (`InstrumentLoadTests`' `onto: .deck(.one)` hits are `Instrument.load` calls, unrelated
to the row.) No test added: the change is a deletion of behaviour, and its absence is precisely what
smoke leg 35 now asserts.

---

## F13 — four triage items — **ALL ADDRESSED**

**(a) L4 — positive queue assertion.** `testTheServiceNeverUsesTheLiveRenderQueue` now also asserts
`serviceQueue === RenderProperties.global().bgCmdQueue`.
*Mutation (reverted):* gave the service a third private queue (`device.makeCommandQueue()!`) — passes
"not the live one", fails the new assertion:
```
:104: XCTAssertTrue failed - and it must be the shared background queue specifically
→ 1 failure, the new assertion ONLY
```

**(b) L33 — cache directory.** `ThumbnailService.cacheDirectoryForTesting` (backed by
`ThumbnailCache.directoryForTesting`) plus
`testAHarnessInstrumentNeverResolvesTheOperatorsRealThumbnailCache` — pure string comparison, no I/O.
*Mutation (reverted):* `if TestHarness.isActive` → `if false` in `Instrument.init`:
```
:120: XCTAssertTrue failed - a test instrument's cache must live under the temporary directory
      — got /Users/arsonrivvers/Library/Application Support/ARShader/Thumbnails
:126: XCTAssertFalse failed - and must never be under Application Support
→ 2 failures
```

**(c) L79 — exported UTI.** `com.arshader.shader-drag` → `com.arsonrivvers.ARShader.shader-drag` in
`App/ARShader/Info.plist:17` and `App/ARShader/ShaderDrag.swift:68`.
*Note on the brief's citation:* it gives `Info.plist:104` and the review gives `:93`; the file is 26
lines and the declaration is at `:17`. Same declaration, wrong line number in both.
The test asserts against the HOST APP's real `Info.plist` via `Bundle.main` (the test bundle is
hosted — `TEST_HOST` in `project.yml`), so code/plist DRIFT is caught, not just the literal.
*Mutation (reverted):* reverted the Swift constant only:
```
:158: XCTAssertTrue failed - com.arshader.shader-drag is not under com.arsonrivvers.ARShader
:166: XCTAssertTrue failed - Swift says com.arshader.shader-drag, Info.plist says
      ["com.arsonrivvers.ARShader.shader-drag"]
→ 2 failures
```

**(d) `ShaderUnit.load(url:)` generation bump.** `loadGeneration += 1` on the unreadable path, plus
`isLoading = false` — without the latter the newly-superseded load leaves the spinner up forever,
which the bump itself creates. (Disclosed: the brief said "one line"; this is two, and the second is
a direct consequence of the first.)
*Test:* `testAnUnreadableFileSupersedesACompileAlreadyInFlight`.
*Mutation (reverted):* bump removed:
```
:71: Fulfilled inverted expectation "A's compile must NOT apply".
:75: XCTAssertNotNil failed - the error the operator was just shown must not be cleared
:78: XCTAssertNil failed: "file:///…/shaderunit-….fs" - a superseded load must never stamp
     sourceURL — that is what lights the wrong slot's live badge
→ 3 failures
```

---

## F14 — the wrong `~207pt` figure — **ADDRESSED**

Annotated as superseded in place, not deleted, at both misleading sites:

- `docs/superpowers/plans/2026-08-01-arshader-thumbnails-and-drag-drop.md:1791` — inline correction.
- `docs/superpowers/specs/2026-08-01-arshader-responsive-surface-design.md:22` — block quote, with
  the explicit note that the section's ARGUMENT is unaffected and only the magnitude was overstated.

Both point at `SurfaceMetrics.maxCellWidth`'s doc comment as authoritative.
`SurfaceGeometryTests:311`'s coincidental `−207` left alone, as directed.

---

## Verification sweeps (no truncation, per CLAUDE.md #8)

```
$ grep -rn "com\.arshader" App/ docs/ .superpowers/ | grep -v ShaderDragTests.swift:148
docs/superpowers/plans/…md:1204  (historical task snippet — now annotated SUPERSEDED in place)
count: 1  → 0 live occurrences

$ grep -rn "testNoRecallTargetIsAnFXChain" App/ docs/ .superpowers/ | grep -v SlotRecallTargetTests
docs/superpowers/plans/…md:990   (historical task snippet — now annotated SUPERSEDED in place)
count: 1  → 0 live occurrences

$ grep -rn "MUTATION probe\|mutation probe\|MUTATION:" App/
count: 0   → every mutation reverted

$ grep -rn "click to load onto deck A" App/
App/ARShader/LibraryPanelView.swift:180  (the comment explaining the removal)
count: 1  → 0 live occurrences in UI copy
```

---

## What I did NOT do

1. **F11's lock** — refused with evidence (see above). The underlying dead-nil-check defect is
   FILED, not fixed: fixing it changes editor behaviour, which is the brief's stated STOP condition.
2. **F8's hover-enter ⌥ sampling** — deferred to a device leg, as the brief directed.
3. **The F6 geometry assertion the review asked for** — proven unable to fail; deleted rather than
   shipped. The seeding it depended on is in.
4. **No test for the F3 undo's VIEW wiring.** `SlotCell` is `private` and the
   `undoTitle: bank.undoable?.menuTitle` hand-down lives inside `body`; this is the same irreducible
   `.dropDestination`-closure seam the review already documented as acceptable, and I have not
   pretended otherwise. The MODEL is fully covered.
5. **No new files.** Everything landed in existing sources and existing test files, so the committed
   `.xcodeproj` needed no xcodegen regeneration.
6. **Nothing outside the item list was touched.** The one adjacent edit — annotating two stale plan
   snippets that the sweeps surfaced — is disclosed above and in the commits.
7. **No on-device verification.** Every fix here is STAGED, not CONFIRMED. F4 in particular
   ("is the malformed frame visible on the wall") remains a device question; the fix is now gated by
   a test either way.

## Recommended next step

Scoped re-review, then merge. Two items want the operator's eye first: the F11 filing (a real defect
with a cross-target blast radius, currently unaddressed at HEAD), and the F3 undo's menu placement
(shown on every cell, which is a judgement call the device session should confirm).
