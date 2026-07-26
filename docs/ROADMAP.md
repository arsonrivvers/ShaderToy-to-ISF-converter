# TrueISFEditor Roadmap — v-next and beyond

_Source: full diagnostic review, 2026-07-17 (four parallel read-only subsystem reviews: conversion
pipeline, render/preview path, app layer + AI assist, VJ-readiness gap analysis; top findings
spot-verified in code). Scope decision by Conner, same day: **this app stays an ISF editor** —
no Syphon, no audio FFT, no MIDI/OSC/BPM/live-performance features here. Those belong to the
future custom VJ app (Part 3), which will use this app's design and render stack as its baseline._

## Verdict snapshot

Strong: the Metal render stack (off-main CVDisplayLink loop, crash-contained shader loading,
per-frame source routing, GPU stats) is production-grade and carries straight into the future VJ
app. The conversion pipeline is disciplined and regression-tested (~350 kit tests). The AI-assist
layer is cleanly seamed and security-hardened.

Weak: app-layer data safety (three verified bugs, Phase A), and the param/value model — input
values live as view-local SwiftUI `@State`, which causes today's worst product bug and blocks
presets, write-back, and the VJ app's automation layer (Phase B).

---

## Phase A — Data safety (do first)

| # | Item | Evidence |
|---|------|----------|
| A1 | **Clear CodeMirror history on document switch.** Undo bleeds across documents: open A, open B, ⌘Z reverts to A's text inside B's document; ⌘S then corrupts B's file. | `Resources/code-editor.html:36` (`setText` never resets history) |
| A2 | **Unsaved-changes guard on quit.** No `applicationShouldTerminate` anywhere; ⌘Q silently destroys edits. | grep-verified zero hits |
| A3 | **Fingerprint the Diagnose & Fix flow.** The stale-apply guard derives `expectedContains` from the *current* source at apply time — a tautology; fix results also survive document switches and can apply into the wrong shader. Fingerprint at generation time (like suggestions/apply already do) + reset assist state on `documentGeneration` change. | `EditorScreen.swift:184` |
| A4 | **Surface save failures loudly.** Save errors go only to the 5s auto-clearing status toast; a failed save into read-only `/Library/Graphics/ISF` is nearly invisible. Alert or persistent error affordance. | `EditorViewModel.swift:182-189` |

## Phase B — The keystone: ParamStore + scene continuity

**B1 — Extract a ParamStore.** Move shader input values out of `PreviewControlsView` `@State`
dictionaries into an observable model between the UI and `PreviewCoordinator.setInput`.
This single refactor:
- fixes silent value-revert on every recompile (scene rebuilds at header defaults while
  sliders keep showing dragged values — the core authoring loop lies to the user)
- fixes the pop-out output window never receiving param edits or event pulses
- unlocks presets, write-back-to-header, automation, and (future app) MIDI/OSC mapping
- makes param behavior unit-testable at all

**B2 — Time + param continuity across recompiles.** App-owned pausable `RenderClock` in
`MetalRenderCore` driving `ISFMSLSafeRenderAtTime` (survives scene swaps) + ParamStore value
replay after `applyCompile`. Kills the animation-restart flash on every keystroke. _Mechanism
decision 2026-07-17 (PM review): NOT `loadURL:resetTimer:NO` on the live scene — that runs a
full synchronous transpile under the render lock (per-edit hitch) and abandons the
validate-first crash containment. **Persistent-buffer contents still reset on recompile** —
explicit deferral; revisit as an opt-in "reload in place" if feedback-shader authoring demands
it. Reset becomes an explicit control (see D-transport)._

**B3 — Pop-out parity.** Route ParamStore changes + event pulses to the output window's
controller; stop double-transpiling (share the compile or forward the compiled scene).

**B4 — Engine housekeeping (same area, cheap):** cap `doubleRenderSize()`; pause render while
the window is miniaturized/occluded; fix `ISFSceneSource.lastGood` aliasing a pool-recycled
texture. _Pool `housekeeping()` DEFERRED (2026-07-17): calling it on compile/size-change crashed
the full test suite — trimming the shared VVMTLPool races other live controllers' render threads
holding in-flight pooled textures (inline + pop-out + nested-ISF render concurrently in
production too). Needs a globally-quiescent hook (e.g. all drivers paused) before it's safe;
the memory ratchet remains a known issue mitigated by the size cap._

## Phase D — Authoring UX (the "best ISF editor" tier)

