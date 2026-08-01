---
title: ARShader Milestone 2 phase 3c — still frames, drag and drop, and the preview/program split
date: 2026-07-31
revised: 2026-08-01
status: approved (revision 3 — PM review folded; master-pin corrected against the real frame graph)
target_repo: ShaderToy-to-ISF-converter
depends_on: docs/superpowers/plans/2026-07-31-arshader-slot-bank.md (phase 3b, branch m2-slot-bank)
review: ~/.claude/c-suite/reports/pm/2026-07-31-arshader-3c-thumbnails-drag-drop-spec-review.md
---

# Phase 3c — still frames, drag and drop, and the preview/program split

Driven by an operator mockup and a design conversation on 2026-07-31, after phase 3b was installed
and seen on device.

**Revision 2 (2026-08-01)** folds the PM spec review, which returned REWRITE with eight findings.
The substantive one: revision 1 never said whether a *live* deck still follows `PREVIEW SCALE`, and
three mutually exclusive readings were each supported by different sentences of the same section.
The operator's ruling is now in "The preview/program split" below, and the other seven findings are
resolved in place.

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

#### A drop on a FILLED slot never overwrites it

Phase 3b's hard-won rule — *"A click on a filled slot can only recall. It can never overwrite.
Losing a dialled-in look mid-set to a one-cell mis-click is unrecoverable, and would happen exactly
once before the bank stopped being trusted"* — is enforced today by `capture` having exactly one
call site in `SlotBankStripView`, gated to empty-cell click, ⌥-click, and Replace.

A drag is a *bigger* mis-click risk than a click, not a smaller one: the operator is moving across
the surface with a payload attached, and a slot is a small target next to seven identical ones. So:

- **Dropping on an EMPTY slot fills it.** No confirmation.
- **Dropping on a FILLED slot is REJECTED by default** — the drop does not take, the slot is
  unchanged, and the cell shows the rejection treatment below.
- **⌥-drag replaces**, mirroring ⌥-click exactly. The modifier is the same one, deliberately: there
  is one "I mean it" gesture on this surface, not two.
- Replace and Clear stay in the context menu unchanged.

This must reuse the existing gating rather than adding a second path into `SlotBank.capture`. Any
implementation that gives a drop its own unguarded call to `capture` has reintroduced the defect,
and a test must fail if it does: **drop a library row onto a filled slot; assert the slot's `Preset`
is byte-identical afterwards.**

#### Rejected drops, and how the operator knows

Revision 1 enumerated only accepted pairs, which left every other combination as implementer's
choice. The full matrix — anything not listed as accepted above is rejected:

| Drag from | Drop on | Result |
|---|---|---|
| Any | Filled slot (no ⌥) | **Rejected** — never overwrite |
| Library row | MASTER FX | Accepted (appends a stage) |
| **Deck monitor** | Deck monitor, FX section, MASTER FX | **Rejected** — a deck is not a shader source for anything but a slot capture |
| **Slot** | Anything | **Rejected — a slot is not a drag SOURCE in this phase.** Slot→deck is what *clicking* a slot already does; adding a second gesture for it doubles the ways to fire a slot mid-set with no new capability. Revisit only with the APC40 work. |
| Anything | Anywhere not listed as accepted | **Rejected** |

**Rejection must be visible before the operator commits, not after.** Two mechanisms, both required:

1. **During the drag**, a valid target highlights and an invalid one does not. `NSDragOperation.none`
   from the drop delegate gives the "no entry" cursor for free — that is the baseline, not the whole
   answer.
2. **On an attempted drop that is refused**, the target gives one brief non-modal shake or flash. No
   dialog, no alert, nothing that steals focus. A rejected drop mid-set must cost zero attention
   beyond "that didn't take."

Silence on rejection is the failure mode to avoid: an operator who drops a look onto a filled slot,
sees nothing happen, and cannot tell whether it was refused or whether it silently overwrote.

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
- **While the program feed is OPEN, the whole live chain is pinned at full output resolution** —
  live decks and the master alike. `PREVIEW SCALE` cannot reach the projector by any path.
- **While it is CLOSED, `PREVIEW SCALE` governs the whole live chain exactly as it does today.**
  Nothing is projected, so there is no image to protect and the saving is free.
