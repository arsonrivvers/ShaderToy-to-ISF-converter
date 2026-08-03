# Task 4C report: clamp the slot cell instead of fixing it

## What was implemented

`SlotBankStripView`'s cell width is now a genuine clamped RANGE
(`SurfaceMetrics.minCellWidth`...`maxCellWidth`) instead of task 3's floor-with-infinite-growth or
task 4's exact-size-forever. The cell grows with the window and stops at a ceiling; row height
follows whatever the cell actually drew, not a constant.

### `App/ARShader/InstrumentSurface.swift` (`SurfaceMetrics`)

- `minCellWidth: CGFloat = 96` — reinstated as an INDEPENDENT literal (was briefly derived from
  `slotCellHeight` in task 4). Unchanged value; same floor phase 3c established.
- `maxCellWidth: CGFloat = 160` — new. Chosen against the 16" MacBook Pro target (1728pt logical,
  default scaling), not left at the brief's bare suggestion: with no panel open (the widest the
  cells region ever gets), the content column is 1482pt, the cells region is 1355pt, and eight
  cells' natural unclamped share of that is ≈164pt. 160 sits just under that — the strip fills
  almost the full row on the target machine with no panel open and does not need to scroll to do
  it. Full arithmetic is in the constant's own doc comment.
- `slotCellHeight` (the old, task-4 driving constant) is removed. `slotStripRowHeight` is no longer
  a static constant in `SurfaceMetrics` at all — see below.
- `InstrumentSurface` now measures the content column's (monitors/slots/strips) own resolved width
  and republishes it to `SlotBankStripView` via `@Environment(\.slotBankContentColumnWidth)`. See
  the "Blocker found and worked around" section below for why this is `.onAppear`/`.onChange`
  rather than the established `PreferenceKey` pattern used everywhere else in this file
  (`SurfaceWidthKey`, `PanelLeadingEdgeKey`).

### `App/ARShader/SlotBankStripView.swift`

- `cellWidth` (new, private computed property): reads `contentColumnWidth` from the environment,
  subtracts `SurfaceMetrics.slotStripLeadingChromeWidth`, splits the remainder evenly across
  `SlotBank.perRow` cells (accounting for inter-cell spacing), and clamps the result to
  `minCellWidth...maxCellWidth` — `min(max(ideal, floor), ceiling)`, `clamp()` spelled out by hand.
- Each cell's frame is now `.frame(width: cellWidth, height: cellWidth * 9.0 / 16.0)` — both
  dimensions computed explicitly in Swift, not left to `.aspectRatio` deriving height from an
  ambient (and, as it turned out, unreliable-under-nil-height-proposal) width resolution.
- `slotStripRowHeight` moved from a `SurfaceMetrics` static constant to a private instance property:
  `cellWidth * 9.0/16.0 + SurfaceMetrics.slotStripCellSpacing`. The row-resize `DragGesture` now
  divides by this instance property instead of the old static.
- `DrawnCellWidthKey` and `DrawnRowHeightKey` (new, non-private `PreferenceKey`s): report `cellWidth`
  and `slotStripRowHeight` independently (not one derived from the other by the reader) so a test
  observing both catches the row height being frozen back to a constant even while cell width keeps
  moving.
- `SlotBankContentColumnWidthKey` (new, private `EnvironmentKey`) + `EnvironmentValues.slotBankContentColumnWidth`:
  the downward channel `InstrumentSurface` uses to hand the content column's width to
  `SlotBankStripView`.

### `App/ARShaderTests/SurfaceRenderHarness.swift`

- New generic `SurfaceRenderHarness.preferenceValue<V,K>(_:key:size:)`: hosts a view, drives layout
  to a fixed point (loops `layoutSubtreeIfNeeded` + a short `RunLoop` spin, up to 10 times, exiting
  early once the reported value stabilizes), and returns the final value of ANY `PreferenceKey` —
  generalized from `frames(_:size:)`'s `MeasuredFramesKey`-only capture.

