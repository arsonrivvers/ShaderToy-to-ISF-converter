# ARShader Milestone 2, phase 3a — the panel framework

**Date:** 2026-07-31
**Status:** DESIGN — approved by the operator, not yet planned or built.
**Extends** the Milestone 2 phase 2 instrument (`e3ca357`).
**Supersedes nothing.** The platform-superseded cockpit UI spec
(`docs/arshader/legacy-cockpit/2026-07-24-ar-shader-adaptive-cybernetic-cockpit-ui.md`) is the
design source for Appendix A's geography and Appendix D's component behaviour; nothing in its
Svelte/`ControlBridge` delivery applies.

Sources: Milestone 1 live smoke findings 4 and 5
(`docs/reports/live-smoke-instrument-m1.md`), and the operator's brainstorm answers of 2026-07-31.

---

## 1. Why phase 3 is two phases

M1 finding 4 asked for a collapsible library and "a button-driven slide-out panel system like
TrueISFEditor." Finding 5 asked for a library that is genuinely useful for show prep. In
brainstorming, the operator widened both:

- The panel is not a library container. It is **a host for tools later phases will add** — settings
  now, and on the 2026-07-22 roadmap `AudioService`, MIDI-learn and LFO, `PresetBank`,
  `SyphonPublisher` and `Recorder`, each of which wants its own surface.
- "Useful for show prep" means **set lists** — named, *ordered* collections a performer builds for
  a booked show, the way a DJ builds a crate. Not a filter over whatever folder a file sits in.

Those are two independent subsystems. The panel framework is layout and UI state. Set lists are a
new persisted data model with their own failure modes — a set list that silently drops a shader
renamed last week is worthless, and you find out on stage.

**This spec covers the panel framework only (phase 3a).** Set lists, favorites and recents get
their own spec (phase 3b) after 3a is confirmed on device. The order is not arbitrary: the library
panel is a *tenant* of the panel host. Building set lists first means building their UI twice, once
in today's fixed column and again inside the rail.

**A type badge (generator vs filter) is explicitly deferred** past both phases. `LibraryModel` is
deliberately content-lazy — it enumerates names and file dates and never parses the ~1,500 files —
and a type badge needs every header parsed. That is its own piece of work, and the operator ruled
it a later feature.

## 2. What we're building

Four full-height regions, left to right:

```
┌────┬──────────────┬────────────────────────────────────────┬─────────┐
│RAIL│ PANEL        │  MONITORS  (flexible height)           │ MIXER   │
│ 44 │ 280, resiz.  │  ┌────────┬────────┬────────────────┐  │ 200     │
│    │              │  │ DECK A │ DECK B │   PROGRAM      │  │         │
│ ▤  │  LIBRARY     │  └────────┴────────┴────────────────┘  │xfader   │
│ ⚙  │              ├────────────────────────────────────────┤preview% │
│    │              │  DECK A strip │ DECK B strip │ MASTER  │cue %    │
│    │              │  ▾ SOURCES    │ ▸ SOURCES    │ ▾ FX    │stats    │
│    │              │  ▾ FX      3  │ ▾ FX      0  │         │BLACKOUT │
│    │              │  ▸ PARAMETERS │ ▾ PARAMETERS │         │         │
└────┴──────────────┴────────────────────────────────────────┴─────────┘
      ↑ closes entirely when
        no rail icon is active
```

Today's surface is `VStack { monitors(maxHeight: 260); HSplitView { library | deckStrips | mixer } }`
— everything visible always, nothing collapsible.

### 2.1 The monitor row must become flexible

Today the monitor row is pinned at `.frame(maxHeight: 260)` and the deck strips take the rest.
**That inverts.** The monitor row takes whatever vertical space the deck strips are not using, with
a floor; the deck-strip row sizes to its content.

This is load-bearing, not cosmetic. It is the mechanism by which collapsing a section hands its
height to the picture. Without it, collapsing a section leaves grey space and the operator's first
stated pain — "monitors are too small" — is untouched no matter how much collapses.

### 2.2 The rail

A 44pt column of icons, one per available panel, full window height at the far left. Day one: two
icons, `library` and `settings`.

