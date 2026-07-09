All 44 assigned files have now been read in full. Per the coordinator's instruction, here is the complete report (no file written).

# Batch 07 Analysis Report — AR_Genuary2026_day6 + AR_Genuary2026_day7

## Coverage
- files_assigned: 44
- files_read: 44 (day6: v01–v05, v07–v12 = 11 files; day7: v01–v33 = 33 files. day6_v06 does not exist in the batch list — no miss.)
- misses: none

A key structural discovery: **filename version ≠ internal version.** The `DESCRIPTION` fields carry their own version numbering. day7 file vNN ≈ internal "V(N+3)" up through v20 ("V23"), after which the author **abandons the V18–V23 trunk and forks back to V17**, producing a "V17.x" branch: v21="V17.1", v22="V17.4", v23/v24="Boolean Lattice V1/V2" (clean-slate rewrites), v25="V17.5", v26="V17.6", v29="V17.7" (filed out of order), v27="V17.8 Phantom", v30="V17.8 Host-Proof", v28/v31="V17.9" variants, v32="V17.9.5", v33="V17.9.6". The file sequence is a literal fossil record of a branch-and-revert workflow. Credits shift from "Converted by Gemini" (day6) → "Gemini Hybrid" → "Arson Rivvers + Gemini Hybrid" (v29+), the author claiming co-authorship exactly when he starts porting his own prior "Volumetric Chaos Ultra" feedback engine into the AI-drafted core.

---

## Family 1: AR_Genuary2026_day6 — "Volumetric Neon" (v01–v05, v07–v12; 11 files)

**Purpose & visual identity.** Generator. Two 2D SDF "manifolds" (A and B), each morphable across 15 shapes, interfere with each other; the interference field is shaded with fake-3D lighting and pushed through an LCH-style color-space solver to produce dense, gassy neon with noise-driven chroma grain. Single-object, dark-background, club-visual look.

**Architecture.** Single pass, no buffers, no PASSES block at all. All complexity is in the fragment function: coordinate pipeline (pixel-smash → glitch tear → zoom/rot → curl-noise domain warp) → dual SDF evaluation → interference → normal/lighting → LCH color assembly → post FX stack.

**Techniques.**
- **15-entry SDF morph library with router + fractional crossfade.** Seven iquilezles primitives (circle/triangle/box/pentagon/hexagon/octagon/ring) plus eight bespoke "complex manifolds" (`sdSingularity` = ring with radius-driven rotation `p *= rot(r*4.0 - T*0.5)` plus angular sin ripples; `sdQuantumKnot` = gyroid `sin(x)cos(y)+sin(y)cos(T)` intersected with a sphere; `sdBioBulb`/`sdVoidShard`/`sdArtifact`/`sdCoral` = 4–5-iteration abs-fold Kali-style fractals with per-iteration `rot()` and smin accretion). `get_morphed_dist` does `mix(d1, d2, fract(slider))` between `floor` and `ceil` shape IDs — one float slider scrubs seamlessly through 15 topologies.
- **Seamless interference-operator morphing** — the same floor/ceil/fract crossfade applied to *CSG operators*, not shapes. Five ops: algebraic blend `a - b*a*p + b`, inverted smin, subtraction, symmetric XOR `smin(max(a,-b), max(b,-a), .1)`, and smin with a `sin(a*b*20*p)` moiré perturbation. Blending between *operators* by mixing their scalar results is a distinctive, reusable trick.
- **LCH via inverse-matrix color solve.** Load-bearing snippet:
```glsl
vec3 lch(vec3 c) {
    c.z *= 6.28;
    return max(pow(abs(vec3(c.x, c.y*cos(c.z), c.y*sin(c.z)) * inverse_mat3(m2)), vec3(3.)) * inverse_mat3(m11), 0.);
}
```
  A hand-rolled `inverse_mat3` (full cofactor expansion) inverts two hardcoded matrices (`m11`≈RGB→XYZ-ish, `m2`≈Lab-ish) per pixel. Comments say "RESTORED... Fixes Monochromatic Issue" — evidence an earlier rev pre-inverted constants and broke color. Hue = `.2 + x*0.9` (the interference distance drives hue) plus 2-octave gradient-noise chroma jitter (`control_chroma_split`) — this is what produces the signature "chromatic grain" of the family.
