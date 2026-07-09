# Batch 02 Analysis Report

## Coverage
- files_assigned: 36, files_read: 36, misses: none (all files read in full)
- Note: within the assigned 36, one file — `/Library/Graphics/ISF/AR_ConversionImport_X_v01.fs` (internally labelled "collection_23-01-08_shader.glsl") — is itself a broken/incomplete ShaderToy port (references undefined variables `u`, `O`, `uvAspect`; would not compile). Flagged under Rough Edges, not treated as a read failure.

## Per family

---

### Family: AR_Circle2Square (v01–v09) + AR_Circle2Square_simple (v01–v05) — 14 files

**Purpose & visual identity**: Generators. A circle-morphing-to-square radial/tunnel pattern family, ranging from fractal "fold space" kaleidoscopic bloom (v01–v02) to perspective ring tunnels (v03–v09) to a standalone pulsing-ring toy (simple v01–v05).

**Architecture**: All single-pass (no PASSES block, no PERSISTENT/FLOAT buffers) — pure per-pixel procedural math, no feedback or simulation state. Iteration counts driven by `for(i<10){ if(float(i)>=paramCount) break; }` (const bound + runtime break, the standard host-safe pattern). v07 uses a 48-iteration loop to fake discrete ring "objects."

**Techniques**:
- **Superellipse circle↔square morph**: `pow(pow(|x|,n)+pow(|y|,n),1/n)` with `n` swept 2→~32, blended with true Chebyshev square distance (`max(|x|,|y|)`) at the high end (`mix(superellipse, square, shapeType*shapeType)`) for crisp corners. Present in nearly every file — the family's signature primitive. v06+ splits the range: analytic superellipse up to n=16, then mix toward Chebyshev, avoiding pow() precision blowup at high n.
- **Fold-space fractal loop** (v01/v02): `uv = foldSpace(uv*uvScale, offset, mode)` with 4 selectable fold modes (fract/abs/triangle-wave/mod), iterated and ring-lit via `pow(brightnessBase/d, exponent)`, colored with an IQ cosine palette (`palA + palB*cos(TAU*(palC*t+palD))`), per-iteration weight `pow(iterFade, i)`.
- **Smooth fractional-parameter interpolation** (v06+): `sdPolygonSmooth` blends polygon SDFs at `floor(sides)` and `floor(sides)+1` by `fract(sides)`; layer/ring counts use the same fractional-fade trick (`countAlpha = fract(ringCount)` for the last ring) — so *every* integer-natured control animates smoothly. A distinctive house pattern.
- **Reciprocal-depth pseudo-3D tunnel** (v06): the pivotal architectural leap —
  ```glsl
  float z = 1.0 / max(d0, nearClip);   // screen distance → pseudo-depth
  z *= angularMod;                      // angular fold sculpting (star/petal warp)
  float fog = exp(-depthFog * z);
  ```
  Rings placed evenly in z compress toward the vanishing point and accelerate as they approach — true infinite tunnel perspective from a flat 2D distance field, zero geometry. Harmonic complexity adds a golden-ratio-detuned second wave (`sin(z*freq*1.618 + anim*0.7)`).
- **Discrete perspective ring objects** (v07): each of up to 48 rings has its own z-position (`mod(i*spacing + motion, tunnelDepth)`, wrapping for infinite recycling), perspective projection `radius = tunnelRadius/z`, per-ring spiral twist (`twistAngle = globalRot + z*twistRate`), hash-based per-ring size jitter, brightness `1/pow(z, depthCurve)`, and near/far wrap-fade via double smoothstep to hide the wrap seam.
- **Layered physical-light glow** (v08/v09): three concentric exponential glow bands per ring — core (white-hot: `mix(color, vec3(1.0), 0.6)`, sharp), halo (colored, medium), bloom (colored, wide) — all widths scaled by `1/z` perspective; v09 adds an "orb" mode with a `pow(1-r², falloff)` sphere-luminosity profile plus a Gaussian center hotspot (`exp(-ratio²*8.0)`), crossfaded against ring-glow.
- **Tunable perspective curve** (v08/v09): `zMap = mix(1.0, z, depthCurve)` — one knob sweeps flat (0) → linear perspective (1) → warp-speed compression (3).
- **Seamless-loop ring growth** (simple v01→v03): v01 linear phase; v03 replaces it with a normalized exponential radius curve `(exp(phase*3.5)-1)/(exp(3.5)-1)` so the ring exits off-screen before wrapping, plus smoothstep fade-in/out windows (first/last 15% of phase) to hide the reset pop.
- **Infinite sine-ring pattern** (simple v04/v05): abandons the loop-reset problem — `sin(dist*ringFrequency*TAU + flow)` is periodic by construction. v05 stacks depth layers with `warpedDist = dist*exp(-depthWarp*baseDist)` tunnel compression.
- **BPM tempo-sync** (simple v02–v05): `effectiveSpeed = (bpm/60)*beatDivision`, with `useBPM` toggle and `phaseOffset` — manual-or-tempo dual timing.
- **Kaleidoscope fold** (v01/v02): `angle = mod(angle,seg); angle = abs(angle - seg*0.5)` polar segment mirroring, applied pre-fractal.
- **Smooth pingpong morph** (v06+): `pingpongSmooth(t) = p*p*(3-2p)` of `abs(mod(t,2)-1)` — replaces v03–v05's raw `sin()` morph for ease-in/out shape oscillation; also drives pulse-mode z-travel.
- **Eased rotation drive** (v03): `easeInOut(t, accel) = t^a/(t^a+(1-t)^a)` — a tunable sigmoid mapping a 0–1 "drive" fader to rotation speed; dropped in v04 for direct predictable control (interesting reversal: easing was tried and rejected for performance control).

