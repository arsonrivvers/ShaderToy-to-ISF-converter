---
schema_version: 1
topic: native-performance-instrument
date: 2026-07-30
tier: just-me
status: complete
correlation_id: arshader-native-pivot-20260730
supersedes_platform_decision_in: docs/superpowers/specs/2026-07-23-td-native-pivot-isf-player-design.md
target_repo: ~/Desktop/AV_Projects/ShaderToy-to-ISF-converter
---

# Native macOS Performance Instrument — Milestone 1

## 1. The decision

AR_Shader moves from the TouchDesigner build to a **native macOS performance app** built on the
TrueISFEditor codebase. This is the operator's decision, made 2026-07-30, and it reverses the
2026-07-23 pivot *to* TouchDesigner.

**TouchDesigner is parked cold.** Not run in parallel, not kept as a live fallback. Section 12
covers leaving it recoverable, which is a requirement of parking it, not a hedge against the
decision.

The trigger was the operator's first live look at the cockpit shell. The stated motivation is
twofold: TouchDesigner's native UI is not visually acceptable for the instrument they want, and
the browser cockpit — chosen to solve that — introduced an architecture whose feature velocity
is poor. Every feature crosses four surfaces (TD Python, a frozen protocol contract, a code
generator, and Svelte) with a security review at the boundary.

## 2. Why this is cheaper than it looks

The 2026-07-23 pivot to TouchDesigner was justified on the grounds that TD shrank "the risky core
to one component — the ISF player." That reasoning no longer applies, because the risky core is
already solved somewhere else.

**TrueISFEditor renders ISF 2.0 through ISFMSLKit — the Metal engine used by VDMX6.** It is the
reference implementation for the exact host family this instrument replaces, it is already
integrated (`MetalRenderCore.swift` imports it), it ships as vendored prebuilt frameworks, and it
is **MIT licensed** with every dependency permissive: VVMetalKit BSD, ISFGLSLGenerator BSD,
glslang MIT/BSD/Apache, SPIRV-Cross Apache, PINCache Apache. No AGPL anywhere.

By contrast the TouchDesigner path runs a custom marcinbiegun-derived translator at 856/947
shaders (90.4%) with known unresolved gaps (IMPORTED textures, V1 multi-buffer assignment,
precision qualifiers, 33 still-dark shaders).

**On the riskiest component, native is ahead of TouchDesigner, not behind.**

### 2.1 What is genuinely lost

Not the engine — the integration dividend. TouchDesigner supplied Syphon out, movie recording,
MIDI, and window/display management essentially free. Swift can do all of these (Syphon SDK,
AVFoundation, CoreMIDI, NSScreen) but each becomes work this project owns.

Also lost: the audio layer. EssentiaTD is AGPL-3.0 and TouchDesigner-bound, so audio analysis is a
genuine native rebuild (FFT, onset detection, tempo). It is **not** in Milestone 1.

Also lost: the cockpit protocol contract, the Svelte shell, and cockpit Tasks 1–7. The *design
thinking* in those documents ports — particularly the fail-closed safety model and the
base-value/effective-value modulation semantics, both of which this spec reuses. The TypeScript
does not.

## 3. Verified architectural facts

Established by reading the TrueISFEditor source on 2026-07-30. These are load-bearing.

- **`MetalRenderCore` already separates rendering from presenting.** It takes `device` and
  `renderQueue` by injection, so instances can share one GPU context, and exposes
  `renderOnce(drawableSize:) -> MTLTexture?` — a scene rendered to a texture with no view
  attached. `draw(in view: MTKView)` is a separate blit-with-aspect-fit layered on top.
- **`ImageSource` is a protocol**: `func texture(size: MTLSize, in cb: MTLCommandBuffer) ->
  MTLTexture?`. `MetalRenderCore` binds routed sources into a scene's image inputs *inside the
  same command buffer*, so a source renders before the filter that reads it. Command-buffer
  ordering for texture inputs is already solved.
- **`DisplayLinkDriver` is per-`MTKView`** and creates its own `CVDisplayLink`. This is the one
  editor-shaped piece: a performance app needs one clock driving all decks, not N independent
  links. Because `renderOnce` is view-independent, this is a rewiring, not a rewrite.
