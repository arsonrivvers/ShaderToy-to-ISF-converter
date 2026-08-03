# Task 4 report: `RECALL TO: A | B` + layout fixes (addition 1/2/3)

## What was implemented

### Task 4 core: RECALL TO constrained to decks
- `SlotBankStripView`: removed the SOURCE picker and its `@State private var source: DeckID`.
  `@Binding var target: LibraryTarget` replaced with `@State private var recallTarget: DeckID = .one`.
  Added `static var recallTargets: [DeckID] { DeckID.allCases }`.
- RECALL TO picker now iterates `Self.recallTargets` (2 segments: A, B), bound to `$recallTarget`.
- `recall(_:)` now calls `instrument.load(preset.shaderURL, onto: .deck(recallTarget), thenApply:)`.
- `capture(into:)` is now a no-op (`private func capture(into index: Int) {}`), documented as
  deliberate: SOURCE is gone, so there is no deck to capture FROM until task 6 restores capture via
  a deck-monitor drag. `SlotCell` itself (its `activate()` and context menu) is untouched, per the
  global constraint — clicking an empty cell or Replace silently does nothing this review cycle.
- `InstrumentView`: drops `target: $libraryTarget` from the `SlotBankStripView(...)` call site.
  `libraryTarget` itself is kept — `LibraryPanelView` still needs it until task 5.
- New file `SlotRecallTargetTests.swift`, exactly as specified in the brief (2 tests).

### Addition 1 (highest priority): the strip is far too tall
**Diagnosis confirmed and fixed.** `SlotCell`'s call site used
`.frame(minWidth: SurfaceMetrics.minCellWidth, maxWidth: .infinity)`, letting the ambient
HStack/ScrollView proposal stretch each cell's width in a real window (operator screenshot:
~1/8 of available width per cell, two rows rivaling the monitor strip in height).

**Fix:** drive sizing from an explicit fixed HEIGHT, with width derived at 16:9, using
`.frame(width:height:)` (exact, both axes) instead of `.frame(minWidth:, maxWidth: .infinity)`.
- New constant `SurfaceMetrics.slotCellHeight: CGFloat = 54` — the driving constant.
- `SurfaceMetrics.minCellWidth` changed from an independent `let = 96` to a derived
  `var { slotCellHeight * 16.0 / 9.0 }` (still exactly 96 — no behavior change to callers that
  reason about it as a floor).
- `SurfaceMetrics.slotStripRowHeight` changed from `let = 60` to `var { slotCellHeight +
  slotStripCellSpacing }` (still exactly 60).
- Cell call site in `SlotBankStripView.content`: `.frame(width: SurfaceMetrics.minCellWidth,
  height: SurfaceMetrics.slotCellHeight)`.

**Height constant chosen: 54pt** (→ width 96pt). Reasoning: task 3 already vetted 96pt-wide /
54pt-tall as the legibility floor for a 16:9 thumbnail ("unreadable as a still" below it, per its
own doc comment) and as the anti-overlap floor (`.contentShape` hit areas). That floor was always
*meant* to be the cell's actual size, not just a lower bound the old code failed to enforce — this
fix makes production actually reach it, using the SAME already-reviewed number rather than picking
a new, unvetted one. I did not invent a smaller number: shrinking below 96pt risks reopening the
"unreadable thumbnail" problem task 3 raised `minCellWidth` to fix in the first place.

**A material finding that changes what this fix can claim to have proven** (see "Concerns" below):
mutation-testing the new test against the exact old buggy modifier chain — including rendering the
REAL `SlotBankStripView` inside a real `InstrumentSurface` — still measured cells pinned at the
floor in the render harness. The harness cannot reproduce the operator's screenshot at all, old
code or new. The fix is correct on `.frame(width:height:)`'s documented, proposal-independent
semantics, not on empirical reproduction. I've marked this STAGED, not CONFIRMED, in the code
comments and below.