**The rail itself is always visible.** It is a fixed 44pt column and never hides — including in
show mode. Only the panel beside it opens and closes. A rail that could disappear would leave the
operator with no way back to a tool except a keyboard shortcut they may not remember mid-set.

- Click an icon: that panel opens.
- Click the icon of the panel that is already open: the panel closes entirely and its width goes to
  the rest of the surface. The rail stays.
- Click a different icon: the open panel swaps; width is unchanged.
- `⌘⌥1` … `⌘⌥9` select by rail position. `⌘⇧P` toggles show mode.
- Panel width is draggable, with a 260pt minimum, and is remembered.

Adding a tool in a later phase is one enum case and one view. It costs no layout renegotiation and
no screen space when closed, which is the whole reason for a rail rather than a set of fixed
regions.

### 2.3 What collapses, and the rule

**Configuration collapses. Performance never does.**

Inside a deck strip, `SOURCES`, `FX` and `PARAMETERS` collapse to a header row. The deck name, the
loaded shader name, opacity and blend do not — they are performance controls, the same category as
the crossfader. The master strip's `FX` collapses on the same terms.

This is the same line the mixer/settings split draws (§2.4), applied one level down, so there is one
rule to remember rather than two lists.

**A collapsed header carries a count or a summary:** `▸ FX 3`, `▸ PARAMETERS 12`,
`▸ SOURCES cam→in0`. Collapsing hides detail; it never hides the fact that detail exists. This is a
direct response to the phase-2 defect where a disclosure triangle opened onto nothing — the failure
mode of a collapsible surface is a control the operator cannot find, and a bare header with no
count is that failure mode by design.

### 2.4 The settings panel, day one

`OUTPUT RES` — the typed W×H, its presets menu, and the megapixel readout — moves off the mixer
strip into the settings panel. It is set at load-in, not mid-song.

**Three controls deliberately stay on the mixer strip**, because each is reached for at a bad
moment when a panel-open gesture is the wrong cost:

- `PREVIEW SCALE` and `CUE SCALE` — what the operator drops when the GPU is struggling during a
  set.
- The **`OUTPUT` destination picker.** This one reverses an earlier draft of this spec, on evidence
  from the Milestone 1 live smoke that the draft cited as its own source. Leg 17 is *"Unplug
  mid-set"* and leg 18 is *"Reconnecting and **re-selecting the display** restores fullscreen
  output"* — so re-selecting the display is a mid-set action, performed in the one scenario where
  the operator is already dealing with a failure on stage. Putting it behind a rail click plus a
  panel open is the same mistake the scales rule avoids. Only the *configuration* of output size
  moves; choosing where the picture goes stays one click away.

Legs 15–18 have never run on hardware, so this is reasoned from the smoke report's own wording
rather than from felt experience; if running them shows the picker is genuinely never touched
mid-set, moving it later costs nothing.

### 2.5 Show mode

`⌘⇧P`, plus a button. Entering: snapshot the current arrangement, collapse every section, close the
panel. The freed height goes to the monitors by §2.1.

`⌘⇧P` again restores the snapshot exactly.

**Any deliberate layout action while in show mode switches show mode off immediately and the
current arrangement stands**, discarding the snapshot. That means *both* collapsing or expanding a
section — the operator needs DECK A's FX mid-song — *and* opening, closing or swapping a panel from
the rail. So an untouched round trip restores, and a deliberate action is never silently thrown
away. These are separate testable invariants rather than one ambiguous one (§5).

**The rule has to cover panel selection because §2.2 deliberately keeps the rail live during a
show** so a tool stays reachable mid-set. Without it there is a stage-grade trap: enter show mode,
open Library from the rail to swap a shader, then press `⌘⇧P` expecting it to tidy up — and instead
of closing the panel it fires the *restore* branch and re-expands the entire patch arrangement
mid-song. The one entry point §2.2 argues for would be the one entry point the §2.5 guarantee did
not cover. One rule, both doors: **a deliberate layout action ends the show-mode override.**

## 3. Architecture

### 3.1 `SurfaceLayout` owns all of it