- `OutputSharpness.isProjectingUpscaled` becomes unreachable-by-design rather than a warning the
  operator has to notice.

**Revision 3 correction (2026-08-01), made while planning against the real frame graph.** Revision 2
said "the master is pinned at 1920×1080 unconditionally". That is worse, and reading
`InstrumentRenderer.renderFrame()` is what showed it: a pinned master with scaled decks composites
an upscale into a full-size target on every frame *while output is closed* — paying full-resolution
compositor and master-FX cost for an image whose only consumers are three ~340pt monitor tiles. It
would have partly undone the very saving `PREVIEW SCALE` exists for. Pinning the master **with** the
decks, on the same condition, keeps the projector rule exactly as the operator stated it and costs
nothing when it is closed.

#### The rule, stated so an implementer cannot read it two ways

Revision 1 left this ambiguous and the PM review was right to stop on it. The operator's ruling,
2026-08-01: **live decks follow `PREVIEW SCALE` while output is closed, and pin to 100% the moment
it opens.**

| `OutputDestination` | Live deck (contributing) | Cued deck (not contributing) | Master |
|---|---|---|---|
| `.off` | `previewScale` | `cueRenderScale` (a fraction of live) | follows `previewScale` |
| `.floating` / `.screen` | **100%, pinned** | `cueRenderScale` (a fraction of live) | **1920×1080, pinned** |

In the frame graph this is a **single expression**, which is the strongest argument for it. Today
`InstrumentRenderer.renderFrame()` computes `let liveRes = renderScale.applied(to: outRes)` and
everything else derives from it — deck rasterisation, cue size, master FX, and the master pair's own
allocation. The change is that one line becoming
`let liveRes = isProgramLive ? outRes : renderScale.applied(to: outRes)`. There is no second rule to
keep in sync, and no path by which a deck and its master can disagree about scale.

Why this and not the two simpler rules, both of which were live readings of revision 1:

- **"Live decks always follow `PREVIEW SCALE`"** would upscale a 960×540 deck into a fixed 1920×1080
  master and project the result — the exact soft-projector case the pin exists to make impossible.
- **"Live decks always pinned, `PREVIEW SCALE` touches cued decks only"** is `CueQuality`, which
  `RenderScale` was built to replace. Per `InstrumentRenderer.previewScale`'s own doc comment,
  `CueQuality` applied only to decks at zero effective opacity, making it inert on the deck actually
  costing the frame — measured by the operator 2026-07-30 at **62.8 ms GPU with Cue already at 25%**.
  Reintroducing that is a regression with a receipt.

Cue scale is untouched in every row: a cued deck is not on the projector, so nothing about opening
output makes it need full resolution. That is what preserves a saving while the projector is live.

#### What this costs to build, named because revision 1 did not

`InstrumentRenderer.renderFrame()` **has no knowledge of `OutputDestination` today** — verified by
reading it in full; the only mixer-ish state it sees is `mixer.isBlackedOutForRender()`, which is
blackout, a different concept. `OutputWindowController.destination` is the source of truth and lives
on the main actor.

So this task must thread program-live state into the renderer. It is a new lock-guarded property in
the same shape as `previewScale` — set from the main actor when the destination changes, read under
the lock during the frame, reallocating deck textures on change. Opening or closing the output is
operator-driven and rare, exactly like changing `PREVIEW SCALE`, so a reallocation there is
acceptable and must not happen per-frame.

#### The seven tests, named, with what happens to each

Revision 1 said "updates the seven tests" and named none. They are, in `FrameGraphTests.swift` and
`InstrumentRendererTests.swift`:

**All seven keep passing, unchanged in behaviour** — and that is a finding, not luck.
`OutputDestination.launchDefault` is `.off`, and none of the seven opens an output, so every one of
them was *already* testing the output-closed row of the table above. They were silently assuming it.

