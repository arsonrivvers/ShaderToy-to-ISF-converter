# ArsonRivvers Generation Playbook

*Human/planning reference for TrueISFEditor's ShaderAssist & Remix Studio. NOTE: the app does NOT read this file at runtime — ShaderAssist and Remix Studio load hardcoded skill paths (see "Runtime wiring" below). This doc is for planning prompts, wiring decisions, and future app work.*

Derived from a complete analysis of the 964-shader ArsonRivvers corpus in `/Library/Graphics/ISF` (2026-07-08). The full per-batch analysis reports and the master catalog live in:

- **Master catalog** (the source of truth): `~/.claude/skills/isf-shader-development/references/arsonrivvers_technique_catalog.md`
- **Runtime-facing distillation** (survives the preamble cap): the "ArsonRivvers House Style" section of `~/.claude/skills/shader-lineage-remix/SKILL.md`

## Runtime wiring (as of 2026-07-08)

- `ShaderAssist/SkillPreamble.swift` concatenates exactly two files — `isf-shader-development/SKILL.md` + `shader-dev/SKILL.md` — and **hard-caps the result at 12,000 characters**. `isf-shader-development/SKILL.md` alone is ~15.6KB, so ShaderAssist currently truncates it mid-file and never sees `shader-dev` at all.
- `Remix/RemixPrompt.swift` concatenates three: `shader-lineage-remix` (9.4KB, loads FIRST → fully survives) + `isf-shader-development` (~2.5KB of its head survives) + `shader-dev` (never survives).
- The `claude` CLI subprocess is launched with all tools stripped (`--tools ""`), so **reference files are invisible to the app's sessions** — only SKILL.md text that fits under the cap reaches the model. That is why the generation rules were pushed into `shader-lineage-remix/SKILL.md` and why fixing the cap is the single highest-leverage app change (tracked as an action item: raise/remove the cap, or select skill content per task).

## Generation recipes (what "mind-blowing" means in this corpus)

A new shader reads as extraordinary — not generic — when it hits these five properties (catalog §6):

1. **A causal mechanism, not a look.** Model the codec/chemistry/physics/print process and let the aesthetic emerge. Corpus proof points: datamosh built from real Lucas-Kanade motion estimation + MPEG quadtree macroblocking; misprints from real CMYK plate math; decay from a real two-buffer ecology.
2. **Two coupled systems**, one driving the other's *parameters*: RD chemistry → IFS geometry (multiplicative mapping — the discovered "soul"); CA → architecture reveal; organism ↔ terrain; proof buffer → its own generator.
3. **Imported domain knowledge**: crystallography (17 wallpaper groups + quasicrystals), statistical mechanics (Ising coupling), number theory (Zeckendorf, parastichy, coprime tides), color science (OKLab, spectral integration, gamut-edge blowout), animation theory (the 12-principles rig), codec/hardware failure taxonomies, film-lab craft.
4. **Performability engineered in**: 1×1-buffer state servos (gliding sliders), BPM/swing/slip clocks, macro conductors, stability governors + limiters + panic reset that let a performer *push*.
5. **Self-awareness**: debug views, proof buffers, registers/HUDs rendering internal state.

### Ingredient-combination method (for Remix Studio prompts)

Pick one from each column, then wire A's state into B's parameters:

| A: Engine (state) | B: Renderer | C: Conductor |
|---|---|---|
| Gray-Scott / Lenia / GOL-bitmask CA | glow-accumulation raymarch | 1–2 macro knobs w/ perceptual curves |
| chaos maps (Ikeda/Hénon) w/ persisted orbits | BSP/quadtree layout + print physics | BPM clock + beat envelopes |
| optical flow / tracker table | wireframe splatting / laser edges | activation field (sweep × jitter) |
| feedback buffer (max-decay / signed-delta / self-advected) | bit-packed typography / data HUD | depth-map-as-fader |
| GPU genetics / lineage fields | multi-hit X-ray / deterministic glass | scene presets-as-multipliers + morph |

Always finish with: armor checklist (catalog §4), zero-default controls, IQ palette as 4 color inputs, anti-banding dither, tier 4–5 architecture (persistent FLOAT sim + display minimum).

### Corpus hygiene notes (found during analysis)

- `AR_Horizontal-Line_grid_remix_v01.fs` is **0 bytes** (empty).
- Broken-as-shipped files (useful as lint fixtures): `AR_MeltingCam1_HallofMirrors.fs` (input-name case mismatch), `ArsonRivvers_ImpoShapeDistortion.fs` (header transplanted from megaTorusWarper — body references undeclared inputs), `ArsonRivvers_Kick_Neon_alt(.fs)` (reserved word `sample` — dies on Metal), `AR_SeparationGlitch_v02.fs` (TouchDesigner `sTD2DInputs` samplers), `AR_Genuary2026_day7_v01` (mislabeled pass count, fixed in v02).
- Lint rules a generator/validator should enforce: identifier↔INPUT parity (exact case), reserved-word ban (`sample`, `smooth`, `filter`), PASSES count vs PASSINDEX branches, legacy `PERSISTENT_BUFFERS` (non-persisting) vs per-pass `"PERSISTENT": true`, packed glyph constants ≤16 bits/float.
