All 46 files have now been read in full (one turned out to be a zero-byte file). Full report follows as my final message per the coordinator's instruction.

# Batch 17 Analysis Report — ISF Shader Comprehension

## Coverage
- files_assigned: 46, files_read: 46, misses: 1 — `AR_Horizontal-Line_grid_remix_v01.fs` exists but is **0 bytes (empty file)**; no content to analyze. All other 45 files read in full (including the 2,344-line `AR_GOL_MetaCellularFilter_v14.fs` in two passes).

---

## Family 1: ArsonRivvers_GlitcherGrids (v03–v06, 4 files)

**Purpose & visual identity:** Image filter. Chaotic grid mosaic — the frame is cut into cells that each get random mirror/flip/zoom/offset, evolving into a "magazine layout" system (v04+) with golden-ratio columns and layer bands. Editorial-collage glitch, not datamosh.

**Architecture:** v03: single pass + one PERSISTENT `buffer` for chaotic feedback. v04–v06: pure single-pass (`ISFVSN 2`, no PASSES) — feedback was *dropped* in the rework.

**Techniques:**
- **Per-cell transform stack** (v03): `floor(uv/cellSize)`→cellID; per-cell rand scale (0.5–2.0), offset scaled by `chaosFactor * (1.0/cellSize)` (smaller cells get proportionally more chaos), boolean mirror flips via `rand > 0.5`, everything re-wrapped with `fract()`.
- **Random padded zoom** (v03): `(loc - modCenter) * (1.0/modZoom) + modPad` with `minZoomLevel = 4.0/RENDERSIZE.x` clamp — a resolution-aware zoom floor.
- **Chaotic feedback warp** (v03): buffer resampled at `fract(uv + sin/cos(TIME*k + rand*10)*chaos*0.1)` then mixed by `feedbackLoop` — feedback displacement, not accumulation.
- **Layer/column page-layout engine** (v04+): screen divided into 1–3 horizontal layers (count discretized from a 0–1 slider at 0.33/0.66 thresholds); 3-layer mode animates band heights with `sin(π t)` + `smoothstep(fract(t))` waves with cascading clamp logic to keep heights summing to 1. Columns blend from uniform (0.3/0.3/0.4) to golden ratio (0.618/0.382/0) via `goldenRatioMix` — literally interpolating toward φ layout.
- **Full 2D simplex noise** implementation (inlined, Ashima-style constants) drives per-cell offsets — one of the few files in this batch using real gradient noise rather than hash noise.
- **smoothFlip**: `uv = mix(uv, 1.0-uv, flipVal)` — continuous (scrubbable) flip instead of the v03 boolean flip. Signature "make discrete ops continuous" move.
- Local↔global coordinate plumbing: `mapToLocalCol`/`remapFromLocalCol` pairs with `max(width, 0.0001)` div-guards.

**Control/UI design:** v03: 7 floats with semantic ranges (grainAmount 6–16, gridComplexity 1–100). v04+: everything normalized 0–1 (layerCountSlider, layerMorph, goldenRatioMix, rowColComplexity...); v05 adds the family-standard `effectAmount` master dry/wet (`uv = mix(originalUV, uv, effectAmount)` — bypass at 0). CREDIT line "Arson Rivvers, modifications by [Your Name]" betrays an LLM-assisted template never cleaned up.

**Version evolution:** v03 = chaos-first (feedback + grain + random cells) → v04 = total rewrite as structured layout engine (layers/columns/φ), losing feedback and grain → v05 = fixes the 1-layer black-bar bug (`h1 = 1.0` instead of `0.8+0.2*m`) and adds `effectAmount` bypass — the "always be mixable to identity" lesson → v06 = v05 byte-identical logic, whitespace-minified. Trajectory: from random glitch toward controllable graphic design, then performance-ergonomics.

**Complexity tier:** 2–3 (v03 is a 2 with feedback buffer; v04–v06 are single-pass but with a struct-based multi-system layout engine — 3).

**Signature moves:** golden-ratio-as-slider (`mix(uniform, φ, slider)`); discretizing a 0–1 slider into layer counts; per-cell composite seeds (`randomSeed * gridComplexity * chaosFactor`).

**Rough edges:** v06's minification suggests hand-optimizing for an editor paste; `[Your Name]` credit; dead `ratio1/ratio2` phi locals kept "for reference"; grain and feedback never returned after v03.

---

## Family 2: AR_GOL_MetaCellularFilter (v01–v15 + v15_dataloss_v01/v02, 17 files)

This is the batch's flagship: a two-year evolution of a **generative cellular-automata engine** whose transition rule is itself procedurally generated. Note the naming skew: file versions lag internal names — file v01 is internally "Meta-Cellular Filter v2", v05 is "Tier-C" v1, v07="Tier-C v2", v08="v3", v09/v10="v4", v11="v5", v12/v13="v6", v14/v15="v7", dataloss v02 = the BPM live edition.