| Test | Fate |
|---|---|
| `testRenderScaleResizesTheMaster` | Passes unchanged (master still follows scale while closed). **Gains an explicit output-closed precondition** so the assumption is stated. |
| `testMasterIsFixedAt1920x1080` | Passes unchanged — it never sets `previewScale`, and the default is 100%. Gains the same precondition. |
| `testRenderScaleAppliesToALiveDeckNotJustACuedOne` | Passes unchanged. Gains the precondition. **This is the anti-`CueQuality` gate and must never be deleted.** |
| `testALiveAndACuedDeckRasteriseAtDifferentScalesInTheSameFrame` | Passes unchanged. Gains the precondition. |
| `testCueScaleIsAFractionOfTheLiveRenderNotOfTheOutput` | Passes unchanged. Gains the precondition. |
| `testTheInstrumentStillRendersCorrectlyAtAReducedRenderScale` | Passes unchanged. Gains the precondition. |
| `testSettingTheSameRenderScaleIsANoOp` | Unchanged, no precondition needed — no-op semantics are orthogonal. |

Making the precondition explicit in six of seven is the whole point: an implicit assumption that
happens to hold is one refactor away from a test that passes for the wrong reason, and this codebase
has already shipped one of those (see `SurfaceGeometryTests.stubMonitorIdealHeight`'s comment, where
a rigid stub could only ever prove the stub was rigid).

Four NEW tests carry the other half of the table, and the task is not done without them:

1. With output open, a live deck rasterises at full output resolution **whatever `previewScale` says**.
2. With output open, the master is 1920×1080 at `previewScale` 25%.
3. With output open, a cued deck **still follows `cueRenderScale`** — opening the projector must not
   silently cost the cue saving, which is the whole reason cue is a fraction of live.
4. `OutputSharpness.isProjectingUpscaled` cannot return true for any reachable combination — it is
   now structurally false, since the only condition that made it true (open output at reduced scale)
   no longer reduces the scale. The warning UI it drives is removed, and this test is what stops it
   silently returning.

**Stated honestly, because it changes what to expect:** with the projector open this saves shader
cost nowhere. That is the point — the projector gets everything. The large saving lives exactly
where the operator spends most of his time: **output closed**, where nothing needs full resolution
and `PREVIEW SCALE` still does what it has always done (99.4 ms at 100%, 5.8 ms at 25%, measured
2026-07-30). The monitor tiles additionally stop each sampling a full-size texture into a ~340pt
tile at 120fps — real, measurable, modest, and now the only saving the control claims while live.

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
- **A shader that fails to compile gets a placeholder, cached as such.** Retrying a broken shader on
  every hover is a stutter the operator cannot explain. A failure is a cache *entry*, not a cache
  miss, and is invalidated by the same path+mtime key as a success — fix the shader on disk and the
  next request retries it.
- **Sample time is `t = 2.0` seconds.** Settled 2026-08-01, not implementer's choice. Past nearly
  every fade-in and warmup, early enough that feedback and accumulation shaders have not drifted
  into mush. One documented constant, no per-shader heuristic. A black thumbnail is worse than no
  thumbnail, and t=0 is black for a large fraction of this library.

#### Two consumers, two concurrency policies

Revision 1 specified "one at a time, newest request wins, older pending cancelled". That is correct
for **hover** and wrong for **the bank**, and the PM review was right that revision 1 did not notice
they are different consumers:

| Consumer | Request shape | Policy |
|---|---|---|
| **Library hover** | One at a time, superseded constantly as the pointer moves | **Newest wins, cancel older.** A thumbnail for a row the pointer left is wasted work. |
| **Bank population** | Up to 40 at once, on launch or on expanding rows | **FIFO queue, every request completes.** Cancelling these is the bug — it leaves permanently blank cells that only a resize or relaunch would fill. |

So the service takes a **priority** on each request (`.interactive` cancels its own predecessor;
`.batch` queues and always completes), and hover cancellation must never reach a queued batch item.
Both share the same bounded worker — the bound is what protects the render loop, and a hover sweep
across 1,500 rows must still never spawn 1,500 compiles.

#### Interface

Named here so the implementer is not inventing the phase's most safety-critical surface from prose:

```swift
actor ThumbnailService {
    enum Priority { case interactive, batch }
    enum Result { case image(URL), unavailable }   // `unavailable` is a CACHED failure

    /// Cache hit returns immediately. Miss enqueues and suspends. Never touches the live device.
    func thumbnail(for shaderURL: URL, priority: Priority) async -> Result

    /// Drops in-flight `.interactive` work only. Queued `.batch` requests are unaffected.
    func cancelInteractive()
}
```

