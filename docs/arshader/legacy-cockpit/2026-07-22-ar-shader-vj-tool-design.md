> ℹ️ **LARGELY REALIZED, NOT SUPERSEDED.** This is the *original* native-macOS design, written
> before the 2026-07-23 detour into TouchDesigner and revalidated by the 2026-07-30 return to
> native. Milestones 1 and 2 built its core: `EngineCore`, `SceneSlot`, the compositor, `FXChain`,
> `BlackoutGate`, `LibraryService`, `SourceRouter`, `ParamStore`, and the CVDisplayLink render loop.
> Its still-unbuilt components read as a roadmap: `AudioService`, `ControlBus` (MIDI learn + LFO),
> `PresetBank`, `SyphonPublisher`, `Recorder`. Treat §3 as accurate architecture and §5/§9 as
> forward-looking. Ported from `AV_Projects/AR_Shader` on 2026-07-31.

# AR_Shader — Custom ISF VJ Instrument (v1 Design)

**Date:** 2026-07-22 · **Status:** Approved design, pre-plan · **Owner:** Conner Jones (Arson Rivvers)

## 1. Purpose

A pro-grade native macOS VJ performance app to tour with instead of VDMX/Resolume. All visual sources and effects are the artist's own ISF shaders — generators (ReactionDiffusion, GOL MetaCellular, HyperTesseract, Devolution series, …) and filters (HallofMirrors series, GLitcher, …). Success = a full set performed live on this instrument with no fallback rig.

**Non-goals (v1):** shader authoring/editing (TrueISFEditor owns that), Shadertoy conversion, Windows support, AI performance modes, media/video-file layers, projection warping.

## 2. Performing model

Mirrors the artist's current VDMX rig (screenshot reference: `AV_Projects/AR_ISF-Tool/CleanShot 2026-07-14…png`):

```
DECK A                    DECK B
[ISF generator]           [ISF generator]
[deck FX chain: ISF]      [deck FX chain: ISF]
        \                    /
         [ CROSSFADER (macro over 2 slots) ]
                    |
         [ MASTER FX chain: ISF ]
                    |
         [ output map/fit ] → [ BLACKOUT GATE ] → drawable
                                      └→ Syphon publish / recorder tap
```

