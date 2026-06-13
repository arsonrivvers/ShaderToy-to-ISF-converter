# Remix Crossover Controls — Design Spec

**Date:** 2026-06-13
**Project:** Give the Remix Studio intentional crossover/mutation controls — fix the confirmed "children lean toward Parent A" bias and let the user steer how the two parents blend.
**Branch:** `remix-crossover-controls` (off `master` @ 271f9ca)
**Status:** Approved in brainstorming; ready for implementation plan.

## Summary

Four user-facing knobs that turn the genetic loop from "combine BOTH parents (model decides everything)"
into a steerable blend. All four are pure **prompt-injected instructions** plus state on
`RemixStudioModel` plus one gear popover — no change to the generation/concurrency machinery.

## Problem (confirmed in code)

`RemixPrompt.user` gives both parents equal textual weight, says "combine BOTH" with **no ratio**,
and always presents Parent A **first** — models anchor on the first/labeled-primary example, so
children drift toward whichever parent is structurally dominant. There is no control over the blend.

## Decisions (from brainstorming)

| Question | Decision |
|---|---|
| Balance ↔ trait-routing conflict | **Routing wins; balance fills 'auto'.** An explicitly routed trait always comes from its assigned parent; the balance dial governs only traits left on `auto`. |
| Controls placement | **Gear popover** — a `⚙ Crossover` button opens a popover with all four knobs + a one-line summary chip. Main bar stays Mode/Steer/Batch/Generate. |
| Trait set | **Structure, Color, Motion, Texture.** |
| Anchoring fix | Parents always **labeled A/B by user assignment**, but **presentation order shuffled per child**; balance/routing lines reference the labels so they stay correct regardless of order. |
| Mode-awareness | Balance + Trait routing show only in **Crossover** mode (need two parents); Variation + Directive pool show in **both** Crossover and Mutate. |
| Persistence | Settings persist via `@AppStorage` (JSON-encoded). |

## Component 1 — `RemixCrossoverSettings` (pure value type, TDD'd)

```swift
enum RemixTrait: String, CaseIterable, Codable { case structure, color, motion, texture }
enum RemixTraitSource: String, Codable { case auto, a, b }   // which parent supplies a trait

struct RemixCrossoverSettings: Codable, Equatable {
    var balance: Double = 0.5                                  // 0 = all A, 1 = all B
    var variation: Double = 0.4                                // 0 = faithful, 1 = wild
    var traitSources: [RemixTrait: RemixTraitSource] = [:]     // absent ⇒ .auto
    var enabledDirectives: Set<String> = Set(RemixDirectives.catalog)  // default: all on

    /// The prompt fragments these settings contribute, for a given mode. Crossover-only lines
    /// (balance, routing) are omitted in .mutate. Order is stable for testability.
    func promptLines(mode: RemixMode) -> [String]
    /// One-line UI summary, e.g. "70% B · adventurous · 2 traits pinned".
    var summary: String
}
```

**`promptLines(mode:)` rules:**
- **Variation** (both modes): map `variation` to 4 bands and emit one line:
  - `< 0.25` → "Stay faithful — a recognizable hybrid that clearly reads as both parents."
  - `< 0.5`  → "Balance fidelity and invention."
  - `< 0.75` → "Be adventurous — take real creative liberties while keeping both parents' DNA."
  - `≥ 0.75` → "Wild reinterpretation — treat the parents as loose inspiration, not templates."
- **Balance** (crossover only): let `pct = round(balance*100)`.
  - `pct == 50` → "Weight both parents equally."
  - else → "For any aspect not pinned below, weight the blend roughly `pct`% toward Parent B and `100-pct`% toward Parent A."
- **Trait routing** (crossover only): for each trait with a non-`.auto` source, emit
  "Take the `{trait}` primarily from Parent `{A|B}`." (sorted by `RemixTrait.allCases` order for stability).
- **Directives:** NOT emitted here — they flow through `RemixDirectives.pick(from:)` (Component 2).

## Component 2 — `RemixDirectives.pick(from:)`

Add an allowlist parameter; the batch only draws from enabled vectors.

```swift
static func pick(_ n: Int, seed: Int, from pool: [String] = catalog) -> [String]
```
- **ONE function with a defaulted `from:` parameter** — NOT a second overload. Existing call sites
  (`pick(batchSize, seed: round)`) compile unchanged because the default applies; the new callers
  pass `from: enabledPool`.
- The "enabled pool" passed by callers is the **catalog filtered to `settings.enabledDirectives`,
  in catalog order**: `RemixDirectives.catalog.filter(settings.enabledDirectives.contains)`.
- If `pool` is empty, fall back to `catalog` (never produce zero directives).

## Component 3 — `RemixStudioModel` + `RemixPrompt` wiring

**Persistence (normative):**
- `@Published var crossoverSettings = RemixCrossoverSettings() { didSet { persistSettings() } }`.
- Key constant: `private static let settingsKey = "remixCrossoverSettings"`.
- `init` calls `loadSettings()` (decode JSON from `UserDefaults.standard.data(forKey:)`; on nil or
  decode failure, keep the default-constructed value).
