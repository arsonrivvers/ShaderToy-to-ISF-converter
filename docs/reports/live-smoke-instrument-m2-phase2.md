# Live smoke — ARShader Milestone 2, phase 2 (stacked FX chains)

**Status: PARTIALLY CONFIRMED 2026-07-30 by Conner — the FX surface is signed, four legs remain.**

Phase 2's premise was that a deck should host an unbounded stack of `.fs` effects, and the program
output its own — findings 7 and 8 from the Milestone 1 smoke, where the operator chose an unbounded
chain over fixed slots. That is now built and playing. Two of the three defects found this round
came from the operator's first look rather than from any test, which is the same signal Milestone 1
produced and the reason this report exists.

- **Build under test:** `~/Applications/ARShader.app` (install with `./scripts/run-instrument.sh`)
- **Automated gates:** ARShaderTests 181/181 · TrueISFEditor 514 (3 skipped) · ShadertoyISFKit 312
- **Operator:** Conner
- **Date:** 2026-07-30
- **Branch:** `m2-render-scale-and-fx`, commits `874aa03 … 63ed737` (10 this session)
- **Result:** CONFIRMED for chains, master chain, and the blackout gate. Legs 3–6 NOT RUN.

## Legs

State each hypothesis so it can fail. A leg is only CONFIRMED when the operator saw it.

| # | Leg | Hypothesis | Result |
|---|---|---|---|
| 1 | A chain applies | A filter appended to `A FX` visibly changes Deck A's image, and its filename appears in the stage row | **PASS** — operator: "it does load the fx" |
| 2 | Stage controls open | Expanding a stage reveals that shader's generated sliders | **FAIL, then FIXED** `a98c44f` — see Findings 1 |
| 3 | Order matters | Two different filters produce a visibly different result after ▲▼ than before | **NOT RUN** |
| 4 | Mix dries out | Dragging a stage's Mix 1 → 0 fades its effect out continuously, not in a jump | **NOT RUN** |
| 5 | Blend per stage | Changing one stage's blend mode changes the composite without touching the others | **NOT RUN** |
| 6 | Disable costs nothing | Unticking a stage removes its effect AND its per-tile GPU ms drops | **NOT RUN** — proven in code and by two tests, never watched on the meter |
| 7 | Master chain reaches program | A filter on `MST FX` changes the PROGRAM monitor and NOT the deck tiles | **PASS** — operator confirmed |
| 8 | Blackout still wins | ⌘B blacks the program with a master stage loaded — nothing outranks the panic button | **PASS** — operator confirmed |
| 9 | Sources are routable | A deck filter's `inputImage` can be pointed at a pattern/shader/camera; a stage's primary reads `chain` | **PASS after rework** — see Findings 2 |
| 10 | Render scale trades sharpness for GPU ms | Dropping PREVIEW SCALE lowers measured GPU ms proportionally | **PASS (prior session)** — `render-scale-sweep-2026-07-30.md`, 1.6 ms max deviation |

## Findings from the session

| # | Finding | Disposition |
|---|---|---|
| 1 | **Expanding an FX stage revealed nothing** | **FIXED** `a98c44f`. `ShaderControlsView` is itself a `ScrollView`, and a `ScrollView` nested in another scrolling container has no intrinsic height — with only a `maxHeight` it collapsed to ~0, so the disclosure "opened" onto empty space. Now carries a `minHeight`; the stage NAME is also a hit target, since a 12pt chevron is a poor thing to aim at mid-set. |
| 2 | **Source dropdowns were clutter in the parameter list** | **FIXED** `a98c44f`. Routing moved to its own `SOURCES` block under the shader name, above Opacity. Operator's call from a screenshot of `inputImage`/`depthSource` sitting among the float sliders. The block scales to N inputs — the shader that prompted it has two — which a menu on the monitor tile would not have. |
| 3 | **Blackout button was a 56pt slab** | **FIXED** `63ed737`. 56 → 26pt. It was sized as a stage-lighting hit target, but it gets hit with the keyboard (⌘B latch, Escape momentary), and it was eating vertical room the FX chains need. The blackout PATH is unchanged. |
| 4 | Does unticking a stage really stop costing GPU? | **ANSWERED, code + tests.** Better than a bypass check: `FXChain.publishToRenderThread` filters disabled and zero-mix stages out of the render mirror entirely, so the render thread never sees them — no `renderOffscreen`, no compositor pass. The compiled shader stays resident in VRAM; the per-frame cost is what goes to zero. **Not yet watched on the per-tile meter** (leg 6). |

