# ARShader Milestone 2, phases 3b + 3c — the merge-gate record

Preserved 2026-08-02, before `git worktree prune` could delete it.

This is the adjudication trail behind the `m2-slot-bank` merge: 71 commits, three review gates, two
fix waves. It lived under `.superpowers/`, which is **gitignored** (`.gitignore:18`) and therefore
would have been destroyed the moment the worktree was pruned. Only the branch's *code* was ever
tracked; every judgement about that code was not.

## What is here, and what deliberately is not

**Preserved:** all 41 markdown files — every task brief, every implementer report, every review
verdict, and both phase ledgers. These record decisions, refusals, corrections and mutation proofs
that exist nowhere else and cannot be re-derived from source.

**Not preserved:** the 25 `review-*.diff` files (1.4MB). Each is exactly `git diff <range>` and git
regenerates them on demand forever — committing them would have been storing 1.4MB of derived data
next to the thing that derives it. To rebuild any of them:

```sh
git diff 02fbcd4..9b21ad4 > review-02fbcd4..9b21ad4.diff
```

Phase 3c ranges: `02fbcd4..9b21ad4` (the whole-branch review), `9b21ad4..7fff542` (the 14-item fix
wave), `3edc396..9b21ad4`, `4932bdb..aba0283`, `4f13981..4932bdb`, `aba0283..3edc396`,
`ab775f0..e663888`, `e663888..72fb22e`, `36b23d2..fd2f9f7`, `f8b7d03..36b23d2`, `aa62863..f8b7d03`,
`ebd1bc2..aa62863`, `18e73d8..ebd1bc2`, `711971c..18e73d8`, `f19a70f..711971c`, `30bf31a..f19a70f`,
`74a6db8..30bf31a`.

Phase 3b ranges: `fb120e2..b323817`, `b323817..b5e6d32`, `b5e6d32..f1fa9e4`, `c38eea6..f9a67a7`,
`f9a67a7..fc1d765`, `fc1d765..6f94462`, `7e3d1c8..64e3a24`, `64e3a24..57b4538`, `57b4538..89dc2a1`,
`a9037ba..9f99e0c`, `9f99e0c..7e3d1c8`, `735c65c..dbc64cf`, `dbc64cf..d0f6fc3`.

## Where to start

| Read this | For |
|---|---|
| `sdd/2026-08-01-arshader-thumbnails-and-drag-drop/progress.md` | **The ledger.** Phase 3c decision by decision, including every operator ruling and every deferred finding. The single most useful file here |
| `sdd/2026-07-31-arshader-slot-bank/progress.md` | The same for phase 3b |
| `final-review-report.md` | The whole-branch review, 60 commits — verdict MERGE AFTER FIX WAVE, 10 findings, 0 Critical |
| `final-fix-wave-report.md` + `final-fix-wave-rereview.md` | The 14-item wave and the scoped re-review that caught F7's flag lifecycle reproducing the very defect F7 landed to fix |
| `final-fix-round-2-report.md` | The 3-item round that closed it |
| `badge-observation-fix-report.md` | Task 9 — the live-badge defect the operator found on device in his first two minutes |
| `hang-fastfail-report.md` | The suite "freeze" — mitigation only, root cause still open |

## Three findings worth carrying past this milestone

1. **`ensureGlobals` is dead code in both apps.** Neither `ISFMSLCache.primary` nor `VVMTLPool.global`
   is ever installed — 7 assignment sites, all behind statically-false guards, because
   `NS_ASSUME_NONNULL` makes the `== nil` checks unreachable. Every *first* sight of any shader pays
   a full transpile plus Metal compile, in ARShader **and** TrueISFEditor. Plausibly the largest
   latency win available anywhere in this codebase. Filed:
   `arshader-ensureglobals-dead-msl-cache-20260802`.
2. **The ARShader suite is a 25-second suite**, and every multi-minute "the tests are frozen" run was
   one test (`testSteadyStateAllocatesNoNewTextures`) hanging. **Never judge an xcodebuild run from
   the console tail** — after a host restart it prints a per-launch summary reading
   `Executed 175 tests, with 0 failures` for a run that FAILED with a real total of 327. Only
   `xcrun xcresulttool get test-results summary --path <bundle>.xcresult` tells the truth.
3. **Hover-preview supersession cannot be fixed by any counter or generation scheme.** It is an
   executor FIFO race — render A's job is enqueued strictly before hover B can enqueue its cancel —
   so every cheap fix loses the same race. Only a real suspension point inside `render()` works. The
   150ms dwell delay sidesteps it upstream, which is why a fast sweep is free and a deliberate slow
   sweep on a cold cache is not.

## Status at preservation time

Branch `m2-slot-bank` @ `57aaea5`, 71 commits ahead of `02fbcd4`. ARShader **333/333, 0 skipped**;
TrueISFEditor SUCCEEDED; ShadertoyISFKit 312/0. Build installed at `b61658c`, dylib `06f4aea8…`.

**The 44 live-smoke legs were UNRUN at the moment this was preserved** — see
`docs/reports/live-smoke-instrument-m2-phase3c.md` for their outcome. Nothing in this branch was
CONFIRMED by preservation time; the code was reviewed, not witnessed.
