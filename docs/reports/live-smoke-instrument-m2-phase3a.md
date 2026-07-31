# Live smoke — ARShader Milestone 2, phase 3a (panel framework)

**Status: CONFIRMED — all 17 legs run and signed on device by the operator, 2026-07-31.**

Phase 3a builds the panel framework: a two-icon rail (Library/Settings), a draggable panel that
opens/closes/swaps, per-section collapse on both decks and MASTER FX with a monitor strip that
holds still while they collapse, show mode, and the `⌘⇧P` collapse-everything shortcut. Automated suites are
green, and the legs below have now been run on device by the operator, per the on-device gate in
`CLAUDE.personal.md`.

- **Build under test:** `~/Applications/ARShader.app`, installed 2026-07-31 09:56. `ARShader.debug.dylib`
  verified byte-identical (sha256 `fb33e28d…`) to the `/tmp/arshader-ddata-panel` build product, which
  was produced two seconds after the `9688e9d` commit. Under Xcode 26 the real code is in the
  `.debug.dylib`, not the 58KB `Contents/MacOS/ARShader` stub.
- **Automated gates:**
  - ARShaderTests: **199 tests, 0 failures** (expected 199 — match)
  - TrueISFEditorTests: **514 tests, 3 skipped, 0 failures** (expected 514 (3 skipped) — match)
  - ShadertoyISFKitTests: **312 tests, 0 failures** (expected 312 — match)
- **Operator:** Conner — ran every leg on device, two displays attached (laptop + external)
- **Date:** 2026-07-31
- **Branch:** `m2-panel-framework`, commit `9688e9d` (suite counts recorded at `310d397`; the three
  commits since are the freshness-check fix, the §2.1 reversal and the top-align, all of which left
  the 199/514/312 counts unchanged)
- **Result:** **CONFIRMED. 17 of 17 legs pass, 0 defects found.**

## Legs

State each hypothesis so it can fail. A leg is only CONFIRMED when the operator saw it.

| # | Leg | Hypothesis | Result |
|---|---|---|---|
| 1 | Rail toggle | Rail shows two icons; clicking Library opens the panel, clicking it again closes it entirely | ✅ PASS |
| 2 | Panel swap | Clicking Settings while Library is open swaps without closing | ✅ PASS |
| 3 | Keyboard open/swap | `⌘⌥1` and `⌘⌥2` do the same as clicking | ✅ PASS |
| 4 | Panel resize | Dragging the panel edge resizes it; it does not go below 260pt | ✅ PASS |
| 5 | Independent collapse | Each of SOURCES, FX, PARAMETERS collapses and expands on both decks independently | ✅ PASS |
| 6 | Collapsed summary | A collapsed header still shows its count/summary | ✅ PASS |
| 7 | Monitors hold still | **The monitor strip does not resize and does not slide when sections collapse or expand, or when the panel opens.** Collapsing buys less scrolling in the strips below, not a bigger picture. (Reversed from "monitors grow" at `e208776` on operator feedback — *"the windows jump around and it's confusing"*.) | ✅ PASS |
| 7b | Deck columns top-align | The deck columns sit flush to the top of their region rather than floating centred; collapsing a section shortens the column downward | ✅ PASS |
| 8 | MASTER FX collapse | MASTER FX collapses; its stage count stays visible collapsed | ✅ PASS |
| 9 | Collapse-all shortcut | `⌘⇧P` collapses everything and closes the panel; `⌘⇧P` again restores it exactly | ✅ PASS |
| 10 | Show-mode edit escape | In show mode, expanding DECK A's FX leaves show mode and keeps FX open; the rest stay collapsed | ✅ PASS |
| 11 | Blackout still wins | `⌘B` latches blackout with a panel open, and in show mode. Hold Escape still works | ✅ PASS |
| 12 | Output window toggle | `⌘⇧F` still toggles the output window | ✅ PASS |
| 13 | Mixer strip controls | OUTPUT RES is in Settings and still works. PREVIEW SCALE, CUE SCALE and the OUTPUT destination picker are all still on the mixer strip and still work | ✅ PASS |
| 14 | Arrangement persists | Quit and relaunch: the arrangement is exactly as left | ✅ PASS |
| 14b | Shortcuts fire with field focus | `⌘⇧P` and `⌘⌥1` fire while a text field has focus. Click into the library search field, then the OUTPUT RES width field, and press each shortcut. Blackout uses an app-wide NSEvent monitor precisely because SwiftUI shortcuts are focus-dependent; these new ones do NOT, so this is reasoned-but-unverified until run. If either fails to fire with focus in a field, that is a real defect on stage, not a nicety | ✅ PASS |
| 15 | Generator hides SOURCES | A generator on a deck shows no SOURCES section at all (not an empty one) | ✅ PASS |

## Notes

- The three regression suites were run in the foreground at `310d397` and their verbatim tail
  output recorded. The install and the binary-freshness check were performed separately, before the
  legs: the installed `ARShader.debug.dylib` is byte-identical to the build product.
- **17 of 17 legs pass. No defect was found.** Phase 3a is CONFIRMED.
- **Three fixes landed AFTER these legs ran and are not covered by them** (`47e9091`, from the final
  branch review). The legs were run against `f966779`. Two of the three change behaviour the legs
  touched, so the honest status is: the phase is CONFIRMED, these three fixes are STAGED.
  - The panel now has a width CEILING as well as a floor, clamped against the window. Leg 4 checked
    only the floor. The defect: dragging the handle right past the window edge made the panel wider
    than the window, putting the mixer strip — and BLACKOUT, SHOW MODE and the OUTPUT picker with
    it — off-screen, unrecoverable by mouse and persisted across relaunch.
  - The window's minimum width went 1100 → 1180. At 1100 with a panel open the mixer strip was
    drawn 52pt outside the window. No leg resized the window, which is why 17/17 missed it.
  - `⌘⌥N` bindings and rail tooltips now share one source. No behaviour change at two panels.
  - **Re-smoke needed, three legs:** drag the panel handle far right past the window edge and
    release (the mixer strip must stay fully visible and the handle must stay grabbable); resize the
    window down to its minimum with a panel open (nothing clipped on the right); and confirm the
    panel width you chose survives shrinking and re-growing the window.
- **Leg 7 was corrected before the run, not during it.** The report was written at `310d397`, one
  commit before `e208776` reversed §2.1, so leg 7 still read *"the monitors visibly grow as sections
  collapse. (The whole point.)"* — the behaviour the reversal deliberately removed. Running it as
  written would have failed the build for doing the right thing. It now reads "monitors hold still",
  matching the two gates that replaced the old one. Leg 7b was added for the top-align at `9688e9d`,
  which landed after the report and had no leg at all.
- **One false alarm, caused by this report's own notation.** The operator initially read `⌘⌥1` as
  command-1 and `⌘⇧F` as command-F, got the system beep that any unbound combination produces, and
  reported the shortcuts as dead. They were not: `⌘⇧F`, `⌘⇧P`, `⌘⌥1` and `⌘⌥2` all fire as designed,
  including with a text field focused (leg 14b). Worth recording because the failure mode was the
  *leg text*, not the app — a smoke report is read under stage-like conditions and its key notation
  has to survive that. Spell modifiers out in future legs.
- **Fullscreen output verified on real hardware, with an external display attached** — the program
  window goes genuinely borderless and edge-to-edge on the second screen, no window chrome. This is
  the first time the output path has been seen on two displays. Note that it is NOT a substitute for
  M1 projector legs 15–18 (`arshader-m1-live-smoke-confirmed-gate-20260730`), which remain unrun:
  those cover unplug-mid-set and destination-restore, not just presentation.
