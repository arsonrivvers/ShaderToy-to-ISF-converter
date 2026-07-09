All 34 files read in full. Per the coordinator's instruction, here is the complete report (no file written).

# Batch 10 Analysis Report — AR_Genuary2026 day11 & day12

## Coverage
- files_assigned: 34, files_read: 34, misses: none
- Files: AR_Genuary2026_day11_v01–v09 (9), day11_alt_v01–v09 (9), day11_altb_v01 (1), day12_v01–v13 (13), day12_v1 (1), day12_alt_v01 (1). All in /Library/Graphics/ISF/.

---

## Family 1: Day11 Quine — main line (v01–v09, 9 files)

**Purpose & visual identity**: Generator. Genuary "write a quine" prompt: the shader renders its own source code as a grid of 3×5 bitmap-font glyphs on screen, with a "chaos engine" that modulates per-cell glyph scale via a gradient-from-focus-point mixed with hash noise.

**Architecture**: Single pass, no buffers throughout. Dispatch is pure `main()` with early-`return` bail-outs (out-of-cell-bounds → paint bg and return). All data (source text and font) lives in giant constant lookup functions — a hand-rolled ROM in shader code.

**Techniques**:
- **Bitmap font as 15-bit integers**: each 3×5 glyph packed into one int (`if (c==48) return 31599; // 0`). Bit extraction avoids bitwise ops entirely for host compatibility:
  ```glsl
  int bitIndex = 14 - (row * 3 + col);
  float divisor = pow(2.0, float(bitIndex));
  float val = floor(float(bits) / divisor);
  if (mod(val, 2.0) >= 1.0) isBit = true;
  ```
  This float-math "safe bit extraction" is the family's foundational trick and repeats verbatim in ~18 files.
- **Quine data ROM**: v01/v02 use `getD(int i)` — one `if` per character index returning ASCII of the shader's own header (`/*{ "ISFVSN": "2.0" ...`). v03 truncates and pads with procedural "code-like" filler (`if (modI > 45) return 59; // ;`).
- **Byte-packed data (v04+)**: architectural upgrade — 4 ASCII chars per 32-bit int, decoded with float shift/mask: `float shifter = pow(256.0, 3.0 - float(byteOffset)); return int(mod(floor(float(packedVal)/shifter), 256.0));` — a big-endian byte extractor with zero bitwise operators. Comments explicitly note the equivalence: `// Equivalent to: (packedVal >> ((3-offset)*8)) & 0xFF`.
- **Variable-density grid ("Ref3 composition")**: per-cell zoom by remapping local UV: `vec2 scaledUV = (localUV - center) / scale + center;` with out-of-range clip. Scale driven by `mix(minScale, maxScale, mixedMap)`.
- **Gradient/chaos mixer**: `mixedMap = mix(smoothstep(0,1.4,distance(uv,focusPoint)), hashNoise(cell,seed), chaosAmount)` — a spatial gradient cross-faded with per-cell randomness; then optional threshold-renormalize (`(n-thr)/(1-thr)`) and quantize (`floor(m*steps)/steps`).
- **Seed-as-animation**: animating noise by adding `TIME*animationSpeed` to the hash *seed* rather than the coordinate (v06/v07) — cheap full-field refresh flicker.
- **Scroll-through-data**: `charPtr = int(mod(cellIdx + TIME*scrollSpeed*10.0, 200.0))` — the text stream flows through fixed grid slots.

**Control/UI design**: Grows 2 → 15 inputs. camelCase NAMEs, Title Case LABELs. Emerging conductor pattern: `chaosAmount` is a single macro fader from ordered gradient to full noise. Coarse/fine pair: `seed` (which pattern) vs `noiseScale` (pattern granularity). `invert` bool for projection-mapping-friendly polarity flip.

