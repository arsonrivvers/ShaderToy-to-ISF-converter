All 40 files in batch_23 have been read in full. Per the coordinator's instruction, here is the complete report as my final message.

# Batch 23 Analysis Report — /Library/Graphics/ISF

## Coverage

- files_assigned: 40, files_read: 40, misses: **none**
- Note: `AR_Tron_v\`0.fs` (backtick in filename, clearly a typo'd save of v10's intended name) exists and was read — it is a byte-similar duplicate of `AR_Tron_v01.fs` (identical "Depth Wireframe Lattice" v1 code, 237 lines).
- Naming is deceptive in this batch: **AR_Tron_* is actually the "Depth Wireframe" family** (depth-map → 3D wireframe lattice), **AR_WatercoloringMelt_* is actually the "Video Flow Feedback" optical-flow family**, and **AR_ShiftingHarbor_colorsplash* is the "Twisted Fractal Bloom" family**. Working titles diverge completely from LABEL fields.

---

## Family: ShiftingHarbor_colorsplash (v01, v02, v03, colorsplash2_v01) — "Twisted Fractal Bloom"

**Purpose & visual identity.** Generator. Soft, hypnotic spiral bloom: N rotated/scaled copies of the UV plane, each contributing an exponentially-weighted sinusoidal RGB phase — blurry organic color clouds spiraling to center. colorsplash2 is a cousin: a persistent-buffer trail version whose source is an iterative sin-fold field glow.

**Architecture.** v01–v03: single pass. colorsplash2: 2 passes — pass 0 renders into PERSISTENT `feedbackBuffer` (prev × decay + new glow), pass 1 is tone-map-only display. Dispatch via `if (PASSINDEX == 0) {...; return;}`.

**Techniques.**
- *Iterative rotated-scale bloom accumulator* (the core engine):
  ```glsl
  vec2 rv = rotate2(t*rotationSpeed + fi*0.1) * uv * pow(convergence, fi);
  float w = exp(-length(rv) * bloomRadius);
  col += w * sin(vec3(fi*ps, fi*ps*2., fi*ps*3.) + rv.xyx*colorAmplitude + t + colorShift);
  ```
  v03 replaces `pow(convergence, fi)` with an accumulating `scale *= convergence` — cheaper and enables per-iteration mutation.
