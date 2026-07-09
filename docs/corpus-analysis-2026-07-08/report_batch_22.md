All 48 files read in full (the extensionless `AR_RuttEtra_v03` was verified against `AR_RuttEtra_v03.fs` via diff — 4 changed lines, both covered). Full report follows as my final message, per the coordinator's instruction not to write a report file.

---

# Batch 22 Analysis Report — /Library/Graphics/ISF

## Coverage
- files_assigned: 48, files_read: 48, misses: none
- Note: `AR_RuttEtra_v03` (no extension) and `AR_RuttEtra_v03.fs` are near-duplicates; diff shows the extensionless one parameterizes loop bounds with `const int samples` while the .fs hardcodes literal `5`/`4` — a Metal-backend const-loop-bound workaround caught mid-application.

## Per family

### Family 1: AR_ReactionDiffusion_Gen v01–v13 (+ v10_dataloss_v01, v13_dataloss_v01/v02) — 16 files
**Purpose & visual identity**: Gray-Scott reaction-diffusion driven by live video; organic dots/mazes/coral/worms patterns that eat and grow over the input feed. Filter/generator hybrid (video input always present; `mixWithVideo`/`effectAmount` decide).

**Architecture**: Three distinct generations.
- v01, v06–v08, v10: single PERSISTENT `bufferA` + display pass; chemicals in RG, precomputed display value in B channel.
- v02–v05: **4-step ping-pong** (`bufferA→bufferB→bufferA→bufferB` + display), 4 sim iterations per frame for 4x speed without instability.
- v09, v11–v13: ping-pong x4 **plus a `bufferHold` capture pass** (6 passes) — a state snapshot buffer for freeze/recall performance moves.

**Techniques**:
- *Gray-Scott core*: 9-point Laplacian; two weighting schemes appear — v01's `(cardinal-4c)*0.5 + (diagonal-4c)*0.5` (non-standard, sums to unusual gain) vs v02+'s classic `card*0.2 + diag*0.05 - c` kernel. v05 exposes the kernel itself (`lapCard`, `lapDiag`, `lapGain`) as performable "alternate physics."
- *Video forcing, three routes* (v12+): `videoMode` selects feed-rate modulation (`f + drive*videoFeed`), direct B injection, or A suppression — three visually distinct ways video "burns into" the sim.
- *Luma shaping pipeline* (v09+): `luma → pow(luma, videoGamma) → smoothstep(threshold±softness) → mix(raw, shaped, videoShape)` — a continuously morphable linear-to-thresholded drive curve.
- *Stability governor* (v09+), the signature trick: a per-pixel saturation guard that damps the update where the Laplacian is violent:
  ```glsl
  float edge = abs(laplacian.x) + abs(laplacian.y);
  float satGuard = clamp(1.0 - edge * (1.0 - stability) * 0.06, 0.0, 1.0);
  chem = mix(val_c, chem, satGuard);
  ```
  plus `dt` and reaction gain both scaled by `mix(0.25→0.75, 1.0, stability)` — one knob trading liveliness against blowup.
- *Generalized reaction* (v07+): `reactGain * a * pow(max(b,0.0), bPow)` — exposing the nonlinearity exponent as a control; v09 adds a fast-path: `(bPow>1.95 && bPow<2.05) ? b*b : pow(...)`.
- *Simple/Advanced dual-control* (v01–v05): `simpleMode` bool remaps 4 perceptual macros (flowSpeed, textureAmt, tone, simpleIntensity) onto ~12 physics params via `mix()` chains, including a derived RGB palette (`mix(1.55,0.55,tone)` etc.).
- *Preset system with offset preservation* (v12–v13 `getFK`): presets set base f/k but user slider deltas from the canonical 0.055/0.062 are re-applied on top — sliders act as trims around any preset.
- *State capture* (v09+): `bufferHold` latches sim state on `captureState` event; display crossfades live vs held via `captureMix`/`showCapture` — a performable A/B morph between two sim states.
- *Freeze/single-step debugger* (v09+): `freezeSim` bool + `stepSim` event = pause and frame-advance the PDE, physics-lab style.
- *v13 macro conductor layer*: `macroMix` crossfades the entire manual parameter set toward two meta-knobs (`macroComplexity` → f/k, `macroEnergy` → dt/reactGain/videoFeed) — a "conductor" that overrides the lab.
- *dataloss variants*: performance-optimization remixes. v10_dataloss gates the video texture tap behind `if (videoFeed > 0.0)`; v13_dataloss_v01 gates all of `getVideoDrive` behind `if (vFeed > 0.0)` (commented "Gated: at vFeed==0..."); v13_dataloss_v02 additionally hardens dead-constant colorize values into new INPUTS (`coolColor` color picker, `chemicalAMix`) and adds a no-op event input `ui_dataloss_v02` labeled "🧪 DATALOSS REMIX" as a **version watermark in the UI** — inputs used as labels/section dividers.