- `persistSettings()` JSON-encodes and writes to `UserDefaults` on every mutation (via `didSet`) —
  so settings survive a mid-session crash. (The model is not a View, so it uses `UserDefaults`
  directly, not the `@AppStorage` wrapper.)

**Labeled, shuffled parents (normative):**
- `RemixPrompt.user` signature becomes:
  `user(parents: [(label: String, source: String)], mode:, steer:, directive:, settings:)`.
  Its loop prints `--- PARENT \(label) (untrusted) ---\n\(source)` in the order given. The label is
  the source of truth for "A"/"B"; presentation order is whatever order the array arrives in.
- It appends `settings.promptLines(mode:)` after the TASK + parents lines, then the existing
  `CREATIVE DIRECTION` + optional `ALSO STEER TOWARD` lines. The security line in `system()` is
  unchanged (parents still flagged untrusted; labeling/order does not relax that).
- **Parent-order shuffle (in `RemixGenerator.generate`):** build the labeled pairs from the parent
  sources — pair index 0 → label "A", index 1 → label "B". For `mode == .crossover` with two
  parents, reorder the **pairs array** per child using a deterministic seed
  `seed = round * 1000 + slot` (batch ≤ 8, so this never collides across rounds): a 2-element array
  has two orderings — present A-first when `seed` is even, B-first when odd. Labels travel with their
  source, so "PARENT A" always names parent-slot-A regardless of print position. Mutate mode passes a
  single pair `[("A", source)]` (the mutate prompt never references A/B).
- `RemixStudioModel.generate` passes `crossoverSettings` through and computes the enabled directive
  pool once: `RemixDirectives.catalog.filter(crossoverSettings.enabledDirectives.contains)`.

**Placeholder/child directive consistency (normative):**
- `RemixStudioModel.makePlaceholders` MUST use the same filtered pool and seed as the generator, so a
  placeholder card's `directive` matches the child that replaces it. Change its signature to accept
  the pool: `makePlaceholders(round:size:parents:pool:)` and call
  `RemixDirectives.pick(size, seed: round, from: pool)`. The generator likewise calls
  `RemixDirectives.pick(batchSize, seed: round, from: pool)` with the identical pool — so
  `directives[slot]` matches 1:1 between placeholder and child.

## Component 4 — `RemixCrossoverPopover` (new view) + bar button

- `⚙ Crossover` button sits in the existing **Batch/Generate `HStack`** (after the Generate button)
  in `RemixStudioView.controls`; tapping it opens a `.popover` hosting `RemixCrossoverPopover`. The
  one-line summary chip (`crossoverSettings.summary`, `.caption2`, secondary color) renders as a new
  line directly **below** that HStack within the controls `VStack`.
- Popover contents (mode-aware):
  - **Balance** slider (crossover only) — labeled "Parent A … Parent B", value shown as % B.
  - **Variation** slider (both) — labeled "Faithful … Wild".
  - **Trait routing** (crossover only) — four rows, each a 3-way segmented picker `A / auto / B`.
  - **Directive pool** (both) — six toggles over `RemixDirectives.catalog`.
  - A reset-to-defaults button.
- Summary chip next to the gear button shows `crossoverSettings.summary`.

## Error handling & edge cases

- Empty directive pool → falls back to full catalog (Component 2); UI shows a subtle hint.
- Balance at exactly 0.5 with no routed traits → "weight both equally" (no behavioral surprise).
- Mutate mode → popover hides balance + routing; `promptLines(.mutate)` omits them.
- AppStorage decode failure (older/corrupt blob) → fall back to `RemixCrossoverSettings()` defaults.
- Shuffle determinism: seeded by round+slot so tests are stable and a batch still varies child-to-child.

## Testing (TDD)

- `RemixCrossoverSettings.promptLines`: balanced (==50) vs leaned line; routing emits per pinned trait
  in trait order; routed traits + balance coexist (both lines present); all four variation bands;
  `.mutate` omits balance + routing but keeps variation; stable ordering.
- `summary` formatting (balanced / leaned / N traits pinned / N vectors off).
- `RemixDirectives.pick(from:)`: respects allowlist; empty pool ⇒ full catalog; deterministic by seed.
- Settings Codable round-trip through JSON (and a corrupt-blob → defaults path).
- Parent-order shuffle: with `seed = round*1000+slot`, even seed ⇒ A-first, odd ⇒ B-first, and the
  "A"/"B" labels stay bound to slot identity in both orderings.
- Placeholder/child directive parity: `makePlaceholders(...pool:)` and the generator produce the same
  `directives[slot]` for a given (round, slot, pool) — including a reduced pool (e.g. 2 enabled).
- Popover: build-verified; interaction joins the on-device gate.

## Non-goals (v1)

- Per-trait *blend* percentages (traits are A/B/auto, not 30/70) — possible later.
- Saving/naming setting presets.
- Applying these controls to anything outside the Remix generation prompt.