- **Curl-ish domain warp from noise derivative.** `deriv()` central-differences a 2-octave gradient noise and the uv is displaced by it (`uv -= deriv(uv*scale + 1124. + 100.*mod(floor(TIME*30.),10.), .01, 1) * amt`) — the `mod(floor(TIME*30),10)` seed-cycling makes the smoke re-randomize at 30fps in 10-frame loops, a cheap boiling-film-grain trick.
- **2D SDF fake-3D lighting.** `calcNormal` builds a vec3 normal from the 2D field's finite differences with fixed z (`normalize(vec3(dx,dy,e.x*2.))`), then Blinn-ish spec `pow(dot(n,l),10)` and rim `pow(1-n.z,3)` — full "lit object" reads from a 2D distance field.
- **Post stack (v01 only, later dropped):** math-only Bayer 4×4 (`step(1.5, mod(x,2)+mod(y,2))*2 + ...` — branch-free), halftone with tone quantization + `fwidth(L)` ink-bleed edges, bit-depth crush `floor(col*depth)/depth`, audio-driven pixel smash `floor(gl_FragCoord/px)*px`.
- **Wobble via nested sine** `sin(T*s + sin(T*s)) * amt` — non-sinusoidal organic drift added directly to the distance value (inflates/deflates shapes).

**Control/UI design.** 20–34 float inputs. Naming: `control_*` prefix for continuous, `toggle_*` for bools, `invert_click` legacy. v01 has 5 dedicated `audio_*` inputs (Pixel Smash, Glitch Tear, Bit Crush, Liquid Scream, Noise Storm) each additively boosting a different destruction stage — an explicit audio→FX patchbay. From v10 the labels adopt **section prefixes**: `Cam:`, `Geo:`, `Surf:`, `Color:`, `FX:`, `Tone:`/`Master:` — grouping a flat ISF input list into a mixer-console hierarchy purely via label text. Dual-mode design: `control_daylight_fade` (slider) + `toggle_daylight` (switch) driving the same blend, `clamp(fade + switch, 0., 1.)` — a coarse/instant pair.

**Version evolution.** v01: kitchen-sink audio-reactive with full degradation stack. v02: strips audio + degradation ("Pure Geometry") — the author isolating the core. v03: adds Mode B "Studio Light" (white-background physical render of the same field: mask + diffuse + AO + gloss) with a reality-mixer crossfade. v04: Mode B becomes "Crystal Flux" (fake refraction, subsurface `pow(dot(l,-n),2)`, gloss); adds the conductor color params `spec_warp`/`neon_couple`/`therm_flux`; remaps zoom to safe 0–1 range (`0.6 + z*2.4`) — learning to normalize slider ranges for performance use. v05: replaces zoom with camera Depth + **fisheye** (`uv *= 1 + k*dot(uv,uv)*2`). v07: piecewise depth map (through-object −2.0 → close 0.6 → far 12.0 with sign-flip pass-through) + per-shape rotation speed/direction; Mode B becomes "Spectral Void" (inverted color, `fwidth(x)` cyan electric edges). v08: **rotation speed → rotation angle** (0–1 = one turn) — a VJ-mapping decision (LFO-able absolute angle beats unbounded spin); adds Matrix Warp = blending color matrices with their transposes ("distorts the Physics of the color space"), void evolution (erosion threshold moving through the SDF), solarize (`0.5+0.5*cos(col*6.28+phase)`), and analog invert-mix slider. v09: fixes Matrix Warp's "Pink Wash" by replacing transpose-blend with a **rotation of the color vector around the (1,1,1) diagonal axis** (proper hue-twist, structure-preserving). v10 "Pro UI": full label reorganization + Contrast/Gamma master. v11/v12 "Pro Grade": master tone becomes **Lift/Gamma/Gain + filmic S-curve** (`sCurve` sigmoid mix) — colorist-grade output stage; v12 is v11 with performance defaults dialed in (defaults changed only: fisheye 1.0, sizes .4/.8, shine 3.0, contrast .75 — a saved preset as a file).

**Complexity tier: 4.** Single-pass, but a 15-shape × 5-operator morphing SDF system with a custom color-space solver, dual render modes, and a professional grading stage.

**Signature moves.** Fractional index morphing over *both* shape libraries and CSG operators; hue-from-distance-field LCH; noise-seed cycling `mod(floor(TIME*30),10)`; diagonal-axis color-matrix rotation; L/G/G + S-curve tone stack in a VJ shader.

