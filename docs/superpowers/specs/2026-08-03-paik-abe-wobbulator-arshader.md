---
schema_version: 1
topic: paik-abe-wobbulator-arshader
date: 2026-08-03
tier: just-me
status: complete
correlation_id: arshader-paik-abe-wobbulator-20260803
---

# ARShader Paik/Abe Wobbulator Native FX Specification

## 1. What we're building

A first-party, in-process native Metal FX inside ARShader that traces the immediate upstream video texture as a virtual CRT electron beam through historical Paik/Abe-style deflection and a library of experimental fields. It must produce forward-deposited folds, retrace, mirrors, caustics, and true no-coverage black areas in real time on this computer's 40-GPU-core Apple M5 Max with 128 GB memory.

The product is a reconstruction of the documented mechanism and visible public signatures. It does not claim source-level equivalence to Eric Souther's undisclosed C++ TouchDesigner operator.

## 2. User-visible output + trigger

- **Output the user sees:** The upstream deck or master image becomes a beam-traced CRT raster. Source color follows the traced beam; compressed and retraced regions brighten additively; uncovered regions are opaque black. The stage exposes historical H/V and S behaviors, the eight named experimental families, presets, modulation, quality state, and live diagnostics.
- **What triggers it:** The operator inserts and enables Wobbulator in a deck or master FX chain. First insertion immediately loads a mild Classic S 60 Hz state while preserving a recognizable source image. Normal Raster is one click away. Control and modulation changes become visible by the next presented frame.

## 3. Cousin pattern

**Port from:** docs/superpowers/specs/2026-08-03-datamosh-node-design.md. Port only the concept of one shared first-party native FX backing alongside the existing ISF backing. The Datamosh three-argument backing sketch is not implemented and is too narrow for this effect, so the shared seam must be expanded once rather than allowing Datamosh and Wobbulator to create incompatible abstractions.

The native stage contract has four parts:

- **FXStageDescriptor:** A Sendable value describing stage identity, generator/filter behavior, control descriptors, secondary input descriptors, status vocabulary, and capabilities for the UI.
- **FXStageRenderCore:** A render-thread-safe object that encodes one frame and owns native GPU resources, temporal state, telemetry, and asynchronous Metal fault state.
- **FXRenderContext:** An immutable per-frame value containing frame time, delta time, output size, command buffer, pixel format, linear color and premultiplied-alpha contracts, requested quality policy, and host preserve-alpha setting.
- **FXEncodeResult:** Either a produced non-aliased texture plus telemetry, or a typed pass-through result explaining synchronous failure, unsupported state, no source, or a previously observed asynchronous fault.

ISFStageBacking preserves ShaderUnit behavior, including generators, compilation, controls, errors, secondary image inputs, and renderOffscreen. BeamTraceStageBacking implements the native path. Parameter values are snapshotted before publication to the render thread. Output may not alias the input texture or compositor destination. Lifecycle events cover enable, disable, mix zero, source discontinuity, preset recall, resize, pixel-format change, device change, suspend, resume, panic, retry, and teardown.

This is trusted deterministic Metal code. It stays in-process; XPC is not part of the design.

## 4. Tier + why

**Tier:** just-me

The operator is the only user, and this exact Apple M5 Max Mac is the only deployment target. There is no public distribution, compatibility matrix, runtime account, hosted service, or recurring cost. The implementation can optimize specifically for this GPU while preserving clean host boundaries and deterministic tests.

## 5. Surfaces

- **Swift host integration:** Generalize FXStage and FXChain so ISF and native Metal stages share ordering, enable, mix, blend, source, status, and lifecycle behavior.
- **Metal beam simulation:** Generate virtual raster samples, evaluate scan-time fields, integrate trajectories, and deposit source energy forward into HDR.
- **Native control surface:** Present a small playable Basic surface, an Advanced physics/modulation surface, persistent status, Panic Bypass, Reset Beam, and Clear Persistence.
- **Preset and modulation state:** Store effect parameters, mode memories, modulation assignments, and requested quality policy without capturing host routing, mix, blend, enable state, framebuffer history, or resolved adaptive tier.
- **Diagnostics and recovery:** Report coverage, numerical-invalid count, field/integrator state, GPU duration, sample count, quality changes, and actionable fault state without routing diagnostics to program output by default.
- **Local research fixtures:** Use the gitignored Instagram media, derived keyframes, historical PDFs, and deterministic generated fixtures during development. None enters the application bundle or public repository history.

