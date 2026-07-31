---
title: ARShader Milestone 2 phase 3b — the slot bank
date: 2026-07-31
status: approved
target_repo: ShaderToy-to-ISF-converter
supersedes: nothing
depends_on: docs/superpowers/plans/2026-07-31-arshader-panel-framework.md (phase 3a, merged 02fbcd4)
---

# Phase 3b — the slot bank

## What this is

Eight slots. Each holds a **preset**: a shader together with the parameter values that were dialled
when it was captured. Clicking a slot recalls that look onto whatever the load-target picker names.
The bank is a third tenant of the phase 3a rail.

## Why it is this and not a set list

Phase 3a's handoff named 3b "set lists — ordered collections, the way a DJ builds a crate." That was
wrong about the interaction, and the operator corrected it during brainstorming: the instrument is
driven from an **APC40 MkII**, whose clip matrix is a grid of pads recalled by position, not a
sequence stepped through. Order does not imply progression. A cursor advancing through a playlist
has nothing to bind to on that hardware.

It is also wrong about the payload. A slot recalls a **look**, not a file — "we will be able to load
presets, plus randomize values on all or certain sliders as a layer of future build complexity."
Recalling a shader at its defaults would mean re-dialling on stage, which is the thing the bank
exists to prevent.

The legacy cockpit spec (3,423 lines, `docs/arshader/legacy-cockpit/`) contains favorites, recents,
search, categories and type filters, and **zero** mentions of set lists, crates or playlists. There
is no prior art to port here; this is new design. Favorites and recents, which DO have prior art,
are deferred to 3c.

## Scope

**In:**
- `Preset` — a shader URL plus a `ParamSnapshot`.
- `SlotBank` — eight slots, capture / recall / clear, persisted across launches.
- A `PanelID.bank` rail panel presenting the bank.
- `ShaderUnit.sourceURL` — the loaded URL is currently discarded, so capture cannot be built
  without it.
- Extraction of load-to-target out of `LibraryPanelView` onto `Instrument`, **with the interface
  growth that requires** — this is not a same-behaviour lift and is its own task, not a line item
  inside another. See "The load seam".

**Out, deliberately:**
- **Capturing an FX chain.** A chain is an ordered list of stages each carrying its own parameters.
  That is a different primitive from a `Preset` and pretending otherwise would produce a slot that
  restores something other than what was captured. The SOURCE control offers decks only.
- **MIDI.** The seam is built and nothing binds to it. Binding is a later phase.
- **Naming, browsing and renaming presets** — phase 3c, together with favorites and recents.
- **Randomization** — later. It operates on a `Preset`'s values, which this shape already supports
  without change.
- **Slot counts other than eight.** Eight is one APC40 row. The count is a single constant so the
  full 8×5 grid is a later change of that constant plus a layout, not a change of model.

## Architecture

### `Preset`

```
struct Preset: Codable, Equatable, Identifiable {
    let id: UUID
    var name: String            // 3b: derived from the shader filename. 3c makes it editable.
    let shaderURL: URL
    let snapshot: ParamSnapshot
}
```

`ParamSnapshot` already exists in `App/ISFRuntime/ParamStore.swift`, is already `Codable`, already
tolerates a corrupt entry without failing the whole decode, and `ParamStore.applySnapshot` already
implements per-entry validate-and-clamp against the **live** header range. That last property is
what makes "the shader's parameters changed under a saved preset" a solved problem rather than a
risk this phase has to carry: a preset captured under an older, wider range clamps into the current
one instead of replaying out-of-range values into the engine.

`name` exists in 3b even though nothing edits it, because adding a stored property to a persisted
`Codable` type later is a migration and adding it now is free.

### `SlotBank`

A `@MainActor final class SlotBank: ObservableObject` **with no SwiftUI import**, following
`SurfaceLayout`'s doctrine from phase 3a: every invariant is then testable with no view in play,
which is the only kind of test that has been cheap on this surface.

```
static let slotCount = 8
@Published private(set) var slots: [Preset?]     // always exactly slotCount long

func capture(_ preset: Preset, into index: Int)
func recall(_ index: Int) -> Preset?             // nil when empty or unavailable
func clear(_ index: Int)
func isAvailable(_ index: Int) -> Bool           // false when the shader file has gone
```

`capture` takes a finished `Preset`, it does **not** take a `DeckID` and go fetch one. Reading a
deck's live parameters requires the `Instrument`, and a `SlotBank` that holds an `Instrument` is no
longer unit-testable without one — which would give away the property this design is built on.
Building the preset is the caller's job:

```
// on Instrument
func currentPreset(of deck: DeckID) -> Preset?   // nil when the deck has no shader loaded
```

`recall` likewise returns the preset rather than applying it. Applying needs the instrument and the
target. The model's entire surface is values in, values out.

### `SlotBankStore`

Shaped exactly like the `SurfaceLayoutStore` phase 3a shipped and tested — load returns a default
on any failure, save is a single `Codable` write. Writes happen on capture and clear, which are
discrete events; there is no debounce, unlike the panel-width drag that needed one.

