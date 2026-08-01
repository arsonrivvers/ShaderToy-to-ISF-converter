---
title: ARShader modulation and expression layer
date: 2026-08-01
status: design, approved in brainstorm — not yet planned
target_repo: ShaderToy-to-ISF-converter
slice: 1 of 4 (audio reactivity decomposition)
research_input: private prior-art research, kept outside this repo
---

# ARShader modulation and expression layer

The layer that lets any time-varying source drive any parameter of the instrument, with
per-destination shaping. Audio is its most important future consumer, but this slice contains no
audio code.

## 1. Scope

**In scope.** An expression engine, a source registry, a destination address space, evaluation and
ownership rules, failure containment, persistence of bindings, and a stub source (manual trigger,
LFO, tap) that is a real performance control rather than scaffolding.

**Out of scope.** Audio capture, FFT, onset detection, the band-tuning panel, MIDI, a beat clock,
and MCP authoring. Each is a later slice consuming this one.

**Non-goals.** No modulation of blackout, ever (§4.3). No per-route state in the engine (§2.2). No
multi-binding sum per destination (§6.2).

### 1.1 Why this slice is first

Audio reactivity decomposes into four subsystems: capture + features, detection, **routing**, and
the operator tuning surface. Routing is the part with the least prior art, the most product
consequence, and — because of the stub source — the only one that can be built, played with, and
signed off on device before any of the others exist. Building it against a stub also forces the
source interface to be genuinely provider-neutral, because at design time its only provider is a
button.

## 2. The model

An expression-per-destination model, taken from a prior-art system's expression design (see
prior-art research), with two additions.

Every writable destination may carry **one** compiled expression. Expressions read:

- `ref("<source>/<output>")` — a named source output
- `since("<source>/<output>")` — **addition**, see §2.2
- `valid("<source>/<output>")` — 1.0 when the source is live, 0.0 when stale or lost
- `time`, `dt`, `frame`, `self`
- math: `sin cos abs clamp min max sqrt floor ceil exp log pow`
- motion: `spring(t, m, k, c)`, `spring_v(t, x0, v0, m, k, c)`, `stagger(index, count, span, style)`,
  `anticipate(t, bias)`, `loop_noise(t, period, radius, seed)`

Expressions are stored as text, compiled on set, and are listable, gettable and clearable.
Renaming a source or destination **rewrites stored expressions** so references survive; delete and
recreate does not.

### 2.1 Targeting mode — addition

Each binding declares a mode:

| Mode | Behaviour |
|---|---|
| `absolute` | The expression *is* the value. The prior-art system's behaviour. |
| `offset` | The expression contributes on top of the operator's base value, clamped to the destination's range. |

Performance controls (deck opacity, crossfader, blend, FX wet/dry) default to `offset`.
Everything else defaults to `absolute`.

This exists because an expression that owns its destination outright leaves "operator grabs the
fader mid-set" undefined. `offset` makes the base always live, so a hand on the fader and a kick on
the envelope compose instead of fighting.

### 2.2 `since()` — addition

Expressions are stateless. Per-destination envelope shaping appears to need per-route state; it
does not. It needs one timestamp per source output.

```
since("audio/kick")   // seconds since that output's counter last incremented
```

Decay then becomes ordinary math, and every binding chooses its own:

```
exp(-since("audio/kick") / 0.002)   // 2 ms — strobe
exp(-since("audio/kick") / 2.0)     // 2 s  — slow swell
```

One source, many destinations, independent shaping, zero per-route state. It composes with the
motion vocabulary: `spring_v(since("audio/kick"), 0, 4, 1, 60, 6)` gives a physical bounce off the
same edge.

`since()` is defined for any output of kind `counter`. Before the first increment it returns the
time since the source was registered. It is monotonic within a frame and never negative.

## 3. Sources

A registry of named providers, each publishing named outputs. Every output declares:

| Field | Purpose |
|---|---|
| `kind` | `continuous` (0..1), `counter` (monotonic), `scalar` (unbounded/dB), `phase` (0..1 wrapping) |
| `range` | Declared bounds, for UI and clamping |
| `value` | Current value |
| `valid` | Live vs stale/lost |
| `age` | Seconds since last real update |
| `provenance` | Which provider, for display and diagnostics |