## 6. v1 vs v2

**v1 (ships now):**

- First-party built-in Full Beam renderer only.
- Normal Raster, H/V Yoke, S Curve, Vortex, Radial Breathing, Ripple, Quadrupole, Orbit Coil, Concentric Wave, Kaleidoscope, and Wavefolder.
- Resolution-independent 525/59.94, 625/50, and progressive/custom virtual CRT timing.
- Base-yoke identity calibration, Maxwell-consistent physical fields, a relativistic Boris magnetic pusher, and a double-precision CPU trajectory oracle.
- Energy-normalized forward deposition into linear RGBA16Float, opaque-black no-coverage pixels, source-color retention, fixed and adaptive quality, and deterministic recording quality.
- Basic and Advanced controls, ARShader modulation attachment, factory and user presets, optional persistence/bloom/phosphor finishing, accessibility, status, Panic Bypass, Reset Beam, Clear Persistence, and Retry.
- Sole-device performance proof at 1080p60 and 4K30/60 on this M5 Max.
- Existing ISF behavior preserved through a shared native-stage backing abstraction.

**v2 (deferred):**

- Guarded inverse Fast Preview for one-to-one mappings, only if later measurements show enough value to justify separate scope.
- Public third-party plugin ABI or distributable ISF approximation.
- Support for other Macs, iOS, calibrated amperes/tesla/CRT dimensions, arbitrary user-authored coil geometry, or a general node graph.
- Any redistribution of captured reference media.

## 7. Stage-by-stage

### Stage 1: Host stage creation and render publication

- **Input:** An operator inserts Wobbulator into a deck or master FX chain.
- **Logic:** Construct the first-party descriptor and BeamTraceStageBacking, load the Classic S 60 Hz factory preset, reserve the immediate upstream texture as the primary input, and publish an immutable parameter/render snapshot to FXChain.
- **Output:** A native stage that inherits current chain order, enable, host Mix, all 19 blend modes, and upstream-source semantics.
- **Constraint:** The shared backing generalization must leave all existing ISF generators, filters, secondary inputs, compilation, nil-render pass-through, ordering, mix, and blend behavior regression-identical.

### Stage 2: Virtual CRT raster and base yoke

- **Input:** Upstream texture, render size, frame time, delta time, quality policy, and the selected timing fixture.
- **Logic:** Generate source-raster coordinates independently of output resolution. Compute beam time as field start plus line index times line period plus active-start offset plus horizontal active coordinate times active duration. Advance oscillator phase through porch, sync, retrace, and vertical blanking while suppressing deposition during blanked intervals. Apply base-yoke slopes or fields calibrated so zero experimental field maps the active raster to identity at the screen.
- **Output:** Source UV, source-cell area, represented dwell time, beam time, and initial position/momentum for every active sample.
- **Constraint:** Equal transport time and parameters must produce phase agreement within 0.0001 cycle across 1080p and 4K.

### Stage 3: Field evaluation and trajectory integration

- **Input:** Initial beam state, beam time, selected mode, continuous controls, and immutable modulation values.
- **Logic:** Evaluate coil current from bias, amplitude, waveform, frequency or sync ratio, phase, and duty. Transform every active field by its center, orientation, radius, and length; sum fields before integration. Historical H/V uses transverse dipoles. S Curve uses a finite solenoid model with off-axis and fringe components. Quadrupole uses a validated four-pole field. Modes called physical use an analytic field, vector potential, or validated field map and pass symmetry plus numerical-divergence checks. Vortex, Radial Breathing, Ripple, and Orbit Coil are labeled physically inspired. Concentric Wave and Wavefolder are artistic operators. Kaleidoscope is labeled hybrid and states whether it uses a smooth six-pole/sextupole field or sector reflection. Integrate magnetic trajectories with a relativistic Boris pusher. Terminate and count a ray if forward momentum p_z/p_0 falls to 0.01 or below, or if it leaves the simulation bounds.
- **Output:** A destination screen position and validity state for each source sample.
- **Constraint:** Artistic operators still feed the common forward deposition stage. They may not be substituted with a final screen-space texture warp.

### Stage 4: Full Beam forward deposition