**Control/UI design**: grows from 15 inputs (v01) to 40 (v13). Conventions: GROUP-numbered sections in v04/v05 (`"00 Video"`, `"01 Play"`, … `"08 Advanced Lab"`); **coarse/fine pairs** (`speedCoarse`+`speedFine` additive; `viewScaleCoarse*viewScaleFine`, `gridScaleCoarse*gridScaleFine` multiplicative); events for reset/inject/capture/step; long-type dropdowns with human labels ("Mitosis", "Coral", "Worms"); colorR/G/B triple 0–2 instead of color type (until dataloss_v02 introduces a color picker).

**Version evolution**: v01 monolithic simple/advanced RD filter → v02 pure generator with ping-pong x4, seeds, colorize modes → v03 merges both (video-driven live edition, adds hash-noise injection) → v04 "Live Lab": GROUP metadata, exposed kernel/nonlinearity/boundary/soft-clamp — maximal physics exposure → v05 same but with simple-mode shadow-variable rewrite (v04 wrote to input-named variables, which is illegal on some hosts — v05's `u_lapCard = lapCard; ... if (simpleMode) { u_lapCard = 0.20; }` block exists specifically because **ISF inputs are read-only uniforms**; comment "Local shadow variables for the read-only inputs") → v06–v08 retreat to a single-buffer simpler lab (v08 experiments with a substep loop and advective `flow` offset — abandoned after) → v09 adds ping-pong + hold + stability + freeze/step → v10 single-buffer regression w/ hold (simpler debug base) → v11 re-ping-pongs with `fract()` wrap boundary and duplicated stepFrom code → v12 factors `stepFromA/stepFromB`, adds fkPreset + videoMode + colorize modes → v13 adds patternZoom, diffRatio coupling (`dB = mix(diffuseB, diffuseA*diffRatio, diffRatioMix)`), macro conductor. The trajectory is oscillation between "expose everything" and "make it playable," converging on both simultaneously.

**Complexity tier**: 5 (v13: 6-pass ping-pong+hold simulation with conductor macros, preset trims, three forcing routes, stability governor). Early versions tier 3.

**Signature moves**: stability satGuard; capture/hold buffer crossfade; coarse×fine knob pairs; preset-plus-offset trims; macroMix conductor; read-only-uniform shadowing pattern; per-pass duplicated sampler functions (`sampleA`/`sampleB`/`stepFromA`/`stepFromB`) because buffers can't be passed as function args in ISF's GLSL.

**Rough edges**: v11 contains two fully duplicated ~40-line Laplacian blocks (later factored); v08's substep loop resamples the same buffer inside one pass (no actual sub-stepping — physics bug, abandoned); v10/v13 gridScale samples at non-pixel-aligned offsets producing filtered (not true grid-scaled) neighborhoods; v04→v05 read-only-uniform crash scar; dataloss branches show a separate "optimize for VDMX perf" workflow with commented gating.

### Family 2: AR_ReactionDiffusionFilter v01–v04, v04_xfer–v06_xfer — 7 files
**Purpose & visual identity**: Completely different RD lineage (credit "Port by ShaderSmith ISF Python") — a 3-channel RGB pseudo-reaction-diffusion where the *color channels react with each other*, plus a saturating "RGB blowout" post that pushes colors to gamut edges. Psychedelic, poster-like. Filter.

**Architecture**: single PERSISTENT `bufA` + final pass, all versions.

**Techniques**:
- *Cross-channel reaction* — the family signature: `color.rgb += reactionRate * (color.rgb*color.gbr - color.rgb*color.brg)` — swizzle-rotated channel products as the reaction term (a cyclic 3-species competition, like rock-paper-scissors dynamics in RGB).
- *RGB blowout*: project color away from a center point through matrix `blow`, then compute per-channel headroom and step exactly to the gamut boundary:
  ```glsl
  vec3 dir = blow * (col - cent);
  vec3 maxes = (step(vec3(0.0), dir) - col) / dir;
  float amount = min(maxes.x, min(maxes.y, maxes.z));
  col += dir * amount;
  ```
  (v04_xfer adds `+vec3(1e-6)` denominator guard against div-by-zero — a NaN scar fix).
- *Mass conservation nudge*: `float delta = 1.5 - dot(color.rgb, vec3(1.0)); color.rgb += 0.005*delta;` — pulls total "chemical mass" toward a target so the sim never dies or saturates; later parameterized as `tonePush` (target `mix(1.1,2.0,·)`, gain `mix(0.0,0.02,·)`).
- *Seeded procedural init*: FRAMEINDEX==0 block fills bufA with blocky RGB hash noise where `color.b = 1.0 - bm*r - (1-bm)*g` (anticorrelated B channel = instant reaction fuel).
- *Continuous blend-mode slider* (v04_xfer+): `blendSlide` 0–4 float; evaluates `blendEval(i0)` and `blendEval(i1)` and `mix`es — crossfading *between blend modes* (Overlay→Add→Multiply→Screen→SoftLight) as a single performable axis.
- *Frame-rate independence* (v06_xfer): reaction scaled by `TIMEDELTA * 60.0` with `max(TIMEDELTA, 0.0001)` first-frame guard.
- *Per-channel diffusion via color picker* (v06_xfer): `diffuse` becomes a `color` input so R/G/B decay rates differ → anisotropic color patterns; tone push becomes a rational soft-saturation `(c*(1+p))/(1+p*dot(c,1/3))`.

**Control/UI design**: 4 inputs (v01, near-port) → 16 (v06 "Final Cut"). Naming is expressive not physical: `seedChaos`, `kernelReach`, `camDrive`, `tonePush`, `blowoutPower`. v05_xfer "Corrected" comments mark every fixed line ("CORRECTED: effectAmount now controls..."). effectAmount is wired *organically into the sim* (scales reaction + tone push) as well as final dry/wet — the author's recurring "effectAmount should change behavior, not just crossfade" philosophy.

**Version evolution**: v01 raw port (hardcoded weights, fixed blowout matrix) → v02 parameterizes everything into 8 "expressive controls," makes blowout center procedural (`mix(cA,cB,fract(0.37+1.23*seedChaos+0.41*tonePush))`) → v03 adds 5 blend modes + blendAmount compositing → v04 retunes defaults for "immediate dynamic feedback" → v04_xfer converts blend enum to continuous slider, adds div-guard, `w=0` on FRAMEINDEX 0 (init-frame neighbor-tap guard) → v05_xfer master effectAmount woven through sim; SoftLight formula corrected; kernelReach curve squared → v06_xfer "Final Cut": color-typed per-channel diffusion, TIMEDELTA independence, parameterized blowout colors/sharpness. The `_xfer` suffix appears to mark the transfer-function/crossfade-capable line.

**Complexity tier**: 3 — single feedback buffer, but the blowout math and continuous blend slider are sophisticated.

**Signature moves**: gamut-edge blowout projection; swizzle cross-channel reaction; blend-mode crossfade slider; effectAmount woven into simulation dynamics; procedural blowout centers keyed off unrelated seeds.

**Rough edges**: v01–v03 sample bufA neighbors on frame 0 before init (fixed v04_xfer with `if (FRAMEINDEX==0) w=0.0`); un-guarded `/dir` division until v04_xfer; v06 default `seedDetail` 0.57 with MIN 0.1 makes the "pixel" grid sub-pixel (deliberate mush?).

### Family 3: AR_Robotmelt_terminator_v01 — 1 file
**Purpose & visual identity**: Misleading name — it's "fbm flow (ISF) — parametric": classic iq domain-warped FBM (`fbm(p + r(q(p)))`) where the warp is additionally steered by the *source video's* luminance gradient and RG channels. Chrome-liquid "terminator melt" over video. Filter (source drives, output is grayscale field).

**Architecture**: single pass, no buffers.

**Techniques**:
- *Video-driven flow field inside FBM octaves*: each octave does `p = lacunarity*p + fbmOffset; p += flowField(ouv);` — the flow (mix of `src.rg - 0.5` texture flow and screen-space luma gradient `normalize(vec2(r-c, u-c) + 1e-6)`, rotated by `flowRotate`, scaled `flowGain`) is injected per-octave, using a **global `vec2 ouv`** to smuggle the original UV into the nested fbm calls (GLSL no-closure workaround).
- Double domain warp with independent time rates (`qRateA/B`, `rScaleA/B`, `rRateA/B`) exposing iq's usually-hardcoded constants as 6 sliders.
- Output tone: `outGain * pow(max(f,0.0), outGamma) + outBias`.

**Control/UI design**: 16 floats, tightly grouped by function (fbm shape / flow / warp timing / output tone). No events, no bools.

**Version evolution**: single version.
**Complexity tier**: 2–3 (single pass but triple-nested warp with video coupling).
**Signature moves**: per-octave flow injection; global-variable UV smuggling; `normalize(grad + 1e-6)` NaN guard with comment "avoid NaN at flat regions".
**Rough edges**: filename vs LABEL mismatch (repurposed shell); `fbmOffset` added per-octave makes lacunarity and offset interact confusingly.

### Family 4: Rutt-Etra — AR_Rutt_mod_v01, AR_RuttEtra_V2, v03 (x2), v04, v05_Gridstyle, v06 — 7 files
**Purpose & visual identity**: Rutt-Etra video-synth emulation (luma → displaced scanlines), lineage from Akascape's Shadertoy DdXfRj. Filter.

**Architecture**: v03+ use the full 3-pass form: Pass 0 = **per-column luminance integral** (for each pixel, loop-sum all rows below: `for(i=0; i<gl_FragCoord.y; i++) screen += img.g/RENDERSIZE.y`) into a FLOAT PERSISTENT BufferA; Pass 1 = depth-stepped parallax lookup into that integral (TekF "Retro Parallax"-style: march `i=1..maxSteps`, scale centered UV by `depth/depthNorm`, break when `1-(col.y*col.y) < i/threshold`); Pass 2 = line extraction — quantize `floor(lines * lineDensity * RENDERSIZE.y)` at 5 vertical taps and emit brightness where consecutive quantized values jump (`n[i+1]-n[i] > 0.1`). AR_Rutt_mod_v01 is a single-pass reduction (line extraction only, no integral/parallax).

**Techniques**:
- *Scanline integral buffer*: O(height) per-pixel loop — brutally expensive but produces the cumulative-luminance "terrain" the parallax pass marches over. FLOAT:true is load-bearing (values exceed 1).
- *Quantized-jump line detection*: lines appear where the integer part of `lines*density*res` changes between neighboring rows — this is what draws Rutt-Etra's displaced raster.
- *effectAmount as algorithm stager* (v04): rather than crossfading output, effectAmount scales the integral limit (`limitY = pxy.y * mix(0.1,1.0,effectAmount)`), march step count, depth scale, anim rate, AND the final mix — the effect "assembles itself" as the knob rises.
- *Activation field* (v05_Gridstyle) — the standout: a spatial/temporal field replaces the scalar knob:
  ```glsl
  float sweep = fract(TIME*sweepDir);
  float band  = smoothstep(sweep-0.18, sweep+0.18, uv.y);
  vec2 cell   = floor(uv*vec2(32.0,18.0));
  float jitter= smoothstep(0.25,0.95,h21(cell*1.317+7.0));
  float a = clamp(mix(band*0.85,1.0,base)*mix(0.55,1.0,jitter*base),0.,1.);
  ```
  At partial effectAmount the effect materializes as a sweeping band with per-grid-cell jitter — "no output cross-fade" is stated in the DESCRIPTION as a design goal.
- *Branchless mode selection* (v04/v05): color modes selected via `m0..m3 = step()` products then `processed = m0*c0+m1*c1+m2*c2+m3*c3` — vector-ternary avoidance idiom.
- *Float-encoded enums*: `orientation01`, `accumChannelF`, `colorModeF`, `edgeClampF`, `invertF` are all floats 0–N instead of bool/long — deliberate "all controls as sliders" convention (stated in DESCRIPTION) so every parameter is automatable/interpolatable from the host.
- *Const-loop-bound + runtime break*: `for(int i=1;i<256;++i){ if(i>=mSteps) break; …}` (v04) — the canonical Metal-safe dynamic loop.

**Control/UI design**: v03 zero controls (hardcoded consts) → V2 six controls → v04/v05 24 sliders including tint triple, gamma/contrast/invert post block. `wrapUV` honors a clamp-vs-wrap edge policy slider.

**Version evolution**: Rutt_mod_v01 = single-pass "ported by RV OG BY AKASCAPE" with organic effectAmount → v03 = raw auto-converted Shadertoy with consts (the two v03 files: parameterized-loop vs literal-loop variants — Metal const-bound experimentation) → V2 = consts promoted to INPUTS → v06 = effectAmount properly integrated (displaced-vs-undisplaced UV lerp in the parallax pass + final mix; breakThreshold exposed) → v04 = full slider-ization + orientation + channel select + color modes + staged effectAmount → v05_Gridstyle = activation-field spatial staging. (Version numbers don't track chronology; v06 reads as intermediate between V2 and v04.)

**Complexity tier**: 4 (v04/v05) — 3-pass FLOAT pipeline with staged activation; v03 tier 2.

**Signature moves**: activation-field staging; effectAmount-as-algorithm-stager; all-sliders convention; luminance-integral terrain.

**Rough edges**: O(res.y) inner loop per pixel is a perf bomb at high res; `n[i]` stores a vec2 of a single value (vestigial from the original); v03.x duplicates; V2's `samples` const in a loop bound with `n[i+1].x - n[i].x` comparison on identical components; hardcoded Portland GPS-style magic offsets (`vec2(.5,.4)`).

### Family 5: AR_ryoji-rectangles_v01 — 1 file
**Purpose & visual identity**: Ryoji Ikeda-style strobing vertical line barcode generator — grid of tiles, each running 8 jittering vertical lines, gated by a BPM pulse. Pure generator, black/white.

**Architecture**: single pass, no buffers.

**Techniques**: per-tile deterministic randomness (`seed = dot(tileID, vec2(17.3,45.7))`); cycle-quantized re-randomization (`cycle = floor(tileTime/cycleLength)` feeds `hash31(fi + seed*100 + cycle*99.1)` so line layouts reshuffle every 2.5s, desynced per tile via hashed `tileOffset`); discrete position jumps (`jump = step(0.7, fract(sin((t+n.z)*13.7)*43758.5453))`) layered on sinusoidal sweep; **synthesized audio-reactivity**: `fakeAudio = mix(0.6,1.8,pulse)*ThicknessMul` where `pulse = step(phase, Duty)` from BPM + per-tile phase — a fake beat-follower with duty-cycle control, driving line thickness; final `step(0.5, colVal)` re-binarizes overlaps.

**Control/UI design**: 6 floats — TimeRate, GridX/Y, BPM, Duty, ThicknessMul. BPM as a first-class input (VJ-set tempo matching without audio routing).

**Version evolution**: single version.
**Complexity tier**: 2.
**Signature moves**: BPM/Duty fake-audio pulse; per-tile phase desync; cycle-hashed reshuffling.
**Rough edges**: `hash31`'s MOD3 constants standard; `numLines` fixed at 8; no aspect input beyond `p.x *= res.x/res.y`.

### Family 6: AR_SauronCam1_HallofMirrors — 1 file
**Purpose & visual identity**: "Visual Overdrive" (credit tomachi, converted by Arson Rivvers) — a violent webcam feedback shader: self-dividing buffer feedback with radial distortion, green-screen edge gating, hue tools. Hall-of-mirrors video meltdown. Filter with mouse interaction.

**Architecture**: 3 passes: BufferA (PERSISTENT FLOAT feedback core), BufferB (PERSISTENT FLOAT secondary latch), final additive composite `webcam + bufferA*mix + bufferB*mix`.

**Techniques**: division-based feedback `saturate(wcam / max(self - mod(fac,0.1), 0.0001))` — dividing camera by its own history (with a ±300 wide `saturate`) creates blown, posterized overdrive; radial zoom via `uv = uv*(1.0+facstr) - facstr/2.0` where facstr derives from both center distance and buffer energy `length(wcam)`; `FRAMEINDEX < 5 || uv at borders` reseed guard; iMouse as performance input (mouse Y gates which feedback law applies); `isgreen = smoothstep(edgeThresh, edgeThresh-0.1, 1.0 - dot(wcamsrc, vec4(0.1,1.0,0.1,0.0)))` computed but **unused** (dead green-screen path); `huecol()` hue function also **dead code**.

**Control/UI design**: 5 floats + point2D mouse; conversion added feedbackMix/distortStrength/edgeThresh/motionIntensity/hueShift over the original.
**Complexity tier**: 3.
**Signature moves**: divide-by-history feedback; energy-driven radial zoom; border-strip reseeding.
**Rough edges**: two dead functions (isgreen, huecol wired to nothing); hueShift input therefore inert; `mod(uv,1.0)` sampling everywhere instead of fract (identical, verbose); magic constants (0.499, 0.98 borders) untouched from source.

### Family 7: AR_SecurityOverlay v01–v10 — 10 files
**Purpose & visual identity**: CCTV/surveillance HUD filter — 7-segment timecodes, blinking REC, CAM ID, GPS DMS coordinates, frame counters, audio meters, over a VHS-degraded image. The most "designed" family: pure procedural UI typography in a fragment shader. Filter.

**Architecture**: all single-pass, no buffers — everything is analytic masks composited by `ui = max(ui, element)` accumulation.

**Techniques**:
- *7-segment font engine*: segment rects via `step()` products; glyphs as **bit-packed integers** (`getPattern`: 0→119, 1→36, … A–F for hex) decoded with `int(mod(float(p)/pow(2.,s),2.))` — GLSL-1.2-safe bit tests without bitwise ops. Extended to hex digits for byte readouts (v01–v03).
- *3x5 bitmap letter font*: `drawREC`, `drawSecTag`, `drawSyncLabel`, `drawBitmapLabel(type)` — hardcoded per-column y-tests producing "REC", "CAM", "SYNC", "TBC", "CH", N/W letters. v04's comment: "to avoid the 'bEC' 7-segment look" — the author hit 7-seg's alphabet limits and built a second font.
- *Anchored UI scaling*: `scaleAbout(p, anchor, s) = anchor + (p-anchor)/s` — per-corner inverse-transform of the query point so each HUD block scales about its own screen anchor (`scaleTL/TC/TR/BL/BR` per-block + master `uiScale`) — a genuine layout system.
- *VHS degradation stack* (evolves across versions): line-hashed horizontal jitter + occasional full "tear" pulses; scanline dimming; two-scale film noise; chroma crawl (opposed R/B UV offsets); v05's most complete `applyVHS`: luma hiss, chroma crawl on R/B directly, salt-and-pepper impulses with random sign, traveling horizontal dropout band (`bandY` hashed per ~1.4s, smoothstep-widthed), scanline comb, and a luma-dependent gamma (`pow(l,1.12+0.35*amt)/l` contrast pump).
- *UI-layer degradation separate from video degradation*: dropout cells, shimmer rows, bloom via re-thresholded hash-perturbed copies (`step(0.5, ui*(0.92+0.18*hash21(pixelPos+t)))`), v09/v10 interlace masking of the UI only (`ui *= mix(1.0, step(0.5,fract(y*0.5)), uiInterlaceAmt)`).
- *Fake telemetry*: GPS from hashed seed (`getGPS` in v05) or hardcoded Portland DMS (45°30'47"N 122°39'49"W — decimal comment included, v06+); FPS readout with hash jitter (`fpsBase - fpsJit`); drifting temperature `38 + int(sin(t*0.5)*2.0)`; SYNC label flicker `step(0.1, hash11(t*15.0))`; segmented audio ladder meters with per-channel hash wobble (v08–v09); motion-detect corner brackets flashing on hash triggers (v08); BPM Clock struct with beat counter + phase progress bar (v01–v02).
- *Host DATE uniform* for real calendar overlay (v02+).

**Control/UI design**: v01–v02 zero controls (pure look development) → v03 explodes to 17 (per-corner scales, margins, all degradation amounts) → v04 consolidates to 9 essentials → v05 re-adds gpsSeed → v06–v08 restore per-corner scales → v09–v10 drop per-corner scales for cleaner 10-input surface with `audioLevel` as a manually-drivable (or host-mapped) meter input. Labels on everything from v03 on.

**Version evolution**: v01 kitchen-sink first draft (blockText pseudo-labels — random blocky glyphs "reading as institutional UI") → v02 adds real DATE, drops some clutter → v03 parameterizes everything + anchored scaling system + degree/quote symbols for GPS → v04 rewrite: real bitmap REC font, compact 7-seg engine, cleaner dirt stack, GPS DMS layout → v05 adds seeded GPS generation, letter font N/S/E/W, best VHS stack → v06 SEC-7 branding tag, hardcoded-GPS-from-screenshot (comment cites decimal coords) → v07 adds SYNC flicker label → v08 peak feature count (motion brackets, hex readout, temp, level meter) → v09 normalization pass: unified `drawBitmapLabel(type)`, thickness-parameterized 7-seg (`drawDigit(..., thick)`), audio ladders, larger default margins → v10 final tightening ("Corrected stroke weight" comment), drops v09's extra widgets it deemed clutter. Clear arc: prototype → parameterize → typography quality → feature max → editorial reduction.

**Complexity tier**: 4 — single-pass but a complete procedural typography + layout + degradation system (v08–v10).

**Signature moves**: bit-packed glyph fonts without bitwise ops; scaleAbout anchored layout; separate degradation budgets for video vs UI; fake-plausible telemetry as aesthetic; editorial version arc.

**Rough edges**: drawSecTag/drawSyncLabel contain conditions like `(y==3&&x==0)` inside an `x==0` branch (redundant) and v08's `drawTempLabel` is a near-unreadable nested ternary that likely doesn't render the intended glyphs; v03's uiBloom computes a radius `r` then only uses ±1px offsets; duplicated timecode in two corners (v03) — intentional CCTV redundancy or copy-paste, unclear; scanlines input declared but unused in v04, v06–v08 (vestigial header).

### Family 8: AR_SeparationGlitch_v02 — 1 file
**Purpose & visual identity**: Voronoi-displacement separation glitch (credit "thedantheman (modified)") — image tears into displaced layers with grayscale intermediate, eased by exponential curves. Filter.

**Architecture**: single pass. **Broken as ISF**: samples via `texture(sTD2DInputs[0], p)` — TouchDesigner input syntax, and redeclares all inputs as `uniform float` (harmless but non-idiomatic). This file cannot run in an ISF host without replacing the three `texture(sTD2DInputs[0], …)` calls with `IMG_NORM_PIXEL(inputImage, …)` — a half-finished TouchDesigner port.

**Techniques**: three-scale voronoi displacement mixed into a displacement vector; exponential ease pair (`ease1` = symmetric exp ease with exposed exponent, `ease2 = 1-pow(2,-k*t)`); `gp = progress * effectStrength` global-progress compositing with smoothstep-banded branch blending; exposed grayscale weights (grayR/G/B) — even the luma dot product is performable.

**Control/UI design**: 18 inputs — the author's "expose every constant" pass applied to found code (voronoi scales/offsets, ease exponents, smoothstep knees).
**Complexity tier**: 2 (and non-functional in ISF).
**Rough edges**: entire sampler layer wrong for ISF; `random()`'s `mod(dt,3.14)` truncated-π idiom carried over.

### Family 9: ShaderConvert v01–v02 + ShaderImport_v01 — 3 files
**Purpose & visual identity**: Shadertoy conversion workbench. v01/v02: "Volumetric Box Feedback" — hundreds of animated boxes ray-intersected per pixel, two layers subtracted, edge-detected, fed into a self-warping trail buffer. ShaderImport: "Cloud In a Bottle" volumetric FBM cloud raymarcher with mouse orbit. Generators.

**Architecture**: v01/v02: 3 declared passes (BufferB non-persistent, BufferA non-persistent, BufferC PERSISTENT FLOAT — final pass renders-and-persists in one). ShaderImport: single pass wrapped in `pass0_mainImage(out vec4, in vec2)` Shadertoy-style shim.

**Techniques**:
- *Brute-force box field*: 400/900-iteration loops calling iq's `boxIntersection` analytic slab test per pixel, box sizes from `sin(...)^8` (three squarings) for spiky size distributions, categorical flattening via `if(sin(i) < -0.7) sz *= vec3(1,0.4,1)`.
- *Layer subtraction*: BufferA depth minus BufferB depth, `max(C, 0.)` — carves one box field out of the other.
- *Self-advecting trail*: gradient of the persistent buffer itself displaces its own history read:
  ```glsl
  vec2 g = vec2(dFdx(IMG_NORM_PIXEL(BufferC,uvn).x), dFdy(IMG_NORM_PIXEL(BufferC,uvn).x));
  vec4 prevFrame = IMG_NORM_PIXEL(BufferC, uvn - g*Distortion_Amt);
  C = mix(C*4., prevFrame, Feedback_Decay);
  ```
  — edges smear along their own gradients, a fluid-ish look for two lines. Comment documents the PERSISTENT=true previous-frame semantics.
- *v01→v02 conversion methodology in miniature*: identical code, but every magic number becomes a labeled INPUT (Time_Speed, Camera_Z, Geometry_Density, Edge_Threshold, Edge_Brightness, Distortion_Amt, Feedback_Decay) with comments "// Interactive X" at each replacement site, and the note "Loop counts must remain constant in older GLSL versions for safety."
- *ShaderImport*: converter-stamped **tanh polyfill** for GLSL<130 (`#if __VERSION__ < 130` float/vec2/3/4 overloads with ±10 clamp); mouse-conditional camera path (`if (mouse≈0) auto-orbit else spherical mouse orbit`); 8-octave 3D value-noise FBM volume with `max(min(fbm-0.2,0.2), length(p)-0.5)` bottle-shaped density clamp; directional-derivative lighting (`(volume(ro+light)-v)/length(light)`) tinted through `tanh(ld*vec3(2,2,4))`.

**Control/UI design**: v01 zero inputs (raw conversion) → v02 seven labeled inputs. ShaderImport keeps only Shadertoy's mouse as point2D.
**Version evolution**: the pair is a before/after snapshot of the author's standard "convert then parameterize" workflow.
**Complexity tier**: 3 (heavy compute, modest structure).
**Rough edges**: both v01/v02 declare 3 passes but code a 4th `else` branch (`C = BufferC*1.4`) that never executes — a dead "Image tab" pass from Shadertoy left in; 900-iteration box loop is a GPU furnace; ShaderImport's `vec4(mouse*RENDERSIZE, mouse*RENDERSIZE).z < 0.01` mouse test is a contorted iMouse.z (click-state) emulation that actually tests mouse.x.

## Batch synthesis

**Top 3 most sophisticated files**
1. **AR_ReactionDiffusion_Gen_v13.fs** — six-pass ping-pong Gray-Scott with hold-buffer state capture, freeze/single-step, preset-plus-trim f/k system, three video-forcing routes, shaped luma drive, per-pixel stability governor, diffusion-ratio coupling, and a macro conductor layer that crossfades the whole lab to two knobs. The most complete "simulation instrument" in the batch.
2. **AR_SecurityOverlay_v09/v10.fs** — a full procedural UI toolkit (two font systems, bit-packed glyphs, anchored per-corner layout scaling, widget library, separately-degraded UI layer) in one pass, arrived at through an include-everything-then-edit version arc.
3. **AR_RuttEtra_v05_Gridstyle.fs** — the activation-field concept: replacing dry/wet crossfade with a spatial/temporal computation-staging field (sweep band × per-cell jitter × macro base), explicitly documented in the header as "no output cross-fade."

**Recurring patterns / style fingerprints**
- `effectAmount` philosophy: never just a crossfade — it scales internal algorithm parameters (loop limits, reaction rates, displacement) so the effect *assembles* rather than fades (Rutt v04/v06, RDFilter v05/v06, Rutt_mod v01).
- Boilerplate hash trio: `hash11(p*0.1031...)`, `hash21` via `p3.yzx+33.33`, and the sin-dot 43758.5453 classic — all three coexist across families.
- `FRAMEINDEX < 2` (sims) or `== 0` (filters) init with seeded state, plus explicit reset events.
- Coarse/fine control pairs and float-encoded enums ("all controls as sliders") for host automatability.
- const-bound loops with `if (i>=limit) break;` and branchless step()-mask mode selection — vector-ternary and dynamic-loop Metal hazards systematically dodged.
- Version files as a lab notebook: near-duplicates preserved per revision; `_dataloss` and `_xfer` suffixes marking optimization/transfer branches; comments like "CORRECTED:", "Gated:", "Local shadow variables for the read-only inputs" documenting each fix; no-op event inputs used as UI version watermarks.
- Presets that respect user trims (offset-from-canonical re-application).

**Beyond standard ShaderToy fare**
- The stability satGuard (Laplacian-magnitude-gated update damping) — a homegrown numerical-stability control I've not seen in published Gray-Scott shaders.
- State capture/hold buffer with performable crossfade between live and frozen simulation states.
- The activation-field staging concept (spatially materializing effects).
- Bit-packed 7-seg + 3x5 bitmap font engines with anchored multi-block layout scaling, all bitwise-op-free for GLSL 1.2.
- Blend-mode *crossfading* as a continuous performable axis.
- The gamut-edge "blowout" projection (step exactly to the RGB cube boundary along a matrix-warped direction).
- Negative knowledge preserved in-file: the v04→v05 read-only-uniform shadowing scar, the TouchDesigner sampler stub (SeparationGlitch), the dead 4th pass in the Shadertoy conversions, and the two RuttEtra_v03 variants capturing const-loop-bound experimentation.