**Version evolution** (a textbook learning trajectory):
- v01: static self-render, "Universal Compatibility Mode" (no bitwise ops), recursion of print logic explicitly removed "for brevity/stability".
- v02: "Quine Reader" — one character at a time, typewriter, with zoom control.
- v03: whole-grid composition + gradient size field (the reference-artwork "Ref3" look).
- v04: data storage rewritten to packed ints (4 chars/int) — pure architecture rev, visuals unchanged.
- v05: gradient generalized to movable focus point + chaos slider.
- v06: seed control + animate-noise; comments explain seeding shifts the hash domain.
- v07: dedicated `animationSpeed` decoupled from other speeds; adds threshold + quantize.
- v08: "CORRECTED VERSION" — fixes cols/rows axis bug, noiseScale semantics, quantize formula (`floor(m*steps+0.5)/steps`, works from 2.0), centers focus defaults, ships a complete 3×5 font for ALL printable ASCII with per-glyph pixel-art comments (`// 2: ███   █ ███ █   ███`), unknown chars now blank instead of '8'. Also *inverts* scale mapping (focus = large).
- v09: "CORRECTED VERSION v2" — the font is re-verified glyph by glyph (dozens of bitmap constants changed vs v08); dead code from v08's double grid calculation removed.

**Complexity tier**: 2–3 (v01 is tier 2; v05–v09 tier 3 — single pass but a real parametric composition system).

**Signature moves**: int-packed bitmap fonts + float-math bit extraction; byte-packing 4 chars/int; the `(localUV-center)/scale+center` per-cell zoom; gradient⊕noise conductor.

**Rough edges**: v08 contains visible mid-refactor scrap (grid computed one way, then immediately recomputed "Simpler fix:" below). `cellIdx` uses non-integer `cols` (float aspect) so rows drift — accepted as texture rather than fixed until alt-line v08. Fonts before v09 have wrong/reused glyphs (S=5, U=A reuse noted in comments).

---

## Family 2: Day11 Quine — alt line "Chaos Engine Pro" (alt_v01–v09, 9 files)

**Purpose & visual identity**: Generator (+"Stylize"). The performance-grade fork of Family 1: same quine/font ROM core, escalating into a full VJ instrument with cinematic color grading, a modular glitch engine, scan bands, and per-row flow.

**Architecture**: Single pass throughout, even at 1785 lines. Structured with banner-comment sections (`// --- UTILS ---`, `GLITCH ENGINE`, `CINEMATIC COLOR GRADING`, `OCULAR EFFECTS`, `DATA SOURCE`, `MAIN RENDERER`) — module discipline inside one file. Deliberate ordering: UV-space glitches → grid/data lookup → glyph rasterize → 10-stage post pipeline.

