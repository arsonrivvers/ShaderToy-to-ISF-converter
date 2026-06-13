# Remix Crossover Controls Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add four steerable crossover/mutation knobs to the Remix Studio — Parent balance A↔B (fixing the confirmed Parent-A lean), Variation, Trait routing, and Directive pool — as prompt-injected instructions surfaced in a gear popover.

**Architecture:** A pure `RemixCrossoverSettings` value type turns the four knobs into prompt fragments (`promptLines(mode:)`) and a summary string. `RemixStudioModel` owns one persisted `crossoverSettings`. `RemixPrompt.user` takes labeled parent pairs + settings; `RemixGenerator` shuffles parent presentation order per child (pure helper, deterministic) and draws directives from the enabled pool. A `RemixCrossoverPopover` exposes all four knobs from a `⚙ Crossover` button. No change to the generation/concurrency machinery.

**Tech Stack:** Swift / SwiftUI / Swift Concurrency, XCTest in `TrueISFEditorTests` (xcodegen + xcodebuild). macOS 13.0 target.

**Spec:** `docs/superpowers/specs/2026-06-13-remix-crossover-controls-design.md`

**Branch:** `remix-crossover-controls` (off `master` @ 271f9ca).

**House rules (same as prior Remix work):** every new app source file that unit tests touch must be added to the **explicit** `TrueISFEditorTests` source list in `App/project.yml` (after the existing `TrueISFEditor/Remix/...` entries), then `cd App && xcodegen generate`. View-only files (the popover) are NOT added to the test target. Test classes touching `@MainActor` types are `@MainActor final class … : XCTestCase`. Build/verify command (warm `ddata-review`):

```bash
cd App && xcodegen generate && xcodebuild -project TrueISFEditor.xcodeproj -scheme TrueISFEditor -derivedDataPath ./ddata-review -destination 'platform=macOS,arch=arm64' ARCHS=arm64 ONLY_ACTIVE_ARCH=YES test 2>&1 | grep -E 'error:|Executed [0-9]+ tests, with|\*\* TEST'
```

(For build-only, replace `test` with `build`, expect `** BUILD SUCCEEDED **`. Baseline before this plan: 116 tests, 3 skipped.)

