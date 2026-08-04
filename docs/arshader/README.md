# ARShader — imported design reference

ARShader is the native macOS performance instrument in this repo (`App/ARShader/`, target
`ARShader`). It began life in a separate TouchDesigner project at
`~/Desktop/AV_Projects/AR_Shader` and moved here on 2026-07-30 when the operator parked
TouchDesigner cold and rebuilt on the TrueISFEditor codebase.

This folder is where the design material from that earlier project now lives. It was **copied**
on 2026-07-31, not moved — the old folder is untouched and remains the historical origin, including
its TouchDesigner network, its `webui/` Svelte cockpit, and the plans that built them.

## Where ARShader docs go from here

The port deliberately split into two destinations, because two different kinds of document ended up
in the old repo:

| Kind | Home | Why |
|---|---|---|
| **New** specs, plans, notes | `docs/superpowers/{specs,plans,notes}/` | Where the superpowers skills write and look for them, and where every other ARShader doc in this repo already lives. |
| **Live smoke and test reports** | `docs/reports/` | Existing convention (`live-smoke-instrument-m1.md`, `-m2-phase2.md`). |
| **Imported reference from the AR_Shader era** | here, `docs/arshader/` | Not this repo's pipeline output. Grouping it keeps a 3,400-line superseded spec from sitting next to live ones. |

Do not add new specs or plans to this folder. It is an import, not a working directory.

## Inventory

### `ui-reference/` — 46 visual references · **gitignored**

45 JPGs plus `VDMX6-current-layout.png` (the operator's actual VDMX6 layout — the functional
baseline and muscle memory the instrument is meant to replace). 8.1 MB.

**These are excluded from git** (`.gitignore`: `docs/arshader/ui-reference/`) exactly as they were
in the old repo. They are third-party screenshots with no established provenance, and this repo is
public. They live on disk for local design work only.

Every one of the 46 files is individually reviewed in **Appendix H** of the cockpit UI spec below —
what to borrow from it and what to leave. Correspondence verified 46/46 on import, no file named in
the audit is missing and no file on disk is unaudited. Note the audit's own finding: two JPGs are
byte-identical, so there are 45 unique images across 46 files.

### `legacy-cockpit/` — the AR_Shader-era design set

| File | Status |
|---|---|
| `2026-07-24-ar-shader-adaptive-cybernetic-cockpit-ui.md` (3,423 lines) | **Platform superseded, design content live.** The UI write-up. Its Svelte/`ControlBridge`/WebSocket delivery is dead; Appendices A (information architecture), B (VDMX6 baseline), C (art direction), D (component + interaction spec) and H (the 46-file audit) are the design source for the native surface. |
| `2026-07-22-ar-shader-vj-tool-design.md` | **Largely realized.** The original native design, written before the TouchDesigner detour and revalidated by the return to native. Milestones 1–2 built its core; `AudioService`, MIDI/LFO `ControlBus`, `PresetBank`, `SyphonPublisher` and `Recorder` are still unbuilt and read as a roadmap. |
| `2026-07-30-cockpit-dynamic-decks-and-live-monitors-design.md` | **Superseded the day it was written**, banner already on the file. Kept for two findings that are still true: Video Stream Out TOP is Nvidia+Windows only, and the frozen protocol's `deckId` was never restricted to four decks. |
| `ar-shader-adaptive-cybernetic-cockpit-manifest.md` | **Superseded.** Prebuild manifest pinning a Svelte/Vite/three.js dependency set for the browser cockpit. Record of decisions only — install nothing from it. |

### Prior-art dossier — **not in this repo**

Architecture and adoption research on a third-party commercial instrument, framed as "what to
learn, what to port, and what to rebuild natively on Apple Silicon" for **ARShader 2.0**. It was
**removed from this repository on 2026-08-03 at that developer's request** and is kept privately
outside git; it is named here only so the gap in the inventory is explained rather than silent.

Two of its recommendations are live and are ARShader's own to build, independent of the research:
an MCP surface around `EngineFacade`, and generated controls plus identity-safe presets from the
ISF metadata `SlotCompiler` already parses. Both are unbuilt.

### Moved into the normal pipeline, not into this folder

These two were authored in the old repo but their own frontmatter names this one as
`target_repo`. They belong in the standard locations and are now there:

- `docs/superpowers/specs/2026-07-30-native-performance-instrument-design.md` — the native pivot
  decision and Milestone 1 spec.
- `docs/superpowers/plans/2026-07-30-native-instrument-milestone-1.md` — the M1 implementation
  plan. Executed and CONFIRMED; banner added because its frontmatter still reads `status: draft`.

## Deliberately left behind

Still in `~/Desktop/AV_Projects/AR_Shader`, not copied, because they only describe the parked
TouchDesigner build:

- `docs/superpowers/plans/2026-07-24-adaptive-cybernetic-cockpit-implementation.md` (5,741 lines,
  the Svelte cockpit build plan)
- `docs/superpowers/plans/2026-07-22-phase0-engine-spike.md`,
  `2026-07-23-phase-a-isfplayer-tox.md`, `2026-07-23-phase-b-instrument-core.md`,
  `2026-07-23-phase-c-audio-bindings.md`, `2026-07-30-monitor-transport-spike.md`
- `docs/superpowers/specs/2026-07-23-td-native-pivot-isf-player-design.md` (the pivot *to*
  TouchDesigner, itself reversed)
- `docs/derivative-report-listcomp-callback-recursion.md` (a TouchDesigner bug report)
- `_inspiration/EssentiaTD`, `_inspiration/TouchDesigner-ISF-parser`,
  `_inspiration/isf-touchdesigner` (TouchDesigner reference repos)

The phase-C audio bindings plan is the one most likely to be wanted again — if `AudioService` gets
built, its analysis design is worth reading even though its TouchDesigner implementation is not.
