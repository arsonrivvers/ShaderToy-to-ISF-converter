## Coverage
- files_assigned: 34, files_read: 34, misses: none

All files read in full: AR_Genuary2026_day22_01.fs through day22_22.fs (22 files) and AR_Genuary2026_day23_01.fs through day23_12.fs (12 files). All in /Library/Graphics/ISF/.

---

## Family 1: Schotter Neighbor-Overlap Plotter (day22_01 → day22_09)

**Purpose & visual identity**: Georg Nees "Schotter" (1968) homage — a grid of squares that grow more rotated/displaced/chaotic toward the bottom of the frame, rendered as pen-plotter line art (off-white paper, near-black ink). Generator, single pass throughout this sub-family.

**Architecture**: Single pass, no buffers. Core technique: sample a 3×3 neighborhood of grid cells per pixel so a neighbor's box can rotate/drift into the current pixel and still get drawn (`for y=-1..1, x=-1..1`) — the load-bearing trick that lets overlap/spillover render correctly without a geometry pass.

**Techniques**:
- **Cell hashing**: `hash21` (`fract(p*vec2(234.34,435.345)); p+=dot(p,p+34.23); fract(p.x*p.y)`) reused verbatim across the whole family; each hash channel gets a distinct additive offset (`+1.0`, `+101.1`, `+202.2`…) to decorrelate position/rotation/size/pen/masking randoms from one seed.
- **Vertical chaos gradient**: `chaosZone = smoothstep(chaosStart, 1.0, 1.0-normalizedY)` — order at top decaying to chaos at bottom; the signature Nees device, reused in every later Schotter family.
- **SDF box + rounded box**: standard `sdBox`/`sdRoundedBox`; `abs(dist)-strokeWidth` for outline; `1-smoothstep(-w,w,x)` with `w=fwidth(dist)` for AA stroke masks.
- **Void/ghost/masking stochastic layers**: per-cell `step(1-chance, hash)` gates for "void" (skip cell), "ghost" (double-struck echo offset `vec2(0.02,-0.02)` + rot(0.05) at 0.3 alpha, simulating servo/registration bounce), and "masking" (paint paper color back over the fill to fake white-out of shapes underneath).
- **"Broken grid" clipping** (04+): a clip-flagged shape may draw ONLY when processed from its own home cell (`if (isNeighbor && shouldClip) continue;`), producing the torn/interrupted grid look.
- **Hatch fill**: `hatch()` = `sin(p.x*density*PI)` thresholded via smoothstep; cross-hatch by `max()` of two hatch calls at angle+90° (06+). Hatching rotates with the shape because it uses `localUV`; a comment notes using `uv` instead would give screen-print-style global hatching.
- **Servo jitter / "X-Ray" glitch** (05–09): `localUV += jitter * sin(localUV.y * K)` where jitter is a hash-derived vec2 scaled by `SERVO_Jitter` — coherent sine-modulated positional wobble reading as pen vibration. File 07 explicitly splits it into two independent effects (XRAY_Glitch at frequency 50, SERVO_Jitter at frequency 120, "to avoid interfering with the X-Ray pattern") after discovering they fought each other.
- **Derivative-aware bleed** (09): `dynamicBleed = PAPER_Bleed/(1.0 + w*200.0)` with `w=fwidth(d)` — uses the screen-space derivative of the distance field as a proxy for "how glitched is this geometry" and suppresses ink bleed exactly where XRAY jitter creates large derivatives, so bleed doesn't erase the glitch artifact. Non-obvious cross-coupling of an AA quantity into an art-direction parameter. File 07 used a cruder binary version (`effectiveBleed = (XRAY_Glitch > 0.001) ? 0.0 : ...`).

**Control/UI design**: 9–22 float inputs. A `PREFIX_Name` convention emerges partway through (`CHAOS_Start`, `PEN_Base`, `GHOST_Chance`, `SIZE_Var`); chance-style 0–1 stochastic gates (`voidChance`, `ghostChance`, `maskChance`, `roundChance`); `SEED` as the single global re-randomize knob. Coarse/fine pairs like `PEN_Base`/`PEN_Var`, `SIZE_Base`/`SIZE_Var`.

