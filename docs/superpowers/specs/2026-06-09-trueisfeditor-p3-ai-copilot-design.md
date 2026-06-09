# P3 — In-App AI Co-Pilot (headless Claude Code) Design Spec

**Date:** 2026-06-09
**Status:** Approved (brainstorm complete; ready for implementation plan)
**Repo:** `/Users/arsonrivvers/Desktop/AV_Projects/ShaderToy-to-ISF-converter`
**Predecessors:** P1.5 native ISFMSLKit preview + P2 warnings/errors IDE (both merged to master)

---

## 1. Problem & Goal

The editor can detect and rule-fix common shader errors (P2), but a working VJ wants a smarter helper:
"diagnose and fix this shader," and "suggest how this could evolve." The user wants this **inside the app**
(buttons), powered by **their Claude subscription, not pay-per-call API**.

**Verified constraint (see memory `claude-subscription-auth-for-third-party-app`):** a third-party app cannot
bill a Claude subscription via the Messages API / a raw OAuth token (blocked + ToS-barred). The only
subscription-backed path that yields **in-app buttons** is invoking **headless Claude Code** (`claude -p`),
which uses the user's logged-in Claude Code auth. Confirmed locally (CLI v2.1.170): `-p`/`--print`,
`--output-format json`, `--append-system-prompt`, `--model`, and skills resolve in print mode.

**Goal:** in-app **Diagnose & Fix** and **Suggestions** buttons that run `claude -p` on the user's
subscription, load the `shader-dev` + `isf-shader-development` skills, and return structured results. Fixes
land via a **per-edit diff-review** (Apply/Skip), reusing P2's guarded `applyTextEdit`.

### Non-goals (P3)
- No MCP server (terminal-driven; rejected in favor of in-app one-shot `claude -p`).
- No Anthropic API key / pay-per-call path (the reverted P2 Settings field stays gone).
- No agentic multi-step Claude loop or tool-use in v1 — a single `claude -p` call returning JSON.
- No auto-apply — every edit is reviewed and applied individually.

---

## 2. Architecture

```
ShaderAssistViewModel (app)  ── builds task ──▶ ShaderAssistPrompt (ShadertoyISFKit, pure)
        │                                          │ system rules + numbered source + diagnostics
        ▼                                          ▼
ClaudeCodeRunner (app) ── Process: claude -p --output-format json --model … --append-system-prompt … <prompt>
        │ stdout (JSON envelope)
        ▼
ShaderAssistResponseParser (ShadertoyISFKit, pure, TESTABLE)
        │  unwrap claude envelope {result:"…"} → extract inner JSON → AIFixResult | AISuggestionsResult
        ▼
   ┌─ AIFixResult ─▶ DiffReviewPanel (per-edit before→after + rationale + Apply/Skip)
   │                       Apply ─▶ EditorViewModel.apply(TextEdit)  [P2 guarded path] ─▶ recompile
   └─ AISuggestionsResult ─▶ SuggestionsPanel (advisory idea cards)
```

### Where things live
- **Pure + testable → `ShadertoyISFKit`:** `ShaderAssistPrompt` (prompt construction), the result types
  (`AIFixResult`, `AIEdit`, `AISuggestionsResult`, `AIIdea`), and `ShaderAssistResponseParser`.
- **App target:** `ClaudeCodeRunner` (subprocess), `ShaderAssistViewModel`, `DiffReviewPanel`,
  `SuggestionsPanel`, Settings field for the binary path, the AI buttons.

---

## 3. ClaudeCodeRunner (app)

```swift
struct ClaudeRunResult { let rawStdout: String }   // the claude -p JSON envelope text

enum ClaudeRunError: Error { case binaryNotFound, notAuthenticated, timedOut, processFailed(String) }

@MainActor
final class ClaudeCodeRunner {
    /// Resolve the `claude` binary: (1) Settings override, (2) ~/.local/bin/claude,
    /// (3) /opt/homebrew/bin/claude, (4) /usr/local/bin/claude, (5) `/bin/zsh -lc 'command -v claude'`.
    func locateBinary() -> URL?

    /// Runs `claude -p --output-format json --model <model> --append-system-prompt <system> <prompt>`
    /// as a Process; async, cancellable, with a timeout. Returns raw stdout (the JSON envelope).
    func run(prompt: String, system: String, model: String,
             timeout: TimeInterval = 120) async throws -> ClaudeRunResult
}
```
- **GUI PATH gotcha:** a Finder-launched app doesn't inherit the shell `PATH`; binary resolution must not
  rely on `PATH` — use the explicit candidate list + a login-shell `command -v` fallback. Cache the result.
