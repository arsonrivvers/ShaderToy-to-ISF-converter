All 44 files were read in full before the stall; the complete report follows as my final message per the coordinator's instruction.

# Batch 01 Analysis Report

## Coverage
- files_assigned: 44, files_read: 44, misses: none

All 44 files listed in batch_01.txt were read in full (no truncation). Paths relative to `/Library/Graphics/ISF/`.

---

## Per family

### 1. Datamosh / Optical-Flow Glitch — `AR_11111.fs`
- **Purpose & visual identity**: Filter. Enhanced datamosh using a real optical-flow estimate (not just UV jitter) between a "motion" input and a delayed buffer, then displaces `inputImage` along the flow vector with radial chromatic aberration and per-pixel freeze/glitch probability. Reads as genuine "broken codec" motion smear.
- **Architecture**: 4 passes. Pass0 (half-res `flowMaskBuffer`, persistent): computes optical flow via gradient/finite-difference of luminance between current & delayed frame, then a manual 3x3 Gaussian blur (weights 1/16..4/16) of the flow mask, accumulated with `feedback` decay. Pass1 (half-res `delayBuffer`, persistent): stores previous `motionImage` frame (1-frame delay line). Pass2 (`feedbackBuffer`, persistent, full-res): applies the flow-driven UV displacement + per-pixel freeze + radial chromatic aberration + noise wiggle, blends with previous feedback. Pass3: passthrough.
- **Techniques**:
  - Manual optical flow: samples 8-neighborhood of both current and delayed luminance frames, computes `gradx`/`grady` (central differences), then velocity `vx = curdif * (gradx / safe_gradmag)`, split into positive/negative halves packed into a vec4 mask (`xout.x/xout.y, yout.x/yout.y`) — a "signed flow packed in RGBA" encoding, since signed data can't survive standard buffers/blur cleanly. Note the `max(gradmag, vec4(0.00001))` divide-by-zero guard.
  - Hand-rolled 3x3 Gaussian blur of the flow mask via 9 explicit weighted taps (no loop), run at half resolution for perf (`"WIDTH": "$WIDTH/2.0"` in PASSES).
  - Freeze/glitch: `random(uv*RENDERSIZE + randomSeed) < freezeProbability` → holds old feedback pixel instead of updating (stutter/frame-hold artifact).
  - Radial chromatic aberration keyed to `dir = normalize(uv - 0.5)`, with three offset scales for R/G/B (1.5x / 1.0x / 0.5x).
- **Control/UI design**: 10 inputs, all plain descriptive camelCase (`feedback`, `originalMotion`, `displacementIntensity`, `invertMotion`, `feedbackMix`, `randomSeed`, `freezeProbability`, `chromaticAberration`, `noiseIntensity`, `motionImage` as a second image input). No sectioning/emoji conventions — predates the later labeling systems.
- **Version evolution**: Single version in this batch; DESCRIPTION says "Enhanced," implying a simpler predecessor elsewhere.
- **Complexity tier**: 4 — multi-pass persistent-buffer optical-flow system with downscaled sim passes.
- **Signature moves**: Real gradient-based optical flow (most VJ datamosh shaders fake it with jittered UVs); signed-flow-in-RGBA packing; half-res sim buffers.
- **Rough edges**: Dead commented-out `coeffs` const at top. Separate `motionImage` input duplicating `inputImage`'s role adds host-wiring friction.

### 2. Shadertoy conversion tests — `AR_11-ISFShaderConversion_test_v01/v02.fs`
- **Purpose & visual identity**: Generators. Ports of two ShaderToy raymarch pieces: v01 = "Firewall" by @XorDev (polar-coordinate accretion cylinder with trig turbulence), v02 = "Cloud In a Bottle" (volumetric fbm cloud with orbiting camera).
- **Architecture**: Single pass; both use the `pass0_mainImage(out vec4 O, vec2 I)` wrapper called from a thin `main()` on `PASSINDEX == 0` — the author's standard converted-Shadertoy scaffold preserving the original `mainImage` signature.
- **Techniques**:
  - v01: XorDev code-golf raymarch — `for(O*=i; i++<2e1; )` (zero-init by multiplying uninitialized accumulator by 0-valued iterator), polar transform `p = vec3(atan(p.z+=9.,p.x+.1)*2., .6*p.y+t+t, length(p.xz)-3.)`, turbulence via nested `for(d=0.;d++<7.;) p += sin(p.yzx*d+t+.5*i)/d;` (the classic decreasing-amplitude trig-octave domain warp), cosine-palette coloring `1.+cos(p.y+i*.4+vec4(6,1,2,0))`, and `O = tanh(O*O/6e3)` tonemap.
  - v02: 3D value noise (`hash(n + dot(step, corner))` trilinear mix), 8-octave fbm, volumetric density `volume(p) = max(min(fbm(p*2+0.01*TIME)-0.2, 0.2), length(p)-0.5)` (fbm clipped and intersected with a bounding sphere), front-to-back alpha compositing with early-out at `col.w > 0.998`, directional light approximated by density difference `ld = (volume(ro+light)-v)/length(light)`.
  - v02 carries a **GLSL 1.20 tanh polyfill block** (`#if __VERSION__ < 130`, manual `(e-1)/(e+1)` on clamped input, overloaded for float/vec2/vec3/vec4), explicitly commented "auto-added by the converter" — a reusable host-compatibility defense for modern ShaderToy code on ISF's older GLSL.
- **Control/UI design**: v01 zero inputs; v02 one `point2D mouse` (auto-orbits when idle — checks a mouse-derived value near 0 to fall back to `2.0*vec3(cos(t),1,sin(t))` circular path).
- **Version evolution**: v01→v02 is exploration of two different raymarch styles for conversion feasibility, not refinement.
- **Complexity tier**: 3 (single pass but real volumetric raymarching + fbm).
- **Signature moves**: The version-gated tanh polyfill; the pass0_mainImage bridging scaffold.
- **Rough edges**: v02's `vec4(mouse * RENDERSIZE, mouse * RENDERSIZE).z` construction is an auto-converter artifact of ShaderToy's `iMouse.zw` click state (ISF has no click state) — fragile but functional.

### 3. Raymarched image relief — `AR_3D_Displacement_v01.fs`
- **Purpose & visual identity**: Filter. Extrudes input video into a lit 3D bas-relief: luma → height, raymarched as a smooth-min blend of a box SDF and the image displacement, with rotatable camera.
- **Architecture**: Single pass; classic sphere-tracing raymarcher (MAX_STEPS 100, SURF_DIST .001, MAX_DIST 4) wrapped in a 2x2 AA supersampling loop.
- **Techniques**:
  - `GetImagePlane(p)`: maps world XY → image UV (aspect-corrected, X-flipped), luma via Rec.601 dot, returns `vec4(tex*luma/2., (1.0-luma*treshold*thresholdMultiplier)*effDepth)` — luma-as-displacement in the SDF's w channel.
  - iq's polynomial `smin(a,b,k)` blends image displacement with the bounding box (`GetDist = smin(image, box, shapeSmoothness)`; note negative default `shapeSmoothness = -0.03` gives a subtractive/crease feel).
  - Central-difference normals; simple half-Lambert lighting `dif = dot(n, normalize(vec3(1,2,3)))*.5+.5`; gamma correction `pow(col, vec3(.4545))`.
  - **`effectAmount` macro dry/wet**: `effRotationY = mix(0.5, rotationY, effectAmount)` etc. — at 0 every camera/depth control collapses to a neutral default. This "wet/dry crossfade for an entire scene" pattern recurs across the author's later families.
