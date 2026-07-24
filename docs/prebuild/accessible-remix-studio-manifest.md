---
schema_version: 1
topic: accessible-remix-studio
date: 2026-07-24
tier: fast
surfaces: [ui, persistent_storage, llm, external_api]
cousin_pattern: port-plan
activated_categories: [2, 5, 11, 12, 13]
decisions:
  model: "existing configured Claude/Codex provider"
  temperature: null
  caching: { strategy: "existing provider and WebKit behavior", cache_control: false }
  tools_vs_text: "existing provider safety flags remain unchanged"
  structured_output_schema: "existing RemixResponseParser contract"
  streaming: true
  prompt_registry_entry: "existing RemixPrompt, unchanged"
scaffolds_wired: [xcodegen, XCTest, native-arm64-build, manual-accessibility-gate]
budget_ceiling: { usd: 0, tokens: null, wall_clock_s: null, recursion_depth: null }
cfo_signoff: not-required
counsel_signoff: not-required
---

# Prebuild Manifest: Accessible Remix Studio

## What we're building

Retrofit the existing Remix Studio into a persistent three-zone native workspace. The user opens or restores a session, explicitly chooses parents, generates children, compares them in Grid, 2-up, or Hero mode, promotes or opens a winner, and recovers cleanly from provider, compiler, renderer, or Shadertoy verification failures.

## v1 vs v2

- v1: the complete approved spec at `docs/superpowers/specs/2026-07-24-accessible-remix-studio.md`.
- v2 (deferred): node-link lineage canvas, collaboration, cloud sync, session bundles, automatic LLM repair, more than two comparison panes, automated Shadertoy verification.

## Category status

| # | Category | Status | Notes |
|---|---|---|---|
| 1 | Eval-first | PASS | TDD for every state transition and pure interaction model. |
| 2 | Prior art | PASS | Port the existing Remix Studio, lineage tree, crossover controls, preview budget, progress strip patterns, and snapshot persistence patterns. |
| 3 | Best practices | N/A | Native patterns already established in this repository; no external recommendation required. |
| 4 | LLM design decisions | PASS | Provider, prompts, concurrency, safety flags, and response parser remain unchanged. |
| 5 | Budget guards | PASS | No new paid infrastructure or API usage. User-controlled batch size remains the usage ceiling. |
| 6 | Guardrails stack | PASS | Existing provider airlock remains. Untrusted shaders stay data, never instructions. |
| 7 | Tool airlock | PASS | No new tools or model agency. |
| 8 | Observability | PASS | Compact status and Activity Drawer expose generation, quiet, failure, retry, and verification states. |
| 9 | Prompt registry | N/A | No prompt changes. |
| 10 | Multi-tenant posture | N/A | Single-user local tool. |
| 11 | Failure-mode catalog | PASS | Full catalog lives in spec section 11. |
| 12 | HITL checkpoints | PASS | Cloudflare, Generate/Retry, promotion/open, security, native review, and on-device acceptance are explicit. |
| 13 | Scope clarity | PASS | UI, state, persistence, retry, accessibility, and WebKit resolver boundaries are named; deferred work is explicit. |

## Open questions

- None. Conner approved the spec and delegated remaining product calls.

## Failure-mode catalog

Use the complete table in spec section 11. No failure may erase entered source, selected parent target, successful siblings, lineage, or the actionable next step.

## HITL checkpoints

Use the complete table in spec section 12. Cloudflare always requires legitimate human interaction when the site requests it; the app never synthesizes or accessibility-presses the widget.

## Brand/voice constraints

- `/Users/arsonrivvers/.claude/user-context/profile.yaml`
- Minimum rendered text size: 14 px equivalent.
- Concrete maker-facing language, no corporate gloss, no raw provider JSON.
