---
schema_version: 1
topic: cockpit-dynamic-decks-and-live-monitors
date: 2026-07-30
tier: just-me
status: complete
correlation_id: arshader-cockpit-decks-monitors-20260730
amends: docs/superpowers/specs/2026-07-24-ar-shader-adaptive-cybernetic-cockpit-ui.md
---

> ⛔ **SUPERSEDED 2026-07-30, the same day it was written.** Later that session the operator
> decided to park the TouchDesigner build cold and move AR_Shader to a native macOS app built on
> the TrueISFEditor codebase. See `2026-07-30-native-performance-instrument-design.md`.
> **Do not implement anything in this document.** It is retained because its findings are still
> true and still useful — particularly §3 (Video Stream Out TOP is Nvidia+Windows only) and the
> verified fact that the frozen protocol's `deckId` was never restricted to four decks.

# Cockpit Amendment: Dynamic Deck Count and Live Program Monitors

## 1. What we're building

Three separable changes to the Adaptive Cybernetic Cockpit, arising from the operator's
first live review of the Task 7 static shell on 2026-07-30.

1. **Dynamic deck count.** The cockpit stops assuming four decks. It renders whatever
   decks the authoritative snapshot advertises, defaulting to two, and gains a third or
   fourth with no code, type, or protocol change when a slot is activated in
   TouchDesigner.
2. **Live program monitors.** Three low-resolution, real-time-as-possible video monitors
   — deck 1, deck 2, and master out — inside the cockpit, each independently freezable
   and switchable off to reclaim resources.
3. **Fluid layout.** Replace the single hard breakpoint with a layout that scales to the
   viewport, optimized for the operator's laptop display.

This document amends the 2026-07-24 cockpit specification. That specification's
"four deck cards" and "dominant program monitor" language is superseded by sections 4
and 5 below. Everything else in it — the three modes, the semantic control contract,
the fail-closed safety model, the never-fake-a-capability rule — is unchanged and
remains binding.

## 2. Why this is not a preference change

Two of the three items correct defects rather than adjust taste.

The four-deck assumption was never an engine fact the operator asked for; the instrument
has four slots because Phase A benchmarked four players. The operator performs with two.
Encoding "four" into the cockpit's type system would have hardcoded a benchmark artifact
into the performance surface.

The missing monitors are a genuine capability gap. The operator cannot currently see
what is loaded on the off-air deck, nor confirm master output non-visually, without
looking at the projection. For an instrument whose stated purpose is replacing VDMX on
tour, that is a functional regression against the tool being replaced.

## 3. Verified platform constraints

These were confirmed against Derivative documentation on 2026-07-30 and are load-bearing
for section 5. They are recorded here because the obvious solution is unavailable and a
future reader will otherwise propose it again.

- **`Video Stream Out TOP` cannot be used.** The documentation states it "uses the Nvidia
  Hardware Encoder to create the stream and therefore requires an Nvidia GPU and Windows
  to operate." The deployment machine is macOS. This eliminates WebRTC, RTSP, RTMP and
  SRT video-out entirely, including the otherwise-ideal WebRTC-to-browser path.
- **The available path is CPU-side frame extraction.** `TOP.saveByteArray(filetype,
  quality=1.0, metadata=[])` returns a `bytearray` and supports `.jpg`. `TOP.numpyArray(
  delayed=False, writable=False)` documents `delayed` as avoiding "stalling the GPU
  waiting for the result immediately," and always returns floating point regardless of
  GPU texture format.
- **Readback cost scales with pixels read, not pixels rendered.** A GPU-side downscale
  ahead of the tap is therefore the primary cost control, not an optimization.

## 4. Dynamic deck model

### 4.1 Behavior

The cockpit renders one deck card per entry in the snapshot's `decks[]` array, in
snapshot order. Two decks is the default exposure, not a constant. Activating a third
slot in TouchDesigner causes a third card to appear with no client change.

The crossfader continues to map deck 1 to A and deck 2 to B, which is the engine's
current fixed behavior. Any decks beyond the first two are manual-contribution, matching
the language already in the implementation plan. The cockpit does not invent dynamic A/B
assignment; that remains a named future capability.

