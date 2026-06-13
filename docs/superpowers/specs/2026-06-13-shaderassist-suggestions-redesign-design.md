# ShaderAssist Suggestions Redesign - Design

Date: 2026-06-13
Project: TrueISFEditor
Status: Design approved in-session; implementation not started

## Sources Read

- `~/.claude/c-suite/handoffs/2026-06-13-trueisfeditor-remix-crossover-merged-next-suggestions.md`
- `~/.claude/projects/-Users-arsonrivvers-Desktop-AV-Projects-ShaderToy-to-ISF-converter/memory/remix-next-features-queue.md`
- `App/TrueISFEditor/Views/EditorScreen.swift`
- `App/TrueISFEditor/Views/SuggestionsPanel.swift`
- `App/TrueISFEditor/Views/DiffReviewPanel.swift`
- `App/TrueISFEditor/ShaderAssist/ShaderAssistViewModel.swift`
- `App/TrueISFEditor/ShaderAssist/AssistProvider.swift`
- `App/TrueISFEditor/ShaderAssist/ClaudeCodeRunner.swift`
- `App/TrueISFEditor/ShaderAssist/CodexRunner.swift`
- `ShadertoyISFKit/Sources/ShadertoyISFKit/ShaderAssist/ShaderAssistPrompt.swift`
- `ShadertoyISFKit/Sources/ShadertoyISFKit/ShaderAssist/ShaderAssistTypes.swift`
- `ShadertoyISFKit/Sources/ShadertoyISFKit/ShaderAssist/ShaderAssistResponseParser.swift`
- `docs/superpowers/specs/2026-06-09-trueisfeditor-p3-ai-copilot-design.md`
- `docs/superpowers/specs/2026-06-11-trueisfeditor-layout-shaderassist-v2-design.md`

## Goal

Redesign the main editor's ShaderAssist Suggestions flow from a flat advisory list into a goal-driven,
apply-directly workflow:

1. Ask what the user wants to improve before generating suggestions.
2. Offer 4-5 goals tailored to the current shader.
3. Generate suggestions scoped to the selected goal.
4. Let the user multi-select favorites.
5. Use one Claude/Codex call to implement all selected suggestions as one coordinated source rewrite.
6. Show a user-gated diff before changing the in-memory editor source.

This is for the main editor / ShaderAssist section only. Remix Studio is out of scope.

## Product Shape

Use the approved hybrid of a focused sheet and compact in-editor controls:

- First Suggestions click opens a focused sheet.
- The sheet asks "What do you want to improve?" and generates shader-specific goal cards.
- The user picks a goal or enters a custom goal.
- The sheet closes and the active goal appears as a compact control in the ShaderAssist section.
- Suggestions render in the existing ShaderAssist panel, now as selectable cards.
- Apply happens from the panel, not inside the sheet.

The first payoff is not a count or confirmation. The payoff is a concrete shader diff that can be applied to the
live editor and immediately recompiled.

## User Flow

1. User clicks `Suggestions`.
2. If there is no active goal for the current source, show `SuggestionGoalSheet`.
3. Sheet runs `suggestionGoals` against the current source and diagnostics.
4. Sheet displays 4-5 tailored goals plus a custom goal field.
5. User selects or enters a goal.
6. ShaderAssist stores the active goal and source fingerprint.
7. The panel runs `suggestions(goal:)`.
8. The panel displays scoped suggestions with multi-select checkboxes.
9. User selects one or more suggestions.
10. User clicks `Apply Selected`.
11. ShaderAssist runs `applySuggestions(goal:selectedIdeas:)` once for the whole selected set.
12. The app parses a full replacement source and shows a diff review.
13. User clicks `Apply to Editor`.
14. The app sets the editor text in memory through a dedicated editor-view-model method, recompiles, and marks
    the file dirty.

## Architecture

Keep the existing ShaderAssist stack:

```text
EditorScreen
  -> ShaderAssistViewModel
    -> AssistProvider
      -> ClaudeCodeRunner / CodexRunner
    -> ShaderAssistPrompt
    -> ShaderAssistResponseParser
  -> SuggestionsPanel / new goal and apply-review views
  -> EditorViewModel editor/apply APIs
```

The existing runners remain the only path to Claude/Codex. The redesign adds task shapes, result types,
workflow state, and UI. It does not add a second LLM subsystem.

## Types

Extend the shared ShaderAssist model in `ShadertoyISFKit`.