`save()` must not swallow its own encode failure silently. Phase 3a's branch review found exactly
that in `SurfaceLayoutStore`, where an unencodable value would end persistence for the session with
no symptom until the next launch. This store asserts on encode failure in debug builds.

### `ShaderUnit` must retain the URL it loaded

`ShaderUnit.load(url:)` currently reads the file and forwards only `url.lastPathComponent` as a
display string; the `URL` is discarded on the same line. `shaderName` is all that survives. So
`currentPreset(of:)` has **no live source for the `shaderURL` half of its own return type**, and
capture as specified cannot be built.

Reverse-lookup through `LibraryModel` is not a substitute: filenames are not unique across the
corpus — the library list truncates in the *middle* precisely because "long AR_Genuary names differ
at the END" — and a shader may be loaded from outside the scanned folders entirely.

`ShaderUnit` gains `private(set) var sourceURL: URL?`, set in `load(url:)` and left nil for the
`load(source:name:)` path (which has no file behind it). This is a named file change, not an
incidental one.

### The load seam

`LibraryPanelView.load(_ url:)` is currently a **private method on a view**. It maps a URL plus a
`LibraryTarget` onto "replace deck A's shader" or "append a stage to master FX". A slot bank cannot
reuse a private view method, and a MIDI handler certainly cannot.

It moves onto `Instrument`:

```
func load(_ url: URL, onto target: LibraryTarget, thenApply snapshot: ParamSnapshot? = nil)
```

**This is not a pure refactor, and the spec must not pretend it is.** The interface grows a
parameter, and the growth is forced by a collision:

`ShaderUnit.onCompileFinished` is a **single-owner optional closure, not a multicast bus**, and
`LibraryPanelView.append` already permanently claims it on every FX-appended stage for
`chain?.stageDidChangeScene()` — an ongoing concern, not a one-shot. Layering snapshot-apply onto
the same hook means whoever assigns second silently drops the first: either the chain stops
republishing, or the snapshot never applies, depending on write order. That hits **three of the
picker's five segments** (`deckFX` ×2, `masterFX`).

It compounds: for FX targets the new `FXStage` and its `ShaderUnit` are created *inside* `load`, so
a `Void`-returning `load` leaves the caller no reference to the object it would need to hook.

So `load` itself owns the composition. It sets one `onCompileFinished` that chains
`stageDidChangeScene()` (FX targets only) and then the optional snapshot-apply, and **clears the
one-shot afterwards**. Without that clear, a later unrelated library load onto the same deck would
re-fire the stale closure and replay an old preset's values onto a shader they were never captured
from — the same "destroys state you didn't ask it to" failure the click-gesture rule exists to
prevent, relocated from a button to a hook.

Existing library behaviour is unchanged for existing callers: a deck target **replaces**, an FX
target **appends**, and `thenApply` defaults to nil.

**Accepted trade-off:** `load` always recompiles, even when the target already has that exact URL
loaded. Recalling the same slot twice — which a VJ does routinely to reset a knob mid-set — leaves
the deck playing its pre-recall values until the async compile lands and the snapshot applies. No
black frame (the compile-first-swap-on-success doctrine holds), but a visible window. Named here as
accepted rather than left to be discovered; a same-URL fast path that skips compile and applies the
snapshot directly is a later optimisation, not 3b.

## Behaviour

| Rule | Why |
|---|---|
| Recall fires into the load-target picker's current selection | One answer to "load onto what", shared by library clicks and slot hits. The operator plays both decks at once, so an "idle deck" auto-target has nothing to mean. |
| Capture reads from a separate two-segment SOURCE control (A / B) in the bank header | The picker means "where things go"; capture means "where this came from". They genuinely differ — sending library clicks to master FX while capturing deck A is a normal state. |
| **A click on a filled slot can only recall. It can never overwrite.** | Losing a dialled-in look mid-set to a one-cell mis-click is unrecoverable, and would happen exactly once before the bank stopped being trusted. |
| **Opening the bank ends show mode. Recall itself does not.** | Both halves matter and the first draft of this spec got it wrong — see "Show mode, honestly" below. |
| A slot whose file has gone shows as unavailable, does nothing when fired, and is **not** cleared | External drives come back. A silent no-op is wrong; auto-clearing is worse. |
| An empty slot invites capture; a filled one does not | The only click that can destroy state is the deliberate one. |

### Show mode, honestly

The first draft of this spec claimed "recall does not end show mode" as a safety property, in the
spirit of phase 3a's "configuration collapses, performance never does". On the surface as built,
that claim is **false**, and the test proposed to pin it **could not have failed**.

Phase 3a's `SurfaceLayout.select(panel:)` calls `endShowModeOverride()` unconditionally — by
design, and with an invariant test behind it, because opening Library mid-set has to end the show
rather than let a later `⌘⇧P` re-expand the whole pre-show arrangement. In 3b the *only* way to
reach a slot cell is to open the bank panel. So the show has already ended via the rail click that
got you there, before any slot is clickable.