This is the provider-neutral contract the prior-art dossier argues for, instantiated. Audio, MIDI,
OSC, a beat clock and future sensors all publish through it without engine changes.

### 3.1 The stub provider

Ships in this slice and stays permanently:

| Output | Kind | Notes |
|---|---|---|
| `manual/trigger` | `counter` | A button. Increments on press. A legitimate live control — hitting it on the downbeat is a real technique, and it gives `since()` envelopes with no audio. |
| `manual/lfo` | `continuous` | Rate and shape (sine, triangle, saw, square), phase-integrated per §5.2. |
| `manual/tap` | `phase` | Tap tempo. Publishes 0..1 beat phase and holds last tempo when tapping stops. |

Anything publishing `counter` gets `since()` shaping for free, so a MIDI note and a kick drum
behave identically downstream.

## 4. Destinations

Three address spaces:

```
deck.<a|b>.input.<isfInputName>          shader inputs, via ParamStore
deck.<a|b>.fx.<stageID>.<paramName>      per-deck FX chain
master.fx.<stageID>.<paramName>          master FX chain
mixer.crossfader                         instrument controls
deck.<a|b>.opacity | .blend
```

### 4.1 FX stages are addressed by stable ID, never by index

Phase 2 made FX chains stackable and reorderable. `deck.a.fx.2.amount` silently rebinds to a
different effect the moment the chain is reordered, with no error anywhere — a kick would begin
driving an unrelated parameter and nothing would report it.

Every FX stage therefore carries an identifier assigned at insertion, stable across reorder,
persisted with the chain. Bindings address that ID. This is the same defect class as phase 3b's
`sourceURL` riding the swap and `unload()` failing to clear it, both of which cost fix rounds; the
cost of designing it out here is one field.

### 4.2 Shader inputs may disappear, and bindings survive it

Loading a different shader on a deck changes its input set. A binding whose input no longer exists
is **retained and reported skipped**, not deleted — swapping the original shader back restores it.
This reuses the applied/skipped semantics phase 3b built for preset recall, deliberately, so the
instrument has one story about bindings that cannot currently resolve.

### 4.3 Blackout has no address

Phase 3a made blackout structurally unreachable from show mode — no `SectionKey`, no `PanelID` —
rather than promising not to touch it. The same reasoning applies with more force to modulation: an
expression that can kill the output mid-set is a defect with no upside. Blackout is not in the
destination registry, by construction rather than by convention.

## 5. Evaluation

### 5.1 One snapshot per frame

All expressions evaluate once per frame against a single frozen generation of source values, before
the render pass. Without this, two destinations bound to the same source can read it a frame apart
and visibly drift — a sync failure that presents as a detector problem and is not one.

### 5.2 Clock

`time` and `dt` come from the app-owned render clock, not wall clock, so pause behaves and a shader
recompile does not restart motion. Rate-driven motion integrates phase (`phase += rate * dt`)
rather than multiplying a live rate by absolute time, so a rate change does not discontinuously
jump the phase.

### 5.3 Cycles read the previous frame

An expression referencing a destination that is itself driven reads **last frame's** value. One
frame of latency is imperceptible; the alternative is a cycle detector that rejects a patch
mid-set, which is a worse failure than 16 ms of lag. Deterministic, and requires no explanation to
the operator.

## 6. Ownership

### 6.1 A driven control is visibly driven

In `offset` mode the base is always live and no conflict exists.

In `absolute` mode the destination displays as driven, and a gesture on it is **ignored, not
silently clearing the driver**. An explicit "clear driver" affordance sits with the control. Silent
clearing destroys work that cannot be recovered; silent ignoring is merely confusing, and the
visible driven state resolves the confusion.

### 6.2 One expression per destination

Combining sources happens inside the expression. This keeps the ledger answerable — "what drives
this?" always has exactly one answer — and avoids unbounded summation across bindings.

## 7. Failure doctrine

