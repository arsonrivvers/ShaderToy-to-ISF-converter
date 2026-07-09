All 44 files read in full. Per the coordinator's instruction, here is the complete report (batch_20).

# Batch 20 Analysis Report — /Library/Graphics/ISF

## Coverage
- files_assigned: 44, files_read: 44, misses: none

---

## Per family

### Family 1: AR_MSFT_SpriteType (v01–v16 + claude_v15/16/17 — 19 files, "Hyper-Archive" lineage)

**Purpose & visual identity**: A typographic/data-brutalist sprite-grid **generator-as-filter**: an input image (usually rendered text) is used as a mask, and every masked grid cell is filled from a procedural library of ~42 monochrome micro-patterns — geometric tiles, 4×5 bitmap ASCII glyphs, 8-bit icons (heart, arrow, smiley, invader), and "pseudo-kana" fake-Japanese stroke glyphs. Output reads like a corrupted terminal/dot-matrix printout of the source text. CREDIT is "Gemini" throughout (LLM-collaborative authoring); the `claude_v*` files are Claude-produced refactors of the same engine.

**Architecture**: Single-pass throughout the whole 19-file family — all complexity is in cell-index math, not buffers. Core skeleton: aspect-corrected UV → grid `floor/fract` split → per-cell mask sample at cell center (`IMG_NORM_PIXEL(inputImage, (cellID+0.5)/gridDensity)`) → pattern dispatch → `mix(paperColor, inkColor, inkAmount)`. From v04 onward the grid becomes hierarchical (recursive subdivision); from v10 onward a full glitch pre-pass warps screen UVs before grid construction.

**Techniques** (the heart of this family):
- **Bit-packed 4×5 ASCII font**: characters stored as single floats decoded with float-math bit tests — `mod(floor(bits / pow(2.0, float(y*4+x))), 2.0)`. Char ramp ordered by ink density (`. - : ; + = * % #`) so index doubles as a brightness ramp. v03 adds `|` (bits=33685504, >16 bits, silently truncated on some GPUs — see rough edges); v10 adds block/checker/bracket/corner glyphs.
- **Pattern router**: giant `if (index == N) return fn(uv)` dispatch over step/fract primitives (box outline via `step(s,max(d.x,d.y))` difference, cross, X, h/v/d lines, dot grid, diamond, checker, pinwheel `step(0.5,sin(atan(p.y,p.x)*8.0))`, quarter-circle truchet, herringbone, Bayer-ish dither).
- **Neighbor-aware blank clustering** (`isBlank`): a cell re-derives its left/top neighbor's random roll (pure function of cellID, no buffer needed) and biases its own blank probability: `effectiveDensity = neighborBlank ? mix(density,1.0,0.7) : mix(density,0.0,0.3)`. Cheap stateless "clumped holes" — a signature stateless-cellular trick. claude_v* replaces it with value-noise spatial modulation of the threshold.
- **Probabilistic quadtree**: per-level roll `random(finalID + float(i)*13.0 + patternSeed)` against per-depth sliders; on success `finalID = finalID*2.0 + floor(finalUV*2.0); finalUV = fract(finalUV*2.0)` — ID arithmetic guarantees deterministic, seed-stable cells at every depth. Grows from 1 level (v04) → 4 (v07) → 7 with per-depth probability sliders (v09/v10+).
- **Cluster-coherent style selection**: value noise `noise(finalID / clusterCohesion)` picks the *category* (solid / wireframe / ASCII-frame / tiled-text / chaos pattern) so neighborhoods share a style, blended 25–30% with per-cell `random()` "pepper" so clusters aren't uniform. From v07: four **weight sliders normalized into probability buckets** (`pSolid, pWire, pText`, remainder = chaos) — a proto-mixer-desk UI.
- **ASCII box-drawing frames**: edge tests on cell UV route to `+` corners, `|` verticals, `-` horizontals; interior gets sparse `.` noise — the "data-map/TUI" look.
- **Glitch suite** (v10–v11, kept thereafter), all UV-domain ops before grid construction: `quantizePos` (floor-quantize whole screen = bitcrush), `hardShift` (discrete random row slides), `dataMosh` (second coarser quantize), row shift by `glitchOffset`, per-column Y `colSlip`, per-cell X scatter, plus **inverse-shift of the mask samplePos** so the source text stays legible while the grid tears (`samplePos.x -= rowShift` etc.).
- **"Logic" corruption ops** (v12): `logicKill` — kill subdivision where `mod(cellX*cellY, factor) < 1.0` (fake XOR interference); `oddEvenCull` — attenuate odd recursion depths; `bitShift` — position-derived integer added to char/pattern indices (data corruption); `logicInvert` — checkerboard ink inversion ("selected file" look).
- **Generative growth camera** (v13): replaces linear grid scale with exponential zoom `genScale = pow(2.0, macroScale*0.3+1.0)` plus a "sector snap" offset, so the master dial *travels through* the fractal instead of resizing it; mask switches to screen-space sampling (text becomes a stationary window onto an infinite grid).
- **Per-layer growth rates** (v14): each recursion level gets its own split rate slider (1–4), making mixed 2×/3×/4× subdivision trees.
- **BSP splits + stretch tracking** (v15): splits can be (2,1)/(1,2)/(2,2) chosen per level; `splitRatio` biases the split point via `pow(uv, 1.0/bias)`; a `groupRatio` accumulator tracks cumulative cell aspect (`groupRatio /= splitDim / max(splitDim.x, splitDim.y)`) and is used to compute `tiledUV = fract((paddedUV-0.5)*groupRatio+0.5)` so glyphs tile square inside stretched cells — the "Perfect Tiling Fix." Also **polyrhythmic grouping**: pre-recursion, 4×4 meta-cells can merge runs of cells into 4×1/1×4/2×2 spans.
- **Tonal system** (v10+): per-cell grey multiplier `1.0 - random(vec2(cellVar, depth)) * toneVar` then an **ink-gain contrast curve** `smoothstep(0.5 - g*0.5, 0.5 + g*0.5, ink)` — one slider morphs the whole image from soft greyscale collage to hard 1-bit.
- **4-ink palette system** (v16/claude_v17): paper + primary/secondary/detail/accent colors; selection value = `random(cellID)*colorNoise + (depth/7)*colorDepth` (+0.2 bias for wire/text categories), `fract()`-wrapped, banded 0.4/0.7 into the three inks; separate low-probability accent override — a "technical drawing" palette driven by recursion depth.

