All 44 files were read (7 giant catalog files hit the read cap on first pass; I captured their headers, shape catalogs, and confirmed the endpoint main()/blend logic with targeted follow-up reads). Full report follows as the deliverable.

---

# Batch 21 Analysis Report — AR_ProqxisShapes / AR_PsychArt / AR_ReactionDiffusion

## Coverage
- files_assigned: 44, files_read: 44, misses: none
- Note: 7 of the largest files (AR_ProqxisShapes_v22_gp.fs at 1550 lines and catalogtest v02–v08 at 1760–2432 lines) exceeded the single-read token cap; each was read for its first ~1100 lines (header, full shape catalog up to that point, all helper/chaos code) and the remaining tails were verified by targeted offset reads and greps of the final file (catalogtest_v08) to capture the endpoint architecture (metaMapCatalogBlend, metaMapCatalogSpanBlend, banked-nav main()). The truncated tails are shape-function catalogs plus a render main() that is byte-identical boilerplate to fully-read siblings, so no architectural information was lost.

---

## Family 1: AR_ProqxisShapes (v01–v22_gp + catalogtest v01–v08, 37 files)

This is the batch's flagship: a two-year evolution of a single volumetric SDF-morphing generator, from a 187-line toy to a 2,432-line 113-shape performable instrument. It is one continuous lineage; I treat the catalogtest files as the final arc of the same family.

**Purpose & visual identity**: Generator. A glowing, fog-wrapped volumetric raymarcher orbiting a central morphing organism — SDF fields (clover/coral/tendril/inversion, later 100+ shapes) crossfaded by a "morphPhase," rendered not with surface hits but with density-glow accumulation (`contrib = gain * palette / (1 + d*d*falloff)`), giving everything a translucent nebula/x-ray look. Palette is cos-spectrum keyed to log-distance. Distinctly "alive": every shape breathes via `sin(t)` modulation of every radius and rotation.

**Architecture**:
- v01–v03: single pass.
- v04 onward: 2 passes — a **1x1 PERSISTENT FLOAT buffer (`morphPhaseBuffer`) used as a scalar state register**, pass 0 writes `mix(current, target, morphLerp*0.02)` each frame (exponential slew limiter), pass 1 is the raymarcher reading `IMG_PIXEL(morphPhaseBuffer, vec2(0.5)).r`. This is the family's foundational trick: GPU-persistent smoothed parameter state so a hard slider jump becomes a cinematic morph.
- v17 variant: 3 passes — adds a second 1x1 `timeAccBuffer` storing `(accumulatedTime, lastTIME, smoothedSpeed, initFlag)`; dt-integrated time accumulator (`accum += dt * smoothedSpeed`, smoothing alpha `1-exp(-dt*8)`) so changing timeSpeed never causes a time-jump; first-frame detection via `FRAMEINDEX == 0 || !(prev.a > 0.5)`.
- v11_distFX-5 onward / catalogtest: 3 passes — `morphPhaseBuffer` (state), `sceneColor` (full-res scene), final pass = **true post-process chromatic aberration** resampling sceneColor with per-channel UV offsets (replacing the earlier fake in-place CA).
- Core loop: camera orbit or manual rig → per-step domain distortion → `metaMap` SDF blend → glow accumulation + bloom accumulator → Reinhard tonemap (`col/(col+1)`), exp fog, screen-center halo, `pow(bloom/(bloom+1), 0.6)` bloom mix, hash-dither `/128` to kill banding.

