# TrueISFEditor — Layout/Viewport Fixes + ShaderAssist v2 (Design)

**Date:** 2026-06-11
**Branch:** `layout-shaderassist-v2`
**Status:** Design — pending user review

## Summary

A combined spec covering seven user-requested changes in two independent groups:

- **Group A — Preview & Layout** (mostly fixes; build first): collapsible code editor, responsive
  render toolbar, aspect-correct "Fit" (no distortion), and fixing the black pop-out output window.
- **Group B — ShaderAssist v2** (feature): provider abstraction (Claude **and** OpenAI-Codex, both
  on existing CLI subscriptions), Settings for provider/model/login, a live embedded terminal of the
  diagnosis stream, and loading the ISF authoring skills into the assist session.

Both groups ship on one branch, sequenced **A then B**. Incremental cost ≈ **$0** (both providers use
existing subscriptions via their CLIs; no API keys, no crons, no hosted services).

## Goals

1. The code editor column can be collapsed (like the library sidebar already can).
2. The render toolbar never hides controls when the window/column is narrowed.
3. "Fit" preserves the render aspect ratio and letterboxes — stretching the canvas never distorts.
4. Popping out the output renders the shader correctly (camera/source-fed filters included), not black.
5. ShaderAssist can use either Claude (subscription via `claude` CLI) or OpenAI (subscription via
   `codex` CLI), with a model picker and visible login status.
6. A live terminal shows the raw model/CLI activity stream during a diagnosis.
7. The assist session is primed with ISF expertise (the `isf-shader-development` + `shader-dev` skills).

## Non-Goals

- API-key (pay-per-call) providers. Out of scope — both providers are subscription-CLI only. (Keychain
  plumbing stays unused for assist; revisit only if an API path is ever added.)
- The INPUT authoring GUI (sub-project B from the prior brainstorm) — separate, deferred.
- Multi-pass/HDR tonemapping changes to the display pass beyond aspect-fit.

---

## Group A — Preview & Layout

### A1. Collapsible code editor