- **The codebase is healthy.** 302 kit + 227 app tests green, CSO verdict SHIP, 69 of 83 cleanup
  items closed. It also already contains a pixel-verification harness (`PixelGate`,
  `FramePixelStats`, `FramePNGEncoder`, headless capture) directly reusable for compositor
  verification.

## 4. Milestone 1 scope

**"Playable at home"** — the operator drives the instrument by hand for an hour and reports what
is wrong with it. This milestone deliberately excludes audio and MIDI.

In scope:

- two decks, each with opacity and a blend mode
- crossfader as a macro over deck opacity
- monitor viewports (deck A, deck B, master)
- shader library and auto-generated per-shader controls
- blackout / panic
- a deliberately minimal UI

### 4.1 Why the milestone is this small

The operator's stated first-show requirement was nearly the full TouchDesigner feature set
(everything except presets). That was deliberately reduced, for a reason grounded in this
project's own history:

**The TouchDesigner build's failure mode was that a great deal got built before anything got
played.** Phase A is CONFIRMED because the operator watched it run. Phases B and C — the mixer,
blackout, source routing, scenes, and the entire audio layer — are STAGED: built, tested,
reviewed, and never performed with. Defining Milestone 1 as "everything needed for a show"
reproduces that pattern in a new language.

The UI is the specific thing at risk. It is the operator's primary motivation for the pivot, and
designing it before they have played with the instrument would design it against imagination.

## 5. Repo structure

Work happens in `~/Desktop/AV_Projects/ShaderToy-to-ISF-converter`.

A new Swift package, `ISFRuntimeKit`, holds what both apps need: `MetalRenderCore`, `RenderClock`,
`DisplayLinkDriver`, `ImageSource`, `SourceRouter`, `BlitFit`, and the ISF input/control model.
TrueISFEditor is refactored to import it. A new app target — the performance instrument — imports
the same package. One source of truth for the ISF runtime; no duplicated vendored frameworks.

The editor's existing 227 app + 302 kit tests are the evidence that the extraction was
behavior-preserving. The extraction is not complete until they pass unchanged.

**Hard prerequisite: the extraction must not begin while the Codex session active in that repo on
2026-07-30 is still working.** It moves files the editor depends on, and that session had
uncommitted changes (`TrueISFEditorApp.swift`, `App/project.yml`) and untracked files
(`CaptureInputPlan.swift`, `CaptureInputPlanTests.swift`) in flight. Two writers on one checkout
is the collision the operator's standing rules exist to prevent.

## 6. Render architecture

**One clock for the instrument.** A single `DisplayLinkDriver` drives one frame for everything.
The per-view display-link model stays with the editor.

Each frame, within one command buffer:

1. Deck A renders offscreen to a texture.
2. Deck B renders offscreen to a texture.
3. The compositor blends them into the master texture (section 7).
4. The blackout gate runs (section 8).
5. The master is presented to the output surface.

Monitor viewports draw the deck and master textures that already exist. There is no readback, no
encode, no frame budget and no cost governor — the entire problem class that made the browser
cockpit expensive does not exist in this architecture.

Master resolution is fixed at 1920×1080 with pooled textures, so steady-state rendering performs
no allocation.

## 7. Layer stack and blending

A deck is `{ shader, opacity, blendMode, inputs }`. Decks composite in order onto the master.

**The master begins each frame as opaque black** (RGBA 0,0,0,1). Deck 1 composites onto that,
deck 2 composites onto the result. This is stated explicitly because it determines what a blend
mode blends *against* on the bottom layer — with no shader loaded on deck 1, or with deck 1 at
zero opacity, the output is black rather than undefined. An empty instrument shows black, never a
stale or uninitialized frame.

Blend modes are implemented in MSL from the **W3C Compositing and Blending specification**. They
are not extracted from any installed commercial application. If reference implementations are
wanted, Vidvox's separately published open ISF library may be consulted subject to its own
license; the blend math itself is standard and published, and does not require it.

