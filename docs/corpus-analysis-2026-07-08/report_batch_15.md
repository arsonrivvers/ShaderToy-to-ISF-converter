All 46 files read in full. Here is the complete report.

# Batch 15 Analysis Report — AR_Genuary2026 day24–day27

## Coverage
- files_assigned: 46, files_read: 46, misses: none

---

## Family 1: Pifragile Recursive Subdivision (day24_01 … day24_08, 8 files)

**Purpose & visual identity**: Generator. Reverse-engineering of Pifragile's JS generative art (recursive rectangle subdivision, Bauhaus/coolors.co palettes, mostly-hollow wireframe rectangles on cream/dark grounds). The 8 versions are one continuous engineering campaign to make a CPU-recursive algorithm render faithfully on a GPU.

**Architecture evolution (the heart of this family)**:
- **v01–v04 (single-pass, per-pixel UV descent)**: the pixel *walks down* the BSP tree by renormalizing its own UV at every split — `if (uv.x < splitPoint) uv.x /= splitPoint; else uv.x = (uv.x-splitPoint)/(1.0-splitPoint);` with a seed accumulator (`seed += 13.0*float(i)` etc.) so each leaf gets a deterministic identity. Splits choose between 0.5, golden ratio 0.618/0.382, and later extreme ratios 0.05/0.95. Limitation: each pixel only knows its own leaf — stroke widths distort with box size and neighboring-box edges are invisible.
- **v05 (day24_05, "Faithful v3")**: formalizes the PRNG into a sequential stream — `nextRand(inout seed){ seed = fract(seed*1.61803398875 + 0.31415926535); return hash(...); }` — mimicking JS sfc32 call ordering; adds `struct BoxResult`, GLSL Fisher–Yates palette shuffle via `int perm[6]`, forced-square aspect (`min(RENDERSIZE.x, RENDERSIZE.y)` letterbox), and documents original hex palettes in comments. Also replicates the original's *overflow* semantics: `subBox(0.8 + m4)` ratio can exceed 1.0 → negative margin → boxes escape their cells.
- **v06 (day24_06, "v4 Analytical Edge")**: abandons UV descent for a true **iterative stack machine** — `Box boxStack[24]; int depthStack[24]; float seedStack[24]` — popping boxes, subdividing, pushing both children, and collecting SDF edge distance (`boxEdgeDist` = classic 2D rounded-box SDF) so strokes get *screen-constant* width across all leaves. Early-out: `if(boxDist > 0.1) continue;`.
- **v07 (day24_07, "v5 True Multi-Pass Recursion")**: the standout. 9 `PASSES`, one per tree depth; each pass enumerates all 2^depth leaves by **path-bits encoding** — `traceBoxPath(..., int pathBits)` extracts bit d without bitwise ops (`int divisor=1; for(k<d) divisor*=2; pathBit = int(mod(floor(float(pathBits)/float(divisor)), 2.0));`) — and renders only cells whose random terminal depth equals that pass's depth. The final pass composites pass0…pass7 by alpha priority. This is GPU tree-recursion via pass-per-level dispatch — well beyond ShaderToy-standard.
- **v08 (day24_08, "v6 Enhanced")**: 11 passes (depths 1–10), parameterizes what was hardcoded: `strokeWeight`, `hollowProb`, `splitBias` (edge↔center split preference), `goldenRatio` bool, `crossPattern` (Mondrian-style crosses inside cells, inverted color on solids), `outerMargin`, `depthIntensity` (drives both grid multiplicity and depth cap); anti-aliased strokes via `smoothstep(strokeWidth±AA)` with **depth-relative thinning** (`depthFactor = 1.0/(1.0+depth*0.3)`), alpha-blended composite, and a bounding-circle early-out per path.

**Control/UI design**: v01–v05 use the author's signature `m0…m4` five-macro-knob scheme (palette selector / color seed / grid density+depth / margin / subbox+noise) — each knob deliberately drives several internals at once. v06+ append named refinement sliders on top of the macro set.

**Complexity tier**: 4 (v07/v08 are multi-pass GPU tree evaluators with conductor knobs; earlier versions tier 2–3).

**Signature moves**: seed-accumulator leaf identity; path-bits tree enumeration; pass-per-depth dispatch; 80%-hollow wireframe aesthetic; Fisher–Yates in GLSL; overflow-permitting subBox.

**Rough edges**: v06's per-pass palette shuffle is recomputed inside the leaf loop in v07 (fixed in v08 by precomputing `perm[6]` once); v02 contains a commented-out abandoned "datamosh line artifacts" idea; stroke-width screen-constancy is admitted as approximate in v02's comments.

---

## Family 2: Bauhaus Enhanced Subdivision (day24_Alt_01, 1 file)

