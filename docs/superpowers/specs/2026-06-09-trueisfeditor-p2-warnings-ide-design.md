# P2 — Warnings/Errors IDE (Design Spec)

**Date:** 2026-06-09
**Status:** Approved (brainstorm complete; ready for implementation plan)
**Repo:** `/Users/arsonrivvers/Desktop/AV_Projects/ShaderToy-to-ISF-converter`
**Predecessor:** P1.5 native ISFMSLKit preview (merged to master `dfdf0d0`)

---

## 1. Problem & Goal

The diagnostics surface is read-only and split. `WarningsView` shows converter `ConversionWarning`s as
plain (non-selectable) `Text`, with the live compile error hacked in as a special top row. There's no way
to copy an error, jump from an error to its line, look up an unfamiliar ISF/GLSL symbol, or get help fixing
a shader.

**Goal:** turn it into a real diagnostics IDE with four capabilities, behind one unified model:
1. **Selectable/copyable** diagnostics.
2. **Click-to-jump-to-line** from a diagnostic into the editor.
3. **Inline symbol lookups** — hover/option-click a symbol in the editor for its signature + doc.
4. **Fix-suggestions** — rule-based (instant, offline) with a **manual, key-gated LLM fallback**; each
   suggestion is advisory and, where a rule is confident, offers **one-click Apply**.

### Non-goals (P2)
- No auto-LLM on the live-compile loop (cost). LLM is manual-trigger only.
- No full GLSL language server / semantic analysis. Lookups are a curated symbol DB; fixes are pattern rules.
- No searchable reference panel (inline hover was chosen); the symbol DB is structured so a panel could be
  added later without rework.

---

## 2. Architecture

Currently: `EditorViewModel` owns `preview` (`PreviewCoordinator`) and the editor (`CodeEditorController`),
and `EditorScreen` passes converter warnings + `preview.compileError`/`compileErrorLine` into `WarningsView`
separately. P2 introduces a unified diagnostics backbone.

```
Diagnostic (struct)            ← one shape for converter warnings AND compile errors
DiagnosticsModel : ObservableObject
    merges converter ConversionWarnings + live compile error -> [Diagnostic]
    -> DiagnosticsPanel (display)         (replaces WarningsView)
    -> [EditorDiagnostic] (gutter)        (replaces the ad-hoc pipe in EditorViewModel)
    -> FixRuleEngine (per-diagnostic suggestions)

FixRuleEngine (pure, in ShadertoyISFKit)  diagnostic -> [FixSuggestion]
AnthropicClient (app)                     manual "Explain with AI", key-gated
CodeEditorController (+ revealLine, applyTextEdit)
CodeMirror harness (+ revealLine, applyTextEdit, hoverTooltip over bundled symbols.json)
```

### Where things live
- `Diagnostic`, `FixSuggestion`, `TextEdit`, `FixRuleEngine` → **`ShadertoyISFKit`** package (pure logic,
  `swift test`-able alongside the existing converter).
- `DiagnosticsModel`, `DiagnosticsPanel`, `AnthropicClient`, editor-bridge additions → **app target**.
- `symbols.json` → **bundled editor resource** (loaded by the CodeMirror harness JS).

---

## 3. Data Model

```swift
// ShadertoyISFKit
public enum DiagnosticSeverity { case error, warning, info }
public enum DiagnosticSource { case converter, compiler }

public struct Diagnostic: Identifiable, Equatable {
    public let id: UUID
    public let line: Int?            // 1-based, nil if not line-locatable
    public let severity: DiagnosticSeverity
    public let message: String
    public let source: DiagnosticSource
    public let code: String?         // optional category key for rule matching (e.g. "use_of_texture2D")
}

public struct TextEdit: Equatable {
    public let fromLine: Int         // 1-based inclusive
    public let toLine: Int           // 1-based inclusive
    public let replacement: String
    public let expectedContains: String?  // safety: only apply if the target span still contains this
}

public struct FixSuggestion: Identifiable, Equatable {
    public let id: UUID
    public let title: String         // short actionable label ("Replace texture2D with IMG_PIXEL")
    public let explanation: String   // 1-3 sentences, plain English
    public let edit: TextEdit?       // present => one-click Apply available; nil => advisory only
    public let isAI: Bool            // false for rules, true for LLM-sourced
}
```

`ConversionWarning` (existing) maps to `Diagnostic(source: .converter)`. The live compile error maps to
`Diagnostic(source: .compiler, line: compileErrorLine, severity: .error)`.

---

## 4. FixRuleEngine (pure Swift, ShadertoyISFKit)

```swift
public enum FixRuleEngine {
    /// Returns rule-based suggestions for a diagnostic. `sourceLine` is the editor's text at
    /// diagnostic.line (1-based), used both to match and to build a precise TextEdit.
    public static func suggestions(for d: Diagnostic, sourceLine: String?) -> [FixSuggestion]
}
```

A rule is a matcher over `(message, code, sourceLine)` producing 0+ suggestions. Initial rule set, seeded
directly from the P1.5 corpus failure analysis (see `docs/.../2026-06-09-corpus-acceptance-result.md`):