**Version evolution**: 01 (single-cell, no overlap; ghost baked inline) → 02 (adds neighbor loop for true overlap; masking) → 03 (consolidates ghost+round+void+mask into the neighbor-loop architecture) → 04 (adds CLIP_Chance broken-grid) → 05 (adds hatching, first servo jitter, paper bleed) → 06 ("Phase 6": cross-hatch, recursion/inner-shape at 50% size, red-ink swap, jitter made global instead of chaos-gated, paper grain) → 07 (isolates the X-Ray artifact as its own math with its own frequency, "bleed at zero" preference encoded) → 08 ("Final Integration" — reverts jitter to the chaos-gated baseline the author preferred, consolidates 06+07 features) → 09 ("Final Smart-Shader" — solves the bleed-vs-glitch conflict with fwidth-based dynamic bleed). Descriptions literally narrate reversions ("Restores the specific 'X-Ray' artifact", "Preserves the unique jitter artifacts") — an artifact-preservation loop where accidental glitches the author liked were reverse-engineered into named features.

**Complexity tier**: 2 (01–02) rising to 4 (06–09): still single pass, but 9+ interacting stochastic layers per cell.

**Signature moves**: broken-grid clipping; XRAY/servo dual-jitter split; derivative-driven bleed suppression; "servo bounce" ghost strokes.

**Rough edges**: file 06's description says "Multi-Pass" but there is no PASSES block (name inherited from a discarded draft). Files 06–09 are ~150-line bodies duplicated with tiny deltas — copy-paste iteration rather than shared code.

---

## Family 2: Schotter × BSP/Ising Multi-Pass Plotter (day22_10 → day22_17)

**Purpose & visual identity**: Same Nees lineage re-architected as a true multi-pass BSP box-subdivision system with physics-model-derived randomness (Ising coupling), golden-ratio splits, and temporal ink accumulation. Generator; contains the batch's most sophisticated plotter files.

**Architecture**: File 10 is a single-pass "mode selector" hybrid. Files 11–17 use genuine ISF multi-pass: 8 `passDepthN` targets (one per BSP recursion depth — each pass renders ONLY cells whose subdivision depth equals its index) plus a composite pass; 15+ adds a `PERSISTENT` `accumBuffer` pass for temporal ink build-up (10 passes total). The "one buffer per depth level, composited last" dispatch is a distinctive architecture: it statically unrolls recursion depth into pass count, sidestepping GLSL's lack of recursion.

**Techniques**:
- **File 10, five chaos-field generators behind one `long` dropdown** (`MODE_Select` with VALUES/LABELS): BSP recursive subdivision; a Gray-Scott-flavored reaction-diffusion *approximation* (fbm interference, `reaction = a*b*b`, feed/kill params steering a smoothstep — not a real RD PDE, no sim buffer); an Ising lattice (`isingField`: exp-weighted neighbor spins in a range×range window, Boltzmann probability `exp(-E/T)`, critical-temperature default 2.27); an L-system angle-accumulation grammar (production rules chosen by hash, accumulated angle × decaying scale, `currentPos = floor(currentPos*0.5)` per generation); and a Voronoi field with approximate Lloyd relaxation (`point = mix(point, vec2(0.5), relax*0.5)`) plus F2−F1 edge distance driving chaos. A `MODE_Blend`/`MODE_BlendTarget` pair cross-fades any two modes. Also: `sdPolygon` (N-gon via `mod(atan)` sector fold), morphable polygon⇄circle `sdMorphShape`, stipple fill (jittered grid dots), `label`-type inputs as section dividers (`"═══ GRID FOUNDATION ═══"`), color-type inputs for paper/ink.
- **BSP leaf enumeration via pathBits** (11+): `traceBoxPath` walks maxDepth splits; a `pathBits` integer selects which of the 2^depth leaves is being drawn by extracting `pathBit = (pathBits / 2^d) mod 2` (computed with an unrolled `divisor *= 2` loop — integer-op host workaround). Each pass brute-force iterates `for (pathBits = 0; pathBits < 256; ...)` with runtime break at `numBoxes` — const loop bound + runtime break, the known host-safe pattern.
- **Golden-ratio split system**: `getSplitRatio` blends "original Schotter" edge-weighted ratios {0.15, 0.85, 0.5, rand(0.3–0.7)} with golden ratios {0.618, 0.382, 0.5} under a `GOLDEN_Bias` slider; `shouldSplitVertical` is aspect-aware (wide→vertical split, tall→horizontal) under an `ASPECT_Aware` blend.
- **Ising coupling as spatial chaos correlation** (fixed in v2, file 13): `mySpin·neighborSpin` alignment averaged over 8 neighbors; aligned neighborhoods REDUCE chaos, misaligned INCREASE it (`chaosModifier = 1 - avgAlignment*0.4*coupling`) — ferromagnetic patchiness instead of salt-and-pepper randomness. File 11/12's first version (average neighbor spin only, no self-spin product) is explicitly labeled "FIXED" in 13.
- **Seeded PRNG stream**: `nextRand(inout seed)` with golden-ratio increment `seed = fract(seed*1.618... + 0.314...)` — a stateful sequential RNG carried through the split path so every leaf gets a deterministic unique seed; `makeSeed` is the classic `fract(sin(dot)·43758.5453)`.
- **Ink accumulation** (15+): `result = max(freshFrame, oldAccum * INK_Accum)` — max-based trail accumulation (ink darkens toward a ceiling instead of blowing out; exactly the `max(prev*decay, current)` idiom). Servo-jitter phase gains `+ time*15.0` here specifically so accumulated trails wiggle organically over frames.
- **Root-cell-relative drift** (v3 fix, 15): drift had been scaled by *leaf* box size, so deeply subdivided boxes could never escape their containers; rebased onto `rootCellSize = 1/GRID_Cols` so drift magnitude is depth-independent — a coordinate-reference-frame bug properly root-caused.
- **Culling radius as itemized worst-case sum** (17): `radiusA = length(effectiveDim) + driftAmp + jitterAmp + ghostAmp + penWidth + bleedPad` — every displacement source accounted for, replacing earlier magic-number margins. Also anisotropy-corrected distance (`deltaA.x *= aspect`).
- Final composite adds paper grain (`hash*0.02`) and vignette; INK_GHOST is a dedicated grey (`vec3(0.65,0.63,0.60)`) rather than alpha-faded black.