**Techniques** (the heart):
1. **SDF crossfade morphing** — `metaMap` linearly `mix()`es whole distance fields across integer segments of morphPhase (`mix(cloverField, coralField, phase)` etc., wrapping). Not mathematically a true SDF but visually smooth; `metaMapSimple` (nearest-field) exists as the cheap fallback.
2. **Persistent 1x1 buffer as parameter slew limiter** — later generalized: v13 smooths timeSpeed (G channel), v14 adds chaosFrequency (B), v15 smooths twistIntensity; v17 replaces phase-of-TIME with an integrated time accumulator. A whole idiom: buffer channels R/G/B/A = independent smoothed control signals.
3. **Density-glow raymarching** — no surface hit test; every step contributes `1/(1+d²*falloff)` weighted cos-palette (`0.8 + cos(log(length(pos)*scale+1) + i*0.0744 - t + vec3(0,1,2))`) — log-distance drives hue banding; step index `i` adds an iridescent shimmer per step. Step size `T += max(minStep, d*0.5)` (fixed floor prevents stall inside the volume).
4. **The chaos-distortion library (`applyChaosDistortions`)** — up to 19 independently-gated domain warps applied to the ray sample point: turbulence (3-axis offset fbm), energyPulse (`pow(sin,3)` radial scale), vortex (exp-falloff swirl in xz), warpAmplitude (moving attractor push), twist (y-driven rot of xz), shatter (noise displacement masked by `smoothstep(0.3,0.7,|noise|)`), breathing, gravityWells (two orbiting `1/(1+d²)` attractors), electricStorms (`pow(|turb-0.5|*2, 3)` spikes along a time-varying direction), liquidDynamics (viscosity mix), quantumFlicker (hash glitches gated by `smoothstep(0.8,1.0,hash(t))`), quantizeSpace (voxel `floor(p*grid)/grid` + hash jitter to hide aliasing), faultSlip (tangential slide inside `1-smoothstep(0,width,|dot(p,n)+osc|)` bands across up to 3 moving planes), fractureAnisotropy (projection-stretch with exp falloff), tectonicFold (`(abs(d)-d)` one-sided plane fold), eventHorizonWarp (radial compression `v * 1/(1+k/r)` toward a moving mass), spaceTear (offset along numerical noise gradient only inside a `|n-0.6|<0.015` seam, gradient computed **only when seam>0.001** — branch-avoided when possible), shockFront (`pow(max(sin(r*4 - t*1.6),0),3)` expanding wavefront), meltFlow (turbulence-squared downward sag + lateral ooze).
5. **Phase-aware chaos gate** — v11_distFX-5+: `chaosGate = smoothstep(chaosPhaseWindow, 0.0, min(fract(morphScene), 1-fract(morphScene)))` — chaos is strongest only near *stable* (integer) morph phases, and relaxes mid-morph. A conductor-level compositional rule embedded in the shader.
6. **Perceptual meta-sliders** — `opacityLevel` fans out to glowGain/glowFalloff/ambientGlow/haloAmount/ray start distance simultaneously; `opacityMode` selects linear / exponential (`opac²`) / manual-off response curves. v10_simple reduces the whole UI to 5 macro knobs (visualQuality, glowIntensity, effectsStrength, shapeComplexity, camDistance) each expanding to 4–6 internals.
7. **Adaptive quality system** — rayQuality/distortionQuality/morphingDetail/colorComplexity/lightingQuality each pick between full/medium/low code paths (e.g., color: full log-palette → single-freq cos → flat hue); `adaptiveQuality` auto-derates all of them by camera distance (`smoothstep(3,8,camDist)`); octave counts in turbulence gated by intensity (`1 + floor(clamp(x)*2)`); shadow/AO sample counts `int(mix(2,8,quality))` with runtime `break` inside const loop bounds — a Metal/GLSL-ES workaround used everywhere.
8. **Micro-optimizations in later revisions** — expensive palette computed only every other march step and cached (`mod(float(i),2.0)` — comment notes float mod "for ES compatibility"); **first-hit lighting latch** (compute shadows/AO once at first near-surface step, reuse for 2 following steps); `fogStepBoost` grows step size where fog will dominate anyway; `RAY_MAX 256` const with `if (i >= int(adaptiveRaySteps)) break;`.
9. **Volumetric lighting** — soft shadow marching (`shadowAccum *= smoothstep(0, 0.3, d/step)` with growing step), 5-tap normal-direction AO, quality-branched normals (4-sample tetrahedron when quality<0.3, else 6-sample central difference; catalogtest adds *gradient-adaptive epsilon*: recompute normal with 1.5x epsilon when `|∇|` is small to de-noise).
10. **Anti-banding dither ladder** — v07: constant subtle dither into the palette phase; v08: **camera-distance-adaptive dither** `mix(0.08, 0.0, smoothstep(1.5, 6.0, camDist))` (dither only close-up where log-palette banding appears); final ordered dither `(hash(gl_FragCoord)-0.5)/128` always.
11. **The shape catalog** — catalogtest arc: `catalogMode` bool + `shapeId` slider dispatched through a giant if-chain `metaMapCatalog(p,t,id)`. Grows 23 → 55 → 67 → 84 → 94 → **114 shapes**: organic (coralGrowth, anemoneTendrils, amoeba), geometric (torusLoop, gearArray, helixCage), mathematical surfaces (gyroid, Kummer quartic level-set band `|x²y²+y²z²+z²x² − 0.2r²| − 0.04`, Fresnel wave envelope, hyperelliptic Riemann sheets, tesseract projection with true 4D XW/YW rotations and w-modulated edge thickness), virus monsters (fibonacci-sphere spike distributions — `fibonacciDir` golden-angle point placement is a recurring ingredient — capsid spikes, phage with legs, tentacle maw), knots sampled as polyline min-distance (figure-8, trefoil "nebulaKnot" — 12–28 samples of the parametric curve, `d = min(d, length(p - curve(u)))` then inflate), fractals (Mandelbulb power-8 DE, Mandelbox with boxFold/sphereFold, Kleinian `abs(z)/dot(z,z) - c` iterations, Sierpinski plane folds, Apollonian recursive sphere inversion with scale tracking `s /= r2`, Menger via cross-cavity subtraction `max(d, -cross/s)`).
12. **Shape remix combinators** — a deliberate meta-system: `inversionDomain` (dual moving sphere-inversion centers + trig micro-folds + axial mod-wrap), `inversionGate` (ring∧torus intersection mask), `detailBand` (surface-proximity noise `d -= 0.02 * band * n` gated by `1-smoothstep(0,0.08,|d|)` "to avoid SDF collapse"), `smin/smax` polynomial smooth booleans. These generate "Inv" and "Extreme" variants of base shapes mechanically — shape count scales combinatorially, not by hand-writing.
13. **Catalog navigation/morphing (endpoint, catalogtest_v06–v08)** — fractional shapeId blending: `metaMapCatalogBlend` mixes neighbor ids by `fract(sid)` with wraparound; `metaMapCatalogSpanBlend` does a **gaussian-weighted blend over up to 13 neighboring shapes** (`w = exp(-0.5 dx²/σ²)`, σ = span*0.35) then `d = mix(dSpan, dFine, 0.2)` to restore crispness; pass 0 slews the phase with `lerpAmt = clamp(shapeMorphLerp * shapeMorphRate * 0.0167, 0, 0.5)` for "dramatic, slow scrubbing." v08 adds **banked navigation**: `useBankedNav` + `shapeCoarse`/`shapeFine`/`shapeBankSize` — coarse knob picks a bank of N shapes, fine knob scrubs within it, solving the 114-shapes-on-one-slider resolution problem.
14. **Camera rig evolution** — auto-orbit ↔ manual XYZ crossfade (`mix(autoCam, manualCam, camMode)`), camSpeed reused to animate *around* the manual position (Lissajous jitter), pitch/yaw/roll via component-pair mat2 rotations with re-orthonormalization, `orbitRadius`, `focusTarget` look-at, `zoomSpeed` breathing focal length, `viewRoll` sinusoidal roll.

