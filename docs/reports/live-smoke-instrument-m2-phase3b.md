# Live smoke — ARShader Milestone 2, phase 3b (slot bank)

**Status: PENDING — suites green, legs written and UNRUN.**

Phase 3b builds the slot bank: a resizable, collapsible strip of look slots sitting under the
monitor row, always visible. A slot holds a **look** — a shader *plus the values dialled into it* —
so recalling one puts the instrument back exactly where it was, not back at the shader's defaults.
The bank is APC40-shaped: recall by position, forty slots stored, one to five rows drawn.

Automated suites are green. **No leg below has been run.** Phase 3b is STAGED until the operator
runs them on device, per the on-device gate in `CLAUDE.personal.md`.

- **Build under test:** `~/Applications/ARShader.app`, installed 2026-07-31 18:24 from
  `/tmp/arshader-ddata-bank` (never `/tmp/arshader-ddata` — a concurrent codex session works in the
  main checkout). Under Xcode 26 the real code is in `ARShader.debug.dylib`, not the 58KB
  `Contents/MacOS/ARShader` stub. The installed dylib is byte-identical to the build product
  (sha256 `61b7b134…`), and carries both of the collapse-marker fix's new symbols:
  `SurfaceLayout.drawnBankRows` and `SlotBank.hiddenFilledCount(drawnRows:)`, confirmed with `nm`.
  **`strings` is the wrong tool for this check** — mangled Swift symbol names live in the symbol
  table, not `__cstring`, so `strings` reports zero hits on code that is demonstrably present.
- **Automated gates** (all run in the foreground at `1e419da`):
  - ARShaderTests: **256 tests, 0 failures**
  - TrueISFEditorTests: **514 tests, 3 skipped, 0 failures**
  - ShadertoyISFKitTests: **312 tests, 0 failures**
- **Operator:** Conner
- **Branch:** `m2-slot-bank`, commit `1e419da`
- **Result:** **PENDING.**

## Legs

State each hypothesis so it can fail. A leg is only CONFIRMED when the operator saw it.

Legs 1–11 come from the plan's Task 8, rewritten for the strip. Legs 12–16 are Task 8R's rows,
collapse and resize. Leg 17 covers the collapse-marker fix committed after the plan was written.
Legs 18–19 cover two defects found in review whose failure mode is invisible in the call graph.

| # | Leg | Hypothesis | Result |
|---|---|---|---|
| 1 | Strip is always there | The bank is a strip under the monitors, not a panel. There is **no third rail icon** and no shortcut that opens it — it is already open. `⌘⌥1`/`⌘⌥2` still reach Library and Settings | ⬜ |
| 2 | Capture names the look | Clicking an empty cell captures the loaded shader, and the cell takes that shader's name | ⬜ |
| 3 | Recall restores the LOOK | Click a filled slot: the shader loads **and the dialled values come back**. Move a parameter well off its default before capturing, so a shader-only recall would be visibly wrong | ⬜ |
| 4 | Recall never overwrites | Click a filled slot ten times. It recalls ten times and its contents never change. This is the rule the whole bank rests on — a look lost to a mis-click is unrecoverable | ⬜ |
| 5 | Replace and Clear are deliberate | ⌥-click replaces. Hover ▸ **Replace** replaces. Hover ▸ **Clear** empties. Nothing else writes to a filled slot — in particular, the hover-revealed Replace control must sit **outside** the recall click target, so a normal recall click cannot land on it | ⬜ |
| 6 | SOURCE picks the read deck | Set SOURCE to B, load different shaders on A and B, capture: the slot holds **B's** look, whatever RECALL TO is set to | ⬜ |
| 7 | RECALL TO picks the write target | Set RECALL TO to `MST FX` and fire a slot: it appends an FX stage rather than swapping a deck. Both pickers are visible on the strip at the moment you fire — that visibility is the reason the bank left the rail | ⬜ |
| 8 | The bank persists | Quit and relaunch: every captured look is back, **and so are the row count and the collapsed state** | ⬜ |
| 9 | A missing file is dark, not destroyed | Rename a captured shader's file on disk, relaunch: the slot draws unavailable, clicking it does nothing at all, **and the slot is still there**. Rename the file back, relaunch: the slot works again | ⬜ |
| 10 | Eight cells legible at full width | At a normal window size, all eight names in a row are readable, not truncated to nothing | ⬜ |
| 11 | Cells never overlap when narrow | Shrink the window to its minimum with the Library panel open at its 260pt floor. The cells **scroll horizontally** rather than compressing further. Click the extreme left and right edges of a cell: each fires **that** cell, never its neighbour. (Cells previously computed to 31.1pt against their own 32pt floor here, overlapping hit areas) | ⬜ |
| 12 | Recall twice does not black-frame | Fire the same slot twice in a row. The accepted recompile window is a brief flash; a persistent black frame is a defect | ⬜ |
| 13 | Resize adds rows, monitors hold still | Drag the strip's **top edge** upward: it grows by whole rows, one row per drag step, up to five. **The monitor row does not resize and does not slide** while it happens. This is phase 3a's §2.1 reversal, extended | ⬜ |
| 14 | Shrinking never destroys a look | Capture a look into row 2, then drag the strip back down to one row. Grow it again: the look is there, unchanged. (Structural — a resize has no code path to the model at all) | ⬜ |
| 15 | Show mode cannot collapse the bank | Collapse the bank by hand with the disclosure chevron; it collapses. Now press `⌘⇧P`: **show mode leaves the bank exactly as it is**, collapsed or not. Configuration collapses; firing slots is performance | ⬜ |
| 16 | Collapse remembers the rows | Set the strip to three rows, collapse it, expand it: three rows come back, not one | ⬜ |
| 17 | Hidden looks are always marked | With looks captured in rows the strip is not drawing, an orange **"N hidden"** marker sits in the header. Shrink to one row with looks in row 2 — the marker counts them. **Now collapse the strip entirely: the marker counts EVERY captured look**, because nothing is drawn. It must never read as hiding nothing while looks are off screen | ✅ PASS — collapsed with two looks captured, "2 hidden" appears (operator, 2026-07-31) |
| 18 | A failed compile does not corrupt a slot | Recall a slot whose shader has been edited on disk into something that will not compile. The previously-loaded shader keeps playing, and **the live shader's dialled values are NOT overwritten** by the failed recall's snapshot. Then capture into an empty slot: the captured slot must name the shader that is actually **playing**, never the one that failed | ⬜ |
| 19 | The suite never touches the real bank | After running the automated suite on this machine, relaunch the app: the operator's bank is untouched — same looks, same rows. (`Instrument.init()` wrote to real `UserDefaults` before this was fixed, so the suite clobbered the saved bank with fixtures pointing at deleted temp files) | ⬜ |

## Notes

- The three regression suites were run in the foreground at `1e419da` and their counts recorded
  above. ARShaderTests is **256**, up from the plan's expected 240: task 7R and the collapse-marker
  fix added tests after the plan was written. Any number other than 256 means a test was lost.
- **Legs 4, 5, 11, 17, 18 and 19 each correspond to a defect caught in review before shipping.**
  They are not ceremony — each one was true in the call graph and false somewhere else, or would
  have been shipped without the review that found it.
- Leg 17's fix (`1e419da`) landed **after** the rest of phase 3b and is covered by nothing else.