**Techniques**:
- **alt_v01** (dot-grid variant): renders each character as a *dot whose radius encodes the glyph's bit-count* (`countBits`→weight→radius) — data-as-typography abstraction. Timed "decode" reveal: per-char stability ramps via `smoothstep(decodeTime-2, decodeTime+1, t)` with probabilistic true-char reveal, otherwise random glitch char — a Matrix-decode effect built from three hashes. Also plus-sign corner registration marks (print-layout aesthetic).
- **alt_v03**: 3-layer **parallax compositing** in one pass — `renderLayer(uv, depth, t)` called at depths 1.8/1.3/1.0, far layers scaled, slower (`layerSpeed = scrollSpeed*depth`), prime-offset (`depth*123.45`) and manually alpha-blended; foreground layer rendered 3× for **per-layer chromatic aberration** (true re-render RGB split, not a color trick). Quantized "typewriter" time: `qTime = floor(TIME*typeSpeed)/typeSpeed`. Luminance-preserving hue rotate around vec3(0.577): Rodrigues-rotation `rotateHue()`.
- **alt_v04**: bolts on a full **cinematic grading stack**: rgb2hsv/hsv2rgb, lift-gamma-gain (`pow(max((c+lift)*gain,0), 1/gamma)`), contrast pivot 0.5, temperature (r+/b−), tint (g vs magenta), and **10 named film-look presets** (Cyberpunk, Matrix, Blade Runner orange/teal via `mix(teal,orange,luma)`, Tron, Vaporwave hue+0.8, Film Noir crush, Thermal 2-stage LUT, Neon Dreams `col+=col*col*0.3`, CRT Phosphor). Plus vignette/scanline/grain/bloom-approx helpers with strict application order (HSV shift → preset → temp/tint → LGG → contrast → CA → bloom → scanlines → grain → vignette → clamp).
- **alt_v05**: **scan bands** — moving horizontal masks with wrap-around distance (`dist=min(|y-p|, |y-p±1|)`) and 6 effect modes (brighten/darken/invert/colorize/glitch/scale-boost), 4 travel modes (up/down/ping-pong/random-jump via `fract(sin(floor(t*speed))...)`), plus a "sorting animation" that displaces character indices inside wave bands using a selectable waveform (sine/tri/saw/square `getWaveform`). Const loop bound + runtime `break` (`for (float i=0.; i<10.; i++){ if (i>=scanBandCount) break; ...}`) — the documented host workaround.
- **alt_v06**: the **glitch engine** — 9 orthogonal, individually parameterized glitch functions, all gated by a `glitchMaster` multiplier: stepped temporal random (`steppedRandom(t,speed,seed)` = hash of `floor(t*speed)`), row shift (per-row chance + amount + sub-shift chaos), block glitch (returns vec4 = offsetXY/corrupt/colorShift), RGB split with 4 spatial modes (H/V/radial-`atan`/wave), wave distortion (3 stacked sines + temporal gate), thresholded static noise with colored artifacts, temporal jitter, **frame hold** (quantizes the time variable other effects consume: `return floor(t*speed)/speed`), data corruption (block-random offsets into the char ROM), screen tearing (moving band x-offset).
- **alt_v08**: **centered integer grid** — computes `nCols = floor(aspect/cellSize)` and bounds `vec2 gridBounds = vec2(nCols,nRows)*cellSize*0.5`, rejecting pixels outside so only whole cells render, centered — fixes the partial-cell edge artifact of every earlier version.
- **alt_v09**: **Vector Flow / row flow calculator** — per-row scroll with 4 direction modes (unified / alternating `mod(row,2)` / pairs / random), per-row static speed variance from a seeded hash, and a sine speed-wave over row index. Replaces global scroll entirely (`cellIdx` uses `effectiveX = cellX + getRowScroll(...)`).

**Control/UI design**: This family is the UI story of the batch. alt_v06 hits ~60 inputs, then **alt_v07 "UX Redesign" keeps identical engine code but rewrites every LABEL into a namespaced hierarchy**: `"Grid: Cell Density"`, `"Glitch: RGB Split"`, `"Adv: ..."`, `"Tuning: ..."` — plus **separator pseudo-inputs**: a float named `glitchMaster` labeled `"--- GLITCH MASTER ---"` and a long labeled `"--- LOOK: PRESET ---"` doubling as section headers in the host UI. Input JSON also flips from hand-written floats (`15.0`) to serialized ints (`15`) — evidence of round-tripping through a JSON tool. Master/child gating everywhere: every glitch function early-returns unless `master > 0 && amount > 0` (also a perf win). Speed controls for *everything* (9 distinct `*Speed` params in v06).

**Version evolution**: alt_v01 (dot decode) → alt_v02 (bit-grid chaos engine, merges "Shader 1" data with "Shader 2" renderer — the CREDIT fields narrate the merge) → alt_v03 (parallax/color-system side-quest) → alt_v04 (cinematic post) → alt_v05 (scan bands/sorting) → alt_v06 (glitch engine, biggest jump) → alt_v07 (pure UX pass; screen tearing feature *removed* — `// 4. SCREEN TEARING REMOVED`) → alt_v08 (centered-grid geometry fix) → alt_v09 (per-row vector flow). Clear cadence: feature rev → consolidation/UX rev → geometry-correctness rev.

**Complexity tier**: 3 for alt_v01–03; **4** for alt_v06–v09 (single-pass but a multi-subsystem instrument with a conductor + ~60-parameter surface). Not 5 only because there is no feedback/simulation pass.

**Signature moves**: glitchMaster conductor gating 9 sub-effects; UI namespacing + separator inputs; steppedRandom as the universal temporal-glitch primitive; frame-hold implemented as time quantization consumed downstream; scan-band mask with wraparound; per-row flow direction modes.