**Purpose**: Generator; the v7 continuation of Family 1 with an art-history color engine bolted on.

**Techniques**:
- **Kandinsky color–shape doctrine as a slider**: `kandinskyColor()` maps shape type → Blue(circle)/Red(square)/Yellow(triangle), blended into palette color by `kandinskyStrength`.
- Six named palettes as `#define`s (PAPER_WHITE, BAUHAUS_RED, …) with `long`-type dropdown (`VALUES`/`LABELS`) — Classic Bauhaus, Warm Earth, Cool Minimal, Kandinsky Pure, Itten Wheel, Albers Neutral.
- **Warmth shift** (`shiftWarm`: multiply by warm/cool RGB gains), desaturation, monochrome-chance override.
- **Aspect-aware splits**: wide cells split vertically, tall horizontally (`shouldSplitVertical` blends random vs aspect-based by slider).
- **Golden grid snap**: `nearestGoldenSnap` pulls UVs toward 0/0.382/0.5/0.618/1 lines with `smoothstep` falloff — compositional alignment as a post-warp.
- **Diagonal axis transform**: rotates content UV around center by ±45° or the true screen diagonal (`atan(1.0/aspect)`), strength-blended.
- **Tier scaling**: quantizes subBox size into 4 discrete tiers (0.35/0.55/0.78/1.05) — discrete size classes rather than continuous.

**Controls**: 20 inputs; keeps m0–m4 legacy row plus Bauhaus section. **Tier: 4.**

**Rough edges**: `getShapeType` computes circle/rect/triangle but only color uses it — the triangle/circle geometry is never drawn (abandoned direction); axis transform applied *pre-grid* so it shears cell lookup rather than rotating rendered boxes.

---

## Family 3: Piston City (day24_Alt_02 … day24_Alt_08, 7 files)

**Purpose**: Generator; raymarched infinite voxel-city of subdivided cubes riding sinusoidal pistons, neon glow tops, mirror-bounce reflections. Original is a Shadertoy (fingerprints: `#define fs(i) (fract(sin((i)*114.514)*1919.810))`, `lofi` macro). The 7 files are an "unlock and stabilize" campaign.

**Architecture**: single-pass raymarcher; sparse traversal via `qt()` — repeated `lofi(ro + rd*eps*size, size)` cell snapping with halving size (an implicit octree descent), `isHole()` culls cells with a time-scrolled hash-density function (`heck`), and `ibox()` slab-test AABB intersection. Rays reflect on hit (`colRem` throughput) and continue.

**Version evolution**:
- **Alt_02 "Clean Edition"**: strips the original's stochastic sampling/jitter for sharp lines; adds `nightmareIntensity` conductor (screen tear + camera twitch + domain warp + chromatic aberration + dirty-color mix all on one knob), 5 user `color`-type palette slots, glitch delete (`fract(time*20.0)>0.9` gates random cell deletion).
- **Alt_03 "Unlocked"**: exposes `worldScale`, `recursionDepth`, `lookY`, `fogDist`, `contrast`, `vignetteStr`, `reflectivity` — the systematic magic-number-to-slider pass.
- **Alt_04 "Clean Controls"**: robustness rewrite — `ibox` handles rays *starting inside* the box (tN/tF selection with correct normal sign), `max(abs(rd), 1e-5)` div-by-zero guards, `r.len = max(b, 0.002)` min-advance, hole flag correctness.
- **Alt_05 "v2 Stable Cells, Real Camera"** (credited "rewrite by AR"): full re-architecture. `_uiMain`/`_uiCamera`/… **section dividers implemented as dummy `image`-type inputs with `━━` labels**; `long`-type dropdowns for projection (Perspective/Ortho/Blend) and floor-cut mode; proper `Cell`/`Hit` structs; probabilistic subdivision (`subdivideChance`/`subdivideBias`) replacing the original's hash break; per-cell piston phase = time + spread·hash + spatial `dot(baseId, 1)` + chaos; world drift with wraparound period; ACES approx tonemap; energy accounting (`throughput`, `absorb`, `albedo`, `baseDiffuse`).
- **Alt_06 "v2.2 DDA Grid"**: replaces the eps-nudged cell stepping with a **true 3D-DDA traverser** (`ddaInit`/`ddaAdvance` with `tMax`/`tDelta`/axis masks) so steps/bounces sliders actually behave; separates `evalBase` (per-base-cell hole/piston, evaluated once per DDA cell) from `evalDetail` (subdivision descent at the sample point); AABB normal selection with epsilon bias to break ties; `floorCutAABB` conservative test plus `floorCutPoint` exact hit test; nested-loop flattening (single loop with manual bounce bookkeeping and `dda = ddaInit(...)` re-init after reflection).
- **Alt_07 "Fixed Controls + Palette System"**: backports Family-1-style palette architecture (6 palettes × 6 colors, shuffle by `colorSeed`/`colorVariation`) plus HSV `hueRotate`/`saturationMult`; makes `worldScale` actually scale geometry+camera+fog coherently (`gWorldScale` global).
- **Alt_08 "UNHINGED"**: ~60 inputs exposing *everything* including hash multipliers (`hashMult1=114.514`, `hashMult2=1919.810`), subdivision ratio, piston waveform, material thresholds, per-channel smoothstep bounds — with **⚠️ warnings in LABELs** marking parameters that break the render ("`subdivisionRatio != 0.5` creates asymmetric/broken subdivision", "`reflectivity > 1` amplifies energy (unstable feedback)"). Section dividers here are `event`-type inputs with `═══` labels.