**Codable note:** `traitSources` is keyed by `String` (the trait's rawValue), not by the `RemixTrait` enum, to avoid JSONEncoder's enum-keyed-dictionary-as-array gotcha. Accessors hide the string keys.

---

## File structure

| File | Responsibility | Tested by |
|---|---|---|
| `App/TrueISFEditor/Remix/RemixCrossoverSettings.swift` (new) | Value type: 4 knobs + `promptLines(mode:)` + `summary` + trait accessors | unit |
| `App/TrueISFEditor/Remix/RemixDirectives.swift` (modify) | `pick(_:seed:from:)` defaulted allowlist | unit |
| `App/TrueISFEditor/Remix/RemixPrompt.swift` (modify) | `user` takes `[(label,source)]` pairs + `settings:`; injects `promptLines` | unit |
| `App/TrueISFEditor/Remix/RemixGenerator.swift` (modify) | `generate` gains `settings:`/`pool:`; pure `orderedParents` shuffle | unit |
| `App/TrueISFEditor/Remix/RemixStudioModel.swift` (modify) | `crossoverSettings` + persistence; filtered pool; `makePlaceholders(pool:)` | unit |
| `App/TrueISFEditor/Remix/RemixCrossoverPopover.swift` (new) | The gear popover UI (4 knobs + reset) | build + on-device |
| `App/TrueISFEditor/Remix/RemixStudioView.swift` (modify) | `⚙ Crossover` button + popover + summary chip | build + on-device |
| `App/TrueISFEditorTests/RemixCrossoverSettingsTests.swift` (new) | promptLines / summary / Codable | — |
| `App/TrueISFEditorTests/RemixDirectivesTests.swift` (new or existing) | `pick(from:)` allowlist | — |
| `App/TrueISFEditorTests/RemixGeneratorTests.swift` (modify) | `orderedParents` shuffle determinism | — |
| `App/TrueISFEditorTests/RemixPromptTests.swift` (modify) | labeled pairs + settings injection | — |
| `App/TrueISFEditorTests/RemixStudioModelTests.swift` (modify) | persistence round-trip + placeholder/child parity | — |

---

### Task 1: `RemixCrossoverSettings` value type (pure, TDD)

**Files:**
- Create: `App/TrueISFEditor/Remix/RemixCrossoverSettings.swift`
- Create: `App/TrueISFEditorTests/RemixCrossoverSettingsTests.swift`
- Modify: `App/project.yml`

- [ ] **Step 1: Write the failing tests**

`App/TrueISFEditorTests/RemixCrossoverSettingsTests.swift`:

```swift
import XCTest
@testable import TrueISFEditor

final class RemixCrossoverSettingsTests: XCTestCase {
    private func lines(_ s: RemixCrossoverSettings, _ mode: RemixMode) -> String {
        s.promptLines(mode: mode).joined(separator: "\n").lowercased()
    }

    func test_defaults_balancedAndAllDirectivesEnabled() {
        let s = RemixCrossoverSettings()
        XCTAssertEqual(s.balance, 0.5, accuracy: 0.0001)
        XCTAssertEqual(s.enabledDirectives, Set(RemixDirectives.catalog))
        XCTAssertTrue(s.traitSources.isEmpty)
    }

    func test_balanced_emitsEqualWeightLine_crossover() {
        let l = lines(RemixCrossoverSettings(), .crossover)
        XCTAssertTrue(l.contains("equally"))
        XCTAssertFalse(l.contains("toward parent b"))
    }

    func test_leaned_emitsPercentLine_crossover() {
        var s = RemixCrossoverSettings(); s.balance = 0.7
        let l = lines(s, .crossover)
        XCTAssertTrue(l.contains("70%"))
        XCTAssertTrue(l.contains("toward parent b"))
        XCTAssertTrue(l.contains("30%"))
    }

    func test_traitRouting_emitsPerPinnedTrait_inTraitOrder() {
        var s = RemixCrossoverSettings()
        s.setSource(.b, for: .motion)
        s.setSource(.a, for: .structure)
        let pieces = s.promptLines(mode: .crossover)
        let joined = pieces.joined(separator: "\n")
        XCTAssertTrue(joined.contains("Take the structure primarily from Parent A"))
        XCTAssertTrue(joined.contains("Take the motion primarily from Parent B"))
        // structure precedes motion (RemixTrait.allCases order)
        XCTAssertLessThan(joined.range(of: "structure")!.lowerBound,
                          joined.range(of: "motion")!.lowerBound)
    }

    func test_routedTrait_andBalance_coexist() {
        var s = RemixCrossoverSettings(); s.balance = 0.7; s.setSource(.a, for: .structure)
        let l = lines(s, .crossover)
        XCTAssertTrue(l.contains("structure primarily from parent a"))  // routing line
        XCTAssertTrue(l.contains("70%"))                                // balance line (for auto traits)
    }

    func test_variationBands() {
        func band(_ v: Double) -> String { var s = RemixCrossoverSettings(); s.variation = v; return lines(s, .crossover) }
        XCTAssertTrue(band(0.1).contains("faithful"))
        XCTAssertTrue(band(0.4).contains("balance"))
        XCTAssertTrue(band(0.6).contains("adventurous"))
        XCTAssertTrue(band(0.9).contains("wild"))
    }

    func test_mutate_omitsBalanceAndRouting_keepsVariation() {
        var s = RemixCrossoverSettings(); s.balance = 0.7; s.setSource(.a, for: .structure); s.variation = 0.9
        let l = lines(s, .mutate)
        XCTAssertFalse(l.contains("parent b"))
        XCTAssertFalse(l.contains("primarily from parent"))
        XCTAssertTrue(l.contains("wild"))            // variation still present in mutate
    }

    func test_summary_reflectsState() {
        var s = RemixCrossoverSettings()
        XCTAssertTrue(s.summary.lowercased().contains("balanced"))
        s.balance = 0.7; s.setSource(.a, for: .structure)
        XCTAssertTrue(s.summary.contains("70% B"))
        XCTAssertTrue(s.summary.lowercased().contains("1 trait"))
    }

    func test_codableRoundTrip() throws {
        var s = RemixCrossoverSettings(); s.balance = 0.7; s.variation = 0.8
        s.setSource(.b, for: .color); s.enabledDirectives = ["lean minimal and restrained"]
        let data = try JSONEncoder().encode(s)
        let back = try JSONDecoder().decode(RemixCrossoverSettings.self, from: data)
        XCTAssertEqual(s, back)
    }
}
```

- [ ] **Step 2: Register the file in `App/project.yml` and regenerate**

In the `TrueISFEditorTests` target's explicit source list (after `- TrueISFEditor/Remix/RemixTreeBuilder.swift`), add:

```yaml
      - TrueISFEditor/Remix/RemixCrossoverSettings.swift
```

Create an EMPTY `App/TrueISFEditor/Remix/RemixCrossoverSettings.swift`, then `cd App && xcodegen generate`.

- [ ] **Step 3: Run tests to verify they fail**

Run the house test command. Expected: compile errors — `RemixCrossoverSettings` / `RemixTrait` / `RemixTraitSource` not found.

- [ ] **Step 4: Implement**

`App/TrueISFEditor/Remix/RemixCrossoverSettings.swift`:

```swift
import Foundation

enum RemixTrait: String, CaseIterable, Codable { case structure, color, motion, texture }
enum RemixTraitSource: String, Codable { case auto, a, b }

/// The four crossover knobs as a pure value type. Turns into prompt fragments via `promptLines`.
/// `traitSources` is keyed by trait rawValue (Codable-safe; enum-keyed dicts encode badly).
struct RemixCrossoverSettings: Codable, Equatable {
    var balance: Double = 0.5                                   // 0 = all A, 1 = all B
    var variation: Double = 0.4                                 // 0 = faithful, 1 = wild
    var traitSources: [String: RemixTraitSource] = [:]          // trait.rawValue -> source (absent ⇒ auto)
    var enabledDirectives: Set<String> = Set(RemixDirectives.catalog)

    func source(for trait: RemixTrait) -> RemixTraitSource { traitSources[trait.rawValue] ?? .auto }
    mutating func setSource(_ s: RemixTraitSource, for trait: RemixTrait) {
        if s == .auto { traitSources[trait.rawValue] = nil } else { traitSources[trait.rawValue] = s }
    }

    /// Prompt fragments these settings contribute. Crossover-only lines (balance, routing) are
    /// omitted in `.mutate`. Stable order: variation, balance, then routing in RemixTrait order.
    func promptLines(mode: RemixMode) -> [String] {
        var out: [String] = [variationLine]
        guard mode == .crossover else { return out }
        out.append(balanceLine)
        for trait in RemixTrait.allCases {
            let s = source(for: trait)
            guard s != .auto else { continue }
            out.append("Take the \(trait.rawValue) primarily from Parent \(s == .a ? "A" : "B").")
        }
        return out
    }

    private var variationLine: String {
        switch variation {
        case ..<0.25: return "Stay faithful — a recognizable hybrid that clearly reads as both parents."
        case ..<0.5:  return "Balance fidelity and invention."
        case ..<0.75: return "Be adventurous — take real creative liberties while keeping both parents' DNA."
        default:      return "Wild reinterpretation — treat the parents as loose inspiration, not templates."
        }
    }

    private var balanceLine: String {
        let pct = Int((balance * 100).rounded())
        if pct == 50 { return "Weight both parents equally." }
        return "For any aspect not pinned below, weight the blend roughly \(pct)% toward Parent B "
            + "and \(100 - pct)% toward Parent A."
    }

    /// One-line UI summary, e.g. "70% B · adventurous · 1 trait pinned · 2 vectors off".
    var summary: String {
        var parts: [String] = []
        let pct = Int((balance * 100).rounded())
        parts.append(pct == 50 ? "balanced" : (pct > 50 ? "\(pct)% B" : "\(100 - pct)% A"))
        switch variation {
        case ..<0.25: parts.append("faithful")
        case ..<0.5:  parts.append("balanced mix")
        case ..<0.75: parts.append("adventurous")
        default:      parts.append("wild")
        }
        let pinned = RemixTrait.allCases.filter { source(for: $0) != .auto }.count
        if pinned > 0 { parts.append("\(pinned) trait\(pinned == 1 ? "" : "s") pinned") }
        let off = RemixDirectives.catalog.count - enabledDirectives.count
        if off > 0 { parts.append("\(off) vector\(off == 1 ? "" : "s") off") }
        return parts.joined(separator: " · ")
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run the house test command. Expected: `Executed 125 tests, with 3 tests skipped and 0 failures` (116 + 9 new).

- [ ] **Step 6: Commit**

```bash
git add App/TrueISFEditor/Remix/RemixCrossoverSettings.swift App/TrueISFEditorTests/RemixCrossoverSettingsTests.swift App/project.yml
git commit -m "feat(remix): RemixCrossoverSettings — knobs to prompt lines + summary

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 2: `RemixDirectives.pick(from:)` allowlist (TDD)

**Files:**
- Modify: `App/TrueISFEditor/Remix/RemixDirectives.swift`
- Create: `App/TrueISFEditorTests/RemixDirectivesTests.swift`
- Modify: `App/project.yml` (only if `RemixDirectives.swift` is not already in the test target — it is, via the existing Remix entries; verify and skip if present)

- [ ] **Step 1: Write the failing tests**

`App/TrueISFEditorTests/RemixDirectivesTests.swift`:

```swift
import XCTest
@testable import TrueISFEditor

final class RemixDirectivesTests: XCTestCase {
    func test_pick_default_usesFullCatalog() {
        let got = RemixDirectives.pick(3, seed: 0)
        XCTAssertEqual(got.count, 3)
        XCTAssertTrue(got.allSatisfy(RemixDirectives.catalog.contains))
    }

    func test_pick_from_restrictsToPool() {
        let pool = ["lean minimal and restrained", "emphasize bold color and palette shifts"]
        let got = RemixDirectives.pick(4, seed: 1, from: pool)
        XCTAssertEqual(got.count, 4)
        XCTAssertTrue(got.allSatisfy(pool.contains))
    }

    func test_pick_emptyPool_fallsBackToCatalog() {
        let got = RemixDirectives.pick(2, seed: 0, from: [])
        XCTAssertEqual(got.count, 2)
        XCTAssertTrue(got.allSatisfy(RemixDirectives.catalog.contains))
    }

    func test_pick_deterministicBySeed() {
        XCTAssertEqual(RemixDirectives.pick(5, seed: 3, from: RemixDirectives.catalog),
                       RemixDirectives.pick(5, seed: 3, from: RemixDirectives.catalog))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

First add `RemixDirectivesTests.swift` is automatically picked up (the test target globs `TrueISFEditorTests`). Run the house test command. Expected: compile error — `pick(_:seed:from:)` not found (the `from:` label).

- [ ] **Step 3: Implement**

Replace `RemixDirectives.pick` in `App/TrueISFEditor/Remix/RemixDirectives.swift`:

```swift
    /// `seed` rotates the starting point so successive rounds don't always lead with the same vector.
    /// `from` restricts the draw to an allowlist (the user's enabled directive pool); an empty pool
    /// falls back to the full catalog so we never produce zero directives.
    static func pick(_ n: Int, seed: Int, from pool: [String] = catalog) -> [String] {
        let source = pool.isEmpty ? catalog : pool
        guard n > 0, !source.isEmpty else { return [] }
        return (0..<n).map { source[(seed + $0) % source.count] }
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run the house test command. Expected: `Executed 129 tests, with 3 tests skipped and 0 failures` (125 + 4 new). Existing callers (`RemixGenerator`, `RemixStudioModel.makePlaceholders`) compile unchanged because `from:` is defaulted.

- [ ] **Step 5: Commit**

```bash
git add App/TrueISFEditor/Remix/RemixDirectives.swift App/TrueISFEditorTests/RemixDirectivesTests.swift
git commit -m "feat(remix): RemixDirectives.pick(from:) — restrict batch to enabled pool

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 3: `RemixPrompt.user` labeled pairs + settings injection (TDD)

**Files:**
- Modify: `App/TrueISFEditor/Remix/RemixPrompt.swift`
- Modify: `App/TrueISFEditor/Remix/RemixGenerator.swift` (call site only — keep it compiling)
- Modify: `App/TrueISFEditorTests/RemixPromptTests.swift`

- [ ] **Step 1: Rewrite the prompt tests for the new signature**

Replace the two `user(...)` tests in `App/TrueISFEditorTests/RemixPromptTests.swift` with:

```swift
    func test_crossover_user_includesBothParents_mode_steer_directive() {
        let p = RemixPrompt.user(parents: [("A", "/*{A}*/ a"), ("B", "/*{B}*/ b")],
                                 mode: .crossover, steer: "wavy", directive: "lean chaotic")
        XCTAssertTrue(p.contains("/*{A}*/ a"))
        XCTAssertTrue(p.contains("/*{B}*/ b"))
        XCTAssertTrue(p.contains("PARENT A"))
        XCTAssertTrue(p.contains("PARENT B"))
        XCTAssertTrue(p.lowercased().contains("crossover") || p.lowercased().contains("breed"))
        XCTAssertTrue(p.contains("wavy"))
        XCTAssertTrue(p.contains("lean chaotic"))
    }

    func test_mutate_user_singleParent() {
        let p = RemixPrompt.user(parents: [("A", "/*{A}*/ a")], mode: .mutate, steer: "", directive: "lean minimal")
        XCTAssertTrue(p.contains("/*{A}*/ a"))
        XCTAssertTrue(p.lowercased().contains("mutate") || p.lowercased().contains("vary"))
    }

    func test_user_injectsSettingsPromptLines() {
        var s = RemixCrossoverSettings(); s.balance = 0.7
        let p = RemixPrompt.user(parents: [("A", "a"), ("B", "b")],
                                 mode: .crossover, steer: "", directive: "d", settings: s)
        XCTAssertTrue(p.contains("70%"))           // balance line injected
    }

    func test_user_labelOrderFollowsArrayOrder_butLabelsAreExplicit() {
        // B-first presentation; labels still name the right source.
        let p = RemixPrompt.user(parents: [("B", "srcB"), ("A", "srcA")],
                                 mode: .crossover, steer: "", directive: "d")
        let bIdx = p.range(of: "PARENT B")!.lowerBound
        let aIdx = p.range(of: "PARENT A")!.lowerBound
        XCTAssertLessThan(bIdx, aIdx)              // printed B before A
        XCTAssertTrue(p.contains("srcB"))
        XCTAssertTrue(p.contains("srcA"))
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run the house test command. Expected: compile error — `user` expects `[String]`, got `[(String, String)]` / unknown `settings:`.

- [ ] **Step 3: Implement the new `RemixPrompt.user`**

Replace `user(...)` in `App/TrueISFEditor/Remix/RemixPrompt.swift`:

```swift
    static func user(parents: [(label: String, source: String)], mode: RemixMode, steer: String,
                     directive: String, settings: RemixCrossoverSettings = RemixCrossoverSettings()) -> String {
        var parts: [String] = []
        switch mode {
        case .crossover:
            parts.append("TASK: Crossover-breed a NEW child shader that genuinely combines the visual "
                + "character of BOTH parents below — not a copy of either.")
        case .mutate:
            parts.append("TASK: Mutate the parent below into a NEW variation — keep its essence but "
                + "evolve it in a fresh direction.")
        }
        for p in parents {
            parts.append("--- PARENT \(p.label) (untrusted) ---\n\(p.source)")
        }
        parts.append(contentsOf: settings.promptLines(mode: mode))
        parts.append("CREATIVE DIRECTION: \(directive).")
        if !steer.trimmingCharacters(in: .whitespaces).isEmpty {
            parts.append("ALSO STEER TOWARD: \(steer).")
        }
        return parts.joined(separator: "\n\n")
    }
```

- [ ] **Step 4: Fix the generator call site so the project compiles**

In `App/TrueISFEditor/Remix/RemixGenerator.swift`, the call inside `launch(_:)` currently is:

```swift
                let prompt = RemixPrompt.user(parents: parents, mode: mode, steer: steer, directive: directive)
```

Change ONLY this line to build labeled pairs by index (no shuffle/settings yet — those arrive in Task 4):

```swift
                let labeled = parents.enumerated().map { (label: $0.offset == 0 ? "A" : "B", source: $0.element) }
                let prompt = RemixPrompt.user(parents: labeled, mode: mode, steer: steer, directive: directive)
```

- [ ] **Step 5: Run tests to verify they pass**

Run the house test command. Expected: `Executed 131 tests, with 3 tests skipped and 0 failures` (129 + 2 net new prompt tests; the two rewritten tests replace originals).

- [ ] **Step 6: Commit**

```bash
git add App/TrueISFEditor/Remix/RemixPrompt.swift App/TrueISFEditor/Remix/RemixGenerator.swift App/TrueISFEditorTests/RemixPromptTests.swift
git commit -m "feat(remix): RemixPrompt.user takes labeled pairs + injects settings lines

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 4: `RemixGenerator` — settings/pool params + deterministic parent shuffle (TDD)

**Files:**
- Modify: `App/TrueISFEditor/Remix/RemixGenerator.swift`
- Modify: `App/TrueISFEditorTests/RemixGeneratorTests.swift`

- [ ] **Step 1: Write the failing tests for the pure ordering helper**

Append to `App/TrueISFEditorTests/RemixGeneratorTests.swift` (inside the existing `@MainActor final class RemixGeneratorTests`):

```swift
    func test_orderedParents_evenSeed_keepsAFirst() {
        let pairs = [(label: "A", source: "a"), (label: "B", source: "b")]
        let out = RemixGenerator.orderedParents(pairs, seed: 4000)   // even
        XCTAssertEqual(out.map(\.label), ["A", "B"])
    }
    func test_orderedParents_oddSeed_putsBFirst() {
        let pairs = [(label: "A", source: "a"), (label: "B", source: "b")]
        let out = RemixGenerator.orderedParents(pairs, seed: 4001)   // odd
        XCTAssertEqual(out.map(\.label), ["B", "A"])
        XCTAssertEqual(out.first?.source, "b")                       // label travels with source
    }
    func test_orderedParents_singleParent_unchanged() {
        let pairs = [(label: "A", source: "a")]
        XCTAssertEqual(RemixGenerator.orderedParents(pairs, seed: 1).map(\.label), ["A"])
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run the house test command. Expected: compile error — `RemixGenerator.orderedParents` not found.

- [ ] **Step 3: Implement the helper + thread settings/pool through `generate`**

In `App/TrueISFEditor/Remix/RemixGenerator.swift`:

(a) Add the pure helper (static, top of the type body):

```swift
    /// Presentation order for a child's parents. Two parents alternate by seed parity (even ⇒ A-first,
    /// odd ⇒ B-first) to defeat first-position anchoring; labels travel with their source so "A"
    /// always names parent-slot-A regardless of print order. Other counts are returned unchanged.
    static func orderedParents(_ pairs: [(label: String, source: String)],
                               seed: Int) -> [(label: String, source: String)] {
        guard pairs.count == 2 else { return pairs }
        return seed % 2 == 0 ? pairs : [pairs[1], pairs[0]]
    }
```

(b) Change the `generate` signature to accept settings + pool (both defaulted so any other caller is unaffected):

```swift
    func generate(parents: [String], mode: RemixMode, steer: String, batchSize: Int, round: Int,
                  settings: RemixCrossoverSettings = RemixCrossoverSettings(),
                  pool: [String] = RemixDirectives.catalog,
                  onChild: @escaping (RemixNode) -> Void,
                  onLog: @escaping @Sendable (String, String) -> Void = { _, _ in }) async {
```

(c) Replace `let directives = RemixDirectives.pick(batchSize, seed: round)` with:

```swift
        let directives = RemixDirectives.pick(batchSize, seed: round, from: pool)
```

(d) Replace the Task-3 call-site block inside `launch(_:)` with the shuffled, settings-aware version:

```swift
                let labeled = parents.enumerated().map { (label: $0.offset == 0 ? "A" : "B", source: $0.element) }
                let ordered = RemixGenerator.orderedParents(labeled, seed: round * 1000 + slot)
                let prompt = RemixPrompt.user(parents: ordered, mode: mode, steer: steer,
                                              directive: directive, settings: settings)
```

- [ ] **Step 4: Run tests to verify they pass**

Run the house test command. Expected: `Executed 134 tests, with 3 tests skipped and 0 failures` (131 + 3 new). The existing `RemixStudioModel.generate` caller still compiles (settings/pool defaulted).

- [ ] **Step 5: Commit**

```bash
git add App/TrueISFEditor/Remix/RemixGenerator.swift App/TrueISFEditorTests/RemixGeneratorTests.swift
git commit -m "feat(remix): generator threads settings/pool + deterministic parent shuffle

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 5: `RemixStudioModel` — settings, persistence, pool wiring (TDD)

**Files:**
- Modify: `App/TrueISFEditor/Remix/RemixStudioModel.swift`
- Modify: `App/TrueISFEditorTests/RemixStudioModelTests.swift`

- [ ] **Step 1: Write the failing tests**

Append to `App/TrueISFEditorTests/RemixStudioModelTests.swift` (inside the existing class):

```swift
    func test_crossoverSettings_persistAcrossModelInstances() {
        UserDefaults.standard.removeObject(forKey: "remixCrossoverSettings")
        let m1 = model([.success(isf)])
        m1.crossoverSettings.balance = 0.8
        let m2 = model([.success(isf)])               // fresh instance reads persisted blob
        XCTAssertEqual(m2.crossoverSettings.balance, 0.8, accuracy: 0.0001)
        UserDefaults.standard.removeObject(forKey: "remixCrossoverSettings")
    }

    func test_corruptSettingsBlob_fallsBackToDefaults() {
        UserDefaults.standard.set(Data("not json".utf8), forKey: "remixCrossoverSettings")
        let m = model([.success(isf)])
        XCTAssertEqual(m.crossoverSettings.balance, 0.5, accuracy: 0.0001)  // default
        UserDefaults.standard.removeObject(forKey: "remixCrossoverSettings")
    }

    func test_makePlaceholders_directivesMatchGenerator_forReducedPool() {
        let pool = ["lean minimal and restrained", "emphasize bold color and palette shifts"]
        let placeholders = RemixStudioModel.makePlaceholders(round: 2, size: 4, parents: [], pool: pool)
        let generatorDirectives = RemixDirectives.pick(4, seed: 2, from: pool)
        XCTAssertEqual(placeholders.map(\.directive), generatorDirectives)
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run the house test command. Expected: compile errors — `crossoverSettings` not found; `makePlaceholders` has no `pool:` parameter.

- [ ] **Step 3: Implement**

In `App/TrueISFEditor/Remix/RemixStudioModel.swift`:

(a) Add the persisted property + key near the other `@Published` properties:

```swift
    private static let settingsKey = "remixCrossoverSettings"
    @Published var crossoverSettings = RemixCrossoverSettings() { didSet { persistSettings() } }
```

(b) In `init`, after `self.generator = generator`, load persisted settings (assign to backing store WITHOUT triggering didSet re-persist is fine — a redundant write is harmless, but assign directly):

```swift
    init(generator: RemixGenerator) {
        self.generator = generator
        if let data = UserDefaults.standard.data(forKey: Self.settingsKey),
           let decoded = try? JSONDecoder().decode(RemixCrossoverSettings.self, from: data) {
            self.crossoverSettings = decoded
        }
    }
```

(Note: assigning in `init` triggers `didSet`, which calls `persistSettings()` writing the same blob back — harmless and keeps the code simple.)

(c) Add `persistSettings` near the other helpers:

```swift
    private func persistSettings() {
        if let data = try? JSONEncoder().encode(crossoverSettings) {
            UserDefaults.standard.set(data, forKey: Self.settingsKey)
        }
    }
```

(d) Change `makePlaceholders` to accept the pool:

```swift
    static func makePlaceholders(round: Int, size: Int, parents: [String], pool: [String]) -> [RemixNode] {
        let directives = RemixDirectives.pick(size, seed: round, from: pool)
        return (0..<size).map { slot in
            RemixNode(id: "r\(round)-\(slot)", isfSource: "", parents: parents, mode: .crossover,
                      steer: "", directive: directives[slot], round: round, status: .generating)
        }
    }
```

(e) In `generate()`, compute the pool once and pass settings + pool to both `makePlaceholders` and the generator:

```swift
        let pool = RemixDirectives.catalog.filter(crossoverSettings.enabledDirectives.contains)
        currentBatch = Self.makePlaceholders(round: r, size: batchSize, parents: pids, pool: pool)
        await generator.generate(
            parents: parentSources, mode: mode, steer: steer, batchSize: batchSize, round: r,
            settings: crossoverSettings, pool: pool,
            onChild: { [weak self] node in
```

(leave the rest of the `generate()` body unchanged).

- [ ] **Step 4: Run tests to verify they pass**

Run the house test command. Expected: `Executed 137 tests, with 3 tests skipped and 0 failures` (134 + 3 new).

- [ ] **Step 5: Commit**

```bash
git add App/TrueISFEditor/Remix/RemixStudioModel.swift App/TrueISFEditorTests/RemixStudioModelTests.swift
git commit -m "feat(remix): model owns persisted crossoverSettings + feeds pool/settings to generation

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 6: `RemixCrossoverPopover` + studio bar wiring

**Files:**
- Create: `App/TrueISFEditor/Remix/RemixCrossoverPopover.swift`
- Modify: `App/TrueISFEditor/Remix/RemixStudioView.swift`

Build-verified; interaction joins the on-device gate. The popover file is NOT added to the test target.

- [ ] **Step 1: Create the popover view**

`App/TrueISFEditor/Remix/RemixCrossoverPopover.swift`:

```swift
import SwiftUI

/// The ⚙ Crossover settings popover: balance + variation sliders, a per-trait routing matrix, and a
/// directive-pool toggle list. Balance + routing show only in Crossover mode (they need two parents).
struct RemixCrossoverPopover: View {
    @ObservedObject var model: RemixStudioModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Crossover settings").font(.headline)
                Spacer()
                Button("Reset") { model.crossoverSettings = RemixCrossoverSettings() }
                    .font(.caption).buttonStyle(.link)
            }

            if model.mode == .crossover {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Parent balance").font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Text("A").font(.caption2)
                        Slider(value: $model.crossoverSettings.balance, in: 0...1)
                        Text("B").font(.caption2)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Variation").font(.caption).foregroundStyle(.secondary)
                HStack {
                    Text("Faithful").font(.caption2)
                    Slider(value: $model.crossoverSettings.variation, in: 0...1)
                    Text("Wild").font(.caption2)
                }
            }

            if model.mode == .crossover {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Trait routing").font(.caption).foregroundStyle(.secondary)
                    ForEach(RemixTrait.allCases, id: \.self) { trait in
                        HStack {
                            Text(trait.rawValue.capitalized).font(.caption).frame(width: 70, alignment: .leading)
                            Picker("", selection: Binding(
                                get: { model.crossoverSettings.source(for: trait) },
                                set: { model.crossoverSettings.setSource($0, for: trait) }
                            )) {
                                Text("A").tag(RemixTraitSource.a)
                                Text("auto").tag(RemixTraitSource.auto)
                                Text("B").tag(RemixTraitSource.b)
                            }.pickerStyle(.segmented).labelsHidden()
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Directive pool").font(.caption).foregroundStyle(.secondary)
                ForEach(RemixDirectives.catalog, id: \.self) { vector in
                    Toggle(vector, isOn: Binding(
                        get: { model.crossoverSettings.enabledDirectives.contains(vector) },
                        set: { on in
                            if on { model.crossoverSettings.enabledDirectives.insert(vector) }
                            else { model.crossoverSettings.enabledDirectives.remove(vector) }
                        }
                    )).font(.caption2).toggleStyle(.checkbox)
                }
            }
        }
        .padding(16)
        .frame(width: 320)
    }
}
```

- [ ] **Step 2: Wire the gear button + summary chip into `RemixStudioView.controls`**

In `App/TrueISFEditor/Remix/RemixStudioView.swift`:

(a) Add a popover state var near the other `@State`s (around line 14-17):

```swift
    @State private var showCrossoverSettings = false
```

(b) In the `controls` computed property, find the `HStack` containing the Batch `Stepper` and Generate `Button`. Add the gear button INSIDE that HStack, after the Generate button:

```swift
                Button { showCrossoverSettings.toggle() } label: { Label("Crossover", systemImage: "gearshape") }
                    .popover(isPresented: $showCrossoverSettings, arrowEdge: .bottom) {
                        RemixCrossoverPopover(model: model)
                    }
```

(c) Immediately AFTER that HStack (still inside the `controls` VStack), add the summary chip line:

```swift
            Text(model.crossoverSettings.summary)
                .font(.caption2).foregroundStyle(.secondary)
```

- [ ] **Step 3: Build-verify**

Run the house command with `build`. Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Run the full test suite**

Run the house test command. Expected: `Executed 137 tests, with 3 tests skipped and 0 failures` (unchanged — the popover is view-only).

- [ ] **Step 5: Commit**

```bash
git add App/TrueISFEditor/Remix/RemixCrossoverPopover.swift App/TrueISFEditor/Remix/RemixStudioView.swift
git commit -m "feat(remix): crossover settings popover — balance/variation/routing/pool + summary chip

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 7: Verification + gates

**Files:** none new.

- [ ] **Step 1: Full clean verification**

```bash
cd App && xcodegen generate && xcodebuild -project TrueISFEditor.xcodeproj -scheme TrueISFEditor -derivedDataPath ./ddata-review -destination 'platform=macOS,arch=arm64' ARCHS=arm64 ONLY_ACTIVE_ARCH=YES test 2>&1 | grep -E 'error:|Executed [0-9]+ tests, with|\*\* TEST'
```

Expected: `Executed 137 tests, with 3 tests skipped and 0 failures` and `** TEST SUCCEEDED **`.

- [ ] **Step 2: Binary freshness check (string unique to this change)**

```bash
grep -ac "weight the blend roughly" App/ddata-review/Build/Products/Debug/TrueISFEditor.app/Contents/MacOS/TrueISFEditor.debug.dylib
```

Expected: `1` (the balance-line string is unique to this feature; grep the `.debug.dylib`, not the stub binary).

- [ ] **Step 3: Manual Mechanic review (native-Swift exception — read the diff inline, no subagent)**

Audit the changed files for: retain cycles in the popover bindings capturing `model`, `@Published`-didSet persistence not thrashing UserDefaults on slider drags (acceptable — drags coalesce; note if egregious), the `init` self-assign triggering `didSet` (harmless redundant write), and the segmented-picker tag types matching `RemixTraitSource`.

- [ ] **Step 4: CSO delta review (prompt path changed)**

The generation prompt now carries user-controlled settings text and shuffled parent order. Confirm: (a) parents are still labeled `(untrusted)` regardless of order; (b) `promptLines`/summary contain no user-supplied free text beyond the fixed knob vocabulary (balance %, fixed band strings, trait names) — the only free-text sink remains `steer`, unchanged; (c) no new tool/file/network capability. Quote the relevant lines; verdict SHIP / FIX-FIRST.

- [ ] **Step 5: On-device gate (by absolute binary path — never `open`)**

```bash
pkill -f "ddata-review.*TrueISFEditor" 2>/dev/null; sleep 1
App/ddata-review/Build/Products/Debug/TrueISFEditor.app/Contents/MacOS/TrueISFEditor &
```

Hand to the user: open Remix, set two parents, open ⚙ Crossover, slide balance toward B, pin a trait, disable a directive, Generate — confirm children visibly shift toward B and the summary chip + placeholder directives reflect the settings.

- [ ] **Step 6: Update action items + finish the branch**

Log the on-device gate to `~/.claude/c-suite/inbox/action-items.json` (workArea `trueisfeditor-remix`); after it + CSO pass, use `superpowers:finishing-a-development-branch` to merge `remix-crossover-controls` to master.
