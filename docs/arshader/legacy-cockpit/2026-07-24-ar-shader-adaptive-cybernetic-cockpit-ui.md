---
schema_version: 1
topic: ar-shader-adaptive-cybernetic-cockpit-ui
date: 2026-07-24
tier: just-me
status: complete
correlation_id: arshader-ui-cockpit-20260724
---

> ⚠️ **PLATFORM SUPERSEDED 2026-07-30 — DESIGN CONTENT STILL LIVE.** The Svelte-in-TouchDesigner
> delivery this document specifies was abandoned when AR_Shader moved to a native macOS app
> (`docs/superpowers/specs/2026-07-30-native-performance-instrument-design.md`). **Build nothing
> from §5–§14, Appendix E, or Appendix F** — those describe a web client, a `ControlBridge` COMP,
> and a WebSocket protocol that no longer exist.
>
> **What is still authoritative** and is the reason this file was ported: **Appendix A** (product
> and information architecture), **Appendix B** (VDMX6 functional baseline and muscle memory),
> **Appendix C** (art direction and visual system), **Appendix D** (component and interaction
> specification), and **Appendix H** (per-file audit of all 46 references in `../ui-reference/`).
> Read those as design intent for the native surface; ignore every Svelte/TD implementation detail
> around them. Ported from `AV_Projects/AR_Shader` on 2026-07-31.

# AR_Shader Adaptive Cybernetic Cockpit UI Specification

## 1. What we're building

AR_Shader will gain a show-ready control cockpit for its TouchDesigner VJ instrument. The primary surface is a Svelte 5 and TypeScript single-page application, built by Vite and served directly by TouchDesigner. A new renderer-neutral `ControlBridge` COMP exposes a small semantic API over local WebSockets. TouchDesigner remains authoritative for decks, shader state, routing, mixing, audio analysis, modulation, output, recording, presets, and safety.

The cockpit remixes the capabilities of the operator's previous VDMX6 environment into three stable modes: `PERFORM`, `PATCH`, and `SYSTEM`. It is not a themed recreation of VDMX6. The 45 JPG references define the visual grammar, the saved VDMX screenshot defines the functional baseline and muscle memory, and the existing TouchDesigner network defines executable truth.

The product direction is named **Adaptive Cybernetic Cockpit**. It should feel like a precise audiovisual instrument whose internal state is visibly alive. Cybernetic means the feedback loop among gesture, parameter, modulation, TouchDesigner acknowledgement, signal path, and rendered output is understandable at all times. It does not mean fictional HUD ornament.

The live path has no Node.js, Python web framework, Socket.IO, OSC relay, cloud service, or Envoy dependency. Node.js is a development and build tool only. Envoy remains the authoring interface used to construct and update the TouchDesigner network, never the performer's runtime API.

The staged instrument is trusted as the foundation, but it does not currently expose every VDMX-parity feature described here. This specification separates existing-engine adapters from explicit additive engine addenda. Dynamic four-deck A/B assignment, master level, ordered deck and master FX racks, full clock control, advanced audio trigger controls, recorder and still capture, expanded scene management, advanced LFO behavior, MIDI, and ISF audio texture inputs appear only after their named capabilities exist. The cockpit never fakes them.

## 2. User-visible output + trigger

- **Output the user sees:** A full-screen dark performance cockpit with a persistent system spine, shader library, dominant program monitor, four deck cards, performance mixer, context inspector, and expandable modulation drawer. The interface exposes every current engine capability and reveals future modules only when TouchDesigner advertises them.
- **What triggers it:** Opening the local UI URL served by the `ControlBridge` inside the running `ARShader.toe` project. The client bootstraps against the active TouchDesigner session, establishes control and telemetry channels, receives a complete authoritative state snapshot, and enters `PERFORM`.

## 3. Cousin pattern

**Retrofit:** `docs/superpowers/specs/2026-07-23-td-native-pivot-isf-player-design.md`. That approved specification remains the engine and product foundation. This document adds the operator-facing composition, visual system, VDMX capability migration, renderer-neutral control contract, low-latency local transport, native failure-recovery surface, and clearly named engine addenda required for final VDMX parity. It does not replace or re-litigate the staged TouchDesigner build. Existing behavior is treated as authoritative and sound; addenda extend it behind granular capabilities.

The closest local deployment cousin is `/Users/arsonrivvers/Desktop/AV_Projects/TouchDesigner/ImmersiveHQ_Coursework/WK14-15/web_dashboard`. It proves relative Vite output with `base: './'`, a development WebSocket proxy, and same-host TouchDesigner production serving. Port those deployment mechanics only. Do not port its React, Zustand, or Tailwind layer, single mixed WebSocket, raw `setParam` messages, arbitrary OP paths, or implicit network exposure. The new cockpit reuses the current AR_Shader component contracts and existing scene, routing, blackout, and hot-swap invariants.

## 4. Tier + why

**Tier:** just-me

This is a single-operator instrument, but its rigor is show-critical. The interface controls projected output during live audiovisual performance, so a confusing state, blocked input path, stale command, hidden blackout condition, or browser failure can become a visible show failure. The implementation should stay deliberately local and simple while meeting stricter reliability, latency, safety, readability, and recovery gates than a normal personal dashboard.

The first release has no recurring hosting or cloud cost. All runtime assets, fonts, schemas, and application files are local.

## 5. Surfaces

- **Svelte performance cockpit:** The primary pointer and touch-capable operator surface, optimized for a 1920 x 1080 control display and usable down to 1280 x 800.
- **TouchDesigner `ControlBridge`:** The sole semantic boundary between renderers and the instrument. It validates commands, publishes authoritative state, and never exposes arbitrary OP paths or Python execution.
- **TouchDesigner native lifeboat:** A compact direct-control surface for blackout, master level, deck levels, A/B crossfade, recorder Stop when available, output status, scene recall, and UI server recovery when the browser is unavailable.
- **TouchDesigner engine and addenda:** `IsfPlayer`, four `Deck` COMPs, `Mixer`, `SourceRouter`, `AudioEngine`, `Bindings` when present, `Output`, and `SceneState` remain authoritative. Named `FxRack`, `Clock`, recorder, advanced audio, scene administration, and mixer extensions become authoritative only after implemented.
- **Local HTTP asset and library surface:** TouchDesigner serves the built app, protocol bootstrap, cached library metadata, cached thumbnails, health, and locally bundled fonts.
- **Control WebSocket:** Reliable ordered commands, acknowledgements, state snapshots, revisioned deltas, lifecycle events, errors, and safety state.
- **Telemetry WebSocket:** Droppable latest-value audio, modulation, timing, and performance samples isolated from control backpressure.
- **Preview media lane:** Optional low-resolution program and deck previews that can degrade or stop without affecting control or rendered output.
- **Shared protocol fixtures:** One canonical schema and fixture set validates both TouchDesigner Python and TypeScript interpretations.
- **Design and audit record:** This specification, the 46-file image appendix, and `_inspiration/UI/VDMX6-current-layout.png` remain the implementation source of truth.

## 6. v1 vs v2

**v1 (ships now):**

- V1 is delivered in capability slices. The existing-engine adapter slice ships first. The VDMX-parity release is complete only after the required engine addenda in Appendix J advertise and pass their capabilities.
- Svelte 5, TypeScript, and Vite static application with no service worker.
- TouchDesigner-served production bundle bound to `127.0.0.1`.
- Versioned `ControlBridge` API with semantic targets, granular capabilities, availability, health, revisions, command IDs, accepted and applied acknowledgements, lifecycle events, and structured errors.
- Separate reliable control and droppable telemetry lanes.
- `PERFORM`, `PATCH`, and `SYSTEM` modes with stable global geography.
- Shader library search, category and type filters, favorites, recents, status, explicit load-to-deck controls, and on-demand cached thumbnails.
- Four deck cards with shader identity, source, preview, opacity, blend, actual A/B role, health, binding count, and FX count when available.
- Generated shader inspector for input types the active `IsfPlayer` reports as supported. Float, enum, bool, color, point2D, event, and image ship with the adapter slice; audio and audioFFT texture controls require their engine addendum.
- Existing Mixer adaptation for four deck contributions, fixed current A/B behavior, blend modes, strobe, current master FX slot, and post-FX latching blackout.
- Required VDMX-parity Mixer addendum for dynamic four-deck A/B assignment, master level, ordered per-deck FX, and an ordered repeated-instance master FX rack.
- Source routing with self-route rejection, explicit safe fallback, and source health.
- Audio, BPM, beat phase, implemented LFO controls, MIDI, and binding surfaces only when their granular capabilities are advertised.
- Required VDMX-parity Clock addendum for timing source, manual BPM, presets, Auto, tap, run, pause, reset, beat, bar, cycle, phase, and elapsed time.
- Required VDMX-parity advanced audio addendum for band split, trigger threshold, hysteresis, and inversion, or an explicit transformed mapping through bindings.
- Base, modulation, and effective-value visualization.
- Existing scene save and recall adaptation, with rename, duplicate, protected overwrite, dirty, and partial recall gated by scene-administration capabilities.
- Output, Syphon, display, and diagnostic adaptation; recorder, quantize, still capture, and recorder lifeboat controls gated by recorder capabilities.
- Local pointer feedback within one browser frame and authoritative correction without visual ambiguity.
- A TouchDesigner-native lifeboat whose blackout and minimum recovery path directly control `Mixer` and `Output`, independent of the browser, Web Server DAT, queue, and `InstrumentApiExt`.
- Disconnect recovery through a fresh state snapshot, never cached command replay.
- Local security policy, single controller ownership, read-only observers, message limits, and whitelisted actions.
- Shared protocol tests, live integration tests, latency instrumentation, slow-client tests, and a 30-minute full-stack soak.

**v2 (deferred):**

- Explicit remote LAN control with TLS, authentication, trusted-interface selection, and measured ownership behavior.
- Signed desktop wrapper through Tauri if auto-launch, kiosk window management, or OS integration proves valuable.
- WebRTC preview at higher frame rates only after a dedicated macOS and TouchDesigner performance gate.
- Multi-controller collaboration and deliberate takeover workflows beyond one owner plus observers.
- User-configurable cockpit layouts beyond the three approved modes and stable regions.
- Automation recording, timeline sequencing, macro snapshots, and scene morphing beyond current engine contracts.
- A PWA service worker or offline cache. V1 avoids it to eliminate stale live-control bundles.
- Cloud sync, hosted analytics, remote media libraries, accounts, and internet-dependent services.
- Mobile-specific composition. V1 is responsive at tablet-shaped viewport sizes on the same Mac, but a physical remote tablet requires the deferred LAN mode because production binds to loopback.

## 7. Stage-by-stage

### Stage 1: Boot and establish authority

- **Input:** A running `ARShader.toe` project and the local cockpit URL.
- **Logic:** The app fetches `/api/v1/bootstrap`, validates `apiVersion`, receives `engineSessionId`, capabilities, state revision, session nonce, and channel URLs, then establishes control and telemetry connections. TouchDesigner sends a full `state.snapshot`.
- **Output:** A connected cockpit whose engine state exactly matches TouchDesigner.
- **Constraint:** The client disables writes until the authoritative snapshot is complete. A changed `engineSessionId` invalidates every cached engine assumption.

### Stage 2: Discover and load visual material

- **Input:** Search text, category, shader type, favorite, recent, or selected library item.
- **Logic:** The library reads cached metadata by `libraryRevision`. The operator selects a destination deck with `LOAD D1` through `LOAD D4`, or drags for pointer convenience. TouchDesigner accepts the request, builds the inactive shader chain, validates compile state, warms it, and commits the swap.
- **Output:** The selected deck changes only after `shader.load.succeeded`. Its prior visual stays live while building and remains live if loading fails.
- **Constraint:** An acknowledgement means accepted, not active. The UI follows `started`, `succeeded`, `failed`, and `superseded` lifecycle events.

### Stage 3: Perform the mix

- **Input:** Deck opacity, current A/B relationship, blend mode, crossfader, strobe, pinned macros, scene recall, and blackout gestures. Dynamic A/B assignment and master level appear after their mixer capabilities are advertised.
- **Logic:** The browser updates local control feedback immediately, coalesces continuous gestures to one latest value per target per animation frame, and sends semantic commands. TouchDesigner applies the canonical value and publishes an acknowledgement and revisioned delta.
- **Output:** Responsive mixer operation with visible connection, effective state, and program consequence.
- **Constraint:** Blackout, master, record stop, crossfader, deck levels, output health, and scene recall stay one gesture away. No modal can block `PERFORM`.

### Stage 4: Inspect and patch a deck

- **Input:** Selection of a deck, shader, parameter, source input, or FX instance.
- **Logic:** `PATCH` preserves the stable shell while the right inspector reveals the selected object. Shader metadata generates grouped controls. Routing and FX are edited as explicit signal stages.
- **Output:** A complete, readable edit surface that does not create floating pane sprawl.
- **Constraint:** All parameter writes use stable shader input identities and the current `shaderGeneration`. Old-inspector writes are rejected as `STALE_SHADER`.

### Stage 5: Bind modulation

- **Input:** A selected parameter and an audio, LFO, or MIDI source.
- **Logic:** The operator creates mappings parameter-first. A binding targets slot plus ISF input name, then exposes depth, offset, curve, enabled state, and resolved state. TouchDesigner owns source sampling, clamping, and the final effective value.
- **Output:** A parameter display with separate base thumb, modulation range or offset, and effective-value marker.
- **Constraint:** The browser writes `baseValue` only. Dormant mappings remain visible and re-arm when a matching input name returns.

### Stage 6: Configure output and record

- **Input:** Output display, Window COMP, Syphon, recorder source, audio source, destination, quantize, still capture, arm, start, or stop.
- **Logic:** Transactional commands are sequenced and publish lifecycle events. Global record state and output health stay visible in every mode.
- **Output:** Explicit `READY`, `ARMED`, `WAITING BEAT`, `RECORDING`, `STOPPING`, `COMPLETE`, or `ERROR` states with duration and destination.
- **Constraint:** Recorder, preview, and display failures cannot interrupt the program render path. When recorder capability exists, Stop is one gesture away in the browser and on the native lifeboat.

### Stage 7: Save and recall show state

- **Input:** Scene recall and capture, plus rename, duplicate, dirty-state management, or protected overwrite when scene-administration capabilities exist.
- **Logic:** `SceneState` validates and applies deck contents, parameter values, routing, bindings, audio settings, and LFO settings while preserving excluded safety and output geometry fields.
- **Output:** A visible current scene, dirty indicator, recall progress, and partial-failure report if required.
- **Constraint:** Preset recall cannot engage or release blackout. A failed shader restore retains the last valid deck visual.

### Stage 8: Degrade and recover

- **Input:** Browser disconnect, slow client, failed preview, shader compile failure, missing source, audio dropout, display loss, or TouchDesigner restart.
- **Logic:** The instrument contains each failure at its subsystem boundary. Telemetry and preview drop first. TouchDesigner keeps rendering. The native lifeboat remains available. The browser reconnects with capped exponential backoff, fetches a fresh bootstrap, and replaces engine state from a new snapshot.
- **Output:** A coherent degraded state with a plain-language fault, current safe behavior, and recovery path.
- **Constraint:** The browser never replays unacknowledged cached controls. Disconnect, reconnect, and scene recall never clear blackout. On TD project startup or recovery, a direct `SafetyState` boot gate asserts blackout before `Output` can open and requires an explicit local release.

## 8. Worked example end-to-end

The operator wants to load `AR_Genuary2026_day4_alt_v15` into Deck 2, tune its generated controls, add color grading, bind audio and LFO modulation, crossfade it into program, add a master Gridify effect, and begin a quantized recording. This full parity example assumes the corresponding FX, modulation, dynamic A/B, and recorder capabilities are installed. Before then, the same cockpit exposes only the implemented subset.

1. The cockpit opens in `PERFORM`. The system spine shows current scene, `82.88 BPM`, `AUDIO LIVE`, `1920 x 1080`, healthy render FPS, `REC READY`, and `BLACKOUT OFF`.
2. The operator selects Deck 2. A structural bracket and `D2 SELECTED` label appear. The fixed inspector changes context without moving global controls.
3. The operator searches `Genuary day4 alt v15` in the library. The result displays full identity, generator or filter type, categories, pass count, parse state, compatibility, and cached preview.
4. The operator presses `LOAD D2`. Deck 2 reports `BUILDING` while the old visual remains live. An accepted acknowledgement appears, followed by `shader.load.started`. The preview switches only after `shader.load.succeeded`.
5. The generated shader inspector groups the active inputs. The operator pins `Global Speed`, `Rotation Tumble`, `Box Scale X`, `Box Scale Y`, `Box Scale Z`, and `Spike (Sin/Tan Mix)` to Deck 2's performance macros.
6. Moving `Global Speed` updates the local base thumb immediately. The canonical marker and numeric value confirm the state TouchDesigner applied.
7. The operator adds `AR_ColorGrading_v02` to Deck 2. It appears as `D2 FX 01`. Brightness, Contrast, Saturation, Wet/Dry, blend, bypass, reorder, duplicate, and remove are available. Collapsing the instance keeps Wet/Dry reachable.
8. From `Spike (Sin/Tan Mix)`, the operator selects `MOD`, chooses `AUDIO: KICK`, sets depth, and confirms. The parameter now shows base, incoming kick contribution, and effective value.
9. From `Rotation Tumble`, the operator chooses `LFO 2`, selects Sine, enables beat sync, and sets four measures. A violet LFO chip appears beside the parameter.
10. Deck 2 is assigned to B in the performance mixer. The operator verifies opacity, blend, source health, and FX state.
11. The operator moves the large A/B crossfader toward B. The program monitor remains dominant and shows the mixed result. The fader gesture cannot be stolen by page scroll.
12. The operator opens the compact master FX strip, adds `AR_Gridify_v01`, and adjusts Wet/Dry without leaving `PERFORM`. The real signal strip reads `MIXER -> MASTER FX -> MASTER LEVEL -> BLACKOUT -> OUTPUT`.
13. The operator opens Record, confirms Main Output and BlackHole audio, enables beat quantize, and presses `ARM`. The spine changes from `READY` to `WAITING BEAT`, then to `REC 00:00:01` at the next quantized boundary.
14. If audio drops, the audio chip becomes amber and reads `AUDIO HELD`. Modulation holds its last safe value while visuals and recording continue. It returns to `AUDIO LIVE` only after TouchDesigner confirms restoration.
15. If the browser disconnects, TouchDesigner keeps rendering and recording. The native lifeboat retains blackout, master level, mixer essentials, recorder state and Stop, output health, scene recall, and server restart. Reconnection replaces the browser state from an authoritative snapshot without resetting the show.
16. If immediate output suppression is required, the operator presses persistent `BLACKOUT` once. It latches after master FX, is visible in every mode, and cannot be changed by scene recall.

This flow preserves the functional reach of the previous VDMX6 environment while requiring no floating windows and no more than one contextual drawer at a time.

## 9. Tone constraints

The interface should feel technical without being clinical, futuristic without being fictional, dense without becoming illegible, dark without losing contrast, animated without becoming restless, and custom-built without sacrificing conventional control behavior.

The output image is the primary source of saturation and visual complexity. Interface chrome is near-black, mineral, planar, and precise. Hairline steel geometry establishes modules. Cyan is the cool signal family and A-side color. Coral is the warm action family and B-side color. Selection itself is structural, using a raised surface, neutral state notch, and label; coral may accent its text. Violet is reserved for modulation. Amber means pending, armed, fallback, or degraded. Red means recording, critical fault, or destructive action. Green appears only for confirmed health or success.