**Complexity tier**: 4 (Alt_06 is a real DDA voxel path tracer with piston animation and full UI system).

**Signature moves**: intentional-instability sliders with warning glyphs; section-header pseudo-inputs (two different idioms: `image` type and `event` type); one-knob "nightmare" conductor; DDA re-init after each bounce.

**Rough edges**: Alt_02/03 keep the fragile `1E-2` ray-bias cell snapping (fixed in 04+); Alt_05's inner `i = MAX_STEPS_HARD;` loop-abort idiom is a hack (replaced in 06); `sampleReflection()` is a vestigial one-liner left from removing stochastic sampling.

---

## Family 4: Organic Raymarched Sculpture (day25_01, day25_03; 2 files)

**Purpose**: Generator; three orbiting rounded boxes smin-blended into a molten blob with cinematic studio lighting.

**Techniques**:
- Two-stage domain warp: low-freq triple-sine displacement + high-freq detail product-sines; v2 adds `warp_mix` blending original↔warped position and squares `detail_amount` for perceptual response.
- **Full GGX PBR in ISF**: `D_GGX`/`G_Smith`/`F_Schlick` with roughness², driven by a key/fill/rim tri-light rig with quadratic attenuation.
- **Thickness-approx SSS**: march *into* the surface along −normal counting steps (`thicknessApprox`), `trans = exp(-thick*scatterDepth)`, combined with wrap-lighting (`(NoL+0.45)/1.45`) and a scatter color — cheap translucency.
- 6-tap AO ramp, penumbra soft shadows (`res=min(res, k*h/t)`), ACES + gamma + contrast + saturation + vignette post chain, threshold bloom from luminance.
- Hit refinement: after the main march, 6 half-step relaxation iterations to settle onto the surface.

**Version evolution (v1→v2 is a slider-responsiveness audit)**: v2's header explicitly lists the fixes — camera controls made *additive* on top of auto-orbit (`y = ay + camYaw*m`) instead of a mix that fought the animation; AO/shadow remapped perceptually (`pow(raw, mix(1,4,aoStrength))`); bloom given a reachable threshold slider; fresnel F0 decoupled from surface color; magic numbers promoted (aoRadius, shadowSoftness, rimPower, fogCurve, bgTop/bgBottom colors, maxSteps/maxDist).

**Controls**: ~30 named inputs. **Tier: 3.**

---

## Family 5: Piston Metaballs Crystal Trails (day25_02, 1 file)

**Purpose**: Generator; smin-blended piston-driven boxes rendered as refractive crystal with gyroid interior patterning and temporal trails.

**Architecture**: 2 passes — `trailBuffer` (PERSISTENT+FLOAT) + main. Pass 0 just does `oldTrail * trailDecay`.

**Techniques**: gyroid `dot(sin(p), cos(p.yzx))` projected onto the hit surface as a fake internal-refraction pattern; normal perturbation by the gyroid value; per-channel prism split via `sin(refVec.{x,y,z}*10 + phase)`; piston phase system copied from Piston City (`hash33` chaos phases).

**Rough edges (valuable negative knowledge)**: a 20-line comment block at the end works through ISF feedback topology in real time and concludes the trail buffer *never receives new light* — pass 0 only decays its own history and nothing writes the current frame into it, so "trails" are actually just composited decay of nothing. An honest, documented failed feedback design; the correct pattern (write `current + prev*decay` INTO the persistent target) appears later in day26. **Tier: 2.**

---

## Family 6: Mandelbulb Interior + FXAA (day25_03_alt, 1 file)

**Purpose**: Generator; port of mrange's "Inside the mandelbulb II" with XorDev FXAA as a second pass.

**Techniques**: mandelbulb distance estimator with running derivative `dr = pow(r,power-1)*dr*power + 1`; **signed-direction marching** for inside/outside (`dfactor = isInside ? -1 : 1`); up-to-5-bounce reflect/refract loop with Beer–Lambert (`ragg *= exp(-(st+initt)*beer)` with a *negative* beer color = tinted gain); analytic plane-glow sky (`rayPlane` + box SDF glow rectangles); ACES + sRGB.