- **Input:** Destination positions, source UV/color, source-cell area, dwell time, beam current, beam width, and validity.
- **Logic:** Use the Phase 1 winning representation from Gaussian point sprites, scanline ribbons, or adaptive scanline segmentation. Weight every contribution by beam current times represented dwell/source area. Normalize the finite beam kernel by integrated energy. Accumulate premultiplied source color in linear light into a capability-tested RGBA16Float target with additive blending. Reject blanked, invalid, or non-finite samples before accumulation.
- **Output:** An HDR beam image where retrace and overlap brighten, folds preserve every branch, and uncovered pixels are opaque CRT black.
- **Constraint:** Quality changes may alter sampling and integration cost, but may not change Full Beam into inverse rendering, rewrite a requested control, change a saved preset, or move exposure outside the declared tolerance.

### Stage 5: Display finishing and host composite

- **Input:** HDR beam image, finishing parameters, current temporal history, host Mix, host blend mode, and preserve-alpha contract.
- **Logic:** Apply optional phosphor persistence in explicit ping-pong history, then bloom, phosphor color, scanline visibility, exposure, and tone mapping. Finishing never changes the beam map. Composite through ARShader's existing stage compositor.
- **Output:** The finished stage result in the host's expected color/pixel format.
- **Constraint:** With a valid source, the stage output is opaque, including black no-coverage pixels. Dry/wet behavior belongs to host Mix. No arbitrary hard clamp may destroy HDR caustic range before tone mapping.

### Stage 6: Operator controls and presets

- **Input:** Operator gestures, modulation values, factory presets, and user presets.
- **Logic:** Basic exposes Preset, Mode, Amount, Rate, contextual Phase/Position, Beam Width, Exposure, Quality, and persistent status. Defaults are Classic S 60 Hz, Amount +0.30 on a bipolar -1.00 to +1.00 range, Rate 1 x field, Phase 0 degrees or centered position, Beam Width 1.25 pixels at 1080p with a 0.25 to 8.0 range scaled by output resolution, Exposure 0 EV on a -8 to +8 EV range, and Quality Auto. Quality choices are Auto, High, Balanced, Performance, and Fixed Recording.

  Advanced exposes H/V/S component gains from -1 to +1; Sine, Triangle, Saw, and Square waveforms; duty from 1 to 99 percent; free frequency from 0.01 to 20,000 Hz; field-sync ratios from 1/8 x to 8 x; raster timing fixtures 525/59.94, 625/50, and Progressive/Custom; custom active samples from 64 to 8192, active lines from 64 to 4320, total lines from active lines to 8192, field rate from 1 to 240 Hz, active-start and active-duration fractions from 0 to 1 line, and progressive/interlaced parity; field center X/Y from -2 to +2 and Z from -1 to +1; orientation from -180 to +180 degrees; normalized coil radius/length from 0.01 to 4; beam rigidity from 0.1 to 10; throw from 0.1 to 4; Ripple cycles from 0.25 to 64; Kaleidoscope pole/sector count from 3 to 12 with default 6; Wavefolder folds from 1 to 32; persistence from 0 to 10 seconds; bloom from 0 to 4; diagnostics; and quality telemetry.

  Continuous image-shaping values are modulation-eligible. Mode, timing-standard selection, quality, lifecycle commands, preset operations, and diagnostic routing are not. Every numeric image control has an explicit reset. Mode-specific values are remembered.
- **Output:** An atomic parameter snapshot applied at the next frame boundary.
- **Constraint:** Factory presets include Normal Raster, Classic S 60 Hz, S 180 Hz, H/V Collapse, Circle, Ellipse, Figure Eight, and at least one characteristic state for every experimental family. Presets never store source routing, host Mix/blend, enable state, framebuffer history, or resolved adaptive tier.

### Stage 7: Lifecycle, status, and recovery

- **Input:** Enable/bypass changes, Mix changes, mode/preset/source changes, resize/format/device changes, suspend/resume, GPU completion status, Panic, Reset, Clear, and Retry.
- **Logic:** Disable, host bypass, and Panic immediately pass through and clear temporal history. Mix zero keeps phase/history live for dry/wet performance. Mode, preset, source, resize, format, and device changes apply atomically at a frame boundary and clear history. Suspend/resume clears history and relocks to transport. Save/relaunch restores parameters but never framebuffer history. The visible per-stage Panic Bypass latches pass-through, preserves parameters/modulation, works while faulted, and requires explicit re-enable. Command-Shift-Escape invokes the same action on every Wobbulator stage; ARShader's existing Command-B and Escape Blackout mappings remain unchanged. Reset Beam restores safe fields and recenters coverage. Clear Persistence affects history only.
- **Output:** One non-color-only state: Active, Quality Reduced, Beam Off-screen, No Source, Faulted, Bypassed, or Unsupported, Bypassed. Beam Off-screen shows coverage 0 percent and Recenter Beam. Faulted states expose Retry.
- **Constraint:** A last complete image may cover at most one presented frame. After one resource-recreation attempt, latch pass-through rather than freezing moving video. An asynchronous command-buffer fault cannot claim same-frame recovery; it faults subsequent frames.

