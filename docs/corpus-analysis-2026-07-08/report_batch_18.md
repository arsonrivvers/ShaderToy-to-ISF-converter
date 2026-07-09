All 48 files are now fully read (the KaliedoDepth result was dropped from an earlier parallel batch; re-read individually and confirmed — it is a byte-level near-duplicate of KaleidoTunnelVision_v01's code). Full report follows.

---

# Batch 18 Analysis Report — /Library/Graphics/ISF (Arson Rivvers)

## Coverage
- files_assigned: 48, files_read: 48, misses: none
- Notes: `ArsonRivvers_Kick_Neon_alt` (no extension) and `ArsonRivvers_Kick_Neon_alt.fs` verified byte-identical (`cmp` = IDENTICAL, both 17,558 bytes). `ArsonRivvers_KaliedoDepth.fs` contains the same code as `ArsonRivvers_KaleidoTunnelVision_v01.fs` (duplicate under a second name).

---

## Family 1: AR_Horizontal-Line-Grid v3–v6 (4 files) — "Chaotic Grid / Magazine Layout"

**Purpose & visual identity**: Filter. Recursively re-tiles the input image into a chaotic grid of cells with per-cell aspect-ratio morphing, random offsets, and golden-ratio subdivisions — a "broken magazine layout" / Mondrian-glitch look.

**Architecture**: v3/v4 single-pass, no buffers. v5 adds 2 passes (`lastFrame` PERSISTENT full-res + finalOutput) for trails/motion blur. v6 is a complete rewrite: single pass, layer/column layout engine.

**Techniques**:
- *Iterated compound grid warp*: `applyCompoundGrid` runs up to 30 times, each iteration re-gridding UV at `gridComplex * (1 + i/repetitions)` — recursive domain repetition where each level's cell size drifts, producing non-self-similar fragmentation. Classic host-safe loop: `for(int i=0;i<30;++i){ if(float(i)>=repetitions) break; ... }`.
- *Animated aspect-ratio cycling*: `getCurrentAspectRatio` hashes cellPos into a phase, then `mod(phase,3)` cross-fades between three fixed ratios (1/3, 2/3, 5/4) — cells continuously "breathe" between print-layout proportions.
- *Golden-ratio recursive subdivision* (`applyRecursiveSubdivisions`): per level, splits cells at φ-derived ratios (v5 explicitly `phi=1.61803398875; ratio1=1/phi`), alternating H/V splits per level, with `smoothstep(level, level+1, subdivisionLevels)` so the *subdivision count itself* is a continuous slider.
- *Identity-preserving gate* (v4+): the workaround for "effect at 0 must be bypass":
  ```glsl
  float influence = max(step(0.0001, distortionStrength), step(0.0001, chaosFactor));
  return mix(uv, transformed_uv, influence);
  ```
- *Cell-front morph transition* (v5): `gridMorphPattern` makes cells activate center-outward with per-cell φ-hashed delays — the effect "washes in" as a geometric wave rather than a global crossfade.
- *Velocity motion blur* (v5): 6-tap blur along `(loc - original_loc)` — the warp displacement vector reused as a blur direction.
- *Layout struct engine* (v6): GLSL `struct LayerSetup {count,h1,h2,h3}` / `ColSetup` with `buildLayerSetup`, `getLayerID`, `mapToLocalCol`/`remapFromLocalCol` — a tiny declarative layout system inside a shader; column widths mix from uniform thirds to golden (0.618/0.382/0) via one `goldenRatioMix` slider; 3-layer heights wave-morph over time.
- v6 also swaps the cheap `rand` for a real 2D simplex noise (`simplexNoise2D`) and 3D hash for per-cell scale/flip/zoom.

**Control/UI design**: 8–10 float inputs, camelCase (`gridComplexity`, `chaosFactor`, `organicDistortion`). `effectAmount` appears in v5/v6 as a global dry/wet master (with `LABEL`). v6 renames everything to `*Slider` (`zoomSlider`, `seedSlider`) — all normalized 0–1, layout decided internally (performance-mapping thinking). `randomSeed` 0–100 float as variation dial.

**Version evolution**: v3 baseline (has final `randomPaddedZoomedPositionWithSeed` zoom). v4 removes the global zoom, adds `animationSpeed`, adds the influence bypass gate (fixing "slider at 0 still distorts"). v5 adds feedback trails + motion blur + geometric morph-in transitions and golden-ratio subdivisions — the "make it performable" rev. v6 abandons the recursive grid for a structured magazine layout engine with per-cell zoom (per the DESCRIPTION, deliberately "removes the final global zoom and randomizes per-cell zoom"). Trajectory: procedural chaos → controllable, performable, art-directed layout.

**Complexity tier**: 4 (v5/v6) — multi-system single file with layout structs, morph choreography, and feedback.

**Signature moves**: φ as a compositional constant; per-cell transforms in local UV then remap; continuous-integer sliders via floor/ceil+smoothstep; center-out activation waves.

**Rough edges**: v3's `randomPaddedZoomedPositionWithSeed` dropped in v4 (dead direction); v6 credit line still reads "modifications by [Your Name]" (template leftover); v5 motion blur samples `inputImage` not the warped buffer so the trail pass and blur interact only loosely.

---

## Family 2: AR_HyperTesseract v01, v02, v03, v03_dataloss_v01, v03_dataloss_v02 (5 files) — 4D raymarched voxel-data filter

**Purpose & visual identity**: Filter (versioned from an earlier generator: "V17.9.6-FILTER… input image drives voxel data"). Raymarched tesseract (4D hypercube) whose surface is carved by a "data voxel" field driven by input-image luma, run through an edge-detect + melting feedback loop and a VHS/chromatic-aberration finish. Neon-teal wireframe-glow aesthetic.

**Architecture**: 3 passes — `raymarch_core` (FLOAT, non-persistent, NEAREST filtering), `feedback_loop` (PERSISTENT FLOAT NEAREST), final post pass. v01 mislabels pass count (2 declared, main() has 3 branches — fixed in v02: "Corrected Pass Indexing"). NEAREST MIN/MAG on FLOAT buffers is deliberate for crisp voxel/pixel feedback.

**Techniques**:
- *4D SDF*: `sdTesseract(vec4 p, s, r)` = 4D rounded-box distance; point promoted via `vec4(p,0.0) * rot4D(t)` where `rot4D` rotates in the XW plane — the "4D morph" is a single plane rotation exposed as `Hyper_Speed`.
- *SDF booleans as performance modes*: `opBoolean` gives AND (`max`), OR (`min`), and XOR as a shell: `abs(d1-d2) - thickness` between two tesseracts rotating at different speeds ("Metric Interference").
- *Hamming-metric space glitch* (standout): replaces Euclidean length with bit-count distance:
  ```glsl
  vec3 ip = floor(abs(p) * 16.0);
  float ham = (popcount(ip.x)+popcount(ip.y)+popcount(ip.z)) * 0.15;
  p = normalize(p) * mix(length(p), ham, activeMetric);
  ```
  `popcount` implemented as an 8-iteration mod-2 loop (no bitwise ops — GLSL-ES safe).
- *Voxel data field*: 3D XOR parity texture (`mod(ix+iy+iz,2)`) masked by a hashed existence probability with a "Hasse gradient" (vertical sedimentation `smoothstep(-1.5,1.5,p.y+sin(t))`), thresholded by `voxel_density` with `Logic_Fuzz` softness; the field *subtracts from the SDF* (`geo -= voxelState(...) * depth`) so data literally carves the geometry.
- *Filter conversion*: `sampleInput` projects the 3D hit position to UV (XZ/XY/YZ planar or spherical equirect via `atan/asin`) and thresholds luma (`Input_Threshold/Softness`, plus `Input_Continuous` to mix binary→continuous carve). `Input_Object_Space` bool picks pre-/post-rotation coordinates (v02+), using a `g_p_prerot` global captured inside `map()`.
- *Time quantization*: `mix(rawTime, floor(rawTime), Quantize_Motion)` — continuous↔stepped data flow on one slider.
- *Chrono-logic*: `binaryClock(freq) = mod(floor(TIME*freq),2.0)`; ENTROPY macro gates glitch through `1.0 - (binaryClock(8.)*binaryClock(2.))` — rhythmic AND-clock glitching.
- *Derivative-flow feedback ("melt")*: v01/v02 displace the feedback lookup along `dFdx/dFdy` of the previous frame; v03 replaces it with a real 4-tap gradient over a 2px neighborhood after realizing dFdx of a snapped UV zeroes out (comment: "No dFdx/snapUV interaction that zeroes out").
- *Inverted physics feedback*: `Feedback_Polarity` runs the whole accumulate/decay loop on `1.0 - C` ("energy" domain) then re-inverts — trails of darkness instead of light.
- *Bayer 4×4 ordered dither* (explicit 16-entry `M[16]` array), bit-depth crush `floor(col*steps)/steps`, res-crush UV quantization, polynomial-falloff chromatic aberration (`pow(dot(center,center), curve)`), scanlines, `snapUV` (floor+0.5 pixel-center) forcing NN sampling everywhere.
- *MACRO conductors*: `MACRO_ENTROPY / MACRO_HYPER / MACRO_VHS` each additively boost 4–6 internal parameters (`activeX = baseX + MACRO*k`) — one-knob scene morphs.

**Control/UI design**: The most designed panel in the batch: ~50 inputs, namespaced labels acting as section headers — `"🔥 MACRO: ENTROPY"`, `"Input:"`, `"Form:"`, `"Space:"`, `"Data:"`, `"Glitch:"`, `"Cam:"`, `"Light:"`, `"Retro:"`, `"FB:"`, `"Final:"` — plus a `Force_Reset` event labeled `"🔴 --- MACRO RESET ---"` (emoji + dashes as a visual divider in the host UI). `long` dropdowns with LABELS for logic mode / mirror mode / projection. Bool switches for polarity/object-space.

**Version evolution** (explicitly versioned in DESCRIPTION strings, credits "Arson Rivvers + Gemini Hybrid + Claude" — a documented multi-LLM workflow):
- v01 (V17.9.6): filter conversion of the generator; broken pass indexing; carve depth tied to voxel size; dead `calcNormal` tetrahedral function (unused); unused `mod_*` globals.
- v02 (V18.0.1): pass indexing fixed (explicit `final_output` target); 4 projection modes + object-space mapping; smooth Seed folded into hash "so scrubbing is smooth rather than integer-cell quantized"; raymarcher hit test `abs(d)<0.001` (handles inside-surface after carving).
- v03 (V18.1.0 "Carve Authority + Real Flow + Shaded Geometry"): carve strength untied from voxel grid (`Voxel_Depth * Base_Size * 0.5`); real Lambert lighting with central-difference normals + `Light_Amount`; FOV made a true barrel/pinch (`uv*(1+FOV*dot(uv,uv)*0.3)`) separate from zoom; feedback rebuilt as additive-with-decay (`clamp(C + prev*Decay, 0, Clamp)` with decay 0→no trails, 1→clamped runaway); exposure gain applied *before* quantize "so the feedback clamp actually has room to work"; `MAX_FOLDS=7` const bound with runtime break; loop-invariant `rot2D(t*0.13)` lifted out.
- dataloss_v01: same as v03 but lighting *gated* (`if (Light_Amount > 0.0)`) to skip getNormal's 6 map() evals — pure perf rev.
- dataloss_v02: adds a "🧪 DATALOSS REMIX" event marker input plus `Light_Yaw/Light_Pitch` (degrees→direction with defaults reproducing the old hard-coded `vec3(0.7,0.5,-0.5)`), `Ambient_Floor`, `Scanline_Amount` — hard-coded constants promoted to performable params, back-compatible defaults.

**Complexity tier**: 5 — raymarcher + carving data field + persistent feedback physics + post chain + macro conductor layer, with a documented engineering changelog.

**Signature moves**: macro knobs additively driving many `active*` params; data-as-geometry (luma carves SDF); Hamming metric; binary-clock rhythm gating; NEAREST+snapUV feedback discipline; inverted-energy feedback; promoting magic numbers to "Remix" params with defaults equal to old constants.

**Rough edges**: v01's dead `calcNormal` + unused `mod_*` globals; comment in v02 claims a "Safety clamp" the code doesn't actually implement; `Feedback_Decay` MAX 1.01 (intentional overdrive) is a trap for hosts that randomize; ISF has no header includes so the entire ~350-line prelude is copy-pasted across all 5 files.

---

## Family 3: ArsonRivvers_ImpoShapeDistortion.fs (1 file) — broken hybrid

**Purpose**: Header describes a figure-eight-knot + torus warp with feedback (identical JSON to megaTorusWarper), but the body is the fractalKaleidoscope 10-shape engine referencing uniforms (`distortionMix`, `rotationSpeed`, `zoomSpeed`, `complexity`, `symmetry`, `shape`) that are **not declared in the header** — the file cannot compile as-is. It also declares `PERSISTENT_BUFFERS`+2 passes that main() ignores.

**Architecture/Techniques**: The body is the same MAX_ITERATIONS=20 / 10-shape kaleidoscope core as KaliedoClassic (see Family 5), including the Möbius-like shape 8 (`p*cosh(b)+cross(up,p)*sinh(b)` over `dot(p,p)*sinh(b)+cosh(b)`).

**Complexity tier**: 2 (as an artifact; the intended engine is tier 3).

**Rough edges / negative knowledge**: This is a header-transplant accident — evidence the author edits by pasting JSON headers between files; a generator/skill should validate INPUT names against used identifiers.

---

## Family 4: Kaleido Tunnel/Distortion Vision (7 files: Kaleidocam_HallofMirrors_1, KaleidoDistortionVision_v01, KaleidoMegaDistortionVision_v01/v02, KaleidoTunnelVision_v01, KaleidoDistortionInfiniteTunnelVision_v02, KaliedoDepth)

**Purpose & visual identity**: Filters. Camera/video fed through iterated fold-rotate-scale "fractal kaleidoscope" transforms of the ray direction, projected back to UV — infinite mirrored tunnel / hall-of-mirrors on live input.

**Architecture**: All single-pass, no buffers.

**Techniques**:
- *Core IFS iteration* (shared by all): `p=abs(p); p.xy*=rotate(PI/symmetry); p.xz*=rotate(PI/symmetry); p=rotate3D(p, 0.1sin(t/2), 0.1cos(t/2)); p=2.0*p-1.0;` — fold, wedge-rotate in two planes, wobble, expand.
- *Everything-through-mix bypass*: each op wrapped as `p = mix(p, op(p), effectStrength)` so one slider continuously interpolates from identity to full fractal — the author's signature dry/wet-at-the-math-level pattern.
- *Fractional iteration counts*: compute the transform at `floor(complexity)` and `ceil(complexity)` iterations and `mix(..., fract)` — a continuous "iteration" slider (appears here first, becomes standard in Family 5).
- *Reflection sampling*: `reflect(rd, transformedCoord)` → `.xy*0.5+0.5` → `fract()` as the distorted UV (MegaDistortion v02); v01 instead converts reflection to a *delta* from originalUV so distortionMix scales a displacement, not a crossfade of two unrelated mappings — a real usability fix.
- *Fake AO*: `ambientOcclusion` marches 5 growing steps along the pseudo-normal accumulating `(scale - d)` — not physically meaningful but adds shading depth cheaply.
- *Seamless Z-loop* (InfiniteTunnel v02): `p.z = mod(p.z, loopLength)` inside the iteration for an endless tunnel; camera `ro=vec3(0,0,-time*tunnelSpeed)`.
- *Wave distortion overlay*: `sin(uv.y*10+t)*waveStrength` added to the distorted UV (Mega family).
- *Hall-of-mirrors iterative zoom* (Kaleidocam, auto-converted Shadertoy): per loop `uv*=2; uv-=1; uv=abs(uv);` then `color = (cos(abs(color - sample)*TAU*cosStr)+1)*0.5` — cosine color-folding against recursive samples; finished with YIQ-matrix `hueShift` and luma-lerp saturation.

**Control/UI**: 6–10 floats; consistent vocabulary emerges: `rotationSpeed, zoomSpeed, symmetry (3–12), complexity (1–20), distortionStrength, distortionMix, effectStrength`. Distinction the author converges on: *Strength* = amplitude of displacement, *Mix* = dry/wet.

**Version evolution**: Kaleidocam (raw Shadertoy convert with `iChannel0` naming) → DistortionVision v01 (mix-gated everything) → MegaDistortion v01/v02 (AO + lighting + wave; v01 fixes v02's corner-pivot dry/wet by blending distortion deltas) → TunnelVision/KaliedoDepth (simplified, tunnelDepth removed) → InfiniteTunnel v02 (mod-z looping, `zoom=2.0+zoomSpeed*time`). This family is the incubator for the KaliedoClassic engine.

**Complexity tier**: 2–3.

**Signature moves**: mix-everything identity morph; floor/ceil iteration blending; reflection-vector UV lookup.

**Rough edges**: `zoom = 1 + zoomSpeed*TIME` grows unbounded (drift over a long set — fixed later in Family 5 with `1-exp(-t)` bounded zoom); KaliedoDepth is a dead-name duplicate; lighting from `dot(normal, +z)` is arbitrary but cheap.

---

## Family 5: ArsonRivvers_KaliedoClassic + v2–v10 (10 files) — the flagship kaleidoscope instrument

**Purpose & visual identity**: Filter. The Family-4 engine matured into a 10-algorithm morphable kaleidoscope instrument: two shape slots (DJ crossfade), sequence timeline, smooth symmetry/complexity, and eventually host-independent parameter easing via 1×1 persistent state buffers.

**Architecture**: base–v6: single pass. v7: 2 persistent 1×1 FLOAT buffers (`_metaBuf` time, `_shapePhaseBuf`) + main. v8/v10: **5–6 passes** — `_metaBuf`, `_shapePhaseBuf`, `_complexityBuf`, `_symmetryBuf` (v10 adds `_distortBuf`), all PERSISTENT FLOAT 1×1, plus final render. This is scalar state memory implemented as one-pixel textures — a full parameter-smoothing engine inside ISF. v9 is a TouchDesigner port (see below).

**Techniques**:
- *10-shape algorithm bank* inside the IFS loop: (1) classic fold-rotate-scale, (2) counter-rotated 1.5x−0.5, (3) polar spiral with radial warp/breathing, (4) time-rotating scale, (5) `q*q-1` quadratic (clamped), (6) `q*q*q-0.8` cubic (pre/post clamped), (7) sin-warp `sin(q*symmetry*0.5)*modulation`, (8) hyperbolic Möbius-style `num/denom` with `sinh/cosh` and denominator guard, (9) twist, (10) additive sin-jitter. Every shape is mix-gated by eased distortion.
- *Stability engineering* (v2 onward): per-shape `clamp(p,-2..8)` pre/post, global `p=clamp(p,-8.0,8.0)` every iteration ("prevent NaNs and explosive growth"), denominator guard `denom = (abs(denom)<1e-3) ? ±1e-3 : denom`, safe projection `z=max(abs(z),1e-3)*sign(z); z=max(z,1e-2)`.
- *mirrorRepeat*: `abs(fract(t)-0.5)*2.0` — seamless mirrored tiling replacing `fract()` to kill visible seams.
- *Bounded zoom*: `zoom = mix(1.0, 3.0, 1.0 - exp(-TIME*zoomSpeed))` — replaces the unbounded drift from Family 4.
- *Aspect-correct dry/wet*: converts both original and warped UVs to centered aspect-corrected space, blends there, converts back — "Blend in centered space to avoid corner pivot".
- *Custom GLSL-compat helpers*: `round_compat`, `ease01(t)=t*t*(3-2t)`, `oneMinusExp`, `sinh/cosh` polyfills.
- *Dual-axis smooth quantized params*: symmetry blends between integer wedge counts sym0/sym1 with eased weight; complexity blends floor/ceil iterations — up to **8 kaleidoscope evaluations per pixel** (2 shapes × 2 symmetries × 2 iteration counts), with three tiers of `<0.001 / >0.999` endpoint guards to skip unneeded evaluations.
- *Frame-rate-independent parameter easing* (v7+): pass 0 stores TIME (v8 stores current+previous in .r/.g); easing passes compute `dt = TIME - lastTime`, then `next = mix(prev, target, 1-exp(-dt/easeSeconds))` — proper exponential smoothing toward the UI value, persistent across frames. First-frame detection via `(FRAMEINDEX==0) || !(buf.a > 0.5)` (alpha as an initialized flag — a FRAMEINDEX<2-style init idiom generalized).
- *Shuffled sequence* (v5): multiplicative-permutation shape order — `pickA` chooses a ∈ {1,3,7,9} ("coprime with 10"), `permIndex = (a*i + b) mod 10` — guaranteed full permutation of the 10 shapes from one seed; `autoSequence` walks it on a time base; `hash11` PCG-style float hash.
- *DJ vs Sequence modes* (v6+): `shapeMode` long — either A/B crossfade (`shape`, `shapeB`, `shapeMix`) or one slider sweeping all 10 shapes (`shapeMix*9+1` timeline), with `wrapSequence` bool (9→0 wraparound) in v8+.
- *Trig hoisting*: `s02,c02,s03,c03,s05,c05` precomputed once and threaded through as function args — deliberate per-pixel trig budget management.

**Control/UI design**: stable camelCase vocabulary; `long` dropdowns with LABELS/VALUES for shapes and modes; per-parameter ease times (`easeSeconds`, `easeComplexity`, `easeSymmetry`, `easeDistortion`); ease=0 means "raw UI value" (each consumer checks `(easeX > 0.0001) ? eased : direct`). Early-out full bypass when `distortionMix ≤ 0.0001`.

**Version evolution** (a textbook learning trajectory):
- base: single shape param, unclamped shapes 5/6 (`p*p-1`, `p*p*p-1` — explodes), fract projection.
- v2: shapeB+shapeMix crossfade, clamps everywhere, mirrorRepeat, bounded zoom, input-aspect from `IMG_SIZE(inputImage)`, wet/dry, centerOffset point2D, symmetrySnap.
- v3: smooth symmetry (floor/next blend) + `symmetryMode` Smooth/Quantized.
- v4: dual-symmetry × dual-iteration full blend matrix, endpoint perf guards, centered-space dry/wet, early-out bypass, full-frame geometry (drops per-ray mix).
- v5: autoSequence + shuffleSeed + coprime permutation + `stepSeconds`; host-button conventions (`shuffleNow`, `resetOrder` as bools).
- v6: DJ/Sequence mode switch (simpler than v5's shuffle; a step back in features, forward in usability).
- v7: **persistent 1×1 state buffers** appear; eased shape phase (0..9 continuous) replaces discrete A/B.
- v8: easing generalized to complexity & symmetry (separate buffers + ease times); wrapSequence; enhanced shapes 3 (multi-layer spiral w/ breathe) and 7 (stabilized sin-warp); the huge branch tree of endpoint guards.
- v9: **TouchDesigner port** of v8 — `#define _metaBuf sTD2DInputs[1]`, `textureSize()` fallbacks for `IMG_SIZE/IMG_PIXEL/IMG_NORM_PIXEL` behind `#ifndef HAS_*` guards, `tdUv()`; shape 7 rewritten again (per-axis waves + length-based rotation).
- v10 (lowercase `kaliedoClassic_v10`): consolidation — v8's engine rewritten compactly (dense one-line style), adds `_distortBuf` easing for distortionMix, drops v9's TD shims. The "final" performer build.

**Complexity tier**: 5 (v8/v10) — a parameter-state machine plus an 8-way blended IFS renderer; base is tier 2.

**Signature moves**: 1×1 persistent buffers as scalar memory with dt-correct exponential easing; alpha-channel "initialized" flag; coprime permutation sequencing; endpoint-guarded blend matrices; everything continuously morphable (shapes, symmetry, iterations, all sliders).

**Rough edges**: v2 has both `symmetrySnap` and smooth logic ORed confusingly (`if (symmetryMode==1 || symmetrySnap)` in v3 makes snap always win if left true — default true!); v9's TD defines conflict with ISF (file can't run in both hosts, and `_metaBuf` samples indices that assume a specific TD wiring); massive per-pixel cost at mid-blend (8 IFS evals × 20 iterations); code duplication across the a/b/sym branches is enormous (no functions over the blend matrix).

---

## Family 6: Kick / Depth-Aware Performance Effects (12 files: KickEffects, KickEffects-2, Kick_GrainBurst_v1, Kick_Neon, Kick_Neon_2, Kick_Neon_3, Kick_Neon_4, Kick_Neon_4_DarkGrain, Kick_Neon_4_fluid, Kick_Neon_4_Freeze, Kick_Neon_alt ×2)

**Purpose & visual identity**: Filters designed as *momentary hit effects* — a slider (typically MIDI/audio mapped) punched on the kick drum. Most take a second `depthMap` image input (black=near, white=far) and scale everything by nearness. Neon edge outlines, spectral color trails, grain bursts, ghost decay.

**Architecture**: All multi-pass persistent-buffer systems: typically 2–3 PERSISTENT FLOAT buffers (`effectBuffer`/`trailBuffer`/`ghostBuffer`, or `spectralBuffer`/`flowBuffer`/`echoBuffer`, or `distortBuffer`/`grainBuffer`/`decayBuffer`) + `outputBuffer` composite. Legacy `PERSISTENT_BUFFERS` array + PASSES both declared (older ISF idiom).

**Techniques**:
- *Depth-scaled everything*: the house pattern is `effect * (1.0 - depth)` — near objects glitch/glow harder; e.g. glitch intensity `mix(NEAR_GLITCH_INTENSITY, FAR_GLITCH_INTENSITY, smoothstep(TH-δ, TH+δ, depth))` (GrainBurst).
- *Punch envelope*: `smoothPunch(x) = pow(smoothstep(0.0,0.1,x),2.0)*2.0` — slider shaped so any nonzero hit slams to full; earlier version had a bug `* (1.0 + PUNCH_FACTOR * exp(-TIME*4.0))` (decays from *shader load*, not from the hit — TIME is global), fixed in KickEffects-2 ("fixed punch & unified decay" in the DESCRIPTION).
- *Trail state machine*: PASS0 accumulates effect (`max(current, prev*0.98)` for latch-brightest, or additive), PASS1 trail decays (`prev*TRAIL_DECAY` with motion-based dynamic decay), PASS2 ghost with swirl-displaced resample + chromatic aberration, final composite. Release behavior is explicitly designed: when intensity=0, buffers fade via `GHOST_FADE_SPEED` and get eaten by animated Voronoi fragmentation (`trailMixed *= mix(1.0, pow(voronoi,3.0), 0.8)`) — trails *crumble* rather than fade.
- *Depth-edge neon outlines*: 3×3 neighborhood sum of `length(colorDiff) + abs(depthDiff)*2 + gradientMag*0.5`, smoothstepped, pulsed by `sin(TIME*PULSE + outline*10)`, colored by a 6-color cycling palette where near/far get palette entries 3 apart: `mix(farColor, blendedColor, 1.0 - depth)` — automatic fg/bg color separation from the depth map.
- *Cycling neon palettes as #defines*: `COLOR_1..COLOR_6` magenta/purple/cyan/green/orange/violet; piecewise mix chains (no arrays — GLSL-ES constraint).
- *Rotated multi-octave Voronoi grain*: `advancedGrain` = 4 octaves of animated Voronoi (`o = 0.5+0.5*sin(TIME*0.5 + 6.2831*o)`) with per-octave UV rotation — organic shimmering grain used for glow modulation, turbulence, and dissolves.
- *Freeze/stutter* (Neon_4_DarkGrain / Kick_Neon_3): `stutterTime = floor(TIME*RATE)/RATE; effectTime = mix(TIME, stutterTime, freezeFactor)` where `freezeFactor = smoothstep(0.5,1.0,intensity)` — top half of the slider freezes time; frozen state inverts luma and floods with `spectrumColor * NEON_INTENSITY * invertedLum` (dark areas become brightest — "invert physics" again).
- *Flow-field trails* (Spectral Echo variants): `computeFlowField` = 3 octaves of crystal-noise-directed unit vectors; previous spectral buffer resampled at `uv - flow*(1-depth)*2*intensity` — depth-weighted advection.
- *Intensity response curve input* (Kick_Neon_3): `curveIntensity(x)=pow(x, intensityCurve)` with a user slider 0.1–4.0 — mapping-curve control for MIDI/audio, plus internal rescale `effectIntensity*0.53` (hand-calibrated headroom).
- *360-sample temporal motion blur* (KickEffects): loops `MOTION_BLUR_SAMPLES 360` sub-frame time offsets (`TIME + (1/120)*((i+hash)/N)`) through 4 pattern offset generators (star burst with 7 rotating attractors, 4×4 warping grid attractor field, 6-arm spiral, 8-segment kaleidoscope reflection delta) — brute-force analytic motion blur of a force-field warp; plus camera shake with `exp(-t*5)` falloff.
- *VDMX macro-expansion scar* (Kick_Neon_3): `VVSAMPLER_2DBYNORM(inputImage, _inputImage_imgRect, _inputImage_imgSize, _inputImage_flip, uv)` — the file was saved *after* VDMX's preprocessor expanded IMG_ macros, then hand-edited (renamed `sample` → `ghostSample`/`glowSample`/`echoSample` because `sample` is reserved in Metal/GLSL3). Direct evidence of the Metal-backend reserved-word hazard and the debugging that followed. Kick_Neon_alt still contains `vec4 sample = vec4(0.0);` — the *unfixed* pre-Metal version kept as a fossil.
- *Multi-effect rack* (KickEffects-2): ten 0–1 sliders (cosmicBloom, fractalRift, electricArcs, parallaxShift, pixelConfetti, chromaticShatter, temporalEcho, spaceWarp, neonOutlines, particleBurst), each a self-contained function, summed `totalIntensity` drives shared trail/decay/composite; offset-type effects accumulate into one `totalOffset` before sampling (warp composition, not sequential resampling).

**Control/UI design**: deliberately minimal performance surface — usually ONE hero slider (`neonIntensity` / `effectIntensity`) defaulting to 0, everything else baked as #define constants with inline comments recording tuning history ("Increased from 1.4", "Reduced from 12.0"). Constants-block-as-preset is the family's defining trait: versions differ mostly in #define values.

**Version evolution**: Kick_Neon (texture()-based, GLSL3) → Neon_alt (IMG_PIXEL, `sample` bug latent) → Neon_2 (adds ghostBuffer, 4-color palette, micro-detail fractal noise) → Neon_3 (VDMX-expanded, `sample` renamed, GHOST_INTENSITY halved 1.2→0.65, glow halved — taming pass) → Neon_4 line pivots to "Spectral Echo": Neon_4 (adds intensityCurve + curve-calibrated), DarkGrain (freeze/invert/stutter with COLOR_BOOST 1.8 aggression), fluid (stripped-back gentle version, MIN_BRIGHTNESS 0.4→0.2), Freeze (parameterized ghostPersistence/flowStrength — but *unfinished*: literally ends with the comment `// ... other passes to be implemented ...` and an LLM's "Would you like me to continue with the utility functions…" left in the source). KickEffects → KickEffects-2 documents the punch-bug fix and decay unification in its DESCRIPTION.

**Complexity tier**: 4 across the family (multi-buffer state machines with designed attack/release), 3 for the simpler spectral variants.

**Signature moves**: depth map as a *mixing fader* (near=wet); one-knob hit effects with shaped attack and sculpted decay (Voronoi crumble); `max()`-latch accumulation; constants-with-changelog-comments as preset system.

**Rough edges**: Kick_Neon uses `texture()` directly (host-dependent); Neon_alt's reserved-word `sample` (compile-breaker on Metal — the exact bug class the author later works around); Neon_4_Freeze shipped incomplete with LLM conversation text in-file; duplicated file with/without .fs extension; `getVelocity` computes "velocity" as color difference between input and effect buffer (semantically wrong, visually useful); KickEffects' 360-sample loop is a GPU inferno.

---

## Family 7: AR_Kopie_test-v01.fs (1 file) — "KOPIE / Architecture of Erosion"

**Purpose & visual identity**: Generator; an audiovisual art piece companion to the author's LOCALHOST Strudel album. "The screen is the tape" — three virtual recording machines lay marks that erode; chords choose the palette; dropouts tear.

**Architecture**: 4 passes — `machineB` PERSISTENT FLOAT at **quarter resolution** (`"WIDTH":"floor($WIDTH*0.25)"`), `machineH` PERSISTENT FLOAT at half res, `machineM` PERSISTENT FLOAT full res, non-persistent composite. Resolution matched to mark scale (wide strata need less res than the fine stylus line) — deliberate perf/texture design. Header documents its own house rules: "no ternaries on vector types, marks accumulate additively (prev*decay + deposit), each persistent buffer computes only itself, composite is non-persistent."

**Techniques**:
- *Score-driven inputs*: `trigB/trigH/trigM` event inputs + `chordIndex` long (Fm/Ab/Eb/Bb) fed from Strudel via OSC/MIDI, with `internalClock` bool fallback deriving chord from `mod(floor(t/CYC),4)` where `#define CYC (1.0/0.205)` — the music's cycle length (setcps .205) hard-coded as the visual clock. Audio analysis mapped to `audioWow` (lateral swim of laid marks) and `audioHiss` (grain competing for empty pixels).
- *Harmonic field*: chord → palette (`fieldPalette`: cold slate / dim amber / pale green-grey / dusty violet), density, via if-chains (ternary-free, vector-safe).
- *Wear tides*: `halfTide(t,P)=0.25-0.25*cos(TAU*t/P)` summed at **coprime periods** (4.3/5.9, 5.3/7.1, 6.1/8.3) per machine — slow non-repeating erosion envelopes, quarter-late "so the piece opens intact and decays from zero."
- *Machine clocks*: `machinePulse` = duty-cycle pulse whose period stretches and duty shrinks with wear (`duty = mix(0.20, 0.06, wear)` — dying machines make shorter marks); external trig overrides (`if (trigB) pulse = 1.0;` — "a real note always lands").
- *Additive deposit + decay*: every buffer does `col = prev * decay * tear(...) + deposit`; decay itself is wear/elongation-modulated `mix(0.965, 0.9965, wear*elongation)`.
- *Tear, don't fade*: `tear()` kills whole horizontal bands (`floor(uv.y*28.0)` hashed against time) — dropouts as hard absence.
- *The stylus*: one bright dot whose stroke duration stretches `CYC*mix(0.8, 8.0, wear)` (~4s→40s); "the trail it leaves is a single stroke that crosses chords and changes color mid-line: the past repainted by the present."
- *Stuck head glint*: periodic `smoothstep` window flashes a hand-drawn "intact" version of all three contours — the memory of the undamaged loop.
- *Hiss occupancy competition*: grain added weighted by `(1.0 - occupancy)` where occupancy = luma of laid marks — noise only claims abandoned pixels.
- *Tape ceiling*: `col = 1.0 - exp(-col * masterGain * 1.15)` — soft-knee tone map ("tape ceiling, not clipping"); plus analytic vignette `uv.x*(1-uv.x)*uv.y*(1-uv.y)*16`.
- Ternary-free sign trick: `float dir = step(0.5, hash11(idx)) * 2.0 - 1.0; // float, ternary-free`.

**Control/UI**: 15 inputs mixing score I/O (events, chord dropdown labeled with actual chord names) and aesthetic macros (`wearGain`, `tideSpeed`, `elongation`, `shearAmount`, `rotAmount`, `stuckHead`, `warmth`, `masterGain`) — labels annotate the mapping (`"Wow (map: pitch drift)"`).

**Complexity tier**: 5 — a designed generative system with narrative architecture, multi-rate buffers, external-score integration, and a written constitution in comments.

**Signature moves**: coprime-period envelopes; resolution-tiered persistent buffers; event-input override of internal clocks; occupancy-gated noise; exp tone-map ceiling; extensive intent-documenting comments (unique in the batch — this file is *written*, not accreted).

**Rough edges**: audioWow/audioHiss are manual sliders standing in for an analysis chain ("map:" hints); intact-loop glint hard-codes contour geometry that only roughly matches the machines' random output.

---

## Family 8: AR_LazorShapes_v01.fs (1 file)

**Purpose**: Generator. Wireframe "laser" diamond lattice — 5 stacked rings of 12 points, ring-to-ring vertical struts, 4 long diagonals, tumbling in 3D, drawn as glowing lines on black.

**Architecture**: Single pass, no buffers.

**Techniques**:
- Full Euler rotation matrix built from three wobbling angles (`spinX = t*0.2 + sin(t*0.17)*0.5` — rate + LFO wobble so tumbling never loops visibly).
- *3D-to-2D orthographic line field*: rotate 3D points, take `.xz`, then per-pixel distance to segment via the classic project-and-clamp:
  ```glsl
  float t = clamp(dot(uv - p, dir) / dot(dir,dir), 0.0, 1.0);
  float dist = length(uv - (p + dir * t));
  float laser = LaserWidth / (dist + 0.02);
  ```
  — `w/(d+ε)` falloff = neon glow lines with hot cores; three brightness tiers (ring lines vs vertical struts vs diagonals) in fixed blue palette.
- Shape defined by two `float[5]` arrays (heights, radii) — data-driven silhouette.

**Control/UI**: 4 floats (TimeRate, Zoom, LaserWidth, VertWidth). Header uses nonstandard `"TYPE":"generator"`/`"LABEL"` keys.

**Complexity tier**: 2 — clean single-idea generator; O(5×12×2 + 4) segment evaluations per pixel.

**Signature moves**: additive `width/(dist+soft)` glow accumulation; LFO-modulated rotation rates.

**Rough edges**: brute-force per-pixel loop over all segments; colors hard-coded.

---

## Family 9: LiquidCrystal v01–v03 + LiquidCrystalWarp_v01 (4 files) — "Broken LCD"

**Purpose & visual identity**: Filter. Self-referential RGB-channel feedback smear — the previous frame's own colors steer where each channel resamples the previous frame, producing liquid, oily, acid-trip channel separation ("Broken LCD").

**Architecture**: All 3 passes: `BufferA` PERSISTENT, `BufferB` PERSISTENT, composite. Note: NOT FLOAT — 8-bit feedback, and the grunge that comes with it is part of the look.

**Techniques**:
- *Color-as-flow-field feedback* (the core trick, all versions):
  ```glsl
  float gt = mod(TIME * uv.x * uv.y, u_billow * 6.1415) * u_scale;
  vec2 d1 = uvColor.x * vec2(texel.x*cos(gt*uvColor.z), texel.y*sin(gt*uvColor.y));
  // d2, d3 permute channels
  float bright = (r+g+b)/u_push_RGB + u_push_RGB2;
  float r = IMG_NORM_PIXEL(BufferA, mod(uv + d1*bright, 1.0)).x;  // per-channel resample
  ```
  Each channel's displacement is driven by *other* channels of the feedback buffer; `TIME*uv.x*uv.y` makes phase vary spatially (moiré-like phase gradients). Torus wrap via `mod(...,1.0)`.
- *Buffer cross-flash*: `if (fract(TIME*0.2) > 0.5) baseColor = mix(flow0, flow2, 0.1*flow0.b*flashIntensity);` where flow2 is BufferB sampled at `flow0.xy*0.1+uv` — B's content smeared through A's colors as a periodic strobe.
- *Startup seeding*: `if (FRAMEINDEX < startFrame) gl_FragColor = flowIn;` — feed clean input for N frames before letting feedback take over (the FRAMEINDEX-init idiom, parameterized).
- *v01's structured modulation layer*: adds Sobel edge detection (full 3×3 kernels written out) + luma, `influence = (pow(luma,Gamma)*LuminanceInfluence + pow(edge,Gamma)*EdgeInfluence)` with `MinInfluence` floor, scaling the displacement — content-aware smearing (edges melt hardest).
- *v03's depth integration*: `applyDepthWarp` sine-wave UV warp scaled by depthMap; five selectable blend modes (Overlay/Screen/Multiply/Add/SoftLight) implemented per-channel with scalar ternaries; depth-masked effect opacity.
- Composite pass differences: v01/v02 `BufferA * BufferB` (multiplicative — dark, contrasty); LCWarp `mix(source, mix(A,B,0.5), effectStrength)` (recoverable dry/wet); v03 blend-mode composite.
- Param naming as art: `u_didYOUeatALLthatACID` (channel-mix amount, default 1.19729 — hyper-specific hand-tuned defaults like 2.9209 throughout).

**Control/UI**: v02 is the raw `u_*` Shadertoy-style original (declares `uniform int u_startFrame;` manually — the "int input needs explicit uniform" host quirk). v01 is the cleaned "pro" build: renamed params, Gamma/Min/Influence controls, `EffectIntensity` + `SourceOpacity` masters. LCWarp is the simplified stable set. Evolution of naming: `u_billow` → `DistortionSpeed`, `u_leak` → `distortionSpread`, `u_didYOUeatALLthatACID` → `colorDistortionAmount`.

**Version evolution**: v02 (raw import, feedback clamped) → v01 (adds luma/edge influence engine, *removes* the feedback clamp — comment `// Removed clamping` — embracing blowout) → v03 (depth map + blend modes + time-modulated params `u_rate + time_mod`) → LCWarp_v01 (feedback removed entirely — BufferA/B become two independent single-frame distortions averaged; a "safe" non-accumulating version for mixing).

**Complexity tier**: 3–4 (v03).

**Signature moves**: feedback color channels as vector field; FRAMEINDEX seeding window; deliberately unclamped 8-bit feedback; joke-name parameters with precision defaults.

**Rough edges**: v01 keeps a `PressureScale`-style dead duplication between PASS0 and PASS1 (~100 lines pasted twice with tiny diffs); PASS1 in v02/v01 writes BufferB from *input* (not A) making BufferB a half-processed sibling — works but murky; case-sensitivity trap: v01's JSON declares `FeedbackIntensity` and code uses it, but MeltingCam (Family 11) shows the same author hitting case mismatches.

---

## Family 10: ArsonRivvers_megaTorusWarper_v01.fs (1 file)

**Purpose**: Filter. Polar-domain warp combining a figure-eight-knot-inspired offset and a torus-profile offset (modulated by input luma as pseudo-depth), plus an optional self-intersection feedback pass.

**Architecture**: 2 passes: `feedbackBuffer` (declared PERSISTENT via legacy `PERSISTENT_BUFFERS` array; pass 0 target) + final.

**Techniques**:
- Polar parameterization: `angle=atan(rel.y,rel.x)+π`, `radius=length(rel)/max_radius` mapped to knot params `u=angle*2 (0..4π)`, `v=radius*2`; knot XY `sin(u)*(1+0.5sin(3v))` with z-wave `waveAmplitude*sin(waveFrequency*u + TIME)` used as an inverse-scale (`scale = 1/(1+z)`) — depth-modulated magnification rings.
- Torus offset: `zTorus = (R + r*cos(v))*sin(u)` projected along the angular direction, signed by input luma `(depthValue*2-1)` — bright areas push out, dark pull in.
- Self-intersection feedback: pass 1 re-warps the feedback buffer by its *own* red/green channels `(feedbackColor.rg - 0.5)*2*feedbackDepth*...` — same color-as-displacement DNA as LiquidCrystal.

**Control/UI**: 8 floats, separate intensity per component (knotIntensity/torusIntensity/selfIntersectionIntensity) + global warpIntensity.

**Complexity tier**: 2.

**Rough edges**: feedbackBuffer written every frame from input (pass 0 isn't actually accumulating — "PERSISTENT" is inert here; the "feedback" is a same-frame double warp). Credit "Generated with help from OpenAI's ChatGPT". This file's header is what got transplanted onto ImpoShapeDistortion.

---

## Family 11: AR_MeltingCam1_HallofMirrors.fs (1 file)

**Purpose**: Webcam-driven fluid-ish simulation (Shadertoy convert) — luma-thresholded webcam regions emit velocity/ink into a pressure-advection buffer; output blends webcam with the pressure field ("melting camera").

**Architecture**: 3 passes: BufferA FLOAT PERSISTENT (velocity.xy, pressure.z, ink.w), BufferB FLOAT PERSISTENT, final FLOAT.

**Techniques**:
- Compact stam-style fluid on one buffer: self-advection `tex(g - tex(g).xy)`, neighbor pressure `0.25*(a.z+b.z+c.z+d.z) - 0.05*(c.x-a.x+d.y-b.y)` (divergence term), boundary zeroing at edges.
- *Macro-based DSL*: `#define tex(g)`, `#define emit(v,s) if (length(g-(v))<emitSize) ...`, `#define wallCircle(v,d)` — Shadertoy code-golf idioms carried over.
- Webcam luma gates: bright pixels (`lumens > 2.5 || webcam.r > 0.7...`) emit colored velocity derived from webcam RGB; dark areas damp pressure/ink.
- Pressure overload venting: `if (abs(pressure) > 4.9931 || lumens > 0.8) { pressure *= 0.8; gl_FragColor.w = abs(z)-0.05; }`.

**Rough edges (important negative knowledge)**: **This file is broken as written** — JSON declares `BlendStrength/FluidIntensity/PressureScale` (capitalized) but code uses `pressureScale/fluidIntensity/blendStrength` (lowercase): ISF inputs are case-sensitive → compile failure. Also `tomachi = vec4(1.0001,1.0002,1.0003,0.0)` multiplies feedback slightly >1 (deliberate slow blowup) while alpha is zeroed each frame. BufferB is declared but never written intentionally (only read). A conversion abandoned mid-repair.

**Complexity tier**: 3 (intended).

---

## Family 12: AR_MicroFeedback_v01.fs (1 file)

**Purpose**: Filter. Compact recursive feedback warp — feedback buffer sampled through its own accumulated offset, iterated.

**Architecture**: 2 passes: `feedback` (legacy PERSISTENT_BUFFERS object form `{"NAME":"feedback","TYPE":"image"}`) + passthrough.

**Techniques**:
- Sampler helpers `T_fb(x)/T_in(x)` wrapping `IMG_NORM_PIXEL(..., fract(x/RENDERSIZE))` — pixel-coord API with torus wrap.
- Recursive offset accumulation:
  ```glsl
  vec4 c = vec4(q.x,q.x,q.y,q.y) * sin(timeScale*TIME/3.0 + phaseOffset); c *= warpDepth;
  for (int i=0;i<6;++i){ if (i>=int(iterations)) break;
      c += T_fb(u - c.xy)*2.0 - feedbackDistortion; }
  ```
  — each iteration reads the feedback buffer at the current accumulated offset and folds the *color* back into the offset (color⇄position recursion, the purest statement of the author's feedback obsession).
- Output mixes a re-warped feedback tap with `fract(c/3.0 + colorShift).argb` (swizzled fract palette) under a `feedbackTint` color; written back with `mix(prev, outF, decay)`.

**Control/UI**: 10 inputs; `phaseOffset` MAX literally `6.283185307179586`; `iterations` as `long` with bounded-loop break; `feedbackTint` color input.

**Complexity tier**: 3 — tiny file, dense recursion.

**Rough edges**: `decay` used backwards vs its name (higher decay = *more* new frame); nonstandard PERSISTENT_BUFFERS object syntax (works in some hosts only).

---

## Batch synthesis

**Top 3 most sophisticated files**:
1. **AR_HyperTesseract v03 / dataloss line** — a genuinely engineered 3-pass system: 4D SDF + data-carving voxel field + Hamming-metric space distortion + physics-switchable additive feedback + full retro post chain, governed by three macro conductors, with a real changelog discipline (each rev names its fixes: carve authority, real flow, FOV/zoom separation, gated lighting) and host-portability hardening (const-bound fold loops, loop-invariant hoisting).
2. **ArsonRivvers_KaliedoClassic v8/v10** — the 1×1-persistent-buffer parameter-easing engine (dt-correct exponential smoothing of shape phase, complexity, symmetry, distortion — frame-rate independent, host-agnostic) wrapped around an 8-way-blended 10-algorithm IFS; the most complete "shader as playable instrument" architecture in the batch.
3. **AR_Kopie_test-v01 (KOPIE)** — conceptually the strongest: a generative tape-erosion system with resolution-tiered persistent buffers, coprime wear tides, score-driven event inputs from Strudel, occupancy-gated noise, and a self-documenting house-rules header. Least code per idea.

**Recurring patterns / style fingerprints**:
- *Everything is continuously morphable*: floor/ceil+fract blending for integer params (iterations, symmetry, shapes), `mix(identity, transformed, amount)` at the math level for dry/wet, eased 0–1 sliders shaped by `pow`/smoothstep response curves.
- *Const-bound loops with runtime break* (`for(i<MAX){ if(i>=n) break; }`) everywhere — the Metal/host portability idiom.
- *FRAMEINDEX / alpha-flag initialization* of persistent buffers; `startFrame` seeding windows.
- *Feedback grammar*: `prev*decay + deposit` (additive), `max(prev*decay, current)` (latch), color-channels-as-displacement-field (LiquidCrystal, MicroFeedback, megaTorus).
- *Depth map as fader*: `*(1.0 - depth)` scaling across the whole Kick family.
- *One hero slider defaulting to 0* for performance effects; constants blocks with tuning-history comments as the preset system.
- Shared helper boilerplate: `hash21` (`.1031,.1030,.0973` fract-sin-free hash), `rand` fract-sin, `rotate(a)` mat2, `ease01`, `mirrorRepeat`, `round_compat`, sinh/cosh polyfills, Bayer 4×4 arrays.
- LLM-assisted authorship openly credited ("Gemini Hybrid + Claude", "Modified by ChatGPT") with the author acting as integrator/curator; file lineages fork per experiment (DarkGrain/fluid/Freeze suffixes).

**Beyond standard ShaderToy fare**:
- 1×1 persistent FLOAT buffers as a scalar state machine for frame-rate-independent parameter easing (KaliedoClassic v7–v10) — essentially implementing host-side slider smoothing inside ISF.
- Hamming (popcount) distance metric substituted for Euclidean in a raymarcher.
- Coprime multiplicative permutation (`(a*i+b) mod 10`, a ∈ {1,3,7,9}) for seeded shape sequencing.
- Coprime-period cosine "wear tides" and occupancy-gated noise competition (KOPIE) — generative erosion driven by an external live-coded music score via event inputs.
- Polarity-invertible feedback physics (accumulate darkness) in both HyperTesseract and the freeze variants.
- Resolution-tiered persistent buffers matched to mark granularity (quarter/half/full res in one shader).
- Forensic host-quirk fossils: a VDMX-macro-expanded file hand-fixed for Metal's reserved word `sample` (Kick_Neon_3) alongside its unfixed twin (Kick_Neon_alt), and a case-sensitivity-broken conversion (MeltingCam) — valuable negative-knowledge fixtures for a generator's lint rules (validate header/code identifier parity, ban reserved words, case-check input names).
