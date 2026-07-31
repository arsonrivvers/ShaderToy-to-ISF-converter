---
schema_version: 1
topic: ar-shader-adaptive-cybernetic-cockpit
date: 2026-07-24
mode: retrofit
tier: standard
surfaces:
  - user_facing_ui
  - local_control_api
  - external_libraries
  - persistent_local_state
cousin_pattern: port-plan
activated_categories:
  - 2
  - 3
  - 6
  - 7
  - 8
  - 11
  - 12
  - 13
decisions:
  model: not_applicable_no_runtime_llm
  temperature: not_applicable
  caching:
    strategy: immutable_hashed_assets_no_store_authority_responses
    cache_control: false
  tools_vs_text: typed_semantic_commands
  structured_output_schema: webui/protocol/instrument-api-v1.schema.json
  streaming: false
  prompt_registry_entry: not_applicable
scaffolds_wired: []
budget_ceiling:
  usd: 0
  tokens: 0
  wall_clock_s: 0
  recursion_depth: 0
cfo_signoff: not_required
counsel_signoff: not_required_for_local_build
---

> ⛔ **SUPERSEDED 2026-07-30.** This manifest pins a Svelte/Vite/three.js dependency set and a
> WebSocket protocol schema for the browser cockpit, which was abandoned for the native macOS app.
> **Install nothing from this file.** Retained only as the record of what was decided and why.
> Ported from `AV_Projects/AR_Shader` on 2026-07-31.

# Prebuild Manifest: AR_Shader Adaptive Cybernetic Cockpit

## Prebuild outcome

Proceed with the approved Adaptive Cybernetic Cockpit as a retrofit over the existing TouchDesigner instrument.

The architecture remains:

- Svelte 5 and TypeScript
- Vite static production bundle
- One shared Three.js WebGL atmosphere driven by the existing validated instrument store
- TouchDesigner Web Server DAT for local HTTP and WebSocket service
- Separate reliable control and droppable telemetry WebSocket lanes
- TouchDesigner as the sole engine authority
- A separate direct native lifeboat for safety and recovery
- No show-time Node process, middleware server, cloud service, or Envoy dependency

Prebuild found no reason to change this architecture. It did find one local deployment cousin and two project-state gates that must shape implementation order.

## Why this is standard tier

The approved product spec calls this a just-me instrument. Prebuild uses the standard methodology tier because the build is durable, spans multiple implementation sessions, will be maintained by future Conner and agent collaborators, and controls show-critical output.

The runtime remains local and cost-free. Standard tier here adds planning, failure, and verification rigor without adding production SaaS infrastructure.

## What is already built

| Area | Current truthful state | Prebuild treatment |
|---|---|---|
| Phase A IsfPlayer | Confirmed on-device | Stable engine foundation |
| Phase B instrument core | Staged and accepted as reliable for cockpit planning | Do not reopen its completed design decisions |
| Four decks, Mixer, SourceRouter, Output, SceneState | Present | Adapt through semantic interfaces |
| AudioEngine and Phase C work | Engineering complete and reviewed through Task 8; Task 9 is the operator's real-device live smoke | Treat the staged build as dependable per operator approval, then capture the exact live capability baseline before adapters |
| Existing `/project1/Ui` | Library and deck-selection behavior exists; panel is explicitly throwaway and quiesced | Behavioral reference only; do not extend or clone it |
| Existing `/project1/Ui` panel rendering | Recursion root cause fixed and externalized in `bc956b2`; diagnostic report committed in `e328e88` | Closed prerequisite; preserve its listCOMP callback rule for the new lifeboat |
| Svelte cockpit | Not built | New `webui/` source tree |
| ControlBridge, SessionIdentity, SafetyState, UiLifeboat | Not built | New externalized TouchDesigner components |
| Appendix J engine addenda | Not built unless a live capability says otherwise | Build and advertise independently |

Per the operator's approval, the staged instrument is treated as a dependable foundation. The old panel-render crash is closed, and the old panel remains throwaway. Cockpit implementation starts from a fresh capability capture rather than reopening completed engine or diagnostic work.

## What the user sees and what triggers it

**Artifact:** A full-screen Adaptive Cybernetic Cockpit with stable `PERFORM`, `PATCH`, and `SYSTEM` modes, connected to the running AR_Shader TouchDesigner project.