The visual system must avoid fake HUD decoration, illegible cinematic microtype, generic rounded SaaS cards, broad neon gradients, glow on every control, fake scanlines, random glyph noise, perspective distortion on primary controls, hue cycling, invisible modes, and decorative telemetry. Every graph, route, tick, marker, and animation must reflect real data or real interaction state.

No important or interactive text may be smaller than 14 px. Touch targets are at least 44 x 44 px, with 52 x 52 px preferred for show-critical actions. Critical meaning cannot depend on hover, color alone, or an unlabeled icon.

Motion is direct, mechanical, and signal-driven. Press response is 60 to 80 ms, selection is 100 to 140 ms, drawers are 160 to 200 ms, and mode changes are 200 to 240 ms. There is no spring, overshoot, elastic drift, ambient parallax, or layout breathing. Reduced motion preserves the complete information model.

### 9.1 Real-time visual environment

The cockpit includes a GPU-rendered visual environment, not merely animated CSS chrome. A single Three.js canvas sits behind the operational interface and renders custom GLSL signal fields, particles, routing structures, and spatial transitions derived from validated TouchDesigner state and telemetry. Svelte and the DOM continue to own every control, label, focus target, safety state, and interaction. SVG, CSS, and ordinary Canvas remain appropriate for exact plots and component-local feedback.

The browser compositor has three layers:

1. **Operational layer:** Svelte and DOM controls with stable geometry, sharp type, pointer capture, keyboard behavior, and accessibility semantics.
2. **Data-motion layer:** SVG, CSS, and 2D Canvas traces for meters, modulation paths, timing, selection, acknowledgement, and local gesture feedback.
3. **Atmosphere layer:** One pointer-transparent Three.js WebGL canvas for the living spatial field and custom GLSL effects.

The atmosphere layer may respond to `audio.energy`, `audio.kick`, `clock.bpm`, `clock.beatPhase`, `modulation.selected`, connection health, pending operations, recording state, selected deck, and A/B balance. Every mapping is documented and deterministic. Missing or stale telemetry decays to a neutral state rather than inventing activity.

Three.js is the production GPU abstraction. p5.js is not included in the show-time bundle. It may be evaluated later for an isolated generative 2D study only if the same result cannot be expressed cleanly through the existing Svelte, SVG, Canvas, and Three.js stack.

The canvas is presentation-only: `pointer-events: none`, `aria-hidden="true"`, no WebSocket ownership, no command emission, no layout authority, and no exclusive communication of meaning. It consumes the existing bounded instrument store and requests no new telemetry lane. A renderer fault, context loss, reduced-motion preference, hidden tab, or performance-budget violation freezes, simplifies, or disables the environment while the complete cockpit remains usable.

## 10. Success criteria

- [ ] The production cockpit is a static Svelte 5 and TypeScript bundle built by Vite and served by TouchDesigner with no Node runtime.
- [ ] The production bundle uses one Three.js GPU atmosphere layer plus Svelte, DOM, SVG, CSS, and 2D Canvas for operational and exact data presentation; p5.js is not a show-time dependency.
- [ ] The GPU environment is driven only by validated authoritative state and already-subscribed telemetry, opens no transport, emits no command, and invents no activity when data is absent or stale.
- [ ] Disabling the GPU environment leaves every control, state, warning, safety action, route, and diagnostic available.
- [ ] Reduced motion produces a meaningful static frame, and renderer context loss or performance degradation cannot interrupt control input or TouchDesigner output.
- [ ] Normal production operation passes at `low` animated quality or better; `static` and `off` are accessibility, fault, hidden-document, or emergency performance fallbacks and cannot satisfy the animated-cockpit release gate by themselves.
- [ ] The 14-section specification and every appendix remain the implementation source of truth.
- [ ] All 46 reference files are inventoried, including both byte-identical JPG filenames and the saved VDMX6 PNG.
- [ ] Every VDMX6 capability is explicitly preserved, transformed, or intentionally retired, with a named engine and cockpit destination where preserved.
- [ ] The result is recognizably a new Adaptive Cybernetic Cockpit, not a themed VDMX clone.
- [ ] `PERFORM`, `PATCH`, and `SYSTEM` have stable regions and explicit mode state.
- [ ] Blackout, connection health, output health, current scene, timing, and render warning remain visible in all modes; master level and record state join that persistent layer when supported.
- [ ] No critical action depends on hover, double-click, a hidden modifier, or a floating window.
- [ ] No important text is below 14 px and no critical hit target is below 44 x 44 px.
- [ ] Any indexed shader can be explicitly loaded into any of four decks.
- [ ] Shader loading keeps the old visual live until the new chain is compiled, warmed, and committed.
- [ ] Generated controls cover every input type advertised by the active player, never expose unsupported audio textures, and support grouping, search, pinning, exact values, and scoped resets.
- [ ] When FX-rack capability is advertised, deck and master FX are distinct, ordered, reusable, and expose immutable instance identity, enable, bypass, Wet/Dry, blend, reorder, duplicate, remove, and error state.
- [ ] Source routing reports health, rejects self-routing, and visibly engages the never-black fallback.
- [ ] Audio, full clock, LFO, MIDI, and bindings are reachable from their target parameter and the modulation workspace only at the level advertised by granular capabilities.
- [ ] Base, modulation, and effective values are visually distinct.
- [ ] When recorder capability is advertised, readiness, quantized arm, active recording, duration, Stop, completion, destination, and failure are explicit in the browser, with state and Stop mirrored in the lifeboat.
- [ ] Blackout is latching, post-FX, preset-excluded, one gesture away, and independent from shader reset.
- [ ] TouchDesigner is authoritative for all engine, hardware, persistence, safety, and output state.
- [ ] The browser cannot access arbitrary TD paths, Python, Envoy, or filesystem paths.
- [ ] The browser receives local optimistic feedback within one animation frame.
- [ ] Command acceptance p95 is at most 33 ms, fast scalar application p95 is at most 25 ms, transaction completion has operation-specific budgets, and pointer-to-rendered-output p95 is at most 50 ms at 60 Hz.
- [ ] A sustained 60 Hz crossfader gesture causes no TD render-frame drops.
- [ ] `ControlBridge` consumes less than 1 ms average and less than 2 ms p95 per TD frame under the acceptance workload.
- [ ] No `ControlBridge` telemetry path cooks continuously when no clients are connected.
- [ ] A slow client cannot create an unbounded queue or stall the TD render path.
- [ ] Preview and telemetry can degrade or stop without affecting commands, state, program output, or the native lifeboat.
- [ ] Browser failure, restart, and reconnect leave TD output unchanged and restore the client from a fresh snapshot.
- [ ] A TD restart changes `engineSessionId` and invalidates cached client state.
- [ ] TD boot asserts blackout before output opens, keeps blackout outside ordinary scenes, and requires explicit local release.
- [ ] The native lifeboat remains performable with the browser, Web Server DATs, command queue, or `InstrumentApiExt` intentionally disabled.
- [ ] Existing four-deck, hot-swap, 60 fps at 1920 x 1080, 20 percent GPU headroom, blackout, never-black, and 30-minute soak requirements remain satisfied.

## 11. Failure modes + fallbacks

| Failure mode | Fallback |
|---|---|
| Browser fails to open | TouchDesigner keeps rendering. Use the native lifeboat, restart the UI service, then reconnect to a fresh snapshot. |
| Control WebSocket disconnects | Display `CONTROL LOST`, disable browser writes, keep TD state untouched, expire non-safety momentary leases, and reconnect with capped exponential backoff. |
| Telemetry WebSocket slows or disconnects | Mark affected meters stale, drop queued samples, keep control fully available, and resubscribe after recovery. |
| Preview media stalls | Mark preview stale, reduce frame rate or resolution, or disable it. Never describe preview failure as program-output failure without TD confirmation. |
| TouchDesigner restarts | Assert the direct boot blackout before opening Output, generate a new process-session `engineSessionId`, require explicit local blackout release, then let the browser discard cached state and fetch a complete snapshot. |
| Shader header is malformed | Flag the library item, keep the active shader live, expose a plain-language parse error, and allow the operator to choose another item. |
| Shader compile or warm-up fails | Publish `shader.load.failed`, retain the current visual, keep controls usable, and expose the compiler summary outside `PERFORM`. |
| A newer shader load supersedes an older request | Publish `shader.load.superseded`, stop showing false progress, and track the surviving request. |
| Old inspector writes after a shader swap | Reject with `STALE_SHADER`, refresh the selected schema, and return the control to canonical state. |
| State revision is stale | Reject transactional mutation with `STALE_REVISION`, request current state, and ask for deliberate retry when required. |
| Source is missing or invalid | Engage and label `SAFE SOURCE`, publish fallback state, and preserve non-black output. |
| A deck attempts to route to itself | Reject before cook with `SELF_ROUTE` and preserve the last valid route. |
| Audio device drops | Hold the last normalized analysis values under the existing policy, show `AUDIO HELD`, and auto-reattach when TD confirms recovery. |
| External display is lost | Report preferred and actual display separately, follow the verified Output failover policy, and keep native output controls available. |
| Recorder fails or drops frames | Keep program output live, publish an actionable recorder error, keep Stop available, and preserve the partial file if the backend supports it. |
| Pointer release is lost during a momentary control | Expire the server lease for non-safety controls. A blackout hold remains fail-closed and does not restore live output. |
| Second client connects | Grant observer access by default. The current controller retains the write lease until explicit takeover behavior exists. |
| Client sends malformed or oversized input | Reject with a structured error, cap queue and message sizes, record the event, and never evaluate arbitrary content. |
| Render health degrades | Stop thumbnails, reduce preview, reduce hidden telemetry, retain commands and safety, then raise a visible performance warning. |
| Scene recall contains a bad shader | Keep the last valid deck image, report partial recall, and do not change blackout or output geometry. |
| Native lifeboat and browser disagree | Direct TD state wins. The browser refreshes from authoritative adapters, while blackout and minimum output recovery remain available even if those adapters are faulted. |

## 12. HITL checkpoints

| Trigger | Reviewer | Channel | SLA |
|---|---|---|---|
| Visual tokens and one static `PERFORM` composition are ready | Conner Jones | In-session screenshot review | Before component implementation |
| Pointer and touch control prototypes are live | Conner Jones | On-device usability pass | Before wiring the full inspector |
| `ControlBridge` schema and fixture set are frozen | PM plus implementation agent | Spec and protocol review | Before TD or Svelte integration code |
| Native lifeboat is wired | Conner Jones | Live TouchDesigner smoke | Before relying on the browser surface |
| First end-to-end slider changes TD and returns canonical state | Conner Jones | Live instrument review | Same implementation phase |
| Library, shader load lifecycle, and generated inspector are connected | Conner Jones | Rehearsal workflow review | Before audio and modulation surfaces |
| Audio, LFO, MIDI, and bindings are connected | Conner Jones | Real-device live smoke | Before declaring modulation complete |
| Output display, Syphon, and recorder are connected | Conner Jones | External display and capture smoke | Before hardening |
| Latency, slow-client, disconnect, and 30-minute soak reports pass | Mechanic and PM self-review, then Conner Jones | Evidence review and on-device confirmation | Before performance-ready claim |
| Final UI runs in a representative rehearsal | Conner Jones | Client Success live UX review | Before first show use |

## 13. External assets

- `_inspiration/UI/VDMX6-current-layout.png`: Saved local reference labeled **VDMX6 Current Layout**, 3446 x 2178 RGB PNG, SHA256 `9a832e7f3edf9cfc151c96b5702fa672184812db8d1c248cf493b9388e850bc8`. It is ignored by git with the rest of `_inspiration/`, but is the canonical local capability reference.
- `_inspiration/UI/*.jpg`: 45 visual references, including one exact duplicate pair. They remain local design evidence and are not production assets.
- Locally packaged font files: Space Grotesk Variable for operational hierarchy and IBM Plex Mono Variable for numeric and technical data, subject to license verification and inclusion of their license files. A fully IBM Plex fallback is acceptable if the implementation chooses one family source.
- A coherent locally bundled outline icon set, then a small custom set for blackout, signal routing, modulation, output, and recording. Every icon license must be retained.
- Cached shader thumbnails generated from the local indexed library. Generation is a background or on-demand function that yields to render health.
- Canonical JSON Schema or equivalent protocol source plus shared Python and TypeScript fixtures.
- No cloud fonts, hosted scripts, remote analytics, remote icon APIs, external account, or runtime internet dependency.

Primary technical references:

- [TouchDesigner Web Server DAT](https://derivative.ca/UserGuide/Web_Server_DAT)
- [TouchDesigner WebserverDAT Class](https://derivative.ca/UserGuide/WebserverDAT_Class)
- [Python threading in TouchDesigner](https://docs.derivative.ca/Python_threading_in_TouchDesigner)
- [TouchDesigner Multi Touch In DAT](https://derivative.ca/UserGuide/Multi_Touch_In_DAT)
- [TouchDesigner Panel COMP Panel Page](https://derivative.ca/UserGuide/Panel_COMP_Panel_Page)
- [TouchDesigner Web Render TOP](https://derivative.ca/UserGuide/Web_Render_TOP)
- [TouchDesigner WebRTC Palette](https://derivative.ca/UserGuide/Palette%3AwebRTC)
- [TouchDesigner WebRTC](https://derivative.ca/UserGuide/WebRTC)
- [Svelte overview](https://svelte.dev/docs/svelte/overview)
- [Svelte reactive state](https://svelte.dev/docs/svelte/%24state)
- [Solid fine-grained reactivity](https://docs.solidjs.com/advanced-concepts/fine-grained-reactivity)
- [Vite production build](https://vite.dev/guide/build)
- [WebSockets Standard](https://websockets.spec.whatwg.org/)
- [Pointer Events Level 3](https://www.w3.org/TR/pointerevents3/)
- [Tauri architecture](https://v2.tauri.app/concept/architecture/)

## 14. Anti-scope

- Do not recreate the VDMX6 pane layout or treat its coordinates as requirements.
- Do not rewrite or regress the staged TouchDesigner foundation merely to simplify the UI. The additive, capability-gated engine addenda in Appendix J are explicitly in scope for VDMX parity.
- Do not put Envoy, arbitrary OP paths, filesystem paths, Python, expressions, or shell execution behind the performer API.
- Do not add Node.js, FastAPI, Flask, Socket.IO, an OSC relay, or another always-running middleware process to the live local path.
- Do not bind to `0.0.0.0` or enable remote LAN control by default.
- Do not add accounts, cloud sync, analytics, remote hosting, subscriptions, or recurring services.
- Do not add a service worker to v1.
- Do not make Web Render TOP the primary UI surface.
- Do not require WebRTC for v1 or let preview media share the control queue.
- Do not promise literal zero latency. Meet the measured local frame and millisecond budgets.
- Do not expose a capability until TouchDesigner advertises it. Missing recorder, binding, or FX modules are hidden or described as unavailable in diagnostics, never represented by fake controls.
- Do not place safety, output truth, record stop, or master controls inside transient drawers.
- Do not use decorative telemetry, fake routes, fictional diagnostics, or unrelated HUD markings.
- Do not copy cinematic microtype below 14 px.
- Do not use soft consumer dashboard cards, pill overload, broad shadows, large corner radii, or generic cyberpunk gradients.
- Do not communicate critical state through color alone.
- Do not let hover, double-click, or invisible modifier keys become the only path to a required action.
- Do not add user-layout editing, mobile-specific composition, multi-user collaboration, timeline sequencing, or remote control in v1.
- Do not let thumbnail work, preview encoding, telemetry, logs, or inspector detail compete with TouchDesigner rendering.
- Do not replay cached unacknowledged commands after reconnect.

## Appendix A. Product and information architecture

### A.1 Governing model

The interface follows four sources of truth:

1. The visual inspiration collection defines aesthetic grammar.
2. The VDMX6 screenshot defines functional reach and learned concepts.
3. The TouchDesigner network defines runtime capability and state.
4. The cockpit defines how those capabilities become understandable and fast.

The selected context can change, but the object hierarchy and global geography stay stable.

```text
SHOW SESSION
  SCENE BANK
  SYSTEM STATE
    AUDIO
    TIMING
    DISPLAY AND OUTPUT
    RECORDING
    CONNECTION AND PERFORMANCE
  MIXER
    DECK 1
      SOURCE
      SHADER
      PARAMETERS
      SOURCE ROUTING
      DECK FX
      BINDINGS
    DECK 2
    DECK 3
    DECK 4
    A/B ASSIGNMENT
    CROSSFADE
    STROBE
    MASTER FX
    MASTER LEVEL
    BLACKOUT
```

### A.2 Access tiers

The tiers describe the full parity composition. Capability-dependent items occupy their stable slot only after support is advertised. The remaining layout closes the gap rather than showing a false disabled module.

#### Tier 0: Always visible

- Blackout state and action
- Master level when supported
- Program output health
- Browser-to-TD connection health
- Current scene and dirty state when supported
- BPM, timing source, and beat phase
- Record state, duration, and Stop when supported
- Render FPS or dropped-frame warning
- Current mode

#### Tier 1: PERFORM

- Deck selection and visual state
- Library search and explicit deck load
- Deck source, opacity, blend, current A/B role, and assignment when supported
- Crossfader
- Pinned shader macros
- Compact deck and master FX controls for supported scopes
- Scene recall
- Program monitor

#### Tier 2: PATCH

- Complete generated shader inputs
- Source routing
- Per-deck and master FX order
- Audio, LFO, and MIDI assignment
- Binding depth, offset, curve, and resolved state
- Base, modulation, and effective values
- Scene capture, overwrite, and chain presets

#### Tier 3: SYSTEM

- Audio input and analyzer settings
- Display, Window COMP, and Syphon
- Recorder configuration
- Frame timing, memory, and render health
- API, connection, queue, and protocol diagnostics
- Display failover and audio dropout history

### A.3 Primary modes

#### PERFORM

`PERFORM` is the default show mode. It exposes the dominant program output, four deck summaries, shader loading, crossfader and levels, selected deck macros, compact FX, scene recall, and persistent safety. It contains no blocking modal.

#### PATCH

`PATCH` constructs and tunes the signal graph. It shows the selected deck path, complete generated shader controls, routing, FX racks, modulation, bindings, and scenes. Selecting a deck, effect, parameter, or binding changes the inspector content without changing overall geometry.

#### SYSTEM

`SYSTEM` configures and diagnoses infrastructure. It covers audio, output, Syphon, recording, performance, connections, display failover, and device dropout. Persistent safety and program truth do not disappear.

### A.4 Wide composition

The 1920 x 1080 reference composition uses five stable regions:

```text
+------------------------------------------------------------------+
| SYSTEM SPINE: SCENE | BPM | AUDIO | FPS | OUTPUT | REC | BLACKOUT|
+----------+--------------------------------------+----------------+
| LIBRARY  | CENTRAL STAGE                        | CONTEXT        |
| RAIL     | PROGRAM MONITOR                      | INSPECTOR      |
|          | FOUR DECK CARDS                      |                |
|          |                                      |                |
+----------+--------------------------------------+----------------+
| PERFORMANCE MIXER: DECKS | A/B | XFADE | MASTER | BLACKOUT       |
+------------------------------------------------------------------+
| COLLAPSIBLE MODULATION AND DIAGNOSTICS DRAWER                    |
+------------------------------------------------------------------+
```

The diagram shows the full VDMX-parity state. Unsupported capability slots collapse without moving Blackout, connection, output health, mode, or the mixer foundation.

Starting layout constraints:

| Region | Starting dimension | Behavior |
|---|---:|---|
| System spine | 64 to 72 px high | Global truth only |
| Library rail | 280 to 320 px wide | Search, filter, browse, load |
| Context inspector | 360 to 440 px wide | Selected object only |
| Performance mixer | 220 to 260 px high | Stable continuous controls |
| Modulation drawer | 40 to 48 px collapsed | Expands without hiding safety |
| Central stage | Remaining area | Program monitor remains dominant |

### A.5 Compact composition

At 1440 x 900 and 1280 x 800:

- The library becomes a labeled slide-over drawer.
- The context inspector becomes a labeled slide-over drawer.
- Deck cards become a horizontal strip.
- The mixer remains anchored.
- Low-priority spine diagnostics collapse into a labeled status menu.
- Blackout, connection, and output health always retain text labels. Master and record retain labels whenever their capabilities exist.
- Body text remains at least 14 px.
- Targets remain at least 44 x 44 px.

### A.6 Region ownership

| Region | Owns | Must not own |
|---|---|---|
| System spine | Scene, BPM, audio health, TD connection, render health, output, record, blackout | Deck-specific inputs |
| Library rail | Search, category, type, favorites, recents, status, preview, load destination | Live mixer state |
| Central stage | Program output, four deck visuals, selected emphasis, fallback and loading state | Full configuration |
| Context inspector | Selected deck, shader, input, FX, binding, output device, or recorder | Unrelated global summaries |
| Performance mixer | Deck levels, visibility, A/B, crossfader, blend, strobe, master, quick FX, blackout | Library browsing |
| Modulation drawer | Audio, LFO, MIDI, bindings, dormant routes, values | Program output ownership |

### A.7 Stable spatial memory

These elements do not move among modes:

- System spine
- Mode switcher
- Blackout
- Master level when supported
- Record state and Stop when supported
- Connection health
- Program output health
- Compact mixer access

The context inspector changes content inside a stable boundary.

## Appendix B. VDMX6 functional baseline and TouchDesigner mapping

### B.1 Source record and remix doctrine

| Field | Value |
|---|---|
| Reference image | `_inspiration/UI/VDMX6-current-layout.png` |
| Display label | VDMX6 Current Layout |
| Dimensions | 3446 x 2178 |
| SHA256 | `9a832e7f3edf9cfc151c96b5702fa672184812db8d1c248cf493b9388e850bc8` |
| Role | Previous operational arrangement and capability baseline |
| Explicit non-goal | Recreate the VDMX pane layout |

Remix rules:

1. Preserve capabilities, not coordinates.
2. Preserve relationships, not window boundaries.
3. Preserve fast access to frequent actions.
4. Preserve concepts such as source, layer, FX, opacity, blend, output, audio, clock, LFO, MIDI, recording, and presets.
5. Replace floating panels with stable regions and selected context.
6. Replace repeated chrome with shared component behavior.
7. Keep safety, output health, record state, and master control visible in every mode.
8. Never hide a live-performance requirement behind hover.
9. Never invent telemetry.
10. Treat the browser as a control surface for TouchDesigner, not an independent engine.

### B.2 Shared VDMX interaction vocabulary

The screenshot establishes panel titles, local search, visibility and bypass, disclosure, add, reset, remove, scrolling, asset load and save, exact values beside sliders, previews, transparency checkerboards, and color-coded enable state. The cockpit retains the concepts through one coherent component system rather than literal VDMX chrome.

### B.3 Exhaustive visible capability inventory

#### 1. ISF A Source

- Source search and selection
- Resolution at `3840 x 2160`
- FPS
- `Use Source`
- Explicit unassigned state
- Local visibility, search, and close

#### 2. ISF B Source

- Active `AR_Genuary2026_day4_alt_v15...` shader
- Resolution at `1920 x 1080`
- FPS
- Source selector
- Inspect, search, visibility, and close

#### 3. Generated ISF Interface

- `PANIC RESET`
- `Total Box Count`
- `Spike (Sin/Tan Mix)`
- `Quality Mode`
- `Mirror Mode`
- `Stripe Space`
- `Global Speed`
- `Camera Depth`
- `Field of View`
- `Random Seed`
- `Rotation Tumble`
- `Path Tangling`
- `Position Jitter`
- `Swarm Spread X`
- `Swarm Spread Y`
- `Swarm Spread Z`
- `Grid Structure`
- `Box Scale X`
- `Box Scale Y`
- `Box Scale Z`
- `Size Pulse Spd`
- `Cull Pattern A`
- `Cull Pattern B`
- `Brightness Pre-Threshold`
- `Contrast Gamma`
- Group `MODE 1-Bit Threshold`
- `Threshold Cutoff`
- `Resolution Crush`
- `Z-Stripes`
- `Glitch / RGB Split`
- Sliders, exact values, menus, toggles, event buttons, group headings, reset, and scrolling

The shader event is a scoped reset, not global blackout.

#### 4. Layer A

- `30` FPS
- `ISF A` source
- `Addition.metal` blend
- Transparent preview
- Vertical layer opacity
- Local panel actions

#### 5. ISF A FX

- Load, preview, and save asset
- Ordered effect instances
- Disclosure, visibility, `On`, delete
- Wet/Dry and blend per instance
- `Color Controls`
- `AR_ColorGrading_v02`

#### 6. Layer B

- `30` FPS
- `ISF B` source
- `Addition.metal` blend
- Live preview
- Vertical layer opacity
- Local panel actions

#### 7. ISF B FX

- The same rack mechanics as A
- Expanded Brightness, Contrast, Saturation
- Wet/Dry and blend
- Load, preview, and save

#### 8. Main Output

- Large final preview
- Source, resolution, and FPS
- Vertical master fader
- Visibility and close

#### 9. Canvas / Main Output FX

- Load, `ALL UP`, preview, and save
- Long ordered master chain
- Per-instance disclosure, visibility, enable, delete, Wet/Dry, and blend
- `ArsonRivvers_kaliedoClassic_v10`
- Multiple `AR_HyperTesseract_v03`
- Multiple `AR_Gridify_v01`
- `AR_WatercoloringMelt_v08_colorized`
- Multiple `AR_SortingSmear_2025_v01`
- Repeated instance support and scrollable overflow

#### 10. Audio Analysis

- Low and high regions
- Crossover or envelope graph
- Inverted trigger region
- Gain or normalization
- Live analysis state

#### 11. Movie Recorder

- `Video Source: Main Output`
- `Audio Source: BlackHole 2ch`
- Destination
- `Quantize Rec.? No`
- Ready state
- Video and Image actions

#### 12. Clock

- Audio source `MacBook Pro Microphone`
- BPM presets `44`, `88`, `120`, and `160`
- Audio, clock, and autonomous timing choices
- `Auto`
- `82.88 BPM`
- `13 : 2 : 2`
- `00:00:24.16`
- Phase indicator and transport

#### 13. LFO

- Sine waveform
- Waveform visualization
- Time, Rate, Clock, Measures, Loop, Scratch
- Pause, direction, reset, and add

#### 14. MIDI

- Type set to MIDI
- Event area
- Pause and Clear
- Visibility and close

#### 15. Media Buttons and library

- Target `ISF B`
- Trigger timing `Immediately`
- Collection `testexportfromvdmx.fcol`
- Search and folder tree
- Categories `Text`, `2d`, and `Proqxis`
- Thumbnail shader grid
- Selected state and immediate load
- Visible shaders including `AR_GOL_MetaCellularFilter_v15`, `AR_Genuary2026_day4_alt_v15...`, `AR_ReactionDiffusion_Gen_v10`, and `AR_ReactionDiffusion_Gen_v13...`

### B.3.1 Explicit transformation decisions

- **Per-layer FPS selectors:** V1 intentionally uses the TouchDesigner project cadence for all decks. The VDMX `30 FPS` menus become read-only actual-FPS and health telemetry. Independent deck cadence is deferred behind `decks.independentCadence` because asynchronous deck rates can create mix jitter and unclear latency.
- **Media trigger timing:** V1 supports the authoritative `immediate` request mode only. `Immediate` means start building now and commit only after compile and warm-up. Beat-quantized or scheduled shader commit is deferred behind `library.loadTiming`.
- **Audio crossover and inversion:** These are preserved through the advanced audio addendum as low and high split frequencies, trigger threshold, hysteresis, and trigger inversion. Binding-level negative depth remains available for continuous modulation inversion.
- **Clock:** The familiar controls are preserved in a dedicated `Clock` addendum rather than inferred from read-only audio BPM. It owns source, manual BPM, quick presets, Auto, tap, run, pause, reset, beat, bar, cycle, subdivision, phase, and elapsed show time.
- **Advanced LFO:** The UI exposes only shape, rate, and amplitude until phase, sync, measures, loop, direction, scratch, and pause are implemented and advertised individually.
- **ISF audio textures:** The inspector does not generate working audio or audioFFT texture controls while the active player reports them unsupported. Those controls appear only after the texture-input addendum passes conformance.

### B.4 Capability mapping

| VDMX capability | TouchDesigner authority | Cockpit destination | Required behavior |
|---|---|---|---|
| A and B sources | `slot1` through `slot4` Decks | Deck cards and inspector | Four slots replace two panes. A/B is a mix relationship. |
| Media buttons and library | `IsfPlayer` index | Library rail | Search, type, category, favorites, recents, parse state, preview, explicit load, immediate timing |
| Generated ISF Interface | Active `IsfPlayer` manifest | Context inspector | Generate every supported input type with exact value and reset |
| Layer preview | Deck output TOP | Deck card | Shader, source, resolution, loading, error, and fallback |
| Layer opacity | Deck and Mixer contribution | Mixer and deck card | Large fader, numeric value, reset |
| Layer blend | `Mixer` | Deck quick control and detail | Same supported list across decks |
| A/B relationship | Current `Mixer` plus dynamic A/B addendum | Performance mixer | Current fixed A/B remains truthful; explicit four-deck assignment appears with `dynamicAB` |
| Per-layer FX | `FxRack` deck addendum | PATCH rack | Ordered instances appear only with deck-rack capability |
| Main Output FX | Current `Mixer/fx_master` plus `FxRack` master addendum | Master FX rack | One current slot remains truthful; repeated stable instances require the rack capability |
| Master Fader | Mixer master-level addendum | Persistent mixer | Add before blackout, never move with context |
| Blackout | Final Mixer stage | Persistent safety | One touch, latching, post-FX, preset-excluded |
| Shader Panic Reset | Active shader event | Shader inspector | Label `RESET SHADER`, distinct scope and styling |
| Source routing | `SourceRouter` | PATCH routing | Source health, self-route block, safe fallback |
| Audio Analysis | `AudioEngine/null_bus` plus advanced-audio addendum | Drawer and SYSTEM | Current bus plus split frequencies, threshold, hysteresis, inversion when advertised |
| Clock | Dedicated `Clock` addendum fed by AudioEngine and manual timing | Spine and timing detail | Source, BPM, presets, Auto, tap, transport, beat, bar, cycle, phase, elapsed |
| LFO | `Bindings` LFO sources plus advanced-LFO addendum | Parameter chip and PATCH | Expose shape, rate, amplitude now; advanced controls only when advertised |
| MIDI | `Bindings` MIDI learn | Parameter and bindings table | Slot scoped, live input, pause, clear, dormant |
| Binding matrix | `Bindings` | PATCH modulation | Source to slot and input name, depth, offset, curve |
| Movie Recorder | Output recorder addendum | Spine, SYSTEM, and lifeboat | Ready, arm, quantize, record, duration, Stop, error |
| Image capture | Output still-capture addendum | Record menu | Separate action and nonblocking completion |
| Main output and display | Mixer master into `Output` | Program monitor and SYSTEM | Window, Syphon, display, failover, program truth |
| FX asset save and recall | Chain serialization | FX racks | Change a chain without unrelated show state |
| Show state | `SceneState` plus administration addendum | Scene bank | Existing save and recall now; rename, duplicate, dirty, protected overwrite when advertised |
| Common pane actions | Cockpit components | Relevant objects | Search, bypass, collapse, remove with undo, reset scope |
| Resolution and FPS | Engine telemetry | Deck summaries and spine | Real values only; project cadence is authoritative in v1 |

### B.5 VDMX migration acceptance

The migration passes only if every inventory row above has a cockpit destination, the worked example is possible without floating windows, shader-specific resets cannot be mistaken for blackout, repeated FX instances retain identity, and the resulting composition feels native to the new art direction rather than reskinned VDMX.

## Appendix C. Executive art direction and visual system

### C.1 Direction name and core statement

**Adaptive Cybernetic Cockpit**

The interface is a precision audiovisual instrument whose internal state is visibly alive. It combines the legibility and physical confidence of a professional mixing console with the signal diagrams, telemetry, modular frames, and restrained speculative character in the inspiration set.

The interface should continuously communicate:

1. What is available.
2. What is selected.
3. What is actively changing.
4. What is modulating it.
5. What TouchDesigner actually applied.
6. Whether the output path is healthy.
7. What will happen if the operator touches the next control.

The target is a live machine, not a themed website.

### C.2 Desired impression

- Technical without being clinical
- Futuristic without becoming fictional
- Dense without becoming illegible
- Dark without losing contrast
- Animated without becoming restless
- Powerful without requiring hidden knowledge
- Custom-built without breaking familiar control behavior
- Ready for live performance rather than staged for a screenshot

### C.3 Composition and visual budget

The composition balances dense operational islands with generous negative space. The output media remains the dominant source of color and complexity.

Each major view has:

- One unmistakable visual anchor
- Two to four secondary operational zones
- One stable global truth spine
- A small number of semantic accents
- A clear path from overview to detail
- No field of equal-weight competing panels

Directional budget:

| Layer | Approximate share |
|---|---:|
| Neutral instrument surface | 65 to 75 percent |
| Media, real plots, and live telemetry | 15 to 25 percent |
| Semantic accent color | 5 to 10 percent |
| Atmospheric ornament | Less than 5 percent |

This is a compositional guide, not a literal pixel quota.

Signature tensions:

- Hard geometry against organic moving media
- Cold machine state against warm operator intent
- Stable structure against living signal behavior
- Large status anchors against exact secondary detail
- Dense controls against empty breathing zones
- Monochrome chrome against saturated shader output

### C.4 North-star test

At any moment, the operator should answer the following without opening another tool:

> What is producing the current output, what is changing it, and what is safe to touch next?

An element that does not answer that question, establish hierarchy, or reinforce actual state should be removed.

### C.5 Design principles

#### Instrument first

Every visible frame, trace, marker, number, and animation represents capability or state. Extract precision from the HUD references without copying fictional decoration.

#### Preserve capability, remix geography

Keep the VDMX concepts that support muscle memory, but reorganize them by frequency, context, and risk.

#### Stable global geography

Global truth never moves when the selected deck or mode changes.

#### Progressive disclosure

The first layer exposes show control, the second exposes parameters and mappings, and the third exposes routing and diagnostics.

#### Functional density with hierarchy

Dense information is welcome when titles, current state, selected object, and primary action remain immediately legible.

#### State before style

Color, luminance, line weight, geometry, and motion communicate real state before decoration.

#### Cybernetic causality

Show the base value, external influence, effective result, visual consequence, and TD acknowledgement as one understandable loop.

#### Quiet by default

Idle surfaces are almost still. Motion appears for signals, pending operations, touched controls, recording, or changed health.

#### Media sovereignty

The generated image is the product. Interface chrome frames it without competing.

#### Safety is architectural

Blackout, output health, record, and faults are primary composition elements, not settings.

#### No invisible modes

`PERFORM`, `PATCH`, `SYSTEM`, MIDI learn, armed recording, routing edit, and blackout all have persistent explicit state.

#### Touch and pointer parity

Hover can explain. It cannot be required.

#### Graceful degradation

Reduced preview and telemetry simplify the surface without hiding system truth.

### C.6 Color tokens

| Token | Value | Primary use |
|---|---:|---|
| `--bg-void` | `#050608` | App canvas and deepest negative space |
| `--bg-panel` | `#0C0F12` | Primary instrument regions |
| `--bg-raised` | `#14191E` | Selected cards and drawers |
| `--bg-active` | `#1B2228` | Pressed and active editing surfaces |
| `--line-subtle` | `#252C32` | Dividers, grids, inactive frames |
| `--line-strong` | `#627078` | Functional boundaries and high-value separation |
| `--text-primary` | `#F0F4F2` | Primary labels and critical values |
| `--text-secondary` | `#A4AFB2` | Secondary labels and descriptions |
| `--text-muted` | `#808D93` | Inactive metadata that remains readable |
| `--focus-ring` | `#F0F4F2` | Dedicated keyboard focus ring |
| `--signal-cyan` | `#2AD9D5` | Cool signal color family; spatial channel defines live, connected, or A |
| `--intent-coral` | `#FF5A3D` | Warm intent color family; spatial channel defines action or B |
| `--state-success` | `#64E68E` | Confirmed healthy or complete |
| `--state-warning` | `#FFD15A` | Pending, armed, fallback, degraded |
| `--state-critical` | `#FF3B50` | Fault, recording, destructive |
| `--state-modulation` | `#B18CFF` | Modulation and binding relationships |

Color rules:

- Neutral surfaces occupy most of the interface.
- Cyan and coral are the signature pair.
- Green means confirmed health or completion only.
- Amber means pending, armed, fallback, unresolved, or degraded.
- Red means fault, recording, destructive, or unsafe.
- Violet means modulation and derived influence only.
- State is paired with text, shape, icon, or position.
- Broad neon gradients are prohibited.
- A/B identity is reinforced by explicit labels and spatial association.
- Glow is limited to a restrained 4 to 8 px signal bloom on rare high-value states.
- Normal-size text targets at least 4.5:1 contrast against every surface on which it appears.
- Functional boundaries, focus, selected geometry, and non-text state indicators target at least 3:1 against adjacent surfaces.
- `--line-subtle` is decorative or redundant. It is never the only boundary, grouping, hit-area, selection, or state indicator.

Independent state channels:

- A/B assignment owns a fixed letter chip and narrow assignment edge.
- Enabled or live state owns a signal dot and toggle position.
- Selection owns a raised surface and neutral white or steel state notch. Coral may accent the label but is not the only selector.
- Keyboard focus owns a dedicated high-contrast offset ring.
- Recording owns a red dot, timer, and recorder-specific frame.
- Fault owns a red boundary, fault icon, and recovery copy.
- Blackout owns the unique global treatment in C.13.

### C.7 Typography

Fonts are packaged locally:

- **Space Grotesk Variable:** navigation, panel titles, labels, and large identifiers
- **IBM Plex Mono Variable:** values, time, BPM, dimensions, diagnostics, paths, and tables

CSS fallback stacks:

- Operational: `"Space Grotesk", "IBM Plex Sans", "Helvetica Neue", Arial, sans-serif`
- Numeric: `"IBM Plex Mono", "SFMono-Regular", Consolas, "Liberation Mono", monospace`

Font loading failure must preserve control geometry, values, and legibility with the fallback stack.

Thin cinematic type is not used for operational text.

| Role | Size | Weight | Treatment |
|---|---:|---:|---|
| Utility and metadata | 14 px | 450 to 500 | Secondary, normal case |
| Control label | 15 px | 500 | High contrast |
| Body and value | 16 px | 450 to 550 | Default readable layer |
| Panel title | 18 px | 550 to 600 | Region anchor |
| Mode or major section | 24 px | 600 | Limited use |
| Deck or channel identifier | 36 px | 600 | Spatial landmark |
| Primary metric | 48 px | 500 to 600 | BPM, output, duration |
| Hero status | 64 px | 550 to 650 | Rare critical orientation |

Rules:

- No important or interactive text below 14 px.
- Use tabular lining numerals for changing values.
- Uppercase is limited to short modes, states, deck identities, and authority labels.
- Long names and paragraphs remain mixed case.
- Uppercase tracking is `0.05em` to `0.08em`.
- Numeric columns align by decimal.
- Long shader names preserve their distinguishing suffix through a dedicated full-name line or deterministic center-aware truncation.
- Tooltips are not the only path to a complete name.
- Hierarchy uses size and weight before extra color.
- Control and label line-height is about `1.2`.
- Body and explanatory line-height is about `1.4`.
- Large metric line-height is `1.0` to `1.1`.

### C.8 Spacing and density

Use a 4 px base grid.

| Token | Use |
|---:|---|
| 4 px | Tight internal separation |
| 8 px | Icon and label separation |
| 12 px | Compact control padding |
| 16 px | Standard panel padding and gutter |
| 24 px | Major region separation |
| 32 px | Strong compositional break |
| 48 px | Large negative-space interval |

Operational dimensions:

- Standard row height: at least 40 px
- Standard hit target: at least 44 x 44 px
- Show-critical target: 52 to 56 px
- Compact icon: 20 px inside a 44 px target
- Fader and crossfader handle: at least 44 px effective area
- Panel header: 40 to 48 px
- Destructive touch control: at least 56 px and explicitly labeled
- Gap between adjacent destructive or mutually exclusive controls: at least 8 px

`PERFORM` uses fewer and larger controls with almost no nested scrolling. `PATCH` may use compact grouped rows. `SYSTEM` may use dense tables, but never smaller text.

### C.9 Linework and geometry

- Default border: 1 px `--line-subtle`
- Active boundary: 2 px semantic accent
- Keyboard focus ring: 2 px `--focus-ring` with a 2 px offset, independent from active state
- Safety boundary: 3 px where required
- Default radius: 2 px
- Drawer radius: no more than 4 px
- Large overlay radius: no more than 8 px
- High-authority controls use squared geometry
- Corner cuts appear only on selected high-level objects
- Background grid intervals: 8, 16, or 32 px at 2 to 5 percent opacity
- Tick marks and coordinate lines correspond to real ranges
- Dividers align across neighboring panels
- Depth comes from surface value, border strength, and overlap
- Heavy drop shadows and soft consumer card depth are prohibited
- Functional boundaries meet the 3:1 non-text contrast target. `--line-subtle` remains decorative or redundant.

### C.10 Iconography

- Start from one coherent outline family.
- Use 1.5 px strokes and 20 px default icons.
- Use 24 px for high-authority icons.
- Prefer precise square terminals over rounded consumer styling.
- Pair unfamiliar icons with labels.
- Blackout, reset, save, delete, record, and output routing always have text.
- Animate an icon only for real pending or live state.

### C.11 Surface texture

Allowed:

- Almost invisible static grid
- Very low-amplitude monochrome noise
- Real telemetry traces
- Thin coordinate markers
- Subtle preview vignette

Prohibited:

- Fake scanlines
- Persistent chromatic aberration
- Legibility-reducing grain
- Random alphanumeric noise
- Decorative crosshairs
- Blurred glass panels that weaken contrast

### C.12 Signature motifs

#### Signal rail

A 2 to 4 px signal rail indicates an actual source, route, or processing path. It does not indicate generic selection, keyboard focus, warning, or modulation. If one object must show multiple real signal facts, use physically separated labeled rail segments.

#### Measured frame

High-value regions can use a thin frame with ticks or a scale only when the marks describe a real value.

#### Large identifier

Deck numbers, scene numbers, BPM, modes, and output status can become large spatial landmarks.

#### Living trace

Audio, LFO, timing, modulation, and render health can use restrained data-driven traces.

#### State notch

A small neutral bracket or corner cut is reserved for the selected object. Armed state uses its amber boundary and explicit text instead.

### C.13 State treatments

| State | Visual treatment |
|---|---|
| Idle | Neutral surface, subtle boundary, readable identity |
| Hover | Optional surface lift and stronger boundary |
| Pressed | Immediate luminance shift in 60 to 80 ms |
| Selected | Raised surface, neutral steel or white state notch, and explicit selection label; optional coral text accent only |
| Enabled | Cyan indicator plus `ON`, `LIVE`, or switch position |
| A side | Cyan edge plus `A` label |
| B side | Coral edge plus `B` label |
| Modulated | Violet source marker, modulation range, base and effective values |
| Pending | Amber progress and operation label |
| Armed | Amber boundary plus `ARMED` |
| Recording | Red state, timer, destination, and Stop |
| Success | Temporary green acknowledgement that settles to neutral |
| Warning | Retained amber state until recovery or acknowledgement |
| Fault | Red boundary, plain-language cause, and recovery action |
| Disabled | Reduced contrast with readable identity and reason |
| Disconnected | Broken signal marker, stale label, reconnect status |
| Scene dirty | Amber `MODIFIED` badge beside the scene identity |
| Stale preview | Timestamped `PREVIEW STALE` hatch over preview only, never over program truth |
| Read-only observer | Persistent `VIEW ONLY` owner badge and disabled-write reason |
| Superseded | Neutral `SUPERSEDED` completion state that yields to the surviving operation |
| Partial scene recall | Amber `PARTIAL RECALL` with affected deck list and recovery |
| Autosave pending or failed | Amber `SAVING` or red `AUTOSAVE FAILED` beside scene state |
| Blackout | Unique global treatment defined below |

Canonical blackout treatment:

- `BLACKOUT OFF`: neutral squared 56 px minimum control with explicit `BLACKOUT OFF`. The program boundary remains normal.
- `BLACKOUT ON`: solid 3 px `--state-critical` boundary around the actual program region, inverse high-contrast `BLACKOUT ON` label in the system spine and lifeboat, visibly suppressed program region, and a latched control geometry that cannot be confused with recording or fault.
- `BLACKOUT HOLD`: the same suppressed output plus a static critical striped edge and explicit `BLACKOUT HOLD`. It does not depend on pulse or animation.
- Browser and lifeboat display the same authoritative latch and hold state.
- If preview is stale, the global blackout boundary and label remain visible outside the preview surface.
- Reduced motion does not change the blackout presentation.
- `RESET SHADER` never uses blackout's squared size, global frame, inverse label, or striped hold treatment.

### C.14 Motion and feedback

| Interaction | Duration |
|---|---:|
| Press feedback | 60 to 80 ms |
| Toggle or selection | 100 to 140 ms |
| Value response | One browser frame or data-driven |
| Drawer expansion | 160 to 200 ms |
| Inspector replacement | 160 to 220 ms |
| Mode transition | 200 to 240 ms |
| Success confirmation | 600 to 1000 ms before settling |
| Record pulse | About 1000 ms |
| Connection warning pulse | About 1400 ms |

Preferred easing:

- Direct response: linear or `cubic-bezier(0.2, 0, 0, 1)`
- Panel entrance: `cubic-bezier(0.22, 1, 0.36, 1)`
- Panel exit: `cubic-bezier(0.4, 0, 1, 1)`

Rules:

- Local control response never waits for the network.
- Canonical TD state catches up without an ornamental delay.
- Continuous gestures retain only the newest value per target.
- Meters may smooth. Safety and connection state may not.
- No hue cycling, spring, overshoot, drift, parallax, or breathing.
- Repeating pulse is reserved for record, pending connection, and unresolved warning.
- Ambient traces stop or simplify under reduced motion.
- The full information model works with nonessential animation disabled.

### C.15 Data-reactive GPU environment

The atmospheric field is a live visualization of the cockpit's cybernetic loop. It may be visually rich, spatial, and generative, but it remains quieter than program media and subordinate to instrument legibility.

Approved visual behaviors include:

- Custom GLSL fields whose topology responds to normalized audio energy
- Instanced or shader-generated particles that mark real kick, beat, or modulation activity
- Routing filaments that illuminate only for active semantic routes
- Spatial compression and release tied to pending and acknowledged operations
- Palette bias derived from the selected A/B side without replacing its structural label
- An unmistakable but supplementary environmental change during recording, degraded connection, or critical fault
- Coherent scene-level transitions when authoritative cockpit mode or selection changes

Disallowed behaviors include:

- Random activity presented as telemetry
- A permanent demo animation when the instrument is idle
- Camera drift, ambient parallax, layout breathing, or movement under the pointer
- Broad bloom that lowers text contrast
- Perspective transforms on operational controls
- Per-component WebGL contexts
- GPU effects that intercept pointer events or alter control geometry
- A visual response that claims a command succeeded before TD acknowledgement

The atmosphere uses one shared renderer and a bounded resource profile. It stops its animation loop while the document is hidden, disposes every GPU resource on teardown, handles WebGL context loss without reload, clamps device pixel ratio, and steps down quality before the established TD render, control-latency, or browser-frame budgets are lost. Reduced motion renders a stable, data-derived frame without continuous particles, pulses, or shader-time evolution.

## Appendix D. Component and interaction specification

### D.1 Library item

Each item displays:

- Full shader name
- Generator, filter, or transition type
- Categories
- Pass count
- Parse status
- Load compatibility
- Favorite state
- Preview when available

Actions and behavior:

- Tap selects and previews.
- Explicit `LOAD D1`, `LOAD D2`, `LOAD D3`, and `LOAD D4` buttons support touch.
- Pointer users may drag to a deck, but drag is optional.
- Loading preserves the current visual until commit.
- Failure leaves the active deck unchanged and exposes a concise error.
- Thumbnails pause or reduce when render health falls.
- V1 sends `loadTiming: "immediate"`, which starts the build now and commits only after compile and warm-up. Scheduled and beat-quantized commits remain hidden without their capability.

### D.2 Deck card

Each card displays:

- Large deck number
- Current A/B role, with assignment control only when `dynamicAB` exists
- Live or stale preview
- Active shader full identity
- Shader type
- Resolution
- Deck FPS or health
- Opacity
- Blend
- Source route
- FX instance count when a rack exists
- Active binding count when bindings exist
- Loading, fallback, bypass, and error state

Primary actions:

- Select deck
- Change opacity
- Assign A or B when `dynamicAB` exists
- Change blend
- Enable or bypass
- Load from library
- Open parameters
- Open FX when a rack exists
- Open routing

Selection uses geometry, label, and color together.

### D.3 Generated parameter control

Every parameter displays:

- Human-readable label
- Exact base value
- Default
- Range or options
- Modulation contribution when present
- Effective value when present
- Reset action
- Binding entry point when bindings exist
- Pin-to-PERFORM action

Type behavior:

| ISF type | Control |
|---|---|
| float | Slider, numeric entry, fine adjustment |
| long or enum | Menu or segmented selector |
| bool | Labeled toggle |
| color | Swatch, channel values, color editor |
| point2D | Linked XY surface plus numeric fields |
| event | Momentary labeled action with explicit scope |
| image | Source-route selector and health |
| audio or audioFFT | Audio-source status and routing only when the player reports texture support |

A modulated slider uses three layers:

1. Base thumb
2. Modulation range or offset
3. Effective-value marker

The base thumb does not move unpredictably with modulation.

### D.4 Shader inspector

The inspector includes:

- Shader identity and file
- Compile and load state
- Input search
- Metadata groups
- Pinned macros
- Full parameter list
- Per-control reset
- Group reset
- Shader reset
- Shader event controls
- Binding summary
- Source input routing
- Error details

The legacy `PANIC RESET` event becomes `RESET SHADER` with an explicit `D2 SHADER` or equivalent scope. It must not visually resemble global `BLACKOUT`.

### D.5 FX rack

Each instance includes:

- Stable instance index or user label
- Effect name
- Scope such as `D2 FX` or `MASTER FX`
- Enable
- Bypass
- Wet/Dry
- Blend
- Expand
- Reorder
- Duplicate
- Remove
- Error state

Behavior:

- Repeated effects receive distinct identity, such as `AR_HyperTesseract_v03 03`.
- Reordering displays an insertion point.
- Remove has a short undo window.
- Wet/Dry remains available when collapsed.
- The expanded instance owns the inspector.
- Master and deck scopes differ structurally and textually.
- A real signal strip reads `DECK -> DECK FX -> MIXER -> MASTER FX -> MASTER LEVEL -> BLACKOUT -> OUTPUT`, omitting only stages the engine does not support.

The rack component appears only for the supported scope and reports structured limits such as maximum instances, reorder, duplicate, blend, and preset support.

### D.6 Performance mixer

The mixer contains:

- Four contribution faders
- Deck visibility or enable
- Current A/B role and assignment when `dynamicAB` exists
- A/B crossfader
- Per-deck blend
- Strobe: amount, bass cutoff, decay, and momentary hold. The strobe is an envelope-driven invert flash (low-end envelope vs `Strobe Cutoff`, release via `Strobe Decay`, per the 2026-07-26 redesign `fd6bf1c`); it has NO beat/meter timing and no Clock dependency — the surface must not present tempo-locked strobe controls.
- Master level when `masterLevel` exists
- Master FX global bypass
- Blackout

Behavior:

- The crossfader is the largest continuous control.
- Continuous controls capture pointer or touch.
- Scroll cannot steal a mixer gesture.
- Exact values remain visible.
- Fine mode has an explicit affordance plus keyboard convenience.
- Reset is an explicit action, not double-tap only.
- Blackout is one-touch, latching, and has no confirmation dialog.
- Blackout state uses label, geometry, and color.
- Scene recall cannot alter blackout.

### D.7 Source routing

The routing surface includes:

- Destination deck and image input
- Test pattern
- Camera or capture
- Another deck output
- Supported external source
- Current requested source
- Current actual or fallback source
- Health and resolution
- Self-route warning

Behavior:

- A missing source engages and labels `SAFE SOURCE`.
- Self-routing is blocked before a command is sent.
- Requested and actual source remain distinguishable.
- A filter with no assigned image never silently produces an empty texture.

### D.8 Audio surface

Compact view:

- Input health
- BPM and phase
- Loudness
- Bass, mid, and high
- Kick activity
- `LIVE` or `HELD`

Detailed view:

- Device — known caveat: as of `49682eb` the engine's `audiodevin_mic.device` is a hardcoded `BlackHole2ch_UID` constant and the `Device` custom par is disconnected; the par must be re-wired (par value = device UID, expression restored) before this control ships, or a cockpit write to it silently no-ops
- Analyzer
- Gain
- Attack
- Release
- Kick sensitivity
- Low and high band split frequencies when `audio.bandSplit` exists
- Trigger threshold and hysteresis when `audio.triggerShape` exists
- Trigger inversion when `audio.triggerInvert` exists
- `band1` through `band8`
- Real graphs
- Dropout history

On dropout, values hold according to the AudioEngine contract and the UI displays `AUDIO HELD`. Frozen values cannot masquerade as live analysis.

### D.8.1 Clock and transport

The dedicated Clock addendum owns global show timing rather than treating analyzer BPM as a complete clock.

Compact spine view:

- Timing source: audio, manual, or supported external clock
- BPM
- Beat phase
- Run or paused
- Beat, bar, and cycle position
- Elapsed show time

Detailed view:

- Source selector
- Manual BPM
- Quick presets `44`, `88`, `120`, and `160`
- User-editable preset values after initial parity
- `AUTO` analysis toggle when audio timing is supported
- Tap tempo
- Run
- Pause
- Reset
- Beat, bar, cycle, and subdivision counters
- Phase
- Elapsed time

The current audio-derived `bpm` and `beat_phase` remain visible before the Clock addendum exists, but controls that imply manual or transport authority remain hidden. Scheduled shader load and quantized record read the same Clock authority when their capabilities are installed.

### D.9 LFO editor

The editor includes:

- Waveform
- Rate
- Amplitude
- Target
- Depth
- Effective output

Phase, clock sync, measures, loop, direction, scratch or phase offset, and pause appear only when their individual LFO capability fields are true.

A compact violet LFO chip appears beside each bound target and opens the editor.

### D.10 MIDI learn

Flow:

1. Focus a parameter.
2. Select `LEARN MIDI`.
3. Display an explicit armed state.
4. Receive the moved control.
5. Bind controller, channel, and control ID to slot plus input name.
6. Confirm with text and live activity.
7. Expose Pause, Clear, and Relearn.
8. Preserve name-stable mapping across shader swaps.
9. Show `DORMANT` when the target input is missing.

MIDI learn is absent from controls until the engine advertises MIDI input and learn support. If a learned device later disconnects, the mapping remains visible with device health.

### D.11 Binding matrix

Every row shows:

- Enabled
- Source
- Slot
- ISF input name
- Depth
- Offset
- Curve
- Resolved or dormant
- Current source value
- Current effective target value

Parameter-first creation is the primary workflow. The table is for overview and exact editing, not the only creation path.

### D.12 Recorder

States:

- Unconfigured
- Ready
- Armed
- Waiting for quantize
- Recording
- Stopping
- Complete
- Error

The recorder component is absent from performance controls until recorder support exists. If a configured recorder later becomes unavailable, it remains visible with explicit health and recovery state.

Persistent information:

- State label
- Duration
- Video source
- Audio source
- Destination
- Dropped-frame warning
- Stop

Video and still capture are separate actions. A completed capture produces a nonblocking filename confirmation.

### D.13 Scene bank

The scene surface includes:

- Scene slots
- Current scene
- Recall
- Capture new
- Autosave state

Dirty state, protected overwrite, rename, duplicate, and detailed partial recall appear only when scene-administration capabilities advertise them.

Recall is one touch in `PERFORM`. Overwrite uses intentional hold or explicit confirmation. Blackout and output geometry are excluded.

### D.14 Output and system health

The output surface shows:

- Program resolution
- Program FPS
- Preferred display
- Actual display
- Window state
- Syphon state
- Recorder state
- Failover state
- Browser connection
- Control ownership
- Last protocol error

The central monitor represents the actual program path after master FX, master level when present, and blackout. If blackout is active, the monitor and global state say so explicitly even if an optional preview transport is stale.

### D.15 Common interaction states

| State | Required behavior |
|---|---|
| Default | Neutral surface, identity, current value |
| Hover | Optional explanation only |
| Focus | Strong keyboard focus ring |
| Pressed | Immediate tactile luminance response |
| Selected | Structural boundary and text |
| Active | Explicit `ON`, `LIVE`, or equivalent |
| Bypassed | Explicit `BYPASS` and reduced processing emphasis |
| Disabled | Discoverable reason |
| Loading | Phase label while current output remains |
| Armed | Distinct from active |
| Modulated | Base, influence, and effective result |
| Dormant | Mapping retained, target unresolved |
| Fallback | Safe source distinguished from requested |
| Warning | Degraded but usable |
| Fault | Cause and recovery path |
| Blackout | Global latched safety state |
| Disconnected | Scope, stale state, and reconnect |

### D.16 Live-performance gesture discipline

- Blackout, scene recall, record Stop, crossfade, and deck opacity are one gesture away.
- Shader parameters, FX editing, and bindings are at most two gestures from the selected deck.
- Continuous controls capture their gesture.
- Scroll regions do not steal faders.
- Destructive configuration uses hold, undo, or confirmation.
- Live recovery avoids blocking confirmation dialogs.
- Numeric regions do not shift when digit count changes.
- Toasts never cover blackout, master, crossfader, record Stop, or output health.
- Keyboard and MIDI access augment visible controls and never replace them.

### D.17 Accessibility contract

The cockpit targets WCAG 2.2 AA behavior for text, focus, keyboard access, status, and reflow wherever a live audiovisual control surface can reasonably comply.

Focus order follows stable geography:

1. System spine, beginning with mode and ending with safety
2. Library rail or its open trigger
3. Central stage and deck cards
4. Context inspector or its open trigger
5. Performance mixer
6. Modulation and diagnostics drawer

Focus behavior:

- Opening a drawer moves focus to its heading or first meaningful control.
- Escape closes the top drawer and restores focus to its trigger.
- Focus cannot disappear behind a closed region.
- A focus trap is used only for a true blocking confirmation, never for normal drawers.
- Mode changes restore focus to the corresponding mode heading without moving persistent global controls.
- `VIEW ONLY` is announced and remains visibly persistent.

Control semantics:

- Use native `button`, `input`, `select`, and range semantics where practical.
- Custom faders expose accessible name, `aria-valuemin`, `aria-valuemax`, `aria-valuenow`, and value text.
- Arrow keys adjust sliders and XY controls. Shift provides the documented fine step. Home and End move to limits where safe.
- Menus and segmented controls follow standard keyboard behavior.
- Momentary controls announce pressed state and scope.
- Disabled controls expose an accessible reason.
- Every icon-only convenience has an accessible name even when a visible label appears nearby.

Status behavior:

- Rapid telemetry, meters, beat phase, and modulation traces are excluded from live-region announcements.
- Shader load completion, recorder state, connection loss, and device failure use restrained polite announcements.
- Blackout engagement and critical output loss use an assertive announcement.
- Repeated samples do not re-announce unchanged state.

Reflow and contrast:

- The interface remains operable at 200 percent browser zoom or an equivalent text-resize setting.
- Compact reflow may convert the library and inspector to drawers and decks to a labeled horizontal strip.
- Safety controls never require two-dimensional page scrolling.
- Automated token tests cover 4.5:1 normal text and 3:1 meaningful non-text boundaries.
- Grayscale and common color-vision simulations remain understandable because labels, shape, and position carry state.

## Appendix E. UI platform and connectivity decision

### E.1 Selected architecture

The primary UI is a Svelte 5 application written in TypeScript and built by Vite. TouchDesigner serves the static production files and hosts the local control services through Web Server DAT operators inside `ControlBridge`.

```text
SVELTE 5 SPA
    |
    | HTTP
    | app, bootstrap, library, thumbnails, health
    |
    | RELIABLE WEBSOCKET
    | commands, ack, snapshot, delta, lifecycle, safety, errors
    |
    | DROPPABLE WEBSOCKET
    | audio, modulation, timing, performance telemetry
    |
    | OPTIONAL MEDIA LANE
    | low-resolution previews
    v
/project1/ControlBridge
    |
    | semantic adapters
    v
DECKS, MIXER, SOURCE ROUTER, AUDIO ENGINE, BINDINGS,
OUTPUT, SCENE STATE, ISF PLAYER
```

The browser is a renderer and controller. TouchDesigner is the sole authority for performance state.

### E.2 Why Svelte

Svelte is selected because it provides:

- Compiled, granular updates suitable for many independent controls and meters
- A small production runtime
- Direct TypeScript support
- Predictable custom component composition
- Strong CSS control for a bespoke instrument aesthetic
- A simple static build that needs no production application server
- A maintainable reactive model without a large framework abstraction layer

Solid is the performance runner-up. Its fine-grained reactivity is technically strong, but Svelte offers a better balance of authoring clarity, compiled output, community familiarity, and long-term maintainability for this single-operator tool.

React is not selected. Its ecosystem size does not solve a missing requirement, and its default mental model adds runtime and update-management overhead to a dense control surface.

### E.3 Why native WebSocket

The browser and TouchDesigner both support WebSocket without an extra relay. A direct local socket provides:

- Ordered reliable command delivery
- Full-duplex state events
- Low local overhead
- Browser-native support
- Binary telemetry and preview options
- Explicit backpressure visibility through `bufferedAmount`
- A small protocol surface under project control

OSC is useful for hardware and musical control, but a browser has no native OSC transport. Adding an OSC relay would add another process, another schema translation, and another failure boundary. OSC remains available inside TouchDesigner for hardware integrations but is not the cockpit protocol.

Socket.IO is not selected because reconnection and message envelopes are simple enough to own, and its server runtime would add an unnecessary dependency.

REST polling is not used for continuous state. HTTP is reserved for bootstrap, cached content, and health.

### E.4 Why TouchDesigner serves production

The Web Server DAT can serve HTTP and communicate with WebSocket clients inside the same TouchDesigner project. This removes a separate live server and aligns runtime lifecycle with the instrument.

The Vite build uses relative asset paths and creates a self-contained `dist/` folder. Production does not run Vite's development server.

Suggested repository shape:

```text
webui/
  package.json
  vite.config.ts
  src/
  static/
    fonts/
    icons/
  dist/
  protocol/
    instrument-api-v1.schema.json
    fixtures/
project1/
  ControlBridge.tdn
  ControlBridge/
    InstrumentApiExt.py
    webserver_callbacks.py
    protocol.py
    adapters/
```

The exact externalization shape must follow the existing Embody and TDN conventions at implementation time.

### E.5 Alternatives reviewed

| Approach | Verdict | Reason |
|---|---|---|
| Svelte 5 plus TD Web Server DAT | Selected | Lean static UI, direct local transport, no show-time middleware |
| Solid plus TD Web Server DAT | Runner-up | Excellent reactivity, smaller maintainability advantage for this operator |
| React plus local API | Rejected | Extra runtime and complexity without a project-specific benefit |
| TouchDesigner Panel COMPs only | Lifeboat only | Direct authority, but weaker web-grade layout and styling; standard panel touch behavior and macOS Multi Touch limitations make it a poor primary surface |
| Web Render TOP | Rejected as primary | Adds a separate browser process and render-transfer coupling inside TD on macOS |
| Tauri wrapper | Deferred | Useful only if signed desktop packaging and window lifecycle become requirements |
| Node.js or FastAPI middleware | Rejected | Extra process, extra latency boundary, more show-time failure modes |
| Socket.IO | Rejected | Features exceed the simple local protocol need and require a server runtime |
| OSC bridge | Rejected for browser path | Browser needs a relay, which duplicates the control contract |
| WebRTC for all transport | Rejected | Appropriate for media, unnecessarily complex for controls |

### E.6 Web Render TOP and native Panel role

Web Render TOP is not the primary composition path. It runs Chromium in a separate process and on macOS transfers rendered content back to TouchDesigner. This creates a coupling between browser repaint and TD rendering that provides no advantage when the operator can use the browser directly.

Native Panel COMPs remain important for the lifeboat. The [Multi Touch In DAT](https://derivative.ca/UserGuide/Multi_Touch_In_DAT) is not supported on macOS, and standard Panel COMP touch semantics do not provide the same multi-pointer interaction model as browser Pointer Events. The primary UI therefore uses web pointer events, while native panels hold only the safety and recovery subset.

### E.7 Preview decision

Preview media is a separate concern from control.

V1 target:

- Program preview at 640 x 360 and 15 fps
- Selected deck preview at lower priority
- Binary compressed frames or a similarly isolated local stream
- On-demand cached shader thumbnails
- Latest-frame-wins queue with a queue length of one
- Automatic degradation to 480 x 270 at 5 fps
- Complete disablement before any render-frame loss

The preview path should target less than 100 ms p95 glass-to-glass latency locally, but it is subordinate to render health and control responsiveness.

WebRTC may be evaluated later for 15 to 30 fps preview at 640 x 360 or 960 x 540. Official TouchDesigner guidance warns about CPU cost at higher resolutions, and the macOS support boundary must be verified. WebRTC is accepted only if measured separately with preview on and off.

### E.8 Browser rendering architecture

The production browser uses one compositor with distinct responsibilities:

```text
SVELTE / DOM
controls, labels, focus, safety, layout
        |
SVG / CSS / 2D CANVAS
exact plots, traces, routing, component feedback
        |
THREE.JS / WEBGL
one shared pointer-transparent atmospheric field
        |
EXISTING INSTRUMENT STORE
validated state and bounded telemetry only
```

Three.js `0.185.1` and `@types/three` `0.185.1` are the approved implementation pins. Custom GLSL runs through the shared Three.js renderer. No second animation framework, p5.js runtime, post-processing server, new socket, or browser-to-TD media round trip is required.

The Three.js layer imports typed selectors from the instrument store. It cannot import `InstrumentClient`, create a `WebSocket`, call `fetch`, or send a command. This dependency direction is enforced by tests. The visual environment receives immutable signal frames, while Svelte retains all operational authority.

## Appendix F. ControlBridge contract

### F.1 Proposed COMP

```text
/project1/ControlBridge
├── InstrumentApiExt
├── webserver_http_control
├── webserver_control_callbacks
├── webserver_telemetry
├── webserver_telemetry_callbacks
├── table_command_queue
├── table_event_log
├── timer_telemetry
└── info_server

/project1/SessionIdentity
/project1/SafetyState
/project1/UiLifeboat
```

`InstrumentApiExt` is renderer-neutral. It exposes semantic state and actions without exposing TD operator paths.

`SessionIdentity`, `SafetyState`, and `UiLifeboat` are siblings rather than children of `ControlBridge`. Their startup and minimum safety path remain available if the bridge extension, command queue, or web services fail. `SessionIdentity` also owns the durable-in-session protocol revision, complete plain branch state, active command records, and partitioned terminal dedupe ledgers so a bridge reinitialization cannot reuse a stable session ID with reset protocol state.

Responsibilities:

- Build complete snapshots from authoritative state
- Validate and dispatch whitelisted commands
- Assign engine and state revisions
- Publish structured events and deltas
- Coalesce continuous updates
- Reject stale shader writes
- Deduplicate transactional commands
- Enforce controller ownership
- Keep transport concerns separate from instrument logic

Web Server DAT callbacks parse, validate, enqueue, send an `accepted` acknowledgement, and return. They never claim queued work is already applied. They do not scan the library, compile shaders, capture TOPs, rebuild bindings, or perform heavy work.

### F.2 HTTP surface

| Route | Purpose |
|---|---|
| `/` | Application shell |
| `/assets/*` | Hashed JavaScript, CSS, fonts, and icons |
| `/api/v1/bootstrap` | API version, engine session, capabilities, revisions, nonce, channel URLs |
| `/api/v1/library` | Cached shader library by revision |
| `/api/v1/thumbnail/{shaderId}` | Cached or on-demand preview |
| `/health` | Server, engine, queue, and readiness summary |

Continuous controls never use REST polling.

### F.3 WebSocket lanes

#### `/ws/control`

Carries:

- Commands
- Acknowledgements
- Structured errors
- Complete snapshots
- Revisioned deltas
- Transaction lifecycle
- Safety state
- Controller ownership
- Device and output events

This lane is ordered and never intentionally delayed for telemetry.

#### `/ws/telemetry`

Carries:

- Audio meters
- Beat phase
- Selected modulation traces
- Render FPS
- Frame time
- GPU or memory data when available
- Queue depth and connection stats

Samples are droppable. Latest value wins. Hidden or unsubscribed modules do not publish high-rate telemetry.

The two lanes may use separate Web Server DAT ports. Bootstrap supplies their exact URLs. Neither port may conflict with Envoy's port `9870`.

Connection setup is bounded. Bootstrap fetch, control open, first complete snapshot, control claim, telemetry open, and telemetry replacement each have explicit client deadlines. The server independently closes a control socket that has not received its queued complete snapshot within three seconds. A missed deadline closes only the affected browser transport, disables writes, and starts a fresh-bootstrap retry; it never blocks the native lifeboat.

### F.4 Authority boundaries

| Concern | TouchDesigner authority | Browser responsibility |
|---|---|---|
| Shader playback | Active chain, committed manifest, generated inputs, load state | Selection and progress display |
| Deck state | Opacity, blend, source, base input values | Controls and local inspector selection |
| Mixer | Xfade, contributions, strobe, FX, final blackout | Gesture and canonical feedback |
| Routing | Source validity, self-route, fallback | Source-selection UI |
| Audio | Device, analysis, normalization, dropout policy | Meters and configuration UI |
| Modulation | Binding rows, LFO evaluation, clamping, effective values | Editor and visualization |
| Output | Window, display, Syphon, recorder actual state | Explicit actions |
| Presets | Capture, validation, save, recall, migration | Browser and progress |
| Safety | Blackout, fallback, lifeboat, watchdog | Redundant trigger surface |
| UI composition | None | Selection, drawers, search, sorting, favorites |

Browser-local state includes:

- Selected inspector
- Expanded groups
- Search and filter terms
- Drawer state
- Layout preference
- Favorites if intentionally kept local

Browser-local state is not stored in `SceneState`.

### F.5 Semantic state model

The following is an illustrative base-adapter snapshot before the optional parity addenda and preview lane are enabled:

```json
{
  "apiVersion": 1,
  "engineSessionId": "td-boot-uuid",
  "revision": 883,
  "frame": 192204,
  "capabilities": {
    "decks": {
      "count": 4,
      "independentCadence": false
    },
    "mixer": {
      "dynamicAB": false,
      "masterLevel": false,
      "blendModes": 13
    },
    "fx": {
      "deck": {
        "maxInstances": 0,
        "reorder": false,
        "duplicate": false,
        "blend": false,
        "presets": false
      },
      "master": {
        "maxInstances": 1,
        "reorder": false,
        "duplicate": false,
        "blend": false,
        "presets": false
      }
    },
    "isfInputs": {
      "float": true,
      "long": true,
      "bool": true,
      "color": true,
      "point2D": true,
      "event": true,
      "image": true,
      "audio": false,
      "audioFFT": false
    },
    "audio": {
      "analysis": true,
      "bandSplit": false,
      "triggerShape": false,
      "triggerInvert": false
    },
    "clock": {
      "audioBpm": true,
      "manualBpm": false,
      "auto": false,
      "tap": false,
      "quickPresets": false,
      "transport": false,
      "barCycle": false
    },
    "bindings": {
      "matrix": false,
      "baseModEffective": false
    },
    "lfo": {
      "shape": false,
      "rate": false,
      "amplitude": false,
      "phase": false,
      "clockSync": false,
      "measures": false,
      "loop": false,
      "direction": false,
      "scratch": false,
      "pause": false
    },
    "midi": {
      "input": false,
      "learn": false
    },
    "recorder": {
      "video": false,
      "still": false,
      "quantize": false,
      "directStop": false
    },
    "scenes": {
      "slots": 8,
      "rename": false,
      "duplicate": false,
      "dirty": false,
      "protectedOverwrite": false
    },
    "preview": {
      "program": false,
      "deck": false
    },
    "library": {
      "loadTiming": [
        "immediate"
      ]
    }
  },
  "availability": {
    "audio": {
      "available": true,
      "reason": null,
      "recovery": null
    },
    "output": {
      "available": true,
      "reason": null,
      "recovery": null
    },
    "recorder": {
      "available": false,
      "reason": "NOT_INSTALLED",
      "recovery": "Install and enable the recorder addendum."
    }
  },
  "health": {
    "audio": {
      "state": "live"
    },
    "output": {
      "state": "healthy"
    }
  },
  "decks": [],
  "mixer": {},
  "router": {},
  "audio": {},
  "bindings": {},
  "output": {},
  "scene": {},
  "system": {
    "libraryRevision": 0
  }
}
```

`apiVersion` is independent from the `SceneState` codec version.

`engineSessionId` is generated exactly once by `SessionIdentity` during project startup and survives `ControlBridge` extension reinitialization, Embody reimport, and web-server restart while the outside-bridge protocol state remains valid. A fresh TD project session generates a new ID. Missing, corrupt, or continuity-ambiguous revision or dedupe state rotates the ID before any server becomes ready; an unchanged session ID is never paired with a reset revision or lost transaction ledger.

`system.libraryRevision` is the one authoritative library revision used by snapshot/delta state and `/api/v1/library`. It is a non-negative JavaScript-safe integer and changes only when a complete new library index commits.

`state.delta` is strict top-level branch replacement. `changes` is a nonempty object whose keys are drawn only from `capabilities`, `availability`, `health`, `decks`, `mixer`, `router`, `audio`, `bindings`, `output`, `scene`, and `system`. Each supplied value replaces that complete branch and validates against the same generated schema as the snapshot. No arbitrary paths, partial nested mutations, or deletion sentinels exist.

The main-thread publisher maintains immutable plain branch state and serializes only the bounded changed branches for each revision. It does not rebuild or serialize a complete snapshot at gesture rate. A complete wire snapshot is assembled only for initial connection or forced resynchronization, using the ordered register-copy-enqueue-buffered-deltas procedure. Bootstrap reads cached capabilities, availability, health, state revision, and `system.libraryRevision`; it never traverses TD operators or triggers full-state serialization in a request callback.

The three status layers are distinct:

- `capabilities`: what this build can do and the exact operation limits
- `availability`: whether the supported subsystem is currently present and usable, plus a machine-readable reason and operator-facing recovery when false
- `health`: the live quality or degraded state of a present subsystem

A false capability hides the control outside diagnostics. A supported but unavailable or unhealthy subsystem remains visible with its reason and recovery state. Audio dropout therefore shows `AUDIO HELD`; it does not disappear.

### F.6 Semantic targets

Stable targets use public instrument names:

```text
deck.1.opacity
deck.1.blend
deck.1.input.speed
deck.1.source
deck.1.fx.fx-7f32.wetDry
mixer.xfade
mixer.strobe.amount
mixer.strobe.cutoff
mixer.strobe.decay
mixer.strobe.hold
mixer.masterLevel
mixer.blackout
audio.gain
audio.bandSplitLowHz
audio.bandSplitHighHz
audio.triggerThreshold
audio.triggerInvert
clock.source
clock.bpm
clock.running
binding.17.depth
output.syphonActive
```

TD OP paths and parameter implementation names remain private.

FX targets use immutable `instanceId` values. Rack order is a separate ordered list. Reordering cannot change the target identity or inspector selection.

### F.7 Command envelope

```json
{
  "type": "command",
  "apiVersion": 1,
  "id": "command-uuid",
  "clientId": "perform-console",
  "seq": 301,
  "op": "control.set",
  "target": "deck.1.input.speed",
  "shaderGeneration": 44,
  "value": 0.72,
  "gesture": {
    "id": "drag-91",
    "phase": "update"
  }
}
```

Accepted acknowledgement:

```json
{
  "type": "ack",
  "id": "command-uuid",
  "status": "accepted",
  "acceptedFrame": 192203,
  "operationId": null
}
```

For a transaction, `operationId` is a generated stable identifier and appears on every lifecycle event.

Applied acknowledgement for a fast command:

```json
{
  "type": "ack",
  "id": "command-uuid",
  "status": "applied",
  "revision": 883,
  "appliedFrame": 192204
}
```

Error:

```json
{
  "type": "error",
  "id": "command-uuid",
  "code": "STALE_SHADER",
  "message": "The active shader changed before this control was applied.",
  "revision": 884
}
```

Continuous scalar commands use `clientId`, monotonic `seq`, semantic target, gesture ID, and `shaderGeneration` where relevant. They do not require a global `baseRevision`, which may change during the same drag due to unrelated engine activity.

Each physical browser tab generates one random UUID-based `clientId` for that tab lifetime. Every command and gesture uses a separately generated UUID-based ID; IDs are never derived from sequence numbers and are never reused after reconnect. `seq` starts at zero for each newly authenticated physical control socket and increases for every new command sent on that socket. Reconnect obtains a new bootstrap and resets only the per-connection sequence; the tab identity remains stable and command IDs remain globally unique within the engine session.

Transactional commands include `baseRevision`. Tuple writes are atomic. Blackout commands bypass ordinary stale-revision rejection after authority, nonce, type, and target validation.

Every accepted command ID reaches exactly one terminal outcome:

- Fast scalar: `applied`, `superseded`, or structured `error`
- Transaction: terminal lifecycle event `succeeded`, `failed`, `superseded`, or `cancelled`

If a newer coalesced scalar replaces an accepted value before application, the older ID receives:

```json
{
  "type": "ack",
  "id": "older-command-uuid",
  "status": "superseded",
  "supersededBy": "newer-command-uuid"
}
```

Dedupe retention is partitioned. Active accepted IDs are non-evictable. Completed fast commands use a 2,048-entry LRU scoped to the current engine session. Completed transactional IDs use a separate 4,096-entry session ledger and are never evicted during that engine session; when it is full, new transaction admission returns `BUSY` rather than risking duplicate execution. Scalar and heartbeat traffic therefore cannot churn out scene, output, recording, library, binding, FX, or shader-load outcomes. The ledger and current revision live outside `ControlBridge`. Recovery closes retained active non-safety work with `BRIDGE_RESTARTED` instead of executing it again and reconciles accepted safety engagement against authoritative `SafetyState`.

### F.8 Command families

- `control.set`
- `control.setMany`
- `control.trigger`
- `deck.loadShader`
- `deck.resetInput`
- `router.setSource`
- `fx.add`
- `fx.remove`
- `fx.reorder`
- `fx.duplicate`
- `fx.preset.save`
- `fx.preset.load`
- `scene.save`
- `scene.recall`
- `scene.restoreSession`
- `scene.rename`
- `scene.duplicate`
- `binding.upsert`
- `binding.remove`
- `binding.replaceAll`
- `clock.setSource`
- `clock.setBpm`
- `clock.setAuto`
- `clock.tap`
- `clock.setRunning`
- `clock.reset`
- `clock.setQuickPreset`
- `output.open`
- `output.close`
- `output.setDisplay`
- `output.setSyphon`
- `record.start`
- `record.stop`
- `capture.still`
- `library.reindex`
- `library.cancelReindex`
- `session.claimControl`
- `session.releaseControl`
- `session.heartbeat`
- `telemetry.subscribe`
- `telemetry.unsubscribe`
- `telemetry.reissue`

Every command family is capability-gated. Unsupported commands return `NOT_AVAILABLE`.

`telemetry.reissue` is available to any already bound authenticated control connection after its telemetry socket fails. It returns one fresh 30-second, single-use, telemetry-only loopback URL bound to that control connection, client identity, engine session, and current subscription set. It cannot claim control, open preview, or disturb a healthy control lane.

Fast scalar operations and transactional operations have different scheduling behavior.

Fast controls:

- Opacity
- Crossfader
- Strobe amount
- Gain
- LFO rate
- Shader base values

Transactional operations:

- Shader load
- Scene recall
- Binding replacement
- Library reindex
- Output display change
- Recorder start and stop
- FX-chain mutation

Transactional work is queued and sequenced. Blackout and scalar performance controls remain responsive while a transaction runs.

Concurrency rules:

- Continuous scalar writes use sequence, target, gesture, and shader generation instead of global revision.
- Discrete transactions require `baseRevision`.
- Atomic tuple writes validate and apply as one command.
- Blackout bypasses ordinary stale-revision checks.
- Each accepted transaction emits lifecycle events until it completes, fails, or is superseded.

### F.9 Required error codes

- `INVALID_JSON`
- `INVALID_TYPE`
- `INVALID_MESSAGE`
- `MESSAGE_TOO_LARGE`
- `API_VERSION_MISMATCH`
- `INVALID_TARGET`
- `INVALID_VALUE`
- `OUT_OF_RANGE`
- `STALE_REVISION`
- `STALE_SHADER`
- `SELF_ROUTE`
- `BUSY`
- `NOT_AVAILABLE`
- `DUPLICATE_COMMAND`
- `UNAUTHORIZED`
- `RATE_LIMITED`
- `CONNECTION_LIMIT`
- `UI_NOT_BUILT`
- `NOT_FOUND`
- `BRIDGE_RESTARTED`
- `INTERNAL`

Tuple values such as RGBA and point2D are atomic. The browser never sends their channels as unrelated writes.

These are the exact public v1 codes. Specific operations may constrain which subset they emit, but neither implementation invents an additional wire code without first amending the canonical generated contract and parity fixtures.

### F.10 Server message families

- `state.snapshot`
- `state.delta`
- `telemetry`
- `event`
- `ack`
- `error`

Acknowledgement state is explicit:

- `accepted`: nonterminal, validated and enqueued, no state revision yet
- `applied`: terminal, a fast command changed authoritative state and includes revision and frame
- `superseded`: terminal, a newer accepted command replaced this pending fast command
- `rejected`: terminal structured `error` before acceptance, no state change
- `error`: terminal structured failure after acceptance

Queued transactions receive `accepted`, then operation-specific lifecycle events. They do not receive a false `applied` acknowledgement before completion.

A successful completion event includes the resulting revision and applied or completed frame. A failed or superseded event does not increment state revision unless the operation made an intentional partial change that is itself represented in state.

The exact telemetry envelope is:

```json
{
  "type": "telemetry",
  "apiVersion": 1,
  "engineSessionId": "td-boot-uuid",
  "module": "audio.energy",
  "sequence": 301,
  "frame": 192204,
  "sample": {}
}
```

The generated contract supplies a closed sample schema for every module. Unknown envelope keys, unknown modules, and unknown sample keys fail validation. Telemetry sequence gaps are counted as droppable samples and never trigger authoritative-state resynchronization.

An applied `telemetry.reissue` acknowledgement contains the bounded operation-specific result `{telemetryUrl}`. The URL carries the fresh token; no log or separate browser store exposes that token.

Every transaction event includes both the originating `commandId` and server-generated `operationId`:

```json
{
  "type": "event",
  "event": "shader.load.started",
  "commandId": "command-uuid",
  "operationId": "operation-uuid",
  "frame": 192204
}
```

Required events:

- `shader.load.started`
- `shader.load.succeeded`
- `shader.load.failed`
- `shader.load.superseded`
- `shader.schema.changed`
- `scene.recall.started`
- `scene.recall.completed`
- `scene.recall.failed`
- `clock.source.changed`
- `clock.transport.changed`
- `source.fallback.engaged`
- `source.selfRoute.rejected`
- `audio.device.lost`
- `audio.device.restored`
- `output.display.lost`
- `output.display.restored`
- `record.started`
- `record.stopped`
- `record.frameDropped`
- `library.reindex.started`
- `library.reindex.progress`
- `library.reindex.completed`
- `library.reindex.cancelled`
- `performance.warning`
- `blackout.changed`
- `controller.claimed`
- `controller.released`

A shader-load acknowledgement means accepted. It does not mean active. Only `shader.load.succeeded`, `shader.load.failed`, or `shader.load.superseded` closes the operation.

### F.11 Shader generation

The authoritative shader changes only after the inactive render chain passes build, compile, and warm-up and is committed.

Every committed shader receives a monotonically increasing `shaderGeneration`. All input commands include that generation. A command from a stale inspector is rejected before it can mutate a newly generated parameter page.

### F.12 Base and modulated values

```json
{
  "baseValue": 0.4,
  "modulationValue": 0.18,
  "effectiveValue": 0.58,
  "min": 0,
  "max": 1
}
```

The browser writes only `baseValue`. TouchDesigner owns modulation and clamping.

### F.13 Update rates and subscriptions

| Data | Maximum rate | Behavior |
|---|---:|---|
| Active pointer or touch gesture | 60 Hz | One coalesced latest value per target and animation frame |
| Command acceptance | Immediate | Never held for telemetry |
| Fast command applied ack | By application | Includes authoritative revision and frame |
| Transaction completion | Operation-specific | Lifecycle event, not the acceptance ack |
| Canonical state | Event-driven | Revisioned deltas |
| Audio energy meters | 30 Hz | Latest sample wins |
| Kick | Immediate event | Not network-smoothed |
| BPM | 10 Hz | Global value |
| Beat phase | Up to 30 Hz | Only while visible |
| Selected modulation trace | 15 to 30 Hz | Only visible or armed targets |
| System performance | 2 to 4 Hz | FPS, frame time, warnings, memory |
| Library | Connect or reindex | Cached by revision |
| Thumbnails | On demand | Cached and render-aware |
| Preview | 5 to 15 fps in v1 | Separate latest-frame lane |

No high-rate telemetry loop runs with zero connected and subscribed clients.

The base v1 sample schemas are exact:

| Module | Sample |
|---|---|
| `audio.energy` | finite 0–1 `loudness`, `bass`, `mid`, `high`; exactly eight finite 0–1 `bands`; boolean `held` |
| `audio.kick` | finite 0–1 `strength`; non-negative safe-integer `eventCounter` |
| `clock.bpm` | finite 0–400 `bpm` |
| `clock.beatPhase` | finite 0 inclusive to 1 exclusive `beatPhase`; non-negative safe-integer `beatTotal` |
| `modulation.selected` | 0–16 strict trace records with `bindingId`, semantic `target`, and finite `baseValue`, `contribution`, `effectiveValue`, `clampMin`, `clampMax` |
| `system.performance` | finite 0–10,000 `fps`, `frameTimeMs`, `cpuCookMs`, `gpuFrameMs`; non-negative safe-integer `droppedFrames`, `controlQueueDepth` |
| `library.revision` | non-negative safe-integer `revision`, `shaderCount` |

Continuous modules are latest-value-only. `audio.kick` is an immediate event module and is retained in a bounded transient event ring by the browser. Future modules are unavailable until their exact schemas are added to the generated contract and parity fixtures.

### F.14 Browser gesture coalescing

The client:

1. Captures pointer movement.
2. Updates local visual state immediately.
3. Stores only the newest requested value per semantic target.
4. Flushes at most once per `requestAnimationFrame`.
5. Monitors `WebSocket.bufferedAmount`.
6. Stops producing intermediate updates when backpressure crosses a threshold.
7. Preserves discrete action order.
8. Reconciles against the canonical delta.

### F.15 Ownership

V1 supports:

- One write-owning controller
- Any number of read-only observers within configured limits
- Explicit ownership identity in the system spine
- No automatic takeover
- Server-side lease expiry on disconnect

Ownership flow:

1. A connected client begins as an observer.
2. It sends `session.claimControl` with client identity and session nonce.
3. The server grants the lease if no live owner exists and publishes `controller.claimed`.
4. The owner renews through `session.heartbeat`.
5. Explicit release or lease expiry publishes `controller.released`.
6. A reconnecting client may reclaim after the old lease expires if no other owner acquired it.
7. The client then sends `telemetry.subscribe` for the visible modules.

A second client does not silently gain write authority. A future explicit takeover flow belongs to v2.

### F.16 Momentary and hold controls

Pointer release cannot be assumed to arrive after a disconnect.

- Non-safety momentary controls use a short renewable server lease.
- The control auto-releases if renewal stops.
- Latching blackout is the primary remote safety action.
- A blackout hold is fail-closed. Lost connection does not restore the live output.
- Reconnection never clears blackout.
- `SafetyState` asserts blackout during project startup before `Output` can open. A TD restart therefore returns black and requires explicit local release.
- Blackout stays excluded from ordinary `SceneState`.
- Native keyboard, MIDI, and panel safety remain available.

### F.17 Disconnect and reconnect

On browser disconnect:

- TD continues rendering.
- Output remains open.
- Scene state is untouched.
- No parameter is zeroed.
- No scene is recalled.
- Blackout is unchanged.
- Non-safety leases expire.
- The lifeboat remains active.

Client retry uses capped exponential backoff from 250 ms to 5 seconds with jitter and a prominent disconnected state.

On reconnect:

1. Fetch a new bootstrap.
2. Compare `engineSessionId`.
3. Request a complete state snapshot.
4. Replace all client engine state.
5. Restore browser-local presentation preferences only.
6. Do not replay unacknowledged writes.
7. Reclaim control only through `session.claimControl`.
8. Reopen only visible telemetry through explicit subscription commands.

Transactional commands use stable IDs so duplicate delivery is acknowledged without executing twice.

### F.18 Local security

- Bind production only to `127.0.0.1`.
- Validate WebSocket `Origin` if the current TD callback exposes it. Always require the session nonce in the WebSocket URI or first application message because the documented `onWebSocketOpen` callback exposes client and URI, not the complete handshake headers.
- Require a short-lived session nonce from bootstrap.
- Apply maximum message, connection, queue, and rate limits.
- Validate every JSON field and numeric range.
- Whitelist semantic commands and targets.
- Resolve shader IDs against the indexed library.
- Reject arbitrary OP paths, file paths, Python, expressions, and shell content.
- Keep Envoy and port `9870` separate.
- Never proxy or expose the Envoy MCP endpoint.
- Do not log full sensitive paths in routine UI messages.

Remote LAN mode requires a later explicit design with TLS, authentication, selected interface, controller ownership, and measured latency. The server never binds to `0.0.0.0` by default.

### F.19 Native lifeboat

The browser-independent panel includes:

- Latching blackout
- Blackout hold
- Master level when present
- Four deck opacity controls
- A/B crossfader
- Recorder state and direct Stop when recorder capability exists
- Output open and close
- Preferred and actual display status
- Current shader names and load errors
- UI server and client connection state
- Current scene and active-bank recall
- UI server restart

The lifeboat may share pure validation helpers, but its minimum safety path directly addresses `Mixer`, `SafetyState`, and `Output`. Blackout, recorder Stop, and output recovery cannot depend on the WebSocket, command queue, browser, or `InstrumentApiExt`. The lifeboat still reads authoritative TD state so its labels match the browser when both are healthy.

### F.20 Library contract

The current index is enriched with:

- Stable shader ID
- File hash or modification signature
- Full name
- File
- Generator, filter, or transition type
- Categories
- Description
- Input count and descriptors
- Pass count and persistence
- Parse status
- Compatibility status
- Library revision
- Thumbnail revision
- Last successful load state

The HTTP library response is cached by `libraryRevision`.

`GET /api/v1/library` returns a generated strict envelope containing `apiVersion`, `engineSessionId`, `libraryRevision`, `generatedFrame`, and at most 4,096 strict shader records, with a 4 MiB body limit. Each record freezes stable ID, signature, full name, basename-only file name, shader type, bounded categories and description, strict input descriptors, pass and persistence counts, parse and compatibility status, thumbnail revision, and nullable last-successful-load state. The response uses `ETag: "library-<libraryRevision>"`; an exact `If-None-Match` returns 304. The browser accepts a 200 body only when its session and revision match current authoritative `system.libraryRevision`.

`GET /api/v1/thumbnail/{shaderId}?revision=<thumbnailRevision>` accepts only a generated shader ID and advertised non-negative revision. A successful response is an at-most-512-KiB `image/jpeg` with matching revision header, immutable revision-keyed caching, and an exact ETag. Wrong MIME, stale revision, invalid JPEG, oversize content, malformed ID, or path escape fails closed and never becomes an image source.

Reindex policy:

- Never call the current synchronous full `Reindex()` from a WebSocket callback.
- Prefer incremental file-signature updates after the initial index.
- Full reindex is a `SYSTEM` maintenance transaction, not an unannounced `PERFORM` action.
- Enumerate and parse in bounded batches across frames with a measured per-frame budget, or perform file-only reading and pure parsing in a worker and hand results to the TD main thread.
- Worker code never calls TD APIs.
- Publish progress, cancellation, and completion events.
- Pause or cancel thumbnail work during reindex.
- Yield immediately when render health crosses the warning threshold.
- Commit a new `libraryRevision` atomically after the table is ready.

### F.21 Svelte source responsibilities

```text
src/
├── lib/
│   ├── api/
│   │   ├── protocol.ts
│   │   ├── socket.ts
│   │   ├── commands.ts
│   │   └── schemas.ts
│   ├── stores/
│   │   ├── instrument.svelte.ts
│   │   ├── connection.svelte.ts
│   │   ├── telemetry.svelte.ts
│   │   └── ui.svelte.ts
│   ├── controls/
│   ├── panels/
│   └── visual-system/
├── views/
│   ├── Perform.svelte
│   ├── Patch.svelte
│   └── System.svelte
└── App.svelte
```

The socket layer is the only code permitted to interpret wire messages. Components call typed semantic actions and read derived state. One canonical protocol source generates or validates Python and TypeScript models.

## Appendix G. Performance, verification, and phased delivery

### G.1 Latency definition

Literal zero latency is impossible. At 60 fps, one rendered frame is about 16.67 ms. The product target is zero-feeling local response with bounded canonical correction.

Acceptance budgets:

| Measurement | Budget |
|---|---:|
| Local control paint | Within one browser animation frame |
| Any valid command accepted p95 | At most 33 ms |
| Fast scalar application p50 | Within one TD frame |
| Fast scalar application p95 | At most 25 ms |
| Fast scalar applied ack p95 | At most 33 ms |
| Transaction accepted p95 | At most 33 ms |
| Transaction completion | Operation-specific lifecycle budget |
| Pointer to rendered output p95 | At most 50 ms or three 60 Hz frames |
| ControlBridge average frame cost | Less than 1 ms |
| ControlBridge p95 frame cost | Less than 2 ms |
| Stretch target for ControlBridge p95 | 0.5 ms |
| Preview local latency p95 | Less than 100 ms when enabled |
| Continuous gesture queue | Bounded, latest value per target |

Latency reports separate acceptance, fast application, transaction completion, and rendered visual consequence. A shader build, scene recall, recorder start, or reindex is never judged against the fast scalar completion budget.

### G.2 Render protection

- No full-state serialization per frame.
- No library scan in receive callbacks.
- No shader translation in receive callbacks.
- No image encoding on the control lane.
- No hidden high-rate telemetry.
- No unbounded logs or queues.
- No telemetry cook with zero clients.
- Preview and thumbnails yield before core control.
- Every performance measurement records preview enabled and disabled.
- The Three.js atmosphere consumes existing bounded store data and never creates a transport or telemetry subscription.
- The atmosphere uses one shared WebGL context, is pointer-transparent, and communicates no exclusive meaning.
- Its animation loop stops while hidden and becomes static under reduced motion.
- Adaptive quality lowers device pixel ratio and visual complexity, then disables the atmosphere before any established TD render, GPU-headroom, control-latency, or browser-frame budget is lost.
- Performance reports compare the cockpit with the atmosphere disabled, static, reduced, and full quality.

### G.3 Existing integration map

| Existing component | Adapter behavior |
|---|---|
| `slot1` through `slot4` | Opacity, blend, shader, load state, generated inputs, source, output health |
| `IsfPlayer` | Committed manifest, parameter records, base values, loading and lifecycle |
| `Mixer` | Four contributions, current fixed slot1 A and slot2 B crossfade behavior, strobe, one master FX slot, blackout |
| `SourceRouter` | Semantic source list, actual route, self-route rejection, fallback |
| `AudioEngine` | Configuration, stable bus, telemetry, dropout lifecycle |
| `Bindings` when present | Stable rows and implemented LFO fields without generated OP identity exposure |
| `Output` | Preferred and actual output, Window COMP, and Syphon |
| `SceneState` | Current save and recall slots, restore, migration, and exclusions |
| `Ui` | Library and deck-selection behavior reference only; its render-recursion defect is fixed, but the panel tree is quiesced and explicitly throwaway |
| New `UiLifeboat` | Separate minimal native safety surface; does not reuse the existing `Ui` panel tree |
| New `SessionIdentity` | Process and project-session identity outside bridge extension lifecycle |
| New `SafetyState` | Fail-closed boot blackout and direct safety authority outside ordinary scenes |

Additive components and parameters are listed in Appendix J. They are not described as existing until their capabilities are true.

### G.4 Phase 1: Contract and fixtures

- Freeze v1 envelopes, state paths, commands, errors, and event names.
- Create representative snapshot, delta, event, ack, and error fixtures.
- Validate Python and TypeScript against the same fixtures.
- Define latency timestamps and frame fields.
- Define capability negotiation and ownership.
- Define exact queue and message limits.

Exit:

- Protocol review complete.
- No arbitrary TD path reaches the public schema.
- Cross-language fixture tests pass.

### G.5 Phase 2: ControlBridge and lifeboat

- Add TDN-externalized `ControlBridge`.
- Add semantic adapters and revisions.
- Add command validation, deduplication, and ownership.
- Add HTTP and both WebSocket lanes.
- Add `SessionIdentity`, direct `SafetyState`, and native lifeboat before browser dependency.
- Prove blackout and output operation with both servers, the command queue, and `InstrumentApiExt` independently disabled.

Exit:

- Local protocol smoke passes.
- Lifeboat controls authoritative state.
- TD project startup asserts blackout before output opens.
- ControlBridge extension reinitialization does not change `engineSessionId`.
- Zero-client cook profile meets the budget.

### G.5.1 Phase 2B: Engine surface completion

- Implement Appendix J addenda in independently testable slices.
- Advertise a capability only after its live engine behavior passes.
- Keep current staged behavior unchanged until the corresponding addendum is ready.
- Allow the cockpit to run against the existing adapter slice throughout.

Required VDMX-parity slices:

- Dynamic four-deck A/B routing and master level
- Ordered deck and master FX racks with immutable instance IDs
- Dedicated Clock authority
- Advanced audio split and trigger controls
- Recorder, still capture, quantize, and direct Stop
- Scene administration
- Advanced LFO and MIDI
- ISF audio and audioFFT textures

Exit:

- Appendix J capability matrix matches live bootstrap.
- Unsupported controls remain absent.
- Each new signal-stage ordering is verified in TD before the corresponding UI surface ships.

### G.6 Phase 3: Static cockpit shell

- Establish Svelte 5, TypeScript, and Vite.
- Implement local fonts, tokens, modes, stable regions, and responsive constraints.
- Serve the production bundle through TouchDesigner.
- Implement bootstrap, connection, ownership, snapshot, and global fault states.
- Do a static art-direction review before broad component wiring.

Exit:

- Production build runs without Node.
- `PERFORM`, `PATCH`, and `SYSTEM` retain stable global geography.
- Text and target-size audit passes.
- Automated text and non-text token contrast checks pass.
- Keyboard, 200 percent zoom, reduced-motion, and focus-restoration checks pass.

### G.7 Phase 4: Core performance controls

- Wire deck opacity and blend.
- Wire the truthful current A/B model and crossfader, then enable arbitrary assignment only with `dynamicAB`.
- Wire strobe, source route, and blackout, then master level only with `masterLevel`.
- Add gesture coalescing and canonical reconciliation.
- Add bidirectional state so native or MIDI changes appear in browser.

Exit:

- Sustained crossfader test passes.
- No scroll stealing.
- Blackout works through browser and lifeboat.

### G.8 Phase 5: Library and inspector

- Add cached library endpoint.
- Add search, categories, favorites, recents, and status.
- Add explicit load-to-deck.
- Add load lifecycle and supersession.
- Add generated control descriptors.
- Add shader generation guards.
- Add source input and FX inspection based on capabilities.

Exit:

- Failed shader leaves valid output live.
- Stale control cannot affect a new shader.
- Every supported input fixture renders a control.

### G.9 Phase 6: Audio, timing, and modulation

- Add audio telemetry subscriptions.
- Add parameter-first binding creation.
- Add transactional binding editing.
- Add the implemented LFO fields, then reveal advanced LFO and MIDI fields by capability.
- Add read-only audio timing now and the complete Clock editor only after Clock authority exists.
- Add advanced audio split and trigger controls only after their addendum exists.
- Show base, modulation, and effective values.
- Begin only when the current Bindings contract is stable.

Exit:

- Real audio device smoke passes.
- When MIDI exists, MIDI activity, dormant mapping, and shader re-resolution pass.
- Clock source, presets, transport, counters, and reset pass when advertised.
- Hidden modulation traces do not cook or publish.

### G.10 Phase 7: Output, scenes, and recorder

- Add preferred and actual display state.
- Add Window COMP and Syphon actions.
- Add current scene save and recall, then protected overwrite, dirty state, rename, duplicate, and detailed progress only when advertised.
- Add recorder only when the engine advertises it.
- Add still capture and quantized record flow.

Exit:

- External display unplug and restoration smoke passes.
- Scene recall leaves blackout untouched.
- Recorder failure leaves program output live.

### G.11 Phase 8: Preview and hardening

- Add low-resolution preview lane.
- Add thumbnail cache and render-health backoff.
- Harden reconnect and ownership.
- Add security and malformed-input tests.
- Run latency, slow-client, disconnect, and soak gates.

Exit:

- Preview cannot block control.
- All p95 budgets pass.
- Full-stack 30-minute soak passes.
- On-device rehearsal review passes.

### G.12 Phase 9: Living visual environment

(Cross-reference: this rollout stage is the plan's "Phase 6: Living visual system", Tasks 20–22, and the manifest's phase "7 of 7". Same scope.)

This phase is required product scope, not an optional polish backlog.

1. Build the isolated Three.js renderer, typed signal adapter, adaptive quality controller, reduced-motion state, teardown behavior, and atmosphere-off fallback.
2. Implement and review the bounded v1 behavior matrix: one signal field, one particle population, and one routing-filament layer driven by the approved authoritative sources.
3. Benchmark the Conner-approved production visual system at `off`, `static`, `low`, and `full`, then ship the highest quality that preserves every existing TouchDesigner, control-latency, browser-frame, and accessibility budget.

Exit:

- The renderer boundary proves no transport, command, layout, focus, or safety ownership.
- The complete cockpit remains usable and semantically intact with atmosphere `off`.
- Mechanic and Client Success approve the production UI behavior.
- Conner approves the production art direction against the inspiration collection.
- The final benchmark and 30-minute visual soak pass at `low` animated quality or better.
- The complete cockpit, including its animated visual environment, is marked `PERFORMANCE READY`.

### G.13 Protocol tests

- Valid commands decode identically in Python and TypeScript.
- Unknown fields follow the frozen strictness policy.
- Invalid types, targets, values, and IDs are rejected.
- Duplicate transaction IDs execute once.
- Accepted and applied acknowledgements are never conflated.
- Every accepted ID reaches exactly one terminal outcome, including coalesced fast commands.
- Every transaction lifecycle event carries matching `commandId` and `operationId`.
- Continuous scalar writes do not fail due to unrelated global revision changes.
- Stale transactional revisions and shader generations are rejected.
- Authorized blackout bypasses ordinary stale-revision rejection.
- Tuple controls apply atomically.
- Capability, availability, and health changes produce the correct distinct surface state.
- Reordering FX preserves immutable instance targets and inspector identity.
- Claim, release, heartbeat, subscribe, and unsubscribe messages validate correctly.
- Observer clients cannot write.
- ControlBridge extension reinitialization preserves `engineSessionId`.

### G.14 Live integration tests

- Browser slider changes the intended TD value.
- Fast command first reports accepted, then applied with actual revision and frame.
- Transactions report accepted, then close through operation lifecycle events.
- TD-native and MIDI changes update the browser.
- Shader swap emits complete lifecycle and schema events.
- Old-shader input cannot mutate the new shader.
- Self-routing rejects without a cook cycle.
- Scene recall preserves blackout.
- Browser disconnect leaves output unchanged.
- Browser restart restores through a snapshot.
- TD restart changes engine session.
- Display and audio loss emit structured events.
- TD startup is black before Output opens.
- Native lifeboat remains usable with both web servers, queue, and `InstrumentApiExt` independently faulted.
- Full library reindex yields to rendering, reports progress, and commits one new revision.

### G.15 Performance tests

- Run a continuous 60 Hz crossfader gesture for 10 minutes.
- Run four live decks, mixer, and the currently supported FX topology at 1920 x 1080.
- Run audio telemetry plus at least 10 active bindings when bindings exist.
- Simulate a slow control client.
- Simulate a slow telemetry client.
- Record command, ack, delta, applied frame, and rendered response timing.
- Measure `ControlBridge` with zero clients, one controller, and observers.
- Measure previews enabled and disabled.
- Confirm no ControlBridge-attributable frame drops.
- Run a full reindex and thumbnail-backoff profile separately.
- Run the existing 30-minute soak.

### G.16 Safety tests

- Browser unavailable at startup
- Fail-closed boot blackout before output open
- Control Web Server DAT stopped mid-performance
- Telemetry Web Server DAT stopped mid-performance
- `InstrumentApiExt` fault while using native blackout and output recovery
- Command queue fault while using native blackout and recorder Stop
- Malformed and oversized messages
- Lost pointer release
- Lost connection during blackout hold
- Duplicate scene recall
- Failed shader compile
- Missing camera or route source
- Audio loss and restoration
- External display loss and restoration
- Recorder failure
- Preview encoder stall
- Native lifeboat blackout under every web failure

### G.17 Manual visual and UX review

Before a performance-ready claim:

- Capture `PERFORM`, `PATCH`, and `SYSTEM` at 1920 x 1080.
- Capture `PERFORM` at 1440 x 900 and 1280 x 800.
- Capture blackout off, blackout on, and blackout hold.
- Capture recorder ready, armed, recording, and fault when recorder exists.
- Capture connected, disconnected, and read-only observer.
- Capture shader loading, failed, superseded, fallback, and stale preview.
- Capture a selected A deck and selected B deck with enabled, bypassed, disabled, and modulated controls.
- Capture keyboard focus and drawer focus restoration.
- Capture reduced motion.
- Review grayscale and common color-vision simulations.
- Confirm the media remains the dominant color source.
- Confirm only real telemetry is visible.
- Confirm no text below 14 px.
- Confirm every show-critical target is at least 44 x 44 px.
- Confirm 4.5:1 text and 3:1 functional non-text contrast checks.
- Confirm Blackout, Stop, master, output health, and connection are never covered.
- Confirm keyboard focus is visible.
- Confirm reduced motion preserves all meaning.
- Confirm operation at 200 percent zoom.
- Complete the worked example on a real control display.
- Run one rehearsal with browser disconnect and lifeboat recovery.

The capture set becomes the initial visual-regression baseline suite.

## Appendix H. Exhaustive 46-file visual reference audit

### H.1 Coverage

The source folder contains 45 JPG files and one PNG file, for 46 reviewed files total.

These two JPG files are byte-identical:

- `e40df5dbdbe6640464725fd3ef9596d7-1.jpg`
- `e40df5dbdbe6640464725fd3ef9596d7.jpg`

Both have SHA256 `72323caa9289d3fe62d0b3f7dbb838858184a1351e87e13982d33c5c8a584c30`.

The collection therefore contains 44 unique JPG bitstreams and one unique VDMX PNG, for 45 unique visual references represented by 46 files.

### H.2 Per-file review

#### 1. `0331dc7eb4c2e939e911ae9ed2ce46a6.jpg`

A massive monochrome component and timeline atlas containing rails, segmented bars, nodes, gauges, diagrams, and waveform structures. It is a strong reference for building a coherent primitive language from a limited set of strokes and fills. Borrow its modular consistency and measured geometry, not its extremely small labels or wall-to-wall density.

#### 2. `0480c983a1a013676438f3ce918a7237.jpg`

A sparse schematic composition labeled `XN-705`, anchored by a huge `03`, fine grid lines, and Japanese microtype. It shows how a large identifier and rationed detail can make a nearly empty field feel technical and intentional. Use this principle for deck numbers, modes, scenes, and output state.

#### 3. `067e82fe07f95087114deef373760f60.jpg`

A PIRON laboratory interface with network nodes, a dominant circular control, biological or system vitals, and small orange and green state accents. It balances central authority, peripheral telemetry, and restrained color. Borrow its sense of a monitored living system without decorative scientific labels.

#### 4. `0d5399bd03c41e3ddb35d8d55aabcaef.jpg`

An oblique analytics graph with bright points, linked trajectories, white linework, and sparse red accents. It contributes the idea of active signal relationships and selected events. Perspective may appear in noninteractive diagnostics, but operator controls stay flat and stable.

#### 5. `0e6f04c724f2b2c0ea03434e1f06d242.jpg`

A Cognex `VOID` interface built from node graphs, data blocks, isolated modules, and large black fields. Its strongest lesson is negative space separating functional clusters and making connectivity visible. Borrow the topology and hierarchy, not ambiguous unlabeled nodes.

#### 6. `111b5faf58f6b452cf62e43b29565523.jpg`

A spacecraft electrical schematic using cyan, orange, and red status colors, with physical controls along the edges. It is a major reference for output routing, health, failover, and safety. Every colored path appears to represent actual system status, which is the behavior to preserve.

#### 7. `200d1ca6c6adbf4f3ae937eea573466c.jpg`

A vertical `ANOMALY 489` poster with pixel typography, sparse squares, and high black-and-white contrast. It offers an identity language for fault codes, scene numbers, and rare full-height states. Its drama is reserved for important conditions.

#### 8. `2303d098b6d67023eaa2571fe1e4ff62.jpg`

An oblique node and cable interface with red points marking selected connections or changes. It reinforces visible routing and direct relationships. Use connection lines only when the route is real and operator-relevant.

#### 9. `2d3e5915902a5b768c3a4688d154e4e0.jpg`

A very dark arrangement of nested console windows with subtle gray separation. It demonstrates depth without obvious shadows or bright frames. It also warns against insufficient contrast, so the cockpit keeps the quiet layering while raising text and boundary legibility.

#### 10. `2df6b8eb26be595e4ff760ec88ddadbe.jpg`

A dense vertical system using violet and orange, stacked data cards, a gridded plot, targeting circles, and compact measurements. It is useful for `PATCH` and `SYSTEM` density. Its full-screen intensity is too high for default `PERFORM`.

#### 11. `31559fe6c2bd664d42418dd10a67eb45.jpg`

A tall `INSPECTED` trajectory and targeting map with a bold headline, fine tracks, minute labels, and a large empty field. It demonstrates macro-to-micro hierarchy. Borrow the orientation label and measured paths while keeping live text readable.

#### 12. `33c62748fc406bb21debde45c4c1b069.jpg`

A symmetrical navigation HUD centered on a circular instrument with narrow controls at both sides. It suggests a focused master-control composition and bilateral balance. Symmetry can support the master output or crossfader but must not force artificial mirroring.

#### 13. `3e5446f3e655cb3110b23514fd25e60f.jpg`

A modular `ARRAY DATA` system of media cards, placeholders, status marks, and repeated frames. It is a direct reference for shaders, deck assets, scenes, and loading. Borrow its repeatable anatomy and selected state while enlarging labels and targets.

#### 14. `4240863c4b98a9b80c5fe38bf2416777.jpg`

A monochrome sheet of primitives, symbols, markers, brackets, and component fragments. It is useful for icons and state markers. Select a small coherent subset rather than reproducing the decorative field.

#### 15. `46fc58e9dc64c71529f7fd29ee06b732.jpg`

A tracker or pattern-editor terminal with tabular channels, waveform bars, and dense numeric data. It supports tabular numerals, fixed-width telemetry, timing grids, and sequencing aesthetics. Its extreme density belongs only in specialized timing and diagnostic views.

#### 16. `630bb30b3a9e212c4ef4d3fc05689ed2.jpg`

A dark music or media interface close-up with knobs, a numbered grid, and compact performance controls. It contributes physical-console familiarity and repeated channel structure. Rotary controls should be selective, touch-sized, and paired with exact values.

#### 17. `642224c316309e4cbe336b32f81b6af3.jpg`

A cyan-and-orange VPN or log console with technical events, compact records, and clear accent states. It is a model for connection logs, bridge health, and diagnostic feedback. Translate technical faults into operator language.

#### 18. `66dc738f10d8713e59805c0c34df84b4.jpg`

A monochrome field of numeric trajectories, particles, and linked points. It suggests a living-systems layer for modulation, audio, or signal activity. Similar motion must derive from real data and remain secondary.

#### 19. `6da011bc5fd43c466615008605069b41.jpg`

A compact cyan-and-orange control surface organized around explicit A/B modes and horizontal sliders. It is directly relevant to crossfade, side assignment, mix balance, and dual-state controls. Its disciplined two-accent system informs the A/B grammar.

#### 20. `6ef18c19d848f62c379a06d4ba03bee8-1.jpg`

A `Human / Urban Systems` composition built from large outlined modules on a precise grid. It shows how naming, frames, and sparse data create an architectural systems map. Borrow its scale and boundaries while using actual engine labels.

#### 21. `6f095231b65c4bd99e1c565611364f7f.jpg`

A vertical physical science-fiction console with cyan and coral waveforms, knobs, meters, and hardware-like controls. It is a major tactile reference. Use its material authority, color restraint, and grouped instruments without unnecessary physical bevel simulation.

#### 22. `7e0060d3146df04089b04e922797d435.jpg`

A cyan-and-orange console close-up with technical readouts, controls, and illuminated states. It reinforces cool machine signal against warm operator action. Every illuminated element in the cockpit must carry meaning.

#### 23. `801840c53e3de837270d9622bda71478.jpg`

A Japanese typographic and editorial system with vertical side labels, dense hierarchy, fine dividers, and careful alignment. It is a strong reference for panel labeling and mixed-scale type. Borrow the editorial discipline, not tiny copy or decorative foreign-language text.

#### 24. `85f7cc5307ba293baae3b5fcaea4ebb3.jpg`

A black analytics dashboard with large metrics, line graphs, and supporting values. It demonstrates glanceable telemetry. Apply the principle to BPM, render FPS, output state, recorder duration, and other critical metrics.

#### 25. `897d6c64ceaef041ade899ed69bf9cc1.jpg`

A branching data-flow graph with cyan and magenta active paths. It is a reference for bindings, modulation sources, and route inspection. Simplify simultaneous branches and reserve violet for true modulation.

#### 26. `8b3f19f73e7f55d6876050777de1b548.jpg`

A modular mission-control screen containing buttons, gauges, charts, and status regions. It shows many instrument types sharing one visual grammar. Borrow its module hierarchy while protecting output and safety priority.

#### 27. `970b059400f0854bcc8c55176207e8ec.jpg`

An infinite screenshot recursion in which the interface repeatedly contains itself. It evokes introspection and feedback loops. This is conceptually useful for a cybernetic instrument, but literal recursion belongs only in an intentional shader effect.

#### 28. `9e73d35a1fddcfcac26336e995ff9b4c.jpg`

A minimal thermal-style HUD with a central reticle, angular frame, and tiny peripheral data. It demonstrates a single focal point and restrained framing. Borrow the focus for the program output while avoiding targeting fiction and tiny labels.

#### 29. `a23f867739f1c6b696a257473fe402f5.jpg`

An expanded component, icon, and glyph sheet with many technical primitives. It supplements the other vocabulary references. Use only symbols with clear operational meanings.

#### 30. `a7557d413843ba6986e72d05cfc0ff20.jpg`

A cyan-and-coral physical console featuring block graphs, large dials, scales, and bright states. It is relevant to audio, LFO, clock, and master macros. Borrow physical scale and measured feedback while keeping controls planar.

#### 31. `ace77a5bf1f185c8733c6fd1800c279a.jpg`

A close-up console built around phase presets, cyan and orange states, compact numbers, and hardware grouping. It supports the scene and preset language. The cockpit adds explicit pending, loaded, dirty, and saved distinctions.

#### 32. `aed55f94e762ce4e987ad0a7643e9699.jpg`

A tall multi-section UI atlas containing windows, grids, modules, typography, and a large glyph bank. It is useful for dimensions, headers, repeated panels, and state markers. Treat it as a kit, not a screen to copy.

#### 33. `b122af7b6edc4eb79000e26e64abc423.jpg`

A node and control matrix centered on `Density Amount`, with cables, values, controls, and subtle honeycomb texture. It directly informs contextual parameter editing and modulation. Keep wiring hidden until useful.

#### 34. `baab3feee6b048c1d9037330b83fbb57.jpg`

A synthesis console dominated by `A25X`, with cyan and coral controls. It shows an oversized device identity paired with dense local operation. This informs deck identifiers and selected-object headers.

#### 35. `cb83353a2491d58608c493f88d1055e6.jpg`

A PIRON code or cryptographic interface made from scattered modules, data fields, and restrained orange and green status. It contributes a laboratory-software mood and calm black field. Avoid scattered placement without an operational route.

#### 36. `e40df5dbdbe6640464725fd3ef9596d7-1.jpg`

A blurred monochrome ambient field suggesting translucent fragments and soft glass-like depth. It may inform rare background atmosphere or transitions but cannot determine control contrast. It is byte-identical to the next file.

#### 37. `e40df5dbdbe6640464725fd3ef9596d7.jpg`

The exact duplicate of the previous JPG. It contributes no additional direction beyond the same blurred monochrome atmosphere. Both filenames remain in the audit for completeness.

#### 38. `e54f9c4c4dc273eebb4be6caa20f9375.jpg`

A huge monochrome HUD kit containing radial instruments, waveforms, networks, gauges, bars, maps, and modular frames. It is a rich source for component anatomy and line-weight consistency. Extract a small real-data set rather than inherit its cinematic microdensity.

#### 39. `e7183ebe44faa67d56912cc24564205f.jpg`

An extremely sparse horizontal circuit trace crossing a large black field. It shows how one real route can become a compositional element. This informs source-to-deck, modulation, and output-path inspection.

#### 40. `e8123f842e702ff946e974479b8bceec.jpg`

A stack of black radar, topographic, or cartographic screens with circular scans and layered terrain-like data. It suggests rich diagnostic surfaces for audio, modulation, or render telemetry. Use actual values, not decorative maps.

#### 41. `ea62d45db18923756de824a03c547de7.jpg`

An abstract diagnostic close-up featuring an `E6` selection, status icons, pale blocks, and one coral accent. It is a strong example of one warm selection color against neutral machinery. Use this restraint for selected deck, FX, or parameter focus.

#### 42. `edaf8a75c6eefc35f70808c0d58e9fe2.jpg`

A colorful futuristic mixing desk with fader banks and cyan, yellow, and pink channel states. It is the clearest reference for repeated channel rhythm and tactile scale. Borrow the physical structure while reducing simultaneous color.

#### 43. `f51ce5a64804cec47b29d4fdda32f811.jpg`

A sparse terminal or code readout centered on an almost empty black canvas. It demonstrates disciplined focus and quiet space. It can inform loading and diagnostics when messages are written in plain operational language.

#### 44. `fbbc4144ff633e1d40eaed354dac5309.jpg`

A matrix of illuminated square buttons. It is relevant to scenes, presets, media triggers, and quantized actions. Preserve physical states, larger labels, and clear distinctions among available, selected, armed, and triggered.

#### 45. `fc724729757aabf3afd6c702a71b245b.jpg`

A very dark vertical selectable-card list with a numbered side rail and subtle active states. It is useful for shaders, FX stacks, scenes, and routing lists. Raise contrast and target size while preserving the numbered rhythm.

#### 46. `VDMX6-current-layout.png`

The operator's previous VDMX6 workspace and the functional baseline. It shows two ISF sources, a generated shader interface, Layer A and Layer B previews, opacity and blend, per-layer FX, a large master FX chain, main output, master fader, audio analysis, recording, clock and BPM, LFO, MIDI, media browsing, asset workflows, and panic or reset behavior. Its value is the capability inventory and learned relationships. The cockpit remixes those relationships into stable `PERFORM`, `PATCH`, and `SYSTEM` views.

## Appendix I. Research decision record and implementation traceability

### I.1 Primary findings

#### TouchDesigner Web Server DAT

The Web Server DAT is the correct local host because it supports HTTP and WebSocket communication inside TouchDesigner. It removes a production middleware process and keeps the UI lifecycle with the instrument. Its documented `Local Address` parameter supports an explicit `127.0.0.1` listener; leaving it blank would listen on all interfaces and is prohibited for local production. The documented WebSocket-open callback exposes client and URI, which is why the protocol always requires an application nonce rather than depending on Origin headers.

Sources:

- [Web Server DAT](https://derivative.ca/UserGuide/Web_Server_DAT)
- [WebserverDAT Class](https://derivative.ca/UserGuide/WebserverDAT_Class)

#### TouchDesigner Python callbacks

Web callbacks must stay small. Heavy work is queued and executed through controlled TD work rather than long callbacks or unsafe render-path threading.

Source:

- [Python threading in TouchDesigner](https://docs.derivative.ca/Python_threading_in_TouchDesigner)

#### Native Panel and macOS touch

Native panels are retained for safety, but not the primary interface. The standard panel input model and lack of macOS support for Multi Touch In DAT make web Pointer Events the stronger general interaction surface.

Sources:

- [Multi Touch In DAT](https://derivative.ca/UserGuide/Multi_Touch_In_DAT)
- [Panel COMP Panel Page](https://derivative.ca/UserGuide/Panel_COMP_Panel_Page)
- [Pointer Events Level 3](https://www.w3.org/TR/pointerevents3/)

#### Web Render TOP

Web Render TOP is not selected because the primary browser can run directly on the control display. Rendering Chromium back into TD adds a process and frame-transfer relationship without improving control.

Source:

- [Web Render TOP](https://derivative.ca/UserGuide/Web_Render_TOP)

#### WebRTC

WebRTC is a potential media lane only. It is not part of command transport and is not required for v1. Its higher-resolution CPU cost and actual macOS behavior require a measured spike.

Sources:

- [TouchDesigner WebRTC Palette](https://derivative.ca/UserGuide/Palette%3AwebRTC)
- [TouchDesigner WebRTC](https://derivative.ca/UserGuide/WebRTC)

#### Svelte and Solid

Svelte's compiled component model is selected for the production surface. Solid's fine-grained reactivity validates the architectural preference for granular updates but does not outweigh Svelte's authoring fit.

Sources:

- [Svelte overview](https://svelte.dev/docs/svelte/overview)
- [Svelte reactive state](https://svelte.dev/docs/svelte/%24state)
- [Solid fine-grained reactivity](https://docs.solidjs.com/advanced-concepts/fine-grained-reactivity)

#### Vite

Vite provides the static production bundle. Relative asset paths and hashed files permit direct serving from TouchDesigner.

Source:

- [Vite production build](https://vite.dev/guide/build)

#### WebSocket and Pointer Events

The standards-based WebSocket and Pointer Events APIs provide the necessary low-level control without framework-specific transport.

Sources:

- [WebSockets Standard](https://websockets.spec.whatwg.org/)
- [Pointer Events Level 3](https://www.w3.org/TR/pointerevents3/)

#### Tauri

Tauri is deferred. It becomes relevant only if signed packaging, auto-launch, kiosk window behavior, or OS-level integration becomes a requirement.

Source:

- [Tauri architecture](https://v2.tauri.app/concept/architecture/)

### I.2 Local implementation anchors

| Anchor | Role in this spec |
|---|---|
| `docs/superpowers/specs/2026-07-23-td-native-pivot-isf-player-design.md` | Product and engine foundation |
| `project1/IsfPlayer/IsfPlayerExt.py` | Shader loading, committed manifest, hot-swap lifecycle |
| `project1/IsfPlayer/isf_index.py` | Current library index to enrich |
| `project1/IsfPlayer/isf_header.py` | Categories and descriptions already parsed |
| `project1/slot1.tdn` through `project1/slot4.tdn` | Deck state and output |
| `project1/Mixer.tdn` | Four-deck mix, strobe, master FX, final blackout |
| `project1/SourceRouter.tdn` | Self-route and never-black behavior |
| `project1/AudioEngine.tdn` | Curated audio bus and dropout behavior |
| `project1/Output/OutputExt.py` | Preferred and actual output actions |
| `project1/SceneState/SceneStateExt.py` | Scene persistence and exclusions |
| `project1/Ui.tdn` | Existing library and deck-selection semantics only; not a panel-tree base |
| `docs/superpowers/plans/2026-07-23-phase-c-audio-bindings.md` | Bindings and modulation contract |
| `/Users/arsonrivvers/Desktop/AV_Projects/TouchDesigner/ImmersiveHQ_Coursework/WK14-15/web_dashboard/vite.config.ts` | Local Vite and same-host TouchDesigner deployment cousin; port mechanics only |

### I.3 Critical invariants preserved

- Four concurrent deck architecture
- Hitchless shader hot-swap
- Current visual retained on shader failure
- Source self-route prevention
- Never-black source fallback
- Blackout after master FX and after the optional master-level addendum
- Blackout excluded from scenes
- TouchDesigner authority for output and hardware
- Name-stable binding targets
- Browser failure cannot stop render output
- Existing 60 fps at 1920 x 1080 and GPU-headroom requirements

### I.4 Envoy implementation posture

Envoy should use this document to build or edit TouchDesigner structures, but it must respect these boundaries:

- Author the `ControlBridge` as a semantic, renderer-neutral COMP.
- Keep all authored COMPs externalized through existing TDN conventions.
- Do not treat the Envoy MCP schema as the performer API.
- Do not wire browser commands directly to arbitrary OP paths.
- Preserve existing contracts, then add the narrowly scoped extensions in Appendix J behind capabilities.
- Add capabilities incrementally so the client hides unavailable surfaces.
- Prove the native lifeboat before relying on the web UI.
- Do not extend, clone, or reuse the existing `/project1/Ui` panel tree. Its recursion defect is fixed in `bc956b2`, but the approved cockpit and native lifeboat are fresh surfaces; listCOMP initialization callbacks must never mutate layout attributes that retrigger initialization.
- Build `UiLifeboat` as a separate minimal COMP with direct safety authority.
- Preserve the current staged branch work and avoid unrelated modifications.

## Appendix J. Required engine addenda for VDMX parity

### J.1 Purpose

This appendix resolves the boundary between the trusted staged instrument and the complete cockpit. It does not claim these addenda already exist. It tells Envoy and the implementation plan exactly which TouchDesigner extensions must be built before each parity control is shown.

Rules:

- Existing staged behavior stays valid throughout.
- Each addendum is independently externalized, tested, and capability-gated.
- A false capability produces no fake performance control.
- Availability and health remain visible for supported features.
- The cockpit can run against the base adapter slice before all addenda land.

### J.2 Capability and engine matrix

| Capability | Current truthful state | Required engine addendum | UI unlocked |
|---|---|---|---|
| `mixer.dynamicAB` | Slot 1 is A, slot 2 is B, slots 3 and 4 contribute manually | Add per-deck side enum `A`, `B`, or `THRU`; crossfader weights A and B while THRU remains independent | Four-deck side assignment |
| `mixer.masterLevel` | No dedicated master-level parameter | Add `level_master` after master FX and before blackout | Persistent master fader |
| `fx.deck.maxInstances` | No per-deck rack | Add ordered `FxRack` after each deck source or shader and before Mixer | Deck FX rack |
| `fx.master.maxInstances` | One `fx_master` slot | Replace or wrap with ordered `FxRack` using immutable instance IDs | Repeated master FX rack |
| `clock.manualBpm` | Audio BPM is read-only timing data | Add dedicated `Clock` COMP with manual and audio authority | Manual BPM and presets |
| `clock.transport` | No global run, pause, tap, or reset authority | Add run, pause, tap, reset, counters, and elapsed time | Clock editor and transport |
| `audio.bandSplit` | Curated bass, mid, and high bus only | Add low and high split parameters or equivalent analyzer controls | Crossover controls and graph |
| `audio.triggerShape` | Kick bus without full VDMX trigger shaping | Add threshold and hysteresis | Trigger editor |
| `audio.triggerInvert` | No explicit trigger inversion | Add boolean inversion or binding transform | Invert trigger control |
| `recorder.video` | No recorder action in current Output contract | Add Movie File Out authority, readiness, state, duration, errors | Recorder surface |
| `recorder.still` | No still-capture action | Add explicit still capture and saved-filename event | Image action |
| `recorder.quantize` | No quantized start | Read the dedicated Clock and wait for selected boundary | Armed and waiting states |
| `recorder.directStop` | No lifeboat Stop | Add direct native Stop outside ControlBridge queue | Lifeboat recorder Stop |
| `scenes.rename` | Current scene slots save and recall | Add stable scene ID plus display name | Rename |
| `scenes.duplicate` | No duplicate action | Add validated copy to a target slot or ID | Duplicate |
| `scenes.dirty` | No authoritative dirty signal | Compare current persistable state with recalled scene revision | Dirty badge |
| `scenes.protectedOverwrite` | Save action has no full administration contract | Add intentional overwrite validation and lifecycle | Protected overwrite |
| `lfo.phase` and advanced fields | Phase C contract provides shape, rate, amplitude | Extend LFO authority field by field | Advanced LFO controls |
| `midi.input` and `midi.learn` | Not in the current build | Add slot-scoped MIDI activity and learn authority | MIDI learn and matrix |
| `isfInputs.audio` | Active parser or player may report unsupported | Add audio texture generation and conformance | Audio texture routing |
| `isfInputs.audioFFT` | Active parser or player may report unsupported | Add FFT texture generation and conformance | FFT texture routing |
| `library.loadTiming` | Immediate request only | Add scheduled commit against Clock | Beat or scheduled load |
| `decks.independentCadence` | Project cadence is global | Intentionally deferred until a measured use case exists | Per-deck FPS control |

### J.3 Dynamic A/B behavior

Each deck has one side:

- `A`: multiplied by the A crossfader weight
- `B`: multiplied by the B crossfader weight
- `THRU`: contributes independently of the A/B macro

Defaults preserve existing behavior:

- Deck 1: `A`
- Deck 2: `B`
- Deck 3: `THRU`
- Deck 4: `THRU`

Changing assignment is transactional enough to preserve one coherent mixer revision, but its rendered result should apply by the next frame after acceptance.

### J.4 FX rack behavior

Each FX instance owns:

- Immutable `instanceId`
- Effect shader ID
- Order index
- Enabled
- Bypass
- Wet/Dry
- Blend when supported
- Parameter snapshot
- Load and error state

Rack capability advertises:

- `maxInstances`
- `reorder`
- `duplicate`
- `blend`
- `presets`

Capacity is measured, not assumed. The UI handles a long scrollable chain, but TD advertises the safe active-instance limit for the current build and performance target.

Signal order:

```text
DECK SOURCE OR SHADER
  -> DECK FX RACK WHEN PRESENT
  -> MIXER CONTRIBUTION
  -> A/B OR THRU WEIGHT
  -> COMPOSITE AND STROBE
  -> MASTER FX RACK OR CURRENT MASTER FX
  -> MASTER LEVEL WHEN PRESENT
  -> BLACKOUT
  -> OUTPUT
```

Blackout remains the final visual gate.

### J.5 Clock authority

The `Clock` COMP publishes:

- `source`: `audio`, `manual`, or a supported external clock
- `bpm`
- `auto`
- `running`
- `beat`
- `bar`
- `cycle`
- `subdivision`
- `phase`
- `elapsedSeconds`
- `quickPresets`

Semantic actions:

- `clock.setSource`
- `clock.setBpm`
- `clock.setAuto`
- `clock.tap`
- `clock.setRunning`
- `clock.reset`
- `clock.setQuickPreset`

AudioEngine may feed estimated BPM and phase, but Clock decides which source is authoritative. Quantized record and future scheduled shader commits read Clock rather than duplicating timing.

Clock source, BPM, and quick presets persist as global session state. Ordinary scene recall does not start, stop, or reset transport and does not silently change the active timing source.

### J.6 Advanced audio behavior

The advanced AudioEngine surface publishes:

- `bandSplitLowHz`
- `bandSplitHighHz`
- `kickThreshold`
- `kickHysteresis`
- `kickInvert`
- Current low, mid, high, kick, and band values

The UI draws only real response and envelope data. Inverting a continuous binding can also be achieved through signed depth, but trigger inversion remains an explicit boolean when the addendum exists.

### J.7 Recorder behavior

Recorder authority publishes:

- Supported video and audio source lists
- Destination and filename policy
- Ready and error state
- Quantize capability and selected boundary
- Armed, waiting, recording, stopping, and complete lifecycle
- Duration
- Dropped frames
- Last saved path or filename

`record.stop` has a direct native path. A browser, bridge, or queue fault cannot remove Stop once recording begins.

### J.8 Scene administration

The base scene bank retains current save and recall. Additional fields are advertised separately:

- Stable scene ID
- Display name
- Revision
- Dirty
- Autosave state
- Partial recall result
- Rename
- Duplicate
- Protected overwrite

Blackout, SafetyState, output geometry, controller ownership, and browser layout remain excluded.

### J.9 ISF input support

The active shader schema includes a `supported` flag and optional reason for every parsed input. The cockpit:

- Generates an interactive control only when supported.
- Shows incompatibility in library or diagnostics without a fake input.
- Requires conformance tests before enabling audio or audioFFT texture capability.
- Retains the prior visual when an unsupported shader cannot load safely.

### J.10 Safety and identity addenda

`SessionIdentity`:

- Generates one `engineSessionId` per project startup.
- Stores it outside `InstrumentApiExt`.
- Survives bridge, extension, and web-server reinitialization.
- Changes on a new project session.

`SafetyState`:

- Asserts blackout before Output opens at startup.
- Is not serialized with ordinary scenes.
- Provides direct latch and hold state to Mixer and lifeboat.
- Requires explicit local release after restart.
- Remains readable by ControlBridge when healthy.

### J.11 Capability rollout gate

For each addendum:

1. Implement TD behavior and pure logic tests.
2. Verify signal order and failure containment live.
3. Add protocol fixtures.
4. Advertise the granular capability.
5. Render the component state.
6. Run its visual, interaction, performance, and safety checks.
7. Add it to the rehearsal workflow.

The capability flag is the last step, not the first.