**Port scars documented in comments**: global `const` initializers with function calls removed for strict GLSL ES ("FIX: removed 'const' because POWER is a uniform"), HSV2RGB macro-ized to avoid const-array init. FXAA pass samples `bufferA` with `sqrt(2.0)/RENDERSIZE` texel — the author's standard FXAA idiom from here on. **Tier: 3.** Only 2 inputs (power, loops) — an unusually minimal port.

---

## Family 7: Neon Mountain Wireframe (day25_04_alt, 1 file)

**Purpose**: **Filter** (the only depth-map filter in this batch): builds a glowing 3D wireframe terrain from `inputImage` + `depthMap`, colored by a procedural "mountain" palette.

**Techniques**:
- Per-pixel neighborhood search over grid vertices (`searchRadius` clamped 2–6, scaled by density ratio) — each pixel tests distance to line segments connecting projected 3D grid points (`distToSegment`).
- Depth → 3D: `p0 = vec3(pos2D.x, (d0-0.5)*DepthScale, pos2D.y)`, tilted by rotation and sheared by `perspectiveShift` (fake perspective via `proj.x += p.y * shift`).
- **Density-compensated glow**: `densityRatio = 40.0/gridResY; glowDensityScale = densityRatio²` so line brightness stays constant as grid resolution changes — a resolution-invariance trick.
- `boundedGlow` = smoothstep core + gaussian skirt, deliberately bounded; `aggressiveClamp` = luminance-domain Reinhard-style compressor `lum/(1+lum*0.8)` then hard cap — two layers of anti-blowout for projector use.
- Depth-based line thickness (`computeDepthThickness`: near lines thicker, curved response); `EdgeEnhance` widens lines across depth discontinuities (`1.0 + abs(d0-d1)*EdgeEnhance*20.0`).
- `BrightnessBlend` mixes true depth with image luminance — graceful fallback when no real depth map is connected.

**Tier: 4** (a genuinely novel filter architecture — vector-graphics-style segment rendering in a fragment shader). **Rough edge**: O(searchRadius² × 2 segments) texture fetches per pixel; the author caps radius rather than restructuring.

---

## Family 8: "Option B" Recursive Metaball Glass Cathedral (day25_04, 05, 06, 07, 08, 09, 10, 11, 12, 13; 10 files)

**Purpose**: Generator; the batch's magnum opus. A recursive-domain metaball field rendered as deep refractive glass lit by a synthetic neon environment, evolved across 10 explicitly phase-labeled versions into a full engine.

**Core geometry (constant across all versions)**: `baseMetas` = up to 10 smin'd spheres on lissajous orbits; `map()` re-evaluates the metaball field in an **iterated folded domain** — per iteration: `foldBox` (abs-translate fold), three axis rotations at incommensurate rates (a, 0.73a, 0.51a), scale by `iterScale` with distance renormalization `/sc`, then a *dual combine*: `d = smin(d, di, k*(0.65+0.55*w)); d = mix(d, min(d, di), mixAmt)` where the weight `w = pow(i/N, detailBias)` makes later (finer) iterations contribute more sharply — a fractal metaball with per-octave blend control.