**Purpose & visual identity:** Filter/generator hybrid: the input image seeds and modulates a living CA field that consumes the screen — "data brutalist" boiling pixel structures, trails, strobes, spreading wavefronts.

**Architecture (arc):**
- v01–v04: 3 passes — `stateBuffer` (PERSISTENT+FLOAT), `trailBuffer` (PERSISTENT+FLOAT), render.
- v05–v10: same 3 passes, new engine.
- v11–v13: 4 passes (+ `metaBuffer`: territory/genTag/propHistory/source2Prop).
- v14–v15/dataloss: **5 passes** (+ `histBuffer` first: prevCellA/prevCellB/propDirection/propMomentum) — an explicit history snapshot pass so trail deltas compare against the true previous frame after the state pass overwrites it. This is a hand-rolled double-buffer inside ISF's single-buffer-per-target model.
- Channel packing is documented per version in comments, e.g. v14: `histBuffer: .r=prevCellA .g=prevCellB .b=propDirection .a=propMomentum / stateBuffer: .r=cellA .g=cellB .b=borderMag .a=propField / trailBuffer: .r=intensity .g=delta .b=feedback .a=stress / metaBuffer: .r=territory .g=genTag .b=propHistory .a=source2Prop`.

**Techniques (the heart):**
- **AST/expression-tree CA rules** — the defining invention. v01: 8 leaves fed through a 3-level tree of hash-picked operators (`applyOp` with 13 float ops). v05 rewrite generalizes to `pickInput` (18 inputs: center, 8 neighbors, timeRel, hashed rnd, `step(0.5,c)*rnd`, neighbor-count/min/max, diag/orth counts) × `applyOp` (18 ops: abs-diff, fract-add, mul, max/min, steps, **bit-shift emulation** `fract(a * pow(2.0, floor(fract(b)*8.0)))`, sin-fold, affine-hash, relu-diffs, xor-ish `1.0-step(0.5,fract(a*3.0+b*5.0+t))`). `ruleComplexity` 1–4 gates real tree depth (single op → 2-layer tree → +feedback op → +cross-modulation `root = fract(root + crossMod*0.5)`).
- **Float ops as bitwise-op surrogates** (v02 comment): "The original shader used uint32 bitwise ops which create sharp structure. These float replacements use step/floor/fract to create discontinuities" — explicit GLSL-ES/Metal portability workaround producing XOR-like checkerboards, quantized mins, hard-threshold waves.
- **Generation/experienceTile system**: `generation = floor(ruleSeed) + floor(FRAMEINDEX/duration)` auto-mutates the rule every `duration` frames; `pickExperienceTile` hashes (ruleSeed + mouseKey, generation) into a `ruleSpace` (up to 65536) of virtual rule addresses — the mouse literally scrubs a combinatorial rule library.
- **Smooth-life large neighborhood** (v01–v04): 41×41 bounded loop with `if (abs(yi) > hr) continue;` runtime radius and stride `stp = floor(hr/6.0)` subsampling; `smoothbump(center,width,t) = smoothstep(c-w,c,t)*(1-smoothstep(c,c+w,t))` birth/survive bands — a continuous Lenia-style CA.
- **Stress-agent CA** (v01–v04): per-pixel agents with packed direction (`0.1 + dir*0.2` in one channel; v04 introduces clean `packAgent/unpackAgent` helpers), stress accumulation, panic re-randomization above `panicThreshold`, and neighbor recruitment when local color mismatches the source — a message-passing automaton in a fragment shader.
- **Spreading wavefront**: cells update only when dead AND some neighbor alive (`onWavefront = dead * (1 - neighborhoodEmpty)`) — turns any CA into an infection/crystal-growth front. v07 fixes it reading stale `.b` instead of `.r`.
- **Expanding injector ring + kill zone** (v03): ring of radius `30 + mod(TIME*80, maxDist)` injects source-luma births, a trailing 40px band multiplies state by 0.7 — continuous re-seeding without global resets. Plus **activity guards**: 4-point buffer probe; `act < 0.03` → emergency reseed, `act > 0.7` → dampen ×0.92.
- **Propagation field engine** (v08→): a second scalar field grows at `vel = propagationSpeed * velocityScale`, gated by `step(0.001, neighborMax)`; the CA only updates where `propMask = smoothstep(0, softness, prop)`. 12 seed geometries by v11 (center disk, edge strip, src bright/dark, mouse, corner arcs, **self-referential ones: Trail Peaks, Border Lines, Change Hotspots, Unpropagated ("paradox mode"), Center Ring, Diagonals**) and 12 growth shapes (uniform, H/V, spiral gate `fract(FRAMEINDEX*rate + angle/2π)`, random walk, radial out/in via per-neighbor distance `step` weights, clockwise flow via `sin(neighborAngle - angle)` weights, source-gradient advection, value-noise turbulent flow, self-modulating logistic `4·p·(1-p)` bell, wavefront-follow local-gradient boost).
- **Dual-front interaction** (v11): Pass-Through / **Annihilate** (`overlap` smoothstep kills 90%) / **Reflect** (each source gated to its territory half) / **Merge** (average where both active).
- **Territory system** (v11): metaBuffer.r diffuses ownership weighted by neighbor propagation strength (`(tL*pL+...)/Σp`), and territory *selects a different rule seed* (`seedBase + 50000`) — two competing CAs with a soft border, plus "Generation Layer" mode where old territory keeps running its historical rule.
- **Trail buffer grammar** (all versions): `trailR = max(prev*decay, activity)` peak-hold trails; `trailG = max(prev*decay*0.95, |Δ|)` temporal-edge energy; `trailB` stores last activity for next frame's delta; `trailA` stress. This *is* the canonical `max(prev*decay, current)` trail idiom, four channels deep.
- **Feedback routing matrix** (v11+): `feedbackChannel` selects delta-energy/trail/border/cellA/cellB as the signal that multiplies propagation velocity, with signed `feedbackPolarity` — patchable self-modulation.
- **Dual-channel CA + spatial warp** (v14): channels A/B run separate rule trees (`channelBSeed`), optionally **cross-coupled** by mixing each other's neighborhoods (`cpA_l = mix(lA, lB, coupling)`); neighbor reads pass through `computeWarp` (Polar Ripple / Barrel Lens `d*dot(d,d)` / Wave / **Feedback** = advection along the propagation gradient) — CA on a warped lattice. Multi-scale `neighborBlend` mixes radius-1 and radius-N neighborhoods.
- **Momentum** (v14): `momVel = abs(prevProp - hist.a) * 10.0`, mixed into velocity by `propMomentum` — finite-difference velocity memory.
- **Speed gate**: `step(1.0 - caSpeed, hash(fragCoord, FRAMEINDEX))` — stochastic per-pixel frame skipping for slow-motion CA without temporal banding.
- **BPM lock** (dataloss v02): all cycles re-derived from wall clock — `beatsPerSec() = bpm/60`, reset fires when `floor(TIME/cycleSecs)` changes vs `floor((TIME-TIMEDELTA)/cycleSecs)` — an elegant frame-rate-independent edge detector using TIMEDELTA. Beat pulse `pow(0.5+0.5*sin, 4.0)` ("keeps the kick prominent, tail short"). **audioFFT** input: `IMG_NORM_PIXEL(audioFFT, vec2(audioBand, 0.5)).r * audioGain` modulates seed size along with beat and luma pulses, each additive and zero-default.
- **Macro knobs** (dataloss v02): `energyMacro` scales propagation speed + flash + edge glow; `chaosMacro` amplifies velocity modulation and signed feedback — one-knob live drive.
- Color: 4 modes everywhere (RGB Hash prime-multiplier `fract(v*7/13/23)`, Heat Map, Source Tint, "HSV Rupture" — hue driven by activity+trails with `mix(col, col.bgr, step(0.7, trail.g))` channel-swap ruptures); golden-ratio dual strobe (`flashRate` and `flashRate*1.618`) so flashes never phase-lock.