**Control/UI design**: Grows from 6 inputs (v01) to ~40 (v11+). Consistent conventions: numbered labels in early versions ("1. Macro Grid Size" … ), later **namespaced labels** ("Wire: Frame Width", "Text: Invert %", "Chaos: Icon %", "Glitch: Row Freq", "Logic: Bit Shift"); weight-mixer sliders (`weightSolid/Wire/Text/Pattern`); per-depth slider banks (recProb1–7, growthL1–7); universal `patternSeed` variation dial; ink/paper color pair. This is a live-performance surface: nearly every internal constant of v01 becomes a named uniform by v11.

**Version evolution** (the clearest learning trajectory in the batch):
v01 pattern archive → v02 density/clustering (stateless neighbor trick) → v03 two-scale mega/micro grid with box-type taxonomy (solid/frame/text-fill/chaos) → v04 probabilistic quadtree + noise clustering + row-shift glitch → v05 recursion merged with the full 42-pattern archive → v06 hybrid with `structBalance` → v07 style-weight mixer + 4-level recursion → v08 anisotropic (H/V) splits, gutters, alignment (a direction later redone properly in v15) → v09 per-level probabilities + panning + parameterized text/rotation → v10 7-level recursion, per-category control groups, tone variation, ink gain → v11 glitch suite + float-safe logicKill ("GLSL Fix" title = a compile failure got fixed) → v12 logic trinity (invert/cull/bitshift) → v13 exponential growth zoom → v14 per-layer growth rates → v15 BSP + tiling aspect correction → v16 four-ink color. `claude_v15/16/17` are hardening refactors of v14/v15/v16: `#define ASCII_CHAR_COUNT/MAX_PATTERN_INDEX`, all indices `mod`-clamped, the float `pow(2.0,bitIndex)` bit test replaced with **int arrays + loop-based right shift** (bitsLow/bitsHigh split for >16-bit glyphs — fixing the v03 `|` precision bug), monolithic main() decomposed into `renderWireframe/renderText/renderChaos/selectInkColor` helpers, `originalST` preserved for mask sampling. That is: Gemini iterated features; Claude was brought in to make it portable/robust.

**Complexity tier**: 4 — single-pass but a full generative layout engine (probabilistic BSP/quadtree, style mixer, glitch pipeline, palette system) with 40 conductor-style controls. Only the lack of feedback buffers keeps it from 5.

**Signature moves & standout tricks**: stateless neighbor-clustering; ID-arithmetic quadtree; density-ordered bit-packed font; weight-slider probability buckets; inverse-shifting mask coordinates so glitches tear the grid but not the text; groupRatio aspect tracker; depth-driven ink palette.

**Rough edges**: v02 ships with a comment admitting the library was elided then re-pasted ("I am keeping the exact same 42 functions here… for the sake of script length") — raw LLM-chat artifact. v03's 33685504 glyph exceeds float-safe bit range (motivating the claude refactor). Dead code: `finalScale` glitch scale tracking unused in places; v05's `borderThick` only affects some branches; v13 contains long "should the mask zoom or stay?" deliberation comments left in-source; v15 has visible design-reasoning comments ("Wait, if cell splits horizontally…"). `chaosRot` is a float used as a bool (`step(0.5,…)`). The v08 anisotropic direction was abandoned and redone in v15 with the aspect tracker.

---

### Family 2: AR_MultiColorPixelWarper / AR_MultiColorWarper "Hall of Mirrors" (+ AR_OAIJAOTIAJTOI) — 9 files

**Purpose & visual identity**: Webcam/live-input psychedelic glitch **filters** in two intertwined lineages: (A) "PixelWarper" — chromatic-aberration + `mod()`-modulation + nested `sin(cos(...))` color scramble of a camera feed, blended with hash noise; (B) "Warper" — a persistent-buffer radial-zoom feedback ("hall of mirrors") with sin-palette color warping. Both descend from Shadertoy conversions that were progressively de-moused and slider-ified.

