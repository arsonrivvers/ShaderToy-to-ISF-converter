# ISF Remix Studio — Design Spec

**Date:** 2026-06-11
**Project:** A generative *genetic studio* for ISF shaders — breed/mutate/select loop driven by Claude/Codex.
**Branch:** `isf-remix-studio` (off `master`)
**Status:** Approved in brainstorming; ready for implementation plan.

## Summary

A new **Remix Studio** window (File ▸ Remix ISF…) that turns shader creation into a genetic loop:
pick parents → generate a batch of children (Claude/Codex, concurrently) → previews stream in → you
favorite / promote / mutate the best → repeat. New **orchestration + UI** over proven parts: the
ShaderAssist Claude/Codex runners (generation engine), the Metal preview (parent/child rendering),
and the header-authoring GUI (a chosen child opens in the editor with code + preview + sliders for free).

## Decisions (from brainstorming)

| Question | Decision |
|---|---|
| Loop model | **Full genetic studio** — crossover (breed 2 parents) + mutation (vary one favorite) + text steering + selection |
| Parent sources | Library shader · current editor shader · **pasted Shadertoy link** (fetch→convert, reuses importer) · pasted ISF |
| Batch size | **Adjustable, default 5** (4–6); children generate concurrently and stream in as they compile |
| Cost model | Flat-rate **subscriptions** → no marginal $; the limit is subscription usage, controlled by the batch dial |
| Lineage | v1 = favorites shelf + step-back, **but every child records its parents** (lineage graph from day one); the tree GUI reads that graph in phase 2 |
| Window layout | **A** — parents bay + controls on top · big center gallery · right rail (Favorites + Lineage) |
| Batch diversity | **Auto-varied mutation vectors** per child (chaotic/minimal/color-forward/motion-forward/structural…) on top of shared steer text |
| Thumbnails | Cap how many previews animate at once (favorites/promoted stay live; others freeze a frame) |

## Module 1 — Remix domain + generator (mostly testable; new code, likely in `ShadertoyISFKit` + App seam)

- **`RemixNode`** — `{ id, isfSource, parents: [id], mode (.crossover/.mutate), steer, directive, round, status (.generating/.compiled/.failed) }`. Nodes form a **lineage graph** (children record parent ids).
- **`RemixGenerator`** — assembles a generation prompt: the `shader-lineage-remix` + `isf-shader-development` + `shader-dev` skills (extended `SkillPreamble`), the parent ISF source(s), the `mode`, the shared steer text, and a per-child **mutation vector**. Fires **N concurrent `AssistProvider` calls** (existing Claude/Codex runners — injectable, subscription-based, streaming). Emits each child's ISF as it returns. Concurrency capped (~4 in flight).
- **Validation** — each returned ISF is compiled through the existing engine: compiles → `.compiled` (render preview); fails → `.failed` (⚠ + manual retry in v1; auto-repair via the existing diagnose path is phase 2).

## Module 2 — Studio UI (Layout A; App / SwiftUI)

- **Parents bay + controls (top):** Parent A/B slots sourced from library / current / pasted Shadertoy link / pasted ISF; mode toggle (Crossover ↔ Mutate-favorite); steer text; batch-size stepper (default 5); ⚡ Generate.
- **Gallery (center):** child cards stream ⚙ generating → ▶ live thumbnail → or ⚠. Per card: ★ favorite, ⇪ promote-to-parent, ↗ open-in-editor.
- **Right rail:** ★ Favorites shelf (persists across rounds) + Lineage (v1: breadcrumb/step-back; phase 2: tree GUI).
- **`RemixStudioModel`** (`@MainActor ObservableObject`) owns parents, current batch, favorites, lineage graph; drives `RemixGenerator`.
- **Thumbnails:** small reduced-fps Metal previews; cap concurrent animating previews; off-screen cards freeze a last frame.

## Data flow

```
pick parents (library/current/link/paste) ──► ⚡ Generate
  → N concurrent AssistProvider calls (skills + parents + mode + steer + per-child vector)
  → each ISF compiled → thumbnail streams into the gallery
  → ★ favorite, ⇪ promote a favorite to a parent (or Mutate it)  ──► next round
  → ↗ open a winner in the main editor → code + preview + sliders (authoring GUI)
```

## Error handling

- Generation failures map through the existing `AssistRunError` (not-authed / timeout / process-failed) → shown on the card, never blocks the rest of the batch (partial batches are valid).
- A child that doesn't compile → ⚠ card + manual retry.
- Concurrency capped so we never spawn the whole batch of CLIs at once.

## Performance — the one real cost

N live Metal thumbnails is the heaviest part. Mitigations: small thumbnails at reduced fps; cap
concurrent animating previews (favorites/promoted stay live, others freeze a frame); pause off-screen
cards. The on-device gate watches this.

## Testing

- **Module 1 (unit):** prompt assembly (skills + parents + mode + per-child vector present); lineage-graph
  integrity (parents recorded; step-back); result parsing; `RemixGenerator` against a **fake AssistProvider**
  (concurrency, partial-failure handling, compile-status mapping). The provider seam is already injectable.
- **Studio model:** batch lifecycle, favorites, promote-to-parent, step-back, against fakes.
- **On-device gate:** the live loop + N-thumbnail performance.

## Scope / phases

- **v1:** Modules 1 + 2 — the full breed → stream → pick → mutate/promote → step-back loop, with Shadertoy-link parents.
- **Phase 2 (designed-for):** lineage-**tree** GUI in the right rail; optional auto-repair of failed children.

## Reuse / dependencies

- ShaderAssist runners (`AssistProvider`, `ClaudeCodeRunner`, `CodexRunner`, `SkillPreamble`) — generation engine.
- Importer (`ShadertoyURL`, `WebKitShaderFetcher`/`ShadertoyClient`, `ISFConverter`) — Shadertoy-link parents.
- Preview/compile engine (`MetalPreviewController`, `ISFSceneSource`) — thumbnails + child validation.
- Header-authoring GUI (`HeaderAuthoringModel`, ISFHeader) — "open in editor" gives sliders for free.

## Build order

1. Module 1 (domain + generator) — testable foundation.
2. Module 2 (studio UI + thumbnails) — depends on Module 1.
3. Phase 2 (lineage tree) — later.