**Control/UI design:** grows from 27 inputs (v01) to ~70 (v14). Landmark conventions: `resetCA` bool → `resetButton` **event** type (v05); debugMode long with labeled buffer views (up to 12 views incl. "Warp Field" RGB-encoded vectors); dataloss v02 invents **section-prefixed labels** — `"LABEL":"0.Tempo | BPM"`, `"2.Seed | Size Beat Pulse"`, `"M.Macro | Energy"`, `"Z.Debug | Mode"` — imposing grouped ordering on hosts' flat slider lists. `VALUES` arrays added to long inputs in v14+ (host quirk compliance). v15/dataloss swap `mousePos point2D → mouseX/mouseY floats` and `inputImage → videoSource` (VDMX-friendly; point2D is awkward to map).
**Version evolution (why):** v01→v04 iterate the original 3-system design, fighting mushiness (v03 comment: "the key insight: the AST should select WHICH rule, not modify it per-pixel" — per-pixel random rules produce noise, global rules produce structure). v05 is a clean-slate "Tier-C brutalist engine" rewrite around the 18×18 expression tree. v07 is a *bug-fix + honesty* release (comments enumerate FIXes: dead `.g` channel, generation bleeding into stress, dead-zone srcInjection curve, redundant fetches). v08–v10 grow the propagation/takeover concept into a full field engine. v11 adds ecosystems (territory/dual sources). v12/v13 expose every internal constant ("exposed architecture"). v14 goes maximalist (dual channel + warp + momentum, 5 passes). v15/dataloss turn it into a performable live instrument: performance dispatch (if/else instead of 11 zero-weight `mix` chains — comment: "Dispatch on debugMode rather than running 11 zero-weighted mix() calls"), warp-tap gating, then BPM/audio-locking and slider-count *reduction* (dataloss v02 cuts spiralRate/turbulence sliders — "each only affected a single shape and the defaults are sound", cuts Mouse Cursor seed mode, notes "v01 patches referencing index 5+ need to be re-saved", keeps vestigial `genTag` "so existing PERSISTENT data stays aligned across hot reloads").