**Architecture**:
- Lineage A: single pass. `HallofMirros` (typo file) is the raw conversion (iMouse, texture2D define); `HallofMirrors` 1→3 add sliders, imported PNG (`iChannel0`) hard-edge tiling, then depth warping, then blend modes (3 is fully minified one-line style). `HallofMirrors4_filter` is the conversion to a proper `inputImage` **filter**: texture removed, HSV color morphing added, `precision mediump`. `AR_OAIJAOTIAJTOI` (keyboard-mash name) is the cleaned refactor: helper functions (`applyChromaticAberration`, `calculateGlitchPattern`, `applyBlending`, `applyFinalAdjustments`), 7 blend modes, GROUP metadata on inputs — but it declares `uniform sampler2D iChannel2;` redundantly and uses `texture()` directly (host-compat hazard).
- Lineage B: 2 passes — `PERSISTENT FLOAT BufferA` + output. v02/v03_alt add a second non-persistent `MotionVectors` target computed by **brute-force 5×5 block matching** between inputImage and BufferA (best-offset minimum-difference search), used for motion blur (8-tap directional) and feedback displacement.

**Techniques**:
- **Radial sample-as-signal zoom**: `z = IMG_NORM_PIXEL(input, mod(vec2(length(uv-0.5),1.0),1.0)).r * k; uv = (uv-0.5)*(1.0-z)+0.5` — the image's own brightness along a radial line drives per-pixel zoom, then feedback buffer sampled with `mod(uv,1.0)` wrap = infinite mirror tunnel. Originally audio-reactive (`iChannel2 TYPE audio` in the ur-version).
- **Signature color scramble**: `sin(cos(channel*2π + dist + t_i)*2π + t_i)` with per-channel time rates (t, 0.5t, 1.5t) — chaotic iterated trig map on color values, distance-modulated from screen center.
- **`mod(webcam.rgb, n.rgb)` pattern modulation**: using a tiled texture/noise as per-channel modulo divisor (+1e-6 guard) — a genuinely unusual "wrap the video through the pattern" datamosh.
- **Luminance-as-depth**: `depth = dot(rgb, vec3(0.299,0.587,0.114))` drives displacement, parallax `(uv-0.5)*uParallax*(depth-0.5)`, sin refraction, `smoothstep(threshold±falloff)` layer blending, and screen-space edge detection via `dFdx/dFdy(depth)` for edge-darkening; shadow via gamma `pow(col, mix(1,2,uShadowIntensity))`.
- **GPU block-matching motion vectors** (v02): nested -2..2 loop over BufferA, `motionVec = -bestOffset*20.0` encoded `*0.5+0.5` into a buffer — optical-flow-lite without vertex shaders.
- **Trail persistence "glitch to black"**: where inter-frame difference exceeds a threshold and hash noise fires, pixels slam to black with occasional orange sparks and scanline dropouts — decay as performance gesture.
- **Feedback color rotation**: `result.rgb += (feedbackFrame.gbr - feedbackFrame.rgb) * k` — channel-swizzle differencing pushes hue rotation each feedback iteration.
- Standard blend-mode library (multiply/screen/overlay done per-channel with ternaries on floats, add/subtract/difference in OAIJAOTIAJTOI), `satAdjust` luminance-lerp saturation, rgb2hsv/hsv2rgb pair with time-flowing hue in 4_filter.

**Control/UI design**: `u`-prefixed uniforms (uGlitchIntensity 0–100, uChromaticOffset, uDepthWarp…) — a distinct naming era vs. the later camelCase-no-prefix style. `OPTIONS`-based blend-mode dropdown (float-valued enum decoded via `float(int(uBlendMode+0.5))` threshold chain — no int switch, a Metal-safe idiom). OAIJAOTIAJTOI adds `GROUP` metadata (Input/Glitch/Blending/Depth/Final Adjustments).

**Version evolution**: mouse → sliders; imported Shadertoy PNG → fully procedural / pure filter; single effect → depth system → blend modes/saturation → helper-function architecture. Lineage B: raw feedback tunnel → motion vectors + depth-modulated tracers + glitch-to-black → reorganized pass structure (v03_alt moves the composite into pass 0 so BufferA holds the *finished* frame; `HallofMirrors4` in Lineage A is actually the same author porting the ideas into a no-feedback single-pass filter).

**Complexity tier**: 3 (lineage A), 4 (v02/v03_alt with motion-vector pass and persistent feedback).

**Signature moves**: sample-as-signal radial zoom; per-channel time-decorrelated sin(cos()) scramble; mod-by-texture; block-matching motion pass; channel-swizzle feedback hue drift.

**Rough edges**: filename typos preserved as separate files (`HallofMirros` vs `HallofMirrors`); OAIJAOTIAJTOI's explicit `uniform sampler2D` + `texture()` calls break the ISF convention used everywhere else; v03's minified single-line main is unmaintainable and computes `col` twice (mix then blend-mode mix at 0.5 — a half-abandoned refactor); v02 computes motion vectors in the *output* pass where they're never stored (the search result is discarded except for warping — dead work); `uRectMod*(1.0+uRectMod)` in v3 is an unexplained squared boost.