### Addition 2: `SurfaceMetrics.stripsMinWidth`
**Verified, not blindly trusted — and the given estimate did not hold up.** The brief said the true
minimum had drifted to ~655pt against the declared 620pt. I split `InstrumentView.deckStrips` into
`deckStripsContent` (unfloored, testable) + the `.frame(minWidth:)` wrapper, and measured
`deckStripsContent`'s real natural width via `.fixedSize(horizontal: true, vertical: false)` in the
render harness: **~619pt** — already covered by the existing 620pt floor, with no stale gap open.
I did not raise `stripsMinWidth`; doing so on an unverified number would have widened
`reservedWidth`/`minWindowWidth` for no measured reason. `testTheReservedWidthMatchesTheRegionsItClaimsToCover`
is kept (still useful — catches the two redundant constants drifting from each other) and a new
test, `testTheDeckStripsFloorCoversTheirMeasuredNaturalWidth`, adds the actual reality check the
addition asked for: it will fail if the deck strips' content ever needs more than the declared
floor. `SurfaceLayout.reservedSurfaceWidth` is unchanged (872) since `stripsMinWidth` is unchanged.

### Addition 3: `knownCellOverflow`
Redone from the shipped numbers. Chrome (SOURCE removed, `slotStripGapCount` 3→2, `slotStripRecallWidth`
90 — reusing SOURCE's own DeckID-picker width, since RECALL TO is now literally the same widget):
`16 + 90 + 20 + 1 = 127pt` (was 357pt). At `minWindowWidth` (1180, no panel): `contentColumn = 934`,
`cellsRegion = 934 − 127 = 807`. `needed = 96×8 + 6×7 = 810`. **Shortfall = 3pt** (down from 233,
not fully closed — closing it needed RECALL TO ≤87pt; 90pt is task 4's actual shipped width, reused
rather than reverse-engineered to force closure). `knownCellOverflow` lowered from 233 to 3.

## Tests and results

Full suite: **281 tests, 0 failures, 0 skipped** (baseline 278 + 2 `SlotRecallTargetTests` + 1
`testTheDeckStripsFloorCoversTheirMeasuredNaturalWidth`; net zero from swapping
`testCellWidthIsPinnedAtItsFloorRegardlessOfWindowWidth` → `testCellSizeIsPinnedRegardlessOfWindowWidth`).

Command:
```
xcodebuild test -project App/TrueISFEditor.xcodeproj -scheme ARShader \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/arshader-ddata-bank \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=YES
```

Required gates re-run and green: `testTheMonitorStripIsUnmovedByTheSlotStripBelowIt`,
`testTheMonitorStripDoesNotResizeWhenTheStripsBelowItChange`, `testTheMonitorStripStaysPinnedToTheTop`.

### TDD evidence
- **RED**: `SlotRecallTargetTests.swift` written first per the brief; `SlotBankStripView.recallTargets`
  did not exist → compile failure (brief step 2).
- **GREEN**: after implementing, `SlotRecallTargetTests` (2/2) and full suite pass.
- **Mutation 1** (brief step 6): `recallTargets` mutated to `DeckID.allCases + DeckID.allCases` →
  `testRecallTargetsAreDecksOnly` failed on the count assertion as expected. Reverted.
- **Mutation 2** (Addition 1): reverted the cell's stand-in in `testCellSizeIsPinnedRegardlessOfWindowWidth`
  to the exact old `.aspectRatio(.fit) + .frame(minWidth:, maxWidth: .infinity)` chain → test still
  PASSED (did not distinguish old from new). Then, to rule out a stand-in artifact, mutated
  production `SlotBankStripView`'s real cell call site back to the same old chain and rendered the
  REAL component in a REAL `InstrumentSurface` with a real `Instrument`, measuring the whole strip's
  height at two window widths (1180 vs 2400) — height was identical (95pt/95pt with the fix, 78pt/78pt
  with the old code) at BOTH widths, in both cases. The render harness (a single
  `NSHostingView.layoutSubtreeIfNeeded()` pass) cannot reproduce the operator's screenshot at all —
  this is a genuine limitation of the harness technique, not something this task closed. Both
  temporary probes were removed; production and test code were restored to the fixed/final state
  before the final full-suite run.

## Files changed
- `App/ARShader/SlotBankStripView.swift` — RECALL TO → DeckID, SOURCE removed, capture no-op, exact
  cell frame.
- `App/ARShader/InstrumentView.swift` — drops the `target:` argument at the call site; splits
  `deckStrips` into `deckStripsContent` (testable) + the floor.
- `App/ARShader/InstrumentSurface.swift` — `SurfaceMetrics`: removed `slotStripSourceWidth`;
  `slotStripRecallWidth` 220→90; `slotStripGapCount` 3→2; added `slotCellHeight`; `minCellWidth` and
  `slotStripRowHeight` now derived.
- `App/ARShaderTests/SlotRecallTargetTests.swift` — new, per brief.
- `App/ARShaderTests/SurfaceGeometryTests.swift` — new `testTheDeckStripsFloorCoversTheirMeasuredNaturalWidth`;
  `knownCellOverflow` 233→3 with recomputed doc comment; replaced
  `testCellWidthIsPinnedAtItsFloorRegardlessOfWindowWidth` with `testCellSizeIsPinnedRegardlessOfWindowWidth`
  (renders through a real `InstrumentSurface` with production-faithful sibling structure).

## Self-review findings
- Confirmed no dangling references to `source`, `$target`, or `slotStripSourceWidth` anywhere in
  `App/ARShader` or `App/ARShaderTests` (grepped explicitly).
- Confirmed `SlotCell.activate()` and its context menu were not touched (global constraint).
- Confirmed `libraryTarget` in `InstrumentView` is still used by `LibraryPanelView` (not dead code).
- `SurfaceLayout.reservedSurfaceWidth` was NOT changed, since `stripsMinWidth` was not changed —
  verified `testTheReservedWidthMatchesTheRegionsItClaimsToCover` still passes.
- xcodeproj is XcodeGen-generated and gitignored; regenerated via `xcodegen generate` in `App/`
  after adding the new test file, not committed.

## Concerns (read this before treating Addition 1 as closed)
1. **Addition 1's fix is STAGED, not CONFIRMED.** The render harness this codebase's geometry gates
   rely on cannot reproduce the operator's screenshot — verified by mutation-testing the REAL
   `SlotBankStripView` component with the OLD buggy code restored, inside a real `InstrumentSurface`:
   the harness still measured it pinned at the floor, at both a narrow and a wide window. The fix
   (`.frame(width:height:)`, which is documented, unconditional SwiftUI behavior — it reports
   exactly that size regardless of any ancestor's proposal) is very likely correct, and is
   structurally a strictly stronger guarantee than the old proposal-dependent
   `minWidth`/`.aspectRatio(.fit)` pair. But per this project's own on-device gate doctrine, a
   staged GPU/visual-layout fix that the operator hasn't seen live should not be called CONFIRMED
   off a green test suite alone. **Recommend: run the app, resize the window wide, and confirm the
   slot bank strip is now compact** before this is folded into a "done" milestone claim.
2. **Addition 2's given number (~655) did not hold up under measurement** (~619 measured vs. 620
   declared — no stale gap). I did not raise `stripsMinWidth`. If there's a different reproduction
   method behind the ~655 estimate (e.g., an actual live-window observation rather than a render-harness
   one), it would be worth comparing notes — the same category-gap between harness and live window
   that affected Addition 1 could apply here too, and I can't rule that out from a static render pass.
3. **Addition 3's gap does not fully close** (3pt shortfall remains at the window minimum with no
   panel open) — expected and explicitly allowed by the brief; not a defect.
