All 48 files read in full. Report follows.

# Batch 03 Analysis Report — /Library/Graphics/ISF (Arson Rivvers)

## Coverage
- files_assigned: 48, files_read: 48, misses: none

---

## Family: AR_DataLoss v01–v18 (18 files)

**Purpose & visual identity**: Generator. A monochrome "architect's sketch" study: a shaded 3D sphere sitting on a white paper field of hand-drawn-looking grid cells that fill in probabilistically, with the sphere's cast shadow expressed as *grid density* rather than darkness. Evolves into halftone/dither renderings and finally a full L-system fractal grid architecture. The internal DESCRIPTION versions run ahead of filenames (file v01 = "Split Sphere - Grid Decay", v04 = internal "v8", v11 = internal "v35", v18 = internal "v38") — the files are checkpoints of a much longer iteration chain. CREDIT "Gemini" throughout: an LLM-collaboration series curated by the author.

**Architecture**: Single-pass generator throughout, despite eventually reaching ~970 lines. No buffers; all state is analytic. Dispatch is a plain `main()` with heavy helper decomposition; later versions use GLSL `struct`s (`GrammarRule`, `HierarchicalState`, `Lighting`) — unusual discipline for ISF one-offs.

**Techniques**:
- *Probabilistic cell fill from analytic light*: shadow strength → fill probability, gated per-cell via `step(random(cellID + fillSeed), finalDensity)`. The shadow is never drawn; it emerges statistically. This is the family's core idea.
- *Analytic 2D sphere shading*: normal from `N.xy = uv/radius; N.z = sqrt(1-dot(N.xy,N.xy))`, terminator via `smoothstep(terminatorPos±range, NdotL)` with hardness/position sliders; rim light gated to the shadow side: `rimLight = smoothstep(rimStart,rimEnd,1-N.z) * (1-lightIntensity)`.
- *Volumetric cast shadow without geometry* (v04+): cone from `dot(normalize(uv), -lightDir2D)` smoothstepped by `shadowConeSpread`, radial decay, plus inverse-square "contact occlusion": `1.0/(1.0 + 10.0*d*d)` (v06+).
- *Stochastic recursive subdivision* (v05+): in strong shadow, `cellUV*2.0` subdivides the cell, adopted probabilistically (`if (random(combinedID) < switchProb)`) so the grid "grows resolution" organically inside shadows — sub-cell IDs salted as `cellID + subID*0.13` to keep hashes unique.
- *Unified dither engine* (v07+): a single `getDither(uv, brightness, mode)` with 11 (later 20) threshold patterns (white noise, squares, line screens, diagonal/cross hatch, circles, sine wave, plus, diamond, hex, spokes, rings, Bayer approx, triangular, spiral, Voronoi, noise). Everything — sphere shading, shadow, cell fill, growth mask — is rendered through the same halftone function, giving the print-media identity.
- *Stochastic growth edge* (v09): instead of multiplying ink by a gradient (blur), the gradient drives dither-thresholded *existence*: `forcePaper = getDither(st*ditherScale, 1.0 - growthGradient, mode); totalInk *= 1.0-forcePaper;` — pattern dissolves into paper by losing whole dots. Explicit comment: "This is correct because it feeds into step(rand, density)." Signature insight: probability-space compositing instead of intensity-space.
- *L-system/IFS grid grammar* (v11, refined v12–v18): iterative traversal (`MAX_ITERATIONS` const bound + runtime `break`) carrying a `HierarchicalState` (cellID, cellUV, depth, lineWeight decay 0.7/level, accumulated `totalScale`). Grammar rules: uniform 2x2, golden-ratio H/V splits (`vec2(PHI+1.0, 2.0)`), alternating Fibonacci, silver ratio, asymmetric thirds, organic random divisions. Subdivision probability blends slider, structure noise, shadow strength, and (v16+) an exponential spatial attractor field `exp(-d * 3.0/attractorRadius) * attractorStrength` (point2D input).
- *Depth-aware line AA* (v12+): `smoothstep`-based cell borders using `lineWeight`, corrected by `aaScale = 1.0/totalScale` so golden-ratio cells don't get squashed lines (v15).
- *Ray-traced shadow with divergence control* (v17–v18): true 3D point-light ray/sphere test (`t = dot(-lightPos, rayDir); distFromCenter = length(lightPos + rayDir*t)`), then v18 mixes point-light and parallel-sun ray directions: `rayDir = normalize(mix(parallelRayDir, pointRayDir, divergence))` — a physically-meaningless but artistically-controllable cone-width knob. Dual lighting: sphere surface light decoupled from cast-shadow light source.

**Control/UI design**: Grows from 3 inputs (v01) to 30+ (v09+). Consistent naming: camelCase, semantic groups by prefix (`lightGrid*`/`darkGrid*` mirrored parameter sets per screen half; `growth*`; `shadow*`). Always a `fillSeed`/`globalSeed` (v11 default 137 — fine-structure constant wink). v16 adds `global*` offsets layered additively over side-specific params (a two-level macro system). LABELs used extensively. v11 uses `point2D` attractor. No audio inputs.

