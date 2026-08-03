---
schema_version: 1
topic: paik-abe-wobbulator-arshader
date: 2026-08-03
tier: standard
surfaces: [ui]
cousin_pattern: port-plan
activated_categories: [2, 11, 12, 13]
decisions:
  model: "not applicable"
  temperature: "not applicable"
  caching: { strategy: "not applicable", cache_control: false }
  tools_vs_text: "not applicable"
  structured_output_schema: "not applicable"
  streaming: false
  prompt_registry_entry: "not applicable"
scaffolds_wired: [ARShader-FXChain, Metal, XCTest, PixelGate]
budget_ceiling: { usd: 0, tokens: 0, wall_clock_s: 0.008, recursion_depth: 0 }
budget_scope: "sole 40-GPU-core M5 Max target; effect-only p95 at 4K30/60"
cfo_signoff: not-required
counsel_signoff: not-required
---

# Prebuild Manifest: Paik/Abe Wobbulator for ARShader

## What we're building

A first-party, in-process native ARShader FX that accepts the previous FX-chain texture and deposits its
source raster along a simulated CRT electron-beam path. Loading the effect into a deck or master
FX slot exposes the historical H/V and S-coil behaviors plus the eight experimental families named
in Eric Souther's Coil TOP post. Compression, overlap, fold, mirror, and caustic brightness must
emerge from forward beam deposition rather than a backward texture lookup.

## v1 vs v2

- v1: the complete requested built-in visual instrument for macOS ARShader, including historical H/V and
  S-coil modes, Quadrupole, Vortex, Radial Breathing, Ripple, Orbit Coil, Concentric Wave,
  Kaleidoscope, Wavefolder, scan-time modulation, HDR accumulation, diagnostics, performance tiers,
  presets, tests, and reference-video validation.
- conditional v1.1: guarded inverse Fast Preview for one-to-one states, separately approved and
  estimated after measured v1 performance. It is not required for v1.
- v2 (deferred): a public third-party plugin ABI, arbitrary user-authored coil geometry, calibrated
  amperes/tesla units tied to a measured physical CRT, iOS packaging, and a general node-graph UI.

## Category status

`PASS` means the concern is addressed by this design and has an explicit downstream gate. It does
not mean the feature is implemented or validated.

| # | Category | Status | Notes |
|---|---|---|---|
| 1 | Eval-first | PASS | Golden geometry and reference-frame fixtures precede production kernels. |
| 2 | Prior art | PASS | Expand the repo's planned `FXStageBacking` seam, port ETC behaviors, and use documented forward scanline-ribbon patterns. Do not copy unlicensed reference code. |
| 3 | Best practices | PASS | Use native Metal additive rendering and the current ARShader render-loop conventions. No runtime external SDK or service is added. |
| 4 | LLM design decisions | N/A | No model is part of the effect or render path. |
| 5 | Budget guards | PASS | No paid runtime. Effect-only p95 budgets and whole-chain headroom are defined below for the sole M5 Max target. |
| 6 | Guardrails stack | N/A | Local deterministic GPU effect, no untrusted executable content. |
| 7 | Tool airlock | N/A | No external tool calls at runtime. |
| 8 | Observability | PASS | GPU timing, sample count, fold count, dropped quality tier, and fault state must be visible in diagnostics. |
| 9 | Prompt registry | N/A | No prompts. |
| 10 | Multi-tenant posture | N/A | Single-user local creative tool. |
| 11 | Failure-mode catalog | PASS | Explicit fallback and non-black behavior are listed below. |
| 12 | HITL checkpoints | PASS | The operator approved first-party native Metal Full Beam for v1 on 2026-08-03. Later evidence checkpoints remain explicit below. |
| 13 | Scope clarity | PASS | The approved specification fixes the output, trigger, sole deployment machine, native backing, v1 renderer, and deferred scope. |

## Resolved delivery contract

- The operator approved a first-party, in-process native Metal FX with Full Beam as the only v1
  renderer on this 40-GPU-core M5 Max. Guarded inverse Fast Preview remains conditional v1.1 scope.