**Phase-by-phase evolution (author's learning trajectory)**:
- **day25_04 (Phase 1)**: geometry + the Family-4 lighting stack. No transport.
- **day25_05 (Phase 2)**: multi-bounce reflect/refract with Beer absorption; **stochastic** branch choice (`pick = fract(sin(dot(hp.xy...)))` picks reflect vs refract weighted by fresnel) — noisy.
- **day25_06 (Phase 3)**: adds `envArchitect` — a fully synthetic analytic environment: horizon line (`exp(-abs(y)/width)`), dual light sheets with depth fade, rectangular "rails" projected at distance 10, HSV sky. FXAA final pass. The environment IS the light source.
- **day25_07 ("deterministic")**: kills the noise — replaces stochastic branch selection with **deterministic energy splitting**: reflection contributes `rPart * envArchitect(hp, refl)` immediately (env-only, no recursive march), ray always continues as refraction with `thr *= tPart`. Adds portal ring, tilted second sheet, **environment chromatic aberration** (evaluate envArchitectRaw with ±rotated ray, take R/G/B channels separately), `insideStart`/`dive` camera-inside-the-glass controls.
- **day25_08 (B1)**: **segment-integrated volumetrics inside the medium** — `integrateVolume` marches the interior segment accumulating env emission with per-step transmittance `exp(-(sigmaA+sigmaV)*dt)` and the exact emission integral `emit*(1-att)/ext`.
- **day25_09 (B2)**: shell + cavity — `shell = abs(d) - shellThickness; d = mix(d, shell, shellMix)` hollows the blob; a domain-warped **gyroid cavity SDF** is smooth-subtracted (`smax(d, -cav, k)`) to carve "cathedral tunnels."
- **day25_10 (B3)**: mandelbulb-style energy handling — material-style `matReflect/matTransmit` (allowed >1), `edgeSharpness` exponent on fresnel, per-bounce transmission env contribution, `surfaceLightMix` demoting direct lighting so env+absorption dominate.
- **day25_11 (B4)**: **micro-architecture** — second, finer gyroid (`microSDF`) carved in, with `microEmission` = `exp(-abs(md)*8.0)` glowing ribs along the lattice; micro-gradient **normal detailing** (3-tap gyroid gradient added to the SDF normal); `curvatureProxy` (second derivative along normal, `(d1+d2-2*d0)/e²`) boosting scatter color on ridges. UI reorganized: QUALITY section first with per-subsystem quality scalars.
- **day25_12 (B5)**: HDR pipeline split into 3 passes — scene (HDR float), bloom (9×9 gaussian with **soft-knee extraction**: `soft = sat((x+knee)/(2knee)); m = max(x,0)+soft²·knee`), composite with FXAA, highlight-only chromatic split sampled from the bloom buffer, luminance-weighted grain, and an unsharp-mask sharpen built from 4 extra FXAA+tonemap evaluations.
- **day25_13 (final, 1354 lines)**: production engine. **5-level perf-tier table** (POTATO→ULTRA) documented in a comment block with expected fps targets; 7 independent feature bools; **separable H/V bloom** (2 passes replacing the 2D kernel); **distance LOD** (`mapBaseLOD` reduces fractal iterations with ray distance; micro detail fades out past t≈15); **8 debug modes** (iteration heatmap, depth, normals, AO-only, bounce count, LOD viz, tier overlay); adaptive ray stepping (`s = mix(clamp(d*0.92,stepMin,stepMax), stepMax, emptyBoost*adapt)`); NaN/Inf guard painting magenta (`ldr != ldr` test); camera gimbal-lock clamps. Comments carry a phase-numbered changelog ("Phase 1.1.2 + 2.3.5: Fixed loop bound, tier-based steps").

**Control/UI design**: grows from ~35 to ~70 inputs; `━━ SECTION ━━` labels on the first slider of each group (a third divider idiom: labeling a real input as the header); quality/perf controls always listed first in later versions.

**Complexity tier: 5** — multi-pass HDR volumetric refractive engine with LOD, tiering, and debug instrumentation.

**Signature moves**: deterministic fresnel energy splitting (structural noise-free glass); analytic env-as-lightsource with its own chromatic aberration; nested gyroids at two scales (cavity + micro) with emissive ribs; exact volumetric emission integral; per-octave dual smin/min blend in the fractal loop.

**Rough edges**: enormous copy-paste inheritance — the ~300-line lighting/env block is duplicated verbatim across 7 files; day25_12's sharpen pass re-runs FXAA 4× (very expensive, "fixed" only by the toggle in 13); `lastD` out-param is computed but never used by callers.

---

## Family 9: Metaball Fractal Hybrid (day25_14, day25_15; 2 files)

**Purpose**: Generator; explicit hybrid credited "Geometry from Conner Jones, Architecture from mrange" — Family 8's fractal metaballs transplanted into Family 6's clean bounce-loop renderer.

**Techniques**: mrange-style render loop (throughput, sky via `rayPlane` floor/ceiling glow discs, Beer with negative-color trick `beerCol = -hsv2rgb(...)`); Family 8's shell/cavity/micro carving retained; perf-tier table.

**v14→v15 evolution**: adds `metaShape` slider morphing sphere→rounded-cube primitives (`sdMetaShape = mix(sphere, roundBox, metaShape)`), `orbitPause`+`camAngle` manual camera hold, gimbal-lock up-vector swap, ray-parallel plane guard in `rayPlane`, and — most interesting — **`bgVisibility` separating sky-as-background from sky-as-lighting**: `skyColorVisible` (primary rays, can be black) vs `skyColorLighting` (reflections, always full) so the object stays lit while floating on black for VJ compositing. Also fixes a v14 bug: `map()` called `mapBase(p)` twice (v15 comment: "Use cached 'd' instead of calling mapBase again"). **Tier: 4.**

---

## Family 10: UNHINGED Hybrid Chaotic/Rigid Grid (day26_alt_01, day26_alt_02; 2 files)

**Purpose**: **Filter** (image-warping glitch grid). Hybrid of Pifragile-style rigid BSP layout and organic per-cell UV warping, with persistent feedback. "UNHINGED" = every magic number exposed (~120 inputs in alt_01).

**Architecture**: alt_01: 2 passes (PERSISTENT FLOAT `feedbackBuffer` + display). alt_02: restructured to a single declared pass rendering *into* the feedback buffer, with the identical algorithm body — an experiment in feedback topology (this one gets the write-current-frame-into-persistent-target pattern right, unlike day25_02).

**Techniques**:
- **hybridBSP**: 16-step binary space partition of screen UV; each cut is either "rigid" (snap ratios 0.05/0.5/0.95 driven by `rigidExtremeBias`, with `rigidRunLength` making rigidness *sticky* across levels via `rigidState = mix(n2, rigidState, runLength)`) or "chaotic" (golden-ratio base drifting sinusoidally over time, clamped to `bspRatioMin/Max`). Leaf identity via `id = id*2 + offset` path encoding; outputs `rectUV` + `rectID`.
- **Per-rect personality**: `rectHash(rectID)` modulates warp sign, reach, organicity, aspect set, feedback masking, and even time-quantization phase per rectangle — every BSP leaf behaves differently from one parameter set.
- **Compound micro grid**: inside each rect, `depthCount×drillDown` (≤16) recursion levels of `applyCompoundGridUnified` — per-cell aspect cycling (3 aspect ratios lerped in a cycle), a **trig flow field vs hash field blend** (`buildField`: 8 time coefficients × 7 spatial frequencies of layered sines vs pure hash offsets, blended by `fieldComplexity`), `mirror01` wrap-vs-fract cell wrapping, and per-depth weight `gridMorphPattern` (phi-hashed per-cell reveal thresholds) × exponential falloff.
- **Motion quantize**: `quantizeTime(t*steps)/steps` with per-rect offsets — stepped, datamosh-style motion, dialable from smooth to strobing.
- **Depth-adaptive cheapening**: deeper recursion levels smoothly reduce field complexity/aspect speed/organicity (`cheap = smoothstep(thresh,1,depthNorm)*depthAdaptive`) — perceptual LOD, since deep levels contribute less.
- Seam glow: micro (grid-cell edges) vs macro (BSP rect edges) edge masks with per-cell jittered width.
- Feedback: rotate + zoom previous frame, decay, and mask amount per-rect (`feedbackMaskByRect`).

**Complexity tier: 5** — the most parameterized shader in the batch and a fully original architecture (BSP + recursive warp + feedback in one filter).

**Rough edges**: alt_01's `ui_*` dummy float sliders as section dividers (fourth divider idiom); with 16 macro steps × 16 depth loops the worst-case cost is extreme and only softly guarded; `hash11_fast` quality collapses for some exposed magic values (by design — it's a chaos knob).

