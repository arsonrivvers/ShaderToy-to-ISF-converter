# TrueISFEditor — P1 Editor Spine — Design

**Date:** 2026-06-09
**Status:** Approved design (pre-implementation)

## Context & Goal

TrueISFEditor is a native macOS SwiftUI app that is a working replacement for the defunct VIDVOX
"ISF Editor". ISF (Interactive Shader Format) `.fs` files are GLSL shaders used by VJ hosts (VDMX,
CoGe). The user is a working VJ with a large personal `.fs` library.

The app currently is a *Shadertoy→ISF converter* (`AppModel` + a 3-pane `ContentView`: imported
code · ISF output · live preview). **P1 reshapes it into a document-centric ISF editor**: open a
`.fs` from a library, edit its source with syntax highlighting and inline errors, see it recompile
live, and save. Shadertoy conversion (already built, in `ShadertoyISFKit`) becomes one entry path.

This is the first of several sub-projects. Later phases (NOT in this spec):
- **P2** — Warnings as an in-app research/resolve tool (selectable/copyable, jump-to-line, GLSL/ISF lookups, fix suggestions).
- **P3** — Full input UI (image inputs, `event`, audio) + media sources (camera/video/image).
- **P4** — Pass/buffer inspector, render controls (resolution, freeze, alpha, time), export.

## Locked Decisions

- **Window model:** single-window IDE, with the output preview **detachable** into its own resizable window.
- **Code editor:** CodeMirror 6 hosted in a `WKWebView` (chosen for extensibility — future linting/autocomplete/hover-docs), vendored via esbuild like the existing ISF.js bundle.
- **Library sources:** System (`/Library/Graphics/ISF`), User (`~/Library/Graphics/ISF`), and user-added/dropped folders.
- **Engine untouched:** `ShadertoyISFKit` is not modified by P1; all work is app-layer.

## Out of Scope for P1 (resist scope creep)

- Multiple open documents / tab bar (single open document in P1; multi-doc is P2+).
- Output resolution control, freeze, display-alpha (P4) — P1 preview sizes to its panel.
- Pass/buffer inspector (P4).
- Template picker — one blank ISF skeleton only.
- "Open in ISF Editor" handoff.

## Layout

Three columns (the "Imported Shadertoy" pane is **removed** — it only served the import path, now a sheet):

```
┌─ TrueISFEditor ──────────────────────────────────────────────┐
│ Library         │ source.fs (CodeMirror, editable) │ ▶ Preview │
│ [filter…]       │ /*{ …header… }*/                 │ [render]  │
│ ▾ User          │ void main(){                      │           │
│   a.fs •        │   …                               │ Inputs:   │
│   b.fs  ◀        │ }   ⟵ inline error gutter         │ ─●─  ─●─  │
│ ▾ System (1415) │                                   │ ▢ toggle  │
│   …             │ ⚠ warnings panel (compile+conv)   │  [↗ pop]  │
└─────────────────┴───────────────────────────────────┴──────────┘
```

The editor column gets the freed space. Preview + input controls share the right column.

## Components

