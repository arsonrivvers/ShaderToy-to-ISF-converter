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
- Extraction of load-to-target out of `LibraryPanelView` so that recall, library clicks and (later)
  MIDI all go through one call.

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

### The load seam

`LibraryPanelView.load(_ url:)` is currently a **private method on a view**. It maps a URL plus a
`LibraryTarget` onto "replace deck A's shader" or "append a stage to master FX". A slot bank cannot
reuse a private view method, and a MIDI handler certainly cannot.

It moves onto `Instrument`:

```
func load(_ url: URL, onto target: LibraryTarget)
```

`LibraryPanelView` calls it. `SlotBankPanelView` calls it. A future MIDI handler calls it. This is
the whole reason to extract now rather than when MIDI arrives — recall must not be something that
exists only inside a `Button` closure.

Behaviour is unchanged by the move: a deck target **replaces** its shader, an FX target **appends**
a stage. The extraction is a pure refactor and the existing library behaviour must be provably
identical afterwards.

Recall applies the preset's snapshot after the shader loads. Loading is asynchronous (the scene
compiles), so the snapshot is applied on compile completion via the existing
`ShaderUnit.onCompileFinished` hook that `LibraryPanelView.append` already uses — not immediately
after the `load` call, where the parameters would not yet exist to receive it.

## Behaviour

| Rule | Why |
|---|---|
| Recall fires into the load-target picker's current selection | One answer to "load onto what", shared by library clicks and slot hits. The operator plays both decks at once, so an "idle deck" auto-target has nothing to mean. |
| Capture reads from a separate two-segment SOURCE control (A / B) in the bank header | The picker means "where things go"; capture means "where this came from". They genuinely differ — sending library clicks to master FX while capturing deck A is a normal state. |
| **A click on a filled slot can only recall. It can never overwrite.** | Losing a dialled-in look mid-set to a one-cell mis-click is unrecoverable, and would happen exactly once before the bank stopped being trusted. |
| **Recall does not end show mode** | Phase 3a's rule is that a deliberate *layout* action ends a show. Firing a slot is a *performance* action, like the crossfader. Sibling of "configuration collapses, performance never does". |
| A slot whose file has gone shows as unavailable, does nothing when fired, and is **not** cleared | External drives come back. A silent no-op is wrong; auto-clearing is worse. |
| An empty slot invites capture; a filled one does not | The only click that can destroy state is the deliberate one. |

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
- **recall does not mutate `SurfaceLayout.showMode`** — pinned falsifiably, by exercising a bank
  recall against a live `SurfaceLayout` in show mode and asserting it survives

Two tests guard the refactor rather than the feature:

- `Instrument.load(_:onto:)` replaces on a deck target and appends on an FX target — the behaviour
  that was previously locked inside the view and had no test at all
- a preset's snapshot is applied only after compile completes, not before

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