**Rough edges**: The RGB split is applied as per-pixel color arithmetic, not UV re-sampling (comment admits "Simulate RGB channel separation") — a single-pass compromise; alt_v03 did it properly by re-rendering. `sortingDirection` is reused to drive scan-band direction (copy-paste coupling). The 256-char ROM (~230 `if` statements) is duplicated verbatim in 7 files — no include mechanism in ISF, so the ROM is boilerplate cargo. `charCorruption`'s `vec2 uv` parameter unused in `getGlitchHold`. Chromatic aberration in the post stack is a brightness trick, unlike alt_v03's honest version.

---

## Family 3: Day11 altb — "3D Monolith Light" (altb_v01, 1 file)

**Purpose & visual identity**: Generator, cinematic 3D. A dark triangular monolith on a ground plane in volumetric atmosphere, orbiting camera and warm/cool orbiting light — a complete photographic scene, totally unlike the quine line (a fresh "b" branch).

**Architecture**: Single pass; classic raymarch pipeline with `#define MAX_STEPS 128 / MAX_DIST 50 / SURF_DIST .001`; separate cheap marchers for shadows (48-step soft shadow), glow probing (32 fixed samples along missed rays), and volumetrics (24–64 steps scaled by a quality slider).

**Techniques**:
- **SDF scene**: `sdTriPrism` remapped into a wedge monolith (`sdMonolith` = axis-swizzled prism ∩ bounding box), ground as `p.y - groundLevel`, dual-return raymarch reporting *which* object was hit via `hitMonolith = (mono < ground)`.
- **OKLab color pipeline**: full sRGB↔linear↔OKLab converters and `oklabMix()` (smoothstepped t) used for light warmth blending and sky gradients — perceptual color interpolation inside a live shader is well beyond ShaderToy habit.
- **Volumetric lighting**: per-step soft-shadowed scattering with exponential height-falloff density, 3D value-noise density variation, Rayleigh-ish phase `0.75*(1+cos²)` plus `pow(cosAngle,8)` forward scatter, and transmittance accumulation with early exit at 0.01.
- **Edge glow + chromatic glow**: for rays that *miss*, march 32 samples recording closest approach to the SDF, then `exp(-minDist/glowSpread)` halo modulated by light-facing; chromatic version re-runs it with 3 slightly rotated ray directions and takes R/G/B channels — spectral edge fringing around the silhouette.
- **ACES tone map**, lift-style exposure `pow(2, exposure)`, contrast pivot at 0.18 grey, luminance-weighted film grain, `filmGrainNoise` from value noise.
- Fresnel edge highlight on the near-black monolith (`pow(1-dot(n,-rd),4)`) so the shape reads only by rim and occlusion.

**Control/UI design**: 35 inputs, rigorously grouped by prefix-in-order (camera*, light*, monolith*, atmosphere/volumetric, glow*, chromatic*, godRay*, ground*, then grading). Auto-orbit speed params default non-zero (0.02/0.04) — installation-friendly self-animation. `volumetricSteps` is a normalized 0.2–1.0 *quality* knob mapped to step count, not a raw count.

**Version evolution**: single version; reads as a one-shot "cinematic edition" study.

**Complexity tier**: **4** — full raymarched scene with soft shadows, AO, volumetrics, OKLab grading; not 5 (no feedback/multi-pass, and the god-ray function is vestigial).

**Signature moves**: OKLab mixing; closest-approach glow for missed rays with per-channel ray-rotation chromatic fringe; quality-slider-scaled volumetric loop.

**Rough edges**: `godRays()` takes a `sampler2D occlusionHint` argument that is never supplied and the function is never called — dead code from an abandoned screen-space pass (ISF single-pass limitation bit here). `calcAO` computed only for hits. Camera tilt applied by bending `camForward` after basis construction (approximation, noted stylistically).

---

## Family 4: Day12 alt — translucent squares tunnel (alt_v01, 1 file)

**Purpose & visual identity**: Generator. A looping stack of soft-edged translucent squares receding along a user-set 2D spread vector — a minimal 2.5D tunnel.