## 8. Worked example end-to-end

The operator drops Wobbulator into the master FX chain while a moving color source is live. The stage receives the mixer composite as its immediate upstream texture and loads Classic S 60 Hz at Amount +0.30. At the next frame boundary, the render snapshot selects 525/59.94 timing. Raster sampling assigns every active source coordinate a source-cell area, dwell time, beam time, and base-yoke momentum.

The S-coil current is evaluated at each sample's beam time. The finite solenoid field is summed with the base-yoke field, and the magnetic pusher traces each sample to the screen. The selected forward representation deposits the original source color into linear HDR. Compression and retrace add brightness; uncovered regions stay opaque black. Optional persistence and bloom run after deposition, then the host composites the wet result using its current Mix and blend mode.

The operator turns Amount through zero into negative polarity, attaches modulation to Rate, switches to Orbit Coil, and sweeps host Mix to zero. Phase and persistence keep running while the dry feed is visible, so the wet image is current when Mix returns. An extreme Orbit position sends all samples off-screen; the program output is physically correct black while the stage says Beam Off-screen, coverage 0 percent, and offers Recenter Beam. Pressing Command-Shift-Escape invokes Panic Bypass on every Wobbulator stage immediately, clears their histories, and restores dry pass-through without discarding parameters.

## 9. Tone constraints

- Use concrete video-synthesis language, not hype or fake laboratory precision.
- Use the public labels Radial Breathing, Orbit Coil, and Concentric Wave consistently.
- Present Historical, Physical, Physically Inspired, Hybrid, or Artistic classification in an info row or tooltip, not as clutter on the performance surface.
- Never imply source-level parity with Souther's private implementation.
- Keep rendered text at least 14 pixels equivalent.
- Status must use text and iconography, never color alone.
- Panic, bypass, presets, and primary controls require keyboard and VoiceOver access.
- Diagnostics remain monitor-only unless the operator explicitly routes them to program output.
- Use no em dashes in operator-facing copy or project documentation.

## 10. Success criteria

- [ ] Full Beam preserves source color, every visible branch after folds, additive retrace/caustic brightness, and opaque-black no-coverage areas for all historical and named experimental modes.
- [ ] Zero field is at or below 0.25 output-pixel RMS and 0.75-pixel maximum identity error; valid GPU endpoints are at or below 0.25-pixel RMS and 1.0-pixel maximum error versus the double-precision CPU oracle; relative momentum drift is at or below 0.00001; normalized divergence residual is at or below 0.001 for physical fields; factory presets produce zero numerically invalid samples.
- [ ] Integrated exposure stays within 2 percent across output resolution and quality tiers; major caustic centroids stay within 1 pixel at 1080p and 2 pixels at 4K; the symmetric mean distance between 95-percent-energy contours stays within 2 pixels at 1080p and 4 pixels at 4K.
- [ ] On this M5 Max, effect-only p95 GPU duration is at or below 4 ms at 1080p60 and 8 ms at 4K30/60 after warm-up and throughout a ten-minute sustained run; the full 4K60 chain remains within 16.67 ms p95; automatic quality uses hysteresis and never switches renderer or changes exposure outside tolerance.
- [ ] Existing ISF regression coverage remains green, and the staged native-app exercise passes source changes, rapid mode/preset recall, Mix sweeps, bypass/re-enable, extreme modulation, off-screen black, injected allocation and command-buffer faults, save/relaunch, Panic, Retry, keyboard access, VoiceOver labels, next-frame control response, and prepared switches without a black gap or runtime pipeline-compilation stall, and Command-Shift-Escape panic-all without colliding with Command-B or Escape Blackout.

## 11. Failure modes + fallbacks

