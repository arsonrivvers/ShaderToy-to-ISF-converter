All 47 files are now covered (v16–v22 were verified line-by-line via exhaustive diffs against their fully-read predecessors, since they share ~95% identical bodies). Here is the full report.

# Batch 04 Analysis Report — AR_FractalVolume + the Game of Life Trilogy

## Coverage
- files_assigned: 47, files_read: 47, misses: none
- Method note: `AR_GameOfLife_filterA_v16.fs` through `v22.fs` (7 files, ~1300 lines each, ~95% byte-identical to fully-read v15/v14) were covered by reading full headers plus exhaustive `diff` against their fully-read predecessors; every changed line was inspected. All other 40 files read in full.

---

## Family 1: AR_FractalVolume (V01 — 1 file)

**Purpose & visual identity**: Generator. Volumetric ray-marched IFS fractal — a folded sin-warped domain rendered as glowing emission clouds with cosine-palette coloring, orbiting/breathing camera. Explicitly an "optimized" conversion (credit: "Converted and optimized for ISF").

**Architecture**: 3 passes. Pass 0 = half-res volumetric march (`halfResBuffer`, `WIDTH $WIDTH/2`); Pass 1 = full-res composite into `feedbackBuffer` (PERSISTENT) doing unsharp-mask upscale sharpening + temporal feedback blend (poor-man's TAA); Pass 2 = display. This half-res-sim → sharpen-upscale → persistent-temporal-blend pipeline is the batch's most complete performance architecture.

**Techniques**:
- **Emission-accumulation volumetric march**: no surface hit — each step adds `cmap * cheapTanh(2*emission_kernel/dt) * brightness`; the tanh-of-inverse-step-size kernel concentrates emission where the SDF is tight. Early-out on `t > max_ray_dist || dot(color,color) > accCapSq` (squared cap precomputed).
- **Domain-folding IFS inside the march**: per-step loop of `p.xy *= R; p = sin(p*warp_freq)*warp_intensity; p += sin(localT/ff*0.6 + p.xzy/ff)*(ff*sin_drive); p.zx *= R; p /= dot(p,p)+fold_decay;` — sphere-inversion (`p/dot(p,p)`) plus sin-fold with per-octave frequency `ff *= 2.0`, and a **temporal warp** where marching distance retards local time (`localT -= length(...)*temporal_warp`) so geometry morphs along the ray.
- **SDF combo**: `max(shell - length(p), abs(fbm(p) - threshold))` (hollow shell intersected with an fbm isosurface band), then smooth-union with a bounding sphere via the `length(vec2(d,k))` smooth-min form.
- **Cost discipline**: gradient noise with derivative math stripped, fbm octave ceiling as `exp2(maxOctaves)` compared against a doubling `f` (no `pow` in loop), `cheapTanh` rational approximation (`x*(27+x²)/(27+9x²)`), rotation matrix computed once, all loop invariants hoisted and commented as such.
- **Const-loop-bounds + runtime break** everywhere (`for i<128; if (i>=maxSteps) break;`, `for j<8; if (ff>=foldLimit) break;`) — the documented Metal-backend workaround.
- **Deterministic TAA jitter**: `dither_amount * fract(T*61.123 + dot(uv,uv) + 371*sin(...))` seeds the ray origin `t`, then Pass 1's `mix(sharpened, prev, feedback_mix)` integrates it.

**Control/UI design**: 35 inputs, snake_case names, exhaustive parameterization of every internal constant (step_scale, step_bias, emission_kernel, accumulation_cap, fold_decay...). Palette as `color_base` point2D + `color_z` float = a vec3 phase for the cosine palette, plus `palette_squeeze` (contrast via `cos(k*k)`), saturation via luma-mix. Camera has breathe amp/speed, orbit speed/wobble. No section labels yet (contrast with late GOL files).

**Version evolution**: single version; the DESCRIPTION itself is a changelog ("early ray termination, reduced FBM cost, precomputed loop bounds") — the author optimizes in-place and records it.

**Complexity tier**: 4 — multi-pass, mixed-resolution, temporal-feedback raymarcher with heavy micro-optimization; lacks only conductor/macro controls.

**Signature moves**: half-res sim + unsharp upscale + persistent temporal blend; `cheapTanh` emission kernel; time-retarded domain morph; sphere-inversion fold stack.

**Rough edges**: `noised()` keeps full 8-corner gradient interpolation with a name implying derivatives (vestige of IQ's `noised`); saturation applied per-march-step (wasteful); `hue_shift` added to all palette phase components equally.

---

## Family 2: AR_GameOfLife generator (v01–v13 + v11-alt, v11-alt2 — 16 files)

**Purpose & visual identity**: Generator. Conway-style cellular automaton driven by a center-seeded "primordial soup" and an expanding noisy injection ring, with decay trails, fluid/iterative feedback warps, and (from v06 on) rule presets and macro "conductor" controls. Visual identity: monochrome organic CA textures breathing radially from center (early versions neon-colored).

**Architecture**: constant across all: 2 passes — `golBuffer` PERSISTENT+FLOAT sim pass + display pass; `FRAMEINDEX == 0 || reset` init idiom. Channel packing evolves: v01–v03 state in RGB; v04 splits alpha=raw CA state / RGB=visual (dead cells' ghost trails no longer count as neighbors); v05+ settles on R=brightness, A=raw state.

**Techniques**:
- **GOL on a texture**: 3×3 `IMG_PIXEL` neighbor loop with `continue` on self; thresholded aliveness (`n.x > 0.5/0.6`) so decaying trails don't corrupt the sim — an explicit lesson ("keeps the physics strict but the visuals smooth", v02).
- **v01's golfed rule**: `sum = Σneighbors − 0.5*self; alive = (sum>2 && sum<4)` — replaced in v02 by explicit B3/S23; the author abandoned the golf for controllability.
- **Expanding ring injector**: `currentRadius = startRadius + mod(TIME*expandSpeed, maxDist)`; ring membership × per-pixel hash noise gate injects live cells — a *content conductor* that keeps the CA from dying. v04 adds a **kill ring** (rapid-decay annulus trailing the injection ring: `nextState = prev * 0.7` inside it), v05 adds `ringFill` (thin ring ↔ filled disc) — birth wave followed by death wave = perpetual motion.
- **Trail memory**: `nextState = max(binaryResult, prev * decay)` — the codebase's signature `max(prev*decay, current)` accumulation.
- **Iterative feedback warp** (v04 onward): `vec4 c = vec4(q.x,q.y,q.x,q.y)*sin(TIME*timeMod)*warpDepth; loop: c += T_fb(uv + c.xy*coordScale)*remap − 1.0 − distortion;` — a self-referential accumulator sampling the persistent buffer at coordinates displaced by its own running value; `length(c.xy)` reused as a brightness boost, `c.zy` as render-pass displacement. Classic VJ "video feedback in a loop" formalized as a reusable function with `long`-typed iteration count + const-bound/break.
- **Neon palette** (v02–v03): IQ cosine palette with the "cyberpunk vector" `d = (0.263,0.416,0.557)`, brightness-as-age lookup, `pow(brightness, 0.8)` punch curve.
- **Kaleidoscope render** (v03): polar `mod(angle, slice) − slice*0.5` wedge fold + `abs(fract(uv*0.5)*2−1)` mirror-tiling to hide seams.
- **Edge-mode plumbing** (v05+): wrap/clamp/mirror implemented per-axis in pixel space (`edgeAxis`), later split into independent X/Y modes (v11 file).
- **Rule presets + morphing** (v06+): `getRuleset(id)` returns `vec4(birthMin,birthMax,surviveMin,surviveMax)` for Life/HighLife/Seeds/Diamoeba/Morley/Day&Night; two presets `mix()`ed by a morph amount or sine oscillator — *interpolating discrete CA rules as floats then re-flooring* (`floor(rules.z + 0.5)`) is a distinctive hack.
- **Weighted neighborhoods** (v06+): radius 1–3, Gaussian `exp(-d²/2σ²)` weights normalized back to a 0–8 scale for threshold compatibility; **continuous CA mode** `smoothstep(smoothLo, smoothHi, densityNorm)` (proto-Lenia) and hybrid blend.
- **Activity guards** (v06+): 4-point buffer sample average → reseed when near-extinct, damp when saturated. Self-regulating homeostasis for unattended VJ use.
- **Macro/conductor system** (v11-alt onward, the family's crown): 6→12 macro sliders (`chaos, flow, scale, memory, pulse, density`, later `mutation, depth, tension, rhythm, morph, focus`) each mapped through 20–30 `derived*()` functions with perceptual curves (`chaos*chaos`, `mix(0.85, 0.995, memory)`), several macros co-modulating one internal (e.g. killZoneWidth ← scale×memory×tension×focus). Labels document polarity: `"Chaos (order ← → entropy)"`.
- **radialInwardWarp** (v11-alt2): replaces the chaotic accumulator warp with a weighted multi-tap march toward center (`w = 1−t*0.5`) returning `vec4(intensity, dist, avgSample, pulseMod)` — deliberately symmetric feedback; multi-scale echo layers (`echoOffset = inwardOffset/(i+1)`) fake depth.

**Control/UI design**: evolves from 5 inputs (v01) → 28 explicit engineering knobs (v09/v10) → deliberate collapse to 6–13 macro knobs + mode dropdowns (v11-alt→v13). `event` reset everywhere; `long` for enums with meanings packed into LABEL text ("0=Custom,1=Life,…"). v10 file is the ISF-Editor-normalized twin of v09 (alphabetized JSON, `"ISFVSN": "2"`, stray `tmpInputName` input left behind by the editor).

**Version evolution / learning trajectory**: v01–v02 credit "Gemini" (LLM-drafted seed), v03 first "AR" credit — the author took over. Arc: (1) get the sim right (thresholding trails out of physics), (2) add feedback-warp eye candy, (3) expose *everything* (v05 "Fully Parameterized"), (4) discover full exposure is unplayable live and invert into macro conductors (v06-ALT "Minimal Intelligent Controls"), (5) deepen the macro vocabulary (v07 10 knobs, v08 12 knobs + focus/direct-morph). File-version vs internal-version skew is chronic (files v06–v08 contain "v04/v05" descriptions; v09/v10 both say v05; v11 says v06) — file numbers are save-generations, not release numbers.

**Complexity tier**: v01–v05: 2–3; v06–v13: 4 (multi-mode simulation with rule morphing, weighted kernels, homeostatic guards, macro conductor layer). 

**Signature moves**: injection-ring + kill-ring conductor; `max(prev*decay, current)` memory; iterative feedback-warp accumulator doubling as brightness meter; rule-range interpolation; macro→derived-parameter architecture with polarity-documented labels.

**Rough edges**: v04 `feedbackTint`/`colorShift` RGBA-channel-swizzle (`fract(c/3+shift).argb`) abandoned immediately after; `hash2` declared "for potential future use" and never used; `guardFrames` input in v11 file never referenced in code; `warpFreq` overloaded to mean different things per version; the v09/v10 duplicate pair; kaleidoscope (v03) dropped and never returns to the generator line (resurfaces in filterA warp modes).

---

## Family 3: AR_GameOfLife_filter (v01–v09 — 9 files)

**Purpose & visual identity**: Filter. The v08-generator macro engine converted to process live video: input luma seeds/injects/modulates the CA, output is the CA "eating" the video with radial/flow-warped trails; optional colorize re-tints with source color.

**Architecture**: 2 passes (golBuffer PERSISTENT+FLOAT + render). v03 file experiments with color-in-buffer (RGB=processed color, A=state); v04+ retreats to R=full state / **A=GOL-only state** — a dual-channel design so the render pass can `mix(full, golOnly, hideInput)` and show the automaton without the source.

**Techniques**:
- **Input conditioning**: Rec.601 luma → `mix(luma, 1−luma, invert)` → `smoothstep(threshold±0.1)` × strength. Threshold-with-soft-knee is the universal input gate.
- **Four input topologies** (v01–v03): Seed (init only), Inject (continuous OR), Modulate (input lowers birth threshold & boosts warp), Replace (input = state). Superseded in v04 by continuous *dials*: `golAmount` (passthrough↔full GOL), `golOverride` (input wins↔GOL wins, piecewise blend logic), `birthChance`, `injectionNoise` (clean↔noisy injection with a clean-injection floor `max(injection, inputVal*(1−2*noise))`).
- **13 flow-direction fields** (v05+, `flowMode`): Radial, Sobel edge-following (flow along `(-grad.y, grad.x)`), Horiz/Vert sweeps, Spiral, **curl noise** (hash-based divergence-free field), **golden spiral** (`log(r)*PHI` tangent), diamond-grid alternating cells, 4-vortex array with distance-weighted tangents, **magnetic dipole** field lines (`Br=2cosθ/r³, Bθ=sinθ/r³`), **phyllotaxis** (Fermat spiral at golden angle 2.39996), Lissajous 3:2 tangents, 4-source wave interference (flow along wavefronts via perpendicular-of-gradient). Each has pixel-space and normalized-space variants for sim vs render use.
- **Bitmask rule system** (v06+): rules as `vec2(birthMask, surviveMask)` with bit N = "rule fires at N neighbors", tested by `mod(floor(mask / 2^n), 2) > 0.5` — GLSL-ES-safe bit extraction without integer ops; `countMatchingRules` linearly interpolates bits for fractional (weighted-kernel) neighbor counts. Exact preset encodings documented in comments (Life = (8,12), Diamoeba = (488,480)...).
- **Probabilistic rule morphing**: per-pixel hash chooses ruleset A or B with morph as probability — *spatially stochastic rule mixing* instead of numeric interpolation. v06 hashed with `floor(TIME*10)` → visible sparkle; **v07 "Flicker-Free" removes TIME from the hash entirely** and states the principle in comments: "No TIME in hash = same pixel always gets same random value = no flickering." Same fix applied to birthChance rolls and activity reseeds; injection noise keeps TIME only when the user asks for it (`injectionNoise > 0.01`).
- **Colorize pipeline** (v02→v04): first in-sim (color decays in the buffer), then moved to render pass only (`tintedColor = processedColor * finalBrightness`, gated by `colorize*(1−hideInput)`).

**Control/UI design**: ~30 inputs; the macro sliders inherited from generator v08 (chaos/flow/scale/memory/pulse/mutation/depth/tension/rhythm) minus density (input supplies density). v08 file introduces `VALUES`/`LABELS` arrays for real dropdown menus — a host-UI upgrade discovered mid-family. `flowIntensity` added as a separate gain (v08).

**Version evolution**: v01→v03 explore what "input-driven" means (modes, color); v04 (internal "v03 Clean (Fixed)") is a rethink — continuous dials replace modes, dual-channel full/GOL-only buffer; v05 adds the 13-flow-field library; v06 (internal v04) swaps range rules for exact bitmask presets; v07 (internal v05) is the temporal-stability correctness pass; v08 adds dropdown metadata + flowIntensity; v09 fixes `customSurvive` DEFAULT from 23 (out-of-range leftover of "S23" notation) to 2 — a caught header typo.

**Complexity tier**: 4 — video-reactive CA with rule algebra, flow-field library, and stability engineering; single sim buffer keeps it below tier 5.

**Signature moves**: bitmask CA rules with GLSL-ES bit extraction; per-pixel stochastic rule morphing; TIME-free "stable RNG" doctrine; dual-channel full/GOL-only output with `hideInput`; flow-direction field library.

**Rough edges**: `sampleInputNorm` defined and unused (v01–v02); huge copy-paste triplication of the rule block across caMode branches; v06's flickering morph shipped then patched; customSurvive=23 bug; `derivedInjectionBias` computed in files where it's unused.

---

## Family 4: AR_GameOfLife_filterA (v01–v22 — 22 files)

**Purpose & visual identity**: Filter. The "A" line restarts the filter from the *fully-parameterized* (non-macro) branch and grows into the batch's flagship: an input-driven CA with **inertial per-pixel physics** (velocity field, gravity, edge forces, optical flow) and a **31-mode fractal warp pack**, plus a performer-grade time-control system.

**Architecture**: v01–v11: 2 passes. v12+ (internal v06): **3 passes** — a `1×1` PERSISTENT `timeBuffer` (R=accumulated sim time, G=prev TIME, B=exponentially-smoothed speed, A=init flag) → golBuffer sim → render. Buffer packing from v02 on: **R=previous-frame input luma, G/B=velocity vector (px/frame), A=CA state** — four unrelated state variables in one RGBA texel.

**Techniques** (beyond those inherited from the filter family):
- **Inertial edge physics** (v02): per-pixel velocity integrated with explicit Euler (`vel *= 1−drag; vel += force; clampMaxSpeed`), forces = directional gravity (`gravityAngle*TAU`), edge-tangent flow (Sobel normal rotated 90°, sign fixed by a *spatially-stable random* `tSign` so it never flips over time), edge attract/repel along `towardEdge` (normal flipped by bright/dark side of threshold), all masked by `smoothstep(edgeThreshold, ...)` of normalized Sobel magnitude. Velocity then **advects the CA read coordinate** (`readCoord = px + warp + vel*advectScale`).
- **Optical flow force** (v03): Lucas-Kanade-style `flow ≈ −It·∇I/(|∇I|²+ε)` from stored prev-frame luma — the CA *chases or flees motion in the video*. v11 adds the **aperture-problem fix**: blend LK with a tangent-biased flow (`tangent * sign(It) * 0.5`) weighted by gradient confidence.
- **State-dependent stable stochastic rules** (v04): birth/survive/injection chance gates rolled from hashes seeded by `floor(coord)` + `stateSeed = floor(sum) + self*10` — random but only changing when the local configuration changes ("won't sparkle independently of the sim"). v22 moves the hash from screen-space to `floor(readCoord)` so "randomness flows with advection."
- **The warp-mode pack** (v06→v09 files, 11→14→21→31 modes): all the filter family's flow fields plus domain-fold warps returning a *remapped UV* converted to a clamped pixel offset (`uvWarpToPxOffset`): Kaleido wedge fold (with continuous `kaleidoMirror` blending wedge-wrap↔mirror-fold), Mandelbox-ish **fractalFoldUV** (`abs`, sphere-inversion `p/max(dot(p,p),0.25)−0.45`, per-iteration rotation), **Julia / Mandelbrot / Burning Ship** (6-iteration escape orbits `fract(z*0.1+0.5)`), **Newton z³=1 basins** (with complex division), **3-circle inversion** & **Kleinian-style** limit sets (moving inversion circles + y-mirror), **Sierpinski triangle fold**, **Clifford & De Jong strange attractors**, **Ikeda map**, complex-trig iterate, **Menger-style box fold**, **Barnsley fern IFS** (per-pixel deterministic via seeded hash1 chain), fake-4D "quaternion slice" (3D fold projected), **orbit-trap gradient warp** (finite-difference gradient of min-distance-to-moving-circle over a Mandelbrot orbit, displace down-gradient), **Gray-Scott reaction-diffusion warp** (one explicit GS step computed *on the CA state itself*, F/K mapped from warpScale, displacement along ∇v), and two-level **fbm domain warp** (`r = fbm(p + 4*fbm(p+t))`). Every iterated map is clamped/`fract`ed to stay bounded and uses fixed loop bounds.
- **Time control system** (v10→v13): slider mapping 0=freeze, 0.5=1×, 1=5× via piecewise `computeTimeScale`; slow-mo by *frame-coherent probabilistic frame skip* (`frameHash(FRAMEINDEX) < timeScale`), fast-forward by running up to 5 CA substeps per frame (const-bound loop + break). v12 adds the 1×1 **time accumulator buffer** with exponential smoothing (`alpha = 1−exp(−dt*8)`) so speed changes glide; v13's final design decision: **sim speed uses smoothed speed, warp animation uses raw TIME** so visuals never stutter when the CA freezes.
- **Engine consolidation** (v14–v15): bitmask rules with `rangeToMask` back-compat (`ruleMode` toggle), stable per-pixel morph, `selfSampleMode` (carried local state vs advected sample), reseedWhenDead/dampenWhenHot guardrails with thresholds exposed, per-iteration advection substeps (`readCoord += vel*advectScale*0.2*iter`), 15-preset library (adds Replicator, 2x2, Anneal, DayNight2, Coral, Maze, Move, Stains), caMode Binary/Continuous(Lenia)/Hybrid, variable Gaussian kernel r=1–3 (normalized to 0–8), `quality` toggle halving all fractal iteration counts via `getMaxIters`.
- **v17 refinements**: `temporalSmooth` output blend; activity-based iteration reduction in perf mode; Lenia mode gains **negative growth** (`decayAmt = min(0,delta)*(1−surviveChance)`); Hybrid mode split so binary component always uses equal-weight 3×3 while continuous uses the weighted kernel.
- **v19–v21 refactor discipline**: CA step extracted into `stepBinary/stepContinuous/stepHybrid` + shared `applyStochasticGating`; preset table documented as "Canonical Source — docs derive from this"; v20 adds a **named-constants block** (HASH_SEED_MORPH etc.), `exp2` replacing `pow(2,x)`, wider smoothstep widths, and converts `invert` into a continuous **solarize curve** (`solarizeLuma`: smoothstep-eased identity→invert base + `sin(amount*π)`-weighted V-fold — 0.5 = peak solarization); v21 strips the explanatory comments (release-cleanup pass).

**Control/UI design**: grows to ~45 inputs. v16 invents the family's **section-divider convention**: the first input of a group carries a box-drawing LABEL (`"── SOURCE ──────────────"`, later `"━━ MAIN ━━━━━━━━━━━━━━━━"`), members get `"▸ Name"`, sub-parameters `"   └ Name"`; glyph-coded dropdowns (`⚡ Fast / ✦ Quality`, `■ Binary / ∿ Continuous / ◐ Hybrid`, warp modes classed `○` flow / `◈` fold / `★` fractal). v18 is a pure relabel pass. v22 flips shipped defaults (ruleMode→Range, selfSampleMode→Advected) — tuning the out-of-box feel.

**Version evolution**: file→internal mapping: v01=v01 (range rules + feedback warp), v02=v02 (physics, feedback warp "temporarily disabled (UI cleanup)" — never re-enabled), v03 (+optical flow), v04 (+chance gates), v05 (default retune, inputThreshold 0.3→0.7), v06 (warp menu 0–10), v07 (0–13 kaleido/fractal), v08=v03 (0–20 fractal pack I + kaleidoSegments/Mirror), v09=v04 (0–30 fractal pack II), v10 (+timeControl), v11=v05 (correctness: stable RNG, aperture fix), v12=v06 (time accumulator buffer), v13=v07 (sim-time vs real-time split), v14=v08 (bitmask+morph+guardrails+substeps), v15=v09 (15 presets, Lenia, kernels, quality), v16 (UI sections), v17 (temporal smooth, Lenia decay, hybrid split), v18 (relabel), v19=v10 (refactor), v20=v10.1 (constants/exp2/solarize), v21 (comment strip), v22 (default flips + advected RNG). Clear cadence: *feature spike → correctness pass → UI pass → refactor pass* repeated.

**Complexity tier**: 5 — three-pass system with an auxiliary 1×1 state buffer, per-pixel physics simulation, 31 warp fields, 3 CA modes × 2 rule systems × variable kernels, homeostatic guards, quality scaling, and performer-oriented time transport.

**Signature moves**: RGBA texel as heterogeneous state store (luma/vel.x/vel.y/state); 1×1 persistent buffer as a global scalar register (accumulated time + smoothed control); frame-coherent probabilistic slow-motion; the sim-time/real-time split; the warp-mode mega-menu with uvWarpToPxOffset normalization; stable-hash doctrine graduated into named HASH_SEED constants.

**Rough edges**: `iterativeWarp` deleted in v02 but its `T_fb` helper and `warpIntensityScale`-era inputs linger for versions; enormous duplicated warp library pasted across 17 files (no includes in ISF — the cost of the format); v04→v05 of `reactionDiffWarpUV` computes `u2` (the u-species update) and never uses it; internal-version labels lag file names by up to 6; `sampleInputAt` retained unused once `inputVal` is inlined; the multi-substep fast-forward re-reads the *same* neighborhood each iteration in v10–v13 (fixed only by v14's per-iteration advection), so "5×" was really "1× with extra thresholding" — an acknowledged-by-fix bug.

---

## Batch synthesis

**Top 3 most sophisticated files**:
1. **AR_GameOfLife_filterA_v20.fs** (with v22 as the polished endpoint) — the full stack: physics-advected bitmask/Lenia CA, 31-mode fractal warp dispatch, hybrid time system with 1×1 accumulator buffer, quality scaling, named-constant engineering, solarize input curve. The most "software-engineered" shader in the batch.
2. **AR_GameOfLife_filterA_v15.fs** — the biggest single capability jump: 15-preset bitmask library, three CA modes including honest Lenia-style continuous growth, variable Gaussian kernels normalized to rule space, mutation-oscillated stable morphing.
3. **AR_FractalVolume_V01.fs** — the only raymarcher, and a model of GPU cost discipline: half-res volumetric pass, temporal feedback TAA, cheapTanh emission, hoisted invariants, exp2 octave ceilings.

**Recurring patterns / style fingerprints**:
- `FRAMEINDEX == 0 || reset` init; PERSISTENT+FLOAT sim buffer + bare `{}` display pass; `max(prev*decay, current)` trails.
- The 0.1031 PCG-style `hash(vec2)`; const loop bounds with `if (i >= n) break` as universal Metal armor; `long` inputs for enums with meanings in LABELs, upgraded later to VALUES/LABELS dropdowns.
- **Stable-RNG doctrine**: hashes seeded by pixel coords + discrete state, never TIME, unless flicker is the point — articulated in v05/v07 comments, matured into named HASH_SEED constants.
- Macro→`derived*()` conductor layer with perceptual curves and polarity-labeled sliders; section-divider LABEL headers with box-drawing chars and glyph taxonomies.
- File-version ≠ internal-version; ALT files as A/B forks at decision points; changelog-in-DESCRIPTION.

**Beyond standard ShaderToy fare**:
- A cellular automaton whose *sampling coordinate* is advected by an inertial per-pixel velocity field driven by Sobel edge forces and Lucas-Kanade optical flow of the input video (with an explicit aperture-problem correction).
- A 1×1 persistent texel used as a CPU-less global register for smoothed transport control, and DJ-style time scrubbing implemented as frame-coherent stochastic frame skipping / bounded CA substeps.
- CA birth/survive rules as float-encoded bitmasks with GLSL-ES-safe bit tests, *interpolated bits* for fractional neighbor counts, and per-pixel probabilistic morphing between rulesets.
- A Gray-Scott reaction-diffusion step used not as the visual but as a **warp field generator** over the CA's own state; likewise orbit-trap distance gradients as displacement fields.
- The deliberate design inversion from 28 raw engineering knobs to 6–12 named macro "conductor" controls — the author's most transferable generator-design lesson.