4. Capture is fully non-functional between this task and task 6, as directed. The empty-cell "click
   to capture" affordance and the "Replace with SOURCE deck" context menu item are still visually
   present (per the constraint not to touch `SlotCell`) but silently do nothing — an accepted,
   temporary UX gap for one review cycle, not something I introduced beyond what was directed.

---

## Fix round 1 (4 Important findings)

Reviewer returned SPEC ✅, QUALITY 10 findings (0 Critical, 4 Important, 6 Minor). Fixed the four
Important (F1–F4); the six Minor (F5–F10) were explicitly deferred and NOT touched.

### F1 — `testCellSizeIsPinnedRegardlessOfWindowWidth` was a rigid-stub tautology
Replaced it with `testSlotBankStripCellsRowWidthIsPinnedRegardlessOfWindowWidth`, which renders the
REAL `SlotBankStripView` inside a real `InstrumentSurface` (not a hand-drawn `Color.blue` stand-in),
wrapped in `.fixedSize(horizontal: true, vertical: false)` to force it to report its own ideal
width, and asserts that total equals `slotStripLeadingChromeWidth + the 8-cell row's natural width`
at two window sizes. Mutation-proven both ways:
- **Deleting** `SlotCell`'s `.frame(width:height:)` call site entirely → test FAILS (441pt measured
  vs 937pt expected). The old test would have stayed green here (per the reviewer's finding);
  confirmed this is no longer true.
- **Reverting** to the exact old `.frame(minWidth:, maxWidth: .infinity)` chain → test still PASSES.
  Documented honestly in the test's doc comment, exactly as instructed: this harness cannot
  distinguish the fixed chain from the buggy one (same category-gap noted in fix-round 0's report),
  so the test is a production-coupled regression gate on the sizing mechanism, not proof the
  screenshot bug specifically cannot recur.

### F2 — `knownCellOverflow`'s doc comment repeated the false claim
Rewrote it to say what is actually true: the anti-overlap property rests on `SlotCell`'s call site
using an EXACT `.frame(width:height:)`, which is a property of the code (documented SwiftUI
semantics — an exact frame always reports precisely that size), not something the geometry tests
empirically prove. Named the correction explicitly and pointed at F1's replacement test with an
honest description of what it does and does not establish.

### F3 — the 619pt measurement was of an EMPTY deck strip; F4 — and non-deterministic
Both findings live in the same test (`testTheDeckStripsFloorCoversTheirMeasuredNaturalWidth`) and
were fixed together, then had to be reconciled with each other:

- **F4 (determinism) first**: force-expanded every `SectionKey` before measuring
  (`instrument.surfaceLayout.setExpanded(true, for:)`), removing the dependency on whatever
  `SurfaceLayoutStore()` had persisted to real `UserDefaults`. This alone moved the measured
  "empty" width from ~619pt to a deterministic **815pt** — proving F4's own point: the original
  619pt figure had been silently reading collapsed-section state, not a stable measurement.
- **815pt is a genuine, deterministic gap against the declared 620pt floor** — not something F3's
  "state it explicitly" escape hatch could respectably paper over once it was a repeatable number,
  not a machine-dependent fluke. Raised `SurfaceMetrics.stripsMinWidth` 620→830 (15pt margin).
- **That forced a cascade**, all mechanical (same formulas already established in the code, not new
  design choices): `SurfaceLayout.reservedSurfaceWidth` 872→1082 (must track `reservedWidth`'s
  formula, per the existing `testTheReservedWidthMatchesTheRegionsItClaimsToCover` gate);
  `SurfaceMetrics.minWindowWidth` 1180→1390 (carrying the same 28pt slack `minWindowWidth`'s own
  doc comment already used); `knownCellOverflow` 3→0 in `testEightCellsFitAtTheMinimumWindowWidthWithNoPanelOpen`
  (the wider window makes the 8-cell shortfall deeply negative, −207pt, as a side effect).
- **F3's "populate with a real shader" path was also tried** — loaded a fixture (image input + float
  input) onto both decks and an FX stage onto deck A via `Instrument.load` + the
  `onLoadSettledForTesting` seam, exactly as `InstrumentLoadTests` does — and measured **~993pt**.
  That is a much bigger number than anything in F3/F4's scope, and raising `stripsMinWidth` to cover
  it would cascade further still. I did NOT do that: it's flagged as a separate, deferred finding in
  the shipped test's doc comment, with the load code itself reverted out (scratch, not committed).
  Arithmetically it is no longer an open concern — the new `minWindowWidth` (1390) leaves
  `contentColumn` at 1144pt, comfortably above 993pt — but that is arithmetic against a once-measured
  number, not a fresh re-check, and I said so explicitly rather than implying it was reverified.

**Net effect of F3+F4 together: this fix round changed the window's declared minimum width**
(1180→1390), which was not anticipated going in. I did not do this lightly — see the reasoning above
for why it was unavoidable once F4's determinism fix was correctly applied (the reviewer's
instruction, not optional) rather than something I chose to expand into. Flagging prominently per
`CLAUDE.md`'s "surface conflicts, don't average them."