---

### Family 3: AR_Mutatetest_v01 — "Orbital Filaments" (1 file)

**Purpose & visual identity**: Generator. Nebular light-filament accumulator: ~120 iterated "rays," each a rotated+displaced ring distance whose reciprocal is accumulated with a cosine palette. Explicitly framed as a **breeding experiment**: header says "iterative ray accumulation (Parent A) × per-iteration rotation matrix (Parent B)" — the shader-remix/genetics vocabulary that culminates in OffspringEngine.

**Architecture**: single pass, one big `for (float c = 0.0; c < maxIterations; …)` accumulation loop (float loop counter with uniform-driven bound — works because host allows it; max 300).

**Techniques**:
- **Gradient-noise domain warp before iteration**: proper Perlin-style `gradNoise` (hash2 → dot with corner gradients) bends UV once (`wuv = uv + noiseAmp*vec2(nx,ny)`), and the warped radius `wR` is *also* threaded into the rotation falloff and the palette phase, so one warp organically distorts geometry, rotation, and color together.
- **Radius-dependent rotation**: `angle = angleNumer / exp(wR / rDivider) * sFac + Srot/8.0` — rotation tightest at center, exponentially relaxing outward; `sFac = pow(abs(sin(Srot/8.0)),3.0)` pulses the whole swirl.
- **Reciprocal-distance glow accumulation**: `val = pow(intensity / abs(abs(d) + sn*denomOffset), exponent)` where `d = length(q) - wR*(sin(c*freqB+Sosc)*ampB+offsetB)*scaleB` — each iteration contributes a thin bright ring/filament; the `sn*denomOffset` term animates filament thickness per-ray.
- **Per-iteration cosine palette**: `col += val * (1.0 + cos(c*phaseFreq - Sosc*ePhaseScale + wR*lPhaseScale + vec3(0,1,2)))` — IQ palette phased by iteration index, time, and warped radius.
- **White-preserving Reinhard** (`wnReinhard`) with `whiteLevel` control, blended by `toneMix`, plus `gammaBoost` pre-shape — an unusually careful HDR chain for a 2D accumulator.

**Control/UI design**: 27 flat float inputs exposing literally every constant (freqA/ampA/freqB/ampB/offsetB/scaleB/wobbleAmp/wobbleFreq/denomOffset/phaseFreq/ePhaseScale/lPhaseScale…). No sections/macros — this is the "expose the genome" stage where mutation = slider set.

**Version evolution**: single version; the "Mutatetest" name and Parent A/B comments mark it as an intermediate artifact of the remix/breeding pipeline.

**Complexity tier**: 3 — single pass, but a dense parameterized accumulation system with real tonemapping.

**Signature moves**: threading one domain-warp value through geometry, rotation, and palette simultaneously; per-iteration palettes; reciprocal-distance filaments; explicit parent-labeling of technique provenance.

**Rough edges**: `uvAspect` default 0.47 is a magic tuned value; no early-out (300 iterations of full math per pixel at max); unused `R` computed before warp.

---

### Family 4: AR_Ocean_v01 (1 file)

**Purpose & visual identity**: Generator. Direct ISF port of afl_ext's well-known Shadertoy ocean (MdXyzX): sum-of-exponential-sine-waves water, raymarched between two planes, with cheap analytic atmosphere and ACES.

**Architecture**: single pass (a `pass0_mainImage` wrapper suggests machine conversion). Mouse-as-camera preserved via a `NormalizedMouse` macro hack over a `point2D` input.

**Techniques** (external but present in the corpus as reference material):
- **Wave accumulation with positional drag**: `wavedx` returns `exp(sin(x)-1.0)` wave + derivative; each octave *shifts the sample position* by `p * dx * weight * DRAG_MULT` before the next — the phase-drag trick that makes the peaks sharpen realistically; frequency ×1.18, time ×1.07, weight decays by `mix(weight,0,0.2)`; direction per octave from `vec2(sin(iter),cos(iter))` with `iter += 1232.399963`.
- **Two-plane bisection raymarch**: intersect high/low water planes, then walk `pos += dir * (pos.y - height)` — height-mismatch stepping rather than SDF stepping.
- Different iteration counts for march (12) vs. normals (36); normal-flattening with distance to kill shimmer; Schlick fresnel; `extra_cheap_atmosphere` with its 5.5/13.0/22.4 Rayleigh constants; ACES fitted matrices (the same m1/m2 matrices later reused in Proqxis — this file is plausibly where the author sourced them).

**Control/UI design**: one point2D. Untouched conversion; `usr_this` comment artifacts show an automated "this"→"usr_this" rename.

**Complexity tier**: 3 (sophisticated technique, zero integration effort).

**Rough edges**: mouse macro nonsense (`vec4(mouse*RENDERSIZE, mouse*RENDERSIZE).xy / vec3(RENDERSIZE,1.0).xy`); `if (RENDERSIZE.x < 600.0)` mobile branch is meaningless in VDMX. Useful mainly as negative knowledge: adopted verbatim, not remixed.

---

### Family 5: AR_OffspringEngine_v01 (1 file)

