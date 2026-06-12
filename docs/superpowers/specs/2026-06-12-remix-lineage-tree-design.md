# Remix Lineage Tree GUI — Design Spec

**Date:** 2026-06-12
**Project:** Phase-2 marquee feature of the ISF Remix Studio — the right rail becomes a visual family tree of every shader the genetic loop has produced.
**Branch:** `isf-remix-studio` (continues Modules 1+2)
**Status:** Approved in brainstorming; ready for implementation plan.

## Summary

Replace the right rail's flat Favorites list with a **lineage tree**: an indented, swatch-illustrated
tree of every compiled node in `RemixLineage` (seeds at the root, children nested under their
parents), with selection driving a compact **action strip** (live preview + promote/favorite/open).
The graph data already exists — `RemixLineage` records `parents` ids on every node — so this is
visualization + interaction, plus one small piece of new infra (snapshot capture for row swatches).

## Decisions (from brainstorming)

| Question | Decision |
|---|---|
| Crossover children (two parents) | **Nest under Parent A once**, with a ⚭ badge naming Parent B; clicking the badge selects/highlights B. Tree stays a true tree — no duplicate rows, no alias bookkeeping. |
| Node click | **Select → action strip**: single-click selects and shows a strip (live preview, directive, ↑A ↑B ★ ✎); double-click opens in the editor. One mental model for every node, any round. |
| Row visuals | **Snapshot swatches**: one frame captured at compile time via the existing `renderOnce()` → cached `CGImage` per node id. Tiny static pictures at zero per-row Metal cost; the action strip hosts the rail's only live engine. |
| Placement | **Tree replaces the rail**: favorites become ★-marked rows with a `[★ only]` filter toggle; Step Back stays at the bottom; rail widens 220 → 260px. |
| Rendering approach | **Flatten in the model** (pure DFS → rows with depth), rendered as a `LazyVStack` — not `OutlineGroup` (fights the DAG, owns its own disclosure state, styles poorly at 260px) and not a node-link canvas (overkill for v1). |

## Component 1 — `RemixTreeBuilder` (pure, TDD'd)

```swift
struct RemixTreeRow: Identifiable, Equatable {
    let id: String                  // node id
    let depth: Int                  // indent level
    let secondaryParentID: String?  // parents[1] for crossover children → ⚭ badge
}
enum RemixTreeBuilder {
    static func flatten(_ lineage: RemixLineage,
                        collapsed: Set<String>,
                        favoritesOnly: Bool) -> [RemixTreeRow]
}
```

- **Roots** = nodes with empty `parents` (round-0 seeds), in `lineage.order`.
- **Children of X** = nodes whose `parents.first == X.id`, in `lineage.order`. A crossover child
  therefore renders exactly once (under Parent A) and carries `secondaryParentID = parents[1]`.
  One rendering parent per node ⇒ true tree ⇒ no duplicate traversal, no cycles.
- **Hidden:** nodes with `.failed` or `.generating` status. The gallery owns in-flight/failed
  visibility for the current round; the tree is the album of what worked.
