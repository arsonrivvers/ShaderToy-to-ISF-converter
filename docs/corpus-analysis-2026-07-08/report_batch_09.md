## Batch 09 Analysis Report — AR_Genuary2026 day9/day10 families

## Coverage
- files_assigned: 42, files_read: 42, misses: **none**
- (Five oversized files — `AR_Genuary2026_day9_v03/v04/v05/v06/v07.fs` — exceeded the single-read token cap and were read in two chunks each; full contents covered.)
- All paths under `/Library/Graphics/ISF/`.

---

## Family 1: AR_Genuary2026_day9 v01–v07 — "Hyper-Archive" (recursive typographic grid engine)

**Purpose & visual identity:** Generator (with optional `inputImage` mask, so it doubles as a filter). A dense "data-brutalist archive sheet": recursive quadtree/BSP grid where every cell is filled with one of four content classes — solids, ASCII wireframes, bitmap text glyphs, or a "chaos" library of 32 micro-patterns — in a 4-ink risograph palette on paper. Versions here run Hyper-Archive 16.0 → 19.1.

**Architecture:** v01–v04 single-pass; v05–v07 add `PASSES: [{TARGET: caBuffer, PERSISTENT, FLOAT}, {}]` — a true persistent CA simulation pass feeding the render pass. Dispatch via `PASSINDEX` with pass-0 seeding on `FRAMEINDEX == 0 || caReset`.

**Techniques:**
- *Probabilistic recursive subdivision*: a 7-iteration loop splits each cell 2×2 or 2×1/1×2 (`bspMix` chooses BSP vs quad), gated per depth by `recProb1..7` and a hash roll; `finalID = finalID*splitDim + floor(microRaw)` keeps a stable integer cell ID through the recursion. `splitRatio` biases split position via `pow(uv, 1.0/bias)`.
- *4×5 bitmap font in packed ints*: `getASCIIBits` stores 15 glyphs as 16-bit integers (`bitsLow[9]=30975` etc.) and extracts bits with a loop of integer halving — a GLSL-ES-safe replacement for `>>` (no bitwise ops).
- *Pattern jukebox*: `getPattern(index,...)` — 32 primitives (box, cross, truchet, herringbone, pinwheel, spiral, pseudoKana "alien glyphs" built from a 3×3 grid of random strokes, icons: heart/arrow/smiley/space-invader).
- *Cluster coherence*: content selector = `mix(noise(finalID/clusterCohesion), random(finalID), 0.25)` — low-frequency noise makes neighborhoods share a content class, with per-cell jitter.
- *Glitch stack on the coordinate itself*: dataMosh (position quantize), hardShift (row slide), colSlip, glitchScatterX, quantizePos bitcrush — all applied to `st` before grid construction, so the grid itself tears.
- *Dithered gradients as ink modulation* (v02+): 6 threshold generators (Bayer 4×4 array, halftone, lines, crosshatch density ramp, noise, stipple) × 5 gradient directions, multiplied into `inkAmount`.
- *Inter-cell "Connections"* (v02+): drawConnection consults hashed neighbor state to draw lines/pipes/PCB circuits/nodes/mesh diagonals across cell borders.
- *CA evolution* (v03→v07, the family's core learning arc): v03 fakes CA history from pure noise (comment: "FIXED: Removed recursion from getCAState" — GLSL can't recurse); v05 abandons the fake and does a **true multi-pass persistent CA** (`runSimulation` reads `caBuffer` neighbors, 5 modes: Binary life-like with rule-morphed birth/survive windows, MultiState sum-modulo, Continuous averaging, Cyclic, "Crazy" `fract(sin(param*rule*10.))`); v06 adds **stochastic fractional speed**: `baseSteps = int(caSpeed); if (random(vec2(TIME,1.)) < fract(caSpeed)) baseSteps += 1;` — sub-frame-rate CA stepping via probability, a genuinely clever host-friendly trick.
- *CA→render coupling*: `getCAStateFromBuffer` maps infinite grid IDs into the finite buffer with `mod(cellID*0.05, 1.0)` (acknowledged as an approximation) and CA state culls cells below `caThreshold` and shifts ink color via `caColorize`.
- Multi-layer rendering (up to 3 scaled layers) with Add/Multiply/Screen/Difference blends; audio inputs are plain float sliders (`audioLow/Mid/High`) mapped into subdivision prob, selector, color, glitch.