```swift
enum PanelID: String, CaseIterable, Codable { case library, settings }   // grows later

enum DeckSection: String, Codable { case sources, fx, parameters }

enum SectionKey: Hashable, Codable {
    case deck(DeckID, DeckSection)
    case masterFX
}

/// The whole restorable arrangement: what show mode snapshots, and what persists across launches.
struct Arrangement: Codable, Equatable {
    var openPanel: PanelID?
    var expanded: [SectionKey: Bool]
    var panelWidth: Double
}

@MainActor final class SurfaceLayout: ObservableObject {
    @Published var openPanel: PanelID?          // nil == panel closed
    @Published var expanded: [SectionKey: Bool]
    @Published var panelWidth: Double
    @Published private(set) var showMode: Bool
    private var snapshot: Arrangement?          // taken on entering show mode
}
```

`Arrangement` is the unit of both snapshot and persistence — the same value is written to
`UserDefaults` and held for show-mode restore, so the two can never diverge in what they consider
"the arrangement."

One observable object, not a scatter of `@State` booleans inside views. Three reasons, in order of
weight:

1. Show mode has to save and restore *all* of it atomically. Per-view `@State` cannot be snapshotted.
2. It is the unit under test. Every invariant in §5.1 is exercised with no view in play, which is
   the only kind of test that has ever been cheap on this surface.
3. It is the thing that persists across launches — one `Codable` value, not N `@AppStorage` keys
   that can drift out of sync with each other.

`SectionKey` carries the `DeckID`, so collapsing deck A's FX cannot collapse deck B's. That is a
tested property (§5.1), not a convention.

### 3.2 Where it lives

`App/ARShader/SurfaceLayout.swift`, alongside `MixerState` and `FXChain`. It is instrument UI
state, not runtime — it must not go in `ISFRuntime`, which TrueISFEditor also compiles.

Owned by `Instrument`, injected into `InstrumentView` as an `@ObservedObject`, exactly as
`MixerState` is today.

### 3.3 Blackout is structurally outside this

Blackout is not a `SectionKey`, is not a `PanelID`, and lives in the mixer strip, which does not
collapse and is never behind a panel. Show mode cannot reach it because it has no representation in
`SurfaceLayout` at all. That is structural rather than a promise, and §5.1 asserts it.

### 3.4 Rail implementation

A plain custom rail: `PanelID` enum, one selection value, panel content switched in a `Group`.

Rejected: `NavigationSplitView` — its sidebar is a *list*, not an icon rail that swaps tools, and
its system chrome fights a dark instrument surface. Rejected: the macOS `.inspector()` modifier —
wrong side, single-purpose, and not extensible to N tools.

The custom rail is small and the app owns every pixel, which matters because later phases add
HUD-style tools to it.

## 4. What does not change in 3a

- **Visual treatment.** 3a is structure only, with the current plain styling. Appendix C's
  "Adaptive Cybernetic Cockpit" art direction is a separate pass, done against a surface that has
  stopped moving — the same reasoning that held panels until the feature set settled.
- **The library panel's contents.** Search, sort, the five-way load-target picker and the flat list
  move into the panel unchanged. Set lists, favorites and recents are phase 3b.
- **The render path.** Nothing in this spec touches the render thread, the compositor, the FX
  encode path, or any published render mirror. It is a view-layer and view-state change only.
- **`FXChainView` and `ShaderControlsView` internals.** They gain a collapsed representation; what
  they render when expanded is untouched.

## 5. Testing

### 5.1 `SurfaceLayout` unit tests — no views

1. **Round trip is identity.** Enter show mode, exit with no intervening edit; every section flag
   and the open panel equal their pre-entry values.
2. **Edit in show mode exits and preserves.** Enter show mode, toggle one section; `showMode` is
   false, that section holds its new value, every other section stays collapsed, and a subsequent
   exit does not resurrect the snapshot.
2b. **Opening a panel in show mode exits and preserves.** Enter show mode, `select(panel:)` from
   the rail; `showMode` is false, the panel is open, every section stays collapsed, and a later
   `⌘⇧P` collapses-and-closes rather than restoring the pre-show arrangement. Without this
   invariant the trap in §2.5 is invisible to the suite — none of the other invariants name the
   `select(panel:)`-during-show transition.