**Current:** `EditorScreen` detail is an `HSplitView { centerColumn ; previewColumn }`. The library
sidebar collapses (it's the `NavigationSplitView` primary column); the center editor column does not.

**Design:**
- Add `@AppStorage("editorCollapsed") var editorCollapsed = false`.
- In the `HSplitView`, render the center column conditionally: `if !editorCollapsed { centerColumn }`.
  When collapsed, only library + preview remain.
- Toggle affordances: (a) a button in the preview header bar (icon
  `sidebar.squares.left` / `chevron`) with a tooltip; (b) a `View` menu command "Toggle Code Editor"
  with shortcut **⌘⌥E** (added in `TrueISFEditorApp.commands`).
- Preview column keeps its `minWidth: 320`; with the editor hidden the window can show a large preview.

**Testable:** view-model/`@AppStorage` toggle logic is trivial; verify on-device the column shows/hides
and the shortcut works.

### A2. Responsive render toolbar (wrap to two rows)

**Current:** `renderControlsBar` is a single non-wrapping `HStack` ending in a fixed `width: 160`
Renderer `Picker`. Narrowing the preview column truncates the "Renderer" label and clips the picker.

**Design:**
- Replace the single `HStack` with `ViewThatFits(in: .horizontal)` containing two arrangements:
  - **Wide (preferred):** the existing single row.
  - **Narrow (fallback):** a `VStack` of two rows — row 1 `Fit / W×H / ÷2 / ×2`, row 2
    `Source ▾ / Renderer segmented`.
- Remove the hard `width: 160` on the Renderer picker; let it size to content (segmented Metal|WebKit).
- Nothing is ever hidden; the bar grows one row taller when space is tight.

**Testable:** primarily visual/on-device (layout). Add a snapshot-free sanity check that both
arrangements compile and contain the same controls.

### A3. Aspect-correct "Fit" (no distortion)

**Current:** `MetalPreviewController.draw` renders the scene at `targetSize()` then blits via
`tisf_blit_v`/`tisf_blit_f` with uv 0–1 across the **whole** drawable — any aspect mismatch stretches.

**Design — the render always uses the W×H aspect; the texture is letterboxed into the view:**
- `targetAspect = renderWidth / renderHeight` (the W×H fields; default 640×480 → 4:3). Aspect is
  **always** derived from W×H — that is what "Fit" preserves.
- `targetSize()` changes:
  - **Fit ON:** inscribe `targetAspect` into the current drawable size (largest W×H-aspect rectangle
    that fits) → that is the render size. Crisp (scales with the window) and aspect-locked.
  - **Fit OFF:** render at exactly `(renderWidth, renderHeight)` — fixed resolution.
- Blit letterbox: pass a `float2 fitScale` to `tisf_blit_v` computed each frame from the rendered
  texture size and the drawable size:
  - `texAR = texW/texH`, `viewAR = drawW/drawH`.
  - if `viewAR > texAR` → pillarbox: `fitScale = (texAR/viewAR, 1)`; else letterbox:
    `fitScale = (1, viewAR/texAR)`.
  - `o.pos.xy *= fitScale` (NDC), uv unchanged. Clear-to-black already runs before the blit → bars.
- Net effect: stretching the window adds black bars on the non-matching axis; content is **never**
  distorted, in either Fit state, inline preview and pop-out alike.
- The fit math lives in a pure function `BlitFit.scale(textureSize:drawableSize:) -> (Float,Float)` and
  the inscribe math in `BlitFit.inscribe(aspect:in:) -> MTLSize`, both **unit-tested** independent of
  Metal.

**Testable:** `BlitFit.scale` unit tests (wide-into-tall, tall-into-wide, equal, 1:1). On-device: stretch
the window, confirm bars not distortion.

### A4. Fix black pop-out output window

**Current:** `OutputWindowManager` owns a **separate** `PreviewCoordinator` →
`MetalPreviewController` → `SourceRouter`. On compile, `SourceRouter.updateInputs` defaults each image
input to `NoneSource` (black). The pop-out never receives the inline preview's source selections, so a
filter (e.g. Chaoser needs camera) renders black. Additionally, a second `CameraSource` would open a
second `AVCaptureSession` on the same device.

**Design (two parts):**

1. **Mirror source selections to the pop-out.** Give `OutputWindowManager.show(source:)` and an
   `onChange` sync the inline router's `selections` into the output coordinator's router:
   for each `(name, selection)` call `outputRouter.setSelection(sel, for: name)`. Add a
   `syncSelections(from:)` helper on the manager, called on `show` and whenever the inline router's
   `selections` publish changes (Combine subscription or `.onChange` in `EditorScreen`).

2. **Single shared camera.** Extract the camera into a process-wide shared source so both routers'
   `.camera` selection reads the **same** `AVCaptureSession`/texture:
   - Introduce `SharedCamera` (a singleton wrapper, or inject one `CameraSource` instance into both
     routers via `SourceRouter`'s init). `SourceRouter.sharedCamera` becomes an injected dependency
     defaulting to the shared instance.
   - Avoids two capture sessions and device contention; the pop-out shows the same live camera.

**Testable:** `syncSelections(from:)` copies the selection map (unit test with a fake router).
On-device: pop out a camera filter → shows camera, not black; closing/reopening stays correct.

---

## Group B — ShaderAssist v2

### B1. Provider abstraction (streaming)

**Current:** `ShaderAssistViewModel` calls `ClaudeCodeRunner.run(...)` which uses
`claude -p --output-format json` (single blob) and hardcodes `model: "claude-sonnet-4-6"`.

**Design:**
- New protocol:
  ```swift
  protocol AssistProvider: Sendable {
      /// Streams raw activity events; returns the final assistant message text.
      func run(prompt: String, system: String, model: String?,
               timeout: TimeInterval,
               onEvent: @escaping @Sendable (String) -> Void) async throws -> String
  }
  ```
- Two backends, both behind the existing `ProcessRunning` seam (so unit tests inject a fake):
  - **`ClaudeCodeRunner`** (refactor): `claude -p --output-format stream-json --model <m>
    --append-system-prompt <preamble> <prompt>`. Parse JSONL lines → forward each as an event;
    capture the final `result` message as the return.
  - **`CodexRunner`** (new): `codex exec -m <model?> --json -s read-only --skip-git-repo-check
    -o <lastMsgFile> <prompt>` (model omitted when the user keeps the Codex default). Parse `--json`
    JSONL events → forward; read `<lastMsgFile>` for the final message.
- Provider/model chosen from settings; default provider Claude (Sonnet), default Codex model = Codex's
  own default (no `-m`).
- Error mapping reuses `ClaudeRunError` cases, generalized names where needed (binaryNotFound /
  notAuthenticated / timedOut / processFailed) for both CLIs.

### B2. Settings — provider, model, login status

**Current:** `SettingsView` has a Shadertoy API key + a Claude binary path field. `AppModel` stores
`apiKey` (Keychain) + `claudeBinaryPath` (UserDefaults).

**Design — add a "ShaderAssist" section to `SettingsView`:**
- **Provider picker:** Claude (subscription) · OpenAI (Codex subscription).
- **Model picker (per provider):**
  - Claude: Opus / Sonnet / Haiku (maps to the CLI's accepted model aliases/IDs; default Sonnet).
  - Codex: "Default (recommended)" + any detected slugs; default = leave unset.
- **Login status rows** (one per provider): detect binary presence + auth and show
  "✓ Logged in" / "Run `claude login`" / "Run `codex login`". Binary path override fields for each
  (`claudeBinaryPath`, new `codexBinaryPath`); auto-detect mirrors `ClaudeCodeRunner.locateBinary`
  (add `CodexRunner.locateBinary` checking `/opt/homebrew/bin/codex`, `command -v codex`).
- **Persistence:** `AppModel` gains `assistProvider`, `assistClaudeModel`, `assistCodexModel`,
  `codexBinaryPath` (all UserDefaults — no secrets; subscription CLIs hold their own auth).

### B3. Embedded terminal — live raw stream

**Design:**
- New `AssistTerminalView`: a monospaced, dark, auto-scrolling text panel bound to a published
  `[String]` (or rolling buffer) of streamed event lines on `ShaderAssistViewModel`.
- The view model's `run(...)` forwards each `onEvent` line into the buffer (`@Published var
  transcript`), so the terminal updates live while the model works (reasoning, tool/skill activity).
- The terminal sits in the assist section, collapsible; a **gear button** beside "Diagnose & Fix" opens
  the ShaderAssist settings.
- Streamed events are **display-only**; the **final message** still flows into the existing
  `ShaderAssistResponseParser` → fix/suggestions diff panel (unchanged downstream).
- Replace the static "Uses your Claude subscription" caption with a dynamic
  "Using <provider> · <model>" line.

### B4. ISF skill loading

**Design:**
- Build an **ISF knowledge preamble** at runtime from the two skill files:
  `~/.claude/skills/isf-shader-development/SKILL.md` + `~/.claude/skills/shader-dev/SKILL.md`.
  Concatenate (each under a labeled header), cap total length (e.g. ~12k chars; truncate the longer
  `shader-dev` body if needed) to bound prompt size/latency.
- **Fallback:** if those paths are absent (another machine), use a small bundled ISF primer string so the
  feature still works.
- **Injection:** Claude via `--append-system-prompt <preamble>` (and the CLI also has the skills natively
  available); Codex via the system/context portion of the prompt. Same preamble feeds both, so OpenAI
  gets equivalent ISF expertise.
- A `SkillPreamble.load() -> String` pure-ish function (file reads + cap) is unit-testable with a temp
  dir; the existing `ShaderAssistPrompt.system(for:)` composes preamble + task instructions.

---

## Cross-cutting

### Security
- **Codex sandbox:** always `-s read-only` + `--skip-git-repo-check`. The assist only *analyzes* and
  proposes a diff; the app applies edits through the existing guarded `TextEdit`/diff-review path. Codex
  never writes files or runs unsandboxed commands.
- **CSO review before shipping** (standing rule: new CLI-exec automation / new external-tool surface).
  Flag the `CodexRunner` + provider plumbing for a defensive review prior to merge.

### Cost
- ≈**$0 incremental.** Both providers run through their own CLI on existing subscriptions (Claude sub,
  ChatGPT/Codex sub). No API keys, no metered calls, no crons, no hosted infra. (No CFO gate needed; noted
  for completeness.)

### Testing
- Unit-testable (fakes / pure functions): `BlitFit.scale` (A3); `syncSelections` map copy (A4);
  provider arg-building + JSONL parsing for both `ClaudeCodeRunner` (refactored) and `CodexRunner` (B1)
  via the `ProcessRunning` fake; `SkillPreamble.load` cap/fallback (B4); `AppModel` settings round-trip.
- On-device gate (cannot be automated — native app): A1 collapse + shortcut, A2 wrap at narrow widths,
  A3 stretch shows bars not distortion, A4 pop-out shows camera, B2 settings + login status, B3 live
  terminal streams during a real Diagnose run on each provider.
- Live-integration: run an actual Diagnose & Fix through **both** `claude` and `codex` end-to-end before
  declaring done (per `live-integration-verify`).

## Architecture / file map

- **A1:** `Views/EditorScreen.swift` (+ `TrueISFEditorApp.swift` menu command).
- **A2:** `Views/EditorScreen.swift` (`renderControlsBar`).
- **A3:** `MetalPreviewController.swift` (blit shader + uniform); new `BlitFit.swift` (pure fit math) +
  test.
- **A4:** `OutputWindow.swift` (`syncSelections`), `SourceRouter.swift` + `CameraSource.swift` (shared
  camera injection), `EditorScreen.swift` (wire the sync).
- **B1:** `ShaderAssist/AssistProvider.swift` (new protocol), `ShaderAssist/ClaudeCodeRunner.swift`
  (refactor to streaming), `ShaderAssist/CodexRunner.swift` (new), `ShaderAssist/ShaderAssistViewModel.swift`.
- **B2:** `SettingsView.swift`, `AppModel.swift`.
- **B3:** `ShaderAssist/AssistTerminalView.swift` (new), `EditorScreen.swift` (`shaderAssistSection`).
- **B4:** `ShaderAssist/SkillPreamble.swift` (new), `ShaderAssist/ShaderAssistPrompt.swift`.

## Build order

1. **A4** black pop-out (blocking) → **A3** aspect-fit → **A2** toolbar → **A1** collapse.
2. **B1** provider abstraction + `CodexRunner` → **B4** skill preamble → **B2** settings → **B3** terminal.
3. CSO review → on-device gate → live-integration on both providers → merge.

## Open questions

- Exact Claude model alias strings the CLI accepts for the picker (verify `opus`/`sonnet`/`haiku` vs full
  IDs at build).
- Codex `--json` event schema field names for clean event-line rendering (inspect a real run during B1).