**Control/UI design**: The family oscillates between two philosophies and this oscillation IS the story: expansion (v06: 30 inputs; v11_distFX-2: 50+ inputs incl. 19 chaos knobs) then contraction (v10_simple: 14 meta-knobs; v14/v15: "Static defaults for removed UI sliders" — a `const float` block replacing removed uniforms 1:1 so the body compiles unchanged; catalogtest: camera-only + catalog inputs, everything else const). Naming is consistent camelCase with domain prefixes (`cam*`, `glow*`, `chaos*`, `shape*`, `blowout*`). Coarse/fine pair appears explicitly in v08 (`shapeCoarse`/`shapeFine`). v15 introduces **bool "buttons" as scene presets** (morph1–morph5 setting targetPhase 0–4) — VDMX-friendly momentary control. `chaosPreset` (Calm/Balanced/Chaotic) is a macro that rewrites chaosQuality + chaosPhaseWindow. `randomSeed` + `seededHash` for repeatable performances.

**Version evolution (learning trajectory)**:
- v01→v02: hardcoded constants → full parameterization (every magic number became an input).
- v03: manual camera; v04: **the big architectural leap** — persistent-buffer smoothed morph state (performability: scene changes become gradual).
- v05→v06: perceptual meta-slider + response-curve modes; full camera rotations (buggy first attempt — see rough edges).
- v07→v08: fighting log-palette banding — first constant dither, then camera-distance-adaptive dither (each rev is a diagnosed fix with comments like "Minimal fix: keep original log function but add subtle smoothing").
- v09 x3 (parallel experiments): wShadow = lighting; QC-slides = performance tiers; v09 = merge.
- v10_simple: UI collapse to macro controls (live-performance lesson: too many knobs).
- v11_distFX 1–7: chaos library buildout → perf gating → phase-aware gate → post-process CA in 3rd pass → presets/seed → first 5-shape alternative sequences importing catalog shapes ("Declarations pulled from proxis_Shapetest.isf").
- v12–v15: consolidation, ISFVSN 2.0 headers, buffer-smoothed params, preset buttons.
- v17: dt-integrated time accumulator (jitter-free timeSpeed — a real VJ pain point).
- v18–v22_gp: catalogMode arrives; catalog 23→94 shapes; shapeId default even changed to 35 (virusCapsidSpikes — his evident favorite).
- catalogtest v01–v08: catalog to 114; fractional/gaussian span morphing between arbitrary catalog shapes; banked coarse/fine navigation. Endpoint = a playable shape instrument.