## Failure-mode catalog

| Failure mode | Fallback |
|---|---|
| GPU frame budget exceeded | Step down sample density and integration quality at a frame boundary, reuse the last complete output for at most one presented frame, and show the active tier. If a valid tier cannot resume, pass through. |
| Native stage fails to initialize | Pass the source through, keep the rest of the FX chain live, and expose the actionable error. |
| Field integration produces NaN, unstable low longitudinal momentum, or leaves the simulation bounds | Terminate and blank only the invalid beam sample, increment a diagnostic counter, and never poison the accumulation target. |
| HDR accumulation overflows or becomes non-finite | Scale exposure before accumulation, reject non-finite deposits, preserve finite HDR range for tone mapping, and expose gain/caustic diagnostics. |
| Strong field collapses all samples off-screen | Render black as the physically correct result only when diagnostics confirm zero screen coverage; otherwise pass through on technical failure. |
| Conditional Fast Preview approaches a fold | Disable Fast for that state, preserve the requested strength and preset, explain `Full Beam required for folds`, and offer Full Beam. |
| Unsupported device or pixel format | Select the lowest validated forward tier; if none is valid, pass through with a capability message. |
| GPU command buffer faults after submission | Mark the stage faulted on completion, recreate resources, and pass through on subsequent frames; do not claim same-frame recovery. |
| Persistence stage is disabled, resized, or receives a source/device discontinuity | Clear at the next frame boundary. Mix zero keeps phase/history live. Save/relaunch never restores framebuffer history. |
| Adaptive tier oscillates or changes exposure | Use hysteresis, energy-normalized deposition, and fixed-quality recording/test mode. |
| Resource recovery stalls on a moving frame | Hold the last complete image for no more than one presented frame, attempt one rebuild, then latch pass-through with Retry. |
| Datamosh and Wobbulator evolve incompatible native-stage seams | Assign one owner to the shared backing abstraction. Phase 2 either lands it once or waits for and extends the prior implementation. |

## HITL checkpoints

| Trigger | Reviewer | Channel | SLA |
|---|---|---|---|
| Delivery-contract approval | Operator | Conversation | Complete 2026-08-03 |
| Historical S-curve reference match | Operator plus technical review | Live ARShader comparison | Before experimental modes |
| 4K performance acceptance | Operator plus technical review | Production-port live test | Before declaring ready |
| Historical behaviors, labeled still, observed signatures, and operator-approved reconstruction | Operator plus Client Success review | Separate evidence matrix | Before completion |

## Operator contract

- First insertion preserves the source and opens on a mild `Classic S 60 Hz`; `Normal Raster` is
  one click away.
- Basic: Preset, Mode, bipolar Amount, Rate, contextual Phase/Position, Beam Width, Exposure,
  Quality, and a persistent text-plus-icon status.
- Full Beam is the required v1 renderer. Conditional v1.1 Fast Preview is a topology choice, while
  Quality is a separate cost choice. Adaptive quality never changes renderer or saved values.
- Advanced: H/V/S components, waveform, raster timing, field geometry, integration, persistence,
  finishing, and diagnostics. Numeric controls expose reset values and modulation attachment.
- Primary source is always the immediate upstream chain texture. V1 adds no source picker, and
  presets never store routing, host mix/blend, or enable state.
- With a valid source, uncovered pixels are opaque CRT black. Host Mix supplies dry/wet behavior.
- Panic Bypass latches pass-through, clears history, preserves parameters/modulation, and works
  while faulted. Reset Beam restores safe/recentered fields. Clear Persistence affects history only.
- Visible non-color-only states: Active, Quality Reduced, Beam Off-screen, No Source, Faulted and
  Bypassed, Unsupported and Bypassed.

| Event | Default temporal behavior |
|---|---|
| Disable, host bypass, or Panic | Immediate pass-through and clear history |
| Enabled with Mix zero | Keep phase/history live for dry/wet performance |
| Mode/preset/source/resize/format/device change | Atomic boundary change and clear history |
| Suspend/resume | Clear history and relock to transport |
| Save/relaunch | Restore parameters, never framebuffer history or resolved adaptive tier |