**Rough edges.** Massive duplication — the ~250-line SDF/noise/matrix library is pasted verbatim in all 11 files. `inverse_mat3` computed per-pixel (twice) on constant matrices — significant wasted ALU. Dead code everywhere: `lch_input_B` multiplies noise by `*0.` (a disabled grain input kept for structure), `refr_idx` computed but unused (v04–v05), `solid_core` computed but unused (v09+), `noise(p,int oct)` ignores its `oct` argument (loop hardcoded to 2). `control_color_depth` in v01 has DEFAULT 255 with MAX 32 (out-of-range default). The v03 "restored" comments reveal an AI-roundtrip scar: earlier optimization broke color, fixed by restoring the runtime inverse.

---

## Family 2: AR_Genuary2026_day7 — Tesseract Boolean-Logic Engine (v01–v33; 33 files)

**Purpose & visual identity.** Generator. Two counter-rotating 4D hypercubes (tesseracts) combined with AND/OR/XOR CSG, surfaced with scrolling "data voxel" cuts, rendered as fresnel-glow neon wireframe/hologram, then (from v05 on) fed through a persistent feedback/trail/RGB-split engine. Aesthetic: cyberpunk data-architecture / "Boolean Lattice."

**Architecture.**
- v01–v04: single pass raymarcher (60–80 steps).
- v05 onward: **canonical 3-pass topology** — `PASSES`: `raymarch_core` (non-persistent FLOAT) → `feedback_loop` (PERSISTENT + FLOAT) → unnamed final composite. Pass 1 does edge-detect + trail accumulation into the persistent buffer; pass 2 does chromatic aberration + gamma on the trail buffer. Dispatch is `if (PASSINDEX == 0) ... else if (PASSINDEX == 1) ... else if (PASSINDEX == 2)` in one `main()`.
- v30–v33 add `"MAG_FILTER": "NEAREST", "MIN_FILTER": "NEAREST"` on both targets plus a math-side `snapUV()` — belt-and-suspenders defense against host linear-filtering blur ("Host-Proof Crispness... prevent VDMX/Resolume blur").

**Techniques.**
- **4D SDF + rotor projection.** `sdTesseract(vec4 p, s)` is the box SDF generalized to vec4; the 3D point is lifted (`vec4(p, 0.0)`), spun in the XW plane by `rot4D(t)`, and the SDF of the rotated 4D point is used directly — a cheap "hypercube shadow" whose 3D slice self-intersects and turns inside out as it rotates.
- **Boolean-logic-as-theme CSG router:**
```glsl
float opBoolean(float d1, float d2, int mode) {
    if (mode == 0) return max(d1, d2);           // AND
    if (mode == 1) return min(d1, d2);           // OR
    return max(min(d1, d2), -max(d1, d2));       // XOR
}
```
  The XOR formula itself evolves: v25 tries Stone's-algebra XOR `min(max(d1,-d2), max(-d1,d2))`, and v26 lands on **"Metric Interference"** `abs(d1 - d2) - thickness` — rendering the *equipotential shell where two distance fields have equal strength* as a physical membrane. That progression (CSG-correct → algebraically-correct → visually-correct) is the most instructive arc in the batch.