| Pattern (in message / source) | Suggestion | Edit? |
|---|---|---|
| `texture2D(` in source line | Explain: ISF/Metal use `IMG_PIXEL`/`texture()`, not `texture2D`. | Yes — rewrite `texture2D(a,b)` → `IMG_PIXEL(a,b)` on that line |
| `'active' : Reserved word` (and other MSL reserved words) | Explain reserved-word collision; suggest rename. | Yes — rename the identifier on that line (suffix `_`) |
| `tanh` runtime/compile error (no polyfill) | Explain ES1 lacks `tanh`; offer polyfill insertion. | Yes — insert a `tanh` polyfill above `main` |
| `undeclared identifier` | Explain likely typo / missing declaration / wrong ISF builtin; link the hover DB. | No (advisory) |
| `no matching overloaded function` | Explain signature mismatch; show the expected signature from the symbol DB if known. | No (advisory) |

Rules are data-driven where possible (a list of `(regex, builder)` entries) so adding a rule is a one-liner.
**Every rule gets a unit test** with a real error string + (where applicable) a source line, asserting the
suggestion text and the resulting `TextEdit`.

---

## 5. DiagnosticsModel (app)

```swift
@MainActor
final class DiagnosticsModel: ObservableObject {
    @Published private(set) var diagnostics: [Diagnostic] = []

    /// Rebuild from the two sources. Called by EditorViewModel whenever either changes.
    func update(converterWarnings: [ConversionWarning], compileError: String?, compileErrorLine: Int?)

    /// Gutter projection (1-based lines with messages).
    var editorDiagnostics: [EditorDiagnostic] { ... }
}
```

- Ordering: errors before warnings before info; within a severity, compiler before converter; line-ascending.
- `EditorViewModel` owns a `DiagnosticsModel`, calls `update(...)` from the same place it currently pushes
  the gutter pipe (replacing the ad-hoc `preview.$compileError.combineLatest(...)` wiring).
- `EditorScreen` passes `vm.diagnostics` (the model) to `DiagnosticsPanel` and drives the gutter from
  `model.editorDiagnostics`.

---

## 6. DiagnosticsPanel (app, replaces WarningsView)

- Header: `Diagnostics (N)` with counts by severity.
- Each row:
  - severity icon + color (error red / warning yellow / info secondary),
  - **selectable** message (`.textSelection(.enabled)`), truncating long messages with full text on
    selection/expand,
  - line affordance ("line 42") that is a **button → `onJump(line)`**,
  - if `FixRuleEngine` (or AI) returned suggestions: an expandable area showing each suggestion's
    explanation, an **Apply** button when `edit != nil`, and (for compiler errors) an **Explain with AI**
    button when an Anthropic key is present.
- `onJump: (Int) -> Void` and `onApply: (TextEdit) -> Void` are passed in from `EditorScreen`, wired to the
  `CodeEditorController`.
- Empty state: "No diagnostics".

---

## 7. Editor bridge additions (CodeEditorController + CodeMirror harness)

New `CodeEditorController` methods (mirroring the existing `setText`/`setDiagnostics` ready-gating):
```swift
func revealLine(_ line: Int)                              // -> JS revealLine(line)
func applyTextEdit(fromLine: Int, toLine: Int, _ s: String)  // -> JS applyTextEdit(...)
```
CodeMirror harness (`vendor/codemirror/cm-entry.js` + `code-editor.html`):
- `revealLine(line)` — `EditorView.scrollIntoView` to the line start + set selection to that line.
- `applyTextEdit(fromLine, toLine, replacement)` — dispatch a transaction replacing those lines; the normal
  change handler fires → `onChange` → recompile. CodeMirror's history makes it undoable.
- `hoverTooltip` extension — on hover over an identifier, look it up in the bundled `symbols.json`; if found,
  render a tooltip with `signature` + `summary`. Pure JS, no Swift round-trip.

`applyTextEdit` safety: the controller checks the suggestion's `expectedContains` against the current line
text before applying; if it no longer matches (user edited since), it no-ops and surfaces a transient
"couldn't apply automatically — shader changed" note.

---

## 8. Symbol DB (bundled editor resource)

`symbols.json`: an array of `{name, kind, signature, summary}`:
- **ISF builtins**: `IMG_PIXEL`, `IMG_NORM_PIXEL`, `IMG_SIZE`, `IMG_THIS_PIXEL`, `IMG_THIS_NORM_PIXEL`,
  `RENDERSIZE`, `isf_FragNormCoord`, `TIME`, `TIMEDELTA`, `FRAMEINDEX`, `PASSINDEX`, `DATE`, `gl_FragCoord`.
- **Common GLSL functions**: `texture`, `smoothstep`, `mix`, `clamp`, `fract`, `mod`, `step`, `length`,
  `normalize`, `dot`, `cross`, `pow`, `atan`, `sin`/`cos`, `floor`/`ceil`, `abs`, `sign`, `min`/`max`.