### Tests
Full suite: **281 tests, 0 failures, 0 skipped** (same count as before this round — one test
renamed/rewritten per F1, none added or removed). Command:
```
xcodebuild test -project App/TrueISFEditor.xcodeproj -scheme ARShader \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/arshader-ddata-bank \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=YES
```
Three required gates re-run and green: `testTheMonitorStripIsUnmovedByTheSlotStripBelowIt`,
`testTheMonitorStripDoesNotResizeWhenTheStripsBelowItChange`, `testTheMonitorStripStaysPinnedToTheTop`.

### Files changed (fix round 1)
- `App/ARShader/InstrumentSurface.swift` — `stripsMinWidth` 620→830, `minWindowWidth` 1180→1390,
  doc comments rewritten with the measured derivation.
- `App/ARShader/SurfaceLayout.swift` — `reservedSurfaceWidth` 872→1082 to match.
- `App/ARShaderTests/SurfaceGeometryTests.swift` — F1's test replaced; F2's doc comment corrected;
  F3/F4's test made deterministic; `knownCellOverflow` 3→0 with recomputed doc comment.
- `App/ARShader/SlotBankStripView.swift` — unchanged (mutation-testing edits made and reverted,
  confirmed via `git diff` showing no residual diff before commit).

### Concerns carried forward
- The `minWindowWidth` raise to 1390 is a real, user-visible change (the app now refuses to shrink
  the window as narrow as before) that exists because a determinism bug in a TEST forced a truthful
  remeasurement of a UI constant. It is correct, but it is also a bigger change than "four Important
  findings" implies, and the operator should know the window's minimum size changed and why.