- **Voxel data engine.** `voxelState(p)`: quantize to grid `floor(p*gridRes)`, scroll `id.z += floor(TIME*dataSpeed)`, hash `fract(sin(dot(id, vec3(12.9898,78.233,37.719)))*43758.5453)`, threshold by `step(1.0 - density, val)`; result both *displaces the SDF* (`geo -= data * depth/gridRes`, greebling) and *drives surface color* (voxel⇒hot white). Later variants: dual-hash-field logic combined per logicMode (v19/v20: `min`, `max`, `abs(b1-b2)` of two binary fields, with per-mode density normalization "OR mode needs way less density"); parity-checkerboard `xorTexture` = `mod(ip.x+ip.y+ip.z, 2.0)` (v22+).
- **Per-voxel disassembly explosion.** `getDispersion(p)`: three independent hashes → normalized random vector per voxel cell; `p -= dispersion * glitchAmt * 0.5` before SDF evaluation shatters the object into flying cells. v09 (internal V11) anchors the tumble rotation *before* dispersion so debris rotates with the body, and multiplies the whole map by 0.6 — an explicitly commented **ray-relaxation fix for concentric-ring overshoot artifacts**, later exposed as the `Ray_Relax` slider (0.1–1.0).
- **Emulated integer ops on ES-safe floats** (the standout beyond-ShaderToy material): `popcount()` via 8-iteration `mod/floor` bit-peel with early exit → **Hamming distance metric** `p = normalize(p) * mix(length(p), (pop(x)+pop(y)+pop(z))*0.15, mix)` — space itself re-metrized by bit-counting, producing discrete fractal shells; `emulatedXor()` (v23) reconstructs true bitwise XOR by 4 rounds of per-bit parity accumulation to grow a **Sierpinski lattice**; `binaryClock(freq) = mod(floor(TIME*freq),2)` square waves used as NAND gates to gate glitches (`1.0 - clkA*clkB`). v22's header says it all: "Replaced unsupported bitwise operators with floating-point parity logic for universal compatibility" — a direct host-limitation workaround.
- **Metric morphing:** `mix(euclidean, chebyshev, Metric_Mix)` re-normalizing p — spheres become cubes as the distance metric glitches; kaleidoscopic IFS `Space_Folds` (`p = abs(p) - 0.2*size; rot; rot` in a const-bounded loop driven by `int(Space_Folds)`); domain repetition `Space_Slices` (`mod(p+s/2, s)-s/2`).
- **Feedback pass (the Chaos engine):** edge detection on the raymarch buffer (vector `length()` gradient early; v29 ports "TRASHY EDGE DETECTION (SCALAR)" — `abs(r-r)` channel differences, "Crunchy instead of Smooth" — plus `C = mix(C*4.0, prev, decay)` **overdrive**: input hammered 4× into the trail so `Feedback_Decay` near 1 burns and blooms); **self-advected trails** — flow vector from screen-space derivatives of the *previous frame itself* (`vec2(dFdx(prev.r), dFdy(prev.r)) * flow_force`), so trails melt along their own luminance gradient; `Feedback_Decay` range deliberately crosses 1.0 (0.8→1.01/1.05) with a clamp guard, letting the loop sit at the edge of blow-up; v33 adds **inverted physics** — compute in "energy space" `1.0 - C`, run the same decay, re-invert: darkness eats light on a white field.
- **Retro stack:** UV res-crush `floor(uv*grid)/grid` *before* raymarch (quantizing rays, not pixels — genuinely different look), Bayer 4×4 via `float M[16]` array with const-index workaround, bit-depth `floor(col*steps)/steps`, scanlines, distance-curved RGB split `center*(1 ∓ warp*pow(dist, curve))`.
- **Fresnel-only lighting:** `pow(1.0 - dot(n,-rd), Fresnel_Power)` × glowPower + voxel hot-mix; v30+ replaces normals entirely with **depth-based brightness** `5.0/(t*t*0.1+0.5)` — cheaper, and gives the fog-attenuated hologram look.
- **v27 "Phantom Mode" volumetric accumulation:** replaces hit-test with per-step glow gathering `acc += base * (0.02/(abs(d)+0.005)) * fade`, stepping by `max(abs(d)*0.6, 0.05)` — `abs(d)` lets the camera fly *through* solid geometry without freezing (explicitly commented: "abs(d) ensures we don't get stuck if d is negative (inside)... MIN_STEP prevents black freeze"). v28 hybridizes: `Phantom_Blend` crossfades solid-hit rendering and volumetric accumulation in a single 80-step loop, with a hard `break` only when `Phantom_Blend < 0.05`.

**Control/UI design.** Grows from 7 inputs (v01) to ~50 (v14+). Conventions: emoji-tagged event button `"🔴 PANIC RESET"` / `"🔴 --- MACRO RESET ---"` (event + `Force_Reset` zeroing the persistent buffer — the standard ISF feedback escape hatch); `long` dropdowns with semantic LABELS (logic modes, mirror modes); label section prefixes `Macro:/Form:/Space:/Data:/Glitch:/Cam:/Light:/Retro:/FB:/Final:`; `Seed` slider for RNG re-rolls. The headline UI invention is the **emoji MACRO conductor row** (v15+): `🔥 ENTROPY, 🔮 HYPER, 📼 VHS, 🪞 DOPPELGANGER, 💀 DATA ROT, 🩸 NIGHTMARE` — six one-knob scene morphs, each additively cross-modulating 4–8 internal parameters (ENTROPY → glitch+dataSpeed+snap+ray-noise; VHS → res-crush+dither+bit-depth+RGB-split; ROT → time-stutter `floor(TIME*(10-rot*9.5))` + voxel decay + boolean-mode strobe + forced sharpness; NIGHTMARE → palette swap + uncapped feedback `decay=1.0+n*0.05, clamp=500` + spinning composite lens). This is the author's performance philosophy in code: expose everything, then add one-gesture composite controls on top.