- **Control/UI design**: 10 float inputs, camelCase, includes typo'd `treshold` alongside `thresholdMultiplier`. No sectioning.
- **Version evolution**: v01 only; CREDIT "Rhythmic Visions - Modified by Gemini" — an adopted shader, AI-assisted modification.
- **Complexity tier**: 4 (full SDF raymarcher + smin displacement + AA), single pass.
- **Signature moves**: Luma-as-height raymarched relief of live video; effectAmount neutral-collapse convention.
- **Rough edges**: AA=2 (4 rays/pixel) × 100 steps with no quality selector — the perf-tier control (Quality_Mode) only shows up in later families. `treshold` typo baked into the public control name.

### 4. ASCII family — `AR_ASCII.fs`, `AR_ASCII_2.fs`, `AR_ASCII_BinaryVersion_1/2/3.fs`, `AR_ASCII_Complex_v01.fs`
- **Purpose & visual identity**: Video→character-mosaic stylizers (filters), plus one generator. `AR_ASCII`: 9-level tonal ramp (`. , : * o & 8 @ #`) selected by brightness. `BinaryVersion_1`: 0/1 binary with black/white inversion. `BinaryVersion_2`: digital-rain variant, 13 glyphs, falling columns, red/black fixed palette. `BinaryVersion_3`: stripped-back 0/1 + sourceBlend. `AR_ASCII_2`: generator — raymarched spinning donut rendered as ASCII (dkaraush Shadertoy port). `ASCII_Complex_v01`: font-atlas-texture experiment.
- **Architecture**: All single-pass, no buffers.
- **Techniques**:
  - The shared canonical **float-bitmask glyph stamp**:
    ```glsl
    float character(float n, vec2 p) {
        float s = 4.0;
        p = floor(p * vec2(s, -s) + 2.5);
        if (clamp(p.x,0.,s)==p.x && clamp(p.y,0.,s)==p.y) {
            float b = p.x + (s+1.0)*p.y;
            if (int(mod(n / exp2(b), 2.0)) == 1) return 1.0;
        }
        return 0.0;
    }
    ```
    Each glyph is one float whose bits (extracted via `mod(n/exp2(bit), 2.0)` — no native bitwise ops needed on GLSL ES 1.00) encode a 5x5 lit grid. Identical core across all bitmask variants; `AR_ASCII` parameterizes `scale = mix(4.0, 8.0, (asciiSize-4.0)/12.0)`.
  - Brightness→glyph threshold ladder (nine sequential `if (gray > 0.x) n = ...;` steps) in `AR_ASCII`; brightness→0/1 threshold + separate brightness→bg/fg inversion split (`threshold` vs fixed 0.5) in BinaryVersion_1/3.
  - Pixelation by cell-snapped sampling: `IMG_NORM_PIXEL(inputImage, (floor(uv/_size)*_size)/RENDERSIZE.xy)`; local glyph coordinate via `mod(uv/(_size/2.0), 2.0) - 1.0`.
  - **Digital rain** (BinaryVersion_2): `effectiveCellY = cell.y - TIME*fallSpeed*(0.5+columnRandSpeedOffset)` with per-column hashed speed offset and `mod(effectiveCellY, numCellsY)` wrap — the *source video content* falls through a fixed glyph grid; per-cell time-seeded hash picks among 13 glyph constants (0,1,A,K,M,P,S,X,#,+,?,/,fullblock); cell-center sampling offset (`+vec2(s*0.5)`) for stability.
  - `AR_ASCII_2`: torus SDF via a rotation matrix built from `sin/cos(iTime)` applied as `mat4 * vec4(p+vec3(0,0,-4),1)`, 15-step naive marching `C += d*G(C)`, finite-difference normals, diffuse `D_val`, then brightness→one of 13 approximate ASCII bit patterns; `isBitSet()` does arithmetic bit extraction (`mod(floor(pattern/2^bit),2)`) since GLSL ES 1.00 lacks `&`/`>>`.
  - `ASCII_Complex_v01`: 8x11-cell glyph atlas PNG sampled by computed `atlasUV`; glyph *chosen by 2D value noise* (`noise2d(cell*0.1 + iTime*0.05)`) rather than by image brightness — noise→glyph field, not video quantization.
- **Control/UI design**: `pixelation`+`asciiSize` coarse/fine pair (AR_ASCII); `threshold`/`gridSize`/`sourceBlend` (+`fallSpeed` in v2) with LABEL fields ("Digit Threshold", "ASCII Cell Size"). No macros.
- **Version evolution**: tonal ramp → binary → binary+rain+glyph-variety (peak complexity) → BinaryVersion_3 rollback to minimal binary (fall animation and glyph bank stripped — likely a clarity/perf retreat after v2). `ASCII_Complex_v01` is a parallel atlas-texture branch, evidently abandoned (input declared with hardcoded absolute PATH; still uses ShaderToy-style uniforms).
- **Complexity tier**: 1–2 for the quantizers; 3 for AR_ASCII_2 (raymarch + glyph rendering combined).
- **Signature moves**: The float-bitmask `character()` stamp (texture-free, GLSL-ES-1.00-safe bitmap font); the video-sampling digital rain.
- **Rough edges**: `ASCII_Complex_v01` hardcodes `/Users/arsonrivvers/Downloads/fontAtlas.png` — non-portable prototype. AR_ASCII_2's hex→float pattern constants are flagged "approx." (lossy conversion). BinaryVersion_2 leaves the original adaptive bg/fg logic commented out in favor of hardcoded red/black — dead code documenting a fork in intent. Both `AR_ASCII_2` and `ASCII_Complex_v01` declare stale ShaderToy uniforms (`uniform vec3 iResolution; uniform float iTime;`) that ISF doesn't populate — they compile but the donut only animates because... actually they'd render static/broken unless the host aliases them; conversion scars.

### 5. "Beautiful Kaleido" family (11 files) — kishimisu `mtyGWy` derivatives
`Kaleido_v01`, `KaleidoAlt_v02–v06`, `KaleidoPolar_v01–v02`, `KaleidoSpiral_v01–v02`, `KaleidoTunnel_v01`
- **Purpose & visual identity**: Generators, all descended from kishimisu's famous palette-fractal (`uv = fract(uv*scale) - offset` iterated tiles + IQ cosine palette + inverse-brightness ripple). The author systematically swaps the geometric core while keeping the palette/ripple/iteration "chassis" constant.
- **Architecture**: All single-pass. No ISF PASSES/persistent buffers anywhere in the family — `KaleidoAlt_v04/v05/v06` instead declare a **`prevFrame` image INPUT** for feedback, relying on the host to wire the shader's own output back in (lightweight, host-dependent feedback).
- **Techniques** (shared chassis: `palette(t) = palA.rgb + palB.rgb*cos(paletteFreqMul*(palC.rgb*t + palD.rgb))` with all four vectors exposed as color INPUTS; ripple = `d = pow(brightnessBase/abs(sin(d*rippleFreq + TIME*rippleTimeSpeed)/rippleDivisor), brightnessExponent)`; iteration loop = `for(int i=0;i<10;i++){ if(i>=int(iterations)) break; ...}` — the const-bound/runtime-break idiom, used correctly everywhere):
  - `v01`: faithful parameterized port. 17 inputs replacing every magic number of the original.
  - `KaleidoAlt_v02`: adds `radialFold()` (n-fold kaleidoscope: `ang = mod(atan(p.y,p.x), TAU/n) - TAU/(2n)`), `swirlWarp()` (`ang += strength*r`), 4-octave fbm domain warp per iteration, dynamic tile offset `uvOffset + sin(TIME*offsetSpeed)*offsetAmp`, **time-animated iteration depth** `maxI = int(1.0 + (sin(TIME*depthSpeed)*.5+.5)*(iterations-1.0))` ("breathing" recursion), angle-hue modulation `angHue=(atan(uv.y,uv.x)+PI)/TAU` added to palette t, and Reinhard tonemap `acc/(acc+1)`.
  - `KaleidoAlt_v03`: **signal-flow reorder experiment** — ripple computed on the *original* radius first, ripple value injected as a palette-t offset, and only then tile+falloff. Same ingredients, deliberately different order (comments number the stages 1–5).
  - `KaleidoAlt_v04`: introduces `prevFrame` "quantum delay": `uv += (texture2D(prevFrame, norm).rg - 0.5) * delayMix` — previous frame's color as a UV displacement field, plus the kaleido fold. First temporal-feedback member.
  - `KaleidoAlt_v05`: swaps the 2D tile core for a **Mandelbulb distance estimator** (`theta=acos(z.z/r)*power; phi=atan(z.y,z.x)*power; zr=pow(r,power); dr=zr/r*power*dr+1.0`, 8 iterations, `0.5*log(r)*r/dr`), raymarched with user-set `rSteps/power/bailout/maxDist`, still inside the same radialSym + prevFrame-delay + palette shell — a 3D fractal engine dropped into the 2D chassis.
  - `KaleidoAlt_v06`: back to 2D tiles but max-combined: fbm warp + prevFrame delay + radial fold + swirl + **3-octave ripple stack** `pow(brightnessBase/abs(r1 + 0.6*r2 + 0.3*r3), exp)` at 1x/1.7x/2.3x frequency ratios + angle-hue + Reinhard tonemap.
  - `KaleidoPolar_v01`: pivots primitive to **concentric sawtooth rings**: `saw = pow(abs(fract(r*ringFreq + TIME*ringSpeed) - 0.5)/ringWidth, ringExponent)`, per-iteration radius shift `r = r0 + i*spacing` with time-drifting spacing, plus the ripple highlight — `acc += col*(saw + d)`.
  - `KaleidoPolar_v02`: rings + fold + **fbm-warped ring radius** (`Wr = r + fbm(vec2(r*warpFreq+TIME*warpSpeed, float(i)))*warpAmp` — note fbm seeded with iteration index as y for decorrelation), 3-tier multi-frequency ring stack (`mix(s1,s2,0.5)+s3*0.5`), nonlinear radius `pow(r0, 1.0+i*radiusPower)`, angle-modulated spacing `sin(angle0*ringSpacingFreq+...)*ringSpacingAmp`.
  - `KaleidoSpiral_v01`: drops tiling entirely — **pure iterated swirl** (`while(i<cnt)` loop!) with description explicitly "no tiling or grid seams" — solving the visible tile-seam problem; ripple phase also gets `+normTheta*swirlStrength` for spiral-locked banding.
  - `KaleidoSpiral_v02`: swirl warps radius too — `warpedR = r + strength*0.05*r` (documented "5% per strength unit").
  - `KaleidoTunnel_v01`: rotating n-fold symmetry (`ang = atan(...) + angleOffset + TIME*rotationSpeed` before the fold) with renamed clearer sliders (`patternScale`, `colorOffsetPerIter`, `radialDecay`) — a UX-labeling cleanup rev.
- **Control/UI design**: Consistent 15–25 inputs per file: 4 palette colors + paletteFreqMul; `iterations` with `"STEP": 1.0`; scale/offset; per-iteration color offset + color speed; ripple triple (freq/speed/divisor); brightnessBase/Exponent; alpha. A reusable personal template with per-variant additions. All files carry a "ISF provides these uniforms" comment block (copy-pasted, sometimes stale).
- **Version evolution**: The richest chain in the batch: port → enrich (fold/swirl/warp/animated depth, v02) → reorder pipeline (v03) → add temporal feedback (v04) → swap in 3D fractal engine (v05) → recombine everything in 2D (v06); then parallel primitive pivots: rings (Polar v01→v02: +fold+fbm-warp+multi-tier), seamless swirl (Spiral v01→v02: +radius warp), rotating fold (Tunnel). Arc: master one chassis, then explore every geometry that fits inside it.
- **Complexity tier**: 2–3 for most; `KaleidoAlt_v05` (Mandelbulb raymarch) is 4.
- **Signature moves**: The palette+ripple+iteration chassis as a swap-the-core framework; `prevFrame`-as-INPUT host-wired feedback; time-animated iteration depth; floor/ceil-free "STEP":1.0 integer sliders; the ripple-as-color-offset reorder (v03) as evidence that signal-flow ORDER is treated as a first-class creative variable.
- **Rough edges**: All feedback is host-dependent (breaks in hosts that don't self-wire `prevFrame`). Naming drift between siblings (`colorSpeed` vs `colorTimeSpeed`). `KaleidoSpiral_v01` misses the lower iteration clamp v02 adds (`if(cnt<1) cnt=1`). Stale uniform-list comments. `KaleidoAlt_v03` guards `max(dRipple,1e-6)` where siblings divide by unguarded `abs(d)` — inconsistent division-safety.

### 6. `ArsonRivvers_BrokenPixelSorter_v01.fs`
- **Purpose & visual identity**: Filter. Fake pixel-sorting glitch: brightness-gated pixel migration through a persistent buffer produces smeared vertical streaks with per-frame direction alternation.
- **Architecture**: 2 passes: Pass0 → persistent `BufferA` (accumulator), Pass1 passthrough.
- **Techniques**:
  - Directional migration by frame/row parity: `if (int(mod(float(FRAMEINDEX)*GlitchFrequency + gl_FragCoord.y, 2.0)) == 0)` compare against south neighbor (`if(len_s > len) im = im_s;`) else against north (`if(len_n < len) im = im_n;`) — approximates a bubble-sort sweep distributed across frames, gated per-pixel by `random(gl_FragCoord + FRAMEINDEX) < Randomness`.
  - Bright-pass injection: pixels above `BrightnessThreshold` are re-fed into the accumulation as `bright`, blended by weight pair `(bright*BrightWeight + im*ImWeight)/totalWeight`.
  - Init/reset guard: `if (FRAMEINDEX < 1 || reset()) gl_FragColor = inputPixelColor;` — the standard first-frame seeding pattern.
  - Toroidal buffer sampling via `mod(uv + s, 1.0)`.
- **Control/UI design**: 9 inputs + `Reset` as a **bool** (not the ISF `event` type — a less idiomatic momentary trigger the author later corrects in ChaosLattice/ChaosCubes with proper `"TYPE":"event"`).
- **Version evolution**: single version.
- **Complexity tier**: 3.
- **Signature moves**: Frame-parity distributed "sorting" — a cheap single-tap-per-frame approximation of an inherently sequential algorithm.
- **Rough edges**: bool-as-event; `BrightWeight`/`ImWeight` as 0–100 percent-style ranges is inconsistent with 0–1 conventions elsewhere.

### 7. `ArsonRivvers_Chaos_PatternDepthMap_v01` (no `.fs` extension)
- **Purpose & visual identity**: Filter. XOR-fractal integer mask over live video, mask scale modulated by video luminance ("depth"), with rotation and scroll — circuit-board/Munching-Squares chaos keyed to image content.
- **Architecture**: Single pass, no buffers.
- **Techniques**:
  - Native integer XOR: `int r = x ^ y;` then `abs(r*r*r) / (y + int(TIME*50.0)) % 10970 < threshold` — XOR-of-coordinates fractal, cubed and time-divided for animation. Notably uses real `^` and `%` on ints (works in this host), whereas the ASCII family emulated bit ops arithmetically — evidence of divergent compatibility assumptions across files.
  - Luma-coupled spatial frequency: `adjustedPatternScale = patternScale * (1.0 + depth*2.0)` — the video warps the mask that masks it.
  - Manual 2D rotation of centered pixel coordinates before integer quantization (`direction` in degrees → radians).
- **Control/UI design**: 6 inputs incl. `invertPattern` bool. Plain names.
- **Version evolution**: single version.
- **Complexity tier**: 2 (cheap, single-pass), conceptually neat.
- **Signature moves**: Video-luma-modulated XOR pattern frequency — content-reactive without FFT or feedback.
- **Rough edges**: Missing `.fs` extension (likely won't be listed by extension-filtering hosts); integer division by `(y + int(TIME*50.0))` can hit zero/negative denominators — no guard.

### 8. ChaosCubes family — `AR_ChaosCubes_v00 → v04_beta` (flagship system, 607–879 lines each)
- **Purpose & visual identity**: Generators. "Volumetric Chaos ULTRA": hundreds of animated boxes/ellipsoids ray-intersected per pixel, rendered as FG/BG depth-difference signal with edge glow, curl feedback trails, Bayer dithering, 1-bit threshold mode, RGB split — a complete procedural VJ instrument.
- **Architecture** evolution:
  - v00 ("v3.0 Lowres Ed."): 4 passes — `BufferB` (BG geometry, FLOAT, non-persistent), `BufferA` (FG geometry, diffed vs B), `BufferC` (persistent FLOAT feedback + edge detection), final output (RGB split, `pow 1.2`, ×1.4 hardcoded).
  - v01 ("v4.0"): same 4-pass topology; adds `Feedback_Curl`, `Feedback_Mix`, `Primitive_Mode` (box/ellipsoid), 4-mode `palette()` color system applied per-channel post-RGB-split, `Output_Curve`/`Output_Gain` (un-hardcoding the tone stage), `Edge_Radius`, `Grid_Resolution`, `Size_Exponent` (un-hardcoding `pow(...,6.0)`). Comments mark "BUG FIX: both paths use Cull_Min / Cull_Max" (v00's FG path used a hardcoded 0.9 threshold) and "BUG FIX: camera-inside handling" (box hit now `if(box.y>0.0) hitDist=max(box.x,0.0)`; ellipsoid gets an inside-case fallback branch).
  - v02 ("v4.1"): adds `Wave_Phase`, `Orbit_Flavor` (parameterizing the magic vectors: `wavePhase = vec3(3,2,1)+Wave_Phase`, `orbitFreq = vec3(1,4,2)+Orbit_Flavor*vec3(0.618,1.0,0.382)` — golden-ratio-flavored frequency offsets), `Jitter_Speed`/`Jitter_Frequency` (un-hardcoding 50.0/143.0); replaces v01's messy inlined ellipsoid inside-case with a clean two-root `ellipsoidIntersect`; hoists uniform vectors out of the loop.
  - v03 ("v4.2 Performance Evolution"): **merges the two geometry passes into one** — `renderPassMerged` returns `vec2(depthFG, depthBG)` from a single loop (position/size/rotation trig computed once per box, BG gets only one extra slab test when `i < limitBG`), dropping to 3 passes. Adds: `sphereReject()` bounding-sphere broad-phase (`~3 ops vs ~30`, per its comment), `SIZE_SKIP_THRESHOLD` (skip boxes pow-crushed below 1e-4), `EARLY_EXIT_DEPTH` loop break when both depths bottom out, `fastPow` = `exp2(e*log2(max(x,1e-10)))`. A large header comment documents the entire optimization rationale — profile→optimize→document discipline.
  - v04_beta ("Rotation v2.0"): 2 render passes + display (drops emoji sectioning is retained but control set slimmed: `Orbit_Complexity`/`Seed_Shift`/`Jitter_*`/`Mirror` glitch removed or folded); orbit simplified to `sin(spreadBase + i + sin(i*orbitInner))`; `Grid_Snap` becomes a **continuous blend** `offs = mix(offs, snapped, Grid_Snap)` (was boolean >0.5 gate); grid snap gains `+0.5` round-to-nearest; edge detection adds a diagonal tap; `processSignal` simplified (Bayer/threshold path removed, `Signal_Quantize` becomes value-domain posterize `floor(val*q)/q` instead of UV crush); final pass drops RGB split.
- **Techniques**:
  - **Analytic primitive intersection instead of SDF marching**: slab-method `boxIntersection` and quadratic `ellipsoidIntersect` — per-primitive O(1) cost lets 100–900 primitives be tested per pixel with no marching loop.
  - **FG/BG depth-diff as the image**: two differently-culled versions of the same swarm are rendered and the *absolute difference of their processed signals* (`max(abs(sigFG - sigBG), 0.0)`) is the visual — producing outline/interference structure from solid geometry.
  - Per-index procedural animation: size = `pow(abs(sin(phase + idx*baseScale + 0.2*sin(idx*modul) + t*spd)), Size_Exponent)` (high exponent → spiky/sparse pulses); `Geometry_Spike` crossfades sin→`clamp(tan(...),-5,5)` for violent spikes (cubed for taper: `pow(Geometry_Spike,3.0)`); Lissajous-nested orbits `sin(vec3(idx*Orbit_Complexity) + sin(idx*orbitFreq + t*0.5)) * spreadAmp`.
  - Cull-pattern layers: `sin(idx)` bands vs `Cull_Min`/`Cull_Max` scale boxes anisotropically (`vec3(1,0.1,1)` vs `vec3(0.2,1,1)`) — one hash, two visual populations.
  - **Curl feedback**: `g = vec2(dFdx(buf.x), dFdy(buf.x)); curl = vec2(-g.y, g.x); flowDir = mix(g, curl, Feedback_Curl);` then `prev = IMG_NORM_PIXEL(BufferC, uv - flowDir*Distortion_Amt)` — rotating the self-gradient 90° turns shock-advection feedback into swirling pseudo-fluid trails, one slider between the two regimes.
  - Trail accumulation `C = mix(C*Feedback_Mix, prevFrame, Feedback_Decay)` with `Feedback_Decay` MAX 1.01 (deliberately allowing >1 runaway) guarded by `clamp(C, 0.0, 15.0)` only when >1 — controlled overdrive.
  - **Pre-raymarch UV quantization** (`Signal_Quantize`): `uv = floor(uv*grid)/grid` BEFORE geometry evaluation — the geometry itself becomes blocky, not just the output; feedback lookup optionally double-crushed with the same grid.
  - Bayer 4x4 ordered dithering (16-entry hardcoded matrix / 16.0) blended continuously via `Dither_Fade` against gamma; separate `dither()` screen noise `fract(tan(distance(xy*1.618..., xy)*seed)*xy.x)` (golden-ratio distance trick) for grain and 1-bit "crunchy noise."
  - Screen-space block glitch: floor-quantized block UV + two hash channels, conditional per-block offsets (`if(nY>0.6) offset.x = ...`) — VHS tracking bands.
  - Mirror modes: none / `abs(x)` / `abs(xy)` / kaleidoscope `vec2(max(a.x,a.y), min(a.x,a.y))` (fold across the diagonal).
  - Edge detection on the geometry buffer (4-tap, later 6-tap with diagonal, radius-parameterized `Edge_Radius/RENDERSIZE`) additively injecting `Edge_Brightness` into the feedback — edges seed the trails.
  - Per-channel palette after RGB split (v01–v03): sample BufferC at ±split, run `palette()` independently per channel, take `vec4(rCol.r, gCol.g, bCol.b, 1.0)` — CA and palette interact rather than stack.
- **Control/UI design**: The author's most mature convention: `"NAME"` PascalSnake (`Feedback_Decay`), LABEL prefixed by **emoji section glyphs** — 🔴 PANIC RESET (event), ⚡ hot performance knobs (Speed/Box Count/Trail Length/Punch/Curl/Brightness/Edge Glow/Fluid Distortion/Glitch), 🔶 geometry shape, 🌀 swarm motion, 📷 camera, 🎛 signal/output, 🎨 color, ▪️ threshold/dither block, ✦ edge sub-block, ⚙️ quality/seed/cull engineering. 35–45 inputs per file. `Quality_Mode` long enum (Low/Med/High iteration budgets: 250/500/900 FG). `long` enums with VALUES/LABELS used extensively for discrete modes.
- **Version evolution**: correctness (v00, hardcoded, buggy culls) → features (v01: curl, ellipsoid, palettes, un-hardcoded tone) → parameterization of remaining magic numbers (v02) → algorithmic performance engineering with documented rationale (v03) → simplification/respec beta (v04). The clearest learning-trajectory arc in the corpus.
- **Complexity tier**: 5 throughout — multi-pass simulation system with conductor controls; v03 is the peak.
- **Signature moves**: analytic-intersection swarms; FG/BG signal diff; bounding-sphere broad-phase in a fragment shader; curl-of-own-gradient feedback; pre-geometry UV crush; emoji-sectioned macro UI; deliberate >1 feedback overdrive with a clamp ceiling; `fastPow`.
- **Rough edges**: v00's asymmetric cull bug (fixed v01); v01's inlined ellipsoid inside-case duplication (fixed v02); 900-iteration const loop + runtime break carried through all versions (the flagged Metal-host idiom, handled but expensive); v04_beta drops features (Bayer fade, RGB split, mirror glitch) without renaming — "beta" as an unresolved fork; emoji in JSON LABELs is itself a host-compatibility gamble (works in VDMX; not guaranteed elsewhere).

### 9. Chaoser / grid-warp feedback family — `Chaoser_v01`, `Chaoser_v01_B`, `Chaoser_grid_v01/v02/v03/v03_smoothed/v04_smoothed`
- **Purpose & visual identity**: Filters (v04_smoothed becomes a self-seeding generator). Chaotic per-cell grid UV warp feeding a persistent buffer: shattered-mosaic feedback with grain, edge lift, bright-pass punch-through, and progressive inversion. Credited inspiration: "Karl Gerstner's ideas" (grid_v01/v02 headers) — a rare explicit design-theory reference (Gerstner = Swiss systematic-design pioneer).
- **Architecture**: All 2 passes: Pass0 → persistent `buffer`/`accum` (all the work), Pass1 = passthrough (`grid_v01/v02`), Sobel+unsharp enhancement (`Chaoser_v01` only), or **periodic auto-clear** `if (mod(time,2.0) < 1.0) gl_FragColor = vec4(0.0);` (v01_B, v03, v03_smoothed — the buffer wipes for 1 of every 2 seconds; a blunt anti-runaway/anti-burn-in device).
- **Techniques**:
  - Shared macro kit: `#define luma(rgba) dot(rgba, vec4(0.2126,0.7152,0.0722,0.))`, `degamma/gamma` = `pow(rgba, GAMMA)/pow(rgba, 1/GAMMA)` with GAMMA 2.0 — feedback accumulates in linearized space, output re-gammas; a color-correctness habit maintained across the whole family.
  - `applyChaoticGrid`: `cellPos = floor(uv/cellSize); localUV = fract(uv/cellSize);` per-cell random offset+scale `uv*randScale(0.75+rand*0.5) + randOffset*chaos*1.5`, re-`fract()`ed — the base mosaic warp.
  - **Grain**: `x = (u+4)(v+4)(time*scale*10); g = mod((mod(x,7)+1)*(mod(x,49)+1), 0.1) - 0.05` — multiplicative-mod noise, copy-pasted verbatim across every family member.
  - **Edge lift inside the loop**: `edgeLuma = abs(luma(src at uv+e) - luma(src at uv-e)); bufferColor.rgb += edgeLuma * zoomAmount * 10.0` — source edges continuously re-injected into the accumulator, so trails have glowing outlines.
  - **Bright-pass gate**: `if (originalLuma > 1.0-passThrough && originalLuma > luma(bufferColor)) _feedback = 0.0;` — hot highlights bypass the feedback and print instantly.
  - Per-pixel dithered feedback amount: `if (rand(uv) > 0.5) _feedback = 1.0;` — half the pixels always fully feed back (spatial dithering of the feedback constant itself).
  - v03/v03_smoothed add the macro-staging system: `getCurrentAspectRatio()` (per-cell phase cycles among three aspect ratios rA/rB/rC via `floor(mod(ph,3.0))` + `fract` crossfade); `applyPerCellTransform2()` (aspect scaling about cell center + **organic offsets** — multi-sine per-cell drift fields blended against the random offset by `organic²` weight, so chaos can be smooth-drifting instead of static-random); `gridComplexityPattern()` — a **phi-hashed spatial complexity field**: `cO = fract(cC.x*phi + cC.y*phi*phi)` gates a smoothstep between `floor(base)` and `floor(base)+1` grid levels with center-distance falloff — the *number of grid subdivisions itself* varies smoothly across the frame; `macroSplit` — orientation-biased two-rectangle frame cut at a time-jittering `cut` (clamped 0.25–0.75), blended 20% — BSP-like macro composition over the cell field. The `effectAmount` staging block maps every parameter through `transitionX = mix(neutral, X, effectAmount)` (the neutral-collapse convention again).
  - v04_smoothed (generator): input removed; seeds feedback from neutral gray + grain with a **has-accum test** `hasAccum = step(1e-4, dot(buf.rgb, vec3(1/3)))` to self-boot; adds `macroIterations` (up to 10 compounding `perCell()` applications per pixel, each with index-perturbed seed/chaos); `wrapClamp` blends `fract(p)` vs `clamp(p,0,1)` cell-edge behavior; `cellScaleJitter`; and — the standout correctness fix — **contrast moved entirely to the display pass**, masked by `rectMask = sstep(0.35,0.65, gridComplexityPattern(...))` recomputed at display time, so cosmetic contrast never contaminates the persistent accumulator (earlier versions baked `adjustContrast` into the loop, compounding per frame).
- **Control/UI design**: early files ~9 inputs; v03 ~17 (adds `ratioVariety`, `gridDistributor` bipolar axis-bias −1..1, `timeScale`, `structureJitter`, `orderChaosBalance`); v04_smoothed ~28 with implicit blank-line grouping in the JSON (staging / axes / cuts / aspects / organic / macro / feedback / grain) but **no emoji/number labels** — a parallel, less-formalized convention track vs ChaosCubes. Credit "Arson Rivvers + ShaderSmith" on v04.
- **Version evolution**: `Chaoser_v01` (zoom-warp feedback + one-off Sobel/unsharp display pass, dropped thereafter) → `v01_B` (chaotic grid warp + 2s auto-clear) → `grid_v01` (cleanup) → `grid_v02` (micro-opt: luma computed only when needed) → `grid_v03` (macro staging, aspect cycling, organic drift, effectAmount staging) → `grid_v03_smoothed` (drops the `sstep` alias BUT — critically — grid_v03_smoothed is the variant that names a local variable `smooth`, colliding with the GLSL reserved word; `grid_v03` uses `orgW` and keeps the `sstep()` wrapper whose comment says "alias to avoid 'SMOOTH' tokenization issues on some drivers" — together these two files document the author *discovering and then working around* a reserved-word/tokenizer host quirk) → `grid_v04_smoothed` (generator conversion, macro iteration, wrap/clamp blend, display-pass-isolated contrast).
- **Complexity tier**: 2 (early) → 4 (v03/v04: compound multi-stage procedural grid with spatial complexity fields, still architecturally one accumulation pass).
- **Signature moves**: phi-hashed spatially-varying grid density; contrast isolated to display pass (sim-state purity); bright-pass punch-through gate; per-pixel dithered feedback constant; the 2-second auto-clear as a crude but effective feedback-runaway safety.
- **Rough edges**: The `smooth` reserved-word collision (real host-quirk scar, explicitly commented); `applyPerCellTransform` kept-but-unused in v03+ ("original per-cell (kept but unused)" — dead code retained as reference); duplicated whole files for tiny diffs (v03 vs v03_smoothed); `grainAmount` MIN 6.0 in filter versions (can't turn grain off) fixed to MIN 0.0 only in v04; several defaults in `Chaoser_grid_v03` (0.437, 0.915, 0.612, 0.989) are live-performance captures outside sensible ranges (gridComplexity DEFAULT 0.437 with MIN 1.0 — an invalid default a strict host may clamp or reject).

### 10. `AR_ChaosLattice_v01_dataloss_v01.fs` — Truchet lattice × chaotic maps VJ instrument
- **Purpose & visual identity**: Generator (video blendable via `masterMix`). Multi-scale Truchet/glyph lattice (slash/cross/arc/triangle), up to 4 layers boolean-composited, per-cell rotation driven by real iterated chaotic 2D maps, all BPM-locked, with audio-FFT routing, glitch bombs, geometry-level CA, scanlines, bit-crush, kaleidoscope. Self-described: "No gradients, no softness, only hard edges… maximum visual assault."
- **Architecture**: 2 passes: Pass0 → `chaosBuffer` (PERSISTENT, FLOAT) holding per-cell chaos-map orbit state; Pass1 full display composite.
- **Techniques**:
  - **Real chaotic dynamical systems**: selectable Ikeda (`th = 0.4 - 6.0/(1.0+x²+y²)` rotation map), Hénon (`1 - a·x² + y, b·x`), Tinkerbell (`x²−y²+ax+by, 2xy+2x+0.5y`), Lozi (`1 − a|x| + y, b·x`) — iterated 1–10 steps per frame per cell, state persisted in the buffer.
  - **`chaosBound(v) = v/(1.0+abs(v))`** — rational soft-saturation replacing tanh, with the batch's best host-quirk comment: "tanh was added in GLSL ES 3.00; ISF Editor's compiler is 1.00. The rational form is also ~10x cheaper." (A strict improvement over the exp-based tanh polyfill in the conversion-test family — visible cross-file learning.)
  - **Cell-quantized orbit coherence**: `cellUV = (floor(uv*chaosCellRes)+0.5)/chaosCellRes` for buffer read — neighboring pixels within a cell share one orbit; the inline comment explains that without this "every pixel is an independent orbit and the result is incoherent noise."
  - Seeding: `FRAMEINDEX < 2 || reset` → `pos = centeredCellUV + hash*0.5` — per-cell divergent initial conditions ("visible chaos within ~10 iterations").
  - **BPM timing system**: `beatsPerSec() = bpm/60`, strobe/mutation/bomb cycle lengths in beats; `bombBeatJustFired()` = `step(0.5, floor(TIME/secs) − floor((TIME−TIMEDELTA)/secs))` — frame-rate-independent beat-edge detection (uses TIMEDELTA; strictly better than `mod(TIME, x) < eps`).
  - Beat-quantized parameter mutation: `mutatedParams()` hashes the mutation-cycle *index* to jump mapParamA/B discretely each cycle — attractor-hopping on musical boundaries.
  - **Hard-edged tile primitives** all via `step()`: `tileSlash = 1−step(lw, abs(c.x−c.y))`, cross, ring (`abs(length(c)−0.35)`), and a proper equilateral-triangle SDF (`tileTri`, k=√3 closest-edge branch) still hard-thresholded — SDF math used, softness rejected on principle.
  - Per-cell rotation = hash base + chaos-state offset (`(chaos.x+chaos.y)*chaosInfluence*π`) + time (audio-bass-scaled), then **rotation quantization** (continuous/90°/45°/180° snapping).
  - **Boolean layer compositing**: XOR = `mod(step(t,a)+step(t,b), 2.0)`, AND = `step(t,min(a,b))`, OR = `step(t,max)`, MIX = average, MAX-DIFF = `abs(a−b)`; layers scale by `layerScaleMul` (default φ = 1.618).
  - **Geometry-level chromatic aberration**: re-evaluates the entire `compositeLayers()` at 3 offset UVs (one per channel); the comment explicitly states hard-edge content REQUIRES this because post-shift on colored output "only displaces colors, not the geometry beneath."
  - Audio routing: `IMG_NORM_PIXEL(audioFFT, vec2(band, 0.5)).r * audioGain` at three user-positioned bands; each band mapped to a *named* target — bass→rotation speed, mid→line width pulse, high→hue jolt; bombs additionally require bass impulse × beat edge.
  - **Glitch bombs**: up to 8 hash-placed rectangles per beat index, fire only when `audioBass()*bombBeatJustFired() ≥ 0.05`, with 4 behaviors (invert / `col.gbr` swizzle / solid white / hash-scrambled hue).
  - Strobe engine: three phase-divided pulses (1x/0.5x/0.25x of strobe phase) driving brightness/invert/hue-rotate independently or all together.
  - Kaleidoscope enum: H/V/quad mirrors + 4/6/8/12-fold `atan`-mod folds; view zoom/pan/rotation transform; `hash31` (Dave Hoskins-style sinless hash) for grain; `hsv2rgb` with smoothstepped rgb ramp.
  - 7-mode `debugMode` enum (chaos position/magnitude, individual layers, bomb mask, audio bands) — built-in instrumentation.
- **Control/UI design**: ~50 inputs under the batch's most disciplined labeling: every LABEL prefixed `"0.Tempo |"`, `"1.Lattice |"`, `"2.Chaos |"`, `"3.Composite |"`, `"4.Color |"`, `"5.Audio |"`, `"6.Bomb |"`, `"7.Glitch |"`, `"V.View |"`, `"M.Macro |"`, `"Z.Debug |"` (M and Z letters sort macro near top and debug last). Four **macro/conductor knobs**: `chaosMacro` (scales iteration count AND mutation drift), `assaultMacro` (output gain), `glitchMacro` (scales CA, bit-crush blend, scanlines, grain AND bomb mask together), `masterMix` (generator↔video). The canonical one-knob-drives-many implementation in this corpus.
- **Version evolution**: One file, but the doubled `v01_dataloss_v01` name and "dataloss" tag suggest a recovery/fork event; internally it consolidates conventions from both ChaosCubes (macros, event reset, quality thinking) and the Kaleido family (palette/hash kit), so it likely postdates both.
- **Complexity tier**: 5 — only 2 passes, but the most conceptually advanced file in the batch.
- **Signature moves**: real chaos maps + persisted orbits; rational `chaosBound`; TIMEDELTA-based beat-edge detection; boolean compositing; geometry-level CA; audio-band→named-parameter routing; numbered-section label taxonomy; built-in debug views.
- **Rough edges**: "dataloss" filename scar; debugMode shipped in the default control surface; `frameStutter` uses `floor(TIME*30.0)` (frame-rate-coupled at 30fps assumption) inconsistently with the otherwise rate-independent timing discipline.

### 11. `AR_ChaoticFlowers_v01.fs`
- **Purpose & visual identity**: Filter. Self-referential feedback flow: the buffer's own channel differences act as a displacement field, HSV-modulated each frame, luminance-keyed against live input — swirling petal/bloom trails.
- **Architecture**: 2 passes: Pass0 → persistent `BufferA`, Pass1 passthrough.
- **Techniques**:
  - **Channel-difference pseudo-flow**: `disp = vec2(fb.y−fb.x, fb.x−fb.z) * vec2(dispWeightX, dispWeightY)`, then re-sample the buffer at `uv + disp * spin * dispGain / res` — G−R and R−B differences read as a vector field; color boundaries encode rotation, so swirls self-organize. Far cheaper than AR_11111's true optical flow for a related trail aesthetic.
  - Asymmetric spin: `spinX = spinOffset + movementX*spinGainX` (and Y) — elliptical rather than circular swirl.
  - **HSV-domain feedback modulation**: full `rgb2hsv` → add hueShift/satShift·saturationMod/valShift·brightnessMod → `hsv2rgb` every frame — hue drift compounds through the loop for psychedelic cycling.
  - Sinless hash noise (Dave Hoskins `NOISEVEC vec3(443.8975,397.2973,491.1871)` fract-dot chain) as grain, scaled by `0.8 + movementAvg` (grain tracks flow energy).
  - Two-parameter luminance key: `t = smoothstep(amount−thresholdSoftness, amount+thresholdSoftness, lum); mixF = (1−blendMix)*(1−t) + t` — position + softness + floor, more controllable than a hard threshold.
- **Control/UI design**: 19 inputs with LABEL fields; defaults are many-decimal live-tweaked captures (0.352, 0.771, 0.994, 0.827…) — knob-settings frozen back into the file, a workflow signature. Several floats declared without MIN/MAX (host defaults to 0–1) — loose header hygiene.
- **Version evolution**: single version.
- **Complexity tier**: 3.
- **Signature moves**: channel-difference flow field; HSV-loop hue drift; performance-capture defaults.
- **Rough edges**: `decay` DEFAULT 1.0 (no decay) plus additive noise means the buffer brightens unboundedly until the input key rescues it; missing MIN/MAX on most inputs.

### 12. Chromatic Aberration family — `AR_Chroma_Aber_v01`, `AR_Chroma_Spectrala_v01`, `AR_Chroma_Spectrala_v02`
- **Purpose & visual identity**: Filters; a three-step maturation from basic 3-tap CA to a physically-motivated spectral lens-dispersion simulator. Credits mark the arc: "Custom High-End CA" → "Spectral CA (evolved) — ArsonRivvers / Conner" → "(evolved, full)".
- **Architecture**: All single-pass, pure per-pixel color math.
- **Techniques**:
  - v01 baseline: R/B sampled at `uv ∓ offset`, `offset = mix(dirVector(uAngle), radialVector, uRadialMode) * uIntensity * falloff`, `falloff = pow(dot(cd,cd), uEdgeFalloff)`; movable `uCenter` point2D; header comment "Pre-calculate coordinates to avoid macro parser errors" — a documented ISF host quirk (IMG_NORM_PIXEL is a macro; inline arithmetic in its argument can break the parser).
  - Spectrala v01: replaces 3 taps with **9-sample spectral integration** — wavelength t ∈ [0,1] violet→red, `spectralWeight(t,width)` = three Gaussian lobes at t = 0.78/0.50/0.22 feeding R/G/B accumulators, normalized by per-channel weight sums. Adds: `uDispersionCurve` (`disp = sign(d)*pow(abs(d), curve)` — nonlinear mid-band spread), `uAxialAmount` (per-wavelength rescale about center: `sampleCoord = uCenter + (uv−uCenter)*(1+disp*uAxial) + offset` — longitudinal CA), `uTangentialTwist` (rotate shiftDir by `twist = uTwist*dist*π`), `uFringeBias` (asymmetric `(1±uFringeBias)` per dispersion sign — warm/cool fringe skew), and the **corner-normalized falloff**: `normDistSq = distSq / dot(furthestCorner, furthestCorner)` — inline comment explains that unnormalized `pow(distSq,p)` silently attenuates amplitude as p rises (distSq maxes ~0.5), so normalization makes uEdgeFalloff "a pure shape control, decoupled from amplitude." Plus **delta-isolated saturation**: `caDelta = caColor − originalColor; caDelta = mix(vec3(deltaLuma), caDelta, uSaturationBoost); out = original + caDelta` — provable no-op convergence at zero intensity, clean alpha from the unshifted reference sample.
  - Spectrala v02 adds: **spectral quantization** (`uSpectralBands` ≥ 2 snaps t to N centered bins — hard prism bands); **anamorphic falloff** (`anaDist = vec2(cd.x/ratio, cd.y)` applied to both distance and corner normalization — falloff ellipse squeezes, shift direction stays circular); **highlight-gated CA** (`hl = smoothstep(uHighlightKnee, 1.0, luma); falloff = baseFalloff * mix(1.0, hl, uHighlightBias)` — fringing prefers blown highlights like real lenses); **hue rotation of the delta only** via full RGB↔YIQ matrix pair (comment: linear, "so safe on signed color deltas"; enables magenta/green lens-signature fringes decoupled from the physical spectrum; skipped when |angle| < 0.01 for speed); **per-sample temporal jitter** (`uTemporalJitter`, independent hash per wavelength sample per frame — chromatic *shimmer*, not frame shake; sinless `hash21`, and `tSafe = mod(TIME, 1024.0)` for float-precision stability in long sessions); **sagittal shift** (`tangentDir = vec2(−shiftDir.y, shiftDir.x)` weighted by `uTangentialShift`); **vignette coupling** (`finalColor *= mix(1.0, 1.0−baseFalloff, uVignette)` — deliberately reuses the pre-highlight-bias falloff so vignette doesn't track luma).
- **Control/UI design**: 6 → 12 → 21 inputs; consistent `u`-prefix Hungarian-ish naming (unique in the corpus); every added parameter carries an inline physical-optics rationale comment — the best-documented family in the batch.
- **Version evolution**: textbook limitation→physically-motivated-parameter→documented-why loop; each rev also fixes a real bug class (falloff amplitude coupling; alpha contamination; TIME precision).
- **Complexity tier**: 2 (v01) → 3 (Spectrala v01/v02) architecturally; v02 packs near-tier-4 conceptual rigor in one pass.
- **Signature moves**: Gaussian spectral integration; corner-normalized shape/amplitude decoupling; delta-isolated grading (guaranteed no-op at zero); highlight-gated fringing; per-wavelength jitter; `mod(TIME,1024)` precision hygiene.
- **Rough edges**: essentially none — the most polished family; v01's macro-parser-workaround comment is itself valuable negative knowledge.

### 13. Archive — fractal kaleidoscope tunnels: `KaleidoDistortionVision_v01`, `KaleidoMegaDistortionVision_v02`, `KaleidoTunnelVision_v01`
- **Purpose & visual identity**: Filters ("Modified by ChatGPT" credits). A Mandelbox-style 3D IFS fold applied to the ray direction, whose folded vector then distorts the video-lookup UV via `reflect()` — video textured onto a fractal tunnel, without any actual raymarched surface.
- **Architecture**: single-pass, no buffers.
- **Techniques**:
  - Shared core `fractalKaleidoscope()`: iterate {`p = abs(p)` (octant fold), `p.xy *= rotate(π/symmetry)`, `p.xz *= rotate(π/symmetry)`, small time-wobble `rotate3D(p, 0.1sin(t/2), 0.1cos(t/2))`, `p = 2.0*p − 1.0` (Mandelbox scale-recenter)} — a genuine IFS fold used purely as a **procedural vector field**: `reflectDir = reflect(rd, foldedP)`; `distortedUV = reflectDir.xy * 0.5 * distortionStrength + 0.5; fract()` — 3D-fractal flavor at 2D-filter cost.
  - v01: `effectStrength` wet/dry applied via `mix()` at *every fold sub-step* (`p = mix(p, abs(p), effectStrength)` etc.) plus final lighting blend — total-crossfade architecture (the effectAmount convention applied to a fractal).
  - MegaDistortion v02: always-on fold, but accumulates `normal += normalize(p)` across iterations (smoothed direction vs last-iterate only); adds a fake 5-tap expanding-radius `ambientOcclusion()` heuristic (raymarch-AO idiom without an SDF — stylistic darkening); post-fold sine wave warp on the UV; `reflectivity` lit/unlit blend.
  - TunnelVision v01: simplest, but solves the knob-feel problem — **continuous iteration depth** via evaluating the fold at both `floor(complexity)` and `ceil(complexity)` iteration counts and blending by `fract(complexity)`: a float slider smoothly morphs between discrete fractal depths instead of popping. Uses `const int MAX_ITERATIONS = 20` + runtime break (the safe idiom).
- **Control/UI design**: modest 6–10 inputs (`rotationSpeed`, `zoomSpeed`, `symmetry`, `complexity`, `distortionStrength/Mix`, + `waveStrength`/`reflectivity` in Mega). Pre-convention era: no macros, no sections.
- **Version evolution**: lateral experimentation rather than monotone improvement — v01 (clean global crossfade) → v02 "Mega" (more layers, loses the crossfade) → TunnelVision (leaner, gains smooth-depth). Archived as superseded; their fold-as-vector-field idea and the floor/ceil depth blend survived conceptually into the main-directory Kaleido work.
- **Complexity tier**: 3 each.
- **Signature moves**: IFS fold as procedural UV-distortion field (no marching); floor/ceil iteration blending for continuous-feeling integer depth.
- **Rough edges**: v01's per-sub-step `mix()` wet/dry computes the full fold then discards most of it — wasteful vs one final blend; `int(iterations)` loop bounds in v01/v02 (non-const loop condition `i < int(iterations)`) is exactly the pattern stricter Metal-backend compilers reject — TunnelVision's MAX_ITERATIONS+break fix is likely *why* it exists; the utility trio (`rotate`, `rotate3D`, fold) is copy-pasted across all three.

### 14. Archive — `TorusWarp_v01.fs`
- **Purpose & visual identity**: Filter. Figure-eight-knot parametric wave + torus UV warp (torus amount driven by video's red channel as pseudo-depth), then a second pass uses the depth gradient for "self-intersection" distortion.
- **Architecture**: 2 passes: Pass0 → `feedbackBuffer`, Pass1 reads it, computes gradient, re-samples offset, outputs.
- **Techniques**:
  - **Depth-in-alpha side channel**: Pass0 packs `finalColor.a = clamp(totalDepth, 0,1)` — auxiliary scalar data smuggled through a pass boundary in the alpha of an opaque image.
  - Parametric knot as a warp: `x = sin(u)(1+0.5sin(3v)); y = cos(u)(...); z = amp*sin(freq*u + TIME)`, perspective-ish `scale = 1/(1+z)`, then `knotOffset = knotUV − uv` — a closed-form curve used as a displacement function, never rendered.
  - Video-self-coupling: `torusOffset *= (inputColor.r*2−1) * warpIntensity * torusIntensity` — the image's own red channel signs and scales its torus warp (same self-coupling idea as Chaos_PatternDepthMap).
  - Pass1: manual 4-tap depth gradient `(dR−dL, dD−dU) * depthGradientScale` → `feedbackOffset` → resample — depth ridges pull neighboring pixels inward.
- **Control/UI design**: 9 plain floats, no macro.
- **Version evolution**: single, archived.
- **Complexity tier**: 3.
- **Signature moves**: alpha-as-depth-sidecar between passes.
- **Rough edges**: **Spec bug**: header declares a non-standard top-level `"PERSISTENT_BUFFERS": ["feedbackBuffer"]` while the PASSES entry itself has no `"PERSISTENT": true` — by the ISF spec the buffer is not persistent, so the promised multi-frame "self-intersection feedback" almost certainly never accumulated (same-frame pass-to-pass only). A plausible reason it was archived; and useful negative knowledge — the author later always used per-pass `"PERSISTENT"/"persistent": true` correctly.

---

## Batch synthesis

**Top 3 most sophisticated files:**
1. **`AR_ChaosCubes_v03.fs`** ("v4.2 Performance Evolution", 879 lines) — analytic box/ellipsoid-intersection swarm with FG/BG depth-diff signal generation, bounding-sphere broad-phase culling, size-skip and early-exit optimizations, curl-of-gradient feedback flow, pre-geometry UV quantization, Bayer dithering, and a fully emoji-sectioned ~45-control macro UI, with the optimization rationale documented in a header comment block. The most performance-engineered file, and the endpoint of the clearest correctness→features→parameterization→optimization→simplification arc (v00→v04_beta).
2. **`AR_ChaosLattice_v01_dataloss_v01.fs`** — the only file running genuine chaotic dynamical systems (Ikeda/Hénon/Tinkerbell/Lozi) with persisted per-cell orbits, BPM-locked frame-rate-independent beat-edge triggers (TIMEDELTA-based), boolean-logic layer compositing (XOR/AND/OR/MAX-DIFF), geometry-level (re-evaluated) chromatic aberration for hard-edge content, audio-band→named-parameter routing, four macro conductors, and numbered-section labels. The most conceptually novel file.
3. **`AR_Chroma_Spectrala_v02.fs`** — 9-sample Gaussian spectral-integration CA with lateral/axial/tangential/sagittal dispersion decomposition, corner-normalized shape/amplitude-decoupled falloff (a documented bug fix), highlight-gated fringing, delta-isolated saturation and YIQ hue rotation (provable no-op at zero), per-wavelength temporal jitter, and `mod(TIME,1024)` precision hygiene. The most physically rigorous and best-documented file.

**Recurring patterns / style fingerprints:**
- **Macro "neutral-collapse" dry/wet** (`effectAmount`/`effectStrength`/macro knobs that `mix()` every internal parameter back to a neutral default at 0) — appears independently in AR_3D_Displacement, Chaoser grid v03/v04, Archive KaleidoDistortionVision, and matured into ChaosLattice's 4 macro conductors.
- **Cell-hash grid decomposition** (`floor`/`fract` + `rand(cellPos*seed)` per-cell transform) — the most-repeated low-level utility (Chaoser family, ChaosLattice tiles, digital rain).
- **The multiplicative-mod grain function** `mod((mod(x,7)+1)*(mod(x,49)+1), 0.1)−0.05` copy-pasted verbatim across the entire Chaoser family.
- **Init/reset guards** `FRAMEINDEX < 1/2 || reset` wherever persistent buffers exist; maturation from bool-Reset (BrokenPixelSorter) to proper `"TYPE":"event"` 🔴 PANIC RESET (ChaosCubes/ChaosLattice).
- **Const-bound loop + runtime break** (`for(i<CONST) if(i>=int(param)) break;`) used correctly and pervasively (Kaleido family, ChaosCubes 900-loop, ChaosLattice MAX_ITER/MAX_BOMBS) — the Metal-host hazard fully internalized; the two Archive tunnels that instead use non-const `i < int(iterations)` bounds are precisely the archived ones.
- **File-per-experiment workflow**: near-duplicate files for small diffs (Chaoser v01/v01_B, grid v03/v03_smoothed, 5 ChaosCubes revisions, 3 archive tunnels sharing verbatim utilities) — sprawl that a parameterized generator/skill should consolidate.
- **Control-surface information architecture matures over time**: none (ASCII, early Kaleido) → LABEL fields → emoji section prefixes (ChaosCubes) → numbered "N.Section | Name" taxonomy + sorted M./Z. macro/debug blocks (ChaosLattice).
- **IQ cosine palette exposed as 4 color inputs** + ripple triple + brightnessBase/Exponent — a reusable personal generator template across 11 Kaleido files.
- **Performance-capture defaults**: many-decimal DEFAULTs (0.352, 0.915, 0.989…) frozen from live sessions, occasionally out-of-range (Chaoser grid v03 gridComplexity 0.437 with MIN 1.0).

**Beyond-standard-ShaderToy techniques found here:**
- Real discrete chaotic maps (Ikeda/Hénon/Tinkerbell/Lozi) with cell-coherent persisted orbits — not noise-faked chaos.
- BPM-derived, TIMEDELTA-edge-detected musical timing (rare; hobbyist shaders animate on wall clock).
- 9-sample continuous spectral CA with Gaussian sensitivity lobes vs the universal 3-tap shift.
- Analytic-intersection primitive swarms with bounding-sphere broad-phase culling — game-engine culling discipline inside a fragment shader.
- Geometry-level chromatic aberration (re-evaluating the scene per channel) with an explicit rationale for why hard-edge content requires it.
- Corner-normalized falloff and delta-isolated grading guaranteeing exact no-op convergence — uncommon numerical/UX rigor.
- Real gradient-based optical flow (AR_11111) at half-res in pure ISF passes.
- Host-quirk defenses as reusable idioms: rational `chaosBound` tanh substitute with cost/compat rationale; version-gated tanh polyfill; `smooth` reserved-word collision workaround; "pre-calculate coordinates to avoid macro parser errors" (IMG_NORM_PIXEL macro-argument hazard); and the TorusWarp `PERSISTENT_BUFFERS` spec-misuse as documented negative knowledge.