**Purpose & visual identity**: Generator. The flagship "Milestone 0b" of the Offspring Engine project: two donor simulations — Gray-Scott reaction-diffusion (Parent A) and SmoothLife continuous CA (Parent B) — feed a third, persistent, **Lenia-style living field (Offspring C)**. Explicit design thesis in the header: "The fader is inheritance pressure, not opacity. Output is Offspring C, never an A/B blend."

**Architecture**: 4 passes: `rdBuf`, `slBuf`, `offBuf` (all PERSISTENT+FLOAT full-res state buffers) + final render pass. State packing: RD chemistry `vec2(A,B)` in .xy; offspring `vec4(density, lineage, scar, age)`. Toroidal wrap via `fract()` on every buffer read.

**Techniques**:
- **Gray-Scott core**: canonical 9-point weighted Laplacian (0.05 corner / 0.2 edge / −1 center), Du/Dv = 2:1, `reaction = a*b*b`, and — the key performance mapping — **fader sweeps f/k inside the pattern-forming band** (`f = mix(0.030,0.058,fader)`, `k = mix(0.057,0.063,fader)`) so one knob morphs coral→worms→mitosis without leaving stability.
- **SmoothLife (Rafler)**: cut-price kernel — inner disk m = center + 4 axis taps / 5; outer annulus n = 8 ring taps / 8 (`ra=6, ri=ra/3` texel units for legible chunky cells); logistic sigmoids `sig(x,a,w)=1/(1+exp(-(x-a)*4/w))` with published glider constants (b1 .278, b2 .365, d1 .267, d2 .445, aN .028, aM .147); continuous update `life += dt*(2S-1)`.
- **Offspring dynamics**: own 8-tap neighborhood density feeds a **Lenia growth bump** `g(n) = 2*exp(-((n-0.32)/0.18)²)-1`; parents enter only as weighted *food*: `env = (1-fader)*clamp(rd.y-rd.x,0,1) + fader*slSample`; `dd = g*0.35*meta + 0.85*env*meta - 0.06*d + noise*mut*0.25`.
- **Lineage as mosaic inheritance**: per-cell lineage L relaxes toward `targetL = wB*bSig/total` at rate `0.04 + 0.20*env` — cells "become descended from" whoever feeds them, giving emergent A/B mosaics rather than a crossfade.
- **Scar channel**: apoptosis leaves structure — `newScar = max(scar*0.995, (d-newD)*1.5)`; the author's trail-accumulation idiom `max(prev*decay, current)` repurposed as tissue memory. **Age channel** accumulates while alive, resets on rebirth.
- **Mutation zone**: mutation strength peaks at fader=0.5 (`zone = 1-abs(fader-0.5)*2`) — the crossfader midpoint is deliberately the most genetically unstable region (a VJ-performance-theory decision encoded in math).
- **Stability discipline** (stated in comments as house rules): fixed dt under CFL (`dt = mix(0.45,1.0,metabolism)`), `FRAMEINDEX < 2` init (not ==0), `sanitize()` NaN/Inf scrub before every persistent write (`if (!(v==v)) return 0.0`), no vector ternaries, const loop bounds.
- **Phenotype render**: heightfield normal from 4 density taps; diffuse + rim light; **fwidth-based analytic AA** on the membrane threshold (`smoothstep(0.18-aa, 0.18+aa, d)`); dual cosine-palette inheritance (warm coral vs electric cyan) mixed by lineage ± palette macro; scar veining darkens + faint emissive; `pow(d,3)` glow; ACES.

**Control/UI design**: textbook macro-conductor panel: fader / mutation / metabolism / palette / glow (5 macro floats), freeze bool, reseed + reset **events**, and a `long` debugView dropdown (Offspring / Parent A / Parent B / raw state) — debug views as first-class UI.

**Complexity tier**: 5 — three coupled persistent simulations with a genetics layer, hardened numerics, and a lit phenotype renderer.

**Signature moves**: parents-as-environment (never blended); lineage/scar/age state channels; fader-positioned mutation zone; f/k band-riding; per-write sanitization.

**Rough edges**: comments reference an external architecture doc and a "production engine PCG hash" this slice doesn't use; reseed uses `step(0.85,s)`-style salt constants everywhere (magic seeds); slStep's 8-tap annulus is a very coarse SmoothLife kernel (acknowledged trade for speed).

---

### Family 6: AR_OpticalFlow_distort (1 file)

**Purpose & visual identity**: Filter. VDMX-stock-derived (credit "VIDVOX, based on Andrew Benson / v002") Horn-Schunck-style optical flow driving self-distortion; the AR edit is a GLSL-version-compat modernization pass.

**Architecture**: 3 passes: `maskBuffer` (PERSISTENT — flow field, blurred each frame), `delayBuffer` (PERSISTENT — previous frame), output. Flow encoded as 4 channels (+x,−x,+y,−y) to keep values positive.

**Techniques**: temporal gradient `curdif = prevGray - curGray`; spatial gradients summed over both frames; `gradmag = sqrt(gx² + gy² + lambda)` regularization; flow = `curdif * grad/gradmag` split into positive/negative channel pairs; **flow persistence** via `mask + maskHold * blur9(maskBuffer)` (9-tap box blur of its own history — decaying, diffusing flow memory); final pass reconstructs signed displacement `vec2(b.y-b.x, b.w-b.z)` and samples input twice (second sample offset by a strange `vec2(1.02)+uv` with `amt²`) blended 3:1. `#if __VERSION__ <= 120` varying/in dual declarations and `textureSize()`-based texel calculations are the AR-era compat scars.

