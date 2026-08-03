# Task 7R report: rows, collapse, resize drag for the slot bank

## Context

Task 7R was implemented by a prior agent that stalled and was killed before it could run its
mutation proofs or commit. I did not re-implement, refactor, or "improve" anything. I read the
uncommitted diff across all eight files, ran the full suite to confirm the starting state, ran the
two mandatory mutation proofs, confirmed the geometry gates and the safety grep, confirmed the
persistence test's existence, and committed.

## Starting state (before any of my changes)

```
xcodebuild test -project App/TrueISFEditor.xcodeproj -scheme ARShader -derivedDataPath /tmp/arshader-ddata-bank ARCHS=arm64 ONLY_ACTIVE_ARCH=YES
```
```
Test Suite 'All tests' passed at 2026-07-31 17:07:55.492.
	 Executed 252 tests, with 0 failures (0 unexpected) in 17.686 (17.737) seconds
** TEST SUCCEEDED **
```

**252 tests, 0 failures** — matches the brief's stated count (up from 243). All three
monitor-geometry gates and both new task-7R behavioural tests passed at this point.

## Mutation proof (a): shrinking rows must never destroy a preset

**Finding: this guarantee is structural, not merely test-covered.** `SurfaceLayout` (in
`App/ARShader/SurfaceLayout.swift`) holds no reference to `SlotBank` anywhere — the only occurrence
of the identifier `SlotBank` in that file is the static constant `SlotBank.maxRows`, used purely to
clamp `bankRows` in `clampedBankRows(_:)`. There is no stored property, no injected dependency, no
method that reaches into `bank.slots`. `setBankRows(_:)` only ever assigns to
`SurfaceLayout.bankRows`, an `Int`.

I confirmed this by grep before attempting any mutation:
```
$ grep -n "SlotBank" App/ARShader/SurfaceLayout.swift
72:    /// Rows of the slot bank DRAWN, never rows stored — see `SlotBank.slotCount`'s doc comment.
262:        min(max(rows, 1), SlotBank.maxRows)
```
Neither line touches the model. There is no code path from `setBankRows` to `SlotBank.slots` for a
mutation to sever — I would have to invent an entirely new dependency (inject a `SlotBank` reference
into `SurfaceLayout` and add a truncation call) to make `testShrinkingRowsHidesPresetsButNeverDestroysThem`
fail, which is not "mutating a guard" but authoring new coupling that doesn't exist. Per the task's
own instruction for this case, I did not fabricate that coupling. The structural proof stands in
place of a behavioural red/green: the model (`SlotBank.slotCount = perRow * maxRows`, a compile-time
constant with no row concept at all, per `App/ARShader/SlotBank.swift`) and the layout (`bankRows`,
a view-only `Int`) are two independent types with no shared mutable state, so there is no execution
path by which a resize could reach a captured preset.

## Mutation proof (b): show mode must not collapse the bank

Reachable and executed as a genuine red/green cycle.

**Mutation applied** (`App/ARShader/SurfaceLayout.swift`):
1. Added `case slotBank` to `enum SectionKey` and appended `.slotBank` to `SectionKey.all`.
2. In `toggleShowMode()`'s entering branch, inside `for key in SectionKey.all { expanded[key] = false }`,
   added `if key == .slotBank { isBankCollapsed = true }`.

**Result — ran `SurfaceLayoutTests` only:**
```
Test Case '-[ARShaderTests.SurfaceLayoutTests testShowModeCannotCollapseTheBank]' started.
.../SurfaceLayoutTests.swift:257: error: -[ARShaderTests.SurfaceLayoutTests testShowModeCannotCollapseTheBank] : XCTAssertFalse failed - Firing slots is performance; show mode collapses configuration only
Test Case '-[ARShaderTests.SurfaceLayoutTests testShowModeCannotCollapseTheBank]' failed (0.001 seconds).
```
**The named test went RED exactly as expected.** Three collateral failures also appeared in the same
run — `testResizingOrCollapsingTheBankDuringAShowSurvivesExitingIt`,
`testShowModeRoundTripWithNoEditRestoresEverything`, and
`testTheCollapsibleSetIsExactlyTheConfigurationSections` — all expected side effects of adding a case
to `SectionKey.all` (an exact-membership assertion) and of `isBankCollapsed` becoming true on show-mode
entry. 4 failures, 17 passes, 21 total in that suite.