**Control/UI design:** ~90+ inputs — the largest control surfaces in the archive. Section naming migrates from `Prefix: Name` (v01) to fully numbered workflow groups in v07: `1. GLOBAL:`, `2. SIM:` … `9. AUDIO:`, plus `ADV:` and `DET:` tiers pushing 40 rarely-touched knobs to the bottom. Conductor params: `macroScale` (zoom+growth), `patternSeed`, weight quartet (`weightSolid/Wire/Text/Pattern` normalized internally). Event input `caReset`. Coarse/fine style: caMode (coarse) + caRule (fine scan).

**Version evolution:** v01 baseline feature set → v02 adds connections + dithered gradients → v03 bolts on CA/audio/layers but with noise-faked CA (and header admits recursion had to be surgically removed) → v04 "Review Fixed": wires up previously dead params (`polyStruct` now damps split probability, `oddEvenCull` actually skips layers, `logicKill` becomes a visual XOR `abs(outColor - vec3(logicKill))`) → v05 real persistent CA buffer → v06 smooth fractional CA speed → v07 pure UX pass (input reordering only). A textbook trajectory: features → correctness review → architectural fix → performance/feel → ergonomics.

**Complexity tier: 5** — multi-pass simulation + recursive layout engine + conductor-weighted content system.

**Signature moves:** stable integer cell IDs through recursion; bit-packed bitmap font without bitwise ops; probabilistic fractional sim stepping; "review fixed" headers documenting which knobs were dead.

**Rough edges:** v03/v04's noise-CA is a dead end kept in the lineage; `getCAStateFromBuffer`'s `mod(cellID*0.05,1.)` wrap is arbitrary and aliases at large pans; `caGenerations` input survives into versions that ignore it; huge duplicated helper blocks between versions (copy-paste versioning, no includes).

---

## Family 2: AR_Genuary2026_day9_alt v01–v07 — "Morphogenetic Globe" (Lenia/CA on a volumetric sphere)

**Purpose & visual identity:** Generator. A rotating gaseous globe rendered with an ultra-low-step volumetric raymarch (Frostbyte/Xor style), whose surface pattern/geometry is driven by an artificial-life simulation (Lenia in v01–v03, Game-of-Life family in v04–v07) living in a 2D persistent buffer mapped equirectangularly onto the sphere.

**Architecture:** 2 passes throughout: `simBuffer`/`golBuffer`/`caBuffer` (PERSISTENT+FLOAT) + screen pass. `PASSINDEX==0` early-returns the sim; seed on `FRAMEINDEX==0 || reset`.

**Techniques:**
- *Lenia (continuous CA)* (v01–v03): Gaussian ring kernel convolution up to radius 8 (`getKernelWeight` with kPeak 0.5/kWidth 0.15), Gaussian growth function `2*exp(-0.5t²)-1` with hardcoded stability params ("to ensure nice visual structures"); toroidal wrap via `fract(uv + offset*px)`; audio shifts `growthMu` with bass sampled at `texture2D(audioLevel, vec2(0.1, 0.0)).r`.
- *Sphere-texture coupling*: `getLeniaState(p)` maps the rotated march point to equirectangular UV (`atan(z,x)/2π+0.5`, `asin(y)/π+0.5`) — the load-bearing bridge between the 2D sim and 3D volume.
- *Frostbyte 10-step volumetric march* (quoted comments credit the source): Xor golden-ratio dot noise `dot(cos(GOLD*p), sin(PHI*p*GOLD))`, coordinate folding `b.xy = r(sin(b.xy*frostTwist), t*0.5 + length(b)*3.0)`, `stepDist = max(s, 0.05)` forced forward motion producing the signature "sliced" look, inverse-distance light accumulation `l += palette*density/(abs(s)+0.1)`, full-matrix ACES tonemap on `l*l/400`.
- *CA-as-displacement vs CA-as-emission*: v01 lenia displaces the SDF *and* colors; v02 explicitly retracts displacement ("DISPLACEMENT IS NOW PURELY NOISE/GEOMETRIC", lenia is texture only); v03 builds a dedicated `getComplexDisplacement` — 3-axis dot-noise domain warp + base/detail two-octave shape; v05 re-couples CA→geometry (`caDisplacement`); v06 decouples again into a layered emission model (`getCALayered` samples the CA at 6 concentric shell radii for fake internal volume, plus `getCAGradient` finite differences for iridescent color); v07 goes to a clean 64-step sphere march with lighting computed only when `dSphere < 0.1` and an exit heuristic. The author is visibly A/B-ing "does life shape the planet or paint it?"
- *Rule-mask CA engine* (v04–v07, imported from "GOL FilterA Prime+"): rulesets as bitmask pairs (`vec2(8.0,12.0)` = B3/S23; Diamoeba 488/480 etc.), `checkRule` extracts bits via `mod(floor(mask/exp2(n)),2.0)`; three stepping modes (binary/continuous/hybrid) with Gaussian-weighted neighborhoods; per-pixel stochastic **rule morphing** between two presets (`hash(px) < effectiveMorph ? rulesB : rulesA`) with time-sinusoidal mutation.
- *16-mode warp library* applied to the CA's *read coordinate* (v05–v07): radial/spiral/curl/vortex-array/diamond/golden-spiral flows plus fractal UV maps — Julia, Mandelbrot, Newton's method (with `cDiv`), kaleido fold, abs-fold fractal, Clifford and Ikeda strange attractors, Menger fold, two-level fBm domain warp — each clamped to `±warpAmount` pixels. Warping the CA lattice itself, not the display, so the *simulation* inherits fractal structure.
- v04 stores a 4-channel state: R smoothed intensity (with `max(prev*decay, current)`-style instant-on/fade-off), GB velocity from density gradients + curl (`vec2(grad.y, -grad.x)`) with inertia, A discrete state — CA + pseudo-fluid advection in one buffer.