**Control/UI design**: VDMX house style — LABELs on every input, `event` reset, persistence/scale/offset/lambda floats.

**Complexity tier**: 4 (multi-pass flow estimation), though mostly inherited code.

**Rough edges**: the `(vec2(1.02) + texcoord0)` second sample is acknowledged in comments as a bug-workaround ("Original logic with fix… This was likely the real source of the error via macro"); relies on host-provided varyings (`left_coord` etc.) that only exist in VDMX's ISF vertex shader.

---

### Family 7: AR_Philip_Marlowe (v01, v02_edit, v03_edit, v04_edit, v04_Color — 5 files)

**Purpose & visual identity**: Filter. Film-noir B/W treatment (credit Andrea Bovo, "Blondes, Bottles, and Brass Knuckles") — grayscale conversion, animated film grain, and a rotate/zoom **feedback echo** where bright areas punch through the trails. v04_Color forks it into a color-preserving grain treatment.

**Architecture**: 2 passes: `bufferVariableA` PERSISTENT (lowercase `"persistent": true` — works but off-spec) + output.

**Techniques**:
- **Gamma-correct feedback**: sRGB→linear (`pow(c, gamma)`), all mixing in linear, back out with `pow(c, 1/gamma)` — rare rigor for a VJ filter, and v03 makes GAMMA itself a slider (`gammaValue`).
- **Luminance-gated feedback punch-through**: `if (originalLuma > 1.0 - passThrough && originalLuma > bufferLuma) feedback = 0.0;` — highlights always print through the echo, so faces stay legible inside the smear. The family's signature.
- **Rotate/zoom feedback warp**: `uvWarp = rotate(rotationAmount degrees) * ((uv-0.5)*zoomAmount) + 0.5` (+ `feedbackOffset` point2D pan in v03+) — classic video-feedback spiral, in degrees.
- **Grain evolution** — the family's actual study subject: v01 multiplicative `mod((mod(x,13)+1)*(mod(x,123)+1), 0.01)-0.005` grain; v03 replaces with canonical hash noise + `grainScale`/`grainSpeed`; v04 goes **multi-scale**: fine (scale 2.0, weighted 0.3) + coarse (scale 1.0) hash grains, both multiplied by a **luminance factor** `mix(1.0, 1.0-lum, grainLuminanceInfluence)` (shadows grain more, like real film stock) and a `grainNoiseContrast` master.
- **Two-pass consistency fix** (v03+): `computeFinal()` called in *both* passes — pass 0 outputs gamma-compressed, pass 1 writes the linear version to the buffer, fixing v01/v02's subtle bug of storing already-gamma-compressed frames (v02 even double-degammas the input — the bug that presumably motivated the restructure).

**Control/UI design**: grows 7 → 16 inputs; coarse/fine pairs appear (fine vs coarse grain amount+speed); point2D used for feedback drift; invert bool; contrast/brightness post controls.

**Version evolution**: v01 original → v02_edit functional invert + typo'd double-degamma → v03_edit parameterized grain + gamma + feedback offset + shared computeFinal → v04_edit multi-scale luminance-aware grain (B/W) → v04_Color same engine, keeps `originalColor = orig` (color) instead of luma. Clean example of the author taking a found shader and iterating one subsystem (grain) to taste.

**Complexity tier**: 2–3 (two-pass feedback with careful color management).

**Signature moves**: luminance punch-through gate; linear-light feedback; luminance-weighted dual-scale grain.

**Rough edges**: v01/v02 gamma bugs (v02's `degamma(degamma(...))`); v01 grainAmount MIN=6 (can't turn it off — fixed in v02); educational essay comments from the original author preserved verbatim; `PI` defined, never used.

---

### Family 8: AR_Proqxis_Shapes_2026 (v01–v07 — 7 files, "DYPHOTIUM Volumetric Morphing Engine")

**Purpose & visual identity**: Generator. A glow-accumulation volumetric raymarcher over four morphable SDF "creatures" (coral cluster / inversion-fold torus rings / Fibonacci-spiked virus capsid / rotating cross-beam), with a 12-effect domain-distortion rack, HDR bloom, and dual tonemapping. This is the batch's production-grade engine, aimed at the 2026 "Proqxis" set.

**Architecture**: 5 passes in every version: two **1×1 PERSISTENT FLOAT state pixels** (`timeAccBuffer`, `morphPhaseBuffer`), full-res FLOAT `rawRender` (HDR), FLOAT `bloomH`, final composite. The 1×1 buffers are the standout architecture: GPU-resident scalar state machines.