**Complexity tier:** 5 — multi-pass simulation system with macro conductors, self-referential seeding, and a documented buffer ABI.

**Signature moves:** hash-seeded expression trees as an infinite rule space; float surrogates for bitwise ops; peak-hold trail grammar; propagation field as an update *mask* separate from the CA itself; buffer-channel ABIs documented in comments; TIMEDELTA cycle-boundary reset.

**Rough edges:** v14's double-spaced 2,344-line formatting (editor export artifact); v12 vs v13 are near-duplicates both labeled "v6"; `takeoverMask` (v07) computed twice per frame then abandoned in v08; an empty `if (wavefrontThickness > 0.001) {...}` block in v11's `computePropagation` whose body was moved out but the scaffold left with a comment; `tileColorVar`/`experienceTile` naming survives long after actual tiles were removed.

---

## Family 3: AR_GrainSuite (v01–v05, 5 files)

**Purpose & visual identity:** Filter. Filmic grain post-treatment suite — from a basic B/W+grain grader to a dedicated grain *instrument* with presets. CREDIT is "Andrea Bovo <spleen666@gmail.com> (refactored)" — this family is AR's staged refactor of someone else's shader, so it's negative/positive knowledge about his *refactoring* style.

**Architecture:** All: 2 passes — one `persistent` buffer + display pass. Crucial pivot at v03: the persistent buffer stops holding the *image* and holds **only the grain field** ("grain-only feedback"), so feedback smears grain, never the picture.

**Techniques:**
- **Linear-light pipeline**: degamma → process → regamma, with `assumeLinearInput`/`workflow` toggle; `pow(max(c,0), gamma)` guards.
- **grainField**: 3-octave value noise at pixel scale (`px / sizePx`, octaves ×1.931, ×3.917 — deliberately non-integer to avoid alignment), frame-quantized via `frame = floor(TIME * grainFPS + 0.5)` with `grainFreeze` — film-cadence grain at 24fps independent of render rate.
- **shapeSigned** `sign(n) * pow(abs(n), d)` — distribution shaping (sharp vs soft grain); `biasNoise` adds asymmetric dark/light bias.
- **Luma/chroma separation**: `lumaNeutralize(n) = n - dot(n, lumaW)` builds zero-luminance chroma grain from 3 decorrelated fields; separate tonal response curves for luma vs chroma with `chromaHighlightSuppress`.
- **Tonal response**: v03's 3-point shadow/mid/highlight bell → v04 adds "Film Curve" mode: `smoothstep shadow cut × inverse highlight cut × pow(exp(-x²), power)` Gaussian mid-band.
- **Clumping** (v04): a large-scale (85px) noise field multiplies grain amplitude `1.0 + clumpAmount * cl` — silver-halide clustering.
- **Anisotropy** (v04): rotate → stretch x / compress y → unrotate the noise domain = directional streaking with angle control.
- **Feedback with per-scale persistence** (v04): keep factor split `lumKeep = mix(keep, keep*0.55, bias)` vs `chrKeep = ...0.85` so fine luma grain refreshes faster than chroma.
- **edgeModeUV** (v04): branchless clamp/wrap/mirror via three masks summed — the vector-ternary workaround pattern.
- **softLimit01** (v04): rational soft-knee limiter on over/under-range values instead of clamp.
- **Look presets** (v05): `lookPreset` dropdown (Modern Clean / Classic 35mm / Gritty 16mm) implemented as three one-hot floats (`isModern = 1.0-step(0.5,p)` etc.) multiplying/offsetting a dozen internals *while user sliders still apply* — preset-as-remap, not preset-as-lockout.
- Optional **blue-noise texture** fine grain (image input + strength, with hash offset per frame).

