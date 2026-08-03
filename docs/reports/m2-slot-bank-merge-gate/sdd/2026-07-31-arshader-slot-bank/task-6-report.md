# Task 6 report: `PanelID.bank`

## What changed

- `App/ARShader/SurfaceLayout.swift` — added `case bank` to `PanelID`, plus its `systemImage`
  (`"square.grid.3x3"`) and `title` (`"Bank"`) switch arms. Verified `shortcutNumber` needed no
  change: it derives the digit from `allCases.firstIndex(of: self)`, so `.bank` (index 2) got
  `⌘⌥3` automatically.
- `App/ARShader/SlotBankPanelView.swift` (new) — placeholder view exactly as specified:
  `Text("Bank")`, takes only `instrument`.
- `App/ARShader/InstrumentView.swift` — added `case .bank: SlotBankPanelView(instrument: instrument)`
  to `panelContent`.
- `App/ARShaderTests/SurfaceLayoutTests.swift` — added the two tests from the brief verbatim:
  `testTheBankIsTheThirdRailPanelAndBindsCommandOptionThree`,
  `testOpeningTheBankSwapsRatherThanStacking`.
- `App/ARShaderTests/Baselines/{panel-closed,panel-library,show-mode}.png` — re-recorded. See
  "Cost beyond one enum case" below for why these needed to change at all.

Files searched for exhaustiveness before editing: grepped every reference to `PanelID` in the
tree (4 files total: `PanelRailView.swift`, `SurfaceLayout.swift`, `InstrumentView.swift`,
`SurfaceLayoutTests.swift`). `PanelRailView.swift` iterates `PanelID.allCases` in a `ForEach` and
needed zero changes — exactly the rail's premise. `InstrumentView.swift`'s shortcut `ForEach`
(line 247) also needed zero changes; only its non-exhaustive-by-construction `panelContent`
`switch` needed the new arm, which the brief already specified.

## Full-suite command and verbatim tail

```
xcodebuild test -project App/TrueISFEditor.xcodeproj -scheme ARShader -derivedDataPath /tmp/arshader-ddata-bank ARCHS=arm64 ONLY_ACTIVE_ARCH=YES
```

Final clean run (after re-recording baselines and regenerating the project via `xcodegen
generate`, see below):

```
Test Suite 'SurfaceLayoutTests' passed at 2026-07-31 13:33:20.020.
	 Executed 16 tests, with 0 failures (0 unexpected) in 0.007 (0.010) seconds
Test Suite 'ARShaderTests.xctest' passed at 2026-07-31 13:33:20.020.
	 Executed 243 tests, with 0 failures (0 unexpected) in 18.287 (18.338) seconds
Test Suite 'All tests' passed at 2026-07-31 13:33:20.020.
	 Executed 243 tests, with 0 failures (0 unexpected) in 18.287 (18.339) seconds
...
** TEST SUCCEEDED **
```

241 → 243, exactly the two new tests. All previously-passing suites (including
`SurfaceLayoutTests`' own `testEachPanelsShortcutDigitMatchesItsPositionInTheRail` and
`testPanelsPastTheNinthHaveNoShortcutRatherThanACrashingOne`, both of which iterate
`PanelID.allCases`) stayed green with zero edits, because they're already written generically
against the case count rather than hardcoded to 2.

## Did adding the case cost exactly one enum case plus a view, or more?

**More — two real costs surfaced, one genuine and one a red herring worth flagging.**

**1. Genuine cost: the three PNG baseline tests broke, and this is not incidental.**
`SurfaceGeometryTests.testSurfaceBaselines` renders the *whole* `InstrumentSurface` (rail
included) to a PNG and byte-compares it against a committed baseline for three states
(panel-closed, panel-library, show-mode). None of the three states opens Bank — but the rail
itself, which is always visible and iterates `PanelID.allCases`, gained a new icon. That changed
the rendered pixels in all three baselines, so all three failed with "differs from its baseline."