The engine is an N-slot layer stack from day one; the v1 UI exposes it as A/B decks + crossfader. Crossfade is *not* a special case in the engine (per the converter ROADMAP's own design note) — it is a UI macro mapping one control to two slots' opacities.

## 3. Architecture

- **One native process** (SwiftUI, macOS 13+, Apple Silicon-first). Two windows: **control surface** and **output** (borderless fullscreen on a chosen `NSScreen`; floating preview when single-display). No IPC layer — shared process state; the null-signal dual-window *pattern* survives, its Electron/IPC implementation does not.
- **Render loop** owned by the output path: `CVDisplayLink` off-main thread (lifted `DisplayLinkDriver` pattern), `RenderClock` per slot (swap-surviving), `RenderStats` (fps + GPU-ms, surfaced on the control window at all times).
- **ISF hosting** via vendored ISFMSLKit + VVMetalKit (the VDMX6 engine; MIT/BSD/Apache — no reuse constraints). Bootstrap identical to TrueISFEditor: shared `MTLDevice`/queue via `RenderProperties.global()`, `VVMTLPool.global`, `ISFMSLCache.primary`, and **all compiles through the crash-contained `ISFMSLSafeCreateAndLoad`** on a background queue with generation-counter supersession.

### Components

| Component | Responsibility | Origin |
|---|---|---|
| `EngineCore` | SceneSlot array → offscreen textures → composite pass → master FX → map/fit → blackout gate → blit; Syphon/recorder taps | New (assembled from lifted parts) |
| `SceneSlot` | One compiled `ISFMSLScene` + clock + per-slot params + image-input routing | Lift: MetalPreviewController/MetalRenderCore, restructured |
| `Compositor` | Single Metal pass blending N slot textures (opacity + blend mode) | New; blend math ported from null-signal `composite.js` |
| `FXChain` | Ordered ISF filters, output→input; fader-as-hard-gate per effect (0 = fully bypassed) | New; gating pattern from null-signal |
| `BlackoutGate` | Multiply-to-black at the last pre-drawable stage; works even if a shader hangs | Port of null-signal hold-to-blackout, relocated below FX |
| `AudioService` | AVAudioEngine input tap → vDSP FFT → `audio`/`audioFFT` textures; band/AGC/kick/BPM/tap-tempo analysis | New; analysis math ported from null-signal |
| `ControlBus` | Slot-based MIDI learn; LFO engine; single mutation surface into state | MIDI-learn design from null-signal; LFO is **new build** |
| `LibraryService` | Scans user-configured ISF folders + `~/Library/Graphics/ISF`; header-level input metadata | Lift: LibraryModel + ISFHeader parser |
| `PresetBank` | Capture/recall full `SceneState`; banks of slots; output geometry excluded | Pattern from null-signal, new codec |
| `SyphonPublisher` | Publishes final texture as Syphon server | New (Metal server API — see §8 verification) |
| `Recorder` | AVAssetWriter path from final texture | New |
| `SourceRouter` | Image-input routing for filter-type inputs: camera, test patterns, other slots; **never-black** fallback policy | Lift as-is |

### State model

One versioned, `Codable` **`SceneState`** schema — the explicit fix for null-signal's convention-only state (4 hand-synced functions over ~30 closure variables). Rules:

- Single mutation surface: UI, MIDI, LFO, and preset recall all go through the same setters.
- Render thread reads an immutable per-frame snapshot (lock or double-buffer at the slot boundary, as in `MetalRenderCore`).
- Presets serialize `SceneState` minus output geometry; output mapping has its own memory slots (both prior rigs converged on this — projector geometry must survive preset changes).
- Per-shader params are name-keyed (`ParamStore` model lifted from the converter) so presets survive shader edits gracefully (unknown keys dropped with a logged warning, missing keys take shader defaults).

## 4. Failure doctrine (PM-mandated, designed-in not retrofitted)

| Failure | Behavior |
|---|---|
| Panic | Blackout gate: hold-to-black (momentary) + latching toggle; both MIDI-learnable and on-screen; sits below master FX so it works with a hung/runaway shader |
| Output display disconnect | Output falls back to on-control-display preview window; auto re-acquires the external display on reconnect; render never stops |
| Shader compile failure / crash | Crash-contained compile; slot keeps running its previous scene (never-black); error surfaced on control window |
| Audio device dropout | Hold last analysis values + audio textures; visible flag; auto-reattach on device return |
| MIDI controller disconnect | Screen controls remain fully operable; mappings persist; hot-reattach |
| Texture-pool pressure | Render-size caps + Phase 0 soak gate (§6); pool housekeeping only at quiescent points |

## 5. Lift manifest

**From `ShaderToy-to-ISF-converter` / TrueISFEditor (engine substrate, ~50–60% of engine plumbing, field-tested — owner directive: lift as much of this engine as possible, verbatim where possible):** the standing posture is **port the file as-is and keep its name**; deviate only where the N-slot compositor forces it. Lift list: ISFMSLSafeCreateAndLoad compile path (incl. transpile queue + generation-counter supersession) · `DisplayLinkDriver` · `HostAwareMTKView` window-membership pause logic · `RenderClock` · `RenderStats`/`RenderStatsAccumulator` · `BlitFit` + the runtime blit pipeline (`makeBlitPipeline` format-handling) · `PreviewEngine`/`PreviewCoordinator` seam (Metal side only; WebKit engine dropped) · `OutputWindow` manager as the starting point for the fullscreen output controller · render-size controls (`setRenderSize`, 1920×1080 default) · `ImageSource`/`SourceRouter`/`CameraSource` (+ `SharedCamera`) · `ISFSceneSource` (shader-feeds-shader — the seed of FX chaining) · `TestPatternCatalog` + `ISFHeader` (extracted into a small module; rest of ShadertoyISFKit stays behind) · `LibraryModel` scanning · `ParamStore` · `vendor/prebuilt` frameworks + `build-isfmslkit.sh`. **The one deliberate restructure:** `MetalRenderCore`'s single-`ISFMSLScene` ownership becomes the `SceneSlot` array + composite pass; its existing separation of "render scene to texture" from "blit to drawable" is the seam that makes this additive rather than a rewrite.

**From `null-signal` (instrument layer):** dual-window pattern · slot-based MIDI learn · fader-as-hard-gate/knob/button FX shaping · audio analysis math (FFT bands, 4s AGC window, kick refractory + spectral-flux fallback, BPM estimation, tap tempo with synthesized kick) · blackout · preset-bank UX · `composite.js` blend math (12 modes + strobe) · `post.js` FX (split into individual ISF filters: feedback, burn, jitter, scan, dither, ink, mirror-folds, wind, sort, chroma, brightness/contrast — reusable in VDMX as a bonus).

**Explicitly not inherited:** null-signal's monolith structure, p5 modes, Electron/IPC runtime; TrueISFEditor's editor UI, ShaderAssist, Remix Studio, import pipeline.

**Untapped:** `VJ_Code-crossfade` (Offspring Engine) — unreviewed this session (active peer session in that repo). Fold in its crossfade/Syphon-shell lessons before Phase 0 implementation if accessible.

## 6. Build phases (engine-first vertical slice — approved)

Every phase ends **on-device, STAGED until Conner confirms** (two-state doctrine; no phase is "done" from tests alone). One change at a time on the render path; revert before stacking on a broken state.

- **Phase 0 — Engine risk spike.** Starts by importing the §5 TrueISFEditor engine files verbatim (compile-clean in the new app target before any new code). Then: 2–4 concurrent scenes → offscreen → composite → fullscreen output on chosen display, with blackout gate and display-failover included. **Numeric exit gate:** 30-min soak, 4 concurrent scenes with hot shader swaps, sustained ≥60fps @1920×1080, GPU headroom ≥20%, dropped-frame count flat, no VVMTLPool crash. Pre-flight assertions and live-smoke steps named in the plan (protocol boundaries: display acquisition, pool behavior).
- **Phase 1 — Instrument core.** Deck UI (A/B strips, crossfader, blend), library browser + auto-generated param controls, SceneState + presets. First performable milestone = end of Phase 1 (includes blackout from Phase 0).
- **Phase 2 — FX chains.** Per-deck + master ISF filter chains with hard-gate faders; port the post.js FX set to ISF filters (each verified on-device against the null-signal original).
- **Phase 3 — Audio.** AVAudioEngine tap → FFT textures + band/kick/BPM/tap; audio-reactive params; dropout handling. Live smoke with real devices (mic, BlackHole/loopback).
- **Phase 4 — MIDI.** Slot-based learn, hardware smoke with Conner's controllers, disconnect handling.
- **Phase 5 — LFO/automation** (new build; sequenced late deliberately so slips can't jeopardize the performable core).
- **Phase 6 — Syphon + recorder.** Publish + AVAssetWriter recording; live smoke into VDMX/OBS as Syphon client.

Each phase gets its own written plan + `/gate` manifest before execution; CS live UX review at Phase 1 and Phase 4 milestones; Mechanic review = manual CoS code audit (native Metal project exception).

## 7. Testing

- Unit: SceneState codec, preset round-trips, MIDI map, LFO math, FX gate shaping, audio band math (pure parts).
- On-device gates per phase (§6), STAGED→CONFIRMED.
- Live smoke as *named plan tasks* for every protocol boundary: display hot-plug, audio device hot-plug, MIDI hot-plug, Syphon client handshake, recorder file validity.
- Soak tests re-run before any tour deadline (the Phase 0 soak becomes a reusable harness).

## 8. Verified facts & open items

**Librarian verification (2026-07-22, primary sources — all three GO):**

1. **Syphon:** `SyphonMetalServer` is first-class (`publishFrameTexture:onCommandBuffer:imageRegion:flipped:`, thread-safe, `hasClients` for skip-when-unwatched). BSD license. **Vendor from `main` source** (the 2019 "SDK 5" zip predates the Metal BGRA fix, commit `2dc6d319`). Transport is IOSurface forced to **32BGRA**.
2. **ISFMSLKit:** our vendored pin `cac7d662` **is upstream HEAD** (repo dormant since 2026-05-12) — no drift. MIT, unchanged. `audio`/`audioFFT` are host-supplied textures (confirmed — we render FFT/waveform into textures and bind). **Decision (default taken, Conner may veto):** the vendored VVMetalKit submodule is 8 commits behind its master; the delta includes off-thread render-state atomicity, buffer-pool hardening, and `VVMTLSurfaceImage` (MTLBuffer↔CVPixelBuffer bridge — useful for Syphon/recorder). **Phase 0 stays on the field-tested pin** (change-one-thing); if the soak gate fails on pool behavior, fast-forwarding VVMetalKit (clean fast-forward, verified) is the first remedy to try. One-time license-notice retention pass over the glslang subtree before any commercial distribution.
3. **Recording:** AVAssetWriter + AVAssetWriterInputPixelBufferAdaptor is the current non-deprecated path; 32BGRA `CVPixelBuffer`s from the adaptor pool wrapped via `CVMetalTextureCache` (zero-copy); color-space attachments mandatory; `expectsMediaDataInRealTime`, honor `isReadyForMoreMediaData`, monotonic PTS; keep the CVMetalTexture wrapper alive until command-buffer completion.

**Design consequence (binding, applies from Phase 0):** the master composite texture is **`.bgra8Unorm` with an explicit sRGB policy** — one master texture feeds screen blit, Syphon publish, and the recorder with no format re-plumb in Phase 6.

**Open items:**
1. **Offspring Engine review** — blocked on peer session (§5).
2. **App name** — working title "AR_Shader"; decide before first release build.
3. **null-signal has no git repo** — recommend `git init` there independently of this project (its GLSL is a lift source).

## 9. v1.1 futures (performance candy — deliberately deferred)

SCENE-QUENCER (BPM-driven 8-step preset sequencer) · VSN1/Intech Grid bridge (module lifts as-is when wanted) · AI modes (ORACLE/INTERPRETER/LISTEN + audio-caption sidecar — the whole null-signal LLM layer is p5-free and portable) · media bin / video-file + camera layers as deck sources · NDI out · projection warping / multi-output · accent-palette color system as global ISF uniforms · per-slot z-zoom crop macro · output test patterns.
