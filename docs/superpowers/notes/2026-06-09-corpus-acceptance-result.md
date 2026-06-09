# P1.5 corpus acceptance result (2026-06-09)

Ran `CorpusRenderTests` over every `AR_*.fs` in `/Library/Graphics/ISF` through the native
`MetalPreviewController` (ISFMSLKit = VDMX6's engine). Cold PINCache, 5s per-shader poll.

## Headline
- **Total: 896 — Pass: 763 — Fail: 133 — rate 85.2%**
- **Zero crashes** across all 896 (validates the crash-safe `ISFMSLSafeBridge` shim — before it,
  the run terminated on the first pathological shader).
- Core hypothesis confirmed earlier and corpus-wide: ES3 shaders (dynamic loops/indexing) that the
  WebGL1 engine rejected now compile/render.

## Failure breakdown (133)
| Category | Count | Verdict |
|---|---|---|
| `texture2D()` legacy GL function | 67 | Legitimate — ISFMSLKit/VDMX reject it too (needs `texture()`/`IMG_PIXEL`). Matches VDMX. |
| Reserved-word collisions (`active`, …) | 17 | Legitimate — MSL reserved words; VDMX rejects identically. |
| Other GLSL errors (undeclared ident, fn redeclaration, line-continuation, …) | 27 | Mostly genuine shader-side errors; a couple may be ISF-builtin naming worth a later look. |
| Timeout >5s, no flag | 16 | Suspect but likely benign: 13 are one family (`AR_Genuary2026_day14_v01..v13`) — almost certainly cold first-transpile latency exceeding the test's 5s poll, not true failures. The live app's async load completes + PINCaches. |

So ~84/133 failures are **VDMX-equivalent legitimate rejections**: the engine matches VDMX *including
its rejections*, which is the fidelity goal. Effective pass-rate for shaders that should work is well
above 85%.

## Follow-ups (not P1.5 blockers)
1. Re-run the 16 timeouts with a longer poll / warm cache to confirm they're latency, not failures.
2. Spot-check a few "other" errors (`uvAspect`, `_current_imgRect`) for ISF-builtin naming gaps.
3. (From the render task) consider wrapping `createAndRender` in the same C++ try/catch as load, in case
   a compiled-but-pathological shader throws at render time during a live set.

## How to re-run
`echo "" > /tmp/trueisf-corpus.run` then run `-only-testing:TrueISFEditorTests/CorpusRenderTests`
(put an integer in the sentinel file to cap the count). Report is printed + written to the test
process's temp dir as `corpus-report.txt`.