**Stale or lost source.** Outputs publish a defined idle value — `0` for `continuous`, frozen for
`counter`, last value for `phase` — and flag `valid = false`. Expressions may branch on
`valid(...)`. Decaying to idle rather than freezing is deliberate: a frozen shader reads as a
broken app, a still one reads as stopped music, and only the second is true.

**Non-finite results are contained at the engine boundary.** NaN and infinity never reach a Metal
uniform. The destination holds its last finite value and the binding is flagged. A NaN in a uniform
produces a black frame or undefined GPU behaviour with no error anywhere, which is the most
expensive bug class on this render path.

**Out of range** is clamped at the destination in both modes, using its declared range.

**Compile failures are stored, not dropped.** A malformed expression remains saved and inactive
with its error visible. Losing a half-written driver to a fat-fingered paren is unacceptable in a
live tool.

## 8. Persistence

Persisted: base values, expression text, target mode, and the enabled flag.

Never persisted: evaluated output.

**Modulated values bypass the persistence and UI-update paths entirely** and flow straight to the
render path. Phase 3a already had to debounce a `UserDefaults` write per drag frame; routing
modulated output through that path would reproduce that bug at 60 Hz on every bound parameter
simultaneously.

Bindings save and recall with the same applied/skipped reporting as §4.2.

## 9. Testing

The engine is a pure function — `evaluate(bindings, snapshot, dt) → [destination: value]` — with no
audio, GPU, view or Metal dependency, mirroring `SurfaceLayout`'s shape from phase 3a.

### 9.1 Mutation-proven gates

This project has twice nearly shipped tests that could not fail (phase 3a's layout harness, phase
3b's `/tmp/a.fs` fixture and its snapshot-timing assertion). Each gate below ships with the
mutation that must break it, demonstrated:

| Gate | Mutation that must make it fail |
|---|---|
| `since()` decay shape | Change the time constant |
| Frame coherence | Re-read a source mid-frame |
| NaN containment | Remove the guard |
| `offset` ownership | Let `offset` write the base |
| Skipped bindings | Delete on shader swap instead of retaining |
| FX stable IDs | Address by index instead of ID, then reorder |
| Cycle latency | Read same-frame instead of previous-frame |

The FX stable-ID gate is written first. It is the defence against the §4.1 trap.

### 9.2 Performance budget

Evaluating 64 bound routes must cost under **0.5 ms per frame** (3% of a 16.6 ms budget), measured
rather than assumed. Exceeding it moves evaluation off the render thread.

### 9.3 On-device gate

This slice has no protocol boundary — no external API, no hardware, no shell — so correctness is
covered in-process and the device gate is about musicality, not function:

1. A 2 ms decay reads as a strobe; a 2 s decay reads as a swell.
2. Grabbing an `offset`-driven fader feels live, not fought.
3. Grabbing an `absolute`-driven control reads as driven rather than broken.
4. Frame budget holds with the full route set bound.
5. The manual trigger, hit on the beat, is genuinely performable.

Legs 1–5 run with no audio subsystem in existence.

## 10. Open questions

1. **Curve vocabulary.** `exp()` decay is assumed throughout. Whether operators want named curve
   helpers (`decay(since, tau, shape)`) on top of raw math is a UX question best answered after
   leg 1.
2. **Route creation gesture.** A learn-style "touch the parameter, then the source" flow is the
   likely entry point, but it is a surface decision belonging to the tuning-panel slice.
3. **Binding scope.** Whether bindings belong to the instrument globally, to a slot-bank preset, or
   both, interacts with phase 3b's `Preset` and is deferred to the persistence review.

## 11. Provenance

Taken from the prior-art system: expression-per-destination, `ref()` addressing, the motion
function vocabulary, rename-safe reference rewriting, list/get/clear operations, the
provider-neutral output contract, and the publish-idle-on-loss doctrine.

Ours, because the prior-art system does not answer them: `since()`, targeting modes, ownership on gesture,
cycle semantics, FX stable-ID addressing, NaN containment at the boundary, and the persistence
bypass.

From EssentiaTD (AGPL — measurements only, no code): the discipline that analysis parameters must
be justified by measurement rather than taste. Its window-size findings bear on the detection
slice, not this one.
