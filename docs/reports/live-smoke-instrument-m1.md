# Live smoke — ARShader Milestone 1

**Status: SIGNED 2026-07-30 by Conner — CONFIRMED with findings.**

Milestone 1's premise was that the TouchDesigner build's failure mode was a great deal getting
built before anything got played. That is now discharged: the operator drove the instrument, and it
produced feedback within minutes — including one real defect (Freeze) that 104 green tests did not
catch, and a Milestone 2 feature list. That is exactly the outcome the small milestone was for.

- **Build under test:** `~/Applications/ARShader.app` (install with `./scripts/run-instrument.sh`)
- **Automated gates:** ARShaderTests 107/107 · TrueISFEditor 514 (3 skipped) · ShadertoyISFKit 312
- **Operator:** Conner
- **Date:** 2026-07-30
- **Result:** CONFIRMED for the core instrument. Projector legs NOT RUN (see below).

## Findings from the session

| # | Finding | Disposition |
|---|---|---|
| 1 | **Freeze does nothing** | **FIXED** `ab9cfb0`. It held a reference to a texture reused every frame, so contents kept updating under it. Now copies pixels on the rising edge. Mutation-tested: reinstating the old behaviour fails the new test. |
| 2 | Deck A / B / program output resolution are not adjustable | **DONE** `ec176bf` + `cbaf85b` — typed W×H output resolution (presets in a menu); decks follow output; cue = a % of output |
| 3 | No FPS readout | **DONE** `ec176bf` — measured draw cadence + mean GPU ms, ~2×/sec, "no frames" when idle rather than a stale rate |
| 4 | Library cannot be collapsed; wants a button-driven slide-out panel system like TrueISFEditor | Milestone 2 — **phase 3**, deliberately last so the panels are designed once, against the finished feature set |
| 5 | Library needs to be genuinely useful for show prep (organisation, folders — operator said folders can come later) | Milestone 2 |
| 6 | **Add** blend mode missing, plus others worth taking from TouchDesigner's Composite TOP | **DONE** `c790b10` — Add, Subtract, Linear Burn, Vivid Light, Pin Light, Hard Mix, Divide; appended so the twelve W3C indices are unchanged |
| 7 | Need multiple `.fs` per deck — stacked effect chains | Milestone 2 — **phase 2, NEXT**. Operator chose an UNBOUNDED chain over fixed slots |
| 8 | Need a master effects chain on the program output | Milestone 2 (architecture) |

### Found after signing, while the operator kept playing

| Finding | Disposition |
|---|---|
| App froze at launch and showed "0 shaders" | **FIXED** `cbaf85b`. `loadInstrumentLibraries` ran inside a SwiftUI `.task` — main actor — and synchronously stat'd 1,477 files. Only looked instant in testing because the filesystem cache was warm. Now scans off-main and says "Scanning library…" rather than printing a count it does not have. |
| (agent-side) The whole ARShaderTests suite hung indefinitely | **FIXED** `cbaf85b`. A test looped `renderFrame()` 200× synchronously; a Metal command queue permits ~64 buffers in flight, so `makeCommandBuffer()` blocked on its semaphore forever. Diagnosed from a `sample` of the wedged test host. |
| (agent-side process error) The app was killed mid-play, repeatedly | `scripts/run-instrument.sh` quits any running instance before installing. Do not reinstall while the operator is playing without saying so first. |

## Legs not run

Legs 15–18 (**external display / projector**) were not exercised — no external display was
connected during the session. The placement logic is unit-tested against a `ScreenInfo` value model,
but no output window has ever been on a real second screen. Still open under action item
`arshader-m1-live-smoke-confirmed-gate-20260730`.

## Already verified by the agent (not operator-confirmed)

| What | Evidence |
|---|---|
| Library reads the real corpus | Live capture: **1,491 shaders** listed from `/Library/Graphics/ISF` |
| Per-shader controls generate from real `AR_` files | Live capture: `rot_speed_x/y/z`, `morph_speed`, `sponge_scale`, `laser_width`, `camera_z` from an `AR_Genuary2026_day12` shader |
| The frame graph renders end to end | Live capture: Deck A and PROGRAM monitors both showing the loaded shader |
| Staged binary is fresh, not stale | 5 ASCII markers from this build present in `ARShader.debug.dylib` |

## Legs

Fill in **during** the session, not after. State each hypothesis so it can fail.

| # | Leg | Hypothesis | Result |
|---|---|---|---|
| 1 | Library loads | `/Library/Graphics/ISF` lists ≥900 `.fs` entries and search narrows them | |
| 2 | Deck A plays | An `AR_Genuary` shader loads, animates smoothly, **and its filename appears under DECK A** (see the known-unverified note below) | |
| 3 | Deck B plays | A second, different shader loads without interrupting deck A | |
| 4 | Crossfade | Sweeping A→B moves the program monitor continuously, no jump at either end | |
| 5 | Opacity | Deck opacity and effective opacity both move, and disagree when the fader is off-centre | |
| 6 | Blend modes | All 12 modes visibly differ; multiply / screen / difference behave as expected | |
| 7 | Blackout latch | ⌘B blacks the program monitor while deck monitors keep running | |
| 8 | Blackout momentary | Escape held blacks out; released, the image returns; an engaged latch survives it | |
| 9 | Blackout while typing | ⌘B works with the cursor in the library Search field — the reason it is not a bare letter key | |
| 10 | Failed compile | Loading a known-broken shader on deck B leaves deck A playing and shows the error text | |
| 11 | Controls | A shader's own sliders move its image; double-click resets to header default | |
| 12 | Monitor freeze / off | Freeze holds the last frame; Off goes black; both override the live feed | |
| 13 | **Output ships closed** | On a cold launch nothing is projected until Output is chosen | |
| 14 | **Output → floating** | Output ▸ Floating Window shows the program feed, and the main window keeps keyboard focus | |
| 15 | **Output → second screen** | With an external display connected, Output ▸ *that display* fills it edge to edge — no title bar, no menu bar, no cursor | |
| 16 | **Blackout reaches the projector** | ⌘B blacks the external display, not just the on-screen monitors | |
| 17 | **Unplug mid-set** | Pulling the cable while output is live falls back to a floating window; it does not vanish and does not strand | |
| 18 | **Replug** | Reconnecting and re-selecting the display restores fullscreen output | |
| 19 | ⌘⇧F | Toggles the output window, and does NOT collide with blackout | |
| 20 | Sustained run | 20 minutes with shader swaps: no fps decay, no memory growth, no black frame | |

## Known unverified at hand-off

- **Deck name observation.** The strip was rebuilt as `DeckStripView` with its own `@ObservedObject`
  after the first live capture showed the loaded shader's name frozen at "—" while its controls
  updated correctly. The fix is correct by construction but was **not** re-observed on device — the
  relaunched app had nothing loaded. Leg 2 covers it.
- **Occlusion.** The editor pauses its render loop when its window is minimised or covered (its
  "B4" work). The instrument does not yet, so a minimised ARShader keeps rendering at display
  cadence. Not a Milestone 1 blocker; noted so it is not mistaken for a leak.

## Operator notes