**Control/UI design**: consistent `CATEGORY_Name` prefixes (`GRID_`, `CHAOS_`, `SUBDIV_`, `GOLDEN_`, `ISING_`); `ASPECT_Force1to1` bool to pin a square canvas in any host aspect; `TIER_Scaling` bool quantizing sizes to 4 discrete "Bauhaus-style" tiers {0.45, 0.65, 0.85, 1.0}; chaos-link sliders (`SUBDIV_ChaosLink`, `HOLLOW_ChaosLink`) that couple a feature's probability to the vertical chaos field — a distinctive "wire feature X to the chaos conductor" pattern.

**Version evolution**: 10 (single-pass, five-algorithm exploration) → 11 (commit to BSP+Ising multi-pass; square-forced canvas) → 12 (adds ASPECT_Force1to1 + aspect-corrected box math) → 13 (v2: Ising math fixed to true ferromagnetic alignment; uniform depth RNG fix; culling accounts for drift) → 14 (v2.1: adds the 3×3 neighbor loop to the multi-pass renderer — boxes drifting across cell boundaries finally render) → 15 (v3: root-cell drift fix, TIME-animated jitter, PERSISTENT accumBuffer added, neighbor loop → ±2) → 16 (v3.1: neighbor loop → ±3, relaxed culling) → 17 (v3.5: neighbor loop → ±6, itemized culling formula, new distance-weighted `CLIP_Chance` neighbor-prune). A textbook "max the slider, find the clip artifact, widen the search" loop — five versions patched the symptom before/around the real fix in 15.

**Complexity tier**: 5 (11–17): multi-pass, physics-derived stochastic fields, persistent temporal buffer, conductor-linked probabilities. File 10 alone: 4–5 for algorithmic breadth in a single pass.

**Signature moves**: BSP leaf enumeration via pathBits; depth-per-pass architecture; Ising-coupled spatial chaos; max-decay ink accumulation with time-wiggled jitter; itemized worst-case culling.

**Rough edges**: 11/12/13 are near-duplicate ~700-line files with 1–2 real changes each; 13's "Neighbor Sampling Fix" title doesn't match its content (14 actually adds neighbor sampling). The neighbor-radius arms race (±1→±6, a 169-cell loop × up to 256 pathBits per cell per pass) is very expensive — brute force standing in for proper bounds math until 17. Pass 9 in file 11 declares `"TARGET": "passDepth9"` that is never sampled (dead buffer); 13+ replaces it with `{}`.

---

## Family 3: Pifragile Recursive-Subdivision Hatching Plotter (day22_18 → day22_22)

**Purpose & visual identity**: A different lineage credited "Original by Pifragile" — recursive rectangular subdivision filled with engineering-drawing hatching, evolving into a full architectural plot-sheet aesthetic (page frame, registration marks, title block) by file 22. Generator, single pass throughout.

**Architecture**: Single pass. Fixed `MAX_DEPTH=12` recursive binary split of a unit box, unrolled as const-bound loop with runtime break, driven by the same `nextRand`/`makeSeed` PRNG stream as Family 2 (shared toolkit). Returns `BoxResult{localUV, cellSeed, depth}`.