And the proposed test — "exercise a bank recall against a live `SurfaceLayout` in show mode and
assert it survives" — was written against `SlotBank.recall(_:)`, which by this design holds no
`SurfaceLayout` and no `Instrument`. There is no path from `recall` to show mode for a mutation to
break. It is the same shape as the layout gate phase 3a shipped and its branch review had to
repair. Caught here by PM review instead of by a reviewer three weeks later.

What 3b actually ships:

- **Opening the bank ends show mode**, exactly like opening Library or Settings. Consistent, and
  no carve-out is invented for a case that does not yet exist.
- **`Instrument.load(_:onto:thenApply:)` must never touch `SurfaceLayout`.** This one IS falsifiable
  and IS tested: `Instrument` owns `surfaceLayout`, so `load` *could* reach it. The test puts the
  layout in show mode, calls `load`, and asserts `showMode` survives. Add an `endShowMode` call
  inside `load` and it goes red.
- The property becomes load-bearing when **MIDI** arrives, because a pad fires recall without
  touching the panel at all. That is the phase to revisit a `.bank` carve-out in `select(panel:)`,
  with its own justification and its own test — not now, on a path nothing can take.

### The exact gestures

Stated explicitly because "a distinct deliberate gesture" is not a specification.

| Slot state | Gesture | Result |
|---|---|---|
| Empty | click | Captures from the SOURCE deck. Nothing can be lost, so the cheapest gesture is the destructive-free one. |
| Empty | SOURCE deck has no shader loaded | Nothing happens, and the slot says so rather than capturing an empty preset. |
| Filled | click | **Recall.** Always. There is no state in which a plain click overwrites. |
| Filled | hover | Reveals two controls on the cell: **Replace** and **Clear**. Discoverable without a manual. |
| Filled | ⌥-click | Capture over, the fast path for the operator who already knows. Equivalent to hover ▸ Replace. |
| Any | — | No drag-to-reorder in 3b. Reordering implies the sequence model that the APC40 grid deliberately is not. |

The model exposes only `capture` / `recall` / `clear`. Which gesture invokes which is a view
concern and is tested at the view level only insofar as the phase 3a harness already renders the
panel; the *safety* property — that no code path calls `capture` on an occupied slot without an
explicit user act — is a code-review item, not a unit test, and is called out as such in the plan.

## Testing

`SlotBank` has no SwiftUI import and no `Instrument` reference, so all of this is a plain unit test:

- capture writes the source deck's shader and its current values into the given index
- recall of an empty slot returns nil
- recall of a filled slot returns the captured preset, values intact
- clear empties one slot and leaves its neighbours untouched
- a slot pointing at a missing file reports unavailable and recalls nil, and remains occupied
- the bank always has exactly `slotCount` entries, before and after every operation
- store round-trips a populated bank; a corrupt or absent file loads an empty bank rather than
  throwing
Four tests guard the load seam rather than the bank. These need an `Instrument`, so they are not
`SlotBank` tests — and that boundary is the point:

- `Instrument.load(_:onto:)` **replaces** on a deck target and **appends** on an FX target — the
  behaviour that was locked inside a private view method and had no test at all
- a preset's snapshot is applied **after** compile completes, not before
- an FX-target load with a snapshot **still republishes the chain** — the single-owner
  `onCompileFinished` collision, pinned. Assign only the snapshot handler and this goes red
- the one-shot is **cleared after firing**: load with a snapshot, then load again without one, and
  assert the second shader does not receive the first's values
- **`load` does not end show mode** — falsifiable because `Instrument` owns `surfaceLayout` and
  `load` therefore *could* reach it. Put the layout in show mode, load, assert `showMode` survives.

Note what is deliberately NOT tested: `SlotBank.recall` against show mode. `SlotBank` holds no
`SurfaceLayout` by design, so no mutation could make such a test fail. See "Show mode, honestly".

### Tests this phase must NOT write

Phase 3a shipped a layout gate that could not fail, and its own mutation evidence did not cover the
tests that shipped. Every test above must be checked against the mutation it claims to catch:
break the production behaviour, watch the named test go red, restore. A test whose mutation is not
demonstrated does not count as coverage for this phase.

## Risks

**The bank is the first tenant added to the phase 3a rail.** If adding `PanelID.bank` turns out to
cost more than one enum case plus a view, phase 3a's central claim was wrong and that is worth
knowing immediately rather than at phase 3c. This is a deliberate early test of the framework.

**Eight slots in a ~280pt panel is unverified.** The panel is resizable with a 260pt floor. Whether
eight cells with legible shader names fit at the floor is a layout question that will be answered on
device, not in this spec. The model is unaffected either way; `slotCount` is one constant.

**Capture from a deck mid-render.** `ParamStore.exportSnapshot()` returns user-set values only and
is a synchronous main-thread read, so there is no torn-state risk — but capture must be from the
deck's `ShaderUnit.params`, not from any view-local state.