**Version evolution (the learning trajectory).**
1. v01–v04 (V4–V7): single-pass exploration — boolean tesseracts, circuit etch → fluid etch → fresnel traces → voxel greeble + glitch bands + color quantize.
2. v05/v06 (V8): grafts the author's Chaos feedback engine on → 3-pass PERSISTENT architecture; v06 immediately parameterizes hardcodes (voxel_density, cam_zoom, color_steps, flow_force) — "expose the magic numbers" reflex.
3. v07–v09 (V9–V11): 3D voxel explosion; hash artifact fix (raw `sin()` → `fract(sin())*2-1` normalized); rotation anchoring + ray relaxation to kill ring artifacts.
4. v10–v12 (V12–V14): "Unlocked Master / Kinetic Maximalist" — every internal constant becomes an input (tumble axes split, Seed, Fresnel_Power, all colors, Feedback_Clamp, Edge_Width, FOV, Chrom_Ab_Curve); adds Space_Folds/Metric_Mix/Space_Slices, roundable tesseract, smooth Geo_Invert.
5. v13/v14 (V16/V17): Quantize_Motion — hybrid smooth/stepped data flow `mix(rawTime, floor(rawTime), snap)`; then the first three MACROs. **V17 becomes the stable trunk.**
6. v15–v20 (V18–V23): macro maximalism (6 macros with cross-modulated "demented" interactions), then three consecutive *defect-fix* releases whose headers are a QA log: V19 "Zero-Point Fix. safety thresholds so 0.0 means ABSOLUTELY zero effect" (macro bleed at rest — critical for VJ default state), V20 "Clean Start Fix. Forces black buffer on Frame 0" (`FRAMEINDEX == 0` guard — the canonical ISF feedback init bug), V21 "Zero-Feedback Fix. Unlocked Decay range to allow 0.0". V22/V23 unify logicMode across geometry+voxels+feedback blending with smart density normalization.
7. v21–v33 (the V17.x branch): abandons V18–V23, restarts from V17 and pursues *math-driven* novelty: Hamming metric (V17.1), parity-XOR + binary clocks after bitwise-operator compile failures (V17.4), clean-slate "Boolean Lattice" rewrites (v23/v24: emulated XOR Sierpinski, **Hasse sedimentation** — voxel existence probability ramped by world-Y "Bottom = Empty Set, Top = Universal Set", **fuzzy logic** — every `step()` replaced by `smoothstep(±Logic_Fuzz)` so truth values become continuous and color intensity tracks partial truth, CRT scanlines, `max(current, prev*decay)` light-accumulation feedback), reintegration into the trunk (V17.5/V17.6), the author's own Chaos-engine port with scalar "trashy" edges + 4× overdrive (V17.7, first "Arson Rivvers" credit), volumetric Phantom mode + hybrid blend (V17.8/V17.9), host-proofing (NEAREST filters + snapUV), wireframe-only "Data Skeleton" via `Fill_Opacity` defaulting to 0, feedback re-wiring so every FB slider verifiably does something (V17.9.5), and inverted feedback polarity (V17.9.6).

**Complexity tier: 5** (v12 onward). Multi-pass persistent simulation/feedback system, 4D geometry, ~50 inputs organized under macro conductor controls, host-quirk armor.

**Signature moves.** Metric-interference XOR (`abs(d1-d2)-thickness`); float-emulated popcount/XOR/binary-clock suite; Hasse-gradient probability sedimentation; fuzzy-logic smoothstep truth; emoji macro row with additive safety-gated cross-modulation; self-advected overdriven feedback (`mix(C*4, prev, decay)` + dFdx flow); Phantom `abs(d)` fly-through marching; NEAREST+snapUV host-proofing; PANIC RESET event convention.