- **Cancellation:** Swift `Task` cancellation → `Process.terminate()`.
- **Auth detection:** if claude exits non-zero with an auth/login error in stderr, surface `.notAuthenticated`
  with guidance ("run `claude` once in Terminal to sign in"). Do not try to log in from the app.
- **Subprocess is permitted:** app is unsandboxed (P1) and spawning a child process isn't blocked by the
  ad-hoc/hardened-runtime config (P1.5).
- For testability, the actual `Process` launch goes behind a small `ProcessRunning` protocol so
  `ClaudeCodeRunner` can be unit-tested with a fake that returns canned stdout/exit without the real CLI.

---

## 4. Prompt + structured contract (ShadertoyISFKit, pure)

```swift
public enum ShaderAssistTask { case diagnoseAndFix, suggestions }

public enum ShaderAssistPrompt {
    /// System rules passed via --append-system-prompt.
    public static func system(for task: ShaderAssistTask) -> String
    /// Task prompt: numbered source + current diagnostics (+ task framing).
    public static func user(task: ShaderAssistTask, source: String, diagnostics: [Diagnostic]) -> String
}
```

**System rules (both tasks):** "You are an ISF/GLSL shader co-pilot inside TrueISFEditor. The shader targets
ISFMSLKit / VDMX6 (Metal, GLSL ES 3.0 via SPIR-V). Use the `isf-shader-development` and `shader-dev` skills.
Line numbers are 1-based as shown. Respond with **only** a single JSON object matching the schema below — no
prose, no markdown fences." Then the task-specific schema.

**Diagnose & Fix schema** (`AIFixResult`):
```json
{ "explanation": "string — what's wrong, in 1-3 sentences",
  "edits": [ { "fromLine": 11, "toLine": 11,
               "replacement": "    vec4 c = IMG_PIXEL(inputImage, uv);",
               "rationale": "texture2D isn't available; use the ISF sampler" } ] }
```

**Suggestions schema** (`AISuggestionsResult`):
```json
{ "ideas": [ { "title": "Expose `0.5` as a 'speed' INPUT",
               "detail": "Line 23 hardcodes the animation rate; an ISF float INPUT makes it performable.",
               "kind": "make-interactive",         // make-interactive | design | technique | perf
               "lines": [23] } ] }
```

**Types** (`ShadertoyISFKit`): `AIEdit {fromLine,toLine,replacement,rationale}` (maps to P2 `TextEdit` with
`expectedContains` derived from the current line text at apply time); `AIIdea {title,detail,kind,lines?}`.

---

## 5. ShaderAssistResponseParser (ShadertoyISFKit, pure — the reliability surface)