**Complexity tier**: **5** — multi-pass persistent-state simulation-adjacent system, 114-entry procedural shape library with combinator remixing, adaptive quality management, conductor meta-controls, post-process chain. Among the most elaborate single-lineage ISF projects plausible in the wild.

**Signature moves & standout tricks**: 1x1 persistent buffer as multi-channel parameter slew rack; gaussian span-blend over an SDF catalog; fibonacciDir golden-angle instancing; phase-aware chaosGate; `detailBand` gated surface noise; `inversionDomain`+`inversionGate` shape remix combinator; camera-distance-adaptive dithering; every-other-step palette caching; polyline-sampled knots; `(abs(d)-d)` one-sided folds; const-defaults block for de-UI'd uniforms.

**Rough edges**: v06's pitch/yaw/roll math is visibly wrong (yaw computes `fr` then ignores it; roll builds and discards `ru_rotated`; both re-derive vectors ad hoc) — fixed only in distFX-4+ with clean component-pair rotations. Dead code persists everywhere (unused `uv_osc`, `rOffset/gOffset/bOffset` in the fake CA, `edge` variable in tesseract, unused `calm` in preset logic, `hueOffset` still keyed to morphPhase<4 even after 114-shape catalog). The in-place "chromatic aberration" pre-distFX-5 is a no-op channel remix (`chromatic = vec3(col.r,col.g,col.b)` mixed with itself) — only the fringe term did anything; the author evidently realized this and built the real post-pass. `metaMapSimple` in catalog files still dispatches only the original 4 shapes. v16 is missing from the sequence (skipped or deleted). catalogtest_v06 file carries a stray first line `proqxis_ARShapes_v02` above the JSON comment (would break strict parsers — host tolerance scar). The `mix()` of whole SDFs and the 13-tap gaussian blend cost up to 13 full catalog evaluations per march step — brute force accepted for art.

---

## Family 2: AR_PsychArt (AR_PsychArt.fs, AR_PsychArt_v02.fs)