**Architecture**: Single pass; back-to-front loop of up to 40 slices with early break at `count`.

**Techniques**: Painter's-algorithm compositing in one pass: `finalColor = layer*layer.a + finalColor*(1-layer.a)` looping back-to-front. Seamless loop via phase recycling `z = (i + (1-phase))/count` and — key trick — a **fade window hiding the wrap pop**: `fade = smoothstep(0,.15,z)*smoothstep(1.1,.85,z)`, an honest solution the comments reason through aloud. `point2D` input for direction/spread. Soft square edges via double smoothstep on `abs(boxUV)`.

**Control/UI design**: 7 inputs incl. two color inputs with meaningful alpha defaults (front 0.8, back 0.1 — transparency designed in) and a point2D. Comment-heavy deliberation style ("Actually, for a seamless loop, we want...").

**Complexity tier**: 2. **Signature move**: loop-pop concealment fades. **Rough edges**: unused `box()` SDF helper left at top; the long think-aloud comment about the phase jump documents an unresolved-but-masked artifact.

---

## Family 5: Day12 v01–v03 — Reaction-Diffusion Automata (3 files)

**Purpose & visual identity**: Generator/filter hybrid (v01/v02 take a seed `image` input). A three-channel cascade reaction-diffusion / cellular automaton producing coral-like RGB growth, with a moving "cursor" object injecting live cells. The only PERSISTENT-buffer family in the batch.

**Architecture**: **2 passes**: pass 0 → `buffer_a` PERSISTENT+FLOAT (simulation), pass 1 → display. `PASSINDEX` dispatch in main. Init idiom exactly the documented house pattern: 
```glsl
if (FRAMEINDEX < 2 || reset) { ...seed from image or hash noise... }
return IMG_NORM_PIXEL(buffer_a, p).rgb;
```
with an `event`-type `reset` input and a seed-image fallback test (`if (seed.a == 0.0)` → random).

**Techniques**:
- **Ring-sampled neighborhood**: instead of a box kernel, neighbors are sampled on concentric circles: outer loop radius `r=1..10` (const bound, `break` past `radius` slider), inner loop `points = density*r` samples at `angle = 2πp/points`, accumulated as `n += state/r` — a 1/r-weighted disc integral. Radius and angular density are both live-tweakable rule parameters.
- **Cascade RD rule** (unusual, parabola-threshold):
  ```glsl
  live.r += -pow((n.r)/2.0 - gap, 2.0) + gap;
  live.g += -pow((n.r + n.g)/3.0 - gap, 2.0) + gap;
  live.b += -pow((n.r+n.g+n.b)/4.0 - gap, 2.0) + gap;
  live = step(1.0, live);
  ```
  Each channel's survival depends on the mean of itself + all previous channels — a coupled 3-species automaton with binary `step` output; `gap` is a one-knob rule bifurcation control.
- **Geometry injectors**: the sim is "drawn into" by white shapes. v01: circle cursor (auto orbit `cos/sin(TIME*speed)*0.6` or manual XY sliders). v02: a **3D wireframe box** (`sdBoxFrame`) tumbling via axis-angle `rotate3D`, intersected with the z=0 canvas plane — 3D SDF evaluated in 2D sim space as a stamp. v03: a rotating **diamond-lattice wireframe** (5 rings × 12 points + verticals + diagonal braces) built from rotated 3D points projected to `.xz`, with exact point-to-segment distance (`clamp(dot(uv-p,dir)/len2,0,1)`).
- **v02 pass 1 — heightfield raymarch of the sim**: display pass raymarches a terrain whose height = `buffer_a.r * viewHeight`, camera orbit slider, normals from finite-difference of the buffer, diffuse light + exponential fog: the 2D automaton becomes 3D terrain. Cross-domain: a feedback sim consumed by a raymarcher in the same file.

**Control/UI design**: sim params (gap/radius/density) separated from injector params; `event` reset; auto/manual cursor with bool switch. v02 labels prefix by role ("Rule: Gap", "Sim: Radius").