**Techniques**:
- **Smoothed time accumulator** (pass 0): stores (accum, TIME, smoothedSpeed, validity-flag) in one pixel; `dt = TIME - prevTime`, speed low-passed with `alpha = 1-exp(-dt*8)`, `accum += dt*smSpd` — turning the `timeSpeed` slider into a click-free varispeed clock. First-frame detect is `(FRAMEINDEX==0) || !(prev.a > 0.5)` — alpha as an initialization sentinel.
- **Morph phase servo** (pass 1): `phase = mix(phase, morphScene, 1-exp(-dt*2*morphLerp))` — exponential chase of the shape-select knob, so scene changes are always eased regardless of how the knob is jumped.
- **Glow-accumulation marching**: no hit test — every step adds `glowGain*0.02*glow*exp(-T*0.18)*lighting / (1 + d²*glowFalloff)`; inverse-square-of-SDF proximity gives translucent energy-field bodies rather than surfaces.
- **SDF morph crossfade with asymmetric smin**: `mix(smin(d1,d2,k), smin(d2,d1,k), blend)` with `k = smoothK*(0.2+0.8*sin(blend*π))` — blobby union strength peaks mid-morph, shapes stay crisp at rest; plus 0.02/0.98 **early-outs** skipping the second SDF ~96% of the time.
- **Shape library**: coral = 4 orbiting spheres + core + hollowed hull (`max(sphere, -box)`); inversion = trig-warp → **sphere inversion `q/dot(q,q)*0.927`** → z-mod repetition → ring+torus; virus = golden-angle **Fibonacci sphere** (`phi = 2π*fi*0.618…`) spike distribution with per-spike pulse; crossBeam = `abs(min(box1,box2))+0.01` shell trick + surface ripple.
- **Distortion rack** (grows v01→v07), each gated by `if (param > 0.0)`: FBM turbulence (3-axis decorrelated), flame-style **feedback turbulence** (`p += amp*cos(p.zxy*freq - t*speed)` iterated, amp height-weighted), vortex (exp-falloff angular), moving warp center, linear+**quadratic twist** (`twistAccel*p.y²`), **cos-matrix shear** (`mat2` of four phase-offset cosines — a Fractal-Flame-style non-orthogonal transform), noise shatter with smoothstep mask, and from v04: 4-octave iterated-sin **fractal domain warp**, **curl noise advection** (∇× of two decorrelated value-noise fields, central differences, quality-gated), **domain repetition with time drift + per-cell hash rotation**, **gravitational lensing applied to the ray direction inside the march loop** (not the domain — physically-minded), and 1–5 orbiting **repulsion attractors** (inverse-square with +0.2 softening). v07 swaps domainRepeat for **spectralWarp**: N harmonic bands, each a sine of `dot(p, vec3(fi, 0.7fi, 1.3fi))` pushed along a per-band hashed axis, amplitude 1/fi — additive-synthesis logic applied to geometry.
- **Stability engineering as a first-class concern**: `distortionDanger` sums active distortion weights and divides the step multiplier; `maxDistortionDisplacement` inflates the bounding-sphere radius; domain repeat disables the bounding sphere and raises minStep; gravity lens raises minStep. The author models *how much each effect can break sphere tracing* and compensates.
- **Documented optimization program** ([OPT 1A–1M] comment tags): forward-difference normals reusing center d (6→3 evals), lighting gate on `surfaceProximity > 0.08`, **energy-based early termination** (`accumEnergy > 2.5` ≈ 0.97 post-ACES, with the reasoning in the comment), separable bloom O(n²)→O(2n), hoisted loop invariants, bounding-sphere pre-test with `T += boundDist*0.8` skip, deferred tonemap (compute only the active one), palette identity early-out, improved 3D lattice hash replacing a z-offset 2D hash (periodicity artifact fix).
- **Post chain**: threshold+Gaussian separable bloom (weights `exp(-d²/(radius*0.5))`, sample count from quality preset), ACES↔tanh blendable tonemap, hue-rotation-about-grey-axis palette (Rodrigues rotation with k=vec3(0.57735)), two chromatic aberration modes (cheap post multiply vs. true 3× ray-split gated behind quality ≥2.5), Henyey-Greenstein fog scattering, vignette, hash film grain.
- **Quality preset struct**: one 0–3 slider fans out through `getQualitySettings()` into ray steps, step multipliers, color complexity tiers, bloom taps, and CA permission — a single "performance conductor."

**Control/UI design**: ~50 inputs. v01–v04 use LABEL text grouping; v05 flattens/reorders; **v06–v07 introduce Unicode glyph section prefixes** — `▌` camera/global, `⟁` distortions, `◇` shape/morph, `◑` color, `◈` post, `⚙` engine — visual section dividers inside a flat ISF input list (a notable host-UI workaround). Constants promoted per version (v07: fbFreq/fbSpeed/fbHeight).