- `collapsed` prunes all descendants of collapsed ids (their rows simply don't emit).
- `favoritesOnly: true` returns the ★ nodes as a flat list (depth 0, insertion order) — the old
  Favorites list, expressed as a filter.

## Component 2 — `RemixStudioModel` additions

- `@Published var selectedNodeID: String?` — tree selection; the action strip renders when non-nil.
- `@Published private(set) var snapshots: [String: CGImage]` + `func storeSnapshot(id: String, image: CGImage)`.
- `func treeRows(collapsed: Set<String>, favoritesOnly: Bool) -> [RemixTreeRow]` — delegates to
  `RemixTreeBuilder.flatten`.
- `promoteToParent(_:nodeID:)` already supports `.a`/`.b`; the strip wires both buttons.
- **Seed labels (small domain change):** `RemixNode` gains `var label: String? = nil`, and
  `setParent(_:isf:)` becomes `setParent(_:isf:label:)`. `RemixStudioView.resolveParent` passes a
  human label per source: the library entry name, `"editor"`, `"pasted"`, or `"shadertoy"`. Tree
  rows display `label ?? id` — so seeds read "plasma", not "seed-0". Existing call sites compile
  unchanged (defaulted parameter); generated children leave `label` nil.

## Component 3 — snapshot capture (`TextureSnapshot` + `RemixThumbnailView` hook)

- New utility: `TextureSnapshot.cgImage(from: MTLTexture, maxSize: ~64×44) -> CGImage?`.
  Must handle the engine's output formats — `bgra8Unorm`/`rgba8Unorm` directly; float formats
  (e.g. `rgba16Float`/`rgba32Float`) via one pass through the existing passthrough blit pipeline
  into a bgra8 target first. Failure returns nil — never blocks compile reporting.
- `RemixThumbnailView` gains a NEW, additive, defaulted parameter
  `onSnapshot: ((CGImage) -> Void)? = nil` — `onCompile` is unchanged and existing call sites
  compile as-is. The capture fires inside the existing `Coordinator` compile sink, at the exact
  point it delivers `onCompile(true, nil)`: call `controller.renderOnce()` (existing API, returns
  an offscreen `MTLTexture`) → `TextureSnapshot` → deliver the image via `onSnapshot`.
- Wired wherever thumbnails already render with a known node id (gallery `childCard`, parent
  slots) → `model.storeSnapshot`. Everything that has ever been on screen gets a swatch; rows
  without one show a neutral glyph.

## Component 4 — `RemixLineageTreeView` (new file; replaces `rightRail` in `RemixStudioView`)

- Rail width 220 → **260px**.
- **Header:** `LINEAGE` + `[★ only]` toggle (view `@State`).
- **Rows** (in a `ScrollView` + `LazyVStack`): disclosure ▾/▸ (per-node collapse, view-local
  `Set<String>`), ~24×16 swatch (snapshot or glyph), label (`node.label ?? node.id` — seed name
  for round-0, child id otherwise), ⚭ badge when `secondaryParentID != nil`,
  ★ when favorite. Indent 12pt × depth. Selected row gets an accent background.
- **Interactions:** single click → `model.selectedNodeID = row.id`; ⚭ badge click →
  `selectedNodeID = secondaryParentID` (consistent "everything selects"); double-click →
  `openInEditor(node.isfSource)`.
- **Action strip** (fixed between tree and Step Back; shown while `selectedNodeID != nil`):
  one live `RemixThumbnailView(animating: true)` — the only Metal engine the rail runs —
  plus the node's directive text and buttons `↑A` `↑B` `★` `✎ open` `×` (deselect).
- **Step Back** stays at the bottom, semantics unchanged.

## Error handling & edge cases

- ★-only filter active while a non-favorite is selected → selection is NOT cleared; the strip
  stays (close via × or by selecting another node).
- `secondaryParentID` not present in lineage (shouldn't occur) → badge omitted.
- Snapshot conversion failure → glyph fallback, no error surfaced.
- Empty lineage → rail shows a hint ("Add parents and Generate — the family tree grows here").
- ★-only active with zero favorites (lineage non-empty) → distinct hint ("No favorites yet —
  ★ a child to pin it here") so the rail never goes blank with the filter stuck on.

## Testing

- **TDD `RemixTreeBuilder.flatten`:** roots in order; nesting + depth; crossover renders once
  under A with the right `secondaryParentID`; failed/generating hidden; collapse pruning
  (including nested collapse); ★-only flat list; stable ordering across calls.
- **Model tests:** selection publish, `storeSnapshot`/lookup, `treeRows` pass-through,
  `setParent` records the label on the seed node.
- **`TextureSnapshot` test:** programmatically filled bgra8 texture → correct-size CGImage;
  unsupported format → nil (not a crash).
- **Views:** build-verified (`xcodebuild` + 99-test suite stays green); the interactive loop
  (select → promote → regenerate → tree grows) joins the existing on-device gate in
  action-items.json.

## Non-goals (v1)

- Persistence across app launches (lineage is session-scoped today — unchanged).
- Node-link / canvas / pan-zoom graph layout (possible phase 3).
- Lineage export.
- Any change to Step Back semantics or the gallery.