I did not take this on faith — the harness's own doc comment warns that these baselines are
"machine-specific... NOT the load-bearing gate" and can go red together from a display-scale or
OS-point-release drift unrelated to the code change. So I isolated it: reverted
`SurfaceLayout.swift`/`InstrumentView.swift`/`SurfaceLayoutTests.swift` to `HEAD` (2-case rail) in
place and re-ran just `testSurfaceBaselines` — it passed cleanly on this same machine, same
session. Restored my 3-case changes, it failed again. That rules out environment drift and
confirms causation: **adding a rail panel invalidates every full-surface baseline PNG, every
time, regardless of whether the new panel is ever opened in the baselined states.** Re-recorded
via the documented `RECORD` sentinel procedure (created it, ran once — got the expected
sentinel-consumed failure — then ran the full suite clean). This is a real, structural cost of
"one more `PanelID` case" that the phase 3a claim doesn't mention: any visual regression suite
that renders the rail must be touched, and touching it means re-recording under manual git-diff
review (I inspected the diff stat — three PNGs changed size by ~2KB each, consistent with one
added glyph, nothing structurally alarming, but I did not pixel-diff them beyond that).

**2. Red herring, but worth recording so it isn't re-discovered the hard way: the on-disk
`.xcodeproj` was stale relative to `App/project.yml` and needed manual repair to compile at
all** — my first `xcodebuild test` run failed with "Cannot find 'SlotBankPanelView' in scope"
because the new file wasn't in the checked-out `project.pbxproj`. I initially hand-patched the
pbxproj (new `PBXFileReference` + two `PBXBuildFile` entries + group + two Sources-phase
entries) to unblock the run. That worked, but it was the wrong fix: `App/TrueISFEditor.xcodeproj`
is entirely gitignored (`git add` refused it — "ignored by one of your .gitignore files") and is
generated by XcodeGen from `App/project.yml`, whose `ARShader`/`ARShaderTests` targets both
declare `sources: [path: ARShader]` — a **folder glob**, not an explicit file list. I ran
`xcodegen generate` in `App/` and it picked up `SlotBankPanelView.swift` automatically (6
references to the file in the regenerated `project.pbxproj`, matching `SettingsPanelView.swift`'s
count) with **zero `project.yml` changes**. Re-ran the full suite against the freshly-generated
project and it was still 243/243 green. So the project-file side of the claim holds exactly as
advertised — my manual pbxproj surgery was an unnecessary workaround for this worktree's stale
generated artifact, not a real cost of the change. Flagging it because a future task in this
same worktree could hit the identical "cannot find X in scope" symptom and should reach for
`xcodegen generate`, not manual pbxproj editing.

## Commit

`b323817` — `feat(3b): the bank is the third rail panel — one enum case, as advertised`

7 files changed: `App/ARShader/InstrumentView.swift`, `App/ARShader/SlotBankPanelView.swift` (new),
`App/ARShader/SurfaceLayout.swift`, the three `App/ARShaderTests/Baselines/*.png`, and
`App/ARShaderTests/SurfaceLayoutTests.swift`. `App/TrueISFEditor.xcodeproj` was correctly excluded
from the commit (gitignored, generated).

## Concerns for whoever picks this up next (Task 7 and beyond)

- **Every future `PanelID` case will re-break the three baseline PNGs**, for the same structural
  reason (rail is always rendered, glyph count changes pixel output). This isn't a bug to fix in
  Task 6 — the baseline mechanism is explicitly documented as supplementary/re-recordable — but
  whoever writes Task 7 (and any later rail addition) should expect the same `RECORD`-sentinel
  dance and budget for it, rather than being surprised.
- **This worktree's checked-out `.xcodeproj` may still drift from `project.yml`** on other
  branches/worktrees sharing this repo, since it's gitignored and machine-local. If a future task
  in a different worktree hits "cannot find X in scope" for a file that clearly exists on disk in
  a glob-covered directory, the fix is `xcodegen generate` in `App/`, not manual pbxproj edits.
- No concerns about the logic change itself — `PanelID.bank`, its two switch arms, the
  `panelContent` case, and the placeholder view are exactly per brief, and every pre-existing test
  that iterates `PanelID.allCases` passed with zero modification, which is the actual core claim
  being tested and the part that held cleanly.