- **Cache key:** absolute file path + modification date, as revision 1 said. On disk under
  Application Support, one file per entry, so a stale entry is deletable by hand.
- **Eviction:** bounded by **count, not bytes** — a fixed ceiling (start at 2,000, above the ~1,500
  shader library so a full sweep never thrashes), LRU by file access date, swept once at launch and
  never during a set. Thumbnails are small and fixed-size; a byte budget would add arithmetic for no
  behavioural gain.
- **GPU isolation:** its own `MTLCommandQueue`, and its own `MTLDevice` handle obtained
  independently of the instrument's — **never the live renderer's queue**. Sharing the queue is how
  a thumbnail compile becomes a dropped frame mid-set, and it is invisible in every unit test
  because unit tests have no live render loop. A test must assert the service's queue is not
  identical to the renderer's.

## Slot cell states

Three, all distinguishable at a glance, per the operator's "combination of 1 + 2".

**Re-derived for thumbnails, because the 3b table cannot survive the change.** Those states were
designed against flat-colour cells, where saturation was a free channel. A thumbnail is a
photograph: it already spends colour, and shader stills in this library run the whole gamut from
near-monochrome to fully saturated. "Desaturated" is therefore no longer a *readable* difference —
a greyscale ASCII shader's idle cell and its live cell would look identical, and a lurid one would
read as "live" while idle. Saturation may stay as a supporting cue; it can no longer be the carrier.

The carrier becomes **border and badge**, which are chrome the thumbnail cannot collide with:

| State | Treatment |
|---|---|
| **Live** — this slot's shader is on a deck | Thumbnail at full brightness, **2pt coloured border**, **A** or **B** badge |
| **Idle** | Thumbnail dimmed ~35%, no border, no badge. Dimming, not desaturation — brightness is a channel a still image does not already own |
| **Unavailable** — file moved or drive unmounted | Thumbnail dimmed further **and** desaturated, **warning glyph where the badge sits**, and the last-known thumbnail is still shown rather than an empty cell. Does not fire |

The third state is designed rather than inherited: an unavailable slot currently does nothing on
click with almost no explanation, and after two dead clicks the natural next move is the context
menu that destroys it. Keeping its stale thumbnail visible is deliberate — the operator recognises
*which* look is broken, which is exactly the information needed to go remount the drive.

**Verification is visual, not unit.** These three must be told apart on device at cell size, against
real shaders spanning near-monochrome to fully saturated. That is a named smoke leg in task 8, not
an assertion — no unit test can see "distinguishable at a glance".

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

1. **`ThumbnailService`** — the interface above: offscreen render at `t = 2.0s`, disk cache keyed
   path+mtime, count-bounded LRU eviction, two priorities with different cancellation semantics,
   failures cached as failures, its own `MTLCommandQueue` never shared with the live renderer. No
   UI. Fully unit-testable against fixture shaders.
2. **The preview/program split.** Master pinned at 1920×1080 unconditionally; live decks follow
   `PREVIEW SCALE` while output is closed and pin to 100% while it is open; cue scale untouched
   throughout. Threads program-live state into `InstrumentRenderer`, which has none today. Rewrites
   one test, adds a precondition to five, strengthens one, and adds three new ones — all seven named
   in the section above. Do this early: it is the riskiest change and unrelated to the UI work.
3. **Slot cells draw thumbnails**, with the three re-derived states (border/badge carrying, dimming
   not desaturation).
4. **`RECALL TO: A | B`**; slot recall constrained to decks at the type level; SOURCE picker removed.
5. **Drag and drop: library → slot / deck / deck FX / master FX**, with the occupancy rule (empty
   fills, filled rejects, ⌥-drag replaces) and both rejection-visibility mechanisms. Remove the
   library's five-way picker and its click-to-load path.
6. **Drag and drop: deck monitor → slot**, capturing the live look. Same occupancy rule.
7. **Library hover preview**, using `.interactive` priority.
8. **Regression, install, smoke report.** Includes the named visual leg for the three cell states at
   cell size against near-monochrome and fully-saturated shaders.