**Control/UI design:** 10–35 inputs. Prefix groups `SIM:`, `VOL:`/`GEO:`/`DISP:`, `POST:`; v04+ adopt heavy-line dividers `━━ BIOLOGY ━━━━` and Unicode labels (`⟲ Reset`, `■ Binary`, `∿ Continuous`, `★ Julia`). Color: fixed sin palette (v01–03) → 3 color pickers (v04) → 4 cos-palette modes + hue shift (v05+). `reset` event throughout.

**Version evolution:** Lenia+displacement → texture-only → displacement-engine → GOL+advection with color pickers → maximal merge (CA rules + warps + globe, header credits "AR + Gemini + Frostbyte + Bert Chan — Merged by Claude") → emission/depth-layer refinement → clean-surface 64-step rewrite. Learning arc: fidelity of the march (10→12→64 steps) rises as geometric ambition falls.

**Complexity tier: 5** — persistent ALife sim, fractal warp library, volumetric renderer.

**Signature moves:** equirectangular CA→sphere bridge; warping the simulation's read coordinates through strange attractors; CA depth-layering for fake volumetric interiors; verbatim-credited Frostbyte micro-marcher as a reusable chassis.

**Rough edges:** v01 audio path dropped in v02–v03 then never returns; kernel radius loop `int rad = int(kernelRadius)` with dynamic bounds is a compile hazard on strict hosts (the very thing later files avoid with const-bound loops + break); v05 carries `rangeToMask` and `INPUT_SMOOTH_WIDTH` dead code; duplicated 200-line warp library across v05/v06/v07.

---

## Family 3: AR_Genuary2026_day9_altB v01–v07 — Apple II Voxel Raymarcher lineage