Ranked by payoff:

0. ~~**Pop-out editing mode**~~ **LANDED (Plan 2, 2026-07-17, STAGED).** `setPaused` through the
   `PreviewEngine`/`PreviewCoordinator` seam + published `OutputWindowManager.isOpen` +
   `EditorViewModel.popOutEditing`; preview pane collapses, panel expands, banner with Restore
   Preview, FPS readout follows the pop-out.
1. ~~**Version snapshots.**~~ **LANDED (Plan 2, 2026-07-17, STAGED).** `SnapshotStore` (bounded,
   deduped, per-doc folders) + `ParamSnapshot` codec (validate-and-clamp per the null_signal
   preset doctrine); auto-capture on open/import and before every AI apply; versions list
   (⌘⌥V) with diff + restore, restore itself captured.
2. ~~**Real diff in the apply preview.**~~ **LANDED (Plan 2, 2026-07-17, STAGED).** `LineDiff`
   (LCS + folding) + `DiffView`, reused by the apply preview and versions list.
3. **Still-image + movie-file input sources.** New `ImageSource` conformers
   (MTKTextureLoader / AVPlayerItemVideoOutput → CVMetalTextureCache — mirror
   `CameraFrameProvider`). Filter authoring against real footage.
4. **Preview transport.** Pause / scrub / restart time, explicit feedback-buffer reset,
   FRAMEINDEX reset. Pairs with B2 (continuity makes reset *opt-in*).
5. **Preview resolution scaling.** 0.5×/0.25× multiplier before the blit; heavy ray-marchers
   become editable at 60fps.
6. **Movie export.** Deterministic offline render via the existing `ISFMSLSafeRenderAtTime`
   pixel-gate path → AVAssetWriter. Non-realtime frame stepping (see movie-export doctrine —
   never realtime capture).
7. **Write-current-values-to-header.** ParamStore → new `DEFAULT`s in the JSON header via
   `HeaderAuthoringModel`. The payoff moment of interactive tuning.