**Version evolution**: v01 ShaderToy conversion with ISF-native seeding/reset; v02 replaces cursor with 3D box injector + adds raymarched display pass; v03 strips the image input (self-seeding only) and goes for the most elaborate injector geometry with thickness control. Trajectory: converting → hybridizing (sim × 3D) → sculpting the injector.

**Complexity tier**: **4–5** (v02 is the batch's peak architecture: PERSISTENT feedback sim + geometric injection + raymarched heightfield display; tier 5 by the rubric's "multi-pass simulation system", conservative 4.5).

**Signature moves**: ring-kernel RD; parabola-gap rule; "inject life via SDF stamps"; sim-as-heightfield second pass.

**Rough edges**: inner sample loop worst case 10 rings × ~320 points = brutally expensive (const bound 1000 with break — quirk-compliant but heavy); v02's terrain normal uses `pos.y` as "approximate" current height (comment admits); nested-loop break pattern relies on the runtime honoring early break for performance.

---

## Family 6: Day12 v04–v13 + v1 — Fractal Box Lattice / Menger line (11 files)

**Purpose & visual identity**: Generator. A rotating kaleidoscopic fractal of folded boxes ("kifs" — kaleidoscopic IFS), evolving from solid grey raymarch to a neon "laser lattice" X-ray instrument. The batch's strongest example of one core `map()` carried through ten aesthetic reinventions.

**Architecture**: All single-pass raymarchers. Core fold (constant across all versions):
```glsl
float t = base_size;
for (int i = 0; i < 13; i++) {
    t = t * fractal_scale;
    p.xy = m * p.xy;  p.yz = n * p.yz;  p.zx = nn * p.zx;
    p.xz = abs(p.xz) - t;
}
```
— three global mat2 rotators (built in main from `-0.001/0.0035/0.0023 * ui` — mutually irrational-feeling rates) + abs-fold with shrinking offset. Marching is the minimalist `dive()` (`p += d*map(p)` fixed 20 iters, no epsilon test) in early versions, later a proper `castRay` with hit epsilon and max distance.

