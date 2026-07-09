# Batch 08 — Genuary2026 day 8 (22 files, all read, no misses)

All 22 files (`AR_Genuary2026_day8_v01.fs` → `v22.fs`) are single-pass raymarched generators — no PERSISTENT/FLOAT buffers, no multi-pass ISF in this batch.

## Family A — City Geometry Hybrid (v01 only), tier 4
Credit "ocb + 4rknova." Heightfield/plane-marching city tracer (`city_trace`/`getNextPlan`) using 3 overlaid grid scales for skyline variety, plus a secondary AABB box-march (`traceWindow`/`boxImpact`) for windows. Procedural window lighting and dual-grid metal paneling entirely without textures. Standalone — abandoned in favor of Family B.

## Family B — "Radioactive Fractal" Tunnel/City (v02–v12), tiers 2→5
XorDev's Menger-fold fractal (`v = scale*fold_offset - abs(mod(v,scale*rep)-scale)`, CSG via `max(s, min(min(v.x,v.y),v.z))`) with per-iteration domain rotation. Incremental-exposure trajectory: bare fractal (v02) → geometry sliders (v03–05) → orbit-trap glow + ACES tone mapping (v06–07) → full camera rig with sector-warp teleport + roll (v08–09) → AO + jitter + landscape/tunnel mode toggle (v09–10) → 6-way discrete fractal-shape morphing (`getFractalShape(id)` blended via `fract()`) + randomized flight-direction system (v11) → domain-noise erosion + sparse volumetric self-shadowing/god-rays (v12).

## Family C — "Nuclear Dust" Volumetric Scattering (v13–v22), tiers 3→5
Architectural pivot: fixed 200-iteration loop with an internal `mode` state machine implementing a two-phase search→scatter volumetric march (march toward geometry, then re-aim at the light source and integrate density) — a bespoke workaround for ISF/Metal's const-loop-bound constraint. v15+ drops flight camera for randomized static "security cam" placement (hash-seeded position + yaw/pitch Euler look with gimbal-lock guard). Late versions add real physically-based light transport: Henyey-Greenstein phase function (v18+), blue-noise dithering via Laplacian high-pass (v20+), full Beer's Law per-channel spectral absorption (v22 — the batch's technical peak).

## Top 3 standouts
1. **v22** — Beer's Law spectral absorption + Henyey-Greenstein phase + blue noise + directional sun, composed in physically sensible order.
2. **v11/v12** — discrete 7-shape CSG library continuously blended via `fract()`, plus randomized flight system, erosion, sparse self-shadowing.
3. **v01** — structurally distinct dual-tracer city renderer with from-scratch procedural texturing, no textures/buffers.

## Recurring patterns
- `shake = vec3(2*noise(t)-1, 1, fbm(t))` camera-shake idiom copy-pasted verbatim through v12, dropped when Family C goes static-camera.
- `hash`/`noise`/`fbm`/`rot`/`ACESFilm`/`hsv2rgb` boilerplate duplicated unchanged across all 22 files.
- Dominant working method: "expose one more hardcoded constant as a slider next revision" (Family B geometry controls, Family C lighting refinements).
- v14, v20 contain in-code documented bugfix narration ("FIX: Included v.y in the min()... previously created infinite vertical streaks"; "PULSE FIX: Slowed time multiplier") — negative-knowledge worth cataloging.

## Unexpected techniques
- Fixed-loop two-phase search→scatter volumetric march (not standard Shadertoy two-nested-loops form).
- Genuine Henyey-Greenstein + Beer's Law physical light transport in a live-VJ context.
- Discrete-shape-library-with-continuous-blend for morphing between qualitatively different CSG topologies rather than parameter blending.