**Restored** both edits verbatim (removed `case slotBank`, its `.all` entry, and the `if key ==
.slotBank` line). Confirmed via `git diff App/ARShader/SurfaceLayout.swift`: no residue, diff
identical to the pre-mutation uncommitted diff (95 changed lines, unchanged from the original count).

**Result — full suite, foreground, post-restore:**
```
Test Suite 'All tests' passed at 2026-07-31 17:09:34.522.
	 Executed 252 tests, with 0 failures (0 unexpected) in 17.419 (17.471) seconds
** TEST SUCCEEDED **
```
**252/252, 0 failures — GREEN**, confirming the restore was exact.

## Monitor-geometry gates (final green run)

| Test | Result |
|---|---|
| `testTheMonitorStripDoesNotResizeWhenTheStripsBelowItChange` | **PASS** |
| `testTheMonitorStripStaysPinnedToTheTop` | **PASS** |
| `testTheMonitorStripIsUnmovedByTheSlotStripBelowIt` | **PASS** |

Confirmed by name in both the pre-mutation baseline run and the final post-restore run (neither test
lives in a file this task's mutation touched).

## Safety grep (capture call sites)

```
$ grep -n "\.capture(" App/ARShader/*.swift
App/ARShader/SlotBankStripView.swift:226:        bank.capture(preset, into: index)
```
Exactly one call site, inside view code (`SlotBankStripView.capture(into:)`). `SlotCell` itself is
untouched by task 7R (only its container's row/column wiring changed), so the same explicit gestures
(empty-cell tap, context-menu Replace, ⌥-click) are the only paths to it.

## Persistence trap: closed, with a test

`Arrangement` has an explicit `init(from:)` (not synthesized) using `decodeIfPresent` for the two
new fields (`bankRows`, `isBankCollapsed`), falling back to `1` and `false` respectively —
`App/ARShader/SurfaceLayout.swift` lines ~98–110.

A test exists and does exactly what was asked:
`testAnArrangementSavedBeforeThisTaskStillDecodes` (`App/ARShaderTests/SurfaceLayoutTests.swift`)
decodes hand-built JSON containing only the three original keys (`openPanel`, `expanded`,
`panelWidth`), and asserts:
- `decoded.openPanel == .settings` (original value survives)
- `decoded.panelWidth == 331` (original value survives)
- `decoded.expanded.isEmpty` (original, empty, value survives)
- `decoded.bankRows == 1` (new field takes its default)
- `decoded.isBankCollapsed == false` (new field takes its default)

This test passed in both the baseline run and the final post-restore run. No new test was written by
me; per instruction I only report that it exists.

## Commit

Staged all eight files by explicit path (no `git add -A`) and committed:

```
git add App/ARShader/InstrumentSurface.swift App/ARShader/InstrumentView.swift \
        App/ARShader/SlotBank.swift App/ARShader/SlotBankStripView.swift \
        App/ARShader/SurfaceLayout.swift App/ARShaderTests/SlotBankTests.swift \
        App/ARShaderTests/SurfaceGeometryTests.swift App/ARShaderTests/SurfaceLayoutTests.swift
```

See commit SHA in the final report-back message.

## Concerns / notes

1. No defect found in the implementation itself — every claim in the brief checked out against
   source, and both mutation proofs behaved exactly as predicted (including the "structural, not
   behavioural" escape hatch for proof (a), which the brief anticipated correctly).
2. `SlotBankStripView`'s `rowResizeHandle` drag arithmetic (`slotStripRowHeight = 34`) is a feel
   constant, not asserted by any test — consistent with the prior agent's own doc comment calling
   this a feel issue rather than a correctness one. Not a defect, just carried forward as a known
   live-smoke item (same category task 6R already flagged for cell width).