**Control/UI design:** v01: 15 raw inputs → v04: ~45 → v05 keeps ~45 but adds human LABELs to everything ("Grain Sharpness", "Dark Bias", "Streaking") and macro trio `macroStrength/macroSize/macroCharacter` at top. `previewMode` (Normal / Grain Only / Grain on Gray) is a built-in debug/A-B tool. Seed split: `patternSeed` (spatial) vs `timeSeed` (temporal).

**Version evolution:** v01 "Phase-1 corrected foundation" (linear feedback correctness) → v02 pixel-true grain sizes + film cadence + add/mul model → v03 grain-only feedback + luma/chroma + tonal response, drops all image grading ("No image color correction") — scope discipline → v04 v2.6.1 maximal parameterization → v05 v2.7 presets + labels = productization. Clear trajectory: correctness → physical modeling → performance UX.

**Complexity tier:** 4 (v04/v05) — single sim buffer but a deep, physically-motivated parameter system.

**Rough edges:** unused `texel` computed before the early-out in `samplePrevGrain`; v04's `chromaMultiply` half-strength special case (`grainAddMul*0.5`) silently changed to a separate slider in v05; float-typed enum inputs (`previewMode` float with LABELS) instead of `long` — ISF Editor quirk tolerance.

---

## Family 4: AR_Grid_fractalshatter_v01 (1 file)

**Purpose:** Filter. Recursive golden-ratio "shatter" of a base grid; subtle time-animated offsets. A minimal sketch of the subdivision idea used across the Horizontal family.

**Architecture:** Single pass, no buffers.

**Techniques:** per-level split remap `newY = (y+off < r) ? (y+off)/r : (y+off-r)/(1-r)` around `baseSplit = 0.618 + chaos variation`; alternating H/V by level parity; **const loop bound (3) with runtime `if(i >= levels) break`** — the family's standard loop workaround; `effectAmount` UV blend at the end.

**Controls:** 6 floats + effectAmount. CREDIT "Concept by [Your Name]" (another un-filled template).

**Tier:** 1. **Rough edges:** `rand(vec2(local.x, t))` uses the *local* coordinate as hash input, so the "random" variation is continuous across x — likely unintended but produces smooth wobble.

---

## Family 5: AR_Gridify_v01 (1 file)

**Purpose & identity:** Filter. "UNHINGED: Hybrid Chaotic/Rigid Grid with ALL magic numbers exposed." The philosophical opposite of Horizontal v08's 10-slider consolidation: **~120 inputs**, including the hash function's own magic constants as sliders (`hash11Magic` 0.1031, `hashScale1` 123.34, `phiValue` slider around 1.618…).

**Architecture:** 2 passes: PERSISTENT+FLOAT `feedbackBuffer` + display.

**Techniques:**
- **hybridBSP**: 16-step binary space partition where each cut is either **rigid** (snaps to 0.5 or `extreme`/`1-extreme` from `rigidExtremeBias`) or **organic** (φ-based ratio with sinusoidal drift), chosen by a `rigidState` that carries across levels via `mix(n2, rigidState, rigidRunLength)` — run-length-correlated rigidity, so rigid/organic decisions cluster.
- `minRectSize` clamped cuts (`cut = clamp(cut, minP+minRect, maxP-minRect)`) prevent degenerate slivers.
- **Depth loop with LOD**: up to 16 iterations; per-depth `cheap = smoothstep(thresh,1,depthNorm)*depthAdaptive` progressively reduces field complexity, aspect cycling, and organicity at deep levels — explicit shader LOD by iteration depth.
- **buildField**: hash-offset vs multi-sine trig field blended by `fieldComplexity`, with all 8 time multipliers and 7 spatial frequencies exposed (`fieldTimeMultA..H`, `fieldSpatialA..G`).
- **Motion quantize**: `quantizeTime(t + mq*offset, steps) - mq*offset` with per-rect offsets — stepped/stop-motion time where each BSP rect ticks on its own phase.
- **Seam glow**: edge-distance masks in both micro-grid and macro-rect space, jittered widths, `seamMode` blends micro↔macro.
- **mirror01** `1.0 - abs(1.0 - 2.0*fract(x))` — triangle-wave mirror wrap selectable per cell vs `fract` (`cellWrapMode`).
- Rect-hash-driven per-rect parameter variation (sign flips of chaos, reach, organic, aspect scale) — the "every room behaves differently" idea from Horizontal v10, generalized.

**Controls:** the extreme end of AR's exposure philosophy; effectively an "editable source code via sliders" instrument. Labels are terse but complete; `alphaMode` premultiply toggle.

**Tier:** 5 for control-surface scale; core math tier 4.

**Rough edges:** exposing hash constants makes most slider space visually redundant; `stagingStrength` multiplies `tS` twice (inside and after `applyCompoundGridUnified`-equivalent), compounding attenuation — a recurring subtlety in this lineage (see Horizontal v11).