**Version evolution** (the clearest learning trajectory in the batch):
1. v01–v03: hardcoded composition → "Master Control" (every constant becomes a slider).
2. v04–v06: real lighting model (elevation, terminator, rim), volumetric shadow, recursion, per-region dynamic opacity ("THE FIX" comment in v06 — shadow blocks pitch black while outer blocks grey).
3. v07–v08: halftone pivot — all shading unified through `getDither`; light-side gets its own recursion/density controls (composition splits into independently-tunable halves).
4. v09–v10: growth system (oval reveal mask), then replacing clump *noise* with deterministic `getGridStructure` (checkerboard/column/row patterns) — "structural, not random."
5. v11: maximalist L-system rewrite (structs, 8 grammar rules, 20 dithers, PCG hashes *removed*: "Replaced PCG/Bitwise functions to fix GLSL syntax error in standard ISF" — a Metal/GLSL-version scar).
6. v12–v16: deliberate re-simplification — the v11 engine rebuilt incrementally in "Phases" (Phase 1 Grammar, Phase 3 Attractor) on the stable v10 chassis. The author learned v11 was unmanageable and re-integrated its ideas piecewise.
7. v17–v18: lighting realism pass (dual lights, ray-traced shadow, divergence, global contrast curve `(c-0.5)*k+0.5`).

**Complexity tier**: 4 (v11/v16–v18 are near-5 in logic depth, but single-pass, no simulation state; the conductor-style dual-parameter system and grammar engine justify 4).

**Signature moves**: probability-space (dither-gated) compositing; shadow→subdivision recursion; mirrored light/dark parameter banks; golden/silver-ratio grid grammars; seeds as first-class inputs.

**Rough edges**: v11's `rotationAngle`/`skipPattern`/`temporalEvolution` largely inert (rotation computed, applied only to fill UVs); rule 6 "Diagonal Emphasis — Requires Rotation — Phase 2" never completed; v08 has stray `lightSideFadeFactor` removed in v09; duplicated ~300-line getDither/header boilerplate per file (no includes in ISF, so accepted cost); filenames vs internal versions divergent — negative knowledge: the author checkpoints files sparsely.

---

## Family: AR_DeepGlow v01–v06 + combov07 (7 files)