3. **Persistence.** Encode, decode, compare — an arrangement survives a relaunch.
4. **Panel toggle semantics.** Selecting the open panel closes it; selecting a different one swaps
   without closing.
5. **Per-deck independence.** Collapsing deck A's FX leaves deck B's FX untouched.
6. **Blackout is not in the collapse set.** No `SectionKey` case addresses the mixer strip, and
   entering show mode leaves `MixerState.isBlackedOut` unchanged.

### 5.2 Screenshot baselines, mutation-tested

Phase 3a is entirely layout, which is precisely the defect class that has reached the operator
three sessions running: a `ScrollView` nested in a `ScrollView` collapsing to zero height, source
dropdowns lost among sliders, a 56pt button slab. 181 green tests said nothing about any of them.

Baselines for six states: panel closed, library open, settings open, all sections expanded, all
sections collapsed, show mode.

**Each baseline set is mutation-tested before it is trusted.** Specifically: revert §2.1's flexible
monitor height and confirm the show-mode and all-collapsed baselines go red. A baseline suite that
has never failed on a deliberate break is decoration, not a gate.

Follow the `visual-regression-baselines` skill.

### 5.3 Live smoke on device

Numbered legs in the plan, run and signed by the operator. At minimum: the panel opens, closes and
swaps by icon and by keyboard; each section collapses and its count stays readable; show mode
collapses everything and `⌘⇧P` restores it; editing a section in show mode exits it and keeps the
edit; the monitors visibly grow as sections collapse; `⌘B` and Escape still black out with a panel
open and in show mode; the arrangement survives a relaunch.

## 6. Failure modes

| Failure | Why it is plausible here | Mitigation |
|---|---|---|
| A collapsed section becomes unfindable | The whole feature hides controls | Header always carries a count or summary (§2.3); show mode is visibly indicated |
| Collapsing frees space that nothing uses | Today's fixed 260pt monitor cap | §2.1 makes the monitor row flexible; a baseline pins it (§5.2) |
| Show mode discards a mid-set edit | Snapshot restore is blind by default | Editing in show mode exits it and keeps the edit (§2.5), tested (§5.1 #2) |
| Blackout ends up behind a panel | Panels are new and full height | Blackout has no representation in `SurfaceLayout` (§3.3), asserted (§5.1 #6) |
| A new deck inherits another's collapse state | Shared section flags | `SectionKey` carries `DeckID`, tested (§5.1 #5) |
| Keyboard shortcut collision | `⌘B`, Escape, `⌘⇧F` already bound | `⌘⌥1`…`⌘⌥9` and `⌘⇧P` chosen clear of all three; smoke leg confirms |

## 7. Out of scope

- Set lists, favorites, recents, source-folder grouping — phase 3b.
- Generator/filter type badges — deferred past 3b (§1).
- Appendix C art direction — separate pass (§4).
- PERFORM/PATCH/SYSTEM modes from Appendix A.3. Show mode is one toggle over one arrangement, not
  three modes with different geographies. If modes are wanted later they compose on top of
  `SurfaceLayout`; nothing here forecloses them.
- Moving the FX chains out of the deck strips. The operator's answer was in-place collapse, which
  keeps at-a-glance state and moves nothing already learned. This closes the phase-2 handoff's open
  question.
- Named saved layouts. Considered and declined in favour of one show-mode toggle; revisit alongside
  `PresetBank`.

## 8. Open questions

1. **Rail icon set.** SF Symbols are the obvious source and cost nothing, but a VJ instrument rail
   at 44pt with two icons today and six later may want drawn glyphs. Deferred to the art-direction
   pass; SF Symbols in 3a.
2. **The panel remembers which tool was open across launches** — `openPanel` is part of
   `Arrangement` (§3.1) and persisted with it. Recorded here because the alternative (always launch
   closed, for the biggest picture on open) is defensible and this is a one-line flip once the
   operator has lived with it. Not a blocker; the spec decides "remember."