---

## Family 6: AR_HalfToneGlyphs (v01–v03, 3 files)

**Purpose:** Filter. Camera → posterize → ordered square halftone → optional ASCII-like glyph stamps, with edge reinforcement + "digital halo." Print/riso aesthetic.

**Architecture:** Single pass, purely procedural ("no textures").

**Techniques:**
- **Array-free Bayer 4×4**: full 16-entry ordered-dither matrix as a chained ternary on `(x==i && y==j)` — comment says "(array-free, host-safe)": scalar ternaries used precisely because *vector* ternaries and const arrays are hazardous on the Metal backend.
- **Procedural glyph stamps** (v01): `plusShape` (axis distance smoothsteps), `xShape` (`abs(p.x - p.y)` diagonal distance), 2×2 checker; per-cell hash chooses stamp vs solid via `doASCII = step(1.0 - asciiDensity, rndCell)`.
- **Two-level grid**: big mosaic cell (gridSize) → inner subdiv halftone (subdivF); coverage `pow(1.0 - posterizedLuma, gammaCurve)` thresholded against Bayer with `softness` smoothstep AA.
- **Per-cell sample jitter**: polar offset `(jitter/gridSize) * (cos, sin)(2π·hash)` breaks mosaic regularity.
- **Edge reinforce on the snapped grid**: central differences of luma sampled at *snapped* neighbor cells (mosaic-resolution Sobel), then `halo = smoothstep(0, 1/haloRadius, edge) * edgeHalo` lifts color back toward bg — the "digital halo".
- v03: **full effectAmount gating** — every stage lerped by `t` (jitter, posterize, softness, edge, halo, post ops), early-out `if(t<=0.001) return base;`; plus a post-color chain (desat→contrast about 0.5→saturation→gain/lift→output gamma) all scaled by `t`.

**Controls:** v01: 14 including ink/bg `color` inputs; v02 strips glyphs (pure halftone); v03 drops ink/bg colors (shades the *source* color instead: `effectCol = src * shade`) and adds the post chain + `effectAmount` — moving from poster look to VJ-mixable treatment.

**Version evolution:** v01 full concept → v02 subtraction (glyphs removed — presumably too busy on video) → v03 integration into the VJ workflow (bypassable, color-preserving). Note glyphs were *not* re-added in v03: the surviving direction is halftone-shading of the original color.

**Tier:** 2.

**Rough edges:** v01 `haloRadius` used as `1.0/haloRadius` smoothstep edge — misnomer; v03 keeps ink/bg-free shading but the DESCRIPTION still says "Mosaic posterize"; `if(d>=0.999) post=gray;` redundant hard-set after a mix.

---

## Family 7: AR_Horizontal_Combined (v01–v13) + AR_Horizontal-Line_DarkV_v01 (+ empty grid_remix) — 15 files

**Purpose & visual identity:** Filter. The batch's longest continuous lineage: a chaotic grid warper whose cells breathe through cycling aspect ratios, staged spatially by golden-ratio ordering, with trails/motion blur. Evolves from parameter sprawl → 10-knob macro instrument → BSP "rooms" architecture → single-pass distillation.