**Purpose & visual identity:** Generator. A recursive-resolution voxel world (jeyko's Shadertoy "Day 966") rendered in the 16-color Apple II palette with dithering, edge outlines, and progressively more controllable retro/glitch styling.

**Architecture:** 2 passes: `buffA` (PERSISTENT+FLOAT) scene render + post pass. Dispatch `if (PASSINDEX == 0) … else if (PASSINDEX == 1)`.

**Techniques:**
- *Hierarchical voxel DDA with a manual recursion stack* (the family's crown jewel, preserved verbatim through all 7 versions): per-axis hypotenuse precomputation (`zHypot = 1/sin(atan(rd.x/rd.z) …)` with sign fixups), fract-cell exit distances `fZ = xHypot*(1.0001 - fracP.z)` (note the 1.0001 overstep factor against float precision), and a **fractal refinement stack**: when `map(floor(p*currFractalD)) < 0` the traversal *descends* (`currFractalD += 1`), recording `walkTillExit[idx]`/`currDWalk[idx]` in fixed arrays so it can pop back up when it walks out of the parent cell — octree-style LOD raymarching without recursion, up to 7 levels.
- *Animated 4D noise terrain*: `map` uses a vec4 noise (position + time as 4th axis) with chained plane rotations and `dot(sin(p),cos(p))` accumulation; `noiseScaleB * floor(fract(t*0.05)*3.0)` makes the whole world snap between 3 detail regimes on a timer.
- *Face-axis shading*: hit normal derived purely from which DDA axis terminated (`nq[hitAxis] = sign(fract(p[hitAxis]) - 0.5)`), then per-face intensity (top/side/front) — Minecraft-style lighting for free.
- *Apple II palette*: 16 hardcoded `vec3(217,60,240)/255.` entries indexed by `mod(floor(p.x)*14. + nq.x + nq.y*10., 16.)` — world-position-hashed color assignment; `pow(col, vec3(0.4545))` gamma.
- *SDF-based AO macro*: `#define ao(p,n,d,amt) mix(1., clamp(map(p+n*d)/d/pixelScale, 0., 1.), amt)` sampled at 3 radii (v01–v04); v05 replaces it with distance-based "rigid" fake AO for stability.
- *Luma quantize + dither*: `currC = floor(s*quant)/quant; perc = fract(luma(s)*quant); C = perc > dith ? nextC : currC` — v01 uses an external dither texture; v03 introduces procedural Bayer-4×4 fallback; v04's key upgrade is **world-space triplanar dithering**: the dither UV is chosen from `p.xz / p.yz / p.xy` by hit axis, so the pattern sticks to voxel faces instead of the screen.
- *v01's timed glitch theater*: hard-coded `fract(iTime*X)` gates flip pixelScale, invert colors, draw sdBox UI panels and hashed color-block "menu bars" — a self-playing demo the later versions convert into sliders (`styleInvert`, `styleEdge`…).
- *Stochastic voxel transparency* (v05–v07): each voxel rolls `random3(floor(p*currFractalD))` (position-only — v05's header note "NO TIME COMPONENT" marks the flicker bug they fixed) to be solid or "ghost"; v06 implements proper **front-to-back alpha compositing inside the DDA**: `finalColor = mix(finalColor, voxCol, alpha*transmission); transmission *= (1.0 - alpha);` with early exit below 1% and a `p += rd*(1.5/currFractalD)` push-through to avoid self-intersection. v07 adds user-controlled camera clip radius and radial fog distance/density ("Void Control").
- Post pass: 4-direction luma差 edge detection → black outlines; invert/solarize with 0.45 gamma.

**Control/UI design:** 3 inputs (v01) → ~20 (v07), prefix groups `Camera:`, `Voxel:`, `Map:`, `Color:`/`Shade:`, `ADV:`, `Style:`. The evolution v03→v05 splits monolith knobs into per-face shading (`shadeTop/Side/Front`), a classic coarse→fine explosion.

**Version evolution:** faithful conversion (v01) → stripped geometry study (v02) → parameterized hybrid (v03) → world-space material dithering (v04) → rigid deterministic lighting + transparency (v05) → correct alpha compositing (v06) → fog/void controls (v07). The author repeatedly *removes* the original's autonomous glitch behaviors in favor of VJ-controllable equivalents.

**Complexity tier: 4** — sophisticated traversal core (inherited) with substantial original systems layered on, but no persistent feedback dynamics.

**Signature moves:** the LOD DDA stack; triplanar world-space dither; position-seeded (time-stable) stochastic transparency; face-axis normals.

**Rough edges:** `buffA` marked PERSISTENT though never read across frames (cargo-culted); `fZ/fX/fY` read before guaranteed initialization if loop exits early; v03's "is the dither texture present?" heuristic punts to a 50/50 blend; ternaries on scalars only (consistent with the vector-ternary host hazard).

---

## Family 4: AR_Genuary2026_day9_altC v01 — Calabi-Yau Manifold CA

**Purpose & visual identity:** Generator. A 3D cellular automaton living in a volume texture, rendered as a raymarched shell around parametric "string theory" surfaces (Quintic Calabi-Yau, K3, Fermat, Kummer, Enriques) with 4D rotation slicing. The batch's most architecturally ambitious single file.

**Architecture:** **4 passes**: `caBuffer` (PERSISTENT FLOAT, fixed 1024×1024) = 3D CA volume packed as a 2D Z-slice atlas; `feedbackBuffer` (PERSISTENT FLOAT 512×512) = temporally smoothed CA activity for manifold deformation; `geoBuffer` (FLOAT) = raymarched normals+depth G-buffer; final composite pass with deferred lighting.

**Techniques:**
- *3D volume in a 2D atlas*: `vol3Dto2D` tiles Z-slices `sqrt(res)×sqrt(res)`; `sampleVolumeSmooth` does manual **trilinear interpolation from 8 atlas fetches** — full 3D texture emulation in ISF, which has no 3D textures.
- *3D CA (26-neighborhood)* with three topology modes: Euclidean offsets; *Geodesic* (offsets re-projected through the manifold parametrization); *Topological* — 5% hashed "wormhole" jumps to distant cells. Rule masks extend the B/S bitmask idea to 0–26 neighbors; binary/continuous/hybrid stepping; state packed as (prev, velocity, age, state).
- *Manifold parametrizations with complex arithmetic*: `cPow/cExp/cSin/cCos` (with hand-rolled `_sinh/_cosh` "for older GLSL" — a real host-compat scar), Fermat surface via signed `pow(abs(cos θ), 2/n)` superquadric terms, Kummer quartic deformation `p *= 1 + 0.2*lambda*(x²y² + y²z² + z²x²)`, Enriques as K3 quotient by an involution `p.z *= sign(sin(TAU*(u+v)))`.
- *4D slicing*: full set of six 4D rotation matrices; the SDF lifts p to `vec4(p, sliceW)`, rotates in XW/YW/ZW, and evaluates the manifold on the projected point.
- *CA→geometry feedback loop*: `feedbackBuffer` integrates CA activity over 8 Z-samples with temporal smoothing `mix(new, prev, feedbackSmooth)`, and `manifoldSDF` adds it to compactification parameter and shell thickness — the automaton literally re-shapes the manifold it lives on.
- Deferred shading: pass 3 reconstructs the camera ray, re-derives the hit point from stored depth, samples the CA trilinearly for emissive/color, Blinn-Phong + wireframe UV grid overlay + depth fog; 5 color modes (CA state/normals/curvature/depth/UV).

**Control/UI design:** ~35 inputs in 8 divider-labeled sections (`━━ MANIFOLD ━━`, `━━ 4D SLICE ━━`, `━━ CA TOPOLOGY ━━`, …); long-type dropdowns with math-literate labels ("Quintic CY", "Geodesic"); seed patterns (Random/Sphere/Torus/Manifold-Surface/Noise).

**Version evolution:** single version — an experiment rather than a lineage (its ideas continue in altD).

**Complexity tier: 5** — four passes, emulated 3D texture, geometry feedback, deferred shading.

**Signature moves:** Z-slice atlas + manual trilinear sampling; wormhole CA topology; sim-deforms-its-own-substrate feedback.

**Rough edges:** `manifoldSDF` measures distance to *one* manifold point derived from an approximate inverse UV mapping — not a true SDF, so the raymarch converges only loosely; `volumeRes` as a runtime input can't actually resize the fixed 1024² buffer; `getNeighborOffsets` fills 26-element arrays per fragment (very heavy); geodesic mode's inverse mapping is admitted "approximate."

---

## Family 5: AR_Genuary2026_day9_altD v01–v08 — Voxel Hybrid V10/V11 (CA integration → organism ecology)

**Purpose & visual identity:** Generator. Direct continuation of altB's voxel engine: v01 fuses it with multiple CA systems; v02–v08 build the "Organism Erosion System" — a bioluminescent alien growth that spreads through, digests, and erodes the voxel terrain, with a full color-grading suite bolted on.

**Architecture:** v01: 3 passes (`caBuffer` PERSISTENT at **quarter resolution** via `"WIDTH": "floor($WIDTH/4.0)"` — the only expression-sized buffer in the batch; `buffA`; post). v02–v06: 4 passes (`organismBuffer` PERSISTENT, `healthBuffer` PERSISTENT, `renderBuffer`, post). v07–v08: 5 passes adding `bloomBuffer` for separable Gaussian bloom.

**Techniques:**
- *v01, axis-dependent CA rules* (conceptually the wildest idea in the batch): the CA rule applied to a voxel depends on which face the ray hit — Conway B3/S23-variant on XZ for top faces, 1D **Wolfram rule** (bit extracted from `caWolframRule` 0–255 via divide-loop) on YZ for side faces, **Brian's Brain** 3-state on XY for front faces; plus "Temporal Solidification" (crystallize at 2–4 solid neighbors, dissolve when isolated/overcrowded, with hysteresis), "Ghost Transmission" (density-driven solidify/fade fed by the ray's own accumulated transmission), and "Palette Flow" — a CA over *color indices* where hand-mapped complementary Apple II pairs attract (`getComplementaryIndex`: magenta↔white, orange↔blue…). All are noise-simulated (hash-of-time) rather than buffer-read — the v03-of-day9 mistake recurring.
- *Organism system* (v02+): golden-angle seed placement `angle = i*2.39996 + t*0.05`; growth radius `adjustedTime * organismSpeed` (with a startup delay so terrain establishes first) modulated by an fbm+"tendril" noise field (sums of squared traveling sine waves); per-buffer state (density, digestion, age, growthFront) with CA-style neighbor spread `spreadBonus = neighborDensity*organismSpread*0.2` and decay.
- *Health/erosion ecology*: `healthBuffer` is depleted by organism density² (`digestion`), regenerates when the organism leaves, and **damage propagates from eroded neighbors**; the voxel `map()` adds `smoothstep(0,1,damage)*0.8` — the SDF is eaten. Init guard `if (TIME < 0.5 || health≈0 && …)` writes full health, a FRAMEINDEX-style bootstrap.
- *3D↔2D encoding v2*: `encode3Dto2D/decode2Dto3D` pack a wrapped world cube into horizontal Z-layer strips — same atlas idea as altC in simplified strip form, used both to write (sim passes decode their own pixel to world space) and read (render pass encodes march position to sample health).
- *Age-based organism palette*: bioluminescent purple (active) → dark teal (mature) → near-black (decayed) with `sin(t*2 + density*8)` pulsing glow; growth-front emissive rim.
- *Color-correction suite* (v02+): 16 `cc*` inputs implementing exposure→temp/tint→shadows/highlights (luma-masked)→contrast→brightness→saturation→hue (full RGB↔HSV)→gamma, each behind `abs(x) > 0.001` epsilon gates to skip identity work; screen-space vignette/grain/chromatic aberration in the post pass.
- *Lighting upgrade* (v04+): true Blinn-Phong on the face normal (lightDir XYZ sliders, tinted specular, rim light `pow(1-NdotV,3)`), depth-based hue shift through HSV, and (v08) face multipliers folded into `totalLight` rather than replacing it.
- *Compositing correction arc*: v02/v03 blend `mix(finalColor, voxCol, alpha*transmission)` starting from fog color (order-wrong); v05 fixes it to true front-to-back `finalColor += voxCol*alpha*transmission` then composites `+ bgColor*transmission` at the end — the comment "Proper front-to-back compositing … voxels appear over white, not blended with it during accumulation" records the lesson.
- *Bloom arc*: v04 crude in-loop 9×9 weighted gather (81 taps) → v07/v08 proper **separable two-pass Gaussian** (bright-pass extract `col * max(luma-thresh,0)/luma`, 9-tap horizontal into `bloomBuffer`, 9-tap vertical + composite).

**Control/UI design:** 40–60+ inputs, flat `Prefix:` naming (`Camera:`, `Voxel:`, `Map:`, `Color:`, `Void:`, `CC:`, `Organism:`, `FX:`); v06 is notable as a **pure preset re-tune** — identical code, defaults changed (zoom 5, recursion 7, solidProb 1.0, inverted lightDirY) to capture a specific look.

**Version evolution:** V10 CA fusion (v01) → V11 organism+health+CC (v02) → color vividness & user fog/bg colors (v03) → physical lighting + crude bloom (v04) → compositing fix, white-void aesthetic (v05) → preset tune (v06) → separable bloom (v07) → lighting/face-shading integration (v08). Five files share the same "V11" description string — versioning is by filename, not header.

**Complexity tier: 5** — dual persistent simulations coupled through an erosion loop, 4–5 passes, deepest post pipeline in the batch.

**Signature moves:** predator-prey buffer pair (organism vs terrain health); axis-dependent CA rule assignment; expression-sized quarter-res sim buffer; ε-gated CC chain.

**Rough edges:** v01's five CA systems are all noise simulations despite a real buffer existing; organism neighbor sampling ignores the Z-strip atlas boundaries (bleeds between layers); post passes decode screen UV as world position (`decode2Dto3D(uv, worldSize)`) for growth-front glow — geometrically meaningless but visually accepted; massive header duplication (~600 input lines repeated 7×).

---

## Family 6: AR_Genuary2026_day10 v01–v12 — Angular Gradient → "Cinematic Eclipse" (with v03 superellipse detour)

**Purpose & visual identity:** Generator. Starts as a two-line conic-gradient debug view and evolves into a cinematic "eclipse terminator": a rotating hard angular edge treated as a light source with prismatic dispersion, multi-layer atmosphere, and a full film-emulation grade. v03 is a sibling detour: a glowing superellipse (squircle) outline with the same lighting language.

**Architecture:** single pass throughout — all sophistication is analytic. (v01: 45 lines; v12: ~850.)

**Techniques:**
- *Angular-domain everything*: the core primitive is `angle = mod((atan(p.x,p.y)+rot+offset)/2π + 0.5, 1.0)` and **wrapped edge distance** `d = abs(a-e); min(d, 1.0-d)` — all subsequent "spatial" effects (glow, fringe, occlusion) are computed in angle space, so they rotate rigidly with the edge.
- *Chromatic aberration as angular offset*: R/G/B (later +violet) channels sample the edge at scaled angular offsets; v07 formalizes it with a `SpectralWeights` struct commented with Cauchy-equation reasoning (red 1.0, green 0.3, blue −0.6, violet −1.4 × spread) and adds **5-tap Gaussian-weighted multi-sampling per channel** plus a shared "envelope" falloff all channels respect — the fix for the fringes separating into distinct bands.
- *Multi-layer exponential glow*: 3–4 `exp(-dist/(spread*k))` shells with distinct colors (near warm, mid scattering-tinted, far spectral) — a fake bloom stack.
- *Oklab pipeline* (v06+): full sRGB↔linear↔Oklab matrices and `oklabMix` used for *every* color blend, including a 7-stop gold→peach→white→steel→slate→indigo→deep spectral gradient; v11 wraps mixes in smoothstep/quintic "bezier" easings.
- *Cinema color grading* (v06+): per-channel Lift/Gamma/Gain (`gain*pow(c,1/γ) + lift*(1-pow)`), temperature/tint, filmic S-curve `0.5 + t*(1+k(0.25-t²))/(1+k/4)`, soft highlight rolloff, **halation** (red-orange bleed masked by highlight×edge proximity), 3-octave animated film grain scaled by inverse luma, and **triangular-PDF dither** `(hash1+hash2-1)/255` to kill banding.
- *Physically-flavored refinements*: v09 rebuilds the inner rainbow so dispersion runs **across the band width** (position within band → `wavelengthToRGB` CIE-piecewise 380–700nm, red outermost) — with a comment explicitly noting the previous version's hue-along-edge was "wrong"; v10 makes the dark side actually dark (steep `pow(light, lightFalloff)`, `voidBlack`, glow masked to the lit side); v11 adds Rayleigh scattering (per-channel loss `vec3(0.05,0.12,0.25)*dist` + blue haze), light wrap at the terminator, an 8-sample volumetric ray loop with noise breakup, anamorphic horizontal streak, and ACES; v12's entire point is **pipeline order**: staged comments `STAGE 1 LIGHTING → 2 SCENE (HDR) → 3 LENS/OPTICAL → 4 COLOR (LGG → exposure → ACES → display-referred temp/tint) → 5 FILM STOCK (halation on tonemapped image → grain → dither last)`.
- v03 (detour): superellipse SDF `pow(pow(q.x,n)+pow(q.y,n),1/n) - 1` with per-channel *size-scaled* (not angle-offset) chromatic sampling, directional dot-product lighting, purple inner fringe.

**Control/UI design:** 1 input (v01) → 40 (v12). No section dividers (unlike day9) — flat LABEL text, but the *semantics* professionalize: separate coarse/fine chromatic controls (intensity vs spread vs softness), a colorist's Lift/Gamma/Gain ×RGB block, `exposure` in stops, bloom threshold+intensity. The family's conductor is `hardness` (0 = smooth conic gradient, →0.998 = razor eclipse edge) with `if (hardness <= 0.0)` fallback branches preserved in every version.

**Version evolution:** grayscale atan viz → rotation/center/invert → (superellipse detour) → glow+CA on the angular edge → multi-layer spectral (v05) → Oklab + film pipeline (v06) → smooth multi-sample chromatics (v07) → inner rainbow (v08) → physically-correct dispersion (v09) → real darkness (v10) → volumetric atmospherics (v11) → render-order discipline (v12). Uniquely, the code carries **archaeological comments**: v07/v11 contain strings like "Attempt 5 Attempt 3 Attempt 3 …" prepended to function comments — visible residue of iterative AI-assisted regeneration rounds.

**Complexity tier: 3** (v01–v04: 1–2) — single-pass, no feedback, but v09–v12 carry a genuinely deep analytic lighting/grading stack; justified below 4 by the absence of multi-pass simulation.

**Signature moves:** wrapped angular edge-distance as a 1D SDF; envelope-constrained multi-channel dispersion; CIE wavelength ramp for a physically-ordered prism band; the fully staged HDR→display film pipeline in one fragment shader.

**Rough edges:** "Attempt N" comment litter; `rings` input in v01 unused; duplicated 150-line Oklab/grading block in six files; v06's `liftGammaGain` uses `pow(color, gamma)` where v08+ correct it to `pow(color, 1/gamma)` (a real math fix mid-lineage); grain/dither use `fract(TIME)` seeds that will stutter on TIME wraparound in long sets.

---

## Batch synthesis

**Top 3 most sophisticated files:**
1. **`AR_Genuary2026_day9_altC_v01.fs` (Calabi-Yau Manifold CA)** — a 4-pass deferred pipeline that emulates a 3D texture via Z-slice atlas with manual trilinear filtering, runs a 26-neighbor 3D CA with geodesic/wormhole topologies *on* parametric Calabi-Yau/K3/Kummer surfaces built from complex arithmetic, 4D-rotates the slice, and feeds CA activity back into the manifold's own shape. The most conceptually dense shader in the batch.
2. **`AR_Genuary2026_day9_altD_v02.fs` (Organism Erosion V11)** — dual persistent buffers forming a predator/prey ecology (organism density vs terrain health) coupled to the jeyko LOD voxel DDA, with damage diffusion, regeneration, golden-angle seeding, and a 16-parameter epsilon-gated color-correction chain.
3. **`AR_Genuary2026_day9_v06.fs` (Hyper-Archive 19.1)** — true persistent CA driving a probabilistic recursive BSP layout engine with a 32-pattern content jukebox, bit-packed bitmap fonts, and the stochastic fractional-step CA speed trick; ~90-input conductor surface.

**Recurring patterns across families (style fingerprints):**
- The universal hash `fract(sin(dot(p, vec2(12.9898,78.233)))*43758.5453123)` and the `p3 = fract(vec3(p.xyx)*0.1031)` hash appear in nearly every file.
- Sim pass boilerplate: `PASSINDEX==0` early return, seed on `FRAMEINDEX==0 || reset`, toroidal wrap via `fract`/`mod`, trail persistence via `max(next, prev*decay)`.
- No bitwise ops anywhere — bit extraction always via `mod(floor(mask/exp2(n)),2.0)` or divide loops; no vector ternaries; const loop bounds with runtime `break` (`for (int i=0;i<8;i++){ if (i>=steps) break; …}`) — consistent Metal/GLSL-ES defensive style.
- CA rules as B/S bitmask `vec2`s with the same named preset table (Life/HighLife/Diamoeba/Day&Night/Coral/Maze…) copy-pated across three families.
- Divider-style labels (`━━ SECTION ━━`) and prefix namespacing (`SIM:`, `VOL:`, `CC:`, numbered `1. GLOBAL:`) as the UI convention; `event` reset inputs; long-type dropdowns with emoji/Unicode glyph labels.
- Version evolution is by whole-file copy; headers double as changelogs ("Fixed", "Review Fixed", "Correct Render Pipeline Order"); CREDIT lines candidly track AI collaborators ("Gemini", "Merged by Claude", plus jeyko/Xor/Frostbyte/Bert Chan attributions).

**Techniques beyond standard ShaderToy fare:**
- 3D-volume-in-2D-atlas with hand-rolled trilinear filtering (altC) and the simpler Z-strip encode/decode (altD) — full volumetric simulation inside ISF's 2D-buffer constraint.
- Stochastic fractional sim stepping (probability of an extra CA step per frame) for continuously variable simulation speed.
- Warping a CA's *read lattice* through Julia/Newton/Clifford/Ikeda/Menger maps so the automaton inherits fractal structure.
- Axis-dependent CA rule assignment (Conway on floors, Wolfram on walls, Brian's Brain on front faces).
- The manual recursion stack for multi-LOD voxel DDA (`walkTillExit[]`/`currDWalk[]` arrays).
- A colorist-grade single-pass film pipeline: Oklab-space blending, CIE wavelength dispersion, Rayleigh scattering, LGG→exposure→ACES→display-referred ordering, halation computed post-tonemap, triangular-PDF dither last (day10 v09–v12).
- An emergent two-buffer ecosystem (organism digests terrain; terrain regrows) — simulation as narrative, not just texture.