1. **`ISFFile`** — the open document. Fields: `url: URL?` (nil = untitled), `source: String`,
   `isDirty: Bool`, `displayName: String`. The editable artifact; the preview renders *its*
   `source`. (Renamed from the engine's `ISFDocument` to avoid the name clash.)

2. **`LibraryModel` + `LibraryView` (sidebar)** — scans the three sources and lists `.fs` files
   **lazily** (name + path only; never parse 1,400+ files). Sections: User, System, plus each
   added folder. A **filter field** (auto-focused on appear) filters by filename. Added folders
   persist in `UserDefaults`. Drag-drop a folder or "Add Folder…" to add a source. Each row shows a
   **dirty dot** when its open `ISFFile.isDirty`. **Single-click loads** the file (this is an editor
   for editing, not a viewer).

3. **`CodeEditorView`** — `NSViewRepresentable` wrapping a `WKWebView` that hosts CodeMirror 6:
   GLSL + JSON-header syntax highlighting, line numbers, **error-gutter decorations**, bracket
   matching, find. Two-way bound to `ISFFile.source`; emits **debounced (~300ms)** change events to
   Swift. Vendored bundle built with esbuild (new `vendor/` entry alongside ISF.js).

4. **Live recompile loop** — both **open-file** and **edit** events feed the same path:
   `source` set → (debounce on edit; immediate on open) → existing `ISFPreviewController.load(isf:)`
   → harness compiles → the `compile` message fans out to **three sinks**:
   - **Preview** renders.
   - **Input controls** panel is (re)populated from the parsed INPUTS with their DEFAULTs.
   - **Errors** become **inline CodeMirror gutter marks** *and* warnings-panel rows.

   > **Gate (top UX risk):** opening a file MUST populate the input controls within one render
   > cycle using DEFAULT values — not only on subsequent edits. Compile errors MUST appear as inline
   > gutter decorations at the offending line, not only in the warnings panel.

5. **Save / document semantics** — `Cmd-S` saves `source` to `url`. If untitled (from New or
   Shadertoy import), `Cmd-S` routes to **Save As** (NSSavePanel). `Cmd-Shift-S` = Save As. Dirty
   flag drives the title-bar dot and the library-row dot. `File ▸ New` = blank ISF skeleton template.

6. **Detachable output** — the preview can **pop out** into its own resizable `NSWindow` rendering
   the same source. Resolution/freeze/alpha controls are P4; P1 just detaches and resizes.

7. **Shadertoy import as a command** — `File ▸ New from Shadertoy…` opens a **sheet** running the
   existing convert flow (URL fetch / paste, warnings). On success it produces a **new untitled
   `ISFFile`** loaded into the editor. The old read-only "imported source" view, if shown at all,
   lives only inside this sheet for verification and is discarded after.

## First-Launch Behavior

On first launch, **auto-load the System and User ISF directories** with no prompt (they are
standard read-only locations every ISF tool inspects). The sidebar is pre-populated; the VJ types
in the filter, single-clicks a shader, and sees it render — the "first this gets me" moment, well
inside 60 seconds. The personal `~/Desktop/ISF`-style folder is non-standard and still requires
Add-Folder / drop.

## Data Flow

```
Library(single-click) ─▶ load text ─▶ ISFFile.source
                                          │ (immediate on open)
CodeEditor(edit) ─▶ debounce 300ms ───────┤
                                          ▼
                          ISFPreviewController.load(source)
                                          ▼  (compile message)
        ┌───────────────────┬─────────────────────┬───────────────────┐
        ▼                   ▼                     ▼
   Preview render     Input controls          Errors → editor gutter
                      (from INPUTS/DEFAULT)         + warnings panel
Save ─▶ disk (Save As if untitled)
New from Shadertoy ─▶ new untitled ISFFile
```

## Testing Strategy

- **App-logic units (TDD):** `LibraryModel` folder scan (temp-dir fixture: nested dirs, non-`.fs`
  filtered out, dedupe), `ISFFile` dirty/save transitions (open clean → edit dirty → save clean;
  untitled → Save As), blank-template generator (produces a compilable ISF).
- **CodeMirror ↔ Swift bridge:** verified via Playwright against the editor harness (mirrors how the
  preview harness is validated) — set text from Swift side, read change events, apply gutter marks.
- **Native shell:** launch-verify (no crash), confirm staged `.debug.dylib` is fresh.
- Engine remains green (57/57).

## Risks & Edges

- **1,415-file library:** lazy listing + always-focused filter; never parse-all. Sectioned by source.
- **`ISFDocument` name clash:** app document is `ISFFile`; engine keeps `ISFDocument`.
- **Hand-written ISF (not Shadertoy-derived):** fine — ISF.js compiles any valid ISF; the editor is
  source-agnostic.
- **Untitled save:** `Cmd-S` on an untitled doc must open Save As, never silently no-op.
- **Open gesture:** single-click loads; double-click is not a separate action in P1.
- **Bundle size:** CodeMirror 6 bundled offline via esbuild; `node_modules` gitignored.

## Component Boundaries (for isolation)

- `LibraryModel` — *what:* enumerates `.fs` from sources; *interface:* `sources`, `files(filtered:)`,
  `addFolder(_:)`; *depends on:* FileManager + UserDefaults. No UI, no preview knowledge.
- `ISFFile` — *what:* one editable document + dirty/save; *interface:* `source`, `isDirty`, `save()`,
  `saveAs(url:)`; *depends on:* nothing (pure model + file I/O).
- `CodeEditorView` — *what:* edits text + shows gutter marks; *interface:* `text` binding,
  `onChange`, `setDiagnostics([line])`; *depends on:* WKWebView + CodeMirror bundle. Knows nothing of ISF.
- `ISFPreviewController` (exists) — *what:* compiles + renders + reports inputs/errors; reused as-is.
- Editor screen view-model wires the four together via the data-flow above.