**Techniques**:
- **Recursive UV remapping instead of coordinate tracking**: each split remaps `localUV` back to [0,1] (`localUV.x = (uv.x-gr)/(1-gr)`), so a leaf's UV space is always unit — simpler than Family 2's absolute pos/size Box, but loses physical scale. File 21 adds a parallel `localScale` accumulator (`localScale.x *= gr`) precisely to recover physical size for density/pen normalization — the design flaw and its patch both visible.
- **Hatch "palette" system** (19+): `getHatchStyle(paletteIdx, colorIdx)` returns `(angle, baseDensity, crossFlag)` triples from hand-authored lookup tables ("Detailed" palette of 6 styles, "Contrast" palette of 4) — a curated library of hatch textures assigned per box by hash, standing in for a color palette in a monochrome medium.
- **Adaptive hatch density** (20): a long inline comment works through why constant density is wrong across grid scales and derives `adaptiveDensity = paletteDensity * boxScaleEstimate * m5 * 4.0` (the 4.0 labeled "Magic number to make the slider range feel good"), clamped `≥2.0` "to prevent weird aliasing artifacts on tiny boxes."
- **Physical-pixel pen width** (21–22): `halfWidth = (penWidthPx/minDim)/physScale * 0.5` where `physScale = subScale * min(localScale.x, localScale.y)` — pen width specified in screen pixels and propagated through the full scale chain (page margin → grid → cell fill → subbox → recursion) so strokes look plotter-uniform at every depth.
- **Plotter-physics material stack** (21): `paperField` 2-octave value-noise grain; grain-driven `bleed` (dilates halfWidth) and `absorb` (modulates ink density); `pressureVar` noise-modulated stroke width along the line; `liftMask` noise-thresholded gaps simulating pen lifts; `overshootAmount` lines extending past box corners (hand-plotted corner overshoot — drawn by allowing edge strokes to render within `[-o, 1+o]` on the perpendicular axis); `misregister` per-box rotation/offset jitter; `wobble` noise jitter on hatch coordinates. Each behind its own named slider.
- **Composition/tone/grammar system** (22, the family's summit): `massField` (three Gaussian-falloff attractor blobs, two hash-offset from the user-set center) and `flowField` (curl noise via central-difference gradient, `vec2(dy,-dx)`) jointly steer hatch density, hollow probability, outline weight, and hatch *angle* (`angleFollowFlow` rotates hatch toward local flow). `toneMap` applies bias/contrast then posterizes into `toneSteps` levels; `hatchLevelFromTone` maps value to 0/1/2/3 hatch layers (single → cross → triple at +60°, with the triple layer 1.25× pen weight) — real tonal rendering. `pickRatio` exposes the split grammar itself (`ratioMode`: halves / thirds / golden / free / extreme-0.05/0.95, plus `ratioJitter`), `verticalBias`+`biasByDepth`+`clusterAmount` steer split direction by depth and mass, `minBoxAreaStop` halts recursion below an area threshold. Negative-space reservation (`blankReserveAmount` keeps large boxes deliberately empty), depth/mass-linked hollowness, stroke-style mixer (solid/dash/stipple/breakup masks cross-faded by one `strokeStyleMix` slider), and page furniture: `pageFrameInk`, `regMarksInk` (corner crosses), `titleBlockInk` (rect + micro-grid faking a drawing title block with "text" lines).
- **Host-quirk workaround**: `imod(a,b) = int(mod(float(a),float(b)))` because integer `%` is unreliable across ISF hosts (19+).

**Control/UI design**: 18–20 use terse `m0..m5` names (MIDI-mappable minimal knobs); 21 renames everything descriptively with `Group: Name` LABEL prefixes ("Ink/Paper:", "Structure:", "Hatching:", "Plotter:", "Material:") — a deliberate mid-series UX upgrade; 22 grows to ~65 inputs across 12 labeled groups ("Composition:", "Tone:", "Grammar:", "Negative Space:", "Hierarchy:", "Page:", "Stroke:", "Motifs:") — a designed control surface, the largest curated (non-mechanical) INPUT list in the batch.

**Version evolution**: 18 (bare port: subdivision + single hatch + outline) → 19 (hatch palettes, imod fix, hollow chance) → 20 (adaptive density with visible worked reasoning) → 21 ("Upgraded": descriptive naming, physical pen units, full material stack, localScale tracking) → 22 ("Evolved Composition + Tone + Grammar": spatial composition fields, tone quantization, split-grammar exposure, page furniture — the single biggest scope jump in the batch).

**Complexity tier**: 3 (18) → 5 (22). 22 simulates an entire drafting production pipeline (composition → tone → grammar → material → page layout) in one pass.

**Signature moves**: mass/flow-field composition steering both hatch density AND angle; tone-quantized 1/2/3-layer hatching; physical-pixel pen width through a recursive scale chain; page-furniture illusion; corner overshoot + pen-lift gaps as plotter tells.

**Rough edges**: file 20's "But wait! subdivideBox just chops UVs…" comment is the author reasoning out loud about the scale bug in the shipped file — valuable documented negative knowledge about the UV-remap approach. `boxScaleEstimate` in 20 is acknowledged in-comment as an approximation ("if we want it perfect, we'd need to track scale in recursion") — done properly one file later.

---

## Family 4: Tunnelwisp Gyroid Glow Tunnel (day23_01 → day23_02)

**Purpose & visual identity**: Volumetric raymarch through a hollow gyroid lattice accumulating glow (never stopping at a surface), with an independently animated bright "wisp" light. Based on BeRo/Paul Karlik (ShaderToy lineage, credited CC0). Generator, single pass.

**Architecture**: Single pass, no buffers. Glow-accumulation loop (79 iterations default): `z += d + epsilon` march that always runs full length, treating the field value as inverse density rather than a stopping distance.

**Techniques**:
- **Gyroid field**: `g(p,s) = abs(dot(sin(p*s), cos(p.zxwy)) - 1.0)/s` (vec4 variant with `.zxwy` swizzle); shells formed by subtracting two scales: `d = abs(g(p,8) - g(p,24))/4`.
- **Space folding**: `s = q.y + 0.1; q.y = abs(s)` plane-mirror fold, then z-driven rotation `mat2(cos(11.0*U.zywz - 2.0*p.z))` — the compact ShaderToy idiom building a mat2 from one cos() of a shuffled vec4 — twists the lattice into a coherent tunnel.
- **Asymmetric glow accumulation**: `density = max(s>0 ? d : d*d*d, 0.0005); transmission = (s>0 ? 1.0 : 0.1)/opacity_density; o += transmission*col.w*col/density` — inverse-distance glow with a fold-side split (cubed density + 0.1 gain below the mirror plane) that darkens the "floor" reflection.
- **Cosine palette keyed to depth**: `1.4 + 1.8*cos(vec4(1.8,3.1,4.5,0.0) + 7.0*q.z + shift)` — IQ-style palette with the 4th component doubling as a brightness weight (`col.w * col`).
- **Wisp**: independent Lissajous light `1.5*vec2(cos(T*0.7), sin(T*0.9))`, added as `intensity*wispColor/(dist+bias)` after the march — a focal "soul" decoupled from geometry.
- **tanh tonemap + luminance alpha**: `approx_tanh(o/100000)` (manual `(e^{2x}-1)/(e^{2x}+1)` for host compatibility — tanh isn't trusted); `alpha = dot(rgb, vec3(0.299,0.587,0.114))` so black = transparent, making the generator overlay-ready in VDMX.
- **File 02**: zero algorithmic change; every constant exposed as a named ranged INPUT (~45 sliders: iteration count as `long`, zEpsilon, camZ/rayW/timeDiv, per-channel palette base/amp/phase, glowFront/glowBack/backPower/denomEps, all six wisp formula terms, toneMapScale). Also restructures to a `mainImage(out vec4, vec2)` + `main()` wrapper preserving ShaderToy form.

**Control/UI design**: 01 = four "vibe knobs" (Veil Density, Wisp Intensity, Flow Speed, Prism Shift). 02 = total parameterization — the opposite philosophy, a formula turned inside out into a control surface.

**Version evolution**: one step: fixed port → fully externalized constants ("All key constants exposed as sliders").

**Complexity tier**: 2 (01) / 3 (02 for control breadth; algorithm unchanged).

**Signature moves**: inverse-density glow without surface stopping; fold-side asymmetric transmission; luminance-derived alpha for compositing; manual tanh.

**Rough edges**: none significant; 02's slider explosion adds bulk without new range, and its `iterations` uses `long` with a guarded `for(k<200){ if(k>=iterations) break; }` — the const-bound pattern again.

---

## Family 5: Refractive Gyroid Orb / "Pearl" System (day23_03 → day23_12)

**Purpose & visual identity**: The gyroid concept re-architected from a screen-filling tunnel into a camera-orbitable, containable 3D orb — refractive glass volume morphable into an "opalescent pearl," with sphere inversion turning the structure inside-out, full camera rigging, and (by 12) temporal light trails. Ten versions of continuous engineering on one shader; the batch's longest evolution arc.

**Architecture**: Single pass for 03–11 (true map()-based volumetric march with adaptive stepping, distinct from Family 4's fixed-step glow). File 12 goes 2-pass: pass 0 writes a `PERSISTENT: true, FLOAT: true` `trailBuffer` (approximated current-frame glow + advected/decayed previous trail — the batch's only explicit FLOAT feedback buffer), pass 1 runs the full raymarch and composites trails.

**Techniques**:
- **Beer's-law volumetric march**: `map(p,t)` magnitude used both for adaptive step (`t += clamp(abs(den)*0.5, stepMin, stepMax)`) and absorption `exp(-abs(den)*density*8)`; accumulate `col*absorption*stepGain`. Dither (`fract(sin(dot))·0.1`) on the initial t to break banding.
- **Sphere inversion morph** (06+): `sphereInvert(p,R) = p*(R²/dot(p,p))`; `p = mix(p, pinv, m)` continuously flips the structural field inside-out — inversive geometry as a live-performable macro. 09 clamps the scale to 100.0 to stop near-origin coordinate explosion.
- **Containment via smooth boolean**: `smax(core, containD, k)` (built from negated polynomial `smin`) intersects the gyroid with a sphere or spherical band (`sphereShell` blends `r-R` vs `abs(r-R)-thickness`); blend radius k itself morph-interpolated. 06 splits the morph into staggered `mInv = smoothstep(0,0.6,m)` and `mContain = smoothstep(0.4,1,m)` so inversion leads and containment follows.
- **In-march refraction + chromatic aberration**: `if (den<0) rd.xy *= rot(clamp(den,-0.2,0.2)*refraction*0.2)` — fake refraction by bending the live ray with the field value (with clamp added in 05 after instability); `spectral_den = vec3(map(p+rd*chrom), den, map(p-rd*chrom))` for RGB split. 09's changelog explicitly fixes the offset from axis-aligned (`p+chromaticity`) to ray-aligned (`p+rd*chromEff`) — item "[Phase 1: 1.1.3]".
- **Space-warp stack**: torsion (`p.xy *= rot(p.z*torsion)`), crystal fold (`p.xy = abs(p.xy) - fold`), fluid warp (`p += sin(p.zxy*1.5 + t*0.5)*warp`), forward motion (`p.z += t*0.5`) — decomposed into `applySpaceWarps()` in 09 with early-exit when all amounts ~0.
- **Nacre onion shells** (07+, "aesthetic" mode): `onion = abs(fract(r*0.25*nacreFreq + t*0.08) - 0.5) - 0.18; core += aest*nacreStrength*onionBand` — concentric radial bands added to the distance field, drifting outward over time.
- **Skin rendering** (07→10): `skinMask = exp(-|r-R|/skinWidth)` shell proximity × Fresnel rim `pow(1-|dot(N,rd)|, rimPower)`; 10 adds Blinn-Phong specular (`pow(dot(N,H), sharp)`), fake SSS (`exp(-sd/(3·skinW))·(0.5+0.5·dot(N,-rd))`), and pseudo-caustics (`exp(-|den|·5)·(0.5+0.5·sin(|den|·20+T))` projected onto the shell).
- **"Aesthetic" Glass⇄Pearl macro**: one slider retunes ~8 internals via paired `mix()` calls (warp ±, hollow ±, density 0.75→1.65×, chroma 0.6→1.15×, refraction 1.2→0.68×, step gain, skin color cool→warm, tone curve) — the batch's clearest one-knob-many-internals conductor. **"Mutilation" macro** (10+) similarly overdrives torsion/fold/warp/layers/chroma and force-boosts inversion at high values. **"morphDrive"** replaces manual morph with a cosine LFO (`0.5-0.5·cos(2π·T/period)`) shaped by `morphCurve` power.
- **Interior lighting** (10): `estimateNormal` via 3-tap central difference on map() (3 extra field evaluations per lit sample — cost is why it's gated), Lambert + ambient, gated by `surfaceProximity = exp(-|den|·10)`; 12 adds the wisp as a second 3D point light in the diffuse term.
- **Stochastic quality gating** (11): `iterationGate(i, quality, baseFreq)` — smoothstep-shaped probabilistic gate per raymarch step; expensive sub-effects (lighting, chroma, fiber, layers) run on only a quality-scaled fraction of steps, with skipped steps *interpolating from cached values* (`lastLitColor`) instead of dropping to zero. A `qualityMaster` scales seven per-feature quality sliders. A genuinely reusable LOD system for live performance, built branch-light (smoothstep blends, no vector ternaries).
- **Numerical hardening pass** (09, itemized in comments): `custom_tanh` input clamp ±10 before exp; `g()` scale guard `max(s,1e-4)`; inversion scale clamp; interleaved gradient noise (`fract(52.98·fract(dot(p, vec2(0.0671,0.0058))))`) as per-step dither; depth fade `exp(-t·depthFade·0.3)`; adaptive step growth with distance and field emptiness.
- **Trail system** (12): pass 0 deliberately does NOT re-run the raymarch — it approximates current brightness with a cheap screen-space radial glow + wisp proxy (commented "Simplified render — just get the glow areas"), advects the previous trail with a rotational + curl-like warp offset, decays (`·trailDecay`), desaturates old trails toward luma (`mix(vec3(luma), rgb, trailSaturation)`), threshold-gates the feed, clamps to 2.5. Pass 1 composites with a brightness-weighted blend of additive and screen modes.
- **Preset cross-fade** (12): `getPresetParams(float p)` holds 5 named vec4 parameter bundles ("Pristine Glass Orb", "Opalescent Pearl Cathedral", "Fractured Crystal Womb", "Abyssal Inversion Storm", "Ethereal Dream State") and cubically interpolates between adjacent presets on a continuous scrub, blended into the manual params by `presetBlend` — a macro-of-macros performance layer.
- **Temporal AA** (12): sub-pixel jitter of uv from interleaved gradient noise keyed to TIME.

**Control/UI design**: the batch's most distinctive ISF-UI hack: since ISF (in this host) lacks input grouping, section headers are faked with box-drawing characters inside the *first parameter of each group's* LABEL (`"━━ QUALITY ━━━━━━━━━━━━"` — that input is still a live slider whose real meaning is the group's first param), with `●` bullets marking macro/performance knobs and `└` marking sub-params. Grows to ~75 inputs by 12. Note 09/11 use `label`-free grouping; Family 2's file 10 used actual `"TYPE": "label"` dividers — two different solutions to the same problem across the collection.

**Version evolution**: 03 (tunnel→orb rewrite: map()-march, Beer absorption, refraction, chroma split, dither) → 04 (adds torsion/fold/fluid-warp structure controls, relative second gyroid scale `gScaleA*2.5`) → 05 (sphere containment + band mode + full camera: pos/look/FOV/lookBasis; refraction bend clamp) → 06 (sphereInvert inside⇄outside morph with staggered smoothsteps) → 07 (dolly/roll/orbit camera, skin glow + rim, nacre onion, glass⇄pearl `aesthetic` macro, layered interior with modulo-gated secondary gyroid, `morphDrive` LFO, tMax/stepMin/stepMax march controls) → 08 (structured section-header UI reorg; near-identical engine) → 09 ("Phase 1: Foundations & Stability" — decomposition into named field functions, clamps, IGN anti-banding, ray-aligned chroma fix, depth fade, adaptive stepping, toneCurve) → 10 ("Phase 2: Dimensionality & Lighting" — normal-based interior lighting, specular/SSS/caustic skin, pearl fiber anisotropy in spherical coords, `mutilation` macro, sRGB toggle) → 11 ("Phase 2.5: Performance & Quality" — qualityMaster + 6 per-feature sliders, `iterationGate` stochastic gating with interpolated fallback) → 12 ("Phase 3: Transcendence" — 2-pass persistent FLOAT trail buffer, 5-preset cross-fade, temporal AA jitter, wisp as 3D light). The "Phase N" naming plus `// [Phase 1: 1.2]` inline changelog tags show this became a numbered engineering roadmap — a process-rigor step above every other family.

**Complexity tier**: 3 (03) → 5 (08–12). File 12 is unambiguously the batch's most complex single file (~740 lines, 2 passes, ~75 inputs, four interacting macro systems).

**Signature moves**: sphere-inversion topology morph; dual orthogonal conductor macros (aesthetic, mutilation) + preset macro-of-macros; stochastic iteration gating with cached-value interpolation; box-drawing-character section headers; cheap-proxy trail feed decoupled from the expensive render.

**Rough edges**: file 07 (day23_06) and file 08 (day23_07) are near-duplicates — 07 is a label-polish-only diff of 06 ("Inside ⇄ Outside" label), a double-save. 12's `iterations` input silently changed TYPE from `long` to `float` (default 68) — likely a host-compat concession. The trail buffer's pass-0 brightness proxy is knowingly inaccurate (commented as such) because a pass can't read the same frame's later pass — a documented ISF-architecture constraint workaround. 12's comments about "write bright areas to alpha for trail buffer feedback" describe a feedback path that isn't actually wired (the trail buffer never reads the main pass's alpha) — aspirational dead commentary.

---

## Batch synthesis

**Top 3 most sophisticated files:**
1. **AR_Genuary2026_day23_12.fs** (Gyroid Orb "Phase 3: Transcendence") — 2-pass persistent-FLOAT trail system, 5-preset cubic cross-fade, stochastic quality-gated raymarch with interpolated fallback, dual conductor macros, full camera rig, temporal AA; three numbered engineering phases composed without regression.
2. **AR_Genuary2026_day22_17.fs** (with 10 as honorable mention) — endpoint of the BSP/Ising multi-pass system: 10 passes, depth-per-pass dispatch, pathBits leaf enumeration, Ising spatial correlation, persistent max-decay ink accumulation, and the batch's most rigorous itemized culling-radius math. (day22_10 separately packs five distinct chaos algorithms — BSP, pseudo-RD, Ising, L-system, Voronoi — behind one blendable dropdown.)
3. **AR_Genuary2026_day22_22.fs** (Pifragile "Composition + Tone + Grammar") — four rendering concerns stacked in one pass: Gaussian mass fields + curl-noise flow fields steering hatch density AND angle, tone posterization driving 1/2/3-layer hatching, a full plotter-physics material stack, and page furniture (frame/reg-marks/title block) — a complete hand-drafting pipeline simulation with ~65 curated inputs.

**Recurring patterns (style fingerprints):**
- Shared PRNG toolkit: `hash21` (two variants), `hash11`, `nextRand` golden-ratio seed stream, `makeSeed` sin-dot — carried near-verbatim across all five families.
- The vertical order→chaos gradient `pow(smoothstep(start,1,y), curve)` is the unifying compositional device of all Schotter families; later files wire other features (subdivision depth, hollowness) to it via explicit `*_ChaosLink` sliders.
- Conductor-knob design matures visibly across the two days: SEED (trivial) → MODE_Blend → chaos-link sliders → aesthetic/mutilation multi-internal macros → the preset macro-of-macros.
- `1 - smoothstep(-w, w+bleed, abs(d) - penWidth)` with `w=fwidth(d)` is the universal stroke idiom of the plotter families.
- Persistent-buffer feedback appears twice (ink accumulation, light trails), both on the `max(fresh, prev*decay)` / advect-decay-refeed idiom; FRAMEINDEX-based init is notably absent (both rely on decay to self-heal).
- A "final integration / stabilization" file recurs near the end of nearly every family (22_08/09, 22_21, 23_09) — a habit of pausing features to consolidate and re-document.
- Host-quirk scars everywhere: const loop bounds + runtime break for all recursion/iteration; `imod()` for unreliable `%`; manual tanh with input clamps; smoothstep blends instead of vector ternaries; scale/denominator guards (`max(x,1e-6)`) throughout.
- Two competing solutions to ISF's missing input groups: `"TYPE": "label"` dividers (22_10) vs box-drawing characters hijacking the group's first slider LABEL (23_09–12).
- CREDIT fields honestly track AI-assisted lineage (Gemini, ChatGPT, "Conner + Claude") and external sources (Georg Nees, Pifragile, BeRo/Paul Karlik) — the DESCRIPTIONs double as changelogs narrating each version's fix.

**Beyond-ShaderToy techniques:**
- Ising-model ferromagnetic coupling repurposed as a spatial-correlation generator for procedural chaos (patchy rather than salt-and-pepper randomness) — statistical mechanics as an art-direction primitive.
- Sphere inversion (`p·R²/|p|²`) exposed as a continuous live-performable topology morph.
- Stochastic per-iteration quality gating with cached-value interpolation — a bespoke LOD system for live VJ performance well beyond "lower the iteration count."
- Composition-field-driven hatching (mass + curl flow steering density and orientation) — giving a generative system hand-composition-like visual weight distribution.
- Derivative-aware bleed (`fwidth` magnitude as a "geometry is glitching" detector suppressing another effect) — cross-coupling an AA quantity into art direction.
- BSP recursion statically unrolled into one ISF pass per depth level, with leaves enumerated by bit-testing an integer path.

Note: the requested report file was not written (subagent file-write of report .md is blocked); this message is the full report of record.