- The 993pt populated-deck-strip finding remains open and undecided. It is very likely fine (1144pt
  of room now available), but "very likely fine" is exactly the kind of claim this project's own
  render-harness limitation (documented in fix-round 0) says should get an operator's eyes before
  being trusted, not just arithmetic.
- Both this round's STAGED items (Addition 1's cell-stretch fix, and now the populated-deck-strip
  headroom) should be checked together on the next on-device pass.

---

## Fix round 2 (F3 reopened — VERDICT: OPEN)

Re-review: F1, F2, F4 ADDRESSED and left untouched (confirmed via `git diff` — `SlotBankStripView.swift`
has zero diff this round). F3's *resolution* — not the finding itself — was wrong.

### The core error
`testTheDeckStripsFloorCoversTheirMeasuredNaturalWidth` measured
`deckStripsContent.fixedSize(horizontal: true, vertical: false)`. `.fixedSize(horizontal:)` asks
SwiftUI for a view's IDEAL width; for `Text` with no `lineLimit`, ideal width is the FULL
single-line, UNWRAPPED width. `stripsMinWidth`'s own doc comment claims to be a MINIMUM ("below this
they clip rather than shrink") — roughly a widest-word measurement, hundreds of points smaller. The
815pt (empty)/993pt (populated) figures fix-round-1 measured were almost entirely three explanatory
sentences (`FXChainView`'s FX-empty placeholder ×3, `InstrumentView`'s MASTER caption,
`ShaderControlsView`'s "No shader loaded") measured as if they could never wrap. They all wrap fine
in production; nothing clips at 620pt. Fix-round-1's `minWindowWidth` raise (1180→1390) would also
have broken the app on a 13"/14" MacBook at "Larger Text" scaling — a real hardware regression, not
a cosmetic one.

### What was done
1. **Reverted the four-constant cascade, exactly as directed:** `stripsMinWidth` 830→620,
   `SurfaceLayout.reservedSurfaceWidth` 1082→872, `minWindowWidth` 1390→1180, `knownCellOverflow`
   0→3 (with `testEightCellsFitAtTheMinimumWindowWidthWithNoPanelOpen`'s arithmetic recomputed back
   to the 1180-window numbers: chrome 127, contentColumn 934, cellsRegion 807, needed 810,
   shortfall 3).
2. **Retired** `testTheDeckStripsFloorCoversTheirMeasuredNaturalWidth` rather than retargeting it.
   Considered "render at candidate widths and assert no control is clipped" and rejected it: this
   content has no clip-below-a-floor failure mode to detect in the first place (`Text` wraps,
   `Picker`s compress, `Slider`s shorten — the coordinator's own point, confirmed by re-reading the
   view code) — a retarget would either be vacuous (nothing ever clips) or require inventing a new
   arbitrary usability threshold no more principled than the existing hand-picked 620. Deleted the
   test; `stripsMinWidth`'s doc comment now says plainly it is a hand-chosen usability floor, not a
   measured one, and records the full 815/993 story so nobody re-derives the same wrong number.
   `InstrumentView.deckStripsContent` (widened to internal solely for this test, fix-round-1's F10
   note) is reverted to `private` and merged back into `deckStrips` — its only reason for existing
   is gone with the test, so this is a clean revert, not new cleanup scope.
3. **Preserved the F4 determinism technique** per the instruction not to throw it away with the
   test: documented in the retirement comment that `SurfaceLayout.setExpanded(_:for:)`, called
   explicitly before measuring rather than trusting `Instrument()`'s persisted `UserDefaults` state,
   is the same underlying API `testAnExpandedSectionHasRealHeightAndACollapsedOneIsAbsent` already
   uses for single-section determinism, and remains the pattern for any future test that needs a
   known section-expand arrangement. No new test currently needs it, so nothing new was written —
   the technique lives in that existing test plus the doc-comment record, not orphaned code.
4. **Fixed the dangling doc reference**: `InstrumentSurface.swift`'s `slotCellHeight` comment named
   `testCellSizeIsPinnedRegardlessOfWindowWidth` (removed by F1's rename); repointed to
   `testSlotBankStripCellsRowWidthIsPinnedRegardlessOfWindowWidth`, the test that actually exists.
   Swept both production files for any other now-stale test-name references — none found (the two
   remaining mentions of the old names, in `SurfaceGeometryTests.swift`, are both explicitly framed
   as history — "an earlier version of this comment named X" / "v1 (X, fix-round-1 task 3) gave" —
   not live citations).
5. **Corrected `minWindowWidth`'s doc comment**: it now records that 1390 was tried and rejected,
   names the specific hardware reason (13"/14" MacBook at "Larger Text" scaling; `OutputDestination.floating`'s
   same-screen second window), and tells a future reader to redo the arithmetic from the shipped
   numbers rather than assume 1180 still holds if `stripsMinWidth` is ever legitimately raised.

### Tests
Full suite: **280 tests, 0 failures, 0 skipped** (281 − 1, the retired test; no other count changes).
```
xcodebuild test -project App/TrueISFEditor.xcodeproj -scheme ARShader \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/arshader-ddata-bank \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=YES
```
Three required gates re-run and green: `testTheMonitorStripIsUnmovedByTheSlotStripBelowIt`,
`testTheMonitorStripDoesNotResizeWhenTheStripsBelowItChange`, `testTheMonitorStripStaysPinnedToTheTop`.

### Files changed (fix round 2)
- `App/ARShader/InstrumentSurface.swift` — `stripsMinWidth` reverted to 620 with an honest,
  detailed doc comment; `minWindowWidth` reverted to 1180 with a "tried and rejected" doc comment;
  dangling test-name reference fixed.
- `App/ARShader/SurfaceLayout.swift` — `reservedSurfaceWidth` reverted to 872.
- `App/ARShader/InstrumentView.swift` — `deckStripsContent` merged back into `deckStrips`, reverted
  to `private`; byte-identical in structure to the pre-fix-round-1 version.
- `App/ARShaderTests/SurfaceGeometryTests.swift` — `testTheDeckStripsFloorCoversTheirMeasuredNaturalWidth`
  deleted with a retirement note in its place; `knownCellOverflow` reverted to 3 with recomputed
  doc comment.
- `App/ARShader/SlotBankStripView.swift` — untouched (confirmed via `git diff`, F1/F2/F4 stand as-is).

### Concerns carried forward
- `stripsMinWidth` (620) is now explicitly documented as a JUDGMENT CALL, not a measured value — this
  was already true before fix-round-1 ever touched it (the original 620 was never independently
  measured either), but it is now honest about that instead of implying otherwise. If the deck
  strips ever need a real minimum-width regression gate, it needs a genuinely different technique
  (per-control minimum hit-target size, not ideal text width) — flagged in the doc comment as future
  work, not attempted here.
- The 993pt populated-deck-strip figure from fix-round-1 is now moot — it was itself measured with
  the same wrong (`fixedSize`/ideal-width) technique this round retired, so it should not be treated
  as meaningful evidence of anything. Not restated as a concern going forward.
- `minWindowWidth` is back to 1180, matching what shipped before this task started touching it —
  Addition 1's STAGED cell-stretch fix (unaffected by this round) remains the only open on-device
  confirmation item from this task.
