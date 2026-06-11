# ISF Header Authoring — Design Spec

**Date:** 2026-06-11
**Project:** "Project B" — GUI authoring of ISF INPUTS + PASSES, plus editor autocomplete
**Branch:** `project-b-isf-header-authoring` (off `master`)
**Status:** Approved in brainstorming; ready for implementation plan.

## Summary

Add in-app GUI authoring of an ISF shader's `/*{…}*/` JSON header so the user no longer
hand-edits JSON to declare/edit INPUTS and PASSES, plus code-editor autocomplete for ISF/GLSL
identifiers. One branch, **three cleanly-separated modules**.

The code editor text (`ISFFile.source`) stays the **single source of truth**. The GUI is a live
**projection** of the header that, on edit, re-serializes the header and splices it back into the
text — **never touching the GLSL body**.

## Decisions (from brainstorming)

| Question | Decision |
|---|---|
| Scope | All three features as one project, built as three separate modules |
| Primary workflow | Both greenfield authoring and reworking imports — general-purpose header editor |
| Placement | **A** — right column's bottom panel becomes tabbed `Adjust \| Inputs \| Passes` |
| Input edit model | **A** — inline expandable rows (click a row → that type's fields) |
| Sync model | **Live two-way** — text canonical; parse text→GUI on change; GUI edit→reserialize→splice→recompile |
| GLSL scope | **Header-only** — the GUI never edits the GLSL body (no PASSINDEX scaffolding in v1) |

## Module 1 — `ISFHeader` engine (`ShadertoyISFKit`, pure, TDD)

Typed, editable model of the header block. Reuses `HeaderBuilder` emission conventions.

- `ISFInput` — `{ name, type, default, min, max, labels[], values[] }`; only fields valid for the
  type are populated. Types: `event, bool, long, float, point2D, color, image` (the 7 the preview
  supports; `audio`/`audioFFT`/`cube` deferred — preview can't render them).
- `ISFPass` — `{ target: String?, persistent: Bool, float: Bool, width: String?, height: String? }`
  (width/height are ISF expressions, e.g. `$WIDTH/2`).
- `extraKeys` — verbatim pass-through of unmodeled header keys (DESCRIPTION, CREDIT, CATEGORIES,
  ISFVSN, etc.), preserved on re-serialize.
- API:
  - `static func locate(in source: String) -> Range<String.Index>?` — find the `/*{ … }*/` block.
  - `static func parse(_ source: String) throws -> ISFHeader` — decode; throws on malformed JSON.
  - value-type mutations: add/update/remove/move for inputs and passes.
  - `func serializeHeaderJSON() -> String` — emit `{…}` (HeaderBuilder style; arrays in order;
    extra keys preserved).
  - `func write(into source: String) -> String` — replace the header block in `source` (or insert
    a minimal one if absent), leaving **every byte after `}*/` unchanged**.

## Module 2 — Authoring GUI (App, SwiftUI)

- Right column bottom panel → tabbed `Adjust | Inputs | Passes`.
  - **Adjust**: existing `PreviewControlsView` (live value knobs), unchanged.
  - **Inputs**: `InputsAuthoringView` — inline expandable rows over `header.inputs`; `+ Add input`
    type picker; expand → fields per type (numeric min/max; `long` enum label→value editor; etc.);
    delete; up/down reorder.
  - **Passes**: `PassesAuthoringView` — inline expandable rows over `header.passes`; TARGET /
    PERSISTENT / FLOAT / optional WIDTH·HEIGHT; add/delete/up-down reorder.
- `HeaderAuthoringModel` (`@MainActor ObservableObject`) owns the parsed `ISFHeader` and the live
  two-way sync. Echo-suppression mirrors `CodeEditorController`'s existing self-`setText` ignore so a
  GUI write doesn't re-trigger a redundant parse.
- Wired in `EditorScreen` via `EditorViewModel`.

## Module 3 — Editor autocomplete (CodeMirror, `vendor/codemirror/cm-entry.js`)

`@codemirror/autocomplete` with a completion source combining:
- ISF builtins from the already-loaded `symbols.json` (name + signature + summary).
- A static GLSL keyword/builtin list.
- **Declared input names**, pushed live from Swift via a new `setInputNames([…])` bridge whenever
  compiled inputs change.

Pure JS + one small Swift push (`CodeEditorController.setInputNames`) + a `vendor/codemirror` rebuild.

## Data flow

```
editor text (canonical)
  │ text change (hand-edit OR GUI write)
  ▼
HeaderAuthoringModel.parse → ISFHeader ──► Inputs/Passes tabs render
  ▲                                            │ user edits a row
  │ write(into:source) → setText               ▼
  └──────────── ISFHeader mutation ◄───────────┘
                       │ (existing recompile path)
                       ▼
              recompile → compiled inputs → Adjust tab knobs
```

## Error handling

- **Malformed header JSON** → `parse` throws → tabs show "Header JSON is invalid — fix in code" and
  disable structured edits (never write over broken JSON). Adjust tab still works off last good compile.
- **No header present** → "Add header" inserts minimal `/*{ "ISFVSN":"2.0", "INPUTS":[] }*/`.
- **Invalid / duplicate / empty names** → inline row validation blocks the write until valid; never
  emit broken ISF.

## Testing

- **Kit (TDD, fast):** round-trip stability `parse(serialize(h)) == h`; GLSL-body byte-preservation
  (everything after `}*/` unchanged); unknown-key preservation; per-type field sets; pass attributes;
  no-header insert; malformed-header throw.
- **App:** `HeaderAuthoringModel` two-way sync + echo-suppression + validation gating, against a fake
  editor.
- **Autocomplete:** `CodeEditorController.setInputNames` bridge test; JS completion source verified in
  the running app.
- **On-device gate (before merge):** tabbed panel + declare→knob-appears loop in the running app
  (per render/UI rules).

## Scope boundaries (YAGNI)

- Header-only; no GLSL/PASSINDEX scaffolding (possible later opt-in).
- 7 preview-supported input types only.
- Up/down reorder, not drag-drop, in v1.

## Build order

1. Module 1 (`ISFHeader` engine) — pure, TDD, foundation.
2. Module 2 (Authoring GUI) — depends on Module 1.
3. Module 3 (autocomplete) — independent; can land any time after Module 1's input-name source exists.