**Techniques**:
- **v05 (the origin, "Parametric")**: sphere at the fold's end, light as an SDF *object in the scene* (`vec4 g_light` = position + radius), shadows by re-diving toward the light and testing whether the ray reached the light sphere: `if (length(bounce - light.xyz) > light.w + 0.1) col *= 0.2;` — shadowing without a shadow function. GLSL-strictness fixes annotated (`// FIX: strict GLSL requires vec2 subtract`) and `light`→`g_light` rename "to avoid namespace collisions" (VDMX scar).
- **v04**: sphere→`sdRoundBox` with roundness param; scale-proportional box size `vec3(box_scale * t)`.
- **v06**: true **Menger sponge** — abs + axis-sort fold (`if (p.x<p.y) p.xy=p.yx; ...`), cross-carve `c = (min(max(p.x,p.y), min(max(p.y,p.z), max(p.x,p.z))) - 1.0)/s`, `sponge = max(sponge, -c)`, plus rotation inside the fold ("keeps the animation alive"), all **intersected with a container box in original space** (`max(sponge, sdBox(p_origin, size))` — "Force Square Dimensionality").
- **v07**: `sdBoxFrame` (iq's wireframe box) + `sdHollowBox`, a 3-mode `boxPrimitive()` switch (Frame/Hollow/Solid), and — key idea — **multi-level rendering**: draw a box at *every* fold iteration within `[min_level, max_level]`, so the fractal's intermediate scales coexist. Normal-variance edge glow post effect.
- **v08 ("Menger Laser Lattice")**: the aesthetic breakthrough — discard shading entirely; **curvature-based laser edges**: sample normals at ±eps in two axes, `curvature = length(n1-n2)+length(n3-n4)`, `pow(curvature,4.0)`, color `mix(deepBlue, cyan, curvature)`, times intensity, with `1/(1+t²·0.01)` falloff. Geometry edges become self-luminous laser lines.
- **v09**: separates *morph* (in-fold rotation speed) from *whole-object rotation* — rotating camera ray (`ro = rot*ro; rd = rot*rd;` with per-axis speed sliders), commented "rotate the camera/rays (light) instead of object points (heavy)".
- **v1 ("Volumetric Menger Transparent")**: replaces surface marching with **glow accumulation volumetrics**: march *through* with `t += max(abs(d)*step_smooth, 0.05)` (minimum step = transparency hack), per-step `glow = exp(-dist*glow_sharpness)`, front-to-back accumulation `finalColor += palette·glow·density·(1-opacity)` with opacity absorption and early exit; **IQ cosine palette** (`a+b*cos(2π(c*t+d))`) with user hue shift; **per-pixel dither on start t** (`t += dither*0.1`) to kill banding.
- **v10 ("X-Ray Laser Edition")**: **multi-hit raymarching** — `castRayXRay` records up to 4 surface crossings by pushing through each hit (`t += 0.05`) with a minimum-separation guard, then shades each layer with the laser-edge treatment, additively with `xray_falloff` per layer. Now 6-axis curvature sampling. 4 color modes (cyan/depth-rainbow/heat/custom).
- **v11 ("Enhanced")**: **depth-aware line weight** — `depthScale = 1+dist*depth_line_scale` widens the curvature-sampling epsilon and softens sharpness with distance ("KEY FIX: near objects get fine detail, far objects get thicker lines") — a hand-built LOD for line rendering; `mapWithLevel(out hitLevel)` returns *which fold iteration* was hit, enabling "Level Gradient" coloring by fractal depth; adaptive-epsilon normals; 3 X-ray blend modes (additive/screen/depth-sorted alpha); fresnel rim, pulse (`0.7+0.3*sin(length(pos)*spatial - time)`), CA by re-rendering the scene 3× with offset rays; bloom/fog/scanlines.
- **v12 ("Ultimate Edition")**: adds 5-tap SDF **AO**, screen-space **glow halo** (8 renders of the full scene around the pixel!), **DOF** (8-sample golden-spiral aperture of full re-renders, blur ∝ |depth−focal|), **volumetric rays** (screen-space samples toward a light, each a full raycast), and an **energy field** (product of 3 axis sines + cross-waves + noise, smoothstep-sharpened into force lines). Feature-maximal — knowingly (defaults leave DOF/volumetrics off).
- **v13 ("v5 - Type Safe")**: consolidation rev. Drops AO/DOF/halo/volumetrics/energy; keeps X-ray + laser + adds **screen-space dither hatching**: `getScreenSpaceSize(worldSize, depth)` projects box scale to pixels, and boxes large on screen get sine-grid hatch patterns (4 styles: V/H/cross/diagonal) modulated by `1-abs(normal.z)` and tinted by fractal level. Engineering changes: every `out` parameter replaced by **globals** (`g_hitLevel`, `g_hitDistances`…, `float g_numHits` compared with `> 0.5` style), the X-ray layer loop **manually unrolled into 4 explicit blocks**, all `long` inputs compared as ints — title says why: "Fixed all type comparisons for VDMX compatibility". This is a catalog of Metal-backend scars: no out-params through the hot path, no float-indexed component writes, unrolled loops, half-open float counters.

**Control/UI design**: snake_case here (`anim_speed`, `wire_thickness`) vs camelCase in day11 — two conventions coexist by lineage (this line descends from a converted GLSL piece). Growth 6 → ~45 inputs; feature groups gated by `*_enabled` bools; `min_level/max_level` as a range pair; blend/color mode `long` dropdowns with LABELS. `anim_speed` default drops 100→10 by v12/v13 (taming).

**Version evolution summary**: v05 conversion → v04 box swap → v06 real Menger + container → v07 wireframe/multi-level → v08 laser-edge aesthetic → v09 rotation control split → v1 volumetric detour → v10 X-ray multi-hit → v11 depth-aware refinement + level-aware color → v12 kitchen sink → v13 subtractive consolidation + host-compat hardening + one new signature feature (dither hatching). Pattern: aesthetic leap, then control leap, then a maximal rev, then a pruned "type safe" stable.

**Complexity tier**: v04–v08 tier 3; v10–v13 **tier 4** (multi-hit transparency raymarcher with layered blend modes, LOD-aware line rendering and a large gated control surface).

**Signature moves**: curvature-pow laser edges; push-through multi-hit X-ray marching with min-separation; depth-scaled edge epsilon (line-weight LOD); fold-level-indexed coloring; light as in-scene SDF with dive-again shadows; screen-space-size-gated dither hatching; globals-instead-of-out-params for Metal.

**Rough edges**: v12's halo/DOF/volumetrics re-render the entire scene up to 8–20× per pixel — beautiful but unshippable at 60fps (hence v13 dropping them). `smin()` declared in v11/v12 but never used ("Attempt smooth minimum for potential future SDF blending" — labeled speculative). v11's fog uses a fabricated `centerDist` approximation (comment admits "simplified"). The 13-iteration fold always runs fully even when only level 12 renders. `dive()`'s fixed 20 steps with no convergence test yields characteristic smearing accepted as look.

---

## Batch synthesis

**Top 3 most sophisticated files**
1. **AR_Genuary2026_day12_v02.fs** — the only true multi-pass system: PERSISTENT FLOAT reaction-diffusion with ring-kernel cascade rule, life injected by a tumbling 3D wireframe-box SDF stamped into the sim plane, then the sim consumed as a raymarched heightfield terrain with derivative lighting and fog. Three paradigms (CA feedback, SDF geometry, raymarching) composed in 291 lines.
2. **AR_Genuary2026_day12_v13.fs** (with v11/v12 as its ancestry) — multi-hit X-ray fractal raymarcher with depth-aware laser line weight, level-indexed color, screen-space-projected dither hatching, and systematic Metal-compat hardening (globals over out-params, unrolled layers, int-compared longs).
3. **AR_Genuary2026_day11_altb_v01.fs** — cinematic monolith: OKLab-space color pipeline, soft-shadowed volumetric scattering with phase functions, closest-approach chromatic edge glow for missed rays, ACES tone mapping — film-grade rendering vocabulary inside one ISF pass.

**Recurring patterns / style fingerprints**
- The canonical hash `fract(sin(dot(p,vec2(12.9898,78.233)))*43758.5453)` appears in ~28 of 34 files, often wrapped as `random(st, seed)` with a *seed added to the coordinate* — seed-shifting as a first-class control.
- `steppedRandom`/`floor(TIME*speed)` time quantization as the universal "digital" temporal primitive (glitches, typewriter, animated noise).
- Master/child parameter gating (`glitchMaster`, `*_enabled` bools) with early-return no-op guards — both a UI conductor and a perf switch.
- Banner-comment modular sections in single files; explanatory comments written as narrated reasoning; changelogs in header comments ("Fixes applied: 1..6").
- Const loop bounds with runtime `break` everywhere loops are user-sized; float-math bit/byte extraction instead of bitwise ops; explicit vec2() promotion fixes; renamed globals to dodge host namespace clashes — a consistent Metal/VDMX-compat dialect.
- The `(localUV - center)/scale + center` cell-zoom idiom; `1/(1+t²k)` distance falloff; luma via `dot(c, vec3(0.299,0.587,0.114))` in every grading function.
- Version discipline: feature revs alternate with "CORRECTED"/"UX Redesign"/"Type Safe" consolidation revs — the author reliably follows expansion with a pruning/hardening pass.

**Beyond standard ShaderToy fare**
- Quine-as-shader: the shader's own source stored as int ROMs, later *byte-packed 4 chars per int* with a float-math big-endian decoder — data-encoding engineering unusual for VJ shaders.
- OKLab perceptual color mixing and lift-gamma-gain/temperature/tint grading stacks (colorist vocabulary, not shader-golf vocabulary).
- Multi-hit "X-ray" raymarching with per-layer blend modes and minimum hit separation — transparency without sorting or multiple passes.
- Depth-aware curvature-edge line weight (hand-rolled LOD for a line-art renderer).
- Reaction-diffusion with a *ring-integral* kernel and a cascading three-species parabola rule, driven by SDF geometry injectors.
- ISF UI meta-design: separator pseudo-inputs (`"--- GLITCH MASTER ---"`) and namespaced label hierarchies to organize 60-input control surfaces in host UIs.
