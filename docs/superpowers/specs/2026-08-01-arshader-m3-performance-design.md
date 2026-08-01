---
title: ARShader Milestone 3 — measured performance pass
date: 2026-08-01
status: draft — measurement gate not yet run
target_repo: ShaderToy-to-ISF-converter
depends_on: Milestone 2 phase 3c merged and signed on device
---

# Milestone 3 — measured performance pass

Filed 2026-08-01, mid-phase-3c, after the operator asked *"Is there any other way for us to save GPU
render cost here? I'm open to all ideas to maximize performance."*

**Deliberately NOT started during 3c.** Landing a frame-rate change in the middle of a drag-and-drop
phase is how a render path gets destabilised immediately before a show. 3c finishes, gets signed,
and merges first.

## Why this milestone exists

`PREVIEW SCALE` was the instrument's only GPU lever, and phase 3c revision 4 established its honest
limit: **while the projector is open it cannot reduce shader cost at all.** The decks must produce
those pixels for the audience. So the large saving — 99.4 ms → 5.8 ms at 25%, measured 2026-07-30 —
exists only with the output closed, which is exactly when the operator does not need it.

Everything below is about saving GPU **while projecting**, which is the case that matters on stage
and the case no current control addresses.

## The measurement gate — this comes FIRST, before any task

Nothing in the candidate list below is approved for implementation until one measured run exists.
The instrument already has per-element GPU metering (`InstrumentRenderer.meteringEnabled`, the
per-deck command buffers it allocates, `RenderStatsModel`, `GPUPassTimer`), so this costs a session,
not a build.

**The run:** a genuinely heavy shader on BOTH decks — a ray-marcher or high-octave fBm, not
`solid_red` — output OPEN on the external display, metering on, at the operator's real working
window size. Record the per-element split:

| Element | What it tells us |
|---|---|
| Deck A / Deck B rasterisation | Whether shader cost dominates (expected: overwhelmingly yes) |
| The composite pass | Whether §4 is worth doing at all |
| Master FX chain | Whether an FX-heavy show shifts the picture |
| Monitor tile sampling | Whether the revision-4 downscale actually bought anything measurable |

**This list is expected to reorder after that run.** It is a set of mechanisms, not a set of
findings. Do not treat the ranking below as evidence.

## Candidates, ranked by payoff against effort

### 1. Decouple frame rates — program at display refresh, monitors at ~30

The whole instrument runs at one rate today. The operator's own screenshot reads **120 FPS ·
5.5 ms**, i.e. already ~66% GPU-bound at idle-ish load. But:

- The **projector** needs the display's refresh, almost certainly 60.
- The **three monitor tiles** need perhaps 30. Nobody perceives 120 fps in a ~340pt thumbnail.

Program at 60 and monitors at 30 approaches a **2× cut**, and unlike preview scale it works while
projecting. This is the milestone's centrepiece.

Risks to design against: the crossfader and blackout must stay perceptually instant regardless of
the monitor rate — a control that feels laggy on stage is worse than a warm GPU. Blackout in
particular is a panic button and must never wait for a slow tile.

### 2. Cued decks are rate-limited, not just resolution-limited

`renderFrame()` already drops a non-contributing deck to cue *resolution*
(`let isLive = layer.effectiveOpacity > 0` → `(isLive ? liveRes : cueRes)`). It does **not** drop
its rate — a cued deck feeding one small tile still renders 120 times a second.

A cued deck at 20–30 fps is a **4–6× cut on that deck**. The machinery that identifies a cued deck
already exists and is already tested (`testALiveAndACuedDeckRasteriseAtDifferentScalesInTheSameFrame`),
so this is the cheapest real win on the list.

Risk: the deck must be at full rate *before* it becomes live, or a crossfade starts on a stale
frame. The transition, not the steady state, is where this one can go wrong.

### 3. Pause the loop when nobody is looking

Already tracked as `arshader-instrument-occlusion-pause-20260730`. Window minimised or fully
occluded → stop rendering. Free, and it is the difference between a laptop that stays cool between
sets and one that does not.

### 4. Skip the composite when exactly one layer contributes

At crossfader hard-left, the frame still clears the master to opaque black and runs a full
`encodeLayer` blend for a single source. That is a blit's worth of work done as a blend pass. Small
next to §1 and §2, close to free to implement.

Constraint: the master's opaque-black contract and the blackout gate's position in the chain must
not move. Blackout runs after master FX deliberately — *nothing may sit between the panic button
and darkness*.

### 5. Do not render monitor tiles that are not visible

A tile covered by an open panel, or hidden in show mode, is still being fed. Bounded by however
often that is actually true, so it needs the measurement to justify itself.

## Explicitly rejected

**Per-shader quality uniforms or iteration caps.** It means editing ~1,500 shaders, and the
conversion pipeline is precisely where subtle breakage hides. The cost/benefit is wrong and the
blast radius is the whole corpus.

**Softening the projector to recover GPU.** Offered to the operator on 2026-08-01 and refused. The
"projector never affected, ever" rule stands and is not reopened by this milestone.

## Out of scope

- Anything requiring shader source edits
- Anything that changes the ISF conversion pipeline
- MIDI, the APC40 work, and every phase-3c UI concern
