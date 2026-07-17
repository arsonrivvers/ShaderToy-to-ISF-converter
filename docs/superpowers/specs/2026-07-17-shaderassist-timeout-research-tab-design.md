# ShaderAssist: timeout resilience + Research tab

**Date:** 2026-07-17 · **Status:** approved (Conner, in-session)

## Problem

1. A Suggestions "Apply Selected" run completed at 239.3s but the app's hardcoded 240s timeout
   (`ShaderAssistViewModel.run`, `timeout: 240`) killed the CLI during teardown and **discarded the
   completed result** sitting in the collected stdout. The user saw "Claude timed out. Try again."
   and lost a 4-minute run. The `.error` state also dead-ends: no retry, the whole goal-selection
   flow must be rebuilt by hand.
2. Typed custom goals go straight into the rewrite with no step where the model researches *how* to
   do them well. Conner wants a research mode: type a request, get skill-informed concrete upgrade
   ideas back, pick some, apply.

## Part 1 — Timeout resilience

- **420s timeout.** `ShaderAssistViewModel` uses `Self.runTimeout = 420` (matches Remix, which
  learned this on the same class of long rewrites).
- **Salvage-on-timeout.** `AssistRunError.timedOut` gains `(partialStdout: String)`. On timeout,
  `RealProcess` kills the child, waits (bounded, 2s) for the pipe readers to EOF, and throws
  `.timedOut(partialStdout: <collected stdout>)`. Each runner then inspects the partial stream:
  - `ClaudeCodeRunner`: if a complete `{"type":"result"}` event is present, return its text as a
    normal success (the run finished; only teardown outlived the timer).
  - `CodexRunner`: if a completed `agent_message` item is present, return it.
  - Otherwise rethrow `.timedOut`.
- **Try Again.** The viewmodel stashes `(task, source, diagnostics)` for every run;
  `retryLastRun()` re-runs it. The `.error` state renders a **Try Again** button (EditorScreen
  section + the goal sheet's research tab). Stale-source safety is unchanged: apply previews are
  still fingerprint-guarded against the *current* editor source at confirm time.

## Part 2 — Research tab

`SuggestionGoalSheet` becomes a 2-tab sheet (segmented control):

- **Quick Goals** — existing flow, unchanged.
- **Research** — multi-line request field ("What should we dig into?") + **Research Upgrades**
  button → new `ShaderAssistTask.research(request:)`. The system prompt directs the model to mine
  the loaded skill knowledge and return 3–6 concrete ideas (technique name, how it applies to THIS
  shader, kind, lines, impact) in the existing `AISuggestionsResult` schema. Ideas render as a
  checkbox list (selection = `model.selectedIdeaIDs`); **Apply Selected** feeds the same
  `applySelectedGoals` → coordinated rewrite → diff preview pipeline.

Knowledge: the research task loads `SkillPreamble.researchSources` = the default two skills
(isf-shader-development, shader-dev) **plus `arsonrivvers_technique_catalog`** (already inlined on
the Remix path; ShaderAssist gets it only for research to keep other prompts lean).

Security: no new tools, no web. The call keeps the exact tool-stripped posture
(`--tools "" --disallowedTools LSP …` / Codex `read-only`). Works with both providers.

Behavioral note: closing the sheet mid-research does NOT cancel the run (only the goals call is
cancelled, as today); if the research completes after dismissal, the ideas land in the main-screen
SuggestionsPanel — results are never thrown away.

## Testing

- Runner: timeout+salvage (result event present → success; absent → `.timedOut`); Codex analog.
- ViewModel: research transition parses into `.suggestions` + sets `activeSuggestionGoal`;
  `retryLastRun` re-invokes the provider with the same prompt; provider receives 420s.
- Kit: `.research` prompt assembly (system schema + user request present).
- Live smoke (protocol boundary): one real Research run against the actual `claude` CLI before
  declaring done. STAGED until Conner sees it on-device.
