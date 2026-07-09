# Shared GLSLScanner + Rewriter Protocol — Design (Plan Task 3.2)

**Date:** 2026-07-09 · **Branch:** `desloppify-cleanup` · **Plan of record:** `docs/superpowers/plans/2026-07-08-launch-hardening-and-elevation.md` Task 3.2
**Closes:** M3, N1, C5, M14, M18, M20, N2, M1, M2 (M19 already resolved; its `GLSLComments.strip` helper is absorbed as the scanner's seed)
**Gate:** full kit + app suites, `scripts/corpus-run.sh` with pixel gate after every migration step. Compile pass-list must stay identical (verified by ID); pixel-OK count must stay ≥ 64/78 baseline. Any regression reverts that step.

## Problem

Six hand-rolled char-scanning state machines walk GLSL tracking comment/brace/paren state, and they disagree (survey 2026-07-09, all line refs verified then):

| # | Walker | Tracks | Missing |
|---|--------|--------|---------|
| A1 | `GLSLCallParser.replaceCall` (:16-51) | line+block comment | depth, directive |
| A2 | `GLSLCallParser.parseArgs` (:86-103) | line+block comment, paren depth | brace, directive — near-identical copy of A1's comment logic |
| B | `GLSLGlobalScanner.depth`/`statementEnd` (:40-80) | comments, brace depth | paren, directive |
| C | `GLSLFunctionScanner.braceMatchEnd` (:57-76) | comments, brace depth | paren, directive; plus a *third* regex-based comment strip in `normalize` (:41-47) |
| D | `GLSLComments.strip` (:10-32) | comments only | everything else (by design — offset-preserving blank) |
| E | `CommonUniformRewriter.walkRuns` (:48-115) | comments, **directive mode**, brace+paren depth | — (most complete; the model) |

`ShaderAssistResponseParser.extractObject` is brace+string-aware but scans **JSON**, not GLSL — deliberately out of scope.

Consequences already on the backlog: phantom defs from matches inside block comments (M14), `iTime` shipped raw from Common function bodies (C5), paste-path syntax errors (M20), Common-vs-pass macro collisions invisible to the scoper (M18), reserved-word rewrites inside comments (N2), plus M1/M2 scanner blind spots. The 2026-07-09 pixel baseline exposed 10 BLACK compile-clean shaders (`wc33RN wX33zX M3BfzG XtdSDn XXVfRV wfX3WX lcXXzM 33jcRR tXfBz2 3XBBWD`) hypothesized to be largely this class.

Separately (N1), the 14-stage pipeline's rewriters return five different shapes: bare `String`, `[String]`, `Result{code,warnings}`, `Result{code,notes}`, bare `[ConversionWarning]`.

## Goals / Non-goals

**Goals:** one scanner primitive; all six walkers deleted; C5/M14/M18/M20/N2 fixed structurally; M1 per-pass, M2 multi-declarator; one `RewriteResult` convention; corpus pixel-pass ≥ baseline with triaged BLACKs flipping.

**Non-goals:** no full GLSL tokenizer/AST (YAGNI — five queries don't need a parser); no dynamic pipeline composition (ordering is load-bearing, M13 — the explicit stage list in `ISFConverter` stays); no string-literal state (GLSL in this pipeline has none); `ShaderAssistResponseParser` untouched.

## Task 0 — Triage (before any refactor)

1. Fetch the 10 BLACK shaders' sources (`SHADERTOY_DEBUG_FETCH` hooks) and attribute each: C5 (uniform in Common function body) / M1 (multipass accumulator falsely deduped) / M2 (multi-declarator global collision) / other-known / unknown.
2. Re-run the 14 STATIC shaders with a longer pixel-gate warm-up (e.g. 10 frames / later sample times) to identify feedback shaders mislabeled STATIC. If any flip to OK, note it; changing the gate's defaults is a separate decision, not part of this task.
3. Record the attribution table in the implementation plan. **Exit criteria bind to the BLACKs attributed to C5/M1/M2-class causes**, not to all 10.

## Architecture

### GLSLScanner (new: `Rewriters/GLSLScanner.swift`)

One forward cursor over a string's UTF-16 view (matching existing `Def` range semantics):

```swift
struct GLSLScanner {
    struct State {
        var inLineComment: Bool
        var inBlockComment: Bool
        var inDirective: Bool      // inside a #… line (continuations honored)
        var braceDepth: Int        // outside comments/directives only
        var parenDepth: Int
        var inComment: Bool { inLineComment || inBlockComment }
    }
    // iteration: callback or sequence yielding (index, unit, state)
    // state semantics modeled on CommonUniformRewriter.walkRuns —
    // the one walker that survives unbalanced braces in #define bodies
}
```

Helper layer (static queries built on the cursor — each replaces a named legacy implementation):

| Helper | Replaces | Notes |
|---|---|---|
| `inComment(at:)` / `commentSpans(in:)` | nothing (new) | M14's match-position check |
| `strip(_:)` | `GLSLComments.strip` | offset-preserving blank, identical semantics |
| `depth(before:)` | `GLSLGlobalScanner.depth` | now directive-safe |
| `statementEnd(from:)` | `GLSLGlobalScanner.statementEnd` | |
| `braceMatchEnd(from:)` | `GLSLFunctionScanner.braceMatchEnd` | |
| `splitArgs(_:openParen:)` + call walk | both `GLSLCallParser` loops | one comment-skip implementation |
| `topLevelRuns(in:)` | `CommonUniformRewriter.walkRuns` | protected/file-scope runs |
| `functionDefs(in:)` | extends `GLSLFunctionScanner.defs` | **new capability**: `{ name, params: [String], headerRange, bodyRange, fullRange }` |

Scanners are total functions: no throws; unterminated block comments / unbalanced braces scan to end-of-string (current behavior, now documented once at the primitive).

### RewriteResult convention (N1)

```swift
struct RewriteResult {
    var code: String
    var warnings: [ConversionWarning]
}
```

Every single-output rewriter converges on `rewrite(...) -> RewriteResult` (`OutputInitializer.notes` renamed to `warnings`; bare-`String` rewriters wrap with `warnings: []`). Multi-output stages (`HeaderMacroExpander`, `CommonChannelRewriter`, `GLSLBodyBuilder`) keep typed result structs but adopt the field-naming convention and carry `warnings`. `GLSLLint.check` stays detection-only (`[ConversionWarning]`) — it rewrites nothing and pretending otherwise obscures that. The `ISFConverter.convert` stage list stays explicit; its header comment is updated in the same commit as any signature change.

## Migration order (each step: full suite + corpus, own commit)

1. `GLSLScanner` primitive + `GLSLScannerTests` (state-transition matrix — written first; closes the zero-direct-coverage gap over B/C behavior **before** anything moves).
2. `GLSLComments` → delegates to `strip` (lowest risk, pure detection path).
3. `GLSLCallParser` → both loops onto the cursor; C1's tests pin comment handling.
4. `GLSLGlobalScanner` → `depth`/`statementEnd` onto helpers; **M14 fixed here** (reject in-comment match positions) for globals.
5. `GLSLFunctionScanner` → `braceMatchEnd` onto helper; `defs` gains params/bodyRange (`functionDefs`); **M14 fixed** for functions; regex `normalize` comment-strip replaced by `strip`.
6. `CommonUniformRewriter` → `walkRuns` onto `topLevelRuns`.
7. N1 `RewriteResult` convergence (mechanical, behind all existing tests).

## Design changes on the new base (each: TDD, own commit, corpus-gated)

- **C5 + M20 (one design):** scope-aware uniform rewriting — inside a function body, protect a uniform name **only if that function's own param list declares it** (via `functionDefs`); rewrite otherwise. Apply the same rewriter to pass bodies on the paste path (`ShaderFactory` markerless blob). `unrewrittenBodyUniforms` warning kept as safety net — expected to fire ~never afterward.
- **M18:** `GLSLPassMacroScoper.scope(passBodies:commonCode:)` — Common `#define`s join collision detection; mention-detection becomes comment-aware (fixes its current comment-blindness; spurious `#undef`s from comment mentions also disappear).
- **N2:** `GLSLReservedIdentifierRewriter` skips comment spans (strip-mask then rewrite at surviving offsets).
- **M1:** `OutputInitializer` moves from stage 12 (merged file) to per-pass on each isolated pass body, before `GLSLBodyBuilder` assembly. The one pipeline reorder — its own commit, corpus-validated, stage-list comment updated.
- **M2:** `GLSLGlobalScanner` parses multi-declarator statements (`float a, b, c;`, `float a = 1., b = 2.;`) into one `Def` per declarator so `GLSLFunctionDedup`/`GLSLPassNamespace` see every name.

## Testing

- TDD throughout (RED → GREEN per superpowers discipline).
- New: `GLSLScannerTests` (comment/directive/depth transition matrix: `//` inside `/* */`, `*/` immediately followed by `/*`, `\`-continued `#define`, unbalanced braces in macro bodies, unterminated comment at EOF); C5 shadow matrix (param-shadowed / free / nested braces / paste-path); M18 Common-vs-pass collision; M1 multipass accumulator (pass 0 plain-assigns, pass 1 accumulates); M2 declarator lists.
- Existing suites are the migration net: every legacy consumer keeps its tests green through delegation.
- Corpus: `scripts/corpus-run.sh` after every migration step and every design change. Compile pass-list identical by ID; pixel ≥ 64/78 OK; attributed BLACKs flip by the end.

## Risks

- **M1 reorder** changes behavior on single-pass shaders too (detector now sees pass body without Common). Mitigate: detector input = pass body only, but confirm no corpus regression; revert-first discipline on any BLACK/pass-list change.
- **M2** changes `Def` boundaries consumed by dedup/namespace — the highest-subtlety scanner change; lands after both consumers already sit on the shared primitive with tests.
- **C5** flips rewriting ON for code skipped for months. The triage table tells us which corpus shaders exercise it; `unrewrittenBodyUniforms` inverts from "warn on miss" to a regression tripwire.

## Exit criteria (from the plan, sharpened by triage)

One scanner primitive; six walkers deleted; C5/M1/M2/M14/M18/M20/N2 closed in `DESLOPPIFY.md`; N1 convention in place; corpus compile pass-list unchanged; pixel-OK ≥ 64/78 with the triage-attributed BLACKs flipped to OK.
