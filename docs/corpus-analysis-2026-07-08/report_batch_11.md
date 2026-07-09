## Coverage

- files_assigned: 44, files_read: 44, misses: none
- Note: `AR_Genuary2026_day17_03.fs` is 1674 lines and required two paged reads (completed in full). All other files read in a single pass.
- Filename-to-content mapping note: the three "Hyper-Archive" builds (16.0/17.0/18.0) occupy the last three list slots (day16_11 boundary vs day17_01 is the only spot where title-to-filename alignment is ambiguous by one; content lineage is unambiguous and reported by lineage below).

## Per family

### Family 1: "Everything Fits Perfectly (Enhanced)" — day14_v01
- **Purpose & visual identity**: Fully-featured Gray-Scott reaction-diffusion generator with freeze zones, temporal pulsing, and flow advection. Generator.
- **Architecture**: 4 passes — `chemBuffer` (PERSISTENT+FLOAT, sim), `chemBuffer2` (PERSISTENT+FLOAT, declared ping-pong copy), `edgeBuffer` (non-persistent edge/fitness pass), final composite. PASSINDEX dispatch with early `return` per pass.
- **Techniques**:
  - Gray-Scott with 9-point Laplacian (0.2 cardinal / 0.05 diagonal weights), Euler integration, `FRAMEINDEX < 2` init.
  - **Anisotropic diffusion**: per-neighbor weights biased by a flow direction vector — `wN = 0.2 + anisotropy * 0.15 * max(0.0, flowDir.y)` etc., with diagonals getting combined-component bias. Directional pattern growth.
  - **Curl-noise advection**: central-difference curl of value noise added to the sample offset (`flowOffset += curl * turbulence * px * 3.0`), i.e. the RD state is advected through a turbulent field by biasing the history lookup.
  - **Freeze zones**: spatial mask (circle/square/band shapes, invertible, animatable radius) multiplies the local time step — parts of the sim literally run slower. `mix(1.0 - freezeStrength, 1.0, smoothstep(r*0.7, r, dist))`.
  - **Temporal pulse**: sinusoidal LFO optionally made a *spatial wave* (`phase -= length(uv-0.5) * scale * TAU`) modulating feed/kill/diffusion — RD parameters as beat-synced modulation targets.
  - Seed hue stored in the buffer's blue channel at init and carried through the sim for colorization.
  - Edge pass computes gradient magnitude plus **local variance "fitness"** (sum/sumSq over 5 taps) visualized as a stability heat overlay.
  - Colorization: HSV complementary/triadic modes + 3-color custom gradient; standard gamma/vignette/grain post.
- **Control/UI design**: ~50 inputs organized with the author's signature **fake-slider separators** (`"NAME": "SEPARATOR_FLOW", MIN=MAX=0, LABEL "─── FLOW CONTROL ───"`). Dual-mode UI: `simpleMode` bool maps 3 macro knobs (harmony/complexity/emergence) onto f/k/diffusion internals; advanced mode exposes raw params + named f/k presets (Mitosis/Coral/Maze/Spots/Worms). `reset` event, `pause` bool, iteration multiplier dropdown.
- **Version evolution**: standalone within this batch (relative of the DataLoss/video-flow RD line).
- **Complexity tier**: 5 — multi-pass sim, conductor controls, spatial modulation systems.
- **Signature moves**: freeze-zone local timestep; simple/advanced dual mode; curl-advected RD.
- **Rough edges**: `chemBuffer2` is declared but never sampled (dead ping-pong scaffold); pass 1 is a pure copy that wastes fill rate.