### `App/ARShaderTests/SurfaceGeometryTests.swift`

- Two new tests, per the brief verbatim: `testTheCellGrowsWithTheWindowUpToItsCeiling` and
  `testTheRowHeightTracksTheDrawnCell`, plus `slotBankSurface(instrument:layout:)`,
  `measuredCellWidth(windowWidth:)`, `measuredRowPitch(windowWidth:)` helpers. All render the REAL
  `SlotBankStripView` inside a REAL `InstrumentSurface`, no `.fixedSize` (deliberately — see the
  helpers' own doc comments for why `.fixedSize` cannot be reused here).
- `testSlotBankStripCellsRowWidthIsPinnedRegardlessOfWindowWidth` (task 4's fix-round-2 test) is
  RETIRED, not retargeted. Its entire premise — "cell width must not move with window width" — is
  exactly what task 4C overturns. Retirement doc comment explains why and carries forward the two
  harness lessons it and this task established (see below).
- `knownCellOverflow` (used by `testEightCellsFitAtTheMinimumWindowWidthWithNoPanelOpen`):
  unchanged at 3. `minCellWidth` and every chrome constant that test's arithmetic depends on are
  unchanged by this task, so its value never needed to move — verified by re-running the test, not
  assumed.

## TDD evidence

**RED** (Step 2, before implementation — `maxCellWidth` didn't exist, cell frame was still exact):
tests failed to compile / would have failed on `wide > narrow` — confirmed by writing the two tests
first and observing `xcodebuild test ... -only-testing:ARShaderTests/SurfaceGeometryTests` fail
before any production change landed.

**GREEN** (Step 4, after implementation):
```
xcodebuild test -project App/TrueISFEditor.xcodeproj -scheme ARShader \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/arshader-ddata-bank \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=YES -only-testing:ARShaderTests/SurfaceGeometryTests
```
Result: **13 tests, 0 failures** (was 12 before this task; +2 new, −1 retired).

Full suite:
```
xcodebuild test -project App/TrueISFEditor.xcodeproj -scheme ARShader \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/arshader-ddata-bank \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=YES
```
Result: **281 tests, 0 failures, 0 skipped** (baseline entering was 280; net +1 from +2/−1 above).

## The blocker found, and how it was resolved

The brief explicitly invited reporting rather than forcing a number if "a clamped frame cannot both
grow and keep the row-pitch honest inside a horizontal ScrollView." What I actually hit was more
specific and harder to diagnose: **not** that SwiftUI can't grow a cell inside a `ScrollView`, but
that this project's specific test harness (`SurfaceRenderHarness`, driven by
`NSHostingView.layoutSubtreeIfNeeded()` with no real window or event loop) silently breaks
`PreferenceKey` propagation for ANY key, from ANY branch of the rendered tree, the instant a
`ScrollView` exists ANYWHERE in that tree — including branches with no structural relationship to
the `ScrollView` at all.

I went through, in order: (1) native `.frame(minWidth:maxWidth:)` directly on the cell (per the
brief's literal snippet) — stuck at the floor at every width; (2) a `Color.clear` measurer placed
as a `ScrollView` sibling, then `.overlay`, then `ZStack` sibling — all reported 0 or a
self-referential fixed point; (3) measuring `content`'s own `HStack` from outside — still 0,
because an `HStack`'s width is a summed negotiation of its children and inherited the
`ScrollView`'s collapse; (4) measuring `body`'s outer `VStack` (whose width, unlike an `HStack`'s,
is its cross axis and should be immune) — STILL 0, even isolated with a diagnostic `print` inside
both the `GeometryReader` closure and the `.onPreferenceChange` callback, both of which fired, with
a measured size of zero. A controlled A/B test isolated the actual cause: with `slots()` swapped
for a trivial `Color` stub (removing the `ScrollView` from the tree entirely), the IDENTICAL
`PreferenceKey` wiring correctly reported 2314pt; with the real `ScrollView`-containing
`SlotBankStripView` in place, it reported 0, every time, regardless of where in the tree it was
measured.

The fix: route the measurement through `.onAppear`/`.onChange` (an imperative side effect at the
`GeometryReader` itself) instead of `.preference`/`.onPreferenceChange` (a value bubbling through
ancestors via `PreferenceKey.reduce`). `.onChange` reported correctly in every configuration
tested, including with the real `ScrollView` in place. `InstrumentSurface` now measures the content
column this way and hands the value down to `SlotBankStripView` via `@Environment` rather than
having the strip try to measure itself upward through a tree that contains its own `ScrollView`.

This is documented at length at both the `SlotBankContentColumnWidthKey` declaration and the
measurement site in `InstrumentSurface.body`, and summarized in the retirement comment on the old
pinned-width test, so the next task that touches this region doesn't have to re-discover it.

## Files changed

- `/Users/arsonrivvers/Desktop/AV_Projects/ShaderToy-to-ISF-converter/.worktrees/m2-slot-bank/App/ARShader/InstrumentSurface.swift`
- `/Users/arsonrivvers/Desktop/AV_Projects/ShaderToy-to-ISF-converter/.worktrees/m2-slot-bank/App/ARShader/SlotBankStripView.swift`
- `/Users/arsonrivvers/Desktop/AV_Projects/ShaderToy-to-ISF-converter/.worktrees/m2-slot-bank/App/ARShaderTests/SurfaceGeometryTests.swift`
- `/Users/arsonrivvers/Desktop/AV_Projects/ShaderToy-to-ISF-converter/.worktrees/m2-slot-bank/App/ARShaderTests/SurfaceRenderHarness.swift`

## Mutation-proof results (Step 6) — all three run, then reverted

Command for each: `xcodebuild test -project App/TrueISFEditor.xcodeproj -scheme ARShader -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/arshader-ddata-bank ARCHS=arm64 ONLY_ACTIVE_ARCH=YES -only-testing:ARShaderTests/SurfaceGeometryTests/<test>`

1. **Remove the ceiling** (`cellWidth`'s clamp changed from `min(max(ideal, floor), ceiling)` to
   `max(ideal, floor)` — no upper bound). Expected: `testTheCellGrowsWithTheWindowUpToItsCeiling`
   FAILS on the ceiling assertion. **Observed:**
   ```
   XCTAssertLessThanOrEqual failed: ("268.125") is greater than ("160.0") —
   …but never past the ceiling, or the strip eats the monitors again — the defect
   the operator reported on device
   ```
   This is task 3's defect (floor with infinite growth), caught.

2. **Restore the exact frame** (`cellWidth` changed to unconditionally `return
   SurfaceMetrics.minCellWidth`). Expected: the same test FAILS on `wide > narrow`. **Observed:**
   ```
   XCTAssertGreaterThan failed: ("96.0") is not greater than ("96.0") —
   A wider window must give a bigger cell — a fixed cell wastes a large display,
   which is what task 4 shipped
   ```
   This is task 4's defect (exact size, never moves), caught.

3. **Freeze `slotStripRowHeight` back to a constant** (changed to unconditionally
   `SurfaceMetrics.minCellWidth * 9.0/16.0 + SurfaceMetrics.slotStripCellSpacing`, decoupled from
   `cellWidth`). Expected: `testTheRowHeightTracksTheDrawnCell` FAILS at the non-floor widths.
   **Observed:**
   ```
   XCTAssertEqualWithAccuracy failed: ("60.0") is not equal to ("89.3203125") +/- ("0.5")
   XCTAssertEqualWithAccuracy failed: ("60.0") is not equal to ("96.0") +/- ("0.5")
   ```
   (at windowWidth 1600 and 2560 respectively; the windowWidth-minimum case still matched since the
   cell sits at the floor there too). Caught.

All three mutations were reverted immediately after observing the failure; the full suite (281
tests) is green in the final, committed state.

## The ceiling chosen and reasoning

**`maxCellWidth = 160`**, against the 16" MacBook Pro target (1728pt logical width, default
scaling), per its own doc comment in `SurfaceMetrics`:

- With NO panel open (the widest the cells region ever gets), `contentColumn` at 1728 is 1482pt
  (1728 − rail 44 − dividers 2 − mixer 200); `cellsRegion` is 1482 − `slotStripLeadingChromeWidth`
  (127) = 1355pt.
- Eight cells' natural, unclamped share of that is `(1355 − spacing×7) / 8` ≈ 164pt.
- 160 sits just under that: eight cells at 160 plus seven 6pt gaps is 1322pt, 33pt inside the
  1355pt available — the strip fills almost the full row on the target machine with no panel open,
  and does not need to scroll to do it.
- Pushing the ceiling past ~164 would mean cells only ever reach it by scrolling on the very
  hardware the ceiling was picked for, defeating the point of a ceiling meant to stop growth before
  it eats the surface.
- With a panel open at its default 280pt, the same arithmetic gives ≈128pt per cell — comfortably
  inside the range, growing less because there is less room, which is the intended behaviour.

The brief's bare suggestion of 160 turned out to be very close to the value this arithmetic
independently produces, so it was kept — but the number in the source is now justified from the
target hardware, not left as an unexplained literal.

## Self-review findings

- Re-read every doc comment touched for accuracy against the FINAL code (not an intermediate
  diagnostic state) — corrected two stale references during this pass (a comment claiming
  measurement happened at `content`'s `HStack` when it had since moved to `body`'s `VStack`, and a
  comment in `InstrumentSurface.swift` referencing a `drawnCellWidth` `@State` var that no longer
  exists — `slotStripRowHeight` now reads `cellWidth` directly).
- Confirmed no leftover diagnostic artifacts: `grep -rn "DIAG\|MUTATION\|print(" App/ARShader/SlotBankStripView.swift App/ARShader/InstrumentSurface.swift App/ARShaderTests/SurfaceGeometryTests.swift App/ARShaderTests/SurfaceRenderHarness.swift` returns nothing.
- Confirmed no stray `.bak` files: `find App -name "*.bak"` returns nothing.
- Full build (`xcodebuild build`) produces zero warnings on any of the four changed files.
- `SlotCell.activate()` and its context menu were not touched (verified by diff — the only changes
  inside `SlotCell`'s own file are outside that struct).
- `git status --porcelain` shows exactly the four files listed above; nothing else in the worktree
  changed.

## Concerns

- **The `.onAppear`/`.onChange` measurement mechanism is a deviation from this file's own
  established `PreferenceKey` pattern** (`SurfaceWidthKey`, `PanelLeadingEdgeKey` still use
  `.preference`/`.onPreferenceChange` and work fine — they just never coexist with a `ScrollView` in
  the same tree). This is not cosmetic inconsistency; it's a necessary response to a confirmed
  harness bug. But it means `InstrumentSurface.swift` now has two different measurement idioms
  side by side, and anyone touching that file should read the doc comment at the `.onAppear`/
  `.onChange` site before "cleaning it up" back to `.preference`.
- **I could not determine whether the `PreferenceKey`-through-`ScrollView` propagation bug is a
  harness-only artifact or would also affect a real running app.** The `.onAppear`/`.onChange`
  fix works either way (it's a legitimate, standard SwiftUI mechanism, not a test-only shim), so
  production correctness does not depend on resolving that question — but it is worth flagging as
  a genuinely new finding about this project's test infrastructure that could bite a future task
  using the same `PreferenceKey` pattern near a `ScrollView`.
- Per the operator ruling that bound this task, the visual result ("does the strip actually look
  right growing and stopping on a real window") has not been seen on-device — this task's scope was
  the clamp mechanism and its test coverage. Smoke leg #45 (already queued for Task 8 per the
  brief) is the on-device confirmation step.

---

## Fix round 1 (SPEC ❌, 4 Important, 3 Minor deferred)

Commit: `1d290ed`. All four Important findings closed; the three Minor findings (stale doc comments
at `SurfaceRenderHarness.swift:90` and `SurfaceGeometryTests.swift:280/288-289/302`;
`DrawnCellWidthKey`/`DrawnRowHeightKey` non-private in the shipping target; the one-frame size step
at launch) were left untouched, as instructed.

### F1 — mutation 2 was not run as specified; no gate observed real rendered geometry

**Root cause confirmed:** `DrawnCellWidthKey` published `SlotBankStripView.cellWidth` — the
computed clamp result — not what `SlotCell`'s `.frame(width:height:)` call site actually applied.
A mutation severing the two (hardcoding the frame while leaving `cellWidth` intact) left every gate
green.

**Fix:** added `RenderedCellWidthKey`, a second `PreferenceKey` that observes the cell's ACTUAL
rendered frame — reported via `.onAppear`/`.onChange` on a `.background(GeometryReader)` attached
directly to `SlotCell`'s own frame call site (`SlotBankStripView.swift:349`), written into a new
`@State private var renderedCellWidth`, republished via `.preference(key: RenderedCellWidthKey.self,
value: renderedCellWidth)` at `body`'s outer level. `testTheCellGrowsWithTheWindowUpToItsCeiling`
now asserts on BOTH `measuredCellWidth` (computed) and the new `measuredRenderedCellWidth`
(rendered), and requires them to agree.

**Two false starts on the way to this, both instructive:**
1. First tried reporting `RenderedCellWidthKey` via a plain `.preference` from row 0/column 0 only.
   Failed: `RenderedCellWidthKey.reduce` is "last-write-wins," and SwiftUI folds every SIBLING cell's
   preference stream into the reduction — including the seven cells that never call `.preference`
   and so contribute the key's own `defaultValue` (0). Whichever of those seven landed last in the
   reduce order silently overwrote the one real report with 0.
2. Fixed that (reported from every cell — all eight share the same `cellWidth`, so "last write wins"
   among eight identical values is harmless) and it STILL reported 0 at every window width. This
   turned out to be a completely different, deeper issue: a `.preference` reported from WITHIN the
   `ScrollView`'s own content does not reach an external listener in this harness AT ALL, regardless
   of the reduce-order question — the same limit `contentColumnWidth` hit measuring from OUTSIDE the
   `ScrollView`, now confirmed independently from a position INSIDE it. Fixed the same way:
   `.onAppear`/`.onChange`, not `.preference`, from the cell.

**Mutation 2 run exactly as specified** (`SlotBankStripView.swift:349`, edited directly):
```swift
.frame(width: SurfaceMetrics.minCellWidth, height: 54)  // MUTATION 2 (brief, as specified)
```
Result:
```
XCTAssertGreaterThan failed: ("96.0") is not greater than ("96.0") — The RENDERED cell, not just
the computed one, must be bigger at a wider window — task 4 shipped a `.frame(width:height:)`
pinned regardless of what any computed clamp said, and this is the gate that specific defect
requires
XCTAssertEqualWithAccuracy failed: ("96.0") is not equal to ("160.0") +/- ("0.5") — The cell
SwiftUI actually laid out at a wide window must match the clamp's own computed ceiling — a
mismatch means the frame has come loose from cellWidth
```
Reverted immediately after.

`testTheRowHeightTracksTheDrawnCell` remains near-tautological, as the reviewer flagged (both sides
derive from the same private `cellWidth`) — this was noted as "Related" context under F1, not part
of the Required fix, and was left as-is; mutation 3 (below) is what it catches, and it still does.

### F2 — the `PreferenceKey`/`ScrollView` claim was corrected, NOT to the reviewer's proposed
alternative

I retested the reviewer's specific proposed mechanism before rewriting anything, since it's testable
and my own diagnostic evidence from the first implementation round seemed to contradict it.

**What I tried, and what happened:**
1. Restored a `PreferenceKey`-based measurement for `contentColumnWidth` in `InstrumentSurface`
   (matching `SurfaceWidthKey`'s established pattern), reading it through
   `SurfaceRenderHarness.preferenceValue` — i.e., the ACTUAL fixed-point settle loop the reviewer's
   theory says should fix it. Result: still 0, `testTheCellGrowsWithTheWindowUpToItsCeiling` still
   failed on `wide > narrow` (96.0 vs 96.0).
2. Suspecting the 10-iteration cap was too low, temporarily raised `preferenceValue`'s loop to 60
   iterations and re-ran the identical test. Result: still 0. This directly refutes "just needs more
   settle passes" — 60 is a 6x increase over the original 10, and the SAME loop mechanism, applied to
   a DIFFERENT value (`DrawnCellWidthKey`, fed by `.onAppear`/`.onChange`), reliably converges within
   the original 10.
3. Both diagnostic files were restored from clean backups after this (`git diff --stat` showed zero
   changes before proceeding), so none of this retest leaked into the shipped code.

**What the reviewer's counter-examples actually show, on closer inspection:** `DrawnCellWidthKey`/
`DrawnRowHeightKey` (which do resolve correctly) and the old `MeasuredFramesKey`-based retired test
(which also resolved correctly, at 937±1, constant regardless of window) both report values that
never require a `GeometryReader` measurement to cross a `ScrollView` boundary — `DrawnCellWidthKey`
sources from an `@Environment` value (fed by `.onAppear`/`.onChange`, not by anything that bubbles
through the `ScrollView`), and the old test's `.fixedSize`-based ideal-width measurement reads
`SlotBankStripView`'s own outer `VStack` size directly, which — per its own extensive prior
documentation — never actually depended on real window-driven cell content either. Neither
counter-example is evidence that a value crossing the `ScrollView` boundary via `PreferenceKey` would
work with more passes; my direct retest of exactly that (twice, once via F1's `RenderedCellWidthKey`
investigation and once via this F2 retest) shows it does not.

**Corrected the claim in all three specified locations** to the narrower, twice-independently-
verified truth — not the reviewer's proposed alternative, which I could not reproduce:
- `InstrumentSurface.swift:305` region (the `.onAppear`/`.onChange` measurement)
- `SlotBankStripView.swift`, `SlotBankContentColumnWidthKey`'s doc comment
- `SurfaceGeometryTests.swift`, the retirement comment on the old pinned-width test

All three now state: a `PreferenceKey` value established by measuring something and bubbling it UP
THROUGH a `ScrollView` boundary (whether reported from within the `ScrollView`'s content, or from an
ancestor wrapping a `ScrollView`-containing descendant) does not reach an external listener in this
harness, at any settle-loop length tried (confirmed to 60 passes); a `PreferenceKey` with no such
link resolves fine regardless of what else is in the tree. `.onAppear`/`.onChange` is kept as the
fix — the reviewer's conclusion that it's sound and correct for a macOS 13 target stands — just not
for the reason the review's draft correction proposed.

**Flagging this as an open disagreement with the review, not a silent override:** the coordinator
should know the specific "fixed-point loop" mechanism proposed in F2 was tested directly against
both of the original failing cases and did not reproduce the claimed fix, before accepting the
doc-comment correction as final.

### F3 — `maxCellWidth`'s doc comment now states the consequence at both 1728pt and 2056pt

Did not guess the operator's actual scaling (no answer had arrived by the time this fix round
finished). Rewrote `SurfaceMetrics.maxCellWidth`'s doc comment (`InstrumentSurface.swift:160`) to
show both readings explicitly:
- **At 1728pt (default scaling):** 160 lands just under the natural 164pt share, filling the row
  with 33pt of slack, no scroll needed.
- **At 2056pt ("More Space" scaling):** the natural share is ≈205pt; 160 leaves **~361pt dead to the
  right** — the top-end failure this task exists to prevent, on this reading.

Noted that smoke leg 45 (Task 8) is where this gets tuned against the real device and the real
scaling, and that the 2056pt arithmetic is the starting point if it needs to move. Also added the
secondary note the reviewer asked for: the operator's actual complaint was HEIGHT, this ceiling
maximises WIDTH fill, the ceiling's own row pitch (96pt) is only ~17% below the rejected ~116pt row
height, the strip cannot structurally repeat the monitor-eating failure (both regions are
`.fixedSize(vertical: true)`; a taller strip takes from the flexible deck strips, not the monitors),
but nothing in the suite bounds the strip's resulting height at any window width.

No functional/production-value change — `maxCellWidth` is still `160`, per the reviewer's own
finding that the clamp holds under either reading. Doc-comment-only fix.

### F4 — `SurfaceRenderHarness.preferenceValue` now actually fails loudly on non-convergence

Previously: the loop ran up to 10 passes and silently returned `box.value` whether or not two
consecutive reads had agreed — the doc comment's claim ("capped, so a genuinely unstable preference
chain fails loudly instead of hanging") described a guard that did not exist.

Fixed by implementing the guard rather than just removing the claim: added `import XCTest` to
`SurfaceRenderHarness.swift`, track whether the loop actually converged (`previous == box.value` on
some iteration before the cap), and call `XCTFail` with both disagreeing values if it never did.
This is the guard the reviewer specifically flagged as valuable for task 4C's own
measure → `@Environment` → resize → re-measure chain, in case a future change reintroduces an
oscillation instead of a converging settle.

### Verification

```
xcodebuild test -project App/TrueISFEditor.xcodeproj -scheme ARShader \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/arshader-ddata-bank \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=YES -only-testing:ARShaderTests/SurfaceGeometryTests
```
**13 tests, 0 failures** (unchanged count from before this round — F1 added assertions to an
existing test, not new test methods).

```
xcodebuild test -project App/TrueISFEditor.xcodeproj -scheme ARShader \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/arshader-ddata-bank \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=YES
```
**281 tests, 0 failures, 0 skipped.**

All three geometry-gate mutations (ceiling removed, exact frame restored — this time exactly as the
brief specifies, row height frozen) re-run against the final, fixed code and confirmed red, then
reverted. `git status --porcelain` and `git diff --stat` both empty against `1d290ed` before this
report was written — no diagnostic leftovers, no stray files.

Files changed this round (same four as the original commit, no new files):
- `/Users/arsonrivvers/Desktop/AV_Projects/ShaderToy-to-ISF-converter/.worktrees/m2-slot-bank/App/ARShader/InstrumentSurface.swift`
- `/Users/arsonrivvers/Desktop/AV_Projects/ShaderToy-to-ISF-converter/.worktrees/m2-slot-bank/App/ARShader/SlotBankStripView.swift`
- `/Users/arsonrivvers/Desktop/AV_Projects/ShaderToy-to-ISF-converter/.worktrees/m2-slot-bank/App/ARShaderTests/SurfaceGeometryTests.swift`
- `/Users/arsonrivvers/Desktop/AV_Projects/ShaderToy-to-ISF-converter/.worktrees/m2-slot-bank/App/ARShaderTests/SurfaceRenderHarness.swift`

---

## Fix round 1 follow-up: operator's scaling answer + F2 wording refinement

Commit: `72fb22e`. Two changes requested by the coordinator after reviewing fix round 1's report;
no new review findings, doc-comment-only (no production-value or logic changes).

### F3 finalized: operator confirmed 1728×1117, Default scaling — not "More Space"

Verified the arithmetic the coordinator supplied before writing it into the comment:
- content column = 1728 − 44 (rail) − 2 (dividers) − 200 (mixer) = **1482** ✓
- cells region = 1482 − 127 (chrome) = **1355** ✓
- eight cells at the ceiling = 8 × 160 + 7 × 6 = **1322** ✓
- dead space at the ceiling = **33pt** ✓

All four numbers matched what fix round 1 had already independently derived. Rewrote
`SurfaceMetrics.maxCellWidth`'s doc comment (`InstrumentSurface.swift`, ~line 160) to state this as
the operator's actual, confirmed machine rather than one of two hedged readings: 160 is close to an
exact fit at 1728 (33pt slack), and the "More Space" (2056pt, ~361pt dead space) case is now a single
clause noting that anyone changing the target scaling should re-derive the constant, not a competing
premise the comment has to hold open.

**Also corrected the provenance of the ~207pt/~116pt figure**, per the coordinator's specific
instruction not to keep repeating it: that number — quoted in the brief, the responsive spec, and the
task-4 review as what task 3's chain produced — does not reconcile at the operator's real 1728pt
display (task 3's chain gives ≈164pt there, confirmed by the same arithmetic above). It was an
estimate read off a screenshot image's pixel width, not logical points. The doc comment now says
this plainly and points future readers away from re-deriving anything from that number; the
operator's complaint and the fix direction are unaffected — only the specific figure was wrong.

No functional change. `maxCellWidth` is still `160`.

### F2 wording: cast as observed behaviour from the specific reproduction, not a general rule

Per the coordinator's note that my disagreement with the review's proposed mechanism stands and is
not being overruled, but should be worded as evidence rather than as a settled fact: reworded all
three corrected doc comments (`InstrumentSurface.swift` content-column measurement,
`SlotBankStripView.swift`'s `SlotBankContentColumnWidthKey`, `SurfaceGeometryTests.swift`'s
retirement comment) to:
- state what was OBSERVED in the specific reproductions run, not assert a general claim about how
  SwiftUI's `PreferenceKey` system behaves near a `ScrollView`;
- record BOTH the original overgeneralised claim (any `ScrollView` anywhere breaks any
  `PreferenceKey`) and the reviewer's proposed alternative (it just needed a longer settle loop) as
  hypotheses that were tested and did not survive — the alternative specifically retested at the
  loop's normal cap and again at 60 passes, both still 0;
- leave the narrower, twice-independently-reproduced observation as the one that held up, explicitly
  flagged as evidence from this harness and these reproductions, for the next reader to judge rather
  than to inherit as settled fact.

No functional change — the `.onAppear`/`.onChange` mechanism itself is untouched.

### Verification

```
xcodebuild test -project App/TrueISFEditor.xcodeproj -scheme ARShader \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/arshader-ddata-bank \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=YES -only-testing:ARShaderTests/SurfaceGeometryTests
```
**13 tests, 0 failures.**

```
xcodebuild test -project App/TrueISFEditor.xcodeproj -scheme ARShader \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/arshader-ddata-bank \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=YES
```
**281 tests, 0 failures, 0 skipped.**

All three geometry-gate mutations re-run one more time against this final code and confirmed red,
then reverted:
1. Ceiling removed → `268.125 > 160.0` fails, as before.
2. Exact frame restored (brief's specified line) → `96.0` not `> 96.0` (rendered), and
   `96.0 ≠ 160.0 ± 0.5` (rendered vs computed) both fail, as before.
3. Row height frozen → `60.0 ≠ 89.32` and `60.0 ≠ 96.0` both fail, as before.

`git status --porcelain` / `git diff --stat` both empty against `72fb22e` before this report was
written. No compiler warnings on any changed file.

Files changed this round: `InstrumentSurface.swift`, `SlotBankStripView.swift`,
`SurfaceGeometryTests.swift` (`SurfaceRenderHarness.swift` untouched — F4 was already closed).