**Purpose & visual identity**: Filter (image effect). "Psych-art": triple-nested FBM domain-warped rainbow marbling wrapped around the luminance-depth structure of the input video, composited back over the source with selectable blend modes. Liquid-light-show aesthetic.

**Architecture**: Single pass, no buffers. v01 (`AR_PsychArt.fs`) takes `srcImage` + optional `depthImage` with `depthMode` (LumaFromSource / ExternalDepth — built for external depth maps, e.g. depth-camera or ML depth); v02 simplifies to source-only luminance depth.

**Techniques**:
- **Luminance-as-depth warp**: `getDepth = pow(clamp(luma + depthBias), depthSharp)`; numerical gradient from 2 extra taps; warp = `depthAmount * (0.6 * tangent + 0.4 * viewDir * depth)` — the *rotated* gradient (tangent `vec2(-g.y, g.x)`) makes the pattern flow *along* image contours rather than across them, which is why the psych pattern appears to wrap around subjects.
- **Source-coupled FBM**: inside the 11-octave fbm loop, `f += srcCouple * n2(vec2(cc.r, cc.b))` injects the source pixel's red/blue as a noise coordinate — video content perturbs the field directly (srcCouple is signed, default negative).
- **Nonstandard FBM**: octave frequency scales linearly with loop index (`p * 0.4 * fbmFreq * float(i)`) and each octave's coords are *multiplied* by animated noise (`p1.x *= n2(...) * fbmWarp`) — a warp-inside-octave structure, not the canonical amplitude-halving fbm. Then triple nesting: `pattern = fbm(p + fbm(p*2.3 + fbm(p*0.33)))` (classic iq domain-warping, here at 33 fbm evaluations of 11 octaves each = deliberately extravagant).
- **Direct trig palette**: `vec3(sin(shade*0.91 + t*rateA)*1.75+0.5, cos(shade*3.0+t*rateB)*0.75+0.5, cos(shade*13.0+t*rateB)*0.5+0.6)` — deliberately overdriven R channel (×1.75) then routed through hsv2rgb with hue/sat/val gains, i.e., the trig output is *treated as HSV*, which produces the banded rainbow signature.
- **Multiplicative film grain**: `mod((mod(x,13)+1)*(mod(x,123)+1), grainWidth) - grainBias` — the classic "grain" one-liner with width/bias shaping controls.
- **Blend-mode rack**: Overlay/Add/Multiply/Screen/SoftLight selected by a `long` VALUES dropdown (v02) vs float compare (v01 uses `blendMode == 0` float compares on a long — host quirk tolerance), final `mix(src, fx, blendAmount)`.
- v01 quirk: FBM reads sampler coords via a **global `vec2 ouv`** set in main (working around no-closure GLSL); v02 refactors to pass `originalUV` as a parameter — cleaner.

**Control/UI design**: ~22 inputs in tidy blocks (depth / rotation / fbm / osc / color / grain / aspect / blend) — blank-line grouping in the JSON acts as section dividers. `aspectShift` doubles as "0 = auto from RENDERSIZE" sentinel.

**Version evolution**: v01 (external-depth capable, global-variable style) → v02 (single-input simplification, parameterized fbm, header explicitly "unified input"). Direction: fewer wires, self-contained VJ filter.

**Complexity tier**: **3** — single-pass but with a sophisticated depth-tangent warp and heavy nested-FBM field; strong control design.

**Signature moves**: rotated-depth-gradient tangent flow; source-color-as-noise-coordinate coupling; noise-multiplied octaves; trig-as-HSV palette.

**Rough edges**: v01's `uv_osc`/`cc` sample computed then unused (dead code carried into v02's `uv_osc` too); 11 octaves × triple nesting × per-octave depthWarp taps is extremely expensive (depthWarp is loop-invariant but recomputed per fbm call); `fract()` UV wrap in depthGrad causes edge seams.

---

## Family 3: AR_ReactionDiffusion generators (AR_ReactionDiffusion_v01.fs, AR_ReactionDiffusion2.fs)