### Family 2: Gray-Scott strobe experiments (day14_v02–v04)
- **Purpose & visual identity**: 1-bit black/white RD generators where strobing perturbs the chemistry. Generators, hard-thresholded output for the author's "bit-crushed" look.
- **Architecture**: 2 passes each (`rdBuffer`/`chemicalBuffer` PERSISTENT+FLOAT + output). In-shader iteration loop `for (i<30) { if (i >= iterations) break; }` — the const-bound/runtime-break idiom.
- **Techniques**:
  - **v02 Bridge symmetry**: a coordinate transform that mirrors the right half onto the left *during simulation sampling* (`uv.x = 2.0*axis - uv.x` with optional smoothstep blend band), forcing two RD wavefronts to collide at the axis — a "standing wave" artifact engineered on purpose. Bridge force multiplies the Laplacian in a ±0.02 band around the axis.
  - **Strobe-driven chemistry**: `fract(TIME*Hz) < PWM` gates a two-phase regime — white phase multiplies feed (`f *= 5.0`), black phase adds kill and crushes feed (`f *= 0.02`) — inside SDF-defined zones (v02/v03: `sdBox` rects) or globally (v04). The strobe is a chemistry actuator, not a brightness flash.
  - Tunnel zoom: history sampled through `(uv - center)/scale + center` so the pattern perpetually flows inward.
  - Radial 6-fold symmetry fold (`mod(angle, TAU/6)` + reflect); Bayer 2x2 ordered dithering added to the threshold (v02).
  - Manually unrolled neighbor arrays (`vec2 offsets[8]; float weights[8]`) for the bridge-aware Laplacian.
- **Control/UI design**: 20–35 flat inputs, `LABEL`ed; per-zone position/size params; `reset` event. Comment scars: "FIXED: Using texture2D" (host quirk: `IMG_NORM_PIXEL` vs `texture2D` interchange).
- **Version evolution**: v02 (bridge collision) → v03 (rectangular strobe zones, presets) → v04 (same file with zones stripped to full-frame strobe — simplification pass).
- **Complexity tier**: 4.
- **Signature moves**: strobe-as-feed/kill modulation; forced symmetry collision.
- **Rough edges**: v03/v04 compute the Laplacian once *outside* the iteration loop then iterate the reaction — physically wrong (diffusion frozen across sub-iterations) but visually accepted; near-total duplication between v03 and v04.