**Architecture:** v01–v06: 2 passes (`lastFrame` persistent + final) — note the persistent pass declared with lowercase `"persistent": true` and explicit `"WIDTH": "$WIDTH"` (older idiom vs the CA family's `PERSISTENT/FLOAT`). v07: an experimental **10-pass** decomposition (preSrc, auxField, stageField, aspectField, subdivUV, warpedUV, core, temporal, colorOut, finalOutput) — fields rendered to buffers then consumed, explicitly "for profiling, reuse, and debug." v08–v11: back to 2 passes. v12–v13: **single pass, no buffers** (temporal system deleted).

**Techniques:**
- **Aspect-ratio cycling** (whole family): per cell, `phase = rand(cell*seed) + timeChaos`, cycles through 3 ratios (1/3 → 2/3 → 5/4) with `mix` between adjacent — cells continuously morph between portrait/landscape croppings. Scale about cell center `(uv - cs*0.5) * vec2(ar, 1/ar) + cs*0.5`.
- **Organic offset field**: 3-term product-of-sines pseudo-noise per cell (`sin(t*0.2+cx*2)*cos(t*0.3+cy*3) + 0.5*sin(...)` + secondary motion), blended against pure hash offsets by `smoothness = organicDistortion²` with a slow `0.8+0.2*sin(t*0.25)` breathing weight — hash↔flow crossfade as the chaos/organic axis.
- **Spatial staging** (`gridComplexityPattern` / `gridMorphPattern`): transitions ordered per cell by `fract(cx*φ + cy*φ²)` (golden-ratio low-discrepancy ordering) plus a center-out delay `(1-distFromCenter)*0.4` — fractional complexity values dissolve cell-by-cell in φ order rather than popping globally. This is the family's signature and appears in Gridify too.
- **Iterated warp**: up to 10 repetitions of the compound grid at escalating complexity `gridComplex * (1 + i/reps)`, each blended in by a *per-iteration morph field* (`gridMorphPattern(uv + i*0.1, ...)`) — layered warp with spatially staggered onset.
- **Recursive subdivisions**: 3-level BSP-ish splits at φ ratios with `levelTransition = smoothstep(level, level+1, levels)` — fractional levels fade in.
- **Temporal block**: trails `mix(current, previous, trailAmount*effectAmount)`; **motion blur along the warp vector** — velocity = `(warpedUV - uv)`, 6 samples, each sample itself a `mix(inputImage, lastFrame, historyInBlur)` — blur that can smear *history* as well as the current frame; v05 adds `trailMixMode` (average↔additive `min(cur + prev*trail, 1.0)`), `feedbackGain` (>1 blooms), `haloFade`.
- **10-slider macro mapping** (v08 — the family's UX thesis): each knob expands into many internals, e.g. `persistence` alone drives `trailAmount(0→0.85), feedbackGain(0.9→1.4), haloFade, historyInBlur, motionBlur(smoothstep 0.3–1), trailMixMode(step 0.6)`; `warpAmount` drives chaos, distortion 0.3–1.8, and repetition count 3–10; seed derived from knobs (`42 + ratioVariety*37 + gridDistributor*19`) so timbre changes with settings.
- **macroBSP** (v09): golden-ratio BSP with per-step orientation from `fract((i+0.5)*0.618 + seed*0.17)` and **fractional-step animation** — the last cut's ratio lerps from 0.5 as `fract(complexity)` rises, so the complexity slider *grows new walls smoothly*. Micro system re-based into `rectUV` (each room gets its own full grid).
- **Per-macro seeding** (v10): `macroSeed = hash11(rectID...)` → per-room time stretch ±13%, warp boost ±10%, ratio variety — rooms desynchronize.
- **Hidden debug overlay** (v10/v11): `persistence > 0.98` draws macro rect borders — a debug mode smuggled into an existing slider's extreme ("no extra slider").
- **Non-repeating splits** (v11): orientation/ratio hashes keyed off `floor(uv*3)` regions and per-step grids `floor(uv*(3+i))` so different screen areas take different BSP paths (deliberately breaking BSP consistency for variety — cells no longer strictly rectangular), plus slow TIME drift of ratios.
- v12/v13: `structureJitter` (sinusoidal ratio drift) and `orderChaosBalance` (`mix(float(n<0.5), float(rand<0.5), ocb)` then threshold — blending two *boolean* decisions numerically, with a "FIXED:" comment marking the vector/bool-mix workaround); v13's "FINAL ORDER-OF-OPERATIONS FIX": `finalUV = mix(baseUV, effectUV, effectAmount)` guaranteeing identity at 0 — the recurring bypass-correctness lesson stated in caps.

**Control/UI design:** The arc *is* the story: v01 15 sliders → v04–v06 ~28 (every constant exposed: transition grids, φ, morph fields, subdivision ratio/bias/density) → v08 collapses to exactly 10 semantic knobs → v12/13 keep 10 but swap two for structure controls. `effectAmount` always first; input ordering becomes deliberate (v05 header groups: master / staging / time / grid / topology / subdivision / temporal, `inputImage` last).

**Version evolution:** DarkV_v01 (heavily commented original, single time control) → v01 adds modeBlend/staging → v02–v03 split time channels + expose ratios (the "coarse/fine time" decision: `chaosSpeed` default 0.05 vs `organicSpeed` 1.0) → v04–v06 expose topology + upgrade temporal mixing → v07 pass-decomposition experiment (abandoned: v08 returns to 2 passes; buffer round-trips quantize UVs to 8-bit and the aspectField sampling in warpedUV uses the wrong UV — visible as banding; negative knowledge) → v08 the macro consolidation → v09–v11 macro BSP arc (Phases A, B, C1 explicitly named in DESCRIPTIONs) → v12–v13 single-pass distillation, temporal features cut entirely. The lineage then forks into `AR_Gridify_v01` (everything-exposed) and `AR_Grid_fractalshatter_v01` (minimal sketch).

**Complexity tier:** v01–v06: 3; v07: 4 (architecture) ; v08–v11: 4 (macro-conductor design); v12–v13: 3.

**Signature moves:** φ-ordered spatial staging; macro knobs expanding to parameter bundles; fractional-parameter smooth growth (both complexity dissolves and BSP wall growth); debug mode hidden at a slider extreme.

**Rough edges:** v07's buffer pipeline reads `aspectField` at screen `uv` instead of cell space (bug), and packs UVs into 8-bit buffers (no FLOAT flag) — abandoned direction; duplicated per-cell transform math inlined into v07 pass 5 ("simplified" divergence); v11 double-multiplies `stagingAmount` (inside compound grid and again at the per-iteration mix), making the slider response quadratic; `hash21` defined but unused in several versions; the `gridComplexityPattern(uv, base, progress)` `progress` argument is always 1.0 and ignored for four versions.

---

## Batch synthesis

**Top 3 most sophisticated files:**
1. **AR_GOL_MetaCellularFilter_v14.fs** — 5-pass CA engine with dual cross-coupled rule-tree channels, warped-lattice neighbor sampling (including propagation-gradient *feedback* warp), momentum, territory ecosystems, and a fully documented 4-buffer channel ABI. The most architecturally ambitious shader in the batch.
2. **AR_GOL_MetaCellularFilter_v15_dataloss_v02.fs** — the same engine turned into a live instrument: BPM-locked cycle math via TIMEDELTA boundary detection, audioFFT band drive, Energy/Chaos macros, section-prefixed slider labels, and *deliberate feature cuts* with migration notes — engineering maturity, not just accretion.
3. **AR_Horizontal_Combined_v10.fs** — golden-ratio BSP macro rooms with per-room seeding/time-stretch, dual-space (global vs macro) staging fields blended by complexity, and a debug overlay hidden above persistence 0.98 — the densest *design* thinking per line.

**Recurring patterns across families (style fingerprints):**
- `max(prev * decay, current)` peak-hold trails, everywhere temporal memory appears; multi-channel trail grammars (intensity/delta/feedback/stress).
- `effectAmount` master bypass that must be exact identity at 0 — repeatedly *fixed* across families (GlitcherGrids v05, HalfToneGlyphs v03, Horizontal v13's all-caps "FINAL ORDER-OF-OPERATIONS FIX").
- Golden ratio as an organizing constant: φ split ratios, φ-ordered staging (`fract(x·φ + y·φ²)`), 1.618× dual strobe rates.
- Const-bound loops with runtime `break` (`for(int i=0;i<16;i++){ if(i>=steps) break; }`) and stride-subsampled neighborhood loops with `continue` — the Metal/GLSL-ES loop discipline from the brief, confirmed pervasive.
- Branchless mode dispatch via `step()` chains and one-hot masks (colorMode/debugMode/edgeMode), later *reverted* to if/else specifically for performance in v15/dataloss — both directions used knowingly.
- Standard hash family: `fract(sin(dot(p, vec2(12.9898,78.233)))*43758.5453)` in older/grid code, `hash31`/`hash12` (0.1031/33.33 style) in newer sim code — hash choice dates a file.
- `FRAMEINDEX < 2` init guards; reset via `mix(state, initState, doReset)` rather than branches.
- Macro/conductor sliders expanding into parameter bundles (Horizontal v08 persistence; GrainSuite macroCharacter; dataloss energy/chaos macros) — the author's mature UX position, coexisting with its deliberate antithesis (Gridify's everything-exposed).
- Per-cell/per-rect hashed parameter variation ("every room behaves differently") in every grid family.
- Version files as immutable checkpoints — reworks land in new files; comments narrate FIXes and cut features like changelogs.

**Beyond standard ShaderToy fare:**
- Hash-seeded **expression-tree (AST) cellular automata rules** with a scrubbable 65k rule space and depth-gated tree complexity — genuinely novel; I have not seen this pattern in common shader repositories.
- **Propagation-field masking of CA updates** with 12 seed geometries and 12 anisotropic growth shapes, including *self-referential* seeds (seed where trails peaked, where borders are dense, where nothing has propagated).
- **Territory ecosystems**: two rule-sets competing via a diffused ownership field that *selects the rule seed* per pixel.
- A hand-rolled **history pass** (histBuffer) to recover true previous-frame deltas inside ISF's persistent-buffer model, plus finite-difference propagation **momentum**.
- **TIMEDELTA-based BPM cycle-boundary detection** (`floor(TIME/secs) != floor((TIME-TIMEDELTA)/secs)`) — frame-rate-proof beat resets.
- Run-length-correlated rigid/organic BSP decisions (Gridify's `rigidRunLength` state carried through `mix`).
- Section-prefixed `LABEL` naming (`"0.Tempo | BPM"`) as a host-UI grouping hack.
- The GrainSuite's per-scale feedback persistence (fine grain refreshes faster than coarse) and preset-as-parameter-remap (presets that still respect user sliders).