### 4.2 Type safety

`DeckId` is a branded string type. The only way to obtain one is:

```ts
asDeckId(raw: string, snapshot: InstrumentState): DeckId | null
```

which returns `null` unless `raw` matches a deck present in the authoritative snapshot.
No cast, template literal, or raw string may produce a `DeckId`.

This **replaces** the plan's `DeckId = '1' | '2' | '3' | '4'` union, and is strictly
stronger. The union accepted `'3'` at compile time even when deck 3 did not exist; the
branded type rejects any id the live engine does not advertise. The plan's required
`@ts-expect-error` cases — `0`, `5`, an arbitrary string, and an OP path — all still fail
to compile.

The wire protocol requires no change. `deckId` in `protocol-contract-v1.json` is already
a generic constrained string (`^[A-Za-z0-9._:-]{1,64}$`) and `decks` is already an array,
so the frozen v1 contract accommodates this without an epoch bump.

### 4.3 Tests

- A deck id validated from a two-deck snapshot is accepted; `'3'` from the same snapshot
  is rejected at runtime and unavailable at compile time.
- Compile-time rejection of `0`, `5`, arbitrary strings, and OP paths (retained from the
  plan).
- Rendering a three-deck snapshot produces three cards with no code change.
- A deck disappearing from the snapshot removes its card and invalidates any held id.

## 5. Live program monitors

### 5.1 Sources and tap points

Three monitors:

| Monitor | Source | Tap point |
|---|---|---|
| Deck 1 | Deck 1 output | Pre-blackout |
| Deck 2 | Deck 2 output | Pre-blackout |
| Master out | Master output | **Post-blackout** |

**Master out taps after the blackout gate.** "Master out" must mean what the audience
sees. A master monitor showing video while the room is dark is a false readout of engine
state, the same defect class as the fabricated recorder telemetry deleted on 2026-07-30.
Blackout therefore blacks the master monitor, which doubles as visible confirmation the
blackout landed. Deck monitors remain pre-blackout so the operator can still see what
they would be restoring.

### 5.2 TouchDesigner side

Each tap terminates in a GPU-side downscale to tile resolution before any readback, so
a monitor frame moves a small fraction of a 1080p frame: 256×144 is 1/56th the pixels of
1920×1080, and 240×135 is exactly 1/64th. Bytes are produced only in response to a
request. No monitor work runs inside a WebSocket receive callback. All monitor work
combined is bounded by a hard per-frame budget.

**The budget value is set from the spike result, not chosen in advance.** The spike
measures what monitors actually cost; the plan then states the budget as an explicit
millisecond figure derived from the 60fps frame envelope, with the render's requirement
taking precedence. Until that number exists, no monitor rate is implemented.

Resolution is quantized to a small set of fixed steps. Layout changes select a step;
they never drive continuous TOP reallocation.

### 5.3 Client side

Each monitor is independently in one of three states:

- `LIVE` — requesting frames at the governed rate.
- `FROZEN` — displaying the last received frame, **visibly and unmistakably labeled as
  frozen**, requesting nothing.
- `OFF` — displaying nothing, requesting nothing.

A stale frame presented as live is a fabricated readout and is prohibited by the same
rule that governs telemetry. The frozen label is a correctness requirement, not a
convenience.

### 5.4 Cost governor

A hard combined frame-time budget for all monitors. On pressure the governor degrades
monitor frame rate, then freezes monitors, before the render is affected. It states
on-screen that it throttled and why. Manual `FROZEN`/`OFF` always overrides the governor;
the governor never un-freezes what the operator froze.

The render is never a variable the governor is permitted to trade against.

### 5.5 Transport: decided by measurement

Two candidate transports remain open. The decision is made by a spike against the real
engine, with criteria pre-registered here so the result cannot be rationalized afterward.

**Candidate A — client-pull JPEG over HTTP.** The client requests each frame at its own
rate. `FROZEN` and `OFF` are the absence of a request, so an unwatched tap is not
demanded and does not cook — zero cost rather than reduced cost. Backpressure is
inherent. Reuses the validated-JPEG-over-HTTP pattern already specified and security
reviewed for library thumbnails (MIME, length, JPEG signature, revision).