---

## Family 11: Volumetric Morphing "metaMap" Series (day27_01, 02, 04, 05, 06, 07, 10; 7 files)

**Purpose**: Generator; glow-accumulation volumetric raymarcher morphing between a library of animated SDF "creatures," evolved across 5 labeled phases into another engine.

**The two 1×1 persistent-buffer idioms (signature architecture, all versions)**:
1. **Time accumulator with speed smoothing**: `PASSES[0]` = 1×1 PERSISTENT FLOAT storing `(accumTime, lastTIME, smoothedSpeed, validFlag)`. Each frame: `dt = TIME - prevTime`, speed low-passed at ~8 Hz (`alpha = 1-exp(-dt*8)`), `accum += dt*smoothedSpeed`. Result: dragging the `timeSpeed` slider never causes a time-jump — the animation's *rate* glides. First-frame detection via `FRAMEINDEX == 0 || !(prev.a > 0.5)`.
2. **Morph phase buffer**: 1×1 persistent scalar lerping toward `morphScene` — v01 uses frame-dependent `mix(cur, target, morphLerp*0.02)`; v02+ fix it to frame-rate-independent `1-exp(-dt*2*morphLerp)`.

**Shape library**: `coralField` (rotating smin cluster + radial bulge + hull shell), `inversionField` (sphere-inversion `q/dot(q,q)` + z-mod repetition — rings and tori through an inverted domain), `virusCapsidSpikes` (**fibonacci-sphere** spike distribution: `z = 1-2(i+.5)/N; phi = 2π·i·0.618`), later `crossBeam` (abs-symmetry cross of thin boxes with `abs(min(...))+0.01` volumetric-shell trick — imported from the day27_03 flame). Rendering is not surface-hit but **glow accumulation**: `contrib = gain·glow·fade / (1 + d²·falloff)` every step — the SDF acts as a proximity field.

**Color system**: log-distance phase-offset cosine palettes (`0.8 + cos(log(len(pos)*scale+1) + i*0.0744 - t + vec3(0,1,2))`) with **adaptive dithering that fades with camera distance** (`ditherAmount = mix(0.08, 0.0, smoothstep(1.5,6.0,camDist))`) — banding suppression only where banding is visible.

