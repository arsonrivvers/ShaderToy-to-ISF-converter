# Render scale sweep — the Milestone 2 phase 2 gate

**Date:** 2026-07-30
**Operator:** Conner
**Verdict: PASS — no regression. Part B (FX chains) is cleared to proceed.**

## Why this measurement exists

The operator reported the same shader reading **104 FPS · 13.7 ms GPU** in TrueISFEditor and
**31 FPS · 62.8 ms GPU** in ARShader, and asked whether the instrument had a rendering problem.
Rather than answer from inspection, the plan built the render-scale control first and used it as
the instrument: sweeping it holds the output resolution, the projector, and the master allocation
fixed while changing only the number of pixels rasterised. Typing into OUTPUT RES to measure would
have changed the deliverable in order to measure it.

## Conditions

- `AR_ChaosCubes_v04_beta.fs` — a multi-pass feedback shader — on **both** decks
- Deck A live (opacity 1.00 → 1.00), Deck B cued (1.00 → 0.00), crossfader hard left
- OUTPUT RES `1920 × 1080`, CUE SCALE 25%, program output closed
- Build: `~/Applications/ARShader.app`, installed 14:57 from `6261e77`

## Result

| Render Scale | Rasterised | Pixels | Fraction | Predicted (linear) | **Measured** | Δ |
|---|---|---|---|---|---|---|
| 100% | 1920 × 1080 | 2,073,600 | 1.000 | — | **99.4 ms** (20 fps) | — |
| 75% | 1440 × 810 | 1,166,400 | 0.5625 | 55.9 ms | **55.0 ms** | −0.9 |
| 50% | 960 × 540 | 518,400 | 0.2500 | 24.9 ms | **26.5 ms** | +1.6 |
| 25% | 480 × 270 | 129,600 | 0.0625 | 6.2 ms | **5.8 ms** | −0.4 |

Maximum deviation from a straight proportional fit: **1.6 ms**.

## Verdict

**GPU cost is proportional to rasterised pixel count, with no meaningful fixed overhead.** That is
the signature of a frame graph doing exactly the work it should and nothing else. There is no
structural defect to bisect.

The 104-vs-31 comparison was apples-to-oranges, and the code says why:
`MetalRenderCore.targetSizeLocked` returns `BlitFit.inscribe(aspect:in: drawableSize)` when **Fit**
is checked — the editor's `1920 × 1080` fields supply the *aspect ratio*, and the render happens at
the preview pane's drawable size. ARShader had no equivalent and rasterised the full typed output
resolution every frame, on two decks.

Also worth recording: the editor's "104 FPS" is a 9.6 ms frame period against a reported 13.7 ms
GPU. GPU time exceeding the frame period means frames overlap on the GPU and the accumulator is
measuring *submission* cadence, not completed throughput. Both apps share
`RenderStatsAccumulator`, so the comparison is not invalid — but the honest statement of the gap
was always **13.7 ms vs 62.8 ms**, never 104 vs 31.

## Open question raised BY this sweep

Deck A alone at 100% measured **62.8 ms** earlier in the session. With Deck B added, loaded and
faded out at CUE SCALE 25%, the same configuration measures **99.4 ms**.

A cued deck at 25% rasterises 6.25% of the pixels and should have cost about **3.9 ms**. It appears
to have cost **36.6 ms** — roughly 9× too much.

`FrameGraphTests.testALiveAndACuedDeckRasteriseAtDifferentScalesInTheSameFrame` proves the two
decks are *asked* for different sizes (1920 and 480) in the same frame, so if something is wrong it
is below that boundary — candidates: an ISF PERSISTENT/feedback buffer that does not shrink with
the requested render size, or the cue path not reaching the engine. The unit test could not have
caught either.

Next measurement, before deciding whether CUE SCALE survives as a separate control: both decks
loaded as above, RENDER SCALE 100%, read GPU ms at CUE SCALE 100% and again at 5%. If the figure
barely moves, the control is not doing real work.