**Candidate B — MJPEG (`multipart/x-mixed-replace`) server push.** The browser renders
it natively in an `<img>`, giving the smoothest picture for the least client code.
TouchDesigner drives the rate, placing backpressure on the producing side; freeze
requires connection teardown; three long-lived responses interact with a connection and
lease model not designed for them.

**Rejected — binary frames over WebSocket.** The protocol explicitly refuses binary
frames, a property verified in Task 5's CSO gate. Adding a binary lane means new attack
surface and a full fresh security review for no benefit the other two lack.

**Spike protocol.**

- Both candidates, three monitors, 256×144, against the real engine **under realistic
  shader load** — an idle engine flatters both and invalidates the result.
- Measured: render frame-time delta against baseline, dropped render frames, monitor
  frame rate actually achieved, subjective smoothness.
- **Decision rule:** highest sustained monitor frame rate at zero dropped render frames
  and render frame-time impact within budget. On a tie, Candidate A, for the free
  freeze/off semantics and the security-pattern reuse.
- If neither fits the budget at 256×144, that is a valid outcome: monitors ship at
  reduced frame rate or at lower resolution as a confidence view. No monitor rate ships
  unmeasured. This mirrors the discipline the plan already applies to `library.reindex`,
  which must be measured before being advertised.

### 5.6 Security

The monitor route is a new HTTP route serving image bytes and therefore requires a CSO
review under the standing rule, with no velocity bypass. Items for that review:

- Whether observer (non-controller) connections may view monitors. Provisional position:
  yes, monitors are read-only, but this is the reviewer's call.
- Route construction from validated identifiers only; no unvalidated value reaches an
  `<img src>`.
- Loopback-only binding, consistent with the existing servers.
- Resource-exhaustion behavior when a client requests faster than the budget allows.

### 5.7 Tests

- A frozen monitor issues no requests and is labeled frozen.
- An off monitor issues no requests and its tap does not cook.
- Governor degradation is observable and explained in the UI.
- Manual freeze survives governor activity.
- Blackout blacks the master monitor and does not black the deck monitors.
- Malformed, oversized, wrong-MIME and stale-revision frames never become an image
  source.
- Zero connected monitors produce zero monitor cooking.

## 6. Fluid layout

Replace the single `max-width: 1359px` breakpoint with a layout that scales continuously,
optimized for the operator's laptop display as the primary target while holding together
across a range of viewports.

Monitor tiles size to available space and select a quantized readback resolution step
accordingly. Existing hit-target minimums (44px) and the compact side-sheet drawer
behavior established in Task 7 are preserved; this is a scaling change, not a
re-architecture of the shell.

## 7. Non-goals

- No dynamic A/B deck assignment. Still a named future capability.
- No engine change to slot count. Slots 3 and 4 remain in the instrument, unexposed.
  Whether idle slots cost anything is measured, not assumed, and any removal would be a
  separate task with its own gate.
- No full-motion or full-resolution program monitor. The operator specified 1/4 to 1/8
  scale.
- No visual redesign toward the reference art materials. The operator noted the current
  shell does not resemble them and explicitly deferred this.
- No recorder telemetry. Still blocked on real Movie File Out state at Task 14.

## 8. Sequencing

| Order | Work | Gate |
|---|---|---|
| 1 | Dynamic deck model, folded into Task 8 | Task 8's existing live smoke |
| 2 | Monitor transport spike | Measurement result recorded before any build |
| 3 | Monitor subsystem (Task 8b) | CSO review + live smoke |
| 4 | Fluid layout (Task 8c) | Client Success review |

Monitors are deliberately not folded into Task 8. Task 8 already wires six adapters and
eight components; adding a security-reviewable route, a GPU readback path and a cost
governor would mean a failed live smoke could not isolate which subsystem broke it.

## 9. Open questions

1. Observer access to monitors — settled by the CSO review (5.6).
2. Whether idle slots 3 and 4 have measurable cost — measured during Task 8, informs
   nothing in this spec but may spawn a separate task.
3. Reference-art visual direction — deferred by the operator, not addressed here.