**Trigger:** The operator opens the loopback URL served by `ControlBridge`. The browser fetches `/api/v1/bootstrap`, validates the API and engine session, opens the control and telemetry lanes, receives one authoritative snapshot, and enters `PERFORM`.

The browser must remain useful against the current engine slice. Unsupported controls stay absent until their granular capabilities are true.

## Cousin pattern and port boundary

### Engine cousins to port

- `project1/IsfPlayer/IsfPlayerExt.py`: shader load, warm, commit, fail, and supersede lifecycle
- `project1/SourceRouter.tdn`: safe fallback and self-route rejection
- `project1/Output/OutputExt.py`: preferred versus actual output state
- `project1/SceneState/SceneStateExt.py`: versioned scene persistence and exclusions
- `project1/AudioEngine.tdn`: stable bus and dropout behavior after Phase C stabilizes
- Phase B and C implementation plans: STAGED versus CONFIRMED gates, Embody externalization, WIP commit cadence, and shared cook-window discipline
- The existing `UiExt` library search and explicit deck-selection behavior

### Local web deployment cousin

`/Users/arsonrivvers/Desktop/AV_Projects/TouchDesigner/ImmersiveHQ_Coursework/WK14-15/web_dashboard` proves:

- Vite `base: './'`
- Static `dist/` output
- Development WebSocket proxying
- Same-host production service through TouchDesigner
- Runtime validation of incoming messages
- Capped reconnect behavior

Port only those mechanics.

Do not port:

- React, Zustand, Tailwind, or its visual layout
- The single mixed WebSocket
- Raw `setParam` messages
- Arbitrary TouchDesigner OP paths
- Its optimistic-only state model
- Its implicit server binding
- Any production Vite server

### Cousin decision

This is a port plan, not a fresh architecture search. Reuse deployment mechanics and engine invariants while implementing the approved Svelte composition and semantic protocol.

## v1 and v2

### v1

- Capability-sliced local cockpit
- Protocol fixtures shared by Python and TypeScript
- Direct startup identity and fail-closed safety state
- Separate new native lifeboat
- ControlBridge HTTP, control WebSocket, and telemetry WebSocket
- Static Svelte shell with the approved visual system
- Required data-reactive Three.js environment with animated `low` quality as the minimum normal shipping state
- Current-engine controls first
- Library, shader lifecycle, and generated inspector
- Phase C audio and modulation surface after its contract stabilizes
- Eight independently gated engine-addendum slices
- Preview only after control, safety, and frame budgets pass
- Full protocol, integration, accessibility, security, latency, and soak gates

Full VDMX parity is complete when the required Appendix J capabilities are implemented and advertised. Earlier capability slices remain usable releases.

### v2

- Remote LAN operation, TLS, and authentication
- Tauri packaging
- Higher-rate WebRTC preview
- Multi-controller collaboration
- User-configurable layouts
- Timeline automation and scene morphing
- Service worker or PWA behavior
- Cloud sync, hosted analytics, accounts, or remote media
- Mobile-specific composition

## Category status

| # | Category | Status | Notes |
|---|---|---|---|
| 1 | Eval-first | N/A | No LLM or probabilistic runtime behavior |
| 2 | Prior art | PASS | AR_Shader engine cousins and the local TouchDesigner web-dashboard deployment cousin are identified |
| 3 | Best practices | PASS | Current compatible package versions and TouchDesigner serving constraints are recorded |
| 4 | LLM design decisions | N/A | No runtime LLM |
| 5 | Budget guards | N/A | No metered API, hosting, cron, or recurring service |
| 6 | Guardrails stack | PASS | SafetyState, semantic validation, ownership, revisions, capability gating, and native lifeboat form the required stack |
| 7 | Tool airlock | PASS | Performer API is deny-by-default and exposes semantic commands only |
| 8 | Observability | PASS | Command ID, operation ID, revision, frame, latency, health, and session identity are required |
| 9 | Prompt registry | N/A | No prompts |
| 10 | Multi-tenant posture | N/A | One local operator with read-only observers |
| 11 | Failure-mode catalog | PASS | Explicit fallbacks and containment are listed below and in the approved spec |
| 12 | HITL checkpoints | PASS | Operator and reviewer gates are fixed below |
| 13 | Scope clarity | PASS | Artifacts, routes, authority, sequence, exclusions, and task graph are fixed |

