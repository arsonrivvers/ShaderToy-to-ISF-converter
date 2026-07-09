All 40 files were read in full before the interruption. Here is the complete report.

# Batch 19 Analysis Report — /Library/Graphics/ISF

## Coverage
- files_assigned: 40, files_read: 40, misses: none

---

## Family: AR_Mini_Dispersion_SH17A (1 file)

**Purpose & visual identity**: Filter. Chromatic-dispersion/prism lens effect: a weighted multi-tap dispersion blur whose displacement vectors swirl around a movable focus point, with a smoothstep-feathered circular mask blending back to the unprocessed source.

**Architecture**: Single pass, two image inputs (displacement map `iChannel0` + source `iChannel1`). No buffers.

**Techniques**:
- **Spectral-weight dispersion loop**: iterates `i` 0→1 in `1/loopQuality` steps; each tap builds a pseudo-spectral weight `p = vec4(i, gradientPeak*pow((1-i)*i, gradientTightness), 1-i, 1)` (R ramps up, B ramps down, G peaks mid via a beta-like curve) and accumulates `weightedSample = p*p` × sample, normalized by `sum(p*p) + 0.0001`. This is a tunable-spectrum chromatic aberration — the "gradient peak/tightness" knobs shape the virtual spectrum.
- **Dual displacement source**: procedural `noiseAmount * pow(sin(uv*freq + speed*TIME), vec2(3.0))` (cubed sine = sparse spikes) summed with texture-driven `(IMG_NORM_PIXEL(dispMap, mod(uv + 0.1*TIME,1)).xy - 0.5)`.
- **Distance-proportional rotation of the displacement vector**: `rotationAngle = dist * prismRotation`, mat2 rotation applied to the combined displacement — this makes dispersion "swirl" around the focus rather than radiate.
- **Focus mask**: `mask = smoothstep(focusSize, focusSize+focusFeather, dist)`; `mix(original, processed, mask)` — clean/effect split by radius.

**Control/UI design**: 15 inputs, flat list, human-readable LABELs, coarse concept knobs (Focus X/Y, Prism Rotation) + quality knob (`loopQuality` 5–100 exposed as a float — user-facing performance dial). No sections/macros yet — this is the earlier control style.

**Version evolution**: single file ("SH17A" suffix suggests a Shadertoy-hour/series index). Comments explicitly mark "--- NEW: ---" blocks over a prior "smooth dispersion" base — the author's habit of layering one new feature per revision and marking it inline.

**Complexity tier**: 2 — single pass but a nontrivial weighted-spectrum loop and composed displacement fields.

**Signature moves**: the beta-curve spectral weight `gradientPeak*pow((1-i)*i, tightness)` as a user-shapeable dispersion spectrum; per-pixel rotation matrix scaled by distance-to-focus.

**Rough edges**: `mod(displacedUV, 1.0)` wrap can pull opposite-edge pixels into the blur; epsilon-normalization idiom (`+0.0001`) rather than max().

---

## Family: AR_MirrorFeedback_system v01–v03 (3 files)

**Purpose & visual identity**: Filter. The most ambitious feedback engine in the batch: a video-feedback "instrument" with inject → advect → shade pipeline; v03 grows into a five-pass dual-buffer simulation system with a velocity field, scenes, and a musical timebase. This is the flagship family of the batch.

**Architecture**:
- v01/v02: 2 passes — `BufferA` PERSISTENT+FLOAT accumulator + display pass. Dispatch: `if (PASSINDEX == 0) passAccumulate(uv); else passDisplay(uv);` with named per-pass functions.
- v03: **5 passes, 4 persistent float buffers** — `BufferV` (persistent velocity field, stored as `v*0.5+0.5` in RG), `BufferA` (structure/feedback accumulator), `BufferB` (detail/edge-glow layer), `BufferPrev` (previous *source* frame for motion detection), plus display. This is a hand-rolled semi-Lagrangian advection system inside ISF.

**Techniques**:
- **"Lineage-locked" evolve slider** (v01 DESCRIPTION): `evolve=0` reproduces the original legacy shader's math (with a stability fix), `evolve=1` enables the full evolved pipeline; every new feature is scaled by `evo` so the old look is a preserved endpoint, not overwritten. A remarkable versioning-inside-the-shader discipline:
  ```glsl
  vec3 result = mix(originalColor, evolvedColor, evo);
  float effTone = mix(0.2, toneMap, evo); // even at evo=0, mild soft clip (stability fix)
  ```