**Evolution**:
- **01**: kitchen sink — 5-shape morph chain, 9 chaos distortions (turbulence/vortex/warp/twist/shatter/gravityWells/electricStorms/liquidDynamics/energyPulse), many disabled to consts.
- **02 (Phase 1)**: prunes to 3 shapes and 5 distortions; fixes chromatic aberration (v01's version mixed a color with itself — documented dead code); adds saturation early-exit; loop bound 200→160.
- **04 (Phase 2)**: 4-pass architecture (adds HDR `rawRender` + bloom/composite pass); **smooth-min morphing** — `mix(smin(d1,d2,k), smin(d2,d1,k), blend)` with `k` peaking mid-transition (`k = smoothK*(0.2+0.8·sin(blend·π))`) so shapes *merge organically* rather than crossfade; `QualitySettings` struct preset system; Rodrigues-rotation hue shift about the gray axis; bloom luma packed in the HDR alpha channel.
- **05 (Phase 3)**: full **ACES matrices** (Input/Output mat3 + RRTAndODTFit); volumetric fog with **Henyey–Greenstein phase function** (g=0.7); `shapeComposition` (smin-union of all shapes at once); **ray-split chromatic aberration** — three complete ray marches with offset directions, gated behind quality ≥ 2.5.
- **06/07 (Phase 4)**: techniques harvested from the day27_03 flame port, credited as "flame-inspired" — **quadratic twist** (`angle = linear·y + accel·y²` — twist accelerating with height), **shear distortion** (deliberately non-orthogonal `mat2(cos(a), cos(a+11s), cos(a+33s), cos(a+7s))` — the flame's compressed rotation idiom promoted to a technique), **feedback turbulence** (`p += amp·cos(p.zxy·freq - 3t)` swizzled position feedback with height-dependent amplitude), **displacement-driven fire color** (chaos displacement magnitude → log-scaled fire palette), shape taper, tanh tonemap blendable against ACES. 07 = 06 + **dynamic step limiting**: `stepMul = base/(1 + distortionDanger·1.5)` where danger is summed from the distortion sliders — automatic overshoot protection when space is warped.
- **10 (Phase-4 optimized)**: engineering pass with bracketed opt tags — [OPT 1A] forward-difference normals reusing the already-computed center distance (6→3 SDF evals), [OPT 1B] lighting gate on `surfaceProximity > 0.08`, [OPT 1C] morph early-out (blend <0.02/>0.98 skips the second shape — "saves one full SDF evaluation… for ~96% of the morph cycle"), [OPT 1D] separable bloom (5 passes now), [OPT 1E] accumulated-luminance ray termination ("threshold 2.5 maps to ~0.97 after ACES"), [OPT 1F] proper 3D lattice hash replacing the 2D-hash-with-z-offset (killing z-periodicity artifacts).

**Complexity tier: 5** for 05/06/07/10; 3–4 earlier.

**Rough edges**: 01's noise3D adds `i.z` directly to a 2D hash (the periodicity bug fixed only in 10); 01's chromatic aberration is documented dead code; the const-frozen "removed UI sliders" block persists all the way to 10 (opacityMode/colorMode paths still branch on constants); the 300-line camera/glow boilerplate is copy-pasted across all 7 files.

---

## Family 12: Flaming Experiment Port (day27_03, 1 file)

**Purpose**: Generator; faithful unpacking of a code-golfed CC0 Shadertoy flame. Zero inputs.

**Techniques (the seed bank for Phase 4 above)**: 88-step accumulation march where each step rebuilds the ray from scratch (`p = z·normalize(vec3(C-.5r.xy, r.y)); p.z -= 4`); non-orthogonal cos-matrix "rotation" `mat2(cos(a+0), cos(a+11), cos(a+33), cos(a+0))` with quadratic height angle `P.y²/4 + 2P.y - t`; while-loop turbulence `p += 0.4(p.y+2)·cos(p.zxy·d - 3t)/d`; cross of thin boxes `abs(min(box1,box2)) + 9e-3` as a volumetric shell; `o += (P.x/d)·P` inverse-distance emission; `tanh(o/2000)` tonemap with a **custom_tanh polyfill** for older GLSL; `gl_FragColor = vec4(tone, tone.r)` — alpha = red channel so the black background is transparent in the host mixer. Comments translate every golfed idiom. **Tier: 2** (as a port), but high leverage: three of its idioms became named sliders in Family 11.

---

## Family 13: Thin-Film Hybrid Engines (day27_08, day27_09; 2 files)

**Purpose**: Generators; "Phase 3 Hybrid" and "Phase 5 Remix" — crossbreeding the metaball-fractal geometry (Family 8/9) and the morphing shape library (Family 11) with a **thin-film interference** material.

**Techniques**:
- `thinFilmColor(d, n1, n2, cosTheta)`: physical iridescence — path difference `2·n2·d·cosθ` against RGB wavelengths `vec3(650,510,475)` nm, `0.5+0.5·cos(2π·δ/λ + π)` interference; film thickness in *nanometers* as a slider (0–1000 nm).
- **AABB pre-intersection** to skip empty space before marching (`intersectAABB` slab test; bounding size estimated from `metaSpread*2+3`).
- Adaptive tolerance (`SURF_DIST·(1+t·0.02)`) and adaptive normal epsilon (`max(0.001, dist·0.001)`) — precision spent only up close.
- 08: manually unrolled 4-metaball core ("Manual unroll for performance"); reflection throughput *tinted by the film color* (`throughput *= filmCol`).
- 09 (Phase 5): morph shapes + Phase-4 distortions **inside** `map()` (distortion displacement returned as an out-param and driving both hue shift and emissive glow at the surface); `d * 0.7` global distance compression "to compensate for heavy distortion"; distortion-danger step limiting from Phase 4; per-tier `stepLimitScalar`.

**Rough edges / regressions**: 09's time-accumulator pass degrades to `dt = 0.016; // Approx` — the carefully built dt-measured accumulator from Family 11 was dropped in the remix (fixed-timestep assumption breaks the jitter-free property); 09 bounces only on reflection (`roughness < 0.5` else break) — refraction path abandoned. **Tier: 4.**

---

## Batch synthesis

**Top 3 most sophisticated files**:
1. **day25_13** (Optimized Volumetric Raymarcher, 1354 lines) — a production render engine in one ISF file: 5-tier perf table with documented fps targets, 7 feature toggles, distance LOD on the fractal itself, separable bloom, 8 debug visualization modes, NaN sentinel. This is engine engineering, not sketching.
2. **day26_alt_01** (UNHINGED Hybrid Grid) — the most *original* architecture in the batch: BSP macro-layout with sticky rigid/chaotic cut personality, per-leaf behavioral hashing, 16-level recursive micro-grid warp with trig-vs-hash flow fields, motion quantization, and correct persistent feedback — ~120 exposed parameters.
3. **day24_07 / day24_08** (Pifragile v5/v6 multi-pass recursion) — GPU tree recursion via pass-per-depth dispatch with path-bits leaf enumeration and emulated bitwise ops; the cleverest workaround-to-architecture conversion in the batch.

**Recurring style fingerprints**:
- **Version campaigns with phase labels in DESCRIPTION** ("Phase 2:", "Option B Phase B4:", "v2.2") — each file is a checkpoint, and headers double as changelogs.
- **The "unlock" pattern**: take a found/ported shader, then systematically promote every magic number to a slider, culminating in deliberate "UNHINGED" builds with ⚠️-marked instability knobs — instability as a performance feature.
- **Four different UI-section-divider idioms** (dummy `image` inputs, `event` inputs, `ui_*` float sliders, and `━━` labels on real inputs) — evidence of a host (VDMX) with no native grouping, attacked repeatedly.
- **Quality/perf tiering** as a first-class UI section (perfTier tables, QualitySettings structs, per-subsystem quality scalars) in every heavy raymarcher.
- Standard helper corpus repeated everywhere: `hash21/hash33` (0.1031-family), `smin/smax`, `rot2`, ACES approx (2.51/0.03/2.43/0.59/0.14), sRGB mix-form, XorDev FXAA with `sqrt(2)/RENDERSIZE` texels, gyroid `sin·cos` at 2+ scales.
- Const loop bounds with runtime `break` throughout (the documented host quirk), `float`-cast abs for GLSL ES `abs(int)` absence, and `FRAMEINDEX==0 || alpha-flag` persistent-buffer init.

**Beyond-ShaderToy techniques**:
- 1×1 persistent **state buffers as scalar registers** (smoothed time accumulator, morph-phase servo) — using the multipass system as a tiny state machine for jitter-free UI response.
- Pass-per-tree-depth recursion with path-bits enumeration (day24_07/08).
- Deterministic fresnel energy splitting to get noise-free multi-bounce glass (day25_07+), and the exact volumetric emission integral `emit·(1−att)/ext`.
- Sky-as-background vs sky-as-lighting separation for VJ compositing (day25_15 `bgVisibility`).
- Distortion-danger-aware adaptive step limiting (step size auto-shrinks as warp sliders rise).
- Physical thin-film interference with nanometer thickness sliders (day27_08/09).
- Documented *failed* feedback topology (day25_02) followed by the corrected pattern (day26) — a visible learning arc on ISF persistent-buffer semantics.