## Current best practices and pins

Core versions were checked against official release pages and the npm registry on 2026-07-24. The Three.js pins were checked against the npm registry on 2026-07-26:

| Dependency | Exact initial pin |
|---|---:|
| Node.js | `24.18.0` |
| npm | `11.16.0` |
| `@types/node` | `24.13.3` |
| Svelte | `5.56.6` |
| `@sveltejs/vite-plugin-svelte` | `7.2.0` |
| Vite | `8.1.5` |
| TypeScript | `6.0.3` |
| Three.js | `0.185.1` |
| `@types/three` | `0.185.1` |
| `svelte-check` | `4.7.3` |
| Vitest | `4.1.10` |
| `@testing-library/svelte` | `5.4.2` |
| `@playwright/test` | `1.61.1` |

> Pin caveat: `@types/three` patch versions rarely align exactly with three's. Re-verify both exact versions against the npm registry at Task 20 install time; if `@types/three@0.185.1` does not exist, pin the nearest published `0.185.x` and record the substitution here.

Rules:

- Commit a lockfile.
- Use exact versions in the first implementation slice.
- Pin TypeScript below the registry latest because stable `typescript-eslint` 8.64.0 declares support through TypeScript 6.0.x. Do not use an alpha lint toolchain to chase TypeScript 7.
- Treat dependency updates as isolated, verified changes.
- Build with `base: './'`.
- Run Vite only for development and build.
- Serve `dist/` from TouchDesigner in production.
- Bind the Web Server DAT explicitly to `127.0.0.1`.
- Keep source maps off in the production show bundle.
- Resolve static paths against one fixed `dist/` root.
- Reject traversal, dot segments, symlink escape, and unallowlisted files.
- Return correct MIME types.
- Cache hashed assets immutably.
- Return `no-store` for bootstrap, health, and the SPA entry document.
- Use an explicit SPA fallback only for allowed browser routes.
- Treat browser `WebSocket.bufferedAmount` as a pressure signal, not automatic backpressure.
- Bound server queues and disconnect or degrade slow clients.

Primary references:

- [TouchDesigner Web Server DAT](https://derivative.ca/UserGuide/Web_Server_DAT)
- [TouchDesigner WebserverDAT callbacks](https://derivative.ca/UserGuide/WebserverDAT_Class)
- [Node.js 24.18.0 release](https://nodejs.org/en/blog/release/v24.18.0)
- [Vite 8 announcement and Node requirements](https://vite.dev/blog/announcing-vite8)
- [Vite production build](https://vite.dev/guide/build)
- [Vite static deployment](https://vite.dev/guide/static-deploy.html)
- [`@types/node` versions](https://www.npmjs.com/package/%40types/node?activeTab=versions)
- [Svelte Vite plugin](https://www.npmjs.com/package/@sveltejs/vite-plugin-svelte)
- [WebSocket API](https://developer.mozilla.org/en-US/docs/Web/API/WebSocket)

## Scope clarity

### New source artifacts

```text
webui/
  package.json
  package-lock.json
  vite.config.ts
  tsconfig.json
  src/
  static/
    fonts/
    icons/
  protocol/
    protocol-contract-v1.json
    instrument-api-v1.schema.json
    preview-lane-v1.schema.json
    fixtures/
    preview-fixtures/
  tests/
  dist/

project1/
  SessionIdentity.tdn
  SessionIdentity/
  SafetyState.tdn
  SafetyState/
  UiLifeboat.tdn
  UiLifeboat/
  ControlBridge.tdn
  ControlBridge/
    InstrumentApiExt.py
    webserver_control_callbacks.py
    webserver_telemetry_callbacks.py
    preview_callbacks.py
    protocol.py
    protocol_generated.py
    adapters/
```

`dist/` is a generated production artifact. The implementation plan must decide and document whether it is committed or reproducibly rebuilt before show deployment. Production must never depend on an unstated local Vite process.

### Public local routes

- `/`
- Approved SPA routes under the same entry document
- `/api/v1/bootstrap`
- `/health`
- `/api/v1/library`
- `/api/v1/thumbnail/{shaderId}`
- `/ws/control`
- `/ws/telemetry`
- Optional `/ws/preview` on `127.0.0.1:9983`, advertised only when installed and healthy

No route accepts an arbitrary filesystem path, TouchDesigner path, expression, Python source, or shell command.

### Authority

| State | Authority |
|---|---|
| Deck, shader, mixer, route, audio, modulation, output, scene, recorder | TouchDesigner |
| Safety latch and boot blackout | `SafetyState` |
| Project startup identity | `SessionIdentity` |
| Command validation and publication | `ControlBridge` |
| Browser selection, drawer, density, and local focus state | Svelte client |
| Current controller lease | TouchDesigner |
| Production static files | Built `webui/dist/` served by TouchDesigner |

### Persistent state

- Ordinary scenes persist only approved instrument state.
- Blackout, SafetyState, engine session, controller ownership, output geometry, and browser layout remain outside ordinary scenes.
- Browser preferences may use local storage only for non-authoritative presentation settings.
- Reconnect always replaces engine state from a fresh snapshot.

### Runtime exclusions

- No Node server
- No FastAPI, Flask, Socket.IO, or OSC relay
- No cloud or internet dependency
- No service worker
- No runtime Envoy
- No arbitrary TouchDesigner path access
- No primary Web Render TOP

## Sequencing gates

### Gate 0A: Existing UI crash — closed

The diagnostic proved mutually re-entrant listCOMP layout writes in `onInitCol` and `onInitRow`; the externalized fix moved layout authority out of those callbacks. Commit `bc956b2` closes the crash, and `e328e88` records the Derivative report evidence.

No implementation task reopens this work. The old `Ui` remains quiesced and throwaway. `UiLifeboat` is a new minimal COMP and must not clone the old panel tree or write row/column layout attributes from listCOMP initialization callbacks.

### Gate 0B: Accepted engine baseline capture

Before ControlBridge adapters touch shared engine components:

1. Use the received Phase C engineering handoff and the operator-approved staged instrument.
2. Record the exact current accepted commit and require a clean or explicitly scoped worktree.
3. Generate the first real bootstrap fixture from that checkpoint.
4. Do not copy illustrative capability values from the design spec.
5. Advertise `Bindings`, LFO, audio, or related features only when the live component contract is true.

### Envoy and worktree discipline

- The Phase C handoff is now available. Recheck ownership and worktree state at execution time because the real-device live-smoke artifact may still be in progress.
- Live TD mutation lanes use disjoint Envoy claim scopes.
- Pure Svelte and pure protocol work may run in parallel only in non-overlapping files.
- All cook-heavy work and all performance measurement share the same `project:sweep` claim.
- Verify no in-TD background batch remains active before timing.
- Save externalizations and make step-level WIP commits after each live TD construction step.
- Never run parallel agents against the same dirty shared paths.

## Recommended task graph

The Product Manager review recommends 22 implementation tasks across seven phases:

1. **Stabilize, 2 tasks**
   - Adopt the already-closed native UI crash evidence and preserve the throwaway-panel boundary.
   - Capture the actual capability baseline from the operator-approved engine checkpoint.
2. **Contract and Safety, 3 tasks**
   - Freeze schema, fixtures, limits, and cross-language validators.
   - Build SessionIdentity, SafetyState, and the separate UiLifeboat.
   - Build ControlBridge HTTP and WebSocket lanes with semantic adapters.
3. **Core Cockpit, 3 tasks**
   - Scaffold the exact-pinned Svelte application and fixture transport.
   - Implement the approved static shell and design tokens.
   - Wire current-engine performance controls, library, and inspector.
4. **Phase C Surface, 1 task**
   - Wire audio, current timing, LFO, and bindings after the Phase C contract stabilizes.
5. **Capability Addenda, 8 tasks**
   - Dynamic A/B plus master level
   - Ordered deck and master FX racks
   - Clock authority
   - Advanced audio
   - Recorder, still, quantize, and direct Stop
   - Scene administration
   - Advanced LFO and MIDI
   - ISF audio and audioFFT textures
6. **Hardening, 2 tasks**
   - Add subordinate preview and performance degradation.
   - Establish the clean functional-cockpit security, accessibility, latency, soak, and rehearsal baseline.
7. **Living Visual System, 3 tasks** (= plan "Phase 6" — the plan numbers phases from 0; the spec stages this as Appendix G.12 "Phase 9" in its own rollout sequence)
   - Build the isolated Three.js renderer, typed signal derivation, adaptive quality, teardown, and atmosphere-off fallback.
   - Art-direct the bounded signal field, particle population, and routing-filament behavior, then stop for Mechanic, Client Success, and Conner approval on the production build.
   - Benchmark and certify the complete animated cockpit at `low` animated quality or better. `static` and `off` remain fallbacks, not acceptable normal release states.

### PM review decision, 2026-07-26

**VERDICT: SHIP**

The living visual system belongs in required v1 product scope because the operator explicitly values the cybernetic, hyper-futurist experience as part of the instrument rather than optional decoration. The review made two structural corrections before approval:

1. The original single animation task was too broad to review honestly. It is now three independently gated tasks for renderer isolation, art-direction payoff, and final performance certification.
2. The original fallback language allowed permanent `static` or `off` operation to count as feature completion. Normal production must now pass at `low` animated quality or better; non-animated states remain safety and accessibility fallbacks.

The scope is intentionally bounded to one signal field, one particle population, and one routing-filament layer. There is no theme system, visual preset editor, second rendering framework, or arbitrary browser shader authoring in v1. No user decision remains open before implementation.

### Known open engine caveats (2026-07-26 final review)

These are engine-side items from the Task 9 live-smoke and branch review that the cockpit surfaces directly. They are not user decisions, but each must be fixed or truthfully displayed before the surface that touches it ships (see plan Task 9 Step 1):

1. Loudness dB window saturates on BlackHole loopback (gain staging queued, `arshader-audio-polish-20260726`).
2. Essentia `bpm` does not read 0 on silence per contract; it wanders ~70–180.
3. `Analyzer` defaults are still `native` in `scene_state.py` `DEFAULT_AUDIO` and the AudioEngine par default — a v1 scene restore silently degrades analysis off essentia; `AudioEngine.Status` init text is also stale (`arshader-review-findings-fixes-20260726`).
4. The `Device` custom par is disconnected as of `49682eb` (hardcoded `BlackHole2ch_UID` on `audiodevin_mic`); re-wire before shipping a Device selector. Audio Device In also falls back silently on a missing named device (dropout-hold detection folded into the Phase B hardware-smoke gate).

Load-bearing dependencies:

- Clock precedes recorder quantization.
- FxRack precedes chain presets.
- Bindings precedes LFO and MIDI UI.
- AudioEngine precedes advanced audio and ISF audio textures.
- SafetyState and UiLifeboat precede reliance on browser control.
- The functional Task 19 baseline precedes Three.js integration.
- Renderer isolation precedes art-direction tuning, and Conner's visual approval precedes final performance certification.
- Protocol fixtures precede either implementation language.
- Preview is last.

## Failure-mode catalog

| Failure mode | Required fallback |
|---|---|
| Old `Ui` panel behavior regresses | Keep it quiesced and throwaway; do not reuse it for the lifeboat or browser cockpit |
| Phase C changes overlap cockpit adapters | Stop shared-file work and wait for a clean Phase C checkpoint |
| Browser does not open | TD keeps rendering; use the new native lifeboat |
| Static asset path is malformed or traverses | Reject before filesystem access |
| Entry document or bootstrap is cached stale | `no-store`, validate API version and engine session, refuse writes until snapshot |
| Control socket disconnects | Disable browser writes, preserve TD output, reconnect, and fetch fresh state |
| Telemetry socket slows | Drop old samples and retain latest values without affecting control |
| Slow control client accumulates output | Bound queues, coalesce state, then disconnect the client |
| Duplicate command arrives | Replay the retained result for an identical payload without re-execution; reject same-ID/different-payload conflicts |
| TD extension reinitializes | Preserve `engineSessionId` outside the extension |
| TD project restarts | Generate a new session ID, assert blackout, and require explicit local release |
| Capability fixture differs from live engine | Live capability truth wins; fail the fixture test and hide the surface |
| Shader load fails | Keep the last valid visual live |
| Old shader inspector sends a write | Reject as stale and reconcile from canonical schema |
| Native lifeboat disagrees with browser | Direct TD safety and output state wins |
| Preview stalls or degrades render health | Reduce or disable preview before control or render is affected |
| Recorder fails | Keep program output live and preserve direct native Stop |
| External display or audio disappears | Publish structured degraded state and use verified engine fallback |
| Browser receives malformed state | Runtime validator rejects the message and surfaces a bounded fault |
| Package upgrade changes build output | Lockfile and isolated dependency verification prevent silent drift |

## Guardrails and airlock

The local API is deny-by-default.

Allowed:

- Typed semantic command families
- Stable target IDs
- Validated finite values and enums
- Capability-negotiated operations
- Bounded local asset requests

Denied:

- Arbitrary OP paths
- Arbitrary parameter names
- Python or expression evaluation
- Shell commands
- Raw filesystem paths
- Remote interfaces in v1
- Unbounded payloads, queues, subscriptions, or logs
- Observer writes

Safety stack:

1. Loopback-only network binding
2. Cryptographic short-lived bootstrap URI nonce and engine-session validation
3. Single controller lease
4. Strict schema and command allowlist
5. Revision and shader-generation checks
6. Direct SafetyState and UiLifeboat outside the browser path

## Observability contract

Every accepted command is attributable through:

- `engineSessionId`
- client and controller identity
- `commandId`
- `operationId` when transactional
- semantic target
- accepted time
- applied time
- TD frame
- resulting revision
- one terminal outcome

Performance evidence separates:

- Browser-local paint
- Command acceptance
- Fast application
- Transaction completion
- Rendered visual consequence

No observability path may create per-frame full-state serialization, unbounded history, or zero-client cooking.

Protocol source ownership is singular: `webui/protocol/protocol-contract-v1.json` is handwritten; JSON Schema plus Python and TypeScript tables are generated and checked for drift. Connection state binds nonce, client identity, sequence, and controller authority to the physical WebSocket rather than trusting an envelope alone.

## HITL checkpoints

| Trigger | Reviewer | Evidence |
|---|---|---|
| Existing `Ui` crash fix | Satisfied before this plan | Root-cause fix `bc956b2` plus report `e328e88`; no reimplementation |
| Phase C checkpoint | Current Phase C owner | Clean tested capability baseline |
| Protocol fixture freeze | PM and implementation agent | Python and TypeScript fixture parity |
| Static `PERFORM` composition | Conner | Local browser screenshot at approved viewport |
| UiLifeboat | Conner | Live blackout and recovery smoke with browser services disabled |
| First end-to-end scalar | Conner | Browser gesture, accepted ack, applied ack, TD value, rendered result |
| Library and inspector | Conner | Real shader load, failure, supersede, and stale-control workflow |
| Audio and modulation | Conner | Real-device smoke |
| Output and recorder | Conner | External display and capture smoke |
| Server and external-input handling | CSO | Defensive review before ship |
| Any UI increment declared ready | Mechanic and Client Success | Production build, local preview, accessibility and payoff review |
| Final rehearsal | Conner | Representative performance, disconnect recovery, and 30-minute soak |

## Brand and voice constraints

Sources:

- `/Users/arsonrivvers/.claude/user-context/profile.yaml`
- `docs/superpowers/specs/2026-07-24-ar-shader-adaptive-cybernetic-cockpit-ui.md`

Binding constraints:

- Dark interface
- No important text below 14 px
- Peer-level, technical, and maker-literate language
- Concrete state labels instead of marketing language
- No generic AI phrasing or corporate gloss
- Cybernetic means visible cause and effect, not fictional HUD decoration
- Media remains the dominant source of saturation
- Safety meaning never depends on color alone
- No full-screen captures on the shared Mac
- Start the local development server for browser review before committing any UI increment

## Cost and distribution

- Runtime hosting: `$0`
- Runtime API calls: `$0`
- Runtime recurring services: `$0`
- Development dependencies: open-source packages, locally installed
- Tandem Envoy execution: no new deployed service, but approximately 2 to 3 times concurrent agent-session usage while multiple lanes are active
- EssentiaTD remains user-installed and unbundled under the existing AGPL boundary
- Counsel review becomes mandatory before distributing or productizing a build that includes or bundles restricted dependencies

## Open questions

None. The approved spec, operator preferences, current project evidence, and prebuild reviews answer the implementation-shaping questions.

Operational gates remain, but they do not require a new product decision:

- Preserve the closed native UI diagnostic and do not extend the throwaway panel.
- Capture the exact accepted Phase C/current-engine checkpoint.
- Generate real capability fixtures from that checkpoint.
- Review each capability slice before advertising it.