| Failure mode | Fallback |
|---|---|
| M5 frame budget exceeded | Change sample/integration quality at a frame boundary with hysteresis and show Quality Reduced. Reuse the last complete image for at most one presented frame. If no validated tier resumes, pass through. |
| No representation meets the 1080p60 Phase 1 gate | Stop production implementation and renegotiate representation or visual scope before changing the host. |
| 1080p passes but 4K exceeds the 8 ms effect budget | Select a lower validated Full Beam quality at 4K or authorize a separately estimated optimization phase. Do not weaken visual tolerances silently. |
| Native stage initialization or synchronous encoding fails | Pass through immediately, keep the remaining FX chain live, and show the actionable failure. |
| Command buffer faults after submission | Observe completion status, mark the stage Faulted, attempt one resource rebuild, then pass through subsequent frames with Retry. Do not claim same-frame replacement. |
| A trajectory becomes non-finite, unstable, or leaves simulation bounds | Terminate and blank only that sample, increment the numerical-invalid counter, and prevent it from reaching accumulation. |
| Strong valid fields produce zero screen coverage | Render opaque black, show Beam Off-screen and coverage 0 percent, and offer Recenter Beam. Do not misclassify it as technical failure. |
| HDR values overflow or become non-finite | Scale exposure before accumulation, reject non-finite deposits, preserve finite HDR range for tone mapping, and expose the counter. |
| Source is unavailable or changes discontinuously | Pass the upstream texture unchanged while absent, show No Source, and clear temporal history before resuming. |
| Resize, pixel format, device state, suspend, or resume invalidates resources | Pass through during frame-boundary rebuild, clear temporal history, and resume only after resources are valid. |
| Persistence could resume old history | Apply the lifecycle table exactly: disable/Panic clears; Mix zero keeps live; discontinuities clear; save/relaunch never restores framebuffer history. |
| Unsupported pixel format or Metal capability | Show Unsupported, Bypassed and pass through. This M5 is the only device to qualify. |
| Panic is invoked while faulted | Execute host-side latched pass-through and clear temporal resources without waiting on the failed renderer. |

## 12. HITL checkpoints

| Trigger | Reviewer | Channel | SLA |
|---|---|---|---|
| Phase 1 representation, tolerance, and performance evidence | Operator plus Mechanic | Benchmark report and live M5 comparison | Before host backing work |
| Identity, H/V, Classic S 60 Hz, and S 180 Hz reference behavior | Operator plus Mechanic | Live ARShader comparison against historical fixtures | Before experimental modes |
| Basic/Advanced controls, status, Panic, source state, presets, and temporal lifecycle | Operator plus Client Success | Staged native-app exercise | Before finishing/release proof |
| Full named-mode evidence matrix and 4K sustained production-port run | Operator plus Mechanic and Client Success | Live ARShader plus recorded metrics | Before declaring complete |

## 13. External assets

- Current ARShader source tree, especially App/ARShader/FXStage.swift, App/ARShader/FXChain.swift, ShaderUnit, compositor, parameter/preset infrastructure, and existing XCTest/PixelGate fixtures.
- Cousin design at docs/superpowers/specs/2026-08-03-datamosh-node-design.md, used only for the shared native-stage abstraction.
- Research dossier: /Users/arsonrivvers/.claude/c-suite/reports/chief-of-staff/2026-08-03-paik-abe-wobbulator-arshader-research.md
- Gitignored local evidence at docs/arshader/ui-reference/paik-abe-wobbulator/: seven source videos, one labeled still, contact sheets, keyframes, five technical PDFs, text extracts, and SHA-256 manifest.
- This 40-GPU-core Apple M5 Max Mac with 128 GB memory.
- Apple Metal and system frameworks already available to the app.
- No runtime network access, external account, paid API, hosted service, scheduled job, or recurring cost.

## 14. Anti-scope

- No claim of exact equations, presets, or source parity with Eric Souther's private C++ operator.
- No drop-in ISF requirement and no inverse renderer in v1.
- No public plugin ABI, XPC process, third-party executable loading, or general node graph.
- No support or optimization work for another Mac, iPhone, or iPad.
- No calibrated physical units without a measured CRT and coil.
- No arbitrary user-authored coil geometry in v1.
- No second modulation or routing system inside the effect.
- No silent renderer switch, control clamp, preset rewrite, technical black frame, indefinite frozen frame, or diagnostic overlay on program output.
- No redistribution of Instagram media, unlicensed source, or local research captures.