**Rough edges (useful negative knowledge).**
- `mod_*` global float block (11 variables) declared in v14 and cargo-culted through every V17.x file — never written or read. Pure dead weight.
- The V18–V23 trunk is an abandoned direction preserved on disk; DOPPEL/ROT/NIGHTMARE macros and unified-logic feedback never made it into the surviving branch.
- `dFdx/dFdy` on a *sampled texture value* in the feedback pass is formally undefined-ish/host-dependent (works on Metal, quad-granular) — a quirk the author rides rather than fixes.
- Numerous computed-but-unused values persist (`solid_core`, `uvn` quantized then unused in v29–v33 pass 0, `hit` in volumetric v27, `Interference_Speed` overridden by `+1.0` constant in v26+).
- Repeated safety-threshold churn (`>0.01` → `>0.05`) across v15–v17 shows threshold guards being tuned by observed misbehavior, not principle.
- Bayer matrix as a 16-element `float M[16]` with immediate constant indexing — a GLSL-ES const-array workaround kept verbatim in 25+ files.
- Header/body drift: several headers advertise features ("Hasse Vertical Sorting... CRT Phosphor" in files where scanlines exist but Hasse is hardcoded, or v20's Voxel_Size listed but some variants still deriving gridRes differently) — headers are marketing for the rev, code is truth.

---

## Batch synthesis

**Top 3 most sophisticated files.**
1. **AR_Genuary2026_day7_v33.fs (V17.9.6)** — terminal state of the tesseract engine: 4D CSG + parity voxels + Hamming metric + fuzzy logic + Hasse sedimentation + host-proofed NEAREST feedback with polarity-invertible physics (dark-eats-light energy-space computation) and fully re-wired manual FB controls. Every subsystem in the 33-file lineage survives here in its debugged form.
2. **AR_Genuary2026_day7_v24.fs (Boolean Lattice V2)** — the cleanest *idea* file: emulated-XOR Sierpinski lattice, Hasse vertical probability sorting, fuzzy-logic smoothstep truth with intensity-as-truth-value coloring, NAND time faults, `max()` light-accumulation feedback — discrete-mathematics-as-aesthetic, written from scratch rather than accreted.
3. **AR_Genuary2026_day6_v12.fs** — the day6 endpoint: 15-shape/5-operator dual-manifold morph system, inverse-matrix LCH color with diagonal-axis matrix rotation, void-erosion/solarize FX, and a Lift/Gamma/Gain/S-curve colorist output stage — the most sophisticated *single-pass* file in the batch, shipped with performance defaults baked in.

**Recurring patterns across families.**
- The `fract(sin(dot(id, vec3(12.9898, 78.233, ...)))*43758.5453)` hash as the universal RNG; floor/ceil/fract **fractional-index morphing** through discrete libraries (shapes, operators); label-prefix sectioning (`Cam:`, `Geo:`, `FB:`...) as the substitute for ISF's missing UI groups; slider+toggle coarse/instant pairs; `Force_Reset` event + `FRAMEINDEX==0` clear for persistent buffers; bit-depth `floor(col*n)/n` and math-only Bayer dithering in both families; "expose the magic number next rev" as the dominant evolution operator; version headers used as changelogs (each DESCRIPTION states what problem the rev solves).
- Workflow fingerprint: AI-drafted cores ("Converted by/Synthesized by Gemini") iterated ~10–30 revisions with the author's judgment expressed through parameterization, range normalization, zero-state safety, host-proofing, and eventually porting his own earlier engines in ("Arson Rivvers + Gemini Hybrid").

**Techniques beyond standard ShaderToy fare.**
- Discrete-math rendering: float-emulated popcount → **Hamming-distance space metric**; carry-aware emulated bitwise XOR → volumetric Sierpinski; parity checkerboards; binary-clock NAND gates driving glitch scheduling.
- **Metric interference XOR** (`abs(d1-d2)-thickness`) — rendering the equipotential membrane between two SDFs.
- **Hasse-diagram sedimentation** and **fuzzy-logic truth hardness** as voxel-density laws — lattice theory and fuzzy logic as literal visual parameters.
- Feedback trails advected by derivatives of the feedback buffer itself, with deliberate >1.0 decay overdrive and a NIGHTMARE macro that intentionally detonates the loop under a 500.0 clamp.
- Host-quirk armor as a designed feature set: `FRAMEINDEX==0` buffer init, `MAG_FILTER/MIN_FILTER: NEAREST` + math-side `snapUV()` double defense, zero-point macro guarantees, PANIC RESET events — VDMX/Resolume production hardening you never see in ShaderToy ports.
- Per-pixel runtime `inverse_mat3` LCH color solving with hue driven by the SDF value (day6) — color space as part of the generative system, not a palette lookup.