**Control/UI design**: Unicode box-drawing section dividers inside LABEL fields (`"━━ FRACTAL ━━━━━━━━━━━━━"`) to fake section headers in flat-list hosts. Coarse/fine and parent/child pairs via indented `"   └ Speed"` sub-labels. `reset` event inputs on the simple branch. Palette exposed as 4 `color` inputs (palA/B/C/D) matching the cosine-palette signature — a catalog-wide convention. v06+ moves the most-performed knobs into a leading `━━ PERFORM ━━` section (tunnelSpeed/direction/rotation/morph/colorCycle) — deliberate performance-first ordering. Input counts run ~20–35 per file.

**Version evolution**: v01→v02 adds shape-blend/corner controls onto the same fractal engine. v02→v03 is a genre pivot: fractal folding abandoned for a cleaner ring tunnel. v03→v05 add reset, ring fill (thin ring ↔ solid), birth mode (single expanding ring vs full tunnel), thickness — perceptual refinements on the same math. v05→v06 replaces flat ring stacking with reciprocal-depth true perspective + angular depth warp + harmonics. v06→v07 discretizes the depth field into individual perspective-projected ring objects ("flies through" vs "recedes"). v07→v08 trades ring density for per-ring light richness (3-band glow, tunable perspective curve). v08→v09 adds the solid-orb rendering mode. The simple sub-branch runs a parallel evolution solving "seamless looping" three ways (linear clamp → BPM sync + pulse → exponential growth + edge fades → v04's pivot to an inherently periodic sine field), ending with v05 re-adding multi-layer depth to the periodic solution. Clear learning trajectory: from borrowed fractal (credit "AR / kishimisu") toward original perspective systems (credit "AR").

**Complexity tier**: v01–v02: 3. v03–v05: 3. v06: 4. v07–v09: 5 (v07 especially — 48-object perspective system in one pass). simple v01–v03: 2. simple v04–v05: 3.

**Signature moves & standout tricks**: `z = 1/max(d0, nearClip)` reciprocal depth; exponential-radius seamless loop; 3-band core/halo/bloom glow function (directly reusable for any point-light/particle look); fractional-count smooth fades on every integer parameter; golden-ratio harmonic detune.

**Rough edges**: v03's `shapeSmooth` control does a confusing double-remap of superellipse n (`mix(n, 2+(1-cornerSmooth)*28, cornerSmooth)`) — dropped in later versions. v04's `reset` event is declared but never referenced in code (comment admits relying on host TIME-reset behavior). Helper functions copy-pasted near-verbatim across all 14 files rather than shared. v09 declares a `fog` variable fixed at 1.0 (dead remnant of v08's depth fog).

---

### Family: ColorfulFlickers / ColorFullFlickers fractal video filters — 5 files
(`AR_ColorfulFlickers_v05`, `ArsonRivvers_ColorFullFlickers_v01`, `ArsonRivvers_ColorFulFlickers_v02`, `_v02B`, `_v03B`)

**Purpose & visual identity**: Filters (require `inputImage`). "Content-locked fractal": video brightness/edges/structure drive a Mandelbox/Menger-like iterative fold fractal rendered as glow accumulation and luminance-threshold-blended back over the source. Organic, web-like fractal bloom riding the video.

**Architecture**: All single-pass, no persistent buffers. Heavy per-pixel iteration: up to 100–200 outer loop steps with nested 3–7 step fold sub-loops, quality-mode gated.

**Techniques**:
- **Rodrigues 3D rotation macro**, shared verbatim across all 5: `#define R(p,a,r) mix(a*dot(p,a),p,cos(r)) + sin(r)*cross(p,a)` — arbitrary-axis rotation with no matrix.
- **Fold-fractal core**: `p = mod(p - a, a*2.0) - a` modular space repetition, then repeated `p = foldIntensity - abs(p + offset)` folds with scale accumulation `s *= ~1.7` and subtractive structure shift `p = abs(p+off)*mod - vec3(structureX, structureY, structureZ)`; distance estimate `e = length(vec3(p.y,p.z,p.z))/s` accumulated into marching depth `g += e`, color `+= H(g*gradientBalance + ...) * depth / e`.
- **Asymmetric fold offsets to kill mirror seams**: `vec3 p_fold_offset = vec3(0.0137,-0.0241,0.0089)` — "small, asymmetric, non-round constants" (their comment) added inside every fold so the fold axes never sit exactly on the screen center; plus a per-pixel epsilon on direction.y. Deliberate scar-tissue from a visible center-split artifact.
- **Smooth component shuffling** (v02 → refined): ShaderToy original's hard `if(p.x<p.z) p=p.zyx;` swaps replaced by `mix(p.zyx, p, smoothstep(-0.1, 0.1, p.x-p.z-shuffleBias))` — converting branch discontinuities into blendable, biasable transitions (fixes frame-popping).
- **Depth-from-video**: `depth = luminance * (1 + sobelEdge) * depthInfluence * warpDistortion` drives fractal zoom, 3D rotation angle (`rotationAngle = depth*PI`), and color phase — the fractal literally reads the video.
- **Quality-mode tiering** (v02 refined): one 0/1/2 knob gates edge-detection method (none → 4-tap gradient → full 3×3 Sobel), fold depth (3/5/7), and hash-vs-simplex noise mix — a single perf/richness conductor.
- **Curl-noise vortices** (v02B): `curlNoise(p)` = perpendicular central-difference gradient of simplex noise, added to the marching direction, used as the 3D rotation axis (`R(direction, normalize(vec3(curl,0.001)), driver*PI)`), and stirred into `p.xy` inside the loop; vortex amount gated by edge magnitude (`vortexBias + (1-vortexBias)*smoothstep(eMag)`) so swirls concentrate on video edges. Adds a mild spherical inversion tint per fold (`p *= 0.9 + 0.1/dot(p,p)`).
- **Structure-tensor anisotropic metric** (v03B) — the batch's most advanced technique: computes the 2×2 structure tensor from the luminance gradient, extracts eigenvalues/orientation,
  ```glsl
  lam1 = tr*0.5 + disc; lam2 = tr*0.5 - disc; theta = atan(gy, gx);
  M = a*outer(v,v) + b*outer(u,u);          // anisotropic metric
  pN = rot2(theta)*pN;  pN = evert(pN,...); pN = inv2(M)*pN;
  ```
  then marches the fractal through the *inverted metric* — space locally stretches along the image's dominant edge direction. Combined with radial "eversion" `p*(k/r²)` (inside-out inversion, edge-gated) and an OKLab-approximate palette rotation (`okApprox`/`okInv`, rotating the chroma plane by `0.7*paletteMorph`) keyed to the eigenvalue anisotropy ratio. Also: edge-adaptive iteration count (`maxIterations += extra*edgeK`) and temporal jitter seeded by `floor(TIME*3.0)`.
- **v05 variant**: uses an external palette *texture* input (`u_palette` image, sampled at `vec2(fract(g*0.1), 0.5)`) instead of the math palette — the only texture-LUT palette in the batch.

**Control/UI design**: Flat input lists, no section dividers (earlier convention than Circle2Square). ~20–28 descriptive inputs (`structureX/Y/Z`, `edgeSensitivity`, `gradientBalance`). Consistent tail idiom in every file: `blendMix`/`blendThreshold`/`thresholdSoftness` luminance-threshold crossfade of effect over source — a repeated "content gate."

**Version evolution**: v01 (raw ShaderToy adaptation: hard component swaps, fixed structure constants 30/120/8, 7 folds always, full Sobel always) → v02 (parameterizes everything: foldIntensity, structureXYZ, shuffleBias, colorPhase; quality tiering; smooth shuffles; asymmetric fold offsets; scaled-down animation speed to prevent p.z blowup) → v05 (artistic redesign: palette texture, stripped-back input set, fixed fold constants as #defines) → v02B (curl vortex sibling) → v03B (structure-tensor/eversion/OKLab escalation). Trajectory: port → parameterize & harden → stylistic fork → two increasingly principled "video geometry drives fractal geometry" experiments.

**Complexity tier**: v05: 3. v01: 3. v02: 4. v02B: 4. v03B: 5 (research-grade CV technique in a VJ shader).

**Signature moves & standout tricks**: Structure-tensor-driven anisotropic space inversion (v03B) is genuinely novel for VJ work. Asymmetric fold offsets and smoothstep component-shuffling are small, broadly reusable fixes for fractal-fold artifacts. Edge-gated effect strength (vortex, eversion, iteration count) is a recurring principled pattern.

**Rough edges**: Duplicated helpers across all 5 files. v03B's OKLab is a crude approximation (not the real matrices) — deliberate real-time simplification. v01's fixed `vec3(30, 120, 8)` structure constants and always-on 7-fold loop are the unparameterized ancestor state that v02 exists to fix. Naming chaos in this family (ColorFul vs ColorFull, v05 numbered out of sequence with v01–v03B) suggests parallel forks rather than a linear series.

---

### Family: AR_ColorGrading v01/v02 — 2 files

**Purpose & visual identity**: Filter. "CinemaGrade" — a full DaVinci-Resolve-style color-correction suite: not generative at all, a professional grading utility.

**Architecture**: Single pass, no buffers. ~70 inputs organized into ~14 sections via dummy `"TYPE":"text"` inputs used purely as UI separators. Pipeline order in main() mirrors a real grading node graph: input (exposure/temp/tint) → primary wheels → log wheels → tone curve → HSL secondary → channel mixer → split toning → film emulation → tonemap → lens effects → output saturation.

**Techniques**:
- **Lift/Gamma/Gain/Offset wheels** with luminance-range masks: lift `pow(1-l, 1.5)` (shadows, soft rolloff), gamma bell `max(1-|l-0.5|*1.5, 0)^0.8` plus actual per-channel `pow(color, 1-lum*0.5)` for the luminance component, gain `pow(l, 1.5)` multiplicative, offset uniform — the standard DaVinci wheel math reimplemented in GLSL.
- **Log wheels**: three smoothstep-bounded zones with tunable low/high range boundaries — tighter, non-overlapping versions of the primaries.
- **Hue-vs-Sat / Hue-vs-Lum secondaries**: `getHueMask(hue, target, width)` with wraparound-aware hue distance `min(dist, 1-dist)`, applied over 7 hue buckets (red duplicated at 0.0 and 1.0 to handle the wrap), each with its own sat and lum trim.
- **Channel mixer** as a literal `mat3 * color`.
- **Split toning**: HSV-generated shadow/highlight tint colors, smoothstep masks with a balance shift (`0.5 ± balance*0.25`), multiplicative tint blend.
- **Film emulation**: print-contrast toe/shoulder (`x²(3-2x)` toe, `1-(1-x)^2.2` shoulder, luminance-crossfaded); halation as red-orange glow gated by `pow(max(l-0.6,0)*2.5, 2)`; film fade (lifted blacks + desaturation); grain as two value-noise octaves scrolling at different speeds with a midtone-weighted response curve (`1-|l-0.5|*1.5`, floor 0.25).
- **Lens block**: 5×5 box-blur bloom gated by highlight smoothstep; radial chromatic aberration (R/B sampled along `(uv-0.5)*amount`); radial smoothstep vignette.
- **ACES fitted-curve + Reinhard tonemaps**, selectable via float mode.
- **Early-out guards**: nearly every stage begins `if (amount < 0.001) return color;` — cheap when idle despite ~25 sequential function applications.

**Control/UI design**: The `text` dummy-input section-header convention (unique to this family in the batch — a second, distinct solution to ISF's flat UI alongside the box-drawing LABEL trick). Rigorous naming grids (`liftRed/liftGreen/liftBlue/liftLum` per wheel; `mixRedRed`…`mixBlueBlue` for the 3×3 mixer).

**Version evolution**: v02's only change is portability: v01 passed `sampler2D img` into `applyBloom`/`applyChromaticAberration` and called raw `texture2D()` — v02 removes the sampler parameters and routes through `IMG_NORM_PIXEL(inputImage, uv)`, with "Fixed:" comments marking each site. A crisp host-compat lesson: never pass sampler handles or call raw texture functions in ISF; always use the IMG macros on named symbols.

**Complexity tier**: 4 — breadth of a complete grading pipeline (~35 distinct operations), though no procedural depth (only fixed-bound loops).

**Signature moves & standout tricks**: A complete, self-contained reference implementation of professional color-wheel math — every function (`applyLift`, `getHueMask`, `acesTonemap`, film toe/shoulder) is directly liftable into any future ISF color filter.

**Rough edges**: v01's sampler2D pattern (the bug v02 fixes). Grading operations are applied in gamma space without linearization — functional for VJ use, not colorimetrically rigorous. `tonemapMode` as a float 0–2 (rather than a `long` with LABELS, which the author uses elsewhere) is an older-convention scar.

---

### Family: AR_ConversionImport (A, B, C v01/v02, D, E, X v01/v02/v03) — 9 files

**Purpose & visual identity**: Generators. Explicit ShaderToy ports ("Fixed ISF port of https://www.shadertoy.com/view/..." in DESCRIPTIONs; X_v01 sourced from kishimisu.art's collection API). Most follow the classic ShaderToy "accumulate glow over a loop with per-channel phase-offset cosine color" fractal-flame idiom.

**Architecture**: All single-pass, no buffers. X_v03 is the sole raymarcher.

**Techniques**:
- **Shared port scaffolding**: every port re-derives centered UVs the same way — `(gl_FragCoord.xy - RENDERSIZE*0.5) * uvScale / (RENDERSIZE.y * uvAspect)` — with `timeOffset` + `timeScale` inputs standard. The "conversion recipe" itself is a repeated pattern: center-scaled UV, every magic constant lifted to a slider, iteration count as a float input with const-bound loop.
- **Phase-accumulation flame idiom** (A, B, C, D): `col += intensity/abs(d) * (1.0 + cos(phaseAngle + vec4(0,1,2,0)))` — per-channel RGB phase offsets of 0/1/2 radians on a shared angle mixing iteration index, radius, and time. Appears in 5 of 9 files.
- **A**: per-iteration rotating direction vectors `dir = vec2(cos(c*dirFreq+e), sin(...))` with sine-modulated amplitude; white-preserving luma-based Reinhard tonemap mixed by `toneMix`; gamma boost.
- **B**: warped sine chain `sin(exp(sin(innerLen*scale - length(u*scale))) * warpFreq + t*phase)` (nested transcendental warp), per-iteration X-mirroring (`u.x = -u.x`), two smoothstep masks carving the visible annulus.
- **C v01→v02**: orbiting point field (`r = vec2(sin(C*freqA+...), cos(C*freqB*(baseB+sin(S)*sinScaleB)+S))`) with wobble; **v02 adds a real z-axis with perspective divide** — `z = C*depthScale + zWobble*sin(...)`; `persp = 1/(1+z*0.1); P = pos3.xy*persp` — turning the flat particle field into a 3D depth field, and makes `aspect` sculpt the orbit ellipse (`aspect*sin`, `(1/aspect)*cos`). The clearest single-step creative addition in the family.
- **D**: splits time into `Srot`/`Sosc` (independent rotation vs oscillation time scales); exotic radius-dependent rotation `angle = angleNumer/exp(R/rDivider) * pow(sin(Srot/sinTimeDiv), sinPow)` — rotation rate decays exponentially with radius, producing differential-spin spirals.
- **E**: broken one-line kishimisu code-golf shader pasted with undefined `u`/`O`/`uvAspect`/`timeScale` — non-compiling.
- **X v01**: spiral bloom — per-iteration rotation `rot2(t*speed + i*0.1)` with geometric radius decay `pow(0.94, i)`, Gaussian weight `exp(-d*bloomRadius)`, 3-phase sine color.
- **X v02**: iteration-progressive escalation — noise warp, phase amplitudes, and direction chaos all scaled by `(1 + fi/iters)` so distortion visibly ramps across the accumulation; single precomputed noise sample shared by all iterations (explicit perf choice); full IQ palette with exposed freq/offset.
- **X v03**: true SDF raymarcher — twisted torus (`p.xz` rotated by `twistAmp*p.y`), domain-warped by 3D value noise, 64-step march, central-difference normals, orbit camera with look-at frame construction, diffuse light + distance-attenuated bloom `bloom*diff*exp(-t*0.5)`, gamma. Structurally unlike everything else in the batch.

**Control/UI design**: Flat lists, ShaderToy-register names (`freqA`, `ampB`, `powExp`) — different voice from the author's own generators (no dividers, no palette-color inputs, no macros). The porting discipline is the design: every constant becomes a MIN/MAX/DEFAULT slider (up to ~25 per file).

**Version evolution**: Reads as a practice/study set: A/B/C/D work the same accumulation idiom across four source shaders; C v02 and the X branch show original extensions (perspective depth; spiral bloom; progressive micro-warp); X v03 is a deliberate exercise in the one technique class (raymarching) the idiom family doesn't touch. E is an abandoned start.

**Complexity tier**: A/B/D: 2–3. C v01: 2, C v02: 3. X v01: 2, X v02: 3. X v03: 4. E: 1 (broken).

**Signature moves & standout tricks**: X v02's `*(1 + fi/iters)` progressive-distortion scaling — a one-line trick making uniform loops read as escalating. C v02's minimal perspective-divide retrofit. D's exp-decay differential rotation. The systematized "every constant → slider" conversion recipe itself is the reusable asset for a shader-generator.

**Rough edges**: E is non-compiling dead code — direct evidence that raw ShaderToy paste-ports fail on entry-point/UV/uniform mismatches without deliberate adaptation (the "Fixed ISF port" phrasing on A–D implies earlier broken attempts). B declares `smoothBCenter` default 1.28 with the mask `smoothstep(0, 0.09, abs(l - 1.28))` — nearly always ~1.0, i.e. an almost-no-op mask kept as a slider anyway.

---

### Family: AR_CurlflowChroma_v01_dataloss_v01 — 1 file

**Purpose & visual identity**: Hybrid generator/filter. Curl-noise fluid-ink painter: video and audio deposit pigment that advects through divergence-free turbulence and undergoes three-species rock-paper-scissors chemistry, forming rotating spiral wavefronts; persistent feedback braids trails; BPM-locked color blooms and FFT-triggered ink drops. The most ambitious single file in the batch.

**Architecture**: 3 passes — `simBuffer` (PERSISTENT+FLOAT: RGB = ink species, A = flow magnitude), `trailBuffer` (PERSISTENT+FLOAT: diffused ghost layer), final display. Init guard `FRAMEINDEX < 2 || resetButton` seeds sim from video luminance in both buffers. Full-res sim (no downscale trick here).

**Techniques**:
- **Curl-noise velocity field**: perpendicular central-difference gradient of an FBM of Ashima simplex noise — divergence-free by construction, "LOOKS like advection because divergence is identically zero" (their comment) with no pressure solve. FBM uses const-max-octave + runtime break, called out in-code as "the only safe pattern for non-const loop bounds." The snoise itself has the vec2 ternary unrolled to if/else "for Metal backend safety" — two documented host-quirk workarounds in one function chain.
- **Backward-advection**: `ink = IMG_NORM_PIXEL(simBuffer, wrapUV(uv - displacement))` — semi-Lagrangian backtrace with toroidal wrap.
- **Frame-rate-independent timestep**: `dt = clamp(TIMEDELTA*60.0, 0.5, 2.0)` normalizes to per-60fps-frame units; decay applied as `pow(inkDecay, dt)`.
- **Rock-paper-scissors Lotka-Volterra chemistry**:
  ```glsl
  dR = ra * (ink.r*ink.g - ink.b*ink.r);
  dG = ra * (ink.g*ink.b - ink.r*ink.g);
  dB = ra * (ink.b*ink.r - ink.g*ink.b);
  ```
  R eats G, G eats B, B eats R (direction switch swaps predator/prey, reversing spiral rotation). `stabilityFloor` mixes toward neutral gray so no species collapses to zero and locks the state.
- **Flow-coupled reaction brake**: `brake = clamp(1 - flowMag*velocityChemBrake, 0.05, 1)` — chemistry slows in fast eddies, so spirals form in calm zones; their comment: this is "what gives the visual its 'weather front' feel."
- **Self-warping feedback turbulence** (`flowWarp`): previous frame's ink density perturbs the current noise-field input coordinate — sim state stirs its own driving field.
- **Frame-rate-independent beat-boundary detection**: `step(0.5, floor(TIME/secs) - floor((TIME-TIMEDELTA)/secs))` — fires exactly once per beat crossing regardless of frame rate.
- **FFT band drops**: three simultaneous ink drops per beat at hash-derived positions (`hash11(beatIdx + primes)`), one per bass/mid/high band, each tinted toward a different primary specifically so the RPS chemistry engages; exponential distance falloff, per-band sizes.
- **Saturation servo**: pushes ink toward primaries (`mix` toward maxC/minC by a signed boost) so chemistry doesn't desaturate to mud.
- **Trail pass**: 5-tap blur mixed into history, then `max(prev*pow(trailDecay,dt), sim*0.6)` — explicitly max-based ("mix() pulls trails to zero, max() lets them linger" — citing their own ISF skill doc).
- **5 palette modes** including Phase (hue = velocity angle `atan(vel.y,vel.x)`, sat = speed, val = density), Heat (blue→red→white two-stage smoothstep), Aurora, HSV Bloom with beat pulse `pow(0.5+0.5*sin(phase*TAU), 3)`.
- **Edge glow**: 4-tap Sobel-lite gradient magnitude on the sim buffer coloring wavefronts with a hue-shifted palette variant.
- **View system**: zoom/pan/rotate + 5 mirror modes (H/V/quad/6-fold polar kaleidoscope), applied at display so the sim itself stays unmirrored.
- **Glitch post**: radial chromatic aberration (re-palettized, not just RGB-shifted), scanlines, bit-crush `floor(col*2^bits)/2^bits`, FRAMEINDEX-seeded grain — all scaled by one `glitchMacro`.
- **6 debug overlays**: velocity field (as RG+magnitude), curl magnitude, raw ink channels, edge map, audio bands — built-in instrumentation.

**Control/UI design**: The batch's most rigorous surface (~45 inputs): numbered/lettered LABEL prefixes forcing sort order (`0.Tempo |`, `1.Flow |` … `8.Glitch |`, `F.Source`, `V.View`, `M.Macro`, `Z.Debug`). Four macro/conductor knobs (`flowMacro`, `pigmentMacro`, `glitchMacro`, `masterMix`) each scaling a whole subsystem. Dedicated BPM block with separate beats-per-bloom and beats-per-drop divisions. `long` enum inputs with LABELS everywhere.

**Version evolution**: Single file in this batch; internal comments reference "mirrors v02's pattern" (BPM helpers) — it consciously consolidates conventions from across the catalog (curl noise from ColorFullFlickers_v02B, macro knobs, BPM helpers, max-trails, kaleidoscope). Reads as a flagship "everything learned so far" build.

**Complexity tier**: 5 — highest in the batch on every axis (passes, buffer semantics, control surface, technique diversity, in-code documentation).

**Signature moves & standout tricks**: The RPS cyclic chemistry as a color-space reaction system; flow-braked reaction rate; density-feeds-back-into-noise-coordinates; beat-boundary-crossing detector; per-band beat drops tinted to engage the chemistry. All five are distinctive generator "ingredients."

**Rough edges**: Essentially none — unusually clean and self-documenting; even the known hazards (Metal ternary, loop bounds, mix-vs-max) are handled with explanatory comments. Phase palette re-derives curl noise at display time (extra cost) — a documented deliberate tradeoff for post-view-transform accuracy.

---

### Family: AR_CustomStrobe (v01–v04) — 4 files

**Purpose & visual identity**: Filter. Envelope-driven strobe/deconstruction: a hit (manual event or BPM auto-trigger) charges an energy envelope decaying over time, which drives flash brightness, chirping strobe frequency, inversion, glitch operators, and feedback trails.

**Architecture**: v01: 2 passes (1×1 PERSISTENT `envBuffer` + display). v02: 3 passes (+FLOAT `render_buffer`, PERSISTENT FLOAT `trail_buffer`). v03: 4 passes (adds explicit final output pass; trail becomes signed-delta storage). v04: 5 passes (env → render → non-persistent `trail_delta` → persistent `trail_buffer` accumulator → output). One pass added per version as the pipeline gains a concern.

**Techniques**:
- **1×1 persistent state buffer**: `IMG_PIXEL(envBuffer, vec2(0.5))` stores (energy, hitCount, lastTrigTime) in RGB — a scalar state machine in a texture. Energy: reset to 1.0 on trigger, else `energy *= max(0, 1 - decaySpeed*0.05)` (FRAMEINDEX-0 guarded). hitCount wraps at 10000 to dodge float precision loss.
- **Chirp coupling**: strobe frequency `= baseFreq*(0.3 + energy*0.7)` — flicker rate audibly "falls" as the hit decays. 4 oscillator shapes (square/sine/saw/sample-and-hold noise via `hash11(floor(phase))`).
- **BPM auto-trigger with subdivisions and swing**: `period = 60/bpm × {1, ½, ¼, ⅛, ⅓ triplet, 1.5 dotted}`. v02-initial detects beat boundaries by phase math; v02-final/v03/v04 switch to elapsed-time-since-last-trigger (`TIME - lastTrigTime >= swingPeriod`) — more robust at low frame rates and makes swing trivially correct (alternate beats get `period*(1 ± swing*0.6)`).
- **4 decay-curve shapers** applied on read, not in storage: exponential (raw), linear (`sqrt(energy)` perceptually linearizes multiplicative decay), bounce (`abs(sin(t*12))*energy` re-triggers at shrinking amplitude), elastic (`energy*(1+sin(t*20)*energy*0.5)`, overshoots to 1.5).
- **Spatial masks**: v02-initial ships hard grid masks (H/V bands, radial rings, quadrant-stepping); v02-final replaces them with organic layered-sine fields (Wash/Vortex/Caustic/Drift Field), each mixing 2–3 detuned sine terms with per-hit golden-ratio phase drift (`hitCount*0.618 + TIME*0.1`) so no two hits mask identically. Caustic mode multiplies three moving radial sines — a cheap water-caustic look.
- **Per-hit variation everywhere**: displacement rotation angle `hitCount*1.618`, chroma split angle `energy*12 + hitCount*2.4`, mask drift — golden-ratio increments as the standard "never repeats" device.
- **Channel shatter**: three independent strobe oscillators at detuned frequencies (×1.1/×0.9/×1.0) and phase spreads gate per-channel blends toward the negative — RGB channels flicker out of sync.
- **5 negative modes**: full invert, luma-preserving negative (rescales color by invLuma/luma ratio), channel rotate (b,r,g), HSV hue+0.5, multiplicative complement.
- **Displacement engine** (v04, 4 modes): Gradient (luminance-gradient push), Radial (explode from center × local luma), Angular (perpendicular swirl `vec2(-c.y,c.x)/r`), Block (UV quantized to hashed blocks shifting as rigid units — true block-glitch/datamosh flavor).
- **Dither engine** (v04, 4 patterns): Bayer 4×4 (explicit 16-entry array — no const-array init in one expression, Metal-safe), Bayer 8×8 built recursively from two 4×4 layers, halftone (cell-center distance), temporal noise; per-channel coordinate offset for "chromatic dither"; above 50% strength blends toward hard 1-bit `step()`.
- **Signed-delta trail architecture** (v03/v04): trail stores `rendered - clean` in a FLOAT buffer (can hold negatives), decayed and *additively* accumulated, composited as `clamp(live + trail, 0, 1)`. Explicitly motivated: max-based raw-color trails (v02) can only brighten — dark/inversion flashes left no trace. v04 further splits delta computation (non-persistent pass) from accumulation (persistent pass).
- **dFdx/dFdy melt**: `meltUV = fbUV - vec2(dFdx(prev.r), dFdy(prev.r)) * trailMelt*0.5` — screen-space derivatives of the trail's own red channel warp the feedback resample, an organic smear from derivative hardware for free. Present v02+, alongside zoom/rotate feedback transform and `snapUV` pixel-center snapping to reduce feedback blur drift.
- **Early-out**: `if (energy < 0.001) { pass through input; return; }` — the whole effect costs ~nothing when idle.

**Control/UI design**: Colon-prefixed category tags in LABELs (`"Auto: BPM"`, `"Strobe: Decay"`, `"Flash: Inversion"`, `"Trail: Melt"`) — a third distinct section-labeling convention in the batch. Manual `trigger` event + `autoFlash` bool + BPM block is the repeated "manual-or-automatic" pattern. `holdMode` bool freezes decay for sustained effect. `long` enums with human LABELS for every mode selector.

**Version evolution**: v01 (credit "Gemini" — an AI-generated seed) is the minimal envelope+chirp. v02 (credit "Arson Rivvers + Claude") explodes scope: BPM/swing, decay curves, masks, shatter, 5 negatives, crush, dither, and a 3-pass max-based trail engine; then, still numbered v2 (the file read as v03 carries the v2 DESCRIPTION), the architecture is fixed: organic masks replace grids, elapsed-time triggering replaces boundary math, and trails become signed deltas. v04 modularizes: displacement and dither each generalized from single hard-coded methods to 4-way selectable engines, delta/accumulate split into separate passes, spatialDisplace folded into the displacement engine. Trajectory: seed → scope explosion → architectural correction → modular generalization.

**Complexity tier**: v01: 2. v02: 4. v03: 4 (same scope, corrected architecture). v04: 5 (most passes, widest operator selection).

**Signature moves & standout tricks**: Signed-delta FLOAT trail buffers (general solution to "trails must carry darkening too"); dFdx/dFdy melt feedback; golden-ratio per-hit phase drift; 1×1 buffer as multi-scalar state machine; energy-chirped strobe frequency.

**Rough edges**: v02-initial's hard grid masks and max-based raw-color trails are same-version-superseded — direct negative knowledge (boundary-crossing beat detection and brighten-only trails both failed in practice). v01's `strobeSignal = step(0.5, sin(TIME*freq))` with energy-dependent freq causes phase discontinuities as freq changes (fixed implicitly by v02's phase-accumulating oscillator forms only partially — they still multiply TIME×freq; the chirp is approximate throughout).

---

### Family: AR_DancingFlowers_v03 — 1 file

**Purpose & visual identity**: Filter. "Expanded feedback engine" — classic VJ feedback-trails (video seeds a persistent buffer that resamples itself with drift/rotation/color-shift), tuned to a specific aesthetic, with an unusual displacement source.

**Architecture**: 2 passes — PERSISTENT `BufferA` (not FLOAT — 8-bit feedback, unlike the other feedback files in the batch), display pass-through.

**Techniques**:
- **Channel-difference pseudo-flow field**: `organicDisp = vec2(fb.y - fb.x, fb.x - fb.z)` — the fed-back image's own R−G / G−B channel differences serve as the 2D displacement vector. No noise function, no simulation: the color content *is* the velocity field, so displacement co-evolves with the hue drift that constantly changes those channel relationships. Unique in the batch.
- **Joystick steering**: `directionX/Y` inputs (explicitly labeled "(Joystick)") add a manual constant drift on top of the organic one — live-performance steering, `directionAmount` as force.
- **Per-frame HSV drift on the trail**: resampled color → HSV → hue += `hueTrailSpeed*0.01`, sat += `saturationDrift*0.005`, val += `brightnessDrift*0.005` → RGB. Continuous psychedelic color cycling; brightnessDrift doubles as the decay control (negative = fade, positive = bloom/overdrive).
- **Dual-regime luma threshold injection**: `alphaForDark = 1-step(amount, luma)`, `alphaForBright = step(amount, luma)`, crossfaded by `thresholdMix` — one slider morphs between "video's dark regions overwrite the feedback" and "bright regions overwrite," i.e. whether trails grow out of shadows or highlights.
- **Noise seeding**: single value-noise sample added to the trail each frame (`rand.rgb * noiseAmount`) to keep the feedback from sterilizing.

**Control/UI design**: Flat descriptive labels, no section convention; performance-oriented (joystick pair, force, spin). In-code comment "NEW: Internal scaling makes the sliders more intuitive" marks the v03 refinement: raw drift sliders rescaled internally (×0.01, ×0.005) so exposed ranges feel controllable — an ergonomics-over-math revision.

**Version evolution**: v03 only in this batch; the "NEW:" comment indicates prior versions had raw (twitchy) drift ranges. Displacement scale slider MAX of 100.0 with default 0.057 suggests a range that was never re-tightened after the internal rescale — a leftover.

**Complexity tier**: 3.

**Signature moves & standout tricks**: The zero-cost channel-differencing flow field is the standout — organic, content-reactive displacement with no noise function at all; a genuinely reusable lightweight "ingredient."

**Rough edges**: 8-bit (non-FLOAT) persistent buffer will posterize under long feedback + HSV drift; `displacementScale` MIN 0/MAX 100 against a 0.057 default is a mis-scaled slider range; `amount` input has no MIN/MAX declared (relies on host defaults).

---

## Batch synthesis

**Top 3 most sophisticated files:**
1. **`AR_CurlflowChroma_v01_dataloss_v01.fs`** — 3-pass curl-noise fluid painter with three-species cyclic Lotka-Volterra pigment chemistry, flow-braked reaction rate, self-warping feedback turbulence, frame-rate-independent beat-boundary FFT ink drops, 5 palette modes, 6 debug overlays, macro conductors, and documented host-quirk workarounds. Widest technique range, cleanest engineering.
2. **`ArsonRivvers_ColorFullFlickers_v03B.fs`** — structure-tensor eigen-analysis of the source video builds an anisotropic metric that space is inverted through before fractal marching, plus radial eversion and OKLab-approximate chroma rotation keyed to eigenvalue anisotropy. A real computer-vision concept repurposed as VJ material.
3. **`AR_Circle2Square_v07.fs`** — 48 discrete, perspective-projected, spiral-twisted, hash-jittered ring objects wrapping seamlessly through z-depth in one pass, with wrap-fades hiding the recycle seam. (Runners-up: v08/v09's 3-band core/halo/bloom light model; CustomStrobe v04's 5-pass modular glitch engine.)

**Recurring patterns / style fingerprints:**
- IQ cosine palette with palA–palD exposed as 4 `color` inputs — the default color system for original generators.
- Helpers (`rgb2hsv`/`hsv2rgb`, hash11/12/21/31, valueNoise, simplexNoise, `rotate2D`, Rodrigues `R()` macro) copy-pasted verbatim across files — biggest consolidation opportunity for a generator.
- Const-loop-bound + runtime `break` everywhere a parameter drives iteration count; `FRAMEINDEX<2 || reset` as the universal persistent-buffer init guard; `dt = clamp(TIMEDELTA*60, 0.5, 2)` frame-rate normalization.
- `max(prev*decay, current)` trail accumulation as an explicit, commented choice — and the CustomStrobe arc shows its limit (brighten-only) being discovered and fixed with signed-delta FLOAT buffers.
- Three competing section-header UI conventions: box-drawing LABELs (Circle2Square), dummy `TYPE:"text"` inputs (ColorGrading), numbered/colon prefix tags (CurlflowChroma/CustomStrobe) — active experimentation with faking grouped UI in flat-list hosts.
- Macro/conductor knobs (one float scaling a subsystem) and quality-mode tiering as recurring control philosophy; golden-ratio (0.618/1.618) phase increments as the standard per-hit/per-iteration "never repeat" device.
- BPM helpers (period = 60/bpm × subdivision, swing, boundary detection) independently reimplemented in ≥3 families at differing robustness — candidate for one authoritative shared utility.
- Fractional smoothing of integer parameters (fractional ring/layer/side counts fade the last element in) — a distinctive house pattern.

**Beyond-ShaderToy techniques found:**
- Structure-tensor anisotropic space inversion + eversion (v03B).
- Per-pixel cyclic rock-paper-scissors reaction chemistry with flow-coupled rate (CurlflowChroma).
- Reciprocal-depth (`1/d`) tunnel perspective from a pure 2D distance field (Circle2Square v06).
- dFdx/dFdy derivative-driven feedback "melt" distortion (CustomStrobe).
- Feedback-buffer channel differencing as a flow field with no noise source (DancingFlowers).
- Signed-delta FLOAT trail buffers so darkening effects trail correctly (CustomStrobe v03/v04).
- 1×1 persistent buffer as a multi-scalar state machine (energy/hitCount/lastTrigTime) driving a whole effect graph (CustomStrobe).

**Negative knowledge (host-quirk scars, abandoned directions):**
- Never pass `sampler2D`/call raw `texture2D` in ISF — route through IMG macros on named symbols (ColorGrading v01→v02 fix).
- Raw ShaderToy paste-ports fail without deliberate UV/entry-point adaptation (`AR_ConversionImport_E_v01.fs` is a non-compiling abandoned paste; A–D all say "Fixed ISF port").
- Ternaries on vector types unrolled to if/else "for Metal backend safety" (CurlflowChroma snoise); Bayer matrices built by element-wise assignment, not array initializers.
- Hard `if`-swap component shuffles in fractal folds cause frame popping — replaced with smoothstep-blended shuffles (ColorFullFlickers v01→v02); symmetric fold offsets cause a visible center mirror seam — fixed with small asymmetric non-round constants.
- Beat detection by phase-boundary math misfires at low frame rates — replaced by elapsed-time-since-last-trigger (CustomStrobe v02→v03).
- Easing curves on live rotation controls were tried and removed in favor of direct predictable speed (Circle2Square v03→v04).
