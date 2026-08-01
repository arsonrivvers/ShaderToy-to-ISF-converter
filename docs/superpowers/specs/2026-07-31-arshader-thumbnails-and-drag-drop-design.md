---
title: ARShader Milestone 2 phase 3c — still frames, drag and drop, and the preview/program split
date: 2026-07-31
status: approved
target_repo: ShaderToy-to-ISF-converter
depends_on: docs/superpowers/plans/2026-07-31-arshader-slot-bank.md (phase 3b, branch m2-slot-bank)
---

# Phase 3c — still frames, drag and drop, and the preview/program split

Driven by an operator mockup and a design conversation on 2026-07-31, after phase 3b was installed
and seen on device.

## What changes

1. **Slots show still frames, not names.** The strip becomes a contact sheet you read at a glance.
2. **Drag and drop becomes the universal verb** for moving shaders anywhere.
3. **The library shows a preview on hover** and loses its load-target picker entirely.
4. **Slots load decks only** — never FX, never master. `RECALL TO` becomes two buttons, A and B.
5. **The projector feed is pinned at 100% forever.** `PREVIEW SCALE` stops being able to touch it.

## Why each

### Still frames

*"We should use still frames of the shaders in the loading bay."* You recognise a shader by its look
far faster than by `AR_Genuary_17.fs`, and the truncating-middle filenames the library already has to
draw prove the name was never doing the job.

### Drag and drop

*"I want drag and drop to be the way shaders get moved into either deck or FX get put into either
deck or master fx channel."* Today the destination is a mode — a five-way picker you set somewhere
else and then have to remember. Dragging makes the destination the gesture, which removes the
mode entirely. Phase 3b's review found the cost of the mode version directly: with the bank open the
picker was off-screen, so a slot click fired at an invisible destination, and one value of it
silently appended unbounded FX stages.

Every drop target is explicit:

| Drag from | Drop on | Result |
|---|---|---|
| Library row | Slot | The slot holds that shader (at its defaults) |
| Library row | Deck A/B monitor | Loads onto that deck |
| Library row | A deck's FX section | Appends a stage to that deck's chain |
| Library row | MASTER FX section | Appends a stage to the master chain |
| **Deck monitor** | **Slot** | **Captures what is playing — shader AND dialled values** |

That last row is how a *look* gets into a slot now that phase 3b's SOURCE picker is gone
(*"I don't understand source A or B"*). Library→slot gives you the shader; deck→slot gives you the
look. One verb, two meanings distinguished by where you started, which is the thing a mode could
never express.

### `RECALL TO: A | B`

Slots hold shaders and shaders go on decks — *"they will always be shaders not fx."* So the
destination collapses from five cases to two, and clicking a slot (or, later, hitting an APC40 pad)
needs exactly one answer. The five-way picker leaves the library sidebar entirely.

`LibraryTarget` keeps all five cases — drag-and-drop still needs FX destinations — but slot recall
is constrained to `.deck(_)` at the type level, not by convention.

### The preview/program split

**This is the one behavioural correction in the phase**, and it makes the instrument safer than it
is today.

`PREVIEW SCALE` currently sets the rasterisation for the **whole live chain** — both decks *and* the
master composite that feeds the projector. Its name says "preview"; its reach includes the output.
Setting it to 50% takes the master to 960×540 and projects an upscale. Seven existing tests encode
the single-raster assumption, which is how this was found: changing the default broke
`testMasterIsFixedAt1920x1080` and three frame-graph tests.

Operator's ruling: *"Preview scale should only effect whats on the app preview screens, the projector
feed should never be effected ever. That will always be at 100%."*

So:
- **The program/master path is pinned at 100%.** No control lowers it. `OutputSharpness.isProjectingUpscaled` becomes unreachable-by-design rather than a warning the operator has to notice.
- **`PREVIEW SCALE` governs a downscaled copy that only the monitor tiles read.**

**Stated honestly, because it changes what to expect:** this does NOT reduce shader cost. If the
projector needs 1920×1080, that raster happens regardless. What it saves is display bandwidth —
three monitor views each sampling a full-size texture into a ~340pt tile, at 120fps, become three
views reading one small copy. Real, measurable, modest. The large saving still lives where it always
did: with output closed, nothing needs full resolution at all.

## Thumbnails

**On demand, cached to disk, keyed by file path + modification date.** A shader gets a still the
first time it is hovered or slotted; every later request is a cache read. Nothing is generated for
the ~1,500 shaders never touched.

This is the genuine engineering in the phase. Nothing in ARShader renders a still today.
`TextureReadback` and `FramePNGEncoder` already exist in the shared `ISFRuntime`, so the pieces are
there; the work is an offscreen compile → render one frame → read back → encode → cache pipeline that
never blocks the render loop or the main thread.

Non-negotiable constraints:
- **Never on the render thread, never blocking the main actor.** The instrument is playing.
- **Bounded concurrency.** A hover sweep across the library must not spawn 1,500 compiles. One at a
  time, newest request wins, older pending requests cancelled.
- **A shader that fails to compile gets a placeholder, cached as such.** Retrying a broken shader on
  every hover is a stutter the operator cannot explain.
- **Time.** Pick a fixed sample time (not t=0 — many shaders are black at t=0) and document it. A
  black thumbnail is worse than no thumbnail.

## Slot cell states

Three, all distinguishable at a glance, per the operator's "combination of 1 + 2":

| State | Treatment |
|---|---|
| **Live** — this slot's shader is on a deck | Full colour, coloured border, **A** or **B** badge |
| **Idle** | Desaturated, no border, no badge |
| **Unavailable** — file moved or drive unmounted | Desaturated **and** dimmed, warning glyph where the badge sits; does not fire |

The third state is designed rather than inherited, because greyscale is now taken. It matters: an
unavailable slot currently does nothing on click with almost no explanation, and after two dead
clicks the natural next move is the context menu that destroys it.

## Out of scope

- **MIDI.** The seam exists (`Instrument.load(_:onto:thenApply:)`); nothing binds to it.
- **Value randomisation.** Operates on a `Preset`; the shape already supports it.
- **Named/browsable presets, favorites, recents** — still deferred.
- **Animated previews.** Stills only.

## What phase 3b work this supersedes

The SOURCE A/B picker, the strip's five-way `RECALL TO` picker, and `LibraryPanelView`'s target
picker all go. Click-to-load in the library becomes drag-only. The model underneath — `Preset`,
`SlotBank`, `SlotBankStore`, `ShaderUnit.sourceURL`, `Instrument.load(_:onto:thenApply:)` — is
untouched by all of it.

## Task outline

Dependency order. Each ends with an independently testable deliverable.

1. **`ThumbnailService`** — offscreen render, disk cache, bounded concurrency, failure placeholder. No UI. Fully unit-testable against fixture shaders.
2. **Program pinned at 100%; `PREVIEW SCALE` governs a monitor-only downscale.** Frame-graph change; updates the seven tests that encode the current single-raster assumption. Do this early — it is the riskiest change and unrelated to the UI work.
3. **Slot cells draw thumbnails**, with the three states.
4. **`RECALL TO: A | B`**; slot recall constrained to decks at the type level; SOURCE picker removed.
5. **Drag and drop: library → slot / deck / deck FX / master FX.** Remove the library's five-way picker and its click-to-load path.
6. **Drag and drop: deck monitor → slot**, capturing the live look.
7. **Library hover preview.**
8. **Regression, install, smoke report.**