- **Curl noise advection**: rotated finite-difference gradient of value noise, `vec2(ny-n, -(nx-n))/eps` — divergence-free flow used to warp the feedback read UV.
- **Edge-guided flow**: 4-tap luma gradient of the *source*, then flow along the edge (perpendicular to gradient): `edgeFlow = vec2(-grad.y, grad.x)` — trails hug the contours of the input video.
- **Domain-warped noise** (noise fed its own output twice) as a third flow field.
- **Luma/chroma split feedback**: converts to a YUV-ish space (`vec3(luma, r-luma, b-luma)`); luma gets `decay*lumaPersist` (structure/trails), chroma gets `decay*0.98` (decays slightly faster → "cleaner trails"), and chroma is rotated by a 2D rotation matrix (`driftAngle` from time + source energy) — hue drift is literally chroma-plane rotation.
- **Stabilized legacy singularity**: the original math divided by `self - facMod`; v01+ replaces it with `safeDenom = sign(denom)*max(abs(denom), 0.01)` and clamps to ±6 ("tighter than original [-10,10]") — a documented taming of a chaotic divide.
- **Chromatic aberration + diffusion combined sampler**: R pushed outward / B pulled inward along `normalize(uv-0.5)`, each channel through a 5-tap center-weighted box blur (0.5/0.125×4).
- **Cosine hue basis**: `huecol(h) = vec3(cos h, cos(h+2.094), cos(h+4.189))` (2π/3 offsets) multiplied against feedback energy.
- **Soft-clip tone map**: `mix(clamp(x,-1.5,1.5), tanh(x*1.2), amount)` with a hand-rolled `tanh` via `exp` (GLSL-ES safe); v02 hardens it to `safeTanh` with input clamp ±8 (exp overflow guard on Metal).
- **v03 velocity pass**: persistent velocity integrates curl + edge impulse + noise forces with viscosity multiply and an explicit speed limiter `if (vl > vlim) v *= vlim/vl` — a real (if simplified) momentum fluid.
- **v03 anisotropic smear**: 5 taps along the velocity direction (0.46/0.18×2/0.09×2) — motion-blur-like advection sampling for both A and B buffers (duplicated per buffer because ISF can't pass sampler handles).
- **v03 reaction-diffusion mode**: logistic-growth RD hybrid on the accumulator: `upd = x + lap*(rdDiff*rd*1.5) + x*(1-x)*(rdGain*rd*0.8) - x*(1-effDecay)*0.7` using `blur5 - self` as the Laplacian.
- **v03 injection modes**: 4 keying modes (Luma/Edge/Chroma-saturation/Motion vs BufferPrev) each through a shared `gateCurve` = tanh sigmoid with bias/sharpness knobs.
- **v03 SDF region modulation**: the SDF (circle/box/diamond, wobbled by domain-warp noise) doesn't just mask — it *modulates parameters spatially*: decay ×(1.15→0.80), inject ×(0.75→1.35), diffusion ×(1.25→0.65) across the shape boundary, so the interior behaves like a different "chemistry".
- **v03 musical timebase**: `qTime()` quantizes TIME into N steps (4/8/16/32) with swing (odd/even step split point shifted by `sw*0.45`), blended with continuous time by `rate` — VJ-oriented tempo-quantized animation.
- **v03 detail-preserving limiter**: `k = 1/(1 + max(0,peak-thr)*(2+6*soft)); c*k` — ratio-style compression on the max channel instead of a hard clamp.
- **v03 spectral phosphor**: two chroma-rotated copies at angles derived from accumulated energy × `spectralTension`, averaged back in — energy-dependent color splitting.

**Control/UI design**: The house style crystallizes here: **label-type section dividers** `{"LABEL":"── FEEDBACK ──────────────","NAME":"_fb_label","TYPE":"label"}` with underscore-prefixed names; **META macro trio** `evolve` / `intensity` / `stability` — three conductor knobs where `intensity` multiplies inject+flow, `stability` biases decay up and damps inject/flow/chroma/hueDrift (`stabDamp = mix(1.0, 0.55, stab*evo)`) — a "make it safe" knob. v03 adds a **scene system**: `scene` long (Lineage/Liquid/Crystal/Cellular/Architect) + `sceneMorph` + `sceneAmount`, where `scenePreset()` outputs 9 multipliers over the manual params and morphs between adjacent presets — presets as *multipliers over*, not replacements of, manual settings. Sections in v03: META / SCENES / FEEDBACK / FLOW AND GEOMETRY / SDF REGION / INJECTION MODES / COLOR AND LIGHT / SPECTRAL PHOSPHOR / CELLULAR / TIMEBASE / LIMITER / LEGACY WARP. 25 inputs (v01) → 40 (v03).

**Version evolution**:
- v01→v02: pure hardening pass, near-identical structure: `myTanh` → `safeTanh` (clamp ±8), keyMask dot-product normalized by weight sum (v01's raw `dot(src, w)` could exceed 1), chroma direction normalize guarded with `max(length,0.001)` instead of `normalize(x+0.001)`, `fac *= max(0.0,intensity)`, stability now also damps inject/flow/chroma/hueDrift. The author ships a feature version, then immediately ships a numerical-safety version.
- v02→v03: architectural leap — persistent velocity buffer, dual accumulators (structure + detail/edge layer composited at display via `detailMix`), BufferPrev motion keying, scenes, timebase, limiter, RD mode. Label style changes from box-drawing `──` dividers to plain-text (`"LABEL": "META"`), and code compresses to one-line helper style — possibly reformatted through a different tool/model.

**Complexity tier**: 5 (v03) — multi-pass simulation with persistent velocity, conductor controls, scene morphing, and a musical clock. v01/v02 are tier 4.

**Signature moves**: evolve-slider lineage locking; stability as a global damping conductor; SDF-as-parameter-field (not mask); chroma-plane rotation for hue drift; scene presets as multiplier sets with morph; swing-quantized timebase.

**Rough edges**: v03 `applyScenes` scene-neighbor clamp `if (s0+1 < 4) s1 = s0+1; else s1 = 4;` — written as if/else rather than min(), and scene 4 morphs to itself; `shapeA` is computed from `shapeMask*evo` in the velocity pass but never used there (dead code); B-buffer `detail = edge*(0.6+0.8*glow)` is a vec3 from scalar-ish math that leans on implicit broadcasts; LEGACY section persists across all three versions as protected namespace; duplicated blur5A/blur5B and sampleAnisoA/B because ISF buffers can't be parameterized — accepted boilerplate cost.

---

## Family: AR_Mosaic4Shatteredstrobe_v01 (1 file)

**Purpose & visual identity**: Filter/hybrid. A converted Shadertoy (l3fGDf, credited to "420bongrips247365") — self-healing voronoi particles advected by a compact fluid solver, modified so video-input luma gradients inject force; audio input colors the render.

**Architecture**: 4 passes: BufferA (fluid update, PERSISTENT+FLOAT), BufferB (particle state, PERSISTENT+FLOAT), BufferD (fluid copy, PERSISTENT+FLOAT), final render. Classic Shadertoy ping-pong emulated with two fluid buffers (A reads D, D reads A) because ISF persistent buffers can't self-read from a previous pass in the same frame chain.

**Techniques**:
- **Compact 4-neighbor fluid**: `FluidInteract` does combined pressure projection & advection using positions `V0 = V - u`, `V1 = V + u` and pressure `P` in `.z`; per-frame two applications (pass 0 and pass 2) gives 2 solver iterations.
- **Self-healing particle tracking**: `ParticleSwap` compares distance of neighboring particle records to their home cells and probabilistically adopts the neighbor: `Q = mix(Q, p_neighbor, 0.5+0.5*sign(floor(1e5*dl)))` — a voronoi-tracking trick where particles "reproduce" into cells that lost theirs.
- **Video force injection** (author's modification): central-difference luma gradient of `videoInput` scaled ×5.0 added to fluid velocity — bright edges of the video stir the fluid.
- **Audio-modulated coloring**: particle payload `.zw` indexes into the audio texture (`texture2D(iChannel2, vec2(abs(0.3*w),0))`), and base color is a phase-offset sine `0.5-0.5*-sin(...z*vec4(1) + ...w*vec4(1,3,5,4))` — audio warps the color phase per particle lineage.
- `FRAMEINDEX < 1` initialization (grid seed `floor(fragCoord/10+0.5)*-10`) and explicit border zeroing for boundary conditions.
- Duplicated helper functions per buffer (`FluidInteract_ReadBufferD` / `..._ReadBufferA`) — the ISF no-sampler-args workaround, with a comment noting helpers were hoisted to global scope (Metal disallows nested functions).

**Control/UI design**: minimal — just `videoInput` + audio. Hardcoded five jet positions/colors kept from the original ("kept for now"); mouse interaction commented out rather than deleted.

**Version evolution**: v01 only; the commented-out mouse code and "maybe redundant?" notes show mid-adoption state.

**Complexity tier**: 4 — real multi-buffer particle/fluid simulation, though mostly inherited; the author's contribution is the I/O rewiring.

**Signature moves**: probabilistic particle reproduction line; video-gradient-as-body-force.

**Rough edges**: uses raw `texture2D(Buffer, U/R)` instead of IMG_ macros; pass 0 and pass 2 duplicate the jet block ("same as Pass 0, maybe redundant?"); BufferB advection reads velocity at unclamped particle coords; conversion scars (renamed locals `R_local`, `N_local`, `P_calc` to dodge param collisions).

---

## Family: ArsonRivvers_MoshedFeedback_v01 (1 file)

**Purpose & visual identity**: Filter. Datamosh emulation via optical-flow-ish motion masks: pixels get dragged along estimated motion vectors, with random block freezing, radial chromatic aberration, and feedback blending. Signed by full email — an identity piece.

**Architecture**: 4 passes: `maskBuffer` (persistent, **half resolution** `$WIDTH/2.0 × $HEIGHT/2.0`) — motion vector estimate; `delayBuffer` (persistent, half-res) — one-frame delayed copy of `motionImage`; `feedbackBuffer` (persistent, full-res) — the moshed result; final display via `IMG_THIS_PIXEL(feedbackBuffer)`. NOTE: uses lowercase `"persistent": true` (works in VDMX; a known host-tolerance detail).

**Techniques**:
- **Gradient-based optical flow**: current-vs-delayed luma difference `curdif = b - a`, spatial gradients of both delay and motion images at ±0.5-texel offsets, then `v = curdif * (grad/gradmag)` — a one-iteration Horn–Schunck-ish estimate. Positive/negative parts are split into separate channels: `xout = vec2(max(vxd,0), abs(min(vxd,0)))` so the mask stores 4 unsigned components (x+, x−, y+, y−) in RGBA — a clever signed-vector-in-unsigned-buffer encoding.
- **3×3 Gaussian temporal smear of the mask**: full 9-tap kernel (1-2-1/2-4-2/1-2-1)/16 blended by `feedback` back into the mask (`mask + blurVector*feedback`) — motion vectors accumulate and diffuse over time = the "mosh drag".
- **Two-frame delay chain**: pass 1 just writes `motionImage` into `delayBuffer` (after pass 0 read the *previous* frame's copy) — the ISF idiom for frame delay.
- **Per-pixel block freeze**: hash `fract(sin(dot(uv*RENDERSIZE + randomSeed, vec2(12.9898,78.233)))*43758.5453) < freezeProbability` → output frozen feedbackBuffer pixel — I-frame-removal glitch.
- **Radial 3-ring chromatic aberration**: R/G/B offsets at 1.5/1.0/0.5 × scale along `normalize(uv - center)`.
- Displacement composition: `uv + blurAmount(decoded vectors) * feedback * (1-originalMotion) * displacementIntensity` plus animated sine noise wobble.

**Control/UI design**: 10 inputs, flat, no sections (earlier era than MirrorFeedback); `randomSeed` 0–1000 float for scrubbing freeze patterns; bool `invertMotion`.

**Complexity tier**: 4 — genuine motion-estimation multi-pass system with resolution tricks (half-res motion pass = cost-aware).

**Signature moves**: signed-flow-in-RGBA encoding; half-res persistent analysis buffers; freeze-probability blocks.

**Rough edges**: `gradmag` can be zero → division NaN (no epsilon); `coeffs` multiply then averaging via `(r+g+b)/3` double-weights luma oddly; unused `lefta/righta/leftb/rightb` coords computed... (actually used in blur) — fine; mixed `persistent` casing.

---

## Family: AR_MotionBlur_trip_v01 (1 file)

**Purpose & visual identity**: Filter. Converted Shadertoy (Xsc3DS "Motion blur on a video") lightly parameterized: sine-modulated 4-tap feedback blur that produces smearing "trip" trails with a green-channel suppression keying trick.

**Architecture**: 2 passes: BufferA PERSISTENT+FLOAT accumulator + copy-out.

**Techniques**:
- **Green-difference keying**: `newG = min(tex.g, max(tex.r, tex.b)); d = abs(tex.g - newG)` — how far green exceeds both other channels (a greenscreen-ish energy measure) drives where the blur appears via `smoothstep(-0.3, effectThreshold, d)`.
- **Time/space-modulated tap offsets**: `px *= sin(TIME*speed + uv.yx*3.0) * blurAmount` — the blur kernel size oscillates per-pixel (note `uv.yx` swizzle: x-phase driven by y and vice versa).
- **`1.13 * normalize(tex2)`** on the first feedback tap — normalizes the accumulated color vector to constant "chroma energy" then rescales: prevents feedback fade-to-grey and forces saturated trails. Unusual, load-bearing.
- **Zoom feedback**: `uv = (uv-0.5)*feedbackIntensity + 0.5` with feedbackIntensity ~1.001 — classic infinite-zoom trail, exposed with a very tight MIN/MAX (0.99–1.02) showing tuned sensitivity awareness.
- Final `max(clamp(tex*(1-d)...), mix(tex, tex2, smoothstep(...)))` — max-combine keeps source visible under trails (relates to the max(prev*decay, current) house pattern).

**Control/UI design**: 5 added floats with careful narrow ranges around known-good defaults (e.g. feedback 0.99–1.02, default 1.001). Parameterizing a conversion = the author's standard adoption move.

**Complexity tier**: 2.

**Signature moves**: normalize()-based trail saturation lock; narrow "safety-rail" slider ranges around chaos-sensitive parameters.

**Rough edges**: `tex2 /= 4.013` magic constant; retained original's weird constants (0.0008/0.0005 drift) unparameterized.

---

## Family: AR_Mozaic_V01 (1 file)

**Purpose & visual identity**: Filter. Adaptive quadtree mosaic (adapted from ciphrd's Shadertoy): image subdivides into quads where color variance is high — a stylized detail-adaptive pixelation.

**Architecture**: single pass.

**Techniques**:
- **Stochastic variance estimation per quad**: 55 random samples (`hash22` jitter around quad center) accumulate mean and E[x²]; variance = `E[x²] − mean²`; scalar variance = channel average.
- **Iterative subdivision in-shader**: loop up to `maxIterations`; if variance > threshold, `divs *= 2`, recompute quad center/size — each pixel independently walks down the quadtree to its final cell. `const`-bound loop (`SAMPLES_PER_ITERATION 55`) with runtime `break` on the outer loop = the documented Metal-safe loop idiom (`for (int i = 0; i < int(maxIterations); i++)` — note this one is actually a runtime bound; a host-quirk risk the author usually avoids).
- **Grid line overlay**: `smoothstep(0.5 - pixelWidth*divs, 0.5, abs(fract(uv*divs)-0.5))`, opacity-mixed — cell borders drawn at the *final* subdivision level so line density visualizes detail.
- `colorMix` blends quad average color vs original pixel color.

**Control/UI design**: 5 floats + image; simple flat list; float used for what are semantically ints (minDivisions/maxIterations) — ISF-float-everything habit.

**Complexity tier**: 2–3 — single pass but an O(iterations×55) sampling loop with real statistics.

**Signature moves**: per-pixel independent quadtree descent; variance-driven LOD.

**Rough edges**: `samplesBuffer[55]` array in registers is heavy; `int(maxIterations)` as a loop bound may fail on strict GLSL-ES hosts (non-const), a rare deviation from the author's own rule.

---

## Family: AR_MSFT_Build v01–v04 + AR_MSFT_DigiBrute_01 (5 files)

(One design lineage: "BUILD" CMYK print-glitch. DigiBrute is the image-filter cousin; Build v02–v04 are generators with procedural typography. The MSFT prefix marks a commissioned/branded series — Microsoft event visuals.)

**Purpose & visual identity**: Subtractive CMYK misprint aesthetic — paper white base, cyan/magenta/yellow "ink plates" multiplied on with per-plate misregistration, halftone dot fields, paper folds, grain, streaks. v01 is a filter on any input; v02+ require/synthesize a "BUILD" text mask; DigiBrute is the input-image version with column tearing.

**Architecture**: all single-pass generators/filters. No buffers — this family is about layered 2D composition, not feedback.

**Techniques**:
- **Subtractive ink model**: `applyInk(base, inkRGB, mask, op) = base * mix(vec3(1), inkRGB, sat(mask*op))` — inks multiply (subtract light) instead of adding; plate overlap darkening via `overlap = min(cM, min(mM, yM))` → rich-black boost. Ink density from luma inversion in v01: `ink = 1 - (r+g+b)/3`, masked-typography plates in v02+.
- **Row-quantized displacement**: `rowIdx = floor(uv.y * block_size_y)`, hash per row, then **quantized to discrete steps**: `q = floor(((rowRand*2-1)*steps))/steps; rowOff = q*displacement_amount` — the tearing is stair-stepped, not continuous (deliberate digital-brutalist quantization).
- **Procedural block-letter typography** (v02/v03): letters B,U,I,L,D built from `rect01` unions minus hole rects inside a 5-cell layout (`buildMaskProc`) — a full text renderer in ~80 lines, with `use_texture_text` bool to override with a texture mask.
- **Mask erosion for the key plate**: `erodeMask` = min of 5 samples offset by `key_inset` — shrinks the text for the black "key" plate inset inside the color plates (real print-registration behavior).
- **Plate-specific Y shifts**: cY/mY/yY multipliers of `plate_shift_y` (v04 adds fixed sub-offsets +0.0015/−0.0005/−0.0010) — per-plate vertical misregistration.
- **Grid snap**: `snapUV(uv, snapSteps, amt) = mix(uv, floor(uv*snap)/snap, amt)` where snapSteps derives from resolution (`res.x/10, res.y/40`) — everything optionally snaps to a coarse device grid.
- **Fragmentation evolution**: v02 `blockFrag` (per-cell random keep/cut of mask), v03 → `slabify`: samples the mask at *cell centers* on two grid scales (fine cells + 0.35× coarse cells randomly re-added) so letters shatter into slabs rather than pixel dust; plus `edgeOnlyJitter` (v03): threshold jitter applied only on the mask edge band (`edge = sat(m - eroded)`), keeping letter interiors solid.
- **Fold/crease shading**: `foldOne` gaussian `exp(-t²)` highlight/shadow pair with asymmetry sign trick `(t >= 0.0) ? 1.0 : -1.0` (scalar ternary — allowed; the author avoids only vector ternaries).
- **Dot/dash halftone field**: `dotDashField` fract-grid with `halfW = mix(0.45, 0.05, fill)` and aspect-scaled height; v03 hardens with `step` instead of smoothstep.
- **Vertical bar streaks**: per-column hash gating (`step(1-density, r0)`) × pow-hardened profile × random vertical extent (v03 `verticalBars` gives bars random y0/height) — printed "roller streak" artifacts, injected into the ink masks via `max`.
- **Debug modes**: `debug_mode` long 0–6 routes intermediate masks (rowRand, bars, offset, dots, textM, plate RGB) straight to output with early `return` — an in-shader inspector, rare in VJ code and a strong house signature.
- **DigiBrute**: column-quantized `columnID = floor(uv.x * GRID_Density * aspect)` vertical tearing with per-column hash, ±CHROMA on Y for plate separation, luma-matte compositing of glitched "ink" over a procedural paper+dot background, `fwidth`-AA dots.

**Control/UI design**: v02–v04 carry **~40 inputs** in strict thematic blocks (text / blocks / plates / fragments / paper / inks / dots / print region / creases / grain / streaks / debug), snake_case names (`block_size_y`, `rich_black_boost`) — different naming convention from the camelCase feedback family, suggesting per-project conventions. `paper_color` uses TYPE color. No label dividers here — ordering + prefixes do the grouping. DigiBrute uses UPPERCASE_prefix names (`GRID_Density`, `TEAR_Amp`) with "SECTION: Name" labels.

**Version evolution**: v01 (filter, luma-ink from arbitrary input, hardcoded folds) → v02 (generator: procedural BUILD letters, jittered masks, blockFrag fragmentation, ink saturation control) → v03 ("clean key plate, slab quantization plates, structured vertical bars": key plate no longer jittered/fragmented — stays legible; slabify replaces blockFrag; bars become structured elements injected into plates; grain becomes multiplicative `col*(1+g*0.2)` instead of additive; defaults retuned: noise_rate 0.25→0.10, edge_jitter 0.22→0.10) → v04 (back to texture-mask-first "Requires a text mask input", CREDIT "Reformatte HQ", simplified: no slabify/bars-in-plates, per-plate fixed misregistration constants). The trajectory: filter → self-contained generator → art-directed refinement (legibility of key plate, structure over noise) → production tool for real typography.

**Complexity tier**: 3 — single-pass but deep layered composition systems with dozens of interacting masks.

**Signature moves**: multiplicative ink compositing; quantized (stepped) displacement; slab-center mask sampling; edge-only jitter; debug-mode router; procedural rect-letterforms.

**Rough edges**: v02 declares `fragment_*` inputs used only from v02 on but v01 also declares them unused (dead inputs in v01); `letterI` renders full-width serif bars that overlap adjacent cells' margins visually; several sat() wrappers on already-bounded values; DigiBrute credits "Gemini" (LLM-assisted authorship openly recorded in CREDIT fields across this family: "Gemini", "Gemini Hybrid", "Gemini Hybrid / Arson Rivvers" — the credit evolves as the author takes ownership).

---

## Family: AR_MSFT_MIT v01–v16 (16 files)

**Purpose & visual identity**: Generator. The longest visible learning trajectory in the batch: recreating the 1979 MIT Lincoln Laboratory CRT "data blob" aesthetic (quantized noise heatmaps on a Trinitron-style tube). Ends as a full "studio master" CRT composition instrument.

**Architecture**: every version single-pass. Complexity grows in the *layering and control surface*, never in passes — a deliberate choice (static backgrounds/compositions don't need feedback).

**Techniques** (accumulated across the series):
- **Quantize-then-sample**: the core insight, stated in comments — snap UV to a grid *before* sampling smooth noise (`gridUV = floor(uv*gridRes)/gridRes; n = noise(gridUV*scale + t)`), producing hard rectangular "data blocks" whose *values* flow smoothly. "Pixelation of Gradient."
- **CRT barrel distortion**: `f = 1.0 + distortion*r2; distortedUV = centered*f + 0.5` with hard black bezel early-return outside [0,1].
- **Banded palette via stacked smoothsteps**: 4 anchor colors (ink black → deep teal → electric cyan → hot white), three `smoothstep` gates mixed sequentially; band width evolves: hardcoded → `Band_Sharpness` mapped `w = mix(0.2, 0.001, sharpness)` (v11) → direct `Band_Width` input (v13+). Also an IQ cosine palette engine (v04) and 4 tuned theme vectors (v05: Thermal/Swiss/Cyber/Deep Data).
- **Domain warping** (v05): full IQ two-level fbm warp `pattern(p) = fbm(p + 4.0*r)` with q/r out-params, and the q vector reused to displace the aperture grille (`shift = q.x*0.02`) for moiré interference — cross-coupling content into the "physical screen" layer.
- **Trinitron aperture grille**: vertical `sin(uv.x * density * PI)` sharpened by smoothstep; evolves into a **subpixel RGB phosphor triad mask** (v07): three cosines at 2π/3 phase offsets, `pow(mask, 1 + hardness*20)` for black-crush gaps, re-normalized by luma (`mask /= max(0.1, dot(mask, vec3(0.333)))` v07, later `mask /= 0.3`).
- **Beam growth** (v15/v16): mask sharpness *decreases with pixel brightness* — `growth = clamp(intensity*Beam_Growth, 0, 0.9); sharpness *= (1-growth)` with gain compensation — bright pixels physically widen and "eat the grid", a genuinely physical CRT behavior rarely modeled:
  ```glsl
  float growth = clamp(intensity * Beam_Growth, 0.0, 0.9);
  float sharpness = (1.0 + Mask_Hardness * 20.0) * (1.0 - growth);
  mask /= max(0.1, 0.3 * (1.0 - growth * 0.5));
  ```
- **Interlace jitter** (v08): every-other-scanline horizontal offset `jitter = (mod(floor(uv.y*RENDERSIZE.y/2),2)-0.5)*2*Interlace_Jitter` applied to the *signal* UV only, with the explicit principle documented: "The mask is the physical screen; it doesn't jitter. The signal jitters *under* it."
- **Signal bleed / H-smear** (v08): each RGB channel = mix of its sample and a left-offset trail sample — phosphor decay smear, per-channel.
- **Luminance-inverse colored static**: `noiseStrength = Static_Amt*(1.2 - luminance)` with a 3-channel hash — dark areas get more colorful noise (SNR simulation).
- **V-Hold slip** (v10): time-scrolling Y plus chunked shear `shear * step(0.9, fract(y*10))` — rolling-picture tracking error.
- **Phosphor burn** (v10): `burnColor = max(0, signal-0.8)*Phosphor_Burn*2` added with orange tint `vec3(1.0,0.5,0.0)` — overdriven whites bloom warm.
- **Threshold bloom**: `if (luma > Bloom_Thresh) col += col*gain` — cheap halation, kept through all 16 versions.
- **Full grading rack** (v13–v16): rgb2hsv/hsv2rgb hue+sat, per-gun R/G/B drive, black lift (`mix(c, vec3(1), lift*0.2)` haze + `max(vec3(lift), c)` floor), gamma, master brightness/contrast pivot at 0.5 — a color-corrector bolted onto a generator.

**Control/UI design**: the "SECTION: Name" label convention is born and standardized here: `"LABEL": "DATA: Resolution"`, `CRT:`, `SIGNAL:`, `POST:`, `NOISE:`, `COLOR:`, `GUNS:`, `TONE:`, `MASTER:`, `OPTICS:`, `ANIM:` — namespaced flat controls instead of divider rows. Input count: 7 (v01) → 27 (v16). PascalCase_underscore names (`Grid_Res`, `Mask_Hardness`). Seed/Pan/Offset controls (v11+) mark the shift from animation toy to *composition tool* ("Optimized for static background generation with manual noise placement").

**Version evolution** (the clearest learning record in the corpus):
- v01: simplex-noise blob + heatmap if/else palette + vertical grille + bloom + subtle CA.
- v02: discrete random "data states" per cell (hash, ticked time `floor(TIME*speed*10)`), per-channel grid sampling for CA, vignette.
- v03: back to organic Perlin through the grid ("Blob forced into a grid"), tuned burgundy/red palette.
- v04: procedural cosine-palette engine + palette quantization/banding + brightness-aware grille blending.
- v05: domain-warping "liquid" engine, anamorphic X/Y grid ("Barcode"), 4 color themes, grille moiré displacement.
- v06: consolidation — value-noise 2-layer signal, smoothstep-band palette (the keeper), named "Gemini Hybrid / Arson Rivvers" from here on.
- v07: subpixel RGB phosphor triad mask + horizontal scanlines + normalized mask brightness.
- v08: interlace jitter, per-channel signal bleed, colored SNR static, hard mask; signal-vs-screen separation principle documented.
- v09: adds Mask_Opacity + reinstates scanline control (v08 dropped it) — a "make everything optional" pass.
- v10: rectangular cells via Block_Aspect (`vec2(Grid_Res/Block_Aspect, Grid_Res)`), V-Hold slip, hum bars, phosphor burn.
- v11: **subtraction as design** — "Removed Hum Bars and Curvature for a flat, stable, textured look"; flat projection (`distortedUV = uv`).
- v12: composition tool — noise pan/seed/zoom, Band_Sharpness, Flow_Speed defaulting to 0 (static by default).
- v13: "Ultimate" — grading rack (hue/sat/guns/lift/gamma), palette cycle, Signal_Contrast crunching the noise field pre-palette.
- v14: "Director's Cut v2: Zero hardcoded values" — Band_Width, Scanline_Thick, Bloom_Intensity all exposed, Detail_Opacity for the second noise layer, vignette removed; burn moved *before* mask and tint desaturation-linked.
- v15: Beam Growth physics (brightness-adaptive mask).
- v16: "Studio Master" — Master brightness/contrast/gamma/sat rack, boosted distance-weighted CA (`shift = Color_Shift*(1+dist*5)`), Grid_Res default drops 42→16 (bigger blocks — final art direction), grading reordered pre-CRT.
- Meta-pattern: add → measure against reference photos (v05 mentions "Reference 14.58.58" screenshot filenames) → subtract → expose → harden. Ends with everything parameterized and nothing hardcoded — the author's explicit end-state goal.

**Complexity tier**: 3 for any single file (single pass), but the *system* (16-step refinement, 27-control instrument) is tier 4 as a product.

**Signature moves**: quantize-before-sample; signal/screen layer separation; beam-growth mask; luminance-inverse static; "SECTION: Name" label namespacing; zero-hardcoded-values doctrine; iterative art direction against reference screenshots.

**Rough edges**: hash reuse with two identical functions under different names (v02 `hash`/`randomNoise`); v08's dropped Scanline control restored in v09 (feature regression across versions); `mask /= 0.3` fixed gain vs v07's adaptive normalize (brightness inconsistency accepted); persistent `if (bright > thresh)` branch bloom (branchy but cheap); duplicated ~150-line JSON headers across 16 files — no include mechanism in ISF, so evolution = full-file copies.

---

## Family: AR_MSFT_Oscilliscope A–H (8 files)

**Purpose & visual identity**: Audio-reactive generators (visualizers) — a survey of oscilloscope/waveform rendering strategies: layered glow strings (A/B/D), Lissajous XY scope (C), 3D projected ribbon (F), 3D ring scope (G), persistent-trail scope (H). Letters = parallel variants, not strict versions.

**Architecture**: A–F single pass (C has a vestigial empty pass 0 from Shadertoy sound-shader conversion); H is 2-pass with PERSISTENT+FLOAT BufferA for trails. E takes six separate `image` inputs as audio sources (multi-deck host routing).

**Techniques**:
- **A (converted "Discoteq 2")**: 20 additive lines; each line's x is displaced by an audio bin sampled at `vec2(1-t, 0.25)` scaled by `ti`; glow via `smoothstep(0.06*S(0.2,0.9,|x|), 0, |y|-0.004)`; a broad VU from 6 spectrum taps averaged.
- **B**: multi-row waveform: per-row band anchor at `squared(fi)*20` bins (quadratic frequency spacing — low rows get bass, high rows treble), 5-tap `getWeight` smoothing, inverse-distance glow `glowWidth = |lineIntensity/(150*Y)|`, RGB channels animated by three desynced sine clocks; camera angle/zoom via mat2 `rot(radians(angleDegrees))/zoom`. MAX_ROWS=32 const loop with `if(i>=R) break` — the house const-bound/runtime-break idiom.
- **C (converted)**: audio-synthesis Lissajous — `freq(time)` generates stereo waveforms mathematically (musical pitch helpers `415*pow(2,(i-60)/12)`), then `sdSound` marches 600 time-samples drawing `1/(sdSegment*2500)` accumulation; `mainSound` vestige retained. Background: SDF box grid `cube(uv)=mod((uv+.5)*8,1)-.5` + vignette `pow(puv.x*puv.y*30,.5)`.
- **D**: per-string colors — **20 individual TYPE:color inputs** (color01–color20) with an if-chain `getColor(idx)` — brute-force host-palette exposure (no array uniforms in ISF; accepted cost for VDMX color pickers).
- **E**: 6-row version of B where each row reads a *different image input* (`iAudio0..5`) via if-chain; adds per-pixel depth: rows get `z = zBase + depthRange*sin(...)`, perspective scale `1/(1+perspAmount*z*2)`, and a **depth test for the core** (`if (z < bestDepth && core > 0.001)` keep nearest core, glow stays additive) — painter's-algorithm-in-a-fragment-shader for line crossings; `scanSpeed` moving pulse samples the spectrum at a scanning x (`pulse = sampleWeighted(i, fract(TIME*scanSpeed))`).
- **F**: true 3D ribbon: 900-sample polyline of spectrum, world position `(x, amp*yv*env, depth*sin(2π*ribFreq*f)*env)`, full mat3 rotX/rotY/rotZ camera + auto-orbit, perspective projection `p.xy/(1+persp*max(z,-0.95))`, inverse-distance accumulation `acc += 1/(1e-3 + d*600/zoom)`, core extracted by `1 - S(th, 2th, |acc-1|)` (isoline of the accumulation field!).
- **F/G/H envelope gate**: `envGate()` computes attack/decay smoothing `a = 1-exp(-dt/atk)` ... but with `float prev = 0.0` hardcoded — the envelope has no real state (single-pass, nothing persistent), so it degenerates to a scaled instant level. An honest scar: stateful envelope attempted in a stateless shader.
- **G**: closed ring scope — 900 samples around a circle, radius modulated by spectrum `rr = ringRadius + amp*yv*env`, object self-spin `RR` composed with camera orbit `RC`, same segment-SDF glow accumulation.
- **H**: persistent trail scope: BufferA feedback with **pixel-per-second scroll** `shiftUV = vec2(scrollX,scrollY)*TIMEDELTA/R`, **frame-rate-independent decay** `pow(decay, TIMEDELTA*60.0)`, **brightness-preserving tint** (tint normalized by its own luma `Tunit = T/dot(T,lumaWeights)` so tinting doesn't dim trails), 3 quality modes (0: 2-tap local segment from screen-x; 1/2: 300/600-sample polyline with const MAXS=1000 + break), gaussian bin smoothing, `softClip(x,k) = x/(1+k|x|)` on the waveform.

**Control/UI design**: consistent audio-conditioning block across F/G/H: `sensitivity`/`noiseFloor`/`attack`/`decay` — a reusable "audio input stage". Camera blocks (rotX/rotY/rotZ/autoOrbit/perspective/zoom) shared F/G. LABELs document units ("deg/s", "px/sec", "taps"). D/E expose colors as many discrete color inputs. `qualityMode` 0/1/2 float with named modes in DESCRIPTION.

**Version evolution** (A→H reads as an exploration sequence): adopt conversion (A) → generalize to multi-row + camera (B) → study Lissajous/audio-synthesis (C) → color customization (D) → multi-source + depth compositing (E) → real 3D polyline (F) → 3D ring variant (G) → persistent trails + quality tiers (H). Recurring migration from Shadertoy-audio idioms (`vec2(x, .25)` spectrum row) to host-aware sampling with smoothing, gain, gates.

**Complexity tier**: A/C/D: 2; B: 3; E/F/G: 3–4 (E's per-pixel depth sort, F/G's 900-segment SDF march are expensive but sophisticated); H: 3.

**Signature moves**: quadratic band anchoring (`fi²*20` bins); inverse-distance additive glow everywhere; isoline-of-accumulation core extraction (`|acc-1|`); nearest-core depth compositing with additive glow; frame-rate-independent trail math (pow-decay by TIMEDELTA, px/sec scroll); luma-normalized tint.

**Rough edges**: the stateless `envGate` with `prev = 0.0` (vestigial state machine); C's empty PASSINDEX 0 block and unused `mainSound`/`songFreq`/`pitch` (conversion residue); 900-sample × per-pixel loops in F/G are brutally heavy at full-screen (no downscaled pass — unusual, given the author uses half-res buffers elsewhere); E's `bandAnchor = squared(fi)*(20/512)` mixes bin-index and normalized-uv conventions.

---

## Family: AR_MSFT_RadialShape v01–v03 (3 files)

**Purpose & visual identity**: Generators. Black-and-white line-art structure generators built from arrays of hollow SDF boxes — v01: six-fold radial "swept tube" arms of stacked box cross-sections; v02/v03: boxes on an elliptical orbit folded through a kaleidoscope ("Algorithm derived from Stripe.dev artwork instrumentation" — reverse-engineered from a website's canvas art). Monochrome, plotter-like aesthetic.

**Architecture**: single pass, pure SDF ink accumulation, `ink = max(ink, line)` compositing; nested const-bound loops (12 arms × 40 boxes; 120 shapes) with runtime breaks.

**Techniques**:
- **Sweep illusion via non-linear spacing** (v01): `et = pow(t, spacingCurve)` eases box positions along the arm so cross-sections bunch at tips, reading as an extruded tube; radius/angle both driven by `et`.
- **Analytical tangent orientation** (v01): instead of numerically differencing the path, computes `dadt = effBend + 2*et*effFan + spiral` and tangent vector `(drdet*ca - r*dadt*sa, drdet*sa + r*dadt*ca)`, orienting each box to `atan(tang.y, tang.x)` — boxes behave as true sweep cross-sections. The comment notes direction is unchanged by easing (chain-rule scalar cancels) — real calculus in a VJ shader.
- **Macro conductor knobs** (v01): Density / Geometric Tension / Bloom Shape, each neutral at 0.5, computing offsets `dOff = density - 0.5` that push multiple base params at once (`effCount = count + dOff*20`, `effBend = armBend + tOff*0.6` etc.) — three "art direction" faders over eleven raw params.
- **Kaleidoscope with shape-space folding** (v02/v03): the screen UV is folded into a sector (`ang = mod(ang, sector); ang = min(ang, sector-ang)`), and **each shape's center is also folded into the same sector** (`sa = mod(sa, sector); mirrored = step(sector*0.5, sa); sa = min(sa, sector-sa)`) with rotation handedness corrected for mirrored copies (`rot *= 1 - 2*mirrored`) — this simulates a canvas-copy kaleidoscope (all shapes from all sectors visible in the fold), not just a UV mirror.
- **Fill occlusion for depth** (v03): signed distance drives both erase and stroke:
  ```glsl
  float fillMask = (1.0 - smoothstep(-px, px, d)) * fill;
  ink *= 1.0 - fillMask;            // paint background over earlier shapes
  float line = 1.0 - smoothstep(ow - aa, ow + aa, abs(d));
  ink = max(ink, line);             // outline on top
  ```
  — emulates canvas `ctx.fill()` painter's ordering in a single-pass shader; later shapes occlude earlier ones → genuine layered-3D look from 2D max/erase.
- **Deterministic per-shape "noise"**: sum of four incommensurate sines of the index (`sin(fi*0.13)*0.5 + sin(fi*1.57)*0.25 + ...`) — hash-free repeatable variation.
- **AA idiom**: `float aa = max(fwidth(d), px*0.5); 1 - smoothstep(ow-aa, ow+aa, d)` with `ow = max(outlineWidth, px*0.75)` — resolution-proportional minimum line width.
- **Animation gating**: `float anim = animate ? 1.0 : 0.0; phase = TIME*speed*anim` — bool freezes all motion without branching the render.

**Control/UI design**: section dividers here are **zero-range float inputs** (`{"LABEL": "-- Structure --", "NAME": "structSep", "TYPE": "float", "MIN": 0, "MAX": 0}`) — a different divider hack than the label-type rows in MirrorFeedback (host-compat alternative; TYPE label isn't supported everywhere). Sections: Structure / Orbit / Motif / Transform / (Macro) / Style / Animation. v01 has the macro trio; v02 drops it (different underlying algorithm), v03 adds back global scale, orbit tilt/speed, dial blend (progressive size along index), fill toggle. Invert bool for black-on-white vs white-on-black — projection/print awareness.

**Version evolution**: v01 (radial arms, tangent-swept, macros) is a different algorithm from v02 (Stripe.dev orbit+kaleidoscope, count default 106, kaleids 6.4); v02→v03 adds fill occlusion (the depth leap), orbit tilt/orbitSpeed as separate controls (was hardcoded `phase*0.3`), globalScale, dialBlend. Trajectory: build own structure → reverse-engineer an admired artwork → add the one feature (occlusion) the flat version lacked.

**Complexity tier**: 3 (v01, v03) — single pass but O(480)/O(120) SDF loops with real differential geometry and occlusion logic.

**Signature moves**: analytical-tangent sweeps; shape-space kaleidoscope folding with handedness correction; erase-then-stroke occlusion; neutral-at-0.5 macro offsets; zero-range-float section dividers.

**Rough edges**: v02 `t = fi/fN` (should arguably be `fi/(fN-1)` for closure — acknowledged in v02's `denom = max(1.0, float(L))` style elsewhere); `mirrored` handedness fix is approximate for shapes near sector edges; per-shape sine-noise coefficients (0.012, 0.066) look like tweak residue; kaleids is float 6.4 default but floored — fractional part dead.

---

## Batch synthesis

**Top 3 most sophisticated files**:
1. **AR_MirrorFeedback_system_v03.fs** — a five-pass feedback *instrument*: persistent velocity advection, dual structure/detail accumulators, motion/edge/chroma/luma injection modes, SDF regions that modulate the simulation's local parameters, scene presets with morph, swing-quantized musical timebase, ratio limiter. The most complete "engine" architecture in the corpus.
2. **AR_MSFT_MIT_v16.fs** (as the apex of the 16-file lineage) — a generator matured into a mastering console: quantize-before-sample data blocks, signal/screen layer separation, beam-growth phosphor physics, full grading rack, zero hardcoded values. The lineage itself is the artifact: 16 versions of documented art direction.
3. **AR_MSFT_RadialShape_v03.fs** — single-pass painter's-algorithm occlusion (erase-then-stroke on signed distance), shape-space kaleidoscope folding with mirror-handedness correction, and (in v01) analytical tangent sweep math — the highest math-per-line file in the batch.

**Recurring patterns / style fingerprints**:
- Const loop bound + `if (i >= N) break` everywhere (Metal/GLSL-ES safety); `FRAMEINDEX < 1` buffer init; scalar ternaries OK, vector ternaries absent.
- Conductor/macro controls: evolve/intensity/stability; density/geoTension/bloomShape; neutral-at-0.5 offsets; presets as multipliers over manual values, morphable.
- Section organization in two dialects: label-TYPE divider rows (`── FEEDBACK ──`) and zero-range float separators (`-- Structure --`), plus "SECTION: Name" label prefixes (MSFT series).
- Safety idioms: `safeTanh` with ±8 input clamp, `sign(d)*max(abs(d), eps)` safe division, `max(w, 1e-6)` normalizers, softClip `mix(clamp, tanh)`, ratio limiters, narrow slider ranges around chaos points.
- Shared helper corpus: hash21 (both the `123.34/456.21` and `0.1031 p3` variants), value noise with smoothstep interp, IQ sdBox, cosine palettes, rgb2hsv/hsv2rgb, 5-tap center-weighted blur, inverse-distance line glow, `mod(uv,1.0)` wrap on all buffer reads.
- Workflow signature: adopt a Shadertoy conversion → parameterize with tight ranges → harden numerically in the next version → grow a control surface → subtract features for art direction → end with "zero hardcoded values". LLM collaboration is openly credited and progressively absorbed ("Gemini" → "Gemini Hybrid / Arson Rivvers").
- Version hygiene inside shaders: legacy paths preserved behind an evolve slider or LEGACY input section; commented-out original code retained as provenance.

**Beyond-ShaderToy techniques**:
- The **evolve lineage-lock** (old behavior as a guaranteed endpoint of a blend slider) — versioning as a performable parameter.
- **SDF regions modulating simulation parameters** (decay/inject/diffusion vary across a shape boundary) rather than masking output.
- **Swing-quantized timebase** (`qTime` with per-step swing) — musical time inside a shader.
- **Beam growth** phosphor mask (brightness-adaptive mask sharpness with gain compensation) and the signal-jitters-under-static-mask principle.
- **Single-pass painter's occlusion** (`ink *= 1-fillMask; ink = max(ink, line)`) emulating canvas fill ordering.
- **Signed-flow-in-RGBA encoding** (x+/x−/y+/y− channels) for optical-flow masks in unsigned buffers, at half resolution.
- **In-shader debug router** (`debug_mode` long dumping intermediate masks) — instrumentation culture unusual for VJ shaders.