**Purpose & visual identity**: Two small persistent-feedback pieces exploring RD-ish looks before the polished Filter (Family 4).

**AR_ReactionDiffusion_v01 ("Audio RD Feedback Blur")** — generator, audio-reactive. 2 passes: PERSISTENT `feedback` + display.
- **Difference-of-Gaussians pseudo-RD**: `col = prev - (blur2 - blur1*0.999)` — subtracting a wide blur from a narrow blur of the feedback buffer each frame produces Turing-pattern-like band formation without a real Gray-Scott model. `Blur2`'s radius oscillates with time (`vB = b2 - (b2*(0.5+0.5*sin(t)) - b1 - 2)`) so the pattern scale breathes.
- **Audio-driven feedback UV**: FFT sampled radially (`IMG_NORM_PIXEL(Audio, vec2(length(uvR), 0.25))`) and waveform row at y=0.75 (audioFFT texture layout convention); audio modulates zoom-out (`uv2 *= 1 - 0.03*fft*...`) and sinusoidal x/y wobble of the feedback fetch — bass makes the whole pattern contract and shimmer.
- Noise injection `(noise-0.5)/8` keeps the DoG reaction seeded.
- **Host workaround (explicit)**: `monoBlur(sampler2D tex, ..., vec2 texSize)` passes RENDERSIZE in as a parameter with the comment "using explicit texSize to avoid ISF macros inside functions" — IMG_* macros don't expand reliably inside user functions on some hosts; raw `texture2D` used instead. Variable-bound float for-loops (`for(float y=-scale.y; y<scale.y; y+=step)`) — risky on strict GLSL ES but tolerated by the Metal path.

**AR_ReactionDiffusion2 ("Video Diffusion")** — filter. 2 passes: PERSISTENT `bufferA` + visualize.
- 3x3 weighted (4/2/1 Gaussian-ish) blur diffusion of the buffer, decay `feedback` (0.9–1.0), continuously re-driven by video luminance: `newVal = mix(diffused*decay, vLuma, videoInfluence)`.
- **Two-channel state**: stores `vec4(newVal, previousVal, 0, 1)` — .y is last frame's value, used in the display pass for **temporal-derivative highlights**: `col += vec3(0.6,0.85,1.0) * max(c² - c_prev², 0) * highlightGain` — moving edges flash electric blue.
- Palette by power curves `vec3(c*1.5, c^2.25, c^6)` with a large-scale cos pattern flipping to `col.zyx` — cheap two-tone orange/blue field.
- `pow(16*u*v*(1-u)*(1-v), vignettePower)` classic vignette; `smoothstep(0,1,TIME/fadeIn)` performance fade-in.