**Purpose & visual identity**: Filter. A professional-grade HDR bloom ("Deep Glow", explicitly cloning Plugin Everything's After Effects Deep Glow): threshold-extract, multi-resolution Gaussian pyramid, weighted recombination with chromatic dispersion, tint, and blend modes.

**Architecture**: The batch's multi-pass showpiece. v01/v02: 10 passes (extract + 4 mip levels × H/V + composite), mips at /2 /4 /8 via `"WIDTH": "floor(RENDERSIZE.x/2.0)"` expressions. v03+: 14 passes, 6 mip levels down to /32, `FLOAT: true` on every target ("float precision throughout"). v06/combov07: 15 passes adding a `PERSISTENT` `temporalBuffer` for frame-to-frame glow smoothing. Dispatch: long `if (PASSINDEX == n)` chain, each blur pass hand-unrolled per level.

**Techniques**:
- *Soft-knee bright extraction*: quadratic threshold (`thresh = threshold*threshold` "for better control at low values"), knee width `max(0.05, thresh*knee*2.0+0.02)`, and *smootherstep* (`6t⁵-15t⁴+10t³`) — comment: "gentler than smoothstep, reduces flicker" (anti-flicker on video input is a recurring driver).
- *Mip-pyramid blur*: separable 13-tap Gaussian per level, spread scaling with the mip factor (`radius*0.01 … *0.32`), each level blurring the previous level's output — cascade rather than independent blurs.
- *Bilinear-optimized 7-tap Gaussian* (v05+): the classic offsets `1.3846, 3.2308, 5.0769` / weights `0.2270, 0.3162, 0.0703` exploiting hardware interpolation — halves texture fetches. combov07 renormalizes the weights to sum exactly 1.0.
- *Energy distribution*: level weights `wN = pow(0.5, N/spreadFactor)` — an exponential falloff whose base is the "spread" knob; `innerBoost = 1+innerGlow*2.5` hot core vs `outerFade` halo.
- *HDR tone mapping of glow*: `glowMapped = 1.0 - exp(-glow*intensity*2.0)` — exponential rolloff before blending.
- *Chromatic dispersion, two generations*: v01/v02 weight R/B differently per blur level (red tight, blue wide — cheap spectral feel); v03+ true UV-offset aberration, red pulled toward center / blue pushed out, scaled by distance from center.
- *Blend-mode morphing*: branchless N-point interpolation across Add → LinearDodge → Screen → Overlay → W3C-compliant SoftLight (piecewise `d = ((16b-12)b+4)b` for b≤0.25), one float slider scrubbing continuously between modes.
- *Correct gamma pipeline* (v04+): linearize input `pow(rgb, gamma)` before luminance/blur, encode back at the end; user-adjustable gamma.
- *Temporal smoothing with NaN guard* (v06/combov07): `glow = mix(glow, prevGlow, temporalSmooth*0.9)` in a persistent buffer; combov07 adds first-frame/NaN detection `isValidPrev = (prevGlow.r == prevGlow.r) && ... && max < 100.0` — a self-equality NaN test, defensive against uninitialized persistent buffers.

**Control/UI design**: 8 sliders (v01, "8 Sliders. Maximum Impact.") growing to 16 (combov07). Names mirror the AE plugin (radius/intensity/threshold/knee/spread). v04 renames `mix` → `mixAmount` (reserved-word collision scar: `mix` as an input shadows the GLSL builtin — v01–v03 actually call `mix(src.rgb, result, mix)` which only compiles because ISF renames uniforms; v04's rename suggests it bit them). `viewMode` debug channel (composite/glow-only/source/threshold-mask) in v05. Tint evolves: single hue → inner/outer hue pair → `tintSpread` gradient (outer hue = `fract(tintHue + tintSpread*0.5)`, automatic complementary halos).

**Version evolution**: v01 uses a `const float weights[13] = float[](...)` array — v02 is the *same shader* with the array replaced by an `if`-chain `getWeight(i)` ("High-quality 13-tap" comment kept): a textbook Metal/GLSL-120 array-constructor workaround. v03 doubles depth (6 mips, 800px radius) + float passes + true CA. v04 "Ultimate": gamma, aspect (elliptical glow via per-axis stretch), tint, blend modes. v05 "DeepGlow3 Professional": ground-up rebuild — bilinear taps, glow-angle rotation matrix applied to blur directions, inner/outer/mid tint zones, view modes, W3C soft light. v06 "Streamlined": trims to 12 controls, drops CA, adds temporal buffer, `#if __VERSION__ <= 120 #define texture texture2D` compat macro. combov07: the "combo" — reintroduces CA *on top of* the tint-gradient/temporal architecture, blending tinted and CA glows by chroma amount to preserve both.

**Complexity tier**: 5 — genuinely engineered multi-pass system with resolution pyramid, persistent temporal state, and correct color management.

**Signature moves**: mip-cascade bloom in ISF via WIDTH/HEIGHT expressions; blend-mode scrubbing slider; smootherstep anti-flicker knee; NaN-guarded persistent buffer.

**Rough edges**: enormous per-pass copy-paste (12 nearly identical blur passes — no way around it in ISF, but v05's rotation matrix is recomputed in every pass); v01's array version presumably dead-on-Metal but kept as v01; `aspect` applies H-stretch only when >1 and V only when <1 (asymmetric semantics); v05's `glowAngle` rotates the separable axes, which shears rather than truly rotates a wide blur.

---

## Family: AR_DiffusedMelt (v01 + slime_v01, 2 files)

**Purpose & visual identity**: Filter (video-fed generative sim). v01: Gray-Scott reaction-diffusion "fed" by video luma — organic coral/maze patterns growing along bright video features. slime_v01: the same rig re-imagined as a physarum/slime-mold trail simulation seeking video brightness.

**Architecture**: 2 passes: `bufferA` PERSISTENT (+FLOAT in slime) + display pass. Channel-packing: v01 stores chemical A,B in RG and precomputed display color in B; slime stores trail in **alpha** and color in RGB.

**Techniques**:
- *Gray-Scott RD*: 9-point Laplacian (cardinal 0.5 + diagonal 0.5 weighting in v01), classic `reaction = a*b*b`, feed/kill in the canonical 0.055/0.062 neighborhood. Video luma modulates feed: `currentFeed = u_feed + luma * u_videoFeed` — video as nutrient map.
- *FRAMEINDEX<2 / event reset init*: `if (resetBuffer || FRAMEINDEX < 2)` seeding — the known host-quirk-safe init idiom; v01 seeds a center square, slime seeds random sparks `hash > 0.99`.
- *Simple/advanced dual UI*: `simpleMode` bool switches between 3 perceptual macro knobs (flowSpeed/textureAmt/tone) and full simulation params, with explicit remapping tables (`u_diffuseB = mix(0.2,0.7,flowSpeed)` etc.) — a conductor system in miniature.
- *Fragment-shader "agents"* (slime): per-pixel pseudo-agent whose heading comes from noise, 3-sensor sampling (forward/left/right at `sensorAngle`, `sensorDist`) reading the trail alpha, steering toward strongest signal + `videoSense * luma` attraction, movement approximated by sampling the buffer *behind* the agent (`IMG_PIXEL(bufferA, uv - dir*moveSpeed/RENDERSIZE)`), then deposit/4-tap blur/decay. An honest fragment-only approximation of a compute-shader algorithm — visually vein-like even though headings aren't persistent.
- `mirrorX` bool for camera input.

**Control/UI design**: ~16 inputs; simpleMode macro trio is the notable pattern; RGB color as three floats (colorR/G/B) rather than a color input — a house habit.

**Version evolution**: Same header/scaffold, two different simulation cores swapped in — the author treats the "video feeds a sim, sim colorized over video" rig as a template.

**Complexity tier**: 3 (v01), 4 (slime — the agent approximation is genuinely inventive).

**Signature moves**: video-luma-as-feed-rate; channel-packing sim state + display color in one buffer; simple/advanced macro mapping.

**Rough edges**: slime's heading `hash(uv*0.1 - TIME*0.01)` means agents share no persistent direction state — trails come from the deposit/decay dynamics, not true agents (works, but a fenced limitation); v01 colorization `clamp(B - A)` is minimal.

---

## Family: FeedbackCam / Hall of Mirrors (5 files: AR_FeedbackCam_HallofMirrors, AR_FeedbackCAM_filter, AR_DistortionCam1_HallofMirrors, _2, _3)

**Purpose & visual identity**: Filter (originally webcam). High-intensity analog-style feedback: recursive "hall of mirrors" tunnels with hue-cycled psychedelia driven by dividing the source by its own history.

**Architecture**: 2 passes: `BufferA` PERSISTENT FLOAT + passthrough. FLOAT is load-bearing — the math produces values outside [0,1].

**Techniques**:
- *Division feedback* (the family's signature and rarest trick in the batch):
  ```glsl
  vec4 self = IMG_NORM_PIXEL(BufferA, mod(uv, 1.0));
  vec4 feeb = saturate(srcCentered / (self - mod(fac, 0.1)));
  ```
  where `saturate` clamps to ±10 (not 0–1). Dividing the centered source by (history − offset) creates violent, edge-seeking instability that classic `mix`-feedback never produces.
- *Content-dependent radial warp*: `fac = feedbackAmount*(1-4*length(uv-0.5)) + feedbackAmount*length(srcCentered)` then `uv = uv*(1+facstr) - facstr/2` — zoom strength depends on both screen radius and pixel brightness.
- *Cosine hue triad*: `huecol(h) = R*cos(h) + G*cos(h+1) + B*cos(h+2)` keyed to `fac*hueAmount`.
- *Color-sensitivity gate*: `isgreen = smoothstep(0.5, 0.4, 1.0 - dot(src, vec4(redSens,greenSens,blueSens,alphaSens)))` — a per-channel dot-product keyer deciding where hue-shift applies (green-screen-ish selectivity as four sliders).
- Evolution adds: `effectMix` dry/wet (base), noise UV jitter `uv += (noise(uv*10+TIME)-0.5)*0.005` "to break up the obvious circular feedback" (_2), optional `depthSource` image driving UV offset from RG channels (_2), 4-tap diffusion blur of the feedback buffer + epsilon guard `denom = self - fac*0.1 + 0.001` against division blowup (_3), `fract()` wrap instead of `mod()` "to wrap UVs more softly."

**Control/UI design**: 7–11 inputs; stable naming across all five files; a vestigial `tmpInputName` float input persists in every version (dead input never cleaned up — likely a VDMX preset-compat artifact). `_3` uses `"IMPORTED": {"inputImage": "default"}` — a nonstandard experiment.

**Version evolution**: webcam original → generic inputImage port → effectMix for VJ mixing → symmetry-breaking noise + depth-map drive → stability hardening (diffusion, epsilon). Trajectory: wild found-math effect progressively domesticated for live use without losing the instability that makes it work.

**Complexity tier**: 3 — simple pass structure, but the division-feedback dynamics are sophisticated emergent behavior.

**Rough edges**: `mod(fac, 0.1)` in early versions makes feedback offset saw-tooth with brightness (later replaced by `fac*0.1`); `lenuv = 0.5 - length(uv + 0.5)` looks like a bug (uv+0.5 rather than uv-0.5) that became part of the look; `tmpInputName` dead input everywhere.

---

## Family: AR_Displacement_dispersion (1 file)

**Purpose & visual identity**: Filter. Shadertoy conversion (cornusammonis "Displacement with Dispersion"): iterative spectral sampling producing chromatic-dispersion displacement of one image by sine waves + a second feedback image.

**Architecture**: Single pass, two image inputs (iChannel0 displacement driver, iChannel1 displaced source).

**Techniques**: Spectral integration loop — `for(i=0; i<1; i+=quality)` builds per-wavelength weight `p = vec4(i, dispersionScale*pow((1-i)*i, dispersionPower), 1-i, 1)` and accumulates `p*p * IMG_NORM_PIXEL(...)` at increasingly displaced UVs (`pow(sin(uv*freq + speed*TIME), vec2(power))` + image feedback term), normalized by `Σp*p` and shaped with smoothstep-as-sigmoid. The `p*p` (square of a linear spectral ramp) is the minified dispersion-coefficient trick noted in the header comment. Author's contribution: exposing all magic numbers as documented sliders with unusually verbose LABEL strings (labels used as inline documentation).

**Complexity tier**: 2.

**Rough edges**: float-stepped loop (`i+=quality`) is a Metal-risky pattern the author usually avoids elsewhere; kept because converted.

---

## Family: AR_dotPixeL_v01 (1 file)

**Purpose & visual identity**: Filter. "Glitch disintegration with pointillism": Sobel edges gated by noise disintegration masks, monochrome glow color, flicker, micro-glitch UV shivers, cheap bloom.

**Architecture**: Single pass.

**Techniques**: Full 3×3 Sobel (8 taps per axis) → smoothstep edge band around `edgeThreshold`; wave-modulated disintegration `step(particleDensity, noise + sin(uv.y*waveFreq + TIME*2)*0.1)`; two-scale horizontal glitch offsets (`horizontalGlitch` slow ×10 rows + `microGlitch` fast ×30 rows) applied to sample UV *scaled by edge value* (glitch only where edges are); 5×5 box-blur bloom mixed by `bloomAmount`; luminance × glowColor × glowIntensity monochrome output; multiplicative composite `edge * disintegrate * flicker`.

**Control/UI design**: 11 inputs incl. a `color` type (glowColor) — one of the few color-typed inputs in the batch.

**Complexity tier**: 2 — competent single-pass effect stack.

**Rough edges**: `pixelSort()` defined, returns an inversion, never called (abandoned direction, name reveals intent); disintegrationDirection input feeds `directionalDisintegration` which is also never called — two dead subsystems.

---

## Family: AR_DVD (4 files: DVD_Bounce, DVD_Bounce_16x9, DVD_v01, DVD_v02)

**Purpose & visual identity**: Generator. The DVD-logo screensaver: an SDF-drawn DVD logo bouncing in the frame, recoloring on wall hits, with transparency for compositing as a VJ overlay.

**Architecture**: Bounce/16x9: single pass, zero inputs, fully analytic. v01: 2 passes — 1×1-style PERSISTENT FLOAT `time_accum` + render. v02: 3 passes — PERSISTENT FLOAT `particleState` (XY=position, ZW=velocity — a physics register in one texel), PERSISTENT `bounceState` (hit counter), render.

**Techniques**:
- *Vector DVD logo as SDF*: composed from `ellip`/`halfEllip` primitives with boolean ops (`max(d,-d2)` subtraction) plus a shear matrix `p *= mat2(1.0,-0.2,0.0,1.0)` for the italic slant; AA via `d /= fwidth(d)`.
- *Stateless bounce* (Bounce/v01): triangle-wave folding `flip()` (`abs(mod(floor)…)`) of linear motion — position at any TIME with no state; and the standout `calcHitPos()`: analytically reconstructs where the *last wall hit* occurred by intersecting the motion line with cell boundaries, so the color hash `hash12(lastHitPos)` changes exactly on bounce — deterministic color-per-bounce without a counter.
- *Time accumulator pattern* (v01): `newTime = prev.r + TIMEDELTA * Speed` in a persistent buffer, so the Speed slider changes rate *without teleporting* the logo (the flaw of multiplying TIME directly). A tiny but important live-performance discovery.
- *Real integration + steering* (v02): Euler integration `pos += vel*Speed*TIMEDELTA`, wall clamp + velocity flip, plus "car physics" steering: `vel = normalize(mix(vel, targetDir*sign(vel), Steering_Friction))` — Trajectory_Skew/Corner_Lock gradually *steer* the trajectory toward the corner-hitting diagonal instead of snapping. Bounce detection in a separate pass by wall-proximity epsilon, incrementing a color counter (with an honest comment about multi-increment while wall-touching, mitigated by `floor(bCount*0.2)`).
- *Premultiplied-alpha compositing*: explicit FG-over-BG premultiplied blend with user Background_Color/Alpha, and `pow(color, vec3(0.4545))` gamma on the HSL-derived logo color.

**Control/UI design**: 16x9/Bounce: zero inputs (drop-in overlay). v01/v02: 8–10 inputs, Snake_Case naming (unique to this family), LABELs, `bool` Corner_Lock.

**Version evolution**: identical stateless twins → resolution-independent + time-accumulator + background controls → full stateful physics with steering. A textbook stateless→stateful migration; the analytic `calcHitPos` machinery is retained in v01 then abandoned in v02 when real state makes it unnecessary.

**Complexity tier**: 3 (v02) — small, but the state-in-texel physics engine and analytic hit reconstruction are choice techniques.

**Rough edges**: DVD_Bounce.fs and DVD_Bounce_16x9.fs are byte-identical (duplicate); v02 `FRAMEINDEX == 0` init (not `<2` — mild inconsistency with house style); unused `fBox`/`range`/`rangec` helpers carried along.

---

## Family: AR_Edger_v01 (1 file)

**Purpose & visual identity**: Filter. Parameterized Sobel edge detector with a two-strip Technicolor-style colorizer (INKA lineage, updated).

**Architecture**: Single pass.

**Techniques**: Sobel with *separately weighted* diagonal/horizontal/vertical kernel contributions (diagWeight/horizWeight/vertWeight let you bias edge orientation); user-adjustable luma weights (3 floats); edge magnitude shaped by `pow(mag, 0.5*edgeGamma)*edgeGain` with pre-pow `edgeBias` added to the squared gradient; two-strip color process: image split through `redFilter` and `blueGreenFilter` vec3s (as 6 floats), converted to "negatives" (`rednegative = vec4(redrecord.r)`), re-printed through the filters and mixed by `channelBalance` — a film-pipeline emulation; `edgeToAlpha` routes edge magnitude into output alpha for host-side compositing; `intensity` up to 100 deliberately drives HDR overbrights (`clampOut` optional).

**Control/UI design**: 22 inputs, all flat floats, grouped by name prefix — the author's "everything is a knob, vec3s as float triplets" style at its purest.

**Complexity tier**: 2.

**Rough edges**: the gx/gy kernel assembly double-counts direct neighbors (comment "ensure direct L/R scaled" patches it additively) — works but the weights aren't orthogonal; bool-like floats (`invertEdges > 0.5`).

---

## Family: AR_EvolutionDiffusion (3 files: v01, dataloss_v01, dataloss_v02)

**Purpose & visual identity**: Filter — the batch's flagship. "IFS Evolved Filter 2.6": input video seeds a Gray-Scott reaction-diffusion field, whose chemistry drives the geometry of an IFS fractal (orbit-trapped kaleidoscopic line-work), which then flows through a datamosh temporal-feedback engine. CREDIT: "Original v3 soul + UNHINGED treatment by Claude" — explicit LLM-remix provenance.

**Architecture**: 3 declared passes + implicit display: `sim_buffer` PERSISTENT FLOAT (RD state), `render_buffer` FLOAT (IFS frame), `mosh_buffer` PERSISTENT FLOAT (feedback history). Function-per-pass dispatch (`pass_simulation` / `pass_render` / `pass_mosh`) — cleanest pass organization in the batch.

**Techniques**:
- *RD→IFS parameter bridge* ("BIO-IFS BRIDGE"): sim channels `bio.rg` modulate IFS rotation angle (three modes: multiplicative "v3", additive, hybrid), scale (`scaleBase + bio.g*bioInfluence*bioScaleDepth`), per-axis offset, and pre-iteration domain warp — the simulation literally bends the fractal.
- *IFS orbit-trap renderer*: up to 80 iterations (const bound + `break`) of fold (box/triangle/hex/spherical-inversion/none) → rotate with per-iteration drift → scale-translate → soft inversion `p *= 1/(1+r²*inv)`; dual orbit traps (box/circle/lineX/lineY/cross/5-point star) blended by `trapBlend`, both min-trap and *accumulated* trap (`exp(-trapSum/N …)`) mixed by `trapAccumulate`; field shaped `exp(-trapMin*tightness)` → smoothstep threshold.
- *Conductor system* (the house macro-param pattern at full scale): six top-level performance knobs — CHAOS, FORM DISSOLVE, TEMPORAL SMEAR, COLOR INTENSITY, CINEMATIC DRAMA, and **SOUL** — each expanded through ~15 `getEff*()` functions. SOUL is the standout: `mix(userParam, V3_CONSTANT, soulAmount)` pulls every parameter toward `#define`d values of a beloved earlier version ("v3 character") — *version nostalgia as a slider*. FORM DISSOLVE even switches the fold *mode* at thresholds (0.6→spherical, 0.8→none).
- *Input-drive matrix*: five independent video couplings — RD seed (luma threshold), continuous B-chemical injection (`ab.g = max(ab.g, inject)`), feed/kill modulation, direct bio-channel blend (Geo Drive), and color bleed — each with its own depth slider.
- *Datamosh engine*: screen-space derivatives `dFdx/dFdy(luma)` build a flow field; history sampled at `fbUV - flow*flowOffset` (edges drag the past around), luma-keyed refresh `smoothstep(refreshLow, refreshHigh, luma)` decides where fresh frame overwrites history — I-frame/P-frame emulation. Plus feedback zoom/rotate, CA on the render buffer, dFdx-based edge overlay, ACES/Reinhard tonemap, 3-octave film grain.
- *Section dividers via event inputs*: `{"NAME":"ui_input","TYPE":"event","LABEL":"INPUT SOURCE"}` — dummy event inputs used purely as labeled separators in the host UI. Distinctive house convention (11 sections here).
- *IQ cosine palettes* (Neon/Fire/Ice/Earth/Synthwave) + anisotropic Laplacian (`laplacianBias` skews cardinal vs diagonal weights).

**Control/UI design**: ~70 inputs organized into 11 ui_ sections; `long` dropdowns with LABELS arrays for every mode; conductor knobs at top. The most fully-realized VJ control surface in the batch.

**Version evolution**: dataloss_v01 is a *performance remix* of v01 with two surgical changes, each commented with rationale: merging duplicate `getInputLuma` taps in the sim pass ("Single getInputLuma() shared between both branches — don't split back into two taps") and hoisting `angBase`/`offXY` out of the 80-iter loop. dataloss_v02 = v01 remix + one new input, `Dissolve_Tipping_Point`, parameterizing the previously hardcoded formDissolve fold-mode thresholds ("Both stage thresholds shift together; default 0.6 reproduces original 0.6/0.8 trip points"). The `_dataloss_` suffix marks an optimization/parameterization pass that preserves defaults exactly — disciplined remix protocol.

**Complexity tier**: 5 — three coupled systems (RD sim, IFS renderer, mosh feedback) with a conductor layer; the definitive "multi-pass simulation system with conductor controls."

**Signature moves**: SOUL slider (blend-toward-canonical-constants); event-input section headers; RD-drives-IFS bridge; luma-refresh datamosh; remix files that provably preserve prior defaults.

**Rough edges**: `temporalEvolution`-style leftovers absent here but `rotation` rule ordering (zoom→pan→rotate) makes pan non-intuitive under rotation; ~140 header lines duplicated across three files; `seedPert` of 0.001 barely visible (vestigial).

---

## Family: AR_Experimental_Fractalizer_v01 (1 file)

**Purpose & visual identity**: Filter. A raymarched 3D bar/tube lattice (mojovideotech/rez lineage) repurposed: the fractal is marched but *never shown* — its surface normals displace the video's UVs, producing architectural refraction.

**Architecture**: Single pass, 64-step raymarch.

**Techniques**: Distance field of repeated boxes/tubes via `mod(p.yz, period)` cross-sections combined with nested min/max CSG; camera direction triple-rotated by time; normal from 3-tap tetrahedron-ish estimate; then the pivot — `dynamicDistort = distortAmount * (1 + 0.3|barS-1| + 0.3|tubeS-1|) * (1 + 0.2 sin(speed*2π))` couples all sliders ("so they all interconnect"), and `sampleCoord = uv + n.xy * dynamicDistort`. The full `fractalColor` computation (≈15 lines) is computed and discarded — comment admits "(Optionally, you could blend fractalColor into it if desired)".

**Complexity tier**: 3 — a real raymarcher used as a displacement source.

**Rough edges**: dead fractalColor block (expensive dead code, ~30% of the marcher's purpose unused); `float(1.0 + 2.0*sin(...))` no-op cast; the "Experimental" name is accurate — an abandoned-but-kept direction.

---

## Family: ArsonRivvers_ExtremeGridGlitch (2 files)

**Purpose & visual identity**: Filter. Aggressive broadcast-glitch: blocky displacement, RGB split, interlace masks, dropout — v01 chaos-driven pattern roulette, v02 rebuilt around hierarchical grid subdivision.

**Architecture**: Single pass each.

**Techniques**:
- v01: `blockyNoise()` — noise texture (imported `WhiteNoiseDithering.png`) sampled at scrolling `uv.yy` (y-only → horizontal bands), quantized to 20 IDs, thresholded to sparse dropouts; `selectPattern()` rolls one of 7 interlace masks per time-tick (horizontal/vertical/diagonal/wavy/flickering/random/color-shifting lines) weighted by a `chaos` slider; `freeze` bool quantizes time to `floor(iTime)` — stutter-freeze as a performance control.
- v02: proper rewrite — texture dependency dropped for `rand2()` hash; `createSubdivisionGrid()`: up to 10 levels of halving cell sizes, per-level scroll offsets and fading intensity, summed into a line mask that drives RGB-split offsets and displacement; `recursiveLineField()`: quadrant-seeded line placement (`quadrant = floor(pixelPos/(RENDERSIZE*0.5))`, random per-quadrant offsets and on/off gating) — the grid glitch becomes spatially hierarchical rather than pattern-roulette; channel-swap dropout `mix(color, color.bgr, dropout)`; `morphIntensity` master dry/wet with smoothstep.
- Both use const loop bound + `break` for the level loops.

**Control/UI design**: 7–8 inputs; `freeze` bool; `chaos` (v01) replaced by `gridComplexity` + `morphIntensity` (v02) — from randomness knob to structure knob.

**Version evolution**: v01 is a barely-converted Shadertoy (see rough edges); v02 is the "make it actually mine and actually ISF" rewrite, replacing texture noise with hash noise and the pattern roulette with the subdivision-grid concept that later blooms in the DataLoss series — visible cross-pollination.

**Complexity tier**: 2 (v01), 3 (v02).

**Rough edges**: v01 is *broken as ISF* — it defines `mainImage(out vec4, in vec2)` with `iTime`/`iResolution`/`texture(inputImage,...)` and has no `main()`; it's a Shadertoy paste with an ISF header, kept as a reference checkpoint. Also its `finalColor` multiplies all channels by `rgbIntensity` (default 0.1) making output ~black without the mask paths — negative knowledge: this file documents intent, not a working effect. v02's `maskNoise == 1.0` exact-equality test survives only because the zeroed branch guarantees it.

---

## Family: AR_FeedbackGlitch_VDMX (1 file)

**Purpose & visual identity**: Filter. Minimal persistent-buffer echo/sharpen glitch (dantheman lineage): `gl_FragColor = newColor + (U - old/2)` where U is the history sampled at ± a small offset — an unsharp-mask-over-time producing ghosting trails.

**Architecture**: 1 declared pass (`"persistent": true` — lowercase key, a host-tolerance quirk; also `"WIDTH": "$WIDTH"` legacy macro).

**Techniques**: The one-liner temporal Laplacian above; `offset`/`mix_var` control the tap spread and echo gain.

**Complexity tier**: 1.

**Rough edges**: ~55 lines of dead helpers (box, truchetPattern, lines, rotate2D, tile, noise) from the Book-of-Shaders — the file is a gutted sketchbook page; single-target pass means the buffer is also the output (no separate display pass).

---

## Family: AR_FluidClouds_v01 (1 file)

**Purpose & visual identity**: Generator. Domain-warped fbm nebula (Shadertoy sXSGDy conversion): blue/purple void, cyan filament tendrils, magenta plasma bloom, gold hot spots, breathing center swirl. Perfectly loop-seamless.

**Architecture**: Single pass (converted `pass0_mainImage` wrapper).

**Techniques**: Classic IQ double domain warp `f = fbm(p + 3.0*w)` where `w = fbm(p + 2.0*q + ...)`; *seamless looping* — every time term derives from `phase = TAU*TIME/LOOP` via `cos/sin(phase)` drift vectors so the field is exactly periodic (10s); breathing swirl `rot(swirlAmt*sin(phase)/(r+0.3))` — twist inversely proportional to radius; filaments from warp-component difference `smoothstep(0.22, 0.0, abs(w.x - w.y))` — a distinctive way to extract thin bright threads from a warp field; three-accent additive color (cyan filaments, magenta `pow(glow,2)`, gold `pow(max(0,f-0.62),2)*1.8`); `0.16/(r+0.12)` core glow; Reinhard + gamma.

**Control/UI design**: single `point2D` "mouse" input scaling swirl amplitude — mouse-to-point2D is the standard Shadertoy conversion residue, kept functional.

**Complexity tier**: 3 — standard technique, executed with above-standard color discipline and the loop-periodicity constraint.

**Rough edges**: conversion artifacts everywhere — `vec3(RENDERSIZE,1.0).xy` and `vec4(mouse*RENDERSIZE, mouse*RENDERSIZE)` inlined by a mechanical converter; comments still describe Shadertoy uniforms.

---

## Family: AR_FractalFlame (1 file)

**Purpose & visual identity**: Generator. Fragment-side approximation of a fractal flame (normally a particle/histogram algorithm): fiery symmetric wisps in a black-body fire palette.

**Architecture**: Single pass; 600-iteration loop.

**Techniques**: Per-pixel IFS orbit starting at `p = uv*Scale`, cycling three flame variations (`sin`, `swirl` `x·sin(r²)−y·cos(r²)`, `spherical` `p/r²`) by `mod(i,3)`, each step through a time-hashed affine matrix; *density splatting inverted*: instead of scattering points, each pixel accumulates `w = exp(-60*d²)` where `d = length(pNext - uv)` — "did the orbit pass near me?" — an elegant gather-form of the flame algorithm; log-density `log(1+density)` and `pow(density,4)` for flame falloff; angular color `t = 0.2*atan(pNext.y,pNext.x)/π + 0.5` through a hand-rolled 4-stop fire ramp; `uv = abs(uv)` mirror symmetry; `Iterations` as a `long` input handled by const-600 loop + `active = step(fi, iterF-1.0)` mask (the branchless variant of the const-bound/break idiom — masking instead of breaking, likely a Metal-safety choice) with `p = mix(p, pNext, active)` freezing the orbit when inactive.

**Control/UI design**: 3 inputs (TimeRate, Scale, Iterations as `long` with MIN/MAX).

**Complexity tier**: 3 — a genuinely nonstandard reformulation of an offline algorithm.

**Rough edges**: 600 iterations × per-iteration `fract/sin` hashing is heavy; masked (not broken) loop burns full cost regardless of Iterations setting — correctness chosen over speed.

---

## Batch synthesis

**Top 3 most sophisticated files**:
1. **AR_EvolutionDiffusion_v01(+dataloss remixes)** — three coupled engines (Gray-Scott RD → IFS orbit-trap fractal → luma-refresh datamosh) under a six-knob conductor layer, with the SOUL slider blending every parameter toward `#define`d "v3" constants; the `_dataloss_` remixes show a disciplined optimize-and-parameterize protocol with rationale comments and default-preserving changes.
2. **AR_DeepGlow_combov07 (and v05)** — a 15-pass, 6-mip-level, float-precision HDR bloom with bilinear-optimized taps, correct gamma pipeline, branchless 5-point blend-mode scrubbing, tint-gradient system, chromatic aberration layered onto a NaN-guarded persistent temporal buffer. Production-plugin engineering inside ISF.
3. **AR_DataLoss_v11 (internal "v35")** — single-pass L-system grid architecture: struct-based hierarchical state, 8 subdivision grammars (golden/silver ratio, Fibonacci alternation), spatial attractor fields, 20-mode dither engine, all shading routed through probability-space halftoning.

**Recurring patterns / style fingerprints**:
- The sine-fract hash `fract(sin(dot(p, vec2(12.9898,78.233)))*43758.5453)` in ~90% of files, plus `hash12` (Dave Hoskins) for quality-sensitive spots; v11 documents that PCG/bitwise hashes *fail* in standard ISF.
- Const loop bounds with runtime `break` (or, in FractalFlame, a `step()` activity mask) — the Metal loop idiom, everywhere.
- Array-constructor avoidance: DeepGlow v01→v02 is a pure "const array → if-chain getWeight()" fix; every later lookup table is an if-chain.
- `FRAMEINDEX < 2` (or `<5`) + event-input reset for persistent-buffer init.
- Conductor/macro-parameter layers at every scale: simpleMode trio (DiffusedMelt), light/dark mirrored banks + global offsets (DataLoss), the six-conductor + SOUL system (EvolutionDiffusion).
- Event-type inputs as UI section dividers (`ui_input`, `ui_conductor`…) — a house convention worth adopting in any generator.
- LLM-collaboration provenance kept in CREDIT fields ("Gemini", "Claude", "UNHINGED treatment") with the author curating checkpoints; version files are sparse snapshots of longer chats (filename vs internal version mismatch in DataLoss).
- Seeds (`fillSeed`/`globalSeed`/`seed`) as first-class performance inputs; vec3 colors exposed as three floats; dry/wet `effectMix`/`morphIntensity`/`mixAmount` master faders on every filter.
- State-in-texel persistence: physics registers (DVD v02 XY/ZW pos/vel), time accumulators (DVD v01), sim chemistry + display color channel-packed (DiffusedMelt).

**Beyond standard ShaderToy fare**:
- Probability-space compositing (DataLoss v09+): dissolving imagery by dither-thresholding *existence probability* instead of fading intensity.
- The SOUL slider — regression-to-a-canonical-version as a continuous performance control.
- Division feedback `src/(history−k)` with ±10 clamps in FLOAT buffers (HallofMirrors) — found-math instability domesticated across five revisions.
- Gather-form fractal flame (per-pixel "did the orbit pass near me" splatting).
- Analytic last-bounce reconstruction (`calcHitPos`) for stateless color-on-collision, and its later replacement by a one-texel physics engine.
- Shadow divergence control mixing parallel and point-light ray directions — physically wrong, artistically precise.
- Fragment-only slime-mold approximation with sensor steering read from the trail buffer's alpha channel.
