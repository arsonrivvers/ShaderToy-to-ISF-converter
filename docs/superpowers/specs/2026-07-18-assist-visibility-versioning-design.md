# Assist Visibility + Versioning — Design

**Date:** 2026-07-18
**Origin:** Conner's on-device feedback closing the Phase D gate (2026-07-18): assist runs look hung, applied rewrites don't look unsaved, no way to see what changed, no version history in reach. Companion bug fixes (Layer Blend identity defaults `a3547ac`, apply-review overlap `12fce73`) already landed.
**Approach chosen:** A — extend `SnapshotStore` into the version system (over a separate VersionStore, or git-backed history).

## Goals

1. A running ShaderAssist task is visibly alive at all times (never "is it hung?").
2. An applied-but-unsaved rewrite is unmissable, and saving deliberately mints a numbered version (v01 → v02).
3. The editor shows which lines changed since the last save.
4. Version history is embedded in the editor as a `Diagnostics | Versions` bottom-panel toggle, with diff and restore.

Non-goals: branching history (linear timeline chosen), file-per-version on disk (one file + in-app history chosen), timed autosnapshots, VJ/performance features (standing scope fence).

## 1. Version model & save flow

- `Snapshot` gains `kind`: `save(number: Int)` / `aiApply` / `pin(name: String?)` / `safety` / `legacy`. JSON encoding uses three separate fields — `kind` (bare enum string), optional `number` (saves), optional `name` (pins) — no string-packing, so free-text pin names need no escaping (PM F5). Pre-existing snapshot files (no `kind` field) decode as `legacy` and display with their stored labels. No migration.
- **Numbers belong to saves.** On each successful ⌘S the saved state is captured as `save(vNN)`, NN = highest existing save number for the document + 1 (first save = v01). Identical-source saves mint nothing (existing dedup). AI applies and pins are labeled timeline entries and do not consume numbers.
- **Capture events:** every Save (numbered), every AI apply (pre-apply state, as today, now `kind: aiApply`), manual pin from the Versions panel, and — kept from shipped behavior (PM F3) — on document open, as `kind: safety` labeled "Opened". Nothing timed.
- **Dirty state:** the toolbar's lone "•" becomes an **"Edited — ⌘S saves vNN"** pill (computed next number). Immediately after an AI apply, a save-nudge bar replaces the review panel: "Rewrite applied — unsaved. ⌘S saves vNN · view changes" (view-changes jumps to the Versions panel diff). The nudge bar clears back to the plain dirty pill on save, on any manual edit (the "Rewrite applied" claim would be stale), or on starting a new assist run (PM F4).
- **Restore:** restoring any version first captures the current state as `safety` ("before restore"), then replaces editor text + params (existing clamp-on-restore behavior). Restored state is dirty until saved → becomes the next vNN. Timeline stays linear; nothing is deleted by restoring.
- Snapshot cap stays (30/document); pruning is oldest-first regardless of kind (a pin can age out; acceptable at cap 30).

## 2. Versions panel & in-editor change marks

- The bottom "Diagnostics (N)" header becomes a segmented toggle **`Diagnostics | Versions`**. Diagnostics keeps its badge and its current 150pt height; the Versions tab expands the panel to 280pt while selected (PM F1 — the retired `SnapshotListView` needed a 720×440 window; a usable inline diff can't live in 150pt). Versions badges the timeline count.
- **Versions rows** (newest first): kind glyph (save / AI / pin / safety), `vNN` or label, relative time. Actions per row: **Diff** (existing `DiffView`, that version → current buffer, inline in the panel), **Restore** (with safety capture). Panel header has a **pin** button (optional name prompt).
- The ⌘⌥V snapshots sheet is retired; ⌘⌥V now opens the bottom panel on the Versions tab. `SnapshotListView` is superseded by the panel view.
- **Gutter change bars:** the CodeMirror 6 editor gets a change gutter via the existing JS bridge pattern (`setDiagnostics` precedent — a new `setChangeMarks(added:[Int], changed:[Int])`). Swift computes the sets with `LineDiff` (buffer vs newest `save` snapshot's source), debounced with the existing recompile debounce. No saves yet ⇒ no bars. The gutter baseline is ALWAYS the newest save — the panel's Diff picker does not move it.

## 3. Live progress strip

- Visible while `ShaderAssistViewModel.state == .running`, as a slim strip under the bottom panel (independent of the assist sidebar's `showTerminal` disclosure): animated indeterminate bar + `taskName · elapsed · N events · active Ns ago`.
- **Second home (PM F2):** the strip's host section is inside the editor pane, which the shipped ⌘⌥E collapse can hide mid-run. While a run is active AND the editor pane is collapsed, a compact run indicator (spinner · elapsed, amber when quiet >30 s) appears in the always-visible preview-pane header; clicking it restores the editor pane. "Visibly alive at all times" must hold in every reachable pane state.
- Data: each streamed transcript line bumps an event counter + `lastEventDate` on the VM; a 1 s UI timer renders elapsed/ago. No fake percent, no ETA (chosen over ETA-style fill).
- Quiet-but-alive: if no stream activity for >30 s the activity text turns amber ("quiet 48s — still running").
- **Cancel** button on the strip, wired to the runner's existing termination path; cancel surfaces the normal `.error`/idle handling, never a hang.

## 4. Error handling

- Run failure/cancel → strip disappears; existing `.error` state with Try Again presents as today.
- Snapshot capture failures stay silent by contract (never block save/apply — existing `SnapshotStore` behavior). Failed file save shows the existing error path and mints no version.
- Corrupt/unreadable snapshot files are skipped (existing behavior); unknown `kind` strings decode as `legacy`, never crash the panel.

## 5. Testing

- Unit: version-number minting (first save, gaps after prune, dedup-no-mint), kind codec round-trip + legacy tolerance, restore-mints-safety ordering, gutter line-set derivation from `LineDiff`, elapsed/ago formatting, VM event-count/`lastEventDate` updates, cancel path.
- Bridge: gutter/setChangeMarks exercised through the existing editor harness pattern in the app suite.
- On-device gate items (feature is STAGED until Conner confirms): (1) pill shows next version number and updates across saves; (2) timeline round-trip save → AI apply → pin → restore; (3) gutter bars appear after an AI apply and clear on save; (4) progress strip live during a real rewrite, cancel works.

## Review & process notes

- PM spec review required (5+ tasks) — single-stage review, deviations only.
- Mechanic at build-done = manual CoS review (native-app exception). CS live UX review post-device-confirm, bundled with `cs-trueisf-phase-ab-params-20260717` + `cs-trueisf-phase-d-authoring-20260717`.
- Standing: no `git push` until the null_signal colleague heads-up; announce any restage before running it. **CLOSED 2026-08-03 — the heads-up was given and the colleague confirmed go-ahead (operator, this session).**