## Defects caught by review before they shipped

Recorded because none of these would have been caught by a test — they were found by reading.

| What | Where |
|---|---|
| Task 7's `FXStage` called an initialiser Task 7.5 creates, and 7.5's first test called `encode` from Task 8 | Plan ordering — resequenced model → binding → encode, no gate dropped |
| `FXStage.apply` was specified `fileprivate` while `FXChain` lives in another file — could not have compiled | `3ebb947` |
| `masterFX` as a property default: `FXChain.init` is `@MainActor`, property initialisers are nonisolated | `cba58e9` |
| `testTheMasterChainStillUsesOneCommandBuffer` asserted a delta of ONE buffer — an invariant per-element metering retired the previous session | `cba58e9`, rewritten as `testAMasterChainOfManyStagesAddsNoCommandBuffers` |
| The operator's input-source dropdown was in the handoff as "folded into Task 10" but appeared in neither the plan nor the spec | Raised, confirmed, built — `89ad29b` |

## Already verified by the agent (not operator-confirmed)

| What | Evidence |
|---|---|
| Ping-pong parity is real | Mutation test: deleting `swap(&source, &target)` fails 9 tests, including both the plan predicted |
| Mid-chain alpha is preserved, master alpha forced opaque | Mutation test: hard-coding `ao = 1.0` fails both assertions in `testMidChainMixPreservesAlphaInsteadOfForcingItOpaque` |
| A stage reads the chain feed, not a routed camera | `testAStageReadsTheChainFeedNotItsRoutedSources` — read `"camera" is not equal to "none"` before the fix |
| Chain depth costs no command buffers | `testAMasterChainOfManyStagesAddsNoCommandBuffers` — 2 master stages, same 3 buffers as with none |
| Chain depth costs no textures | A ping-pong PAIR covers any depth; one extra texture per deck, allocated with the owned output |
| Staged binary is fresh | ASCII markers from each build present in `ARShader.debug.dylib` before every "relaunch" claim |
| The editor is untouched | TrueISFEditor 514 (3 skipped) re-run at Tasks 5, 7.5 and 11 — `MetalRenderCore` and `SourceRouter` changes are additive with defaults |

## Known open

1. **Legs 3–6 unrun.** Order, Mix, per-stage blend, and disable-drops-the-meter. Leg 6 is the one
   worth doing on the meter rather than on faith — it is a 20-second check now that per-tile GPU ms
   is always on.
2. **The 36.6 ms cue anomaly, still unexplained.** Carried from the previous session. The check:
   both decks loaded, PREVIEW 100%, CUE 25% — if DECK B ≈ DECK A on the tiles, cue is not reducing
   real cost (candidate: an ISF `PERSISTENT`/feedback buffer that does not shrink with the
   requested size).
3. **Colour and alpha use different mix amounts.** `encodeLayer` mixes colour by `src.a * opacity`
   but alpha by `opacity` alone. They agree exactly when a stage outputs alpha 1 — the normal case,
   and the only case the fixtures produce. They diverge when a filter outputs PARTIAL alpha *and*
   Mix < 1: colour goes mostly dry while alpha reads fully wet. Implemented as specced rather than
   redesigned mid-task; the tests pin the specced behaviour. Worth a decision, not urgent.
4. **The spec and plan still say RENDER SCALE and describe a one-buffer frame.** Both superseded in
   the previous session. This cost real time today — the plan's master-chain buffer test asserted
   the retired invariant and had to be rewritten.
5. **Projector legs 15–18 remain unrun on hardware** (`arshader-m1-live-smoke-confirmed-gate-20260730`).
   Unchanged this session, and they now matter more: the projector can be fed a master FX chain.
6. **Layout judgments unmade.** Whether the SOURCES menus are readable at `maxWidth: 150` in that
   column, and whether `minHeight: 150` for an expanded stage is the right amount of room. Both are
   numbers, trivially changed once seen.

## Deferred reviews

- **Client Success** — the FX surface (stage rows, SOURCES block, master column, five-way library
  picker) has not had a UX review. Filed as an action item.
- **Mechanic** — completed as a **manual** review under the standing native-Swift exception. It is
  what caught the `fileprivate` impossibility, the `@MainActor` property-default error, and the
  stale buffer-count assertion.