If conditional v1.1 is approved, Fast Preview is disabled for Wavefolder, sector-reflection
Kaleidoscope, and every detected multi-valued preset. Conditional modes retain Fast only above the
Jacobian safety threshold. A temporary Fast guard never rewrites the requested control or saved
preset.

Factory presets: Normal Raster, Classic S 60 Hz, S 180 Hz, H/V Collapse, Circle, Ellipse, Figure
Eight, plus at least one characteristic state for each experimental family. Recall is atomic and
clears persistence. User presets retain effect parameters, mode memories, modulation assignments,
and requested renderer/quality policy only.

## Performance contract

- Reference tier: the current 40-GPU-core Apple M5 Max development Mac.
- Sole deployment target: this 40-GPU-core Apple M5 Max with 128 GB memory. No lower-tier
  compatibility matrix is required.
- M5 Max proposed effect-only p95: at or below 4 ms at 1080p60 and 8 ms at 4K30/60.
- Benchmark 1080p30/60 and 4K30/60 where supported, with p50, p95, a ten-minute sustained thermal
  run, and separate whole-chain headroom.
- Record vertex/sample count, field evaluations, transient memory, blend overdraw, command-buffer
  GPU duration, and automatic quality transitions.
- The architecture spike compares point sprites, scanline ribbons, and adaptive scanline
  segmentation before selecting the production representation.
- Phase 1 is timeboxed to 3 to 5 engineering days. Failure to meet M5 Max 1080p60 p95 at or below
  4 ms stops production work for scope renegotiation. A 1080p pass with a 4K miss forces an explicit
  supported-tier choice or a separately estimated optimization phase.
- Phase 1 also freezes numerical acceptance thresholds and triggers mandatory schedule
  re-estimation before production kernels.

## Validation gates

- Double-precision CPU trajectory oracle versus the GPU magnetic pusher.
- Resolution-independent 525/59.94, 625/50, and progressive/custom virtual raster timing fixtures,
  including porch, sync, retrace, blanking, and interlaced parity.
- Base-yoke identity fixture before experimental fields are enabled.
- Numerical divergence and symmetry checks for every field labeled physical.
- Exposure and caustic-shape invariance across sample density, output resolution, beam width, and
  quality tier.
- Extreme-field fuzzing for NaN, low longitudinal momentum, off-screen paths, and non-finite HDR.
- Existing ISF regressions for generators, secondary image inputs, compilation, order, mix, blend,
  and synchronous nil-render pass-through.
- Native texture ownership, non-aliasing, resize, teardown, and asynchronous Metal-fault recovery.
- Linear-light, premultiplied-alpha, HDR, tone-map, and temporal-history lifecycle fixtures.
- Fixed-quality deterministic recording mode and sustained p95 GPU timing on the named tiers.
- Staged native-app exercise with moving color and grid/line sources, source changes, rapid
  mode/preset recalls, Mix sweeps, bypass/re-enable, extreme modulation, off-screen black, injected
  GPU fault, save/relaunch, and sustained thermal load.
- Control response by the next presented frame, no black gap or compile stall during prepared
  changes, monitor-only diagnostics, non-color-only status, 14 px minimum text, and keyboard plus
  VoiceOver access for Panic, bypass, presets, and primary controls.

## Explicit v1 non-goals

- Exact source/preset parity with Souther's undisclosed operator.
- A distributable ISF or public plugin ABI.
- Calibrated physical units, iOS delivery, arbitrary coil authoring, or a general node graph.
- Redistribution of the captured reference media or unlicensed reference code.
- Conditional Fast Preview unless it receives separate post-spike approval.

## Brand/voice constraints

- `/Users/arsonrivvers/.claude/user-context/profile.yaml`
- Minimum rendered text size: 14 px equivalent.
- Controls use concrete video-synthesis language, with Basic and Advanced disclosure rather than
  a flat wall of physics parameters.
- Physically grounded, physically inspired, hybrid, and artistic modes are labeled honestly.