```swift
public enum ShaderAssistTask: Sendable, Equatable {
    case diagnoseAndFix
    case suggestionGoals
    case suggestions(goal: String)
    case applySuggestions(goal: String, selectedIdeas: [AIIdea])
}

public struct AISuggestionGoal: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let detail: String
    public let kind: String
    public let whyThisShader: String
}

public struct AISuggestionGoalsResult: Codable, Equatable, Sendable {
    public let goals: [AISuggestionGoal]
}

public struct AIIdea: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let detail: String
    public let kind: String
    public let lines: [Int]?
    public let impact: String?
}

public struct AISuggestionsResult: Codable, Equatable, Sendable {
    public let goal: String
    public let ideas: [AIIdea]
}

public struct AIApplyResult: Codable, Equatable, Sendable {
    public let explanation: String
    public let replacementSource: String
    public let changedLines: [Int]
}
```

Notes:

- Give `AIIdea` a real `id` from the model instead of deriving identity from `title`. Selection needs stable IDs.
- Keep `kind` string-based for compatibility with current suggestion chips.
- `AIApplyResult.replacementSource` is the full source, not line patches. Full-source replacement is less brittle
  when selected suggestions interact.

## View Model State

Extend `ShaderAssistViewModel.State` rather than creating a parallel model:

```swift
case idle
case running(ShaderAssistTask)
case fix(AIFixResult)
case suggestionGoals(AISuggestionGoalsResult)
case suggestions(AISuggestionsResult)
case applyPreview(AIApplyResult)
case rawAnswer(String)
case error(String)
```

Add app-side state:

- `activeSuggestionGoal: String?`
- `suggestionSourceFingerprint: String?`
- `applyPreviewSourceFingerprint: String?`
- `selectedIdeaIDs: Set<String>`
- `lastSuggestions: AISuggestionsResult?`

The fingerprint can be a simple hash of the current source captured when suggestions are generated. Before
applying selected suggestions, compare the current source hash to the stored hash. If the user edited the source
after suggestions were generated, block apply and ask them to rerun suggestions.

When an apply preview is produced, capture the current source fingerprint again. `Apply to Editor` must compare
the editor's current fingerprint to `applyPreviewSourceFingerprint` before replacing source. If the user edits
while the apply call or diff review is open, block the apply and ask them to rerun.

## Prompts

### Goal Prompt

`suggestionGoals` asks for 4-5 goals tailored to the current shader. The goals should include practical
performance controls and creative evolution paths when applicable.

Schema:

```json
{
  "goals": [
    {
      "id": "expose-controls",
      "title": "Expose performance controls",
      "detail": "Turn hardcoded rates, thresholds, and palette constants into ISF inputs.",
      "kind": "make-interactive",
      "whyThisShader": "This shader has repeated numeric thresholds in the cloud layer."
    }
  ]
}
```

### Scoped Suggestions Prompt

`suggestions(goal:)` asks for actionable ideas scoped to the selected goal. It must not drift into unrelated
generic shader advice.

Schema:

```json
{
  "goal": "Expose performance controls",
  "ideas": [
    {
      "id": "cloud-density-threshold",
      "title": "Cloud density and threshold sliders",
      "detail": "Expose the density and cutoff constants as float INPUTS for live control.",
      "kind": "make-interactive",
      "lines": [23, 48],
      "impact": "Makes the cloud layer playable without editing source."
    }
  ]
}
```

### Apply Prompt

`applySuggestions(goal:selectedIdeas:)` sends the original source, active goal, and selected ideas in one call.
It asks for one complete, valid ISF source file and a short explanation.

Schema:

```json
{
  "explanation": "Added float inputs for cloud density and speed, then wired them into the existing constants.",
  "replacementSource": "/*{ ... }*/\n\nvoid main() { ... }",
  "changedLines": [4, 5, 23, 48]
}
```

The prompt must require:

- Preserve valid ISF JSON header syntax.
- Preserve the shader's visual identity unless the chosen goal explicitly asks for transformation.
- Do not remove existing inputs, passes, or image inputs unless the selected suggestions require it.
- Return JSON only, no markdown.

## UI Components

### `SuggestionGoalSheet`

Responsibilities:

- Run/observe `suggestionGoals`.
- Display goal cards.
- Provide custom goal field.
- Let the user confirm one goal.
- Show empty/error states without closing the sheet.

The sheet should not show final suggestions or apply controls.

### `SuggestionsPanel`

Responsibilities:

- Display active goal control.
- Render suggestion cards with checkbox, kind chip, impact text, and line jump.
- Maintain selected count.
- Disable `Apply Selected` until at least one card is selected.
- Provide `Rerun`, `Change Goal`, and `Start Over` affordances.

### `ApplyPreviewPanel`

Responsibilities:

- Show `AIApplyResult.explanation`.
- Show a source diff between current source and `replacementSource`.
- Offer `Apply to Editor` and `Discard`.
- Never apply automatically.