**Version evolution**: v01 feature-complete Phase 4 + first optimization pass (still has dead bloom accumulation inside the march). v02 Phase 1.5 optimization sweep (hoisting, bounding sphere, deferred tonemap, dead-code removal, palette early-out). v03 opacity semantics fix — opacity 0 now truly invisible (`mix(0.0,…)` remaps, halo scaled by opacity); bounding-sphere ambient leak removed. v04 Phase 5 five new distortions + lensing. v05 full rewrite as "DYPHOTIUM v6": ~35% smaller, helper extraction (computeGlow, getHueOffset now *interpolating* hue between phases instead of hard `<1.0` steps), named constants (TAU, PHI_INV, DEG2RAD), CA moved to a radial buffer-split in the final pass, camX/camY/rot dead constants deleted. v06 camera overhaul (orbit speed/radius/tilt, look-at targets) + glyph UI. v07 refinement: parametric feedback turbulence, spectralWarp replaces domainRepeat, **soft bounding fade** (`boundFade = 1-smoothstep(-0.5,2.0,bd)` multiplying contributions — fixing the visible pop when rays crossed the hard bound), displacementToColor floored at 0.08 to prevent dead-black flashes. Trajectory: features → optimize → fix semantics → more features → consolidate/rewrite → UI → polish artifacts.

**Complexity tier**: 5 — multi-pass HDR pipeline, GPU state pixels, 12-effect distortion rack with stability modeling, quality scaling, documented optimization program.

**Signature moves**: 1×1 persistent state pixels for smoothed clock + servo'd morph; distortion-danger-scaled stepping; energy-budget ray termination; asymmetric smin morph; Fibonacci-sphere geometry; glyph-prefixed UI taxonomy; in-loop gravitational ray bending.

**Rough edges**: v01 computes a bloom accumulator inside the march that only exports luma (dropped in v02); huge duplicated header/library across v01–v04 (the pain that triggered the v05 rewrite); `metaMapSimple`/`smax` defined but unused (removed by v05); `morphingDetail` quality field never read; global non-const `mat3` ACES matrices (works but off-spec); float-as-bool `camMode`/`tonemapMode` idiom.

---

## Batch synthesis

**Top 3 most sophisticated files**
1. **AR_OffspringEngine_v01.fs** — three coupled persistent simulations (Gray-Scott + SmoothLife + Lenia-style offspring) with genetics semantics (lineage, scar, age), a performance-theory-driven mutation zone at the crossfader midpoint, hardened numerics (CFL-bounded dt, NaN scrubbing, FRAMEINDEX<2), and a lit, analytically antialiased phenotype renderer. The clearest expression of the author's "simulation as instrument" thesis.
2. **AR_Proqxis_Shapes_2026_v07.fs** (as the apex of v01–v07) — a production volumetric engine with GPU scalar state buffers, a 12-effect distortion rack whose *stability cost is explicitly modeled into the step size*, an annotated optimization program ([OPT] tags), quality-preset conducting, and deliberate artifact fixes (soft bounding fade, color floor).
3. **AR_MSFT_SpriteType_v15/v16 + claude_v17** — a stateless generative layout engine: probabilistic BSP with aspect-ratio tracking for square glyph tiling, polyrhythmic cell grouping, weight-bucket style mixing, a glitch/logic-corruption suite, and a depth-driven four-ink palette — all in one pass with zero buffers.

**Recurring patterns / style fingerprints**
- The canonical `fract(sin(dot(p, vec2(12.9898,78.233)))*43758.5453)` hash and the same 4-corner value noise appear in nearly every family; Proqxis/Offspring graduate to `hash3D` fract-dot lattice hashes.
- IQ cosine palettes (`a + b*cos(2π(ct+d))`) as the universal color engine (Mutatetest, Offspring, Proqxis glow).
- Luminance = `dot(rgb, (0.299,0.587,0.114))` (or Rec.709 in Marlowe) used as depth, mask, gate, and bloom threshold everywhere.
- Persistent-buffer discipline idioms: `FRAMEINDEX<2` (or alpha-sentinel) init, `fract()` toroidal wrap, sanitize-before-write, `max(prev*decay, current)`-style memory (Offspring scar).
- Float-as-enum inputs decoded with threshold chains instead of int switches; `if (param > 0.0)` gating of every optional effect (uniform-branch friendly).
- Conductor-style UI: a few macro knobs over many internals (Offspring), weight-mixer buckets (SpriteType), quality presets (Proqxis), and label taxonomies (numbered → "Section: Name" → Unicode glyph prefixes).
- LLM-collaborative versioning is visible in the files themselves: Gemini-credited feature iterations, then Claude-credited robustness refactors (SpriteType claude_v*), with chat artifacts occasionally fossilized in comments.

**Techniques beyond standard ShaderToy fare**
- Stateless neighbor-clustering (re-deriving a neighbor's RNG roll to bias local probability) — cellular clumping with no buffer.
- 1×1 persistent FLOAT buffers as GPU scalar state machines (smoothed clock, servo'd morph phase) — parameter smoothing done *inside* the shader.
- Distortion-danger stepping: summing effect intensities into a step-size safety divisor and a bounding-radius inflation — explicit stability modeling of domain warps.
- Aspect-ratio tracking through a probabilistic BSP (`groupRatio`) so patterns tile square in non-square cells.
- Inverse-shifting mask sample coordinates so glitch displacement tears the pattern grid while the masking text stays put.
- Mosaic inheritance / lineage fields: simulation cells tracking *which parent fed them*, with scar-tissue memory of death events.
- Bit-packed glyph fonts decoded via float math, then hardened to int-array + loop-shift for GPU portability.
- Fader-position-dependent mutation (instability deliberately concentrated at the crossfade midpoint) — mixer-theory encoded into simulation dynamics.