```swift
public enum ShaderAssistResponseParser {
    public static func fixResult(fromClaudeStdout: String) throws -> AIFixResult
    public static func suggestions(fromClaudeStdout: String) throws -> AISuggestionsResult
}
```
- Two-stage: (1) parse the `claude -p --output-format json` **envelope** and read its `result` string field;
  (2) extract our inner JSON from that string — tolerant of a bare object, a ```json fenced block, or an
  object embedded in prose (scan for the outermost balanced `{…}`). Decode with `JSONDecoder`.
- On failure → throw `ShaderAssistParseError.unparseable(raw:)` carrying the raw text so the UI can show Claude's
  answer verbatim instead of losing it.

---

## 6. UI

- **AI controls** in the editor (a small "AI" group near the diagnostics panel): **Diagnose & Fix** and
  **Suggestions** buttons. While running: a progress indicator + **Cancel**; buttons disabled.
- **`DiffReviewPanel`** (Diagnose & Fix result): header = `explanation` (selectable). Then one card per
  `AIEdit`: the line range, a **before→after** view (current lines `fromLine…toLine` vs `replacement`),
  the `rationale`, and **Apply** / **Skip**. Apply → `EditorViewModel.apply(TextEdit)` (P2 guard; if the line
  no longer matches, the existing "couldn't apply — shader changed" note fires) → live recompile. Applied/
  skipped cards mark their state.
- **`SuggestionsPanel`**: advisory idea cards — `title`, `detail` (selectable), a `kind` tag chip. No apply in
  v1 (future: a "make this an INPUT" action could reuse the converter).
- **Failure states:** binary not found → message + the Settings path field; not authenticated → sign-in
  guidance; unparseable → raw-answer text view.
- **Settings:** an optional **"Claude Code binary path"** field (seeds binary resolution).

---

## 7. Error handling / edges
- Binary not found / not authenticated / timeout / process failure → typed `ClaudeRunError`, each mapped to a
  clear in-UI message; never crash, never hang (timeout + cancel).
- Unparseable JSON → show raw answer; no auto-apply.
- Empty `edits` (Claude found nothing to fix) → "No fixes suggested" + the explanation.
- Stale edit at apply → P2 `expectedContains` guard no-ops with a note.
- Re-entrancy: only one run at a time; starting a new run cancels/ignores the prior.

---

## 8. Testing
- **`ShaderAssistResponseParserTests`** (swift test): bare JSON, fenced JSON, JSON-in-prose, the real
  `claude -p --output-format json` envelope shape, and malformed → throws `unparseable`. Primary coverage.
- **`ShaderAssistPromptTests`**: numbered source + diagnostics present; schema text present; both tasks.
- **`ClaudeCodeRunnerTests`**: inject a fake `ProcessRunning` → assert exact argv
  (`-p`, `--output-format json`, `--model`, `--append-system-prompt`, prompt) and that a non-zero/auth exit
  maps to `.notAuthenticated`; binary-resolution order tested with injected candidate existence.
- **`AIEdit → TextEdit` mapping**: derives `expectedContains` from the current source line.
- **On-device (user's hands):** Diagnose & Fix on a broken `texture2D` shader → review diffs → Apply →
  recompiles clean; Suggestions on a working shader → idea cards. (The first real end-to-end is a human click;
  the agent can't drive native clicks or invoke the live subscription in tests.)
- Build-clean + `swift test` (engine) + app model tests are the gate; Mechanic = manual inline (native Swift).

---

## 9. Files Touched (anticipated)

**New (ShadertoyISFKit — pure, testable)**
- `Sources/.../ShaderAssist/ShaderAssistTypes.swift` (AIFixResult/AIEdit/AISuggestionsResult/AIIdea/ShaderAssistTask/errors)
- `Sources/.../ShaderAssist/ShaderAssistPrompt.swift`
- `Sources/.../ShaderAssist/ShaderAssistResponseParser.swift`
- `Tests/.../ShaderAssistResponseParserTests.swift`, `ShaderAssistPromptTests.swift`

**New (app)**
- `App/TrueISFEditor/ShaderAssist/ClaudeCodeRunner.swift` (+ `ProcessRunning` protocol)
- `App/TrueISFEditor/ShaderAssist/ShaderAssistViewModel.swift`
- `App/TrueISFEditor/Views/DiffReviewPanel.swift`, `Views/SuggestionsPanel.swift`
- `App/TrueISFEditorTests/ClaudeCodeRunnerTests.swift`

**Modified**
- `App/TrueISFEditor/Views/EditorScreen.swift` (AI buttons + panels)
- `App/TrueISFEditor/EditorViewModel.swift` (expose what the co-pilot needs; reuse `apply(TextEdit)`)
- `App/TrueISFEditor/SettingsView.swift` + `AppModel.swift` (Claude Code binary path)
- `App/project.yml` (new sources/tests)

---

## 10. Build sequence
1. Engine: types + `ShaderAssistPrompt` + `ShaderAssistResponseParser` (TDD).
2. App: `ClaudeCodeRunner` (TDD with fake process) + binary resolution + Settings path field.
3. App: `ShaderAssistViewModel` + **Diagnose & Fix** button + `DiffReviewPanel` (proves the pipeline end-to-end).
4. App: **Suggestions** button + `SuggestionsPanel` (reuses the runner).
5. Final: on-device smoke (user), manual Mechanic review.

## 11. Open Questions (carry into the plan)
1. **Model flag vs subscription default:** `--model claude-sonnet-4-6` selects Sonnet, but the subscription
   may pin/override; confirm at implementation that the flag is honored and bills against the subscription.
2. **Suggestions "make-interactive" action:** advisory-only in v1; a one-click "convert to INPUT" is a
   future enhancement (would reuse the existing ISF converter).
3. **Skill cueing:** rely on auto-trigger or explicitly name both skills in the system prompt — default to
   explicitly naming them (belt-and-suspenders); confirm they load in `-p`.

## 12. Risk Register
| Risk | Mitigation |
|---|---|
| GUI app can't find `claude` (no PATH) | Explicit candidate paths + login-shell `command -v` + Settings override (§3) |
| Claude returns non-JSON / prose | Tolerant two-stage parser; raw-answer fallback; strict "JSON only" system rule (§5,§6) |
| Per-call latency feels slow | Async + progress + Cancel + 120s timeout (§3,§6) |
| Bad auto-edit corrupts shader | Per-edit review + P2 `expectedContains` guard (§6,§7) |
| Subscription usage burned unknowingly | One-line in-UI "uses your Claude subscription" note; manual-trigger only (§7) |
| `--model` not honored / wrong billing | Confirm at build time (Open Q §11.1) |