The compositor is hand-written Metal rather than an ISF filter. This was chosen over an
ISF-shader mixer because the mixer is load-bearing: an ISF mixer that fails to compile leaves the
instrument with no output at all. A compiled Metal pipeline cannot fail at shader-load time.

### 7.1 Crossfader semantics

The crossfader is a macro over deck opacity, not a separate signal path:

```
effectiveOpacity(deck) = userOpacity(deck) × crossfadeWeight(deck, x)
```

with deck 1 weighted `1 - x` and deck 2 weighted `x`, for crossfader position `x ∈ [0,1]`.

Both values are real and **both are displayed** — the operator always sees the fader they set and
what it is actually contributing. No control silently overwrites another. This is the
base-value/effective-value pattern already established and approved in the TouchDesigner
Bindings design, reused deliberately.

The model extends to three or more decks without redesign; only the weighting function changes.

## 8. Blackout

Blackout is **not** a blend mode, not a shader, and not a stage in the compositor. It is a final
gate that clears the master to opaque black before present.

It must be structurally incapable of depending on anything that can fail to compile or load. The
same rule governs failure generally: if the compositor pipeline cannot be built, the output is
black, never garbage or a stale frame.

Behavior: latching plus momentary hold, keyboard-reachable at all times, and reachable regardless
of what any panel or drawer is doing. This carries the fail-closed model from the TouchDesigner
`SafetyState` work, which is the most valuable thing that build produced.

## 9. Shader loading

Compile first, swap only on success. A failed compile must never reach the output and must never
interrupt the shader already running. This ports Phase A's hitchless-swap lesson rather than
rediscovering it.

The library points at `/Library/Graphics/ISF` — the authoritative 947-file `AR_` corpus. Library
browsing and auto-generated per-shader controls carry over from TrueISFEditor substantially
intact.

Filter shaders keep TrueISFEditor's current source-routing behavior: camera with test-pattern
fallback. Deck-to-deck routing is out of scope for Milestone 1.

## 10. Testing

- Blend math, crossfade weighting, and layer-stack ordering are pure functions and are unit
  tested.
- Composited output is verified by golden-frame tests through the existing headless capture path.
- The "never unintentionally black" pixel gate built for the converter transfers directly to the
  instrument, and is the primary defense against the silent-black-output class this project has
  hit repeatedly.
- The editor's existing suites must pass unchanged after the `ISFRuntimeKit` extraction.

## 11. UI

Deliberately minimal for Milestone 1: decks, faders, blend dropdowns, library, monitors, blackout.
No visual design ambition, no theming, no motion work.

The interface the operator actually wants is designed **after** they have played with this one.
That sequencing is the entire point of the milestone (section 4.1) and is not an invitation to
"just make it nice while we're in there."

## 12. Parking TouchDesigner

Committing fully to native requires leaving the TD build genuinely recoverable, or "parked cold"
silently becomes "unrecoverable":

- Resolve the 20 uncommitted TouchDesigner files currently in the AR_Shader working tree.
- Record the terminal state: Phase A CONFIRMED, Phases B and C STAGED, cockpit Tasks 1–7
  complete, Task 8 planned but unstarted.
- Note the running instance discrepancy found 2026-07-30: TD was running `ARShader.31.toe` while
  git tracks `ARShader.toe`. Resolve before the final save, or the parked state is not the state
  in the repository.
- `/project1/Output` has `allowCooking = False`, so the master Syphon output is currently dead.
  Record it so a future reader does not mistake it for a bug in the parked build.

## 13. Non-goals for Milestone 1

Audio reactivity, MIDI learn, Syphon out, movie recording, scenes and presets, deck-to-deck
source routing, and more than two decks. The layer-stack model and render graph are built so that
additional decks are additive rather than a redesign, but no more than two are implemented.

## 14. Open questions

1. The name of the performance app target and its bundle identifier.
2. Whether `ISFRuntimeKit` should also absorb the editor's `EditorViewModel`-adjacent control
   generation, or whether the instrument needs its own per-deck control model. Resolve during
   extraction, when the actual coupling is visible.
3. Audio analysis approach for Milestone 2 — Essentia is AGPL and unavailable; Accelerate/vDSP is
   the likely permissive path. Not decided here.