- Curated, ~40-60 entries to start; structured so entries can be added without code changes.
- Validity is unit-tested (parses, required fields, no dupes, core entries present).

---

## 9. AnthropicClient (app, manual + key-gated)

```swift
final class AnthropicClient {
    init(apiKey: String)
    /// Manual "Explain with AI" for a compiler error. Returns one FixSuggestion (isAI: true).
    func explain(error: String, sourceSnippet: String) async throws -> FixSuggestion
}
```
- Key stored via `KeychainStore` (extend it with an Anthropic key slot; entered in `SettingsView`).
- Model: a cheap fast Claude model — confirm the exact current ID against the `claude-api` reference at
  implementation time (do not hardcode from memory); default to the cheapest capable tier.
- Prompt: the compile error + a small window of source around the error line + a one-line ISF-context note;
  ask for a short explanation and, if possible, a concrete fix. Parse into `FixSuggestion`
  (explanation always; `edit` only if the response clearly localizes a single-line replacement — otherwise
  advisory).
- **Manual only** (button per compiler error), **key-gated** (button hidden / routes to Settings if no key),
  bounded timeout, errors surfaced inline. **CFO cost review before this path is enabled by default.**

---

## 10. Testing

- **`FixRuleEngineTests`** (swift test, ShadertoyISFKit): one test per rule with a real corpus error string
  (+ source line) → assert suggestion title/explanation and the exact `TextEdit`. Plus a "no match → []" case.
- **`DiagnosticsModelTests`** (app): merging converter + compiler diagnostics, ordering, dedupe, the
  `editorDiagnostics` gutter projection.
- **`symbols.json` test**: parses, required fields present, no duplicate names, core ISF builtins present.
- **`AnthropicClientTests`**: inject a mock `URLProtocol`/transport; assert request shape + response parsing.
  Never hits the real API.
- **Playwright harness tests** (editor): `revealLine` moves selection/scrolls; `applyTextEdit` replaces the
  right lines and fires a change; `hoverTooltip` shows the expected entry for a known symbol. (Same pattern
  as the existing CodeMirror harness validation.)
- Build-clean + `swift test` (engine) + app model tests are the gate. Mechanic = manual inline (native Swift).
- **Live UX pass**: after build, the user's hands-on test (jump, apply, hover, AI) — native clicks the
  agent can't drive.

---

## 11. Files Touched (anticipated)

**New**
- `ShadertoyISFKit/Sources/.../Diagnostic.swift`, `FixSuggestion.swift`, `FixRuleEngine.swift`
- `ShadertoyISFKit/Tests/.../FixRuleEngineTests.swift`
- `App/TrueISFEditor/DiagnosticsModel.swift`
- `App/TrueISFEditor/Views/DiagnosticsPanel.swift` (replaces `WarningsView.swift`)
- `App/TrueISFEditor/AnthropicClient.swift`
- `App/TrueISFEditor/Resources/symbols.json` (+ harness loader)
- `App/TrueISFEditorTests/DiagnosticsModelTests.swift`, `AnthropicClientTests.swift`, symbols-validity test

**Modified**
- `App/TrueISFEditor/CodeEditorView.swift` (`revealLine`, `applyTextEdit`)
- `vendor/codemirror/cm-entry.js` + `code-editor.html` (revealLine, applyTextEdit, hoverTooltip)
- `App/TrueISFEditor/EditorViewModel.swift` (own `DiagnosticsModel`, replace the gutter pipe)
- `App/TrueISFEditor/Views/EditorScreen.swift` (use `DiagnosticsPanel`, wire jump/apply)
- `App/TrueISFEditor/KeychainStore.swift` + `SettingsView.swift` (Anthropic key slot)
- `App/project.yml` (new sources/resources)

---

## 12. Open Questions (carry into the plan)

1. **Reserved-word rename edit** — renaming an identifier safely needs to catch all uses on the line (and
   ideally the whole shader). For P2, scope the auto-rename to the single reported line; advise for
   multi-line. Confirm during implementation.
2. **AI `edit` extraction** — whether to attempt a structured one-line edit from the LLM or keep AI
   suggestions advisory-only in v1. Default: advisory-only for AI; rules own the Apply path.
3. **Anthropic model ID/pricing** — resolve against the `claude-api` reference at build time; surface the
   per-call cost estimate to the user in Settings.

---

## 13. Risk Register

| Risk | Mitigation |
|---|---|
| LLM auto-fires and burns cost | Manual trigger only; key-gated; CFO review before enabling by default (§9) |
| Apply corrupts the file after edits | `expectedContains` guard; no-op + note if the span moved (§7) |
| Symbol hover laggy | DB bundled JS-side; pure local lookup, no Swift round-trip (§8) |
| Rule engine overfits corpus | Rules are data-driven + unit-tested; advisory fallback for unmatched (§4) |
| Unified-model refactor breaks the gutter | `DiagnosticsModel.editorDiagnostics` replaces the existing pipe behind the same `EditorDiagnostic` shape; covered by tests (§5,§10) |
| Hardcoded/stale Claude model ID | Resolve via `claude-api` reference at implementation, never from memory (§9) |