### Family 3: Digital Crystal RD lineage (day14_v05–v11, v14–v18) — the heart of day 14
- **Purpose & visual identity**: Evolving series of hard-thresholded, 1-bit "digital crystal" reaction-diffusion generators with square/diamond growth geometry, inward feedback flow, and increasingly deliberate numerical instability. Generators; v12–v13 fork into filters (below).
- **Architecture**: The defining move is the **8-buffer ping-pong chain**: `bufferA..bufferH` all PERSISTENT+FLOAT plus output (v05 adds `historyBuffer` for velocity). Pass 0 reads H with the feedback transform; passes 1–7 each read the previous letter; `iterationsPerFrame < N` short-circuits a pass into a pure copy — a variable-iteration sim built from fixed ISF passes. This is the author's answer to ISF having no compute loops: **unrolled iteration as pass topology**.
- **Techniques**:
  - **Geometry-mode Laplacian kernels** (v09+): dropdown selects the diffusion stencil itself — Round (0.2/0.05 9-point), Square (0.25 cardinal only), Diamond (0.25 diagonal only), Cross (0.4 cardinal − 0.15 diagonal, an unsharp/sharpening kernel). Changing the kernel changes the crystal habit: circles vs squares vs 45° diamonds vs spiky axial growth. Matching distance metric `getGeometryDist` (Euclidean / Chebyshev `max(d.x,d.y)` / Manhattan `d.x+d.y` / `min`) used for seeding so seeds match the growth geometry.
  - **Feedback transform**: polar zoom+rotate+twist on the pass-0 read (`a += rotate + twist*r; p /= (1.0 - zoom)`) with clamp/wrap/mirror edge modes (v05), then 4-way symmetry via `abs(uv - 0.5) + 0.5`.
  - **Border strobe injection** (v11+): border pixels are hard-written as chemical sources — strobe ON returns `vec4(0,1,0,1)` (pure B), OFF returns `vec4(1,0,0,1)` (empty) — so the frame edge rhythmically pumps crystal into the inward flow. Combined with a "Final Safety Mask" that blacks the same border in the render pass.
  - **Deliberate destabilization suite** (v15–v18, the learning trajectory's most original stretch): `reactionPower` exposing the exponent in `a * pow(b, p)` labeled "(Danger)"; `laplacianCenter` (1.8–2.2) detuning the center weight of the Laplacian so mass is not conserved; `driftX/driftY` asymmetric neighbor weights `e*(1+drift) + w*(1-drift)` producing directional smearing; `gridCrush` quantizing the *sampling* grid (`floor(uv*seg)/seg`) so the sim runs on a coarser virtual lattice; `kernelStride` widening neighbor distance for blocky growth; `symFold` moving the mirror fold point off 0.5 ("broken mirror"); `biasY` making feed/kill a vertical gradient; `feedLimit` replacing the `(1.0 - a)` saturation ceiling; anisotropic per-axis diffusion `diffA_X/diffA_Y/diffB_X/diffB_Y` via split `lapX/lapY`.
  - Split time scales (v14): chemical A and B integrate with independent dt (`timeScaleA`/`timeScaleB`) — background and crystal move at different speeds.
  - `strobeShove`: strobe pulse temporarily adds to zoom, physically shoving the whole field inward on the beat. `strobeInvert` flips output polarity on-pulse.
  - Output modes (v05): threshold / smooth / chemical-A / both / **velocity** (`abs(B - prev.g) * 10.0` against historyBuffer).
- **Control/UI design**: 20–45 inputs; ultra-compact one-line JSON per input (a formatting fingerprint of this lineage); short labels ("Feed (f)", "W1", "Hz1"); parenthetical warnings in labels ("Reaction Power (Danger)", "Laplacian Focus (Stability)"). `CREDIT: "User & Gemini"` — explicitly LLM-collaborative authorship.
- **Version evolution**: v05 kitchen-sink 8-pass "Ultimate" → v06/v07 corner/center square-seed "crystal/pyramid" looks → v08 **"Ground Up"** total rebuild at ~110 lines (deliberate reset to a minimal core) → v09 re-modularized (named bugfix: `buffer`→`buf` sampler arg) → v10 adds rotate/twist + border safety → v11 strobe injection → v14–v18 progressive instability engineering. The arc is: accumulate features → hit complexity wall → rebuild minimal → re-grow with better architecture → then mine *instability itself* as the aesthetic.
- **Complexity tier**: 5 — 9–10 pass simulation systems with kernel-level controls.
- **Signature moves**: iteration-as-passes; kernel-shape dropdown; border-as-chemical-source strobe; "danger sliders" exposing solver internals as performance controls.
- **Rough edges**: v16 (`v8 Digital Artifacts`) contains a remarkable fossil — ~25 lines of in-comment self-debate ("Wait, we need to pass the diff variables... Let's fix this to be correct... Optimization: Let's inline") plus a dead `computeLaplacian` call whose result is discarded before the inlined recalculation. Internal version numbers skip (no v10 header; file v18 is "v11") — version drift between filename and title.

### Family 4: Reactive Flow Crystal (day14_v12–v13)
- **Purpose & visual identity**: The Digital Crystal engine converted to a **video filter** — webcam/clip luma feeds the RD feed rate. Filter.
- **Architecture**: same 8-buffer ping-pong + output; `videoInput` image input.
- **Techniques**: video luma (`dot(rgb, vec3(0.299,0.587,0.114))`) added to feed per-pixel (`currentFeed = u_feed + luma * u_videoFeed`) so bright image regions grow pattern; `resolveParameters()` global-variable pattern implementing simpleMode macro mapping (flowSpeed→diffusionB+dt, textureAmt→f/k, tone→video influence + a hand-tuned RGB color response); output blend modes (color-blend over source / threshold B/W / raw chemicals). v13 replaces per-pixel border strobe with a **global chemical strobe** (`step(0.5, fract(TIME*Hz)) * intensity * 0.1` added to feed).
- **Control/UI design**: simpleMode + 4 macro knobs mirroring v01's philosophy; mirrorX for camera input.
- **Version evolution**: v12 border-strobe filter → v13 global chemical strobe (zone → field).
- **Complexity tier**: 4.
- **Signature moves**: video-luma-as-feed-rate; generator→filter conversion of an existing engine.
- **Rough edges**: `resolveParameters()` called per-pass redundantly; strobe border writes fight the video drive at edges.

### Family 5: Shock City Cellular Temple EXTENDED (day14_v19)
- **Purpose & visual identity**: Maximalist strobing B&W cellular-automata "temple" — layered CA with polyrhythmic strobes, moiré interiors, diamond symmetry. Explicitly modeled on Eye (Boredoms) visual feedback. Generator.
- **Architecture**: 5 passes — `feedbackBuffer`, `secondaryBuffer`, `tertiaryBuffer`, `ageBuffer` (all PERSISTENT+FLOAT) + composite. Three CA layers run in parallel with cross-coupling.
- **Techniques**:
  - **Rule dropdown**: Standard growth / Game of Life / Brian's Brain (3-state via 0.0/0.5/1.0 encoding) / Seeds — all driven from a shared `Neighborhood` struct (cardinal/diagonal max+sum + Sobel gradient) sampled per layer.
  - **Polyrhythmic strobe**: four `step(1-width, fract(t*rate))` pulses at ratios ×1, ×0.666, ×1.5, ×0.25 max-combined — Euclidean-rhythm-flavored gating of CA birth.
  - **Layer XOR coupling**: `abs(cellState - secondary)` between layers mixed in by `xorFeedback` — layers erase/interfere with each other; layers 2/3 run at phase-offset times and layer 3 uses `mod(rule+1, 4)` (a different rule).
  - **Age buffer**: per-cell age accumulates while alive (`+0.01`, decay `-0.02`) and biases the output threshold — old growth reads differently from fresh.
  - Grid-quantized coordinates with **breathing modulation** (3 stacked sines on grid size), symmetry dropdown incl. octagon-distance, hex-distance, and a "Broken" mode that hash-glitches the mirror; interior moiré texture from three multiplied sines at ×1.37/×0.73 detuned frequencies plus time-scrolled interference; block-row glitch displacement.
  - Struct-based neighborhood sampling with the comment scar "is a macro that relies on specific uniform names that don't exist for a function argument" — evidence of a macro→function refactor forced by the backend.
- **Control/UI design**: 28 verbose multi-line inputs (older formatting style), dropdowns for rule/symmetry/color mode. No reset event (init relies on decay/strobe re-seeding).
- **Version evolution**: single "EXTENDED - maximum complexity" build.
- **Complexity tier**: 5.
- **Signature moves**: multi-layer XOR-coupled CA; age-aware thresholding; polyrhythmic strobing.
- **Rough edges**: `% operator` replaced with `mod()` "for compatibility" (GLSL ES scar); `fractalDepth`, `ringExpansionRate` partially or un-used; layerCount is a float used as a threshold.

### Family 6: Wireframe Feedback Cube (day14_v20, day15_v01–v09)
- **Purpose & visual identity**: Retro rotating wireframe polyhedra XOR-accumulated into a persistent feedback buffer — hollow, banded, screen-burn trails. Generator (Shadertoy port, credited Chris Long).
- **Architecture**: matured to 4–5 passes: `TimeBuffer` (PERSISTENT, 1-pixel time accumulator), `BufferA` (non-persistent fresh geometry render), `BufferB` (PERSISTENT feedback), `BufferDisplay` (PERSISTENT frame-skip latch), main output.
- **Techniques**:
  - **TimeBuffer pattern** (v01+): accumulated time stored in a persistent buffer pixel — `new_time = IMG_PIXEL(TimeBuffer, vec2(0.5)).r + TIMEDELTA * speed` — giving click-free speed changes and true pause, decoupled from host TIME. A reusable ingredient for any speed-controllable animation.
  - CPU-style 3D: 8/12/16 vertices via `getVert` functions (bit-decode via `mod(floor(f/2^k), 2.0)` since no bitwise ops), mat3 rotations, perspective divide `1.0/(camDist - z)`, capsule-SDF line rendering with optional `fwidth`-based AA and Gaussian glow (`exp(-d*d*(10.0/radius))`).
  - **XOR feedback**: `mod(img0.rgb + img1.rgb, 2.0)` — overlapping trails annihilate to black, the family's signature hollow-trail look; grown into 10 blend modes (additive, max, difference, average, sine "Interference ripples", solarize, exclusion, hard-edge, and "Living (GOL)").
  - Pixelated feedback sampling: `floor(coord/pixel_size)*pixel_size + 0.5` (center-of-block; the +0.5 is a documented fix), later split into independent X/Y block sizes.
  - **Frame-skip strobe**: BufferDisplay only refreshes when `mod(FRAMEINDEX, N) == 0`, else re-latches itself — temporal downsampling as an effect.
  - **"Digital Rot"** (v08–v09): when speed≈0 (frozen), a probabilistic decay CA eats the frozen trails — rot chance = edge-distance smoothstep + structural-integrity term `(1 - neighbors/4)`, with squared slider for fine low-end control. Freezing the piece makes it decay.
  - **Living (GOL) blend** (v08+): feedback read through a sine warp field, 5-tap density rule (`0.2<d<0.9 → grow ×1.05`) turning trails into a crawling organism.
  - Multi-geometry (v06+): Merkaba (two tetrahedra), Tesseract (nested cube + struts), Icosahedron with **edge detection by 3D distance** (`abs(dot(p1-p2,p1-p2) - 4.0) < 0.1` over all vertex pairs) instead of hardcoded topology.
- **Control/UI design**: This family develops the author's **`"TYPE": "label"` section headers** (`"== MASTER CONTROL =="`, `"== FEEDBACK LOOP =="` etc.) — 40+ inputs organized into titled panels. Split unidirectional pairs for MIDI-friendly control: `zoom_in`/`zoom_out`, `rotate_left`/`rotate_right`, `shift_up/down/left/right` (each 0..1, differenced in code). `clear_feedback` bool as reset.
- **Version evolution**: v20 raw port → +TimeBuffer speed → +asymmetric pixelation → +full artistic controls (labels, glow, AA, depth fade, blend modes) → freeze-fix (hold feedback when speed<0.01) → multi-geometry → more blend modes → Digital Rot + GOL → split shift controls. Clean incremental feature-growth trajectory with two explicit bug-fix releases.
- **Complexity tier**: 4 — multi-pass feedback system with state machine, though the sim is simple.
- **Signature moves**: TimeBuffer; XOR mod-2 feedback; frame-skip latch pass; rot-when-frozen.
- **Rough edges**: v06's depth fade collapses to a bogus whole-shape multiplier (`clamp(1.0/(abs(proj[0].y)...))`) — fixed properly in v07 by passing z per line; Icosahedron re-derives vertex positions inside the double loop per fragment (expensive); duplicated pulse computation in main and rdStep-equivalents.

### Family 7: IQ Cellular Automata fork (day15_v10, day16_01)
- **Purpose & visual identity**: Port of an Inigo Quilez cellular automaton (angular, circuit-like dendritic growth) with parameters exposed; second version adds decay trails. Generator.
- **Architecture**: 1–2 PERSISTENT+FLOAT buffers + display.
- **Techniques**: 3-state cells (0/1/2) in the red channel; probabilistic update mask from block-quantized hash (`q2 > updateDensity`); anti-clumping death rules (any two adjacent diagonal or orthogonal-pair neighbors kill); distance-2 lookahead suppression; robust `Cell()` lookup with mod-wrap + center-of-pixel sampling ("Fixes black screen issues" — a host scar); trail pass `max(sim, prev * trailDecay)` — the max-decay accumulator idiom.
- **Control/UI design**: 7–8 flat inputs, tint color, reset event.
- **Version evolution**: exposed-params port → +trails buffer.
- **Complexity tier**: 2–3.
- **Signature moves**: the wrapped center-sample `Cell()` helper reused throughout day16.
- **Rough edges**: `FRAMEINDEX == 0` init (not `<2`) — inconsistent with the author's usual guard.

### Family 8: Living Grid / The Spore (day16_02–day16_10)
- **Purpose & visual identity**: The batch's most ambitious original system: a cellular automaton grows across a **recursive L-system/BSP grid**, and the rendered architecture (grid lines, dithered fills) is *revealed* only where the organism has been. Blueprint-becoming-alive aesthetic. Generator.
- **Architecture**: 2 buffers (sim + territory/history) + render, growing to Spore v2's 4–5 passes: `gridField` (cached L-system field: edge-dist/depth/cellHash/containerMask packed into RGBA), `simBuffer` (CA/RD hybrid), `trailBuffer`, `bloomBuffer` (non-persistent Kawase-style blur), composite.
- **Techniques**:
  - **GLSL struct L-system**: `GrammarRule {divisions, scale}` + `HierarchicalState {cellID, cellUV, cellUV_Global, depth, lineWeight, totalScale}`; 8–9 grammar rules (binary, golden-ratio H/V, alternating Mondrian, silver-ratio/A-series, random 2x3, Fibonacci-ish, chaotic, rotated) chosen per cell; probabilistic recursion stop (`hash > continueProb`) so subdivision depth varies organically.
  - **Bounding-box tracking through recursion**: `currentCellOrigin += childID * currentCellSize; currentCellSize /= divisions` so the final leaf's *global center* is known — used to sample the sim buffer once per cell ("BRIDGE"), making whole architectural cells light up as units rather than per-pixel.
  - **Territory mask**: slow-decay history buffer gates line rendering (`cellLines *= smoothstep(0.01, 0.2, territory)`) — the grid literally draws itself where growth has passed.
  - **Attractor field** (Living Grid): `exp(-d * 3.0/radius) * strength` field constrains both CA birth *and* L-system recursion depth — a spatial conductor.
  - **Virtual-resolution sim** (`simPixelSize`): all neighbor lookups computed on a block-quantized lattice (`Cell()` maps virtual coords → block-center pixels) — decouples sim resolution from render resolution, with careful aspect-corrected snap-back in the render pass (the bug the family spends 3 versions fixing).
  - Resolution-adaptive line weight: `lineWeight = 2.5 * (gScale / RENDERSIZE.y)` targeting ~pixels, thinned 0.8–0.9× per depth — fixed a disappearing-lines bug.
  - Spore v2: CA/RD **hybrid growth mode** dropdown (CA / Gray-Scott diffusion / both), grid-edge distance as a diffusion barrier (`gridBarrier` multiplies Du/Dv — architecture constrains chemistry), animated Voronoi domain distortion of the grid, 9-tap two-radius bloom, ACES tonemap, `expandMidtones` curve, and in the final variant **per-channel chromatic aberration** where the *entire composite* (grid+trail+bloom) is recomputed at three offset UVs so even the linework fringes.
  - Age-curved palettes: `pow(v, 3.0)` shaping before heat/inferno gradient lookup (explicit "FIX" so old-but-decaying values still show color).
- **Control/UI design**: `"TYPE": "text"` label rows as section dividers (`"--- GROWTH ENGINE ---"`, later `"══════ ARCHITECTURE ══════"`); named seeds (`globalSeed`/`architectureSeed` 0–9999); mode floats with legend labels ("Palette (0=B&W, 1=Ice, 2=Fire)"); Spore v2 ~30 inputs across four titled sections including a full post-processing rack.
- **Version evolution**: Living Grid (attractor-gated) → Fixed Architecture (line weight, sim/grid noise sync) → Spore center-growth reboot → split controls (mutation vs propagation as separate probability throttles) → scalable resolution → thermal palettes/glow → color-engine fix → v2 total rewrite (grid cached to its own pass, hybrid CA+RD, bloom pass, tonemap) → v2b (per-channel CA compositing). Longest continuous refinement arc in the batch; each rev's DESCRIPTION names the bug it fixes.
- **Complexity tier**: 5.
- **Signature moves**: sim-gated architectural reveal; leaf-cell-center sampling bridge; grammar-rule dropdown of mathematical ratios (PHI/SILVER).
- **Rough edges**: Spore v2 header has a duplicate `"TYPE"` key in the lineThickness input (JSON tolerated by hosts, still a latent bug); `curlNoise` defined but unused in several versions; heavy repeated `traverseLSystem` cost per fragment.

### Family 9: Hyper-Archive 16.0 / 17.0 / 18.0 (day16_11–day17_03 span)
- **Purpose & visual identity**: "Crystallographic Symmetry Engine" — a single-pass generative-typography/print-poster machine: an input image (text mask) is filled with a recursive BSP grid of solids, wireframes, 4x5 bitmap glyphs, pseudo-kana, icons, and SDF shapes, all folded through the **17 wallpaper groups**. Ink-on-paper look. Filter over a text/shape source.
- **Architecture**: single pass, no buffers — pure coordinate pipeline: domain warp → lattice transform → wallpaper fold → glitch/quantize → polyrhythmic grouping → 7-level BSP recursion → content dispatch → palette → print post. 60–90+ inputs.
- **Techniques**:
  - **Complete 17-wallpaper-group folding library** with orbifold annotations per function (`fold_p1`…`fold_p6m`): mirror folds via `p - 2*min(0, dot(p,n)-d)*n`, glides via row-parity flips, hex lattice via skew-coordinate `toHex/fromHex` round-trip, polar wedge folds for pure rotations. `symmetryBlend` linearly interpolates folded/unfolded coordinates.
  - **Quasicrystal modes** (18.0): 5/7/8/12-fold wedge folds (crystallographically forbidden symmetries), the 5-fold built by averaging five rotated fold passes — Penrose-flavored aperiodicity.
  - **BSP/quadtree recursion with per-depth probability sliders** (`recProb1..7` — a 7-knob depth envelope), golden-ratio split bias via `pow(uv, 1/bias)`, and **groupRatio stretch-correction** tracked through splits so glyphs render unstretched in non-square cells.
  - **Bitmap font as floats**: 4x5 glyphs packed into single float bit-fields decoded with `mod(floor(bits / pow(2.0, idx)), 2.0)` — box-drawing chars, letters, patterns (no bitwise ops needed).
  - `pseudoKana`: hash-driven stroke synthesis on a 3x3 subgrid (h/v strokes + conditional diagonals) — procedural fake ideograms.
  - **Content-weight mixer**: normalized weights (solid/wire/text/SDF) select per-cell content via a selector that mixes low-frequency cluster noise with per-cell hash (`mix(clusterVal, cellVar, 0.25)`) so content types clump spatially.
  - 24-entry SDF library (17.0) — IQ primitives (star, moon, vesica, heart, egg, arc) + composites (flower-of-circles, yin-yang via `opSubtract(opUnion...)`, concentric rings, spiral) with union/intersect/subtract/XOR/smooth-union combine dropdown, fill/outline/glow render modes.
  - **Cosine palette system** (IQ `a + b*cos(TAU*(c*t+d))`) with presets + a "custom cosine" mode deriving `a` from the average of the user's 4 colors.
  - **Print engine** (18.0): CMYK halftone with per-channel screen angles (15°/75°/0°/45° to avoid moiré), duotone, registration-error fringing, film grain with `sign(g)*pow(abs(g),0.5)` distribution shaping, 3-octave paper-fiber texture, ink-spread feathering (`smoothstep` widened by noise), 4 vignette shapes, 4 border styles incl. procedural art-deco corner ornaments.
  - Lattice deformation (18.0): shear/stretch/skew before folding (oblique lattices), plus a **dual-lattice** second fold at golden-ratio scale blended by Add/Multiply/Screen/Difference/Overlay for coordinate-space moiré.
  - Correlated blanking: `isBlank` raises blank probability when the left neighbor is blank — runs of empty cells instead of salt-and-pepper.
  - Glitch rack: row hard-shift, column slip, position bitcrush (`quantizePos`), dataMosh quantize, scatter, `bitShift` (cell-index-driven glyph index rotation), `logicKill` (XOR-error culling recursion where `mod(x*y, factor) < 1`), checkerboard `logicInvert` ink/paper swap.
- **Control/UI design**: the batch's largest headers (~90 inputs in 18.0), prefix-grouped labels ("SDF:", "Print:", "Frame:", "Logic:", "Palette:") instead of separators; 4-ink + paper color model; everything defaults print-safe.
- **Version evolution**: 16.0 wallpaper groups + legacy pattern zoo → 17.0 replaces the pattern zoo with the SDF library, adds cosine palettes and domain warping → 18.0 adds quasicrystals, lattice shear/dual-lattice, and the full print/output stage. Numbered like software releases with phase annotations ("Phase 2.1", "Phase 3", "Phase 5") — planned roadmap development.
- **Complexity tier**: 5 (single-pass, but the deepest coordinate pipeline and largest control surface in the batch).
- **Signature moves**: wallpaper-group + quasicrystal fold library; per-depth recursion probability envelope; float-packed bitmap font; print-simulation post stack.
- **Rough edges**: 18.0's cell border draw is commented out (`// inkAmount = max(inkAmount, border * 0.5);` — deliberate removal); `rgbSeparation()` is a stub that returns color unchanged ("would need texture sampling"); `sdArc`, `latticeRepeat/latticeID`, `curlNoise` unused; `paperTexture` input name shadows the `paperTexture()` function (compiles only because GLSL allows it on some backends — fragile).

## Batch synthesis

**Top 3 most sophisticated files:**
1. **Hyper-Archive 18.0 (day17_03)** — a 1674-line single-pass engine unifying crystallographic group theory (all 17 wallpaper groups + 4 quasicrystal folds), a 24-shape SDF library with boolean combine modes, a 7-depth stochastic BSP typesetter with stretch-corrected glyph cells, cosine palettes, and a complete print-simulation stage (angled CMYK halftone, registration error, ink spread). It reads as a designed product with a phased roadmap, not a sketch.
2. **The Spore v2 (day16_09/10)** — CA/RD hybrid growth constrained by, and revealing, a cached L-system architecture field; separate grid/sim/trail/bloom passes; virtual-resolution simulation; per-channel chromatic-aberration compositing of the entire render. The "organism reveals the blueprint" concept is the most original *system design* in the batch.
3. **Digital Crystal v9/v11 (day14_v17/v18)** — the endpoint of the RD lineage where the author stops fighting numerical instability and instruments it: kernel-shape dropdowns, non-mass-conserving Laplacian center, directional drift weights, reaction-exponent "Danger" slider, grid-crushed sampling, broken-mirror folds. Solver internals exposed as performance controls.

**Recurring patterns / style fingerprints:**
- `reset || FRAMEINDEX < 2` init blocks; `for (i < CONST) { if (i >= runtime) break; }` loops; `max(prev * decay, current)` trail accumulators — the known host-quirk toolkit, everywhere.
- **Iteration-as-passes**: 8 PERSISTENT buffers A–H with `iterationsPerFrame < N` pass-through gating, reused across two unrelated families (RD, and structurally echoed in the wireframe display latch).
- The 0.1031 vec3 hash (`hash21`), value noise with octave-break fbm, geometry-mode distance metrics (Euclidean/Chebyshev/Manhattan/Cross) as a reusable dropdown.
- UI grammar evolution visible within one batch: fake separator sliders (day14_v01) → `"TYPE": "label"` headers (wireframe family) → `"TYPE": "text"` dividers (Spore) → prefix-grouped labels (Hyper-Archive). Split unidirectional control pairs (zoom_in/zoom_out) for MIDI mapping. Macro `simpleMode` knobs over raw params.
- Strobe as a *simulation actuator* (feed/kill boost, border chemical injection, zoom shove, invert) rather than a brightness effect — the author's core live-performance idea.
- `CREDIT: "User & Gemini"` and in-comment LLM reasoning fossils (day14_v16) — this corpus openly documents AI-collaborative iteration, including its failure modes.

**Beyond standard ShaderToy fare:**
- The TimeBuffer single-pixel accumulated-time state (persistent-buffer scalar state, not image state).
- A complete orbifold-annotated 17-wallpaper-group + quasicrystal coordinate-folding library in ISF.
- "Digital Rot": a decay CA that only runs while the piece is frozen — freezing causes decomposition.
- L-system leaf-cell center-sampling bridge (grid cells as sampling atoms for a sim buffer), with bbox tracking through stochastic recursion.
- Deliberate Laplacian de-tuning (center weight, drift, stride, crush) as first-class labeled controls — instability engineering rather than instability avoidance.
- Float-packed 4x5 bitmap fonts and procedural pseudo-kana glyph synthesis for typographic texture without textures.