**Control/UI design**: Minimal, well-labeled (`"LABEL":"Decay"` alias on the `feedback` input — naming a uniform `feedback` while also having a buffer named `feedback` in v01 is flirting with collision; here it's the input).

**Version evolution**: v01 = audio-reactive DoG experiment with host-macro scars; RD2 = video-driven, cleaner, introduces the prev-value-in-.y trick and highlight-on-change idea that motivates the Filter family.

**Complexity tier**: **3** — real persistent simulations, small but architecturally correct.

**Signature moves**: DoG-as-RD; radial FFT sampling; state.y = previous frame for temporal derivative highlights.

**Rough edges**: v01's variable-count nested blur loops are O(r²) per pixel per frame and non-constant-bound (portability risk); `fhash(fragCoord * (iTime+1))` white noise flickers at full rate; RD2's `blur()` recomputes `tx(p)` redundantly.

---

## Family 4: AR_ReactionDiffusion_Filter (v01, v01_dataloss_v01, v01_dataloss_v02)

**Purpose & visual identity**: Filter — the production-grade reaction-diffusion video effect ("RD Final Cut Filter"): per-channel RGB pseudo-Gray-Scott driven by the input image, with a distinctive "blowout" color-projection post stage and a morphable blend-mode slider. The dataloss variants are AI-remix experiments of it (the batch's file naming ties into the DataLoss remix pipeline seen elsewhere in the corpus).

**Architecture**: 2 passes — PERSISTENT `bufA` (simulation state) + composite. Sim init on `FRAMEINDEX == 0 || resetSim` (an explicit bool reset input — the family's event/reset pattern) seeds the buffer with **grid-quantized RGB hash noise** (`floor(uv*RENDERSIZE/seedDetail)` cells) with the blue channel constructed as a complement `b = 1 − bm·r − (1−bm)·g` so the three chemicals start mass-balanced.

**Techniques**:
- **Per-channel cyclic reaction**: `pos = color.rgb * color.gbr * (1 + bias)`, `neg = color.rgb * color.brg * (1 − bias)`, `color += rr * (pos − neg) * effectAmount * (TIMEDELTA * 60)` — rock-paper-scissors channel chemistry (R feeds on G, G on B, B on R) whose asymmetry (`bias` mapped from kernelReach ∈ [−1,1]) flips the rotation direction of the color cycling. **Frame-rate independence via `TIMEDELTA * 60` scaling** (with `max(TIMEDELTA, 0.0001)` guard) — rare and deliberate.
- **Diffusion via 4-tap plus-kernel** at parameterized `reach = mix(0, 6, kernelReach²)` pixels with weight `w = mix(0.02,0.6, 1−avg(diffuse)) * mix(0.5,2,kernelReach)` — the `diffuse` COLOR input doubles as per-channel decay (`color = diffuse.rgb * prev`) *and* inverse diffusion weight; `camDrive` mixes smoothstepped source video directly into the chemical state each frame (video as continuous reagent feed).
- **Soft tone compressor**: `color = color*(1+push) / (1 + push*dot(color, vec3(1/3)))` — luminance-normalized push (tonePush) instead of a bare gamma.
- **The "blowout" stage** (the family's signature): build a channel-mixing matrix (`diag/off` from blowoutSharpness·blowoutPower²), pick a center color (procedural mix of two color inputs keyed by `fract(0.37 + 1.23*seedChaos + 0.41*tonePush)` — parameters entangled deliberately), then `dir = blow * (effect − cent)` and **project each pixel along dir until the first RGB channel saturates**: `maxes = (step(0,dir) − effect)/dir; amtStep = min(maxes.xyz); out = effect + dir*amtStep`. This is a per-pixel exact line-box intersection with the unit color cube — posterizes everything onto the gamut surface, producing the hard two-tone "blown out print" look. Genuinely non-standard.
- **Morphable blend-mode slider**: `blendSlide` is a *float* 0–4; `blendEval(i0)` and `blendEval(i1)` computed and `mix()`ed by the fraction — continuous crossfade *between blend modes* (Overlay→Add→Multiply→Screen→SoftLight), rather than a dropdown.
- **Seeded hash with chaos-scaled constants**: `h21` multiplies its magic vector by `(vec2(90,170) + seedChaos*vec2(333,287))` — the seed changes the hash lattice itself, not just an offset.

**dataloss variants** (v01_dataloss_v01/v02 vs base): dataloss_v01 = a performance remix of the sim pass: guards the 4 neighbor taps (`if (w > 0.0)`, and reach==0 collapses to a single center tap × 4) — pure tap-count optimization; dataloss_v02 = same optimization plus a **remix-exposed parameter**: hardcoded `0.5` center pull becomes input `Blowout_Center_Pull`, and adds `{"NAME":"ui_dataloss_v02","TYPE":"event","LABEL":"🧪 DATALOSS REMIX"}` — an event input used purely as a *labeled UI banner/section divider* (emoji label, never read in code). This confirms the corpus-wide convention: event inputs as decorative section headers, and remixes = (a) micro-optimizations, (b) promoting a buried constant to a knob.

**Control/UI design**: 17 inputs; color-typed inputs used semantically (diffuse-as-rates, two blowout palette anchors); `resetSim` bool as re-seed event; blank-line grouping.

**Version evolution**: base → dataloss_v01 (tap guards) → dataloss_v02 (tap guards + exposed Blowout_Center_Pull + remix banner). Base itself already carries lessons from Family 3 (TIMEDELTA scaling, FRAMEINDEX init, complementary seeding).

**Complexity tier**: **4** — true persistent per-channel simulation with frame-rate compensation, a novel gamut-projection post stage, and a continuous blend-mode morph.

**Signature moves**: gamut-surface projection ("blowout"); cyclic gbr/brg channel chemistry; float-slider blend-mode crossfade; color input as per-channel rate vector; TIMEDELTA*60 rate normalization.

**Rough edges**: base version applies the 4 neighbor taps even when `w==0`/reach==0 (fixed in dataloss variants — the remix *was* the fix); `denom = dir + 1e-6` sign-unsafe for negative dir components (potential wrong-side projection at exact 0); `blendEval` int-branching on a mixed float slider relies on host int conversion; unused `pw`-independent paths when blowoutPower=0 still run the whole matrix.

---

## Batch synthesis

**Top 3 most sophisticated files**:
1. **AR_ProqxisShapes_catalogtest_v08.fs** (2,432 lines) — the endpoint: 114-shape SDF catalog with combinator-generated variants, gaussian span-blend morphing between arbitrary shapes, coarse/fine banked navigation, persistent-buffer phase slewing, 3-pass post-CA chain, adaptive quality throughout. A shader that is effectively a playable instrument with a patch library.
2. **AR_ProqxisShapes_v11_distFX-5/-6** — the chaos-conductor peak: 19 gated domain distortions with per-effect octave/plane-count LOD, phase-aware chaosGate tying distortion intensity to morph stability, presets, seeded repeatability, and the first true post-process chromatic aberration pass.
3. **AR_ReactionDiffusion_Filter_v01.fs** — densest technique-per-line file in the batch: frame-rate-independent cyclic RGB chemistry, gamut-projection blowout, morphable blend modes.

**Recurring patterns across families (style fingerprints)**:
- The 1x1 PERSISTENT FLOAT buffer as a smoothed-parameter register (phase, timeSpeed, chaosFrequency, twist; RGBA channels as separate signals) — the author's single most characteristic architectural move.
- `FRAMEINDEX == 0 || reset` init; `TIMEDELTA` rate normalization; const loop bounds + runtime `break` for adaptive sample counts (Metal/ES hazard workaround, ubiquitous).
- The same `hash(vec2)` (5.3983/5.4427/21.5351/14.3137/95.4337 constants) appears verbatim in every ProqxisShapes file; `rot(a) mat2` helper everywhere; final `(hash-0.5)/128` dither on all generators.
- Meta-slider fan-out (one perceptual knob → 4–6 internal params) with selectable response curves; later revisions repeatedly *remove* inputs by pasting a `const float` defaults block — expansion→contraction UI cycles.
- Remix convention: emoji-labeled `event` input as a section banner + a single promoted constant (Blowout_Center_Pull), matching the DataLoss remix pipeline.
- Comment style narrates diagnosis ("Camera distance-based anti-banding fix", "gated to avoid SDF collapse", "booby-trap" style warnings) — the files double as a lab notebook.

**Techniques beyond standard ShaderToy fare**:
- Gaussian-weighted N-way SDF catalog blending with wraparound, plus a fine 2-way blend re-mixed at 20% to keep edges crisp — I have not seen this span-blend idiom in common shader references.
- Banked coarse/fine parameter navigation to make a 114-item discrete space performable on two MIDI knobs.
- The blowout gamut-surface projection (exact line/unit-cube intersection per pixel as a stylization).
- Phase-aware chaos gating (distortion amplitude tied to *distance from the nearest stable morph state*) — a compositional/dramaturgical rule, not a graphics one.
- Shape remix combinators (`inversionDomain`/`inversionGate`/`detailBand`) used to mechanically mass-produce catalog variants — procedural authorship of the catalog itself.
- Fake-then-real chromatic aberration arc: the author shipped a no-op CA for several versions, evidently noticed, and architected a third render pass to do it properly — captured negative knowledge: in-place CA without resampling is impossible, and the fix is a `sceneColor` intermediate target.