8. **Library management.** Save-into-library, rename, duplicate, delete, reveal-in-Finder,
   folder rescan/refresh (today a Save As doesn't appear until relaunch), fix selection desync
   on declined discard.
9. **point2D click-pad** on the preview (drag to set), instead of two sliders.
10. **Templates + header autocomplete.** Filter / multipass / persistent-feedback starters;
    completion for ISF JSON header keys (the most typo-prone part of ISF). _Template
    MECHANISM landed in Plan 2 (bundled `/templates` folder + `TemplateCatalog` + File ▸ New
    from Template); generic starters + header autocomplete remain open._
11. **Shortcut pass:** jump-to-next-error, apply-fix key, focus-editor key.
12. ~~**Accessible Remix Studio workspace.**~~ **LANDED (2026-07-26, STAGED).** Persistent
    three-zone breeding, canvas, lineage, and activity workspace; explicit Parent A/B targeting;
    adaptive Grid, synchronized 2-up, and Hero views; session restore and immutable retry
    requests; structured compile/preview recovery; keyboard resize, collapse, focus, and reset;
    scalable 14pt-minimum text and VoiceOver status/action language. Shadertoy verification uses
    a visible human handoff with exact-slot resume and persistent legitimate clearance, never
    synthetic checkbox or AXPress automation. Ordinary-interaction acceptance remains STAGED
    until Conner completes the on-device checklist.

## Conversion pipeline (parallel track, independent of A/B/D)

1. ✅ **Sanitize Shadertoy metadata into the ISF header** — landed in Plan 3
   (2026-07-24): `ISFDocument.fileText` losslessly escapes literal block-comment terminators
   at the final wrapper boundary; direct and converter-path regressions pin exact round-tripping.
2. ✅ **Wire the unresolved-uniform tripwire for per-pass bodies** — landed in Plan 3
   (2026-07-24): every isolated pass runs `UniformRewriter.unresolvedUniformUses` immediately
   after scoped rewriting and emits a pass-named warning for survivors.
3. **Pixel-BLACK residue classes** (M42 + friends): persistent-buffer first-frame state, iMouse
   zw mirror, IMG_PIXEL half-texel drift in feedback sims.
4. **Keyboard-texture emulation** — synthesize Shadertoy's 256×3 keystate texture from ISF
   bool/event inputs; the largest "converts but renders static" class (~13/78 STATIC).
5. **Monomorphize sampler-as-value Common helpers** (closes 2 of 4 remaining compile fails).
6. Smaller: per-function (not file-global) uninitialized-output lint; per-pass `texelFetch`
   audio row-routing parity with Common; directive-aware `ZeroInitLocals`; mask-aware legacy
   detectors in `GLSLCompat`/`HeaderMacroExpander`; golden `.fs` snapshot tests of converted
   corpus fixtures so stage-ordering regressions are caught offline.
7. **mainVR / cubemap passes:** loud targeted warning at minimum; optional fixed-camera wrapper
   / equirect fake later.

---

## Part 3 — FUTURE CUSTOM VJ APP (out of scope here; recorded for that build)

_Everything in this section is deliberately NOT being built into TrueISFEditor._

**What carries over from this codebase as the baseline:**
- The render stack: `DisplayLinkDriver` + `MetalRenderCore` + `ISFMSLSafeBridge` crash
  containment + `PixelGate` ("a bad shader can't take down the show")
- `ImageSource` protocol + `SourceRouter` (never-black fallback policy); `CameraFrameProvider`
- `PreviewEngine` / `PreviewCoordinator` seam; `loadGeneration` compile-before-swap machinery
- The ParamStore (once Phase B lands) — MIDI/OSC/LFO/automation map onto it directly

**Architecture reworks the VJ app needs (plan for, don't retrofit):**
1. **One-scene core → N-slot compositor.** `MetalRenderCore` holds one `ISFMSLScene`; the VJ app
   needs N slots rendering offscreen into a mix pass. Build crossfade as a slot-array-of-2,
   never a special case — it becomes the layer stack.
2. **Output ownership inversion.** Today the output window mirrors the editor (debounced source
   sync). The VJ app's output owns warmed, pre-compiled scenes; the control surface is the client.
3. **Real window management:** NSScreen enumeration, borderless fullscreen on a chosen display,
   mirror-safe.

**Deferred feature set (was Phase C/E of the 2026-07-17 review):**
- Syphon output (publish post-render texture from `MetalRenderCore.draw` — natural hook exists)
- True fullscreen output on a chosen display
- audio + audioFFT ISF inputs (AVAudioEngine tap → vDSP FFT → texture; ISFMSLKit already
  declares `ISFValType_Audio/AudioFFT`; app currently drops them at `mapInputs`)
- MIDI learn + OSC on ParamStore; LFO/envelope/recorded param automation; BPM clock
- A/B decks + crossfade → layer stack with blend modes; performance sets/banks with warmed
  next-shader preload; transition-shader support (kit exposes isTransStart/End/Progress)

---

## Appendix — Borrowings from null_signal (reviewed 2026-07-17)

_null_signal: colleague's MIT-licensed p5.js/Electron live VJ instrument
(`/Users/arsonrivvers/Desktop/AV_Projects/null-signal`, © 2026 VJ CYBERPATROLUNIT). ~9,100-line
sketch, 69 modes, 4-layer WebGL compositor, 13-effect post chain, 64-slot presets, Electron
control/output split, VSN1 MIDI surface, local-AI INTERPRETER. JS→Swift means we port
**patterns and shader math**, not code._

### Into the editor (A/B/D scope), ranked

_Status 2026-07-17 (Plan 2): item 1 codec doctrine SHIPPED as `ParamSnapshot`
(validate-and-clamp, skip-corrupt, name-keyed); item 2 affordances shipped in Plan 1;
items 3–4 wave 1 SHIPPED as bundled `NS` templates (Mirror Kaleido, Pixel Sort, Chroma
Leak, Bayer Dither, Feedback Echo, Layer Blend — MIT attribution in
`THIRD_PARTY_LICENSES/null_signal.LICENSE.txt` + CREDIT headers). Wave 2 remaining:
wind, ink (water finish), burn/scan/jitter CRT block, shader-side strobe._

1. **Preset/snapshot model → ParamStore codec** (`capturePreset`/`applyPreset`,
   `src/main.js:3539/:4056`). Copy the design decisions: versioned flat JSON; key entries by
   ISF input NAME (they resolve name-first, index-fallback); validate-and-clamp every value on
   apply, skip corrupt entries, never fatal; partition runtime state (window geometry, transport)
   OUT of param snapshots; fast in-place patch when topology matches vs full rebuild —
   exactly the "replay params into a live scene without recompiling" shape Phase B needs.
   Event inputs: model as held+pulse (they capture held state in presets and detect release
   edges on apply) or snapshots can't represent momentary buttons.
2. **Param-panel affordances** (channel-strip code): double-click any control → reset to
   default; a visible "modified from default" marker per row (falls out of ParamStore free);
   skip-at-identity gate (`masterFxActive`, epsilon 0.0005 — bypass a filter stage when all
   inputs sit at identity; cheap perf + honest HUD); fader-gates-effect / knob-shapes-character
   as the param idiom for FX templates.
3. **post.js effects → bundled `VJ Post FX` ISF templates** (`src/shaders/post.js`, GLSL 1.0-
   compatible, each a clean amount/knob/button block): mirror (24 kaleido systems on one knob),
   wind (luma-gated directional smear), sort (pixel-sort approximation), chromaLeak, Bayer/blue-
   noise dither, ink (water refraction finish), burn/scan/jitter, feedback echo (→ PERSISTENT-
   buffer multipass template; CPU-side `drawClassicFeedback` math at `main.js:2209`).
   Gain-staging doctrine: brightness/contrast last.
4. **composite.js → "Layer Blend" two-input ISF filter template** (`compositeFrag:14-109`):
   exact 13-blend-mode math (dodge/burn divide guards) + correct alpha·opacity over-base
   formula — written because native blends are inconsistent across GL; equally true on Metal.
   Shader-side strobe (difference/exclusion over the composite + hashed block masks) as a
   second single-input template.
5. **Media bin → movie/image sources** (`main.js:104-610`, `MediaDisplay.js`): store file
   paths/security-scoped bookmarks in snapshots, never blobs; cap + validate + drop-invalid on
   read; placeholder frame while loading, never black; cover/crop fit from natural size.
6. **INTERPRETER contract → future ShaderAssist param actions** (`src/llm/interpreter.js`,
   `docs/INTERPRETER_CONTRACT_TUNING.md`): closed action schema validated against LIVE state;
   perceptual-delta shaping (reject invisible changes); safety ceilings with post-clamp delta
   recompute; per-action {ok, reason} outcomes + rejection telemetry; prompt constraints must
   match enforcing code. The apply-side discipline ShaderAssist doesn't have yet — relevant
   once ParamStore exists and the AI can set values, not just rewrite source.

### For the future VJ app (recorded, not built)

- One-pass N-layer compositor: per-layer sampler/rect/opacity/blend uniforms, background as
  base, strobe after the stack; three buffer tiers (mode → compositor → post → screen).
- Control/output split: control window renders NOTHING; output re-derives from a diffed,
  debounced (~50ms) preset-shaped state payload; main process = dumb relay that caches last
  state and replays on window reopen; re-entrancy guard on remote applies; output runs its own
  audio so bands never cross IPC.
- Output hardening: fullscreen frameless only when a second display exists (framed preview
  otherwise — frameless-resizable caused Chromium GPU churn); on renderer crash force-load a
  black page — fail-to-black on the projector, never fail-to-desktop.
- Presets: 16 slots × 4 banks, click=recall / hold=save, blank-slot confirm; 8-step preset
  sequencer (bank+slot refs) clock-synced, driven off the UI timer so it runs in the
  non-rendering window; transport always boots disabled.
- MIDI: bindings keyed by visual SLOT, not mode identity (reorder preserves muscle memory);
  reusing a CC auto-unbinds; arm-element → move-CC learn flow.
- Three-tier local AI (fast/heavy/audio-sidecar) with normal/aggressive/takeover autonomy
  profiles gating thresholds, ceilings, and apply counts.

### License

MIT (© 2026 VJ CYBERPATROLUNIT) — porting shader math requires carrying the copyright notice:
add to `THIRD_PARTY_LICENSES` + a `CREDIT` field in each derived ISF header ("Adapted from
null_signal by VJ CYBERPATROLUNIT (MIT)"). **Caveat:** `src/modes/` sketches keep their
UPSTREAM licenses (~13 adapted from third parties per CREDITS.txt) — do not port mode code
without checking the upstream. Everything listed above (composite.js, post.js, presets,
interpreter, Electron layer) is original to the repo and cleanly MIT. Repo is currently
private — courtesy heads-up to the colleague before shipping ported math.

---

_Maintenance note: keep this file current when phases land; DESLOPPIFY.md remains the
bug-level backlog (14 open at review time; conversion criticals C1–C6 fixed pre-launch).
The four full review reports live in the 2026-07-17 session; their top findings are all
reflected above._