The diff can start simple: a monospaced before/after or unified text diff. It must be readable enough to review
what will enter the editor.

### `EditorViewModel` Integration

Add a narrow method for AI-approved full-source replacement, for example:

```swift
func replaceSourceFromAssist(_ source: String, status: String)
```

This method should:

- Set `file.source`.
- Push the full source into `CodeEditorController` via `editor.setText`.
- Sync the header authoring model from the new text.
- Recompile immediately or through the existing debounce path.
- Set a clear status message.

Do not route a full-source replacement through the existing line-level `apply(_ edit: TextEdit)` helper; that
helper is for guarded line patches from Diagnose & Fix.

## Error And Edge States

- **No goals returned:** keep the sheet open, show custom goal field, and offer retry.
- **No suggestions returned:** keep the active goal; offer rerun or change goal.
- **Source changed before apply:** block `Apply Selected` and show "Shader changed since these suggestions were generated. Rerun suggestions."
- **Source changed while apply preview is open:** block `Apply to Editor` and show "Shader changed since this diff was generated. Rerun apply."
- **Apply parse failure:** show raw answer; do not change editor source.
- **Replacement source has no ISF header:** reject the apply result and show an error; do not change editor source.
- **Replacement compiles with diagnostics:** allow the user-gated editor apply. Shader work often needs iterative
  broken-then-fixed passes; after applying, the existing compiler diagnostics should surface immediately.
- **User cancels running task:** preserve the last stable goal/suggestions if available.

## Security

Threat model: untrusted shader source -> LLM -> editor write.

Controls:

- Keep the rewrite in memory until the user approves the diff.
- Never let the CLI write files or run tools.
- Reuse the existing `AssistProvider` runners.
- Preserve Claude hardened flags:
  `--tools "" --disallowedTools LSP --allowedTools "" --strict-mcp-config --disable-slash-commands`.
- Preserve Codex read-only sandbox flags:
  `exec --json --color never -s read-only --skip-git-repo-check --ignore-user-config`.
- Keep the injection guard that marks shader source as untrusted data.
- Validate model output before the editor sink:
  - JSON parses.
  - `replacementSource` is non-empty.
  - `replacementSource` contains an ISF header starting with `/*{`.
  - User confirms diff.

CSO trifecta review is required before merge because the apply path is model output reaching an editor sink.

## Cost

No new API keys, hosted services, crons, or per-call metered API spend. The feature uses the user's existing
Claude/Codex CLI subscriptions. The practical cost is subscription usage/latency, not marginal dollars.

## Testing

Pure/unit tests:

- Decode `AISuggestionGoalsResult`, expanded `AISuggestionsResult`, and `AIApplyResult`.
- Parse goal, suggestion, and apply result envelopes/fenced JSON/raw JSON.
- Prompt tests:
  - goal prompt includes goal schema and asks for 4-5 tailored goals.
  - scoped suggestions prompt includes selected goal and ideas schema.
  - apply prompt includes selected ideas and full-source replacement schema.
- View-model tests with fake provider:
  - goal run transitions to `.suggestionGoals`.
  - selecting a goal runs scoped suggestions.
  - selection state toggles by idea ID.
  - apply blocks when source fingerprint changes.
  - apply parse failure leaves editor source untouched.
  - valid apply produces `.applyPreview`.

App/native verification:

- `xcodegen generate`
- Full app test suite.
- Build with explicit `-derivedDataPath ./ddata-review ARCHS=arm64 ONLY_ACTIVE_ARCH=YES`.
- Staged binary freshness grep using a unique >15-character string from the implementation.
- On-device smoke:
  - Suggestions first click shows goal sheet.
  - goal cards are tailored to current shader.
  - selected goal collapses to panel control.
  - suggestions are scoped to goal.
  - multi-select enables Apply Selected.
  - one apply call yields a diff.
  - Apply to Editor updates source and recompiles.

Manual reviews before merge:

- Native Swift Mechanic review.
- Client Success UX review of the running flow.
- CSO trifecta/security review of the apply path.

## Build Order

1. Shared types and parser support.
2. Prompt support for goals, scoped suggestions, and apply.
3. View-model workflow state with fake-provider tests.
4. Goal sheet UI and active-goal panel state.
5. Selectable suggestions panel.
6. Apply selected -> full-source rewrite -> diff preview.
7. Editor apply integration and verification gates.

## Non-Goals

- No Remix Studio changes.
- No direct file save. Applying changes marks the editor dirty; existing save behavior remains in charge.
- No autonomous rewrite without a diff.
- No new external API or hosted service.
- No separate agent/CLI subsystem.