- *Per-iteration feedback inside the loop* (v03): the current sample point nudges the UV used by the NEXT iteration — `feedbackUV += rotate2(feedbackRotate*fi*0.3)*rv * feedbackAmt*pow(feedbackDecay,fi) / (1.0+d);` — a spatial (not temporal) self-organization trick, with the rotation explicitly documented as preventing collapse into radial lines.
- *Reinhard extended tone map* (`whiteMapping` with white-point parameter) — the family's standard tone stage.
- *Two-octave value-noise fbm domain warp* (`fbm2 = vnoise*0.65 + vnoise(p*2.01+4.3)*0.35`), gated by `if (warpAmount > 0.01)`.
- *Kaleidoscope fold*: `a = mod(atan(p.y,p.x), 2*sector) - sector; return length(p)*vec2(cos(a), abs(sin(a)))` — the `abs(sin)` gives mirrored sectors.
- *Lissajous auto-orbit of the center point*: `centerOff += orbitRadius * vec2(sin(orbitT), sin(orbitT*orbitShape))` with orbitShape as frequency ratio (1.0=circle, 1.5="figure-8ish", 2.0="pretzel" — author's own comment).
- *Breathing* (`1 + breathDepth*sin(t*breathRate*TAU)` scale pulse) and *drift* (`drift*vec2(sin(t*0.71),cos(t*0.53))` — incommensurate frequencies for non-repeating wander).
- colorsplash2's source field is an *iterative sin-fold with accumulating rotation matrix*:
  ```glsl
  rotAccum *= mat2(cos(fj),sin(fj),-sin(fj),cos(fj));
  v += sin(rotAccum * v.yx * fj + t*fieldSpeed) / fj;
  ```
  then glow = cosine palette / `(glowSharpness + length(v))` — inverse-distance glow on a chaotic attractor.
- colorsplash2 feedback transform: fbZoom scale-down, radius-dependent OR global rotation (`fbRotateRadial` bool), small constant `fbOffset` "breaks perfect symmetry, creates drift in the trail". Manual UV round-trip between centered aspect coords and 0-1 texture coords: `texUV = (texUV * R.y + R) * 0.5 / R;`.

**Control/UI design.** Grows 11 → 26 → 31 inputs across versions. v03 introduces `LABEL`-keyed section headers on the first input of each group ("Geometry", "Time & Motion", "Bloom Engine", "Feedback", "Domain Warp", "Color", "Tone"). Strong **zero-default doctrine**: every added feature defaults to off/0 so defaults reproduce the original exactly (stated in DESCRIPTION: "At defaults, identical to the original"). Coarse/fine flavor via convergence (0.85–0.99) vs detailIterations. `point2D` center in v02 replaced by centerX/centerY float pair in v03 (likely host-mapping pragmatics).

**Version evolution.** v01: raw 62-line original (probably a conversion/sketch) with a plain `for (i < iterations)` loop. v02: parameter explosion — exposes hardcoded constants (convergence, phaseSpread), adds geometry/motion/color/tone post stack, and *changes the loop to const-bound + break* (`for (i < MAX_ITERS) { if (i >= iterations) break; }`) — the documented Metal-host workaround. v03: per-iteration feedback, orbit system, section labels, moves saturation/temperature *after* tonemap (color-pipeline ordering lesson). colorsplash2: forks the aesthetic into a temporal-feedback architecture with a different source field.

**Complexity tier: 4** (v03/colorsplash2) — deep parameterization, feedback topologies, curated control architecture; not 5 only because sim is not multi-buffer.

**Signature moves.** Zero-default enhancement layering; labeled control sections; incommensurate-frequency drift; the per-iteration feedback nudge; Lissajous orbit with shape ratio.

**Rough edges.** v02 keeps `spiralTwist * r * 3.0 * sin(t*0.5)` while v03 changes to `(t*0.5 + sin(t*0.3)*0.4)` (unbounded rotation accumulation — deliberate but inconsistent between versions). Duplicated helper boilerplate across all versions (no includes in ISF, so accepted cost).

---

## Family: SliderTest_20_v01 — utility

**Purpose.** 20 dummy float sliders averaged into a gradient tint; a host-UI stress test (how does VDMX render 20 sliders). Generator/utility. **Tier 1.** Notable only as evidence the author tests host UI capacity deliberately. Uses `#ifdef GL_ES precision mediump float` — rare in this corpus.

---

## Family: Solarize_v02 — filter

**Purpose.** VIDVOX's stock Solarize with an added organic wet/dry system. Filter.

**Techniques.** HSV round-trip solarization: fold V around adjustable `centerBrightness` (`v < c ? 1-v/c : (v-c)/c`), power-curve it, optional inversion, luminance-scaled colorize into S. The author's addition: *effectAmount morphs the parameters themselves* (`dynamicPowerCurve = mix(1.0, powerCurve, effectAmount)`) rather than just crossfading output, plus an "organic transition" mix weight modulated by per-pixel hue and brightness:
```glsl
float organicMix = mix(transitionFactor, transitionFactor * (brightnessFactor + hueFactor) * 0.5, 0.7);
```
so the wet/dry boundary shimmers per-pixel instead of being a uniform dissolve. Comment shows ternary-vector-safe `mix/step` variants commented out in favor of scalar ternaries — awareness of the vector-ternary hazard.

**Controls.** 5 + inputImage; VIDVOX naming conventions retained. **Tier 2.** Signature move: parameter-space (not output-space) dry/wet morphing.

---

## Family: SortingSmear_2025_v01 — "Adaptive Sort Feedback"

**Purpose.** Filter. Pixel-sorting-style glitch smear via persistent feedback: each pixel drifts toward brighter/darker neighbors, creating melting sorted streaks.

**Architecture.** Single PERSISTENT pass `lastRender` (self-target — output IS the buffer). Guard: `if ((FRAMEINDEX > 1) && !resetInput)` — the FRAMEINDEX<2 init idiom plus an event-typed "Flush Buffer" reset.

**Techniques.**
- *Neighbor-comparison sort step*: sample lastRender at ±neighborDistance px vertically/horizontally, compare weighted luma, and `mix` toward the neighbor that violates sort order (direction switchable Bright→Dark / Dark→Bright via `long` enum). Not a true sort — an iterative relaxation that converges to sorted-looking gradients over frames.
- *User-weighted luma*: `luma(c, w) = dot(c, w / max(w.x+w.y+w.z, 1e-4))` with brightnessR/G/B sliders — channel-selective sorting (sort by red only, etc.).
- *3×3 morphological erode/dilate on the feedback buffer*, single bipolar control: `morphModeMix` (−1 erode … +1 dilate) with strength and radius — grows or eats the smears.
- *YIQ hue rotation* time-scaled by `TIMEDELTA` (`hueShift(result.rgb, colorShiftAmount * TIMEDELTA)`) — framerate-independent color drift inside feedback, a careful touch.
- `adaptLevel` blends src toward oldC before comparison — controls how fast new video is adopted into the sort field.

**Controls.** 20 inputs, all LABELed, includes event-type reset. **Tier 3.** Signature: bipolar morph-op knob; TIMEDELTA-scaled hue drift in a feedback loop. Rough edge: comment "NOTE: resetInput is treated as a boolean event in your host" — host-quirk scar.

---

## Family: StochasticSpectralBloom_v01 — filter

**Purpose.** Filter. Multi-octave stochastic bloom with chromatic dispersion, anamorphic squeeze, and evolving feedback trails. Header states the doctrine explicitly: "Zero-state safe: all sliders at 0 produce a visible working bloom."

**Architecture.** 2 passes: pass 0 → PERSISTENT+FLOAT `feedbackBuffer` (scene + bloom composite), pass 1 tone-map to screen. Bloom samples read the *feedback buffer*, not the input — so the bloom blooms its own trails (self-exciting).

**Techniques.**
- *Stateful float RNG*: `_rngState` global seeded from fragCoord+FRAMEINDEX with three sin-hash warmup rounds; `rand()` re-hashes state. A deliberate per-pixel-per-frame stochastic sampler without integer ops.
- *Golden-angle sample distribution*: `angle = float(oct*4+i) * GOLDEN_ANGLE + jitter` — low-discrepancy directions across octaves, jittered per frame (temporal dithering hides banding at 4 samples/octave).
- *Octave ladder*: radius ×2 per octave, weight ×falloff per octave, `for (oct<6) { if (oct>=count) break; }` const-bound pattern again.
- *Per-channel chromatic radius*: R/G/B sampled at radius −off/0/+off — spectral fringing on the bloom.
- *Anamorphic warp matrix*: `unrot * mat2(sq,0,0,1/sq) * rot` applied to the sample direction — rotatable streak bloom (lens-flare squeeze at arbitrary angle).
- *Mirrored sample pairs* (`sgn = ±1`) for symmetry at half the noise.
- *HSV trail processing*: hue-rotate + desaturate + brightness-decay the trail each frame — trails evolve color as they age.
- *SoftClip peak-based tone map*: compresses by max channel, preserving hue (`compressed = peak/(peak+knee); x * compressed/peak`).
- *Default-resolve block*: `_bloomRadius = 0.008 + bloomRadius*0.042;` etc. — all UI 0–1 inputs remapped to physical ranges in one labeled section at top of main.

**Controls.** 16 inputs, LABELed, RESET bool, banner-comment architecture doc at the top of the GLSL. **Tier 4.** Signature: golden-angle stochastic bloom; UI→physical mapping layer; self-referential bloom (samples its own trail buffer).

---

## Family: TestFilter — template

VIDVOX's stock "here are the four IMG_* sampling macros" demo (categories "XXX", empty credit). Kept as reference boilerplate. **Tier 1.**

---

## Family: TinyArrows_v01 — "Diagram overlay"

**Purpose.** Filter/overlay. Purely procedural diagram marks (+, ×, arrows, ticks) snapped to a halftone-style grid, placed by tone and density, oriented by image gradient. Outputs premultiplied RGBA overlay (`gl_FragColor = vec4(col, a)`) — designed to be composited by the host.

**Techniques.**
- *Grid snap sampler*: `snap(uv,g) = (floor(uv*G)+0.5)/G` — all tone/gradient decisions made once per cell, not per pixel.
- *SDF vector marks* built from `sdLine` capsules; arrow = shaft + two head strokes; marks rotated by gradient angle: `align = mix(0.0, ang, edgeAlign)` — continuous blend from unaligned to edge-following.
- *Sobel on snapped luminance* (8 IMG_NORM_PIXEL taps at cell resolution) for direction.
- *Stochastic placement*: `place = step(1.0 - density, hash21(cell + seed))` plus per-cell jitter from `hash22`; user-facing `seed` slider (0–9999) for re-rolling layouts.
- *Tone gating*: `smoothstep(toneMin, toneMax, L)` — marks appear only in a tonal band.

**Controls.** 12, LABELed, including the enum-as-float `markType` "0=Plus 1=Cross 2=Arrow 3=Tick" documented in the LABEL. **Tier 3.** Signature: cell-snapped analysis + SDF glyph synthesis; premultiplied overlay output convention.

---

## Family: ArsonRivvers_TorusWarp_v01 — filter

**Purpose.** Filter. UV distortion combining a "figure-eight knot" parametric offset and a torus-derived offset modulated by image brightness, with a second pass that re-distorts along the depth gradient ("self-intersection"). Credit: "Generated with help from OpenAI's ChatGPT".

**Architecture.** 2 passes; uses the legacy `PERSISTENT_BUFFERS: ["feedbackBuffer"]` array + PASSES (older ISF idiom; buffer isn't actually used across frames — it's just an inter-pass scratch target). Depth smuggled through the alpha channel: pass 0 writes `finalColor.a = clamp(totalDepth,0,1)`, pass 1 computes a 4-tap gradient of `.a` and offsets UVs by `depthGradient * selfIntersectionIntensity`.

**Techniques.** Parametric knot/torus math driving 2D UV offsets; per-pixel depth from `inputColor.r` scaling the torus offset (`(depthValue*2-1) * warpIntensity`); alpha-channel side-band communication between passes. **Tier 2–3.** Rough edges: knot math is decorative rather than principled; alpha hijack breaks downstream alpha compositing — negative knowledge: this is the pattern the later Depth Wireframe family replaces with an explicit depthMap input.

---

## Family: AR_Tron v01–v12 + v\`0 (14 files) — "Depth Wireframe" ★ flagship evolution

**Purpose & visual identity.** Filter with dual image inputs (`inputImage` + `depthMap`). Renders the depth map as a glowing 3D neon wireframe lattice — a Rutt-Etra / Tron-grid hybrid: grid vertices displaced in 3D by depth, tilted/rotated, projected back to 2D, drawn as laser lines with glow, colored by depth.

**Architecture.** Single pass, every version. The core algorithmic idea (constant across all 13 revisions): for each output pixel, inverse-project to estimate the grid cell under it, then loop a *bounded neighborhood* of grid vertices (7×7 → 9×9 → adaptive), and for each vertex accumulate distance-to-segment glow for the H / V / diagonal edges to its neighbors. This is "rasterize a mesh in a fragment shader by local search" — a genuinely non-ShaderToy-standard architecture.

**Techniques.**
- *Neighborhood mesh rasterization*: `approxPos = invRot * vec3(uv.x, 0, uv.y); approxGrid = (approxPos.xz*0.5+0.5)*gridRes;` then `for di,dj in [-4..4]` over vertices — bounded loops with `continue` for out-of-range (const-bounds-with-runtime-skip pattern).
- *Depth extrusion*: `p0 = vec3(pos2D.x, (d0-0.5)*DepthScale, pos2D.y)` (the `-0.5` centering appears in v06.1: "Center depth around 0 so tilt doesn't shift the grid vertically" — a learned fix).
- *Laser glow profile*, three generations:
  - v01–v07: `core = width/(dist + width*0.3); glow = width*0.5/(dist + falloff)` — inverse-distance, never reaches zero → accumulation blowout across many edges.
  - v08: bounded Gaussian `exp(-normDist²*4.0)` + smoothstep core, GlowIntensity mixed separately ("V8 FIX: Bounded exponential falloff… no infinite accumulation").
  - v09/v10: `simpleGlow` — smoothstep core + `1.0/(divisor*dist+1.0)` where divisor is driven by glowAmount (explicit comment: "Inspired by fractal shader: col += palette(...)/(400.*d)").
  - v11: back to bounded Gaussian *plus* `glowDensityScale = densityRatio²` and — the big one — **accumulation switched from `+=` to `wireColor = max(wireColor, …)`** ("fixed glow accumulation"): overlapping edges no longer sum to white; max-composite is the definitive anti-blowout.
- *Density normalization* (v08+): `densityFactor = 40.0/gridRes` scales line width, vertex size, and (v11) glow energy so changing GridRes doesn't change perceived brightness/weight.
- *Adaptive search radius* (v11): `searchRadius = clamp(ceil(4.0*densityRatio), 2, 6)` — perf scales with grid density.
- *Depth-based line thickness*: closer = thicker; v11 upgrades to a curve: `thickness = 1 + pow(1-d, curve)*(nearMax-1)*amount*(1+abs(projY)*0.5)` clamped — pseudo-perspective weight.
- *Rutt-Etra scanline mode* (v10): `displaced_y = uv.y + depth*0.3; line = fract(displaced_y * density)` — classic depth-displaced scanlines, crossfadable against the grid (`ScanlineMode` 0–1 mixes the two renderers).
- *Silhouette break* (v10): `shouldBreak = depthDiff > BreakThreshold*0.3` — suppress edges spanning depth discontinuities so foreground/background tear apart like real Rutt-Etra.
- *BrightnessBlend* (v10+): `d = mix(rawD, rawD*(0.5+brightness*0.5), BrightnessBlend)` — luminance modulates depth ("Fake Depth Blend" in v12) so it works without a real depth source.
- *Per-pixel depth-edge Sobel overlay + iso-depth contour lines* (v06.1–v08): `contourLine = 1 - smoothstep(0, width, abs(fract(depth*count)-0.5)*2)` — topo-map rings colored by contrast-adjusted depth.
- *Depth contrast S-curve*: `curved = mid + centered*(abs(centered)*(contrast-1)+1)` — cheap smooth contrast without pow.
- *Palette generations*: HSV hue-from-depth (v01–v08) → two-color `mix(ColorNear, ColorFar, d)` cyan/magenta defaults (v09–v11) → v12 procedural "Mountain" palette `0.5+0.5*sin(p.x*F + p.z*F + t + vec3(2,7,0))` evaluated from 3D position, with the Shadertoy source formula quoted in a comment.
- *GLSL ES discipline throughout*: all loop variables declared outside loops ("Loop variables declared outside for GLSL ES compatibility"), manual `transposeMat3` ("Manual transpose for GLSL ES compatibility"), inverse rotation via transpose.
- Aggressive luma-based Reinhard (`aggressiveClamp`, v11) with hard `min(result, maxBright)` ceiling; earlier `softClamp = c/(1+c*0.5)` (v08).

**Control/UI design.** 20–27 inputs; stable core vocabulary (GridRes, DepthScale, TiltX/Y, LineWidth, Intensity, DepthRange, VideoMix, BlendMode, InvertDepth) with per-version experiments. Consolidation is an explicit goal: v07 "consolidated controls" auto-derives GlowFalloff/VertexSize/ContourCount from single knobs; v08 splits GlowIntensity back out (learned that one knob was over-consolidated). Blend mode as float with legend in LABEL: "Blend (0=Add 1=Screen 2=Overlay)". v10 renames LaserWidth→LineWidth, Brightness→Intensity — vocabulary refactoring mid-family.

**Version evolution (the clearest learning trajectory in the corpus).**
- v01 (+v\`0 dup): square-grid, height-fov UV, 7×7 search, additive inverse-distance glow, HSV palette, auto-rotate wobble.
- v02: full-frame aspect-correct UV (`uv.x *= aspect`, grid X stretched), 9×9 search, blend modes (Add/Screen/Overlay) + GlowStrength.
- v03 (= "V4" label): radical simplification experiment — drops 3D rotation entirely, flat screen-space grid, aspect-correct cell counts (gridX = GridRes*aspect), adds VertexPoints + radial PulseWaves; line width in grid-space units.
- v04 (= "V5"): re-adds 3D (tilt-only, 2-angle rotation matrix), keeps vertices/pulses, DepthMin/Max band mask.
- v05 (= "V6.1"): depth-based thickness, per-pixel depth-edge detection, contour lines, DepthContrast/Midpoint, depth centered at 0.5 for tilt stability.
- v06 (= "V7"): "perfect grid alignment" — one `gridUV` used for both texture sampling and 3D projection (fixed a half-cell mismatch), control consolidation, explicit black background fix at VideoMix=0.
- v07 (= "V8"): the blowout war — bounded exponential glow, density normalization, EdgeEnhance moved from brightness to *width*, softClamp before Intensity.
- v08 (= "V9"): aesthetic reset — two-color palette, simpler glow, compact rotate2D pair replaces mat3, optional animation; drops the inverse-projection cell estimate for a simpler screen-space one (regression accepted for simplicity).
- v09 (= "V10"): Rutt-Etra features — silhouette break, scanline mode, brightness-as-depth blend.
- v10 (= "V11"): max-composite accumulation, glowDensityScale, thickness curve controls, adaptive search radius, aspect-correct grid returns, TiltY reinterpreted as shear ("Perspective Shift": `proj.x += p.y * shift * 0.5`).
- v12: fork — "Neon Mountain Wireframe": V11 chassis + procedural sine palette from 3D position; trimmed control set.
- File-label mismatch note: internal LABELs run one to two versions ahead of filenames from v03 onward (file v03 = "V4" … file v11 = "V11"); v\`0 = v01 duplicate.

**Complexity tier: 4.** Single-pass but algorithmically the densest family in the batch; conductor controls (Intensity, GridRes with density normalization) drive many internals.

**Signature moves.** Fragment-shader mesh rasterization by neighborhood search; max-composite glow; density normalization; ScanlineMode crossfade between two complete renderers in one shader; LABEL-encoded enum legends.

**Rough edges.** v08's screen-space cell estimate ignores tilt (grid can pop out of the searched neighborhood at high tilt); duplicated 40-line edge blocks ×3 per version (H/V/diag) never factored into a function; DepthFade input still present in v09/v10 headers is gone from use in v09 (dead param); v\`0 filename typo left in library.

---

## Family: AR_WatercoloringMelt v01–v08 (+ v04_conversion, v06_alt, v08_colorized) + AR_watercolors_ultra (12 files) — "Video Flow Feedback"

**Purpose & visual identity.** Filter. Optical-flow-advected inverting feedback: brightness-gradient flow vectors displace the previous frame's *inverse*, seeded by a trickle of (usually inverted) video + hash noise — produces melting, watercolor-bleed trails that chase motion. Explicitly derived from "Michael Schuresko's 2017 flow shader".

**Architecture.** All versions: 2 passes — pass 0 → PERSISTENT `bufferA` (the feedback engine), pass 1 composite/display. The engine core, stable across the whole family:
```glsl
float v0 = dot(vid(uv), lw), vx = dot(vid(uv+vec2(d,0)), lw), vy = dot(vid(uv+vec2(0,d)), lw);
vec2 flow = delta * vec2(vy - v0, v0 - vx);         // rotated gradient ≈ flow
vec3 feedback = 1.0 - prev;                          // THE inversion (core aesthetic)
result = seedBleed*(vid + noise) + feedbackMix*feedback;
gl_FragColor = vec4(1.0 - result, 1.0);              // invert back on write
```
The double inversion means the buffer alternates polarity each frame — the signature "breathing negative" look.

**Techniques.**
- *2-tap gradient optical flow* with perpendicular swizzle `vec2(vy - v0, v0 - vx)` (gradient rotated 90° = advect along iso-brightness contours).
- *Magnitude shaping* (v02+): `flow *= flowGain * pow(m, flowExp - 1.0)` — nonlinear response to motion strength (flowExp <1 boosts subtle motion, >1 gates it).
- *User-weighted flow luma* (v04+): lumaR/G/B normalized inside the shader; v08 passes weights as a **color input** (`flowLumaWeights` TYPE color) — using the host's color picker as a 3-slider bundle.
- *Signature hash*: `hash33(p) = fract(vec3(2097152.,262144.,32768.) * sin(dot(p, vec2(41.,289.))))` — appears in 10 of 12 files, the family fingerprint; screen-space scaled `noiseTex` with optional `+ TIME*noiseTime` animation.
- *Motion-direction colorization* (v02): `hue = fract(atan(flow.y,flow.x)/TAU + 0.5)` → HSV → multiply into the inverted feedback, plus tint stage — optical-flow visualization as aesthetics.
- *Feedback response curve* (v04+): `feedback = pow(max(1-prev + bleed, 0), vec3(gamma))` — bleed lifts/crushes, gamma bends trail decay.
- *TouchDesigner host guard* (v06/v06_alt/ultra): `samplePrev()` wrapped in `#if defined(TD_NUM_INPUTS) #if TD_NUM_INPUTS >= 2` conditional compilation with a fallback color — "Hardened for TouchDesigner's ISF host"; fallback `vec3(1.0)` chosen so `1-prev` starts at 0 (neutral). Cross-host portability engineering.
- *Simple/advanced dual-mode UI* (v06/v06_alt/v07): `simpleMode` bool switches between 4 macro knobs (flowSpeed, textureAmt, tone, simpleIntensity) and the full 15-param set; each macro fans out through curated `mix()` maps, e.g. `u_feedbackMix = mix(0.9995, 0.9920, flowSpeed)` (faster flow ⇒ shorter trails, a *musical* coupling), and `tone > 0.5` flips both inversion bools.
- *Reset idiom*: `if (resetBuffer) u_feedbackMix = 0.0;` — one-frame starvation wipe rather than branch-to-clear; v04_conversion instead uses `if (resetInput || FRAMEINDEX < 1) { output video; return; }` — both reset patterns coexist in the family.
- *UNHINGED build* (v08_colorized, the family's apex): adds compounding per-frame feedback transforms (fbZoom ±0.05, fbRotation ±0.1 — "even ±0.005 compounds fast. Push to ±0.05 for tunnels"), flow curl (rotate the flow vector by ±π), chromatic aberration on the buffer read (per-channel offset sampling), full FB color pipeline (contrast around 0.5, desaturation, per-frame accumulating HSV hue shift, tint), Sobel edge injection into the seed, 4-mode mirror symmetry on the feedback UV, 5 blend modes for compositing, and unsharp-mask output sharpening ("outputSharpen > 1.0: halation/ringing artifacts (useful!)"). Uses a **GLSL struct** (`MappedParams`) for the UI→physical mapping layer. Header contains a 10-line "UNHINGED NOTES" block documenting which params go wild outside intended range — performance documentation as code comments.
- *Section-divider hack* (UNHINGED): dummy bool inputs whose LABELs are `"── MASTER ──────────"` etc. — fake UI headers made of box-drawing characters, the author's solution to hosts without group support.
- *Edge Curl Trails* (v07): different advection field — Sobel *edge tangent* (`vec2(-g.y, g.x)`, perpendicular to gradient) blended with *curl noise* (perpendicular gradient of a hash field), step length gated by edge magnitude: `flow = normalize(mix(tdir, curl, swirl))` — trails crawl along and swirl around edges rather than following motion.

**Control/UI design.** From 5 inputs (v01) to 30 (UNHINGED). Naming stable across the family (flowDelta, feedbackMix, noiseGain/Scale/Time, seedBleed, invertVideo/invertOutput, mirrorX). Progressive normalization: raw physical ranges (v01–v06) → all-0-1 UI with internal `mapParams()` remapping (v08/UNHINGED). Simple/advanced macro-mode. Section dividers. Reset as bool or event.

**Version evolution.** v01: minimal port of Schuresko (hardwired mirror, fixed luma). v02: colorization + flow shaping + staged mixing. v03: "No Mirror" variant + effectAmount crossfade. v04: "Advanced" — luma weights, gamma/bleed curve, directional mix, animated noise, both inversion toggles. v04_conversion: "Advanced, Stable" — adds FRAMEINDEX/reset init and switches to `gl_FragCoord/RENDERSIZE` coords. v05: same as v04 but with the coord fix (comment: "Correctly get normalized fragment coordinates") — isf_FragNormCoord evidently misbehaved in some host. v06/v06_alt: Simplified dual-mode + TD hardening (alt returns fallback-color; non-alt returns black — two experiments in fallback policy). v07: Edge Curl fork. v08: back-to-basics remapped "Advanced" (72 lines). v08_colorized: UNHINGED. watercolors_ultra: v08 + samplePrev guard merged — the consolidated "best of" build.

**Complexity tier: 4** (UNHINGED/ultra); v01 alone is a 2.

**Signature moves.** Double-inversion feedback polarity; UI→physical mapping layer with struct; macro/conductor simple-mode; TD conditional-compile guards; box-drawing section dividers; documented "unhinged zones" per parameter.

**Rough edges.** v05 and v04 are near-identical (coord system being the only real diff) — versioning by tiny host fix. `flowDirMix` mixes *between two direction conventions* rather than rotating — a hack kept for compatibility. The v06 black-fallback vs v06_alt white-fallback split shows an unresolved host question left as two files. UNHINGED's `_lbl*` dummy bools pollute OSC/MIDI address space in hosts.

---

## Family: AR_Waterfall_mobius / Waterfall1 / Waterfall2 — Shadertoy conversion studies (3 unrelated files)

**Waterfall_mobius_v01** ("Luminous Möbius Waterfall", from Shadertoy N32GWG). Generator, single pass, zero inputs. Full raymarcher: Möbius-strip SDF (box cross-section rotated by half the sweep angle: `q = vec2(r*c + p.y*s, -r*s + p.y*c)` with `c=cos(a*0.5)` — the half-twist), 3D value-noise fbm fluid height, *inverse-flow surface parameterization* (`surfaceFlow` rewinds a point along the strip by `time` with a stretch factor, so noise flows along the topology seamlessly), angle-unwrap helper for finite-difference bump normals across the ±π seam (`unwrap(a, ref)`), triplanar-style bump via gradient projected off the normal, 5-tap AO, exp-falloff volumetric glow accumulated during the march, ACES-approx tonemap. **Tier 4** as code, but a conversion with zero performance controls — study material, not a VJ instrument.

**Waterfall1_v01** ("winter", wyatt's SandStorm fork, Shadertoy lX3yD8). Generator. **5 passes, 4 PERSISTENT+FLOAT buffers (bufA–bufD)** — a falling-sand/snow particle simulation in textures: passes 0/1 gather particles from a 7×7 neighborhood (position stored in texel .xy, mass in .w, conservation via weighted average), pass 2 applies forces (neighbor-pressure sum, velocity via `inversesqrt` limiter, drag `exp(-.01*mass)`), pass 3 tracks color/age, pass 4 displays mass-weighted tint. Converted with per-pass channel-remap shims (`_ch0_tex` switches source buffer by PASSINDEX — mechanical Shadertoy-multibuffer → ISF translation), mouse as point2D, `FRAMEINDEX < 1` init, commented-out wall-bounce block. The only true multi-buffer particle system in the batch. **Tier 5 architecture** (inherited, not authored — but its conversion shims are exactly the author's ISF-porting playbook).

**Waterfall2_v01** ("scrolling nebula", Shadertoy clX3zl). Generator. Uint-hash (`uvec2 * UI0/UI1`, xor-multiply) value noise; 4-octave rotated fbm (`mat2(0.36,0.80,-0.80,0.36) * scale 2.12`); two scrolling noise layers where layer 1 warps layer 2's x ("we fuck layer2 with layer1 a touch for a lavalamp style effect" — original's comment retained); voronoi starfield using a *texture fetch as RNG* (`IMG_NORM_PIXEL(iChannel0img, p/256.)` — expects a noise texture input, a Shadertoy-ism that silently degrades in ISF without the right image); star mask from color darkness. **Tier 3.** Rough edge: `color = color.zyx` swizzle unconditionally applied (mouse conditional commented out) — conversion scar.

---

## Family: AR_WeirdBlackPuddles_v01 — motion blur

**Purpose.** Filter. Motion-estimated blur with trails (Shadertoy Xsc3DS conversion). 4 passes, 3 PERSISTENT+FLOAT buffers: PrevFrame (frame delay), MotionVectors, BufferA (blur accumulator), display.

**Techniques.** *Brute-force block matching*: 17×17 search (`for y,x in ±8`) comparing current pixel color to previous-frame neighborhood, keeping the offset of best match — O(289) taps, a real motion estimator, however crude; magnitude thresholded by `motionSensitivity`; motion vectors scaled ×20 into the buffer. Pass 2: 8-sample directional blur along the motion vector + trail mix with previous BufferA gated by motion magnitude. Explicit `WIDTH/HEIGHT: "$WIDTH"/"$HEIGHT"` in PASSES (only file in batch using the sizing variables). **Tier 3.** Rough edges: single-pixel block matching (matches color, not blocks — noisy vectors, hence the "weird black puddles" name presumably); no FRAMEINDEX init on PrevFrame.

---

## Batch synthesis

**Top 3 most sophisticated files.**
1. **AR_Tron_v11.fs** ("Depth Wireframe V11") — the culmination of a 12-revision engineering arc: fragment-shader mesh rasterization with adaptive search radius, density-normalized bounded Gaussian glow, max-composite accumulation (the definitive fix for additive blowout), curved depth thickness with pseudo-perspective, shear-based perspective shift, plus the whole V10 Rutt-Etra feature set (silhouette break, scanline crossfade, brightness-as-depth).
2. **AR_WatercoloringMelt_v08_colorized.fs** ("Video Flow Feedback UNHINGED") — a complete live-performance feedback instrument: optical flow + curl + compounding zoom/rotation transforms + chromatic aberration on the buffer read + per-frame hue accumulation + edge injection + mirror symmetry + blend modes + unsharp output, with struct-based param mapping, box-drawing UI section headers, and a header block documenting each parameter's "unhinged zone".
3. **AR_StochasticSpectralBloom_v01.fs** — golden-angle stochastic multi-octave bloom with per-channel chromatic radii, rotatable anamorphic warp matrix, stateful float RNG, HSV-evolving trails, and the family's clearest statement of the zero-default doctrine.

**Recurring patterns / style fingerprints.**
- **Const loop bound + runtime break/continue** everywhere (`for (i<MAX) { if (i>=n) break; }`) — the Metal-host workaround as house style.
- **Zero-default doctrine**: new features default to 0/off so defaults reproduce the previous version or a guaranteed-visible baseline ("Zero-state safe", "At defaults, identical to the original").
- **UI→physical mapping layer**: all-0-1 sliders remapped at the top of main via `mix()` (or a struct) — decouples host UI from DSP ranges.
- **Simple/advanced dual-mode** and **macro knobs that fan out through curated mix() couplings** (flowSpeed simultaneously driving delta, gain, exp, and decay).
- **Section labeling**: LABEL on first input of a group (colorsplash) escalating to dummy-bool box-drawing dividers (UNHINGED).
- **The hash33 fingerprint** (`fract(vec3(2097152,262144,32768) * sin(dot(p, vec2(41,289))))`) and the 12.9898/78.233 classic — two hash families, used consistently.
- **Reset idioms**: event/bool reset + `FRAMEINDEX` guard; the elegant `feedbackMix = 0` one-frame starvation wipe.
- **Reinhard-family tone stages** in every accumulating shader (whiteMapping / softClamp / aggressiveClamp) — hard-won blowout defense.
- **GLSL ES paranoia**: loop vars declared outside loops, manual transpose, scalar ternaries only, `max(x, 1e-6)` denominators.
- **Host portability scars**: TouchDesigner `TD_NUM_INPUTS` conditional compilation, `gl_FragCoord/RENDERSIZE` preferred over `isf_FragNormCoord` after a documented host bug, notes about event-vs-bool reset behavior.
- Filenames as working titles that drift completely from LABELs; versioning includes "back-to-basics" resets (Tron v09, Melt v08) — the author deliberately simplifies after complexity peaks.

**Unexpected / beyond-ShaderToy techniques.**
- Fragment-shader **mesh rasterization by inverse-projected neighborhood search** (Tron family) — vertex-shader work done in a fragment shader because ISF has no geometry stage; I've not seen this pattern in standard ShaderToy fare at this level of refinement.
- **Max-composite glow accumulation** as a principled alternative to additive glow (v11) — a discovered, not textbook, fix.
- **Density normalization** (line width, vertex size, and glow *energy* scaled by 40/gridRes and its square) — perceptual-constancy engineering across a resolution control.
- **Conditional-compilation host guards** inside ISF (`TD_NUM_INPUTS`) — cross-host defensive shader engineering.
- **Parameter-space wet/dry** (Solarize: effectAmount morphs the algorithm's parameters, not the output mix) and per-pixel organic transition weighting.
- **Documented "unhinged zones"** — treating out-of-range parameter behavior as a performable feature and shipping the map in comments.
- **Color-typed input as a 3-slider bundle** (flowLumaWeights) and **bool-typed inputs as UI section headers** — creative abuse of the ISF type system for UI ends.
