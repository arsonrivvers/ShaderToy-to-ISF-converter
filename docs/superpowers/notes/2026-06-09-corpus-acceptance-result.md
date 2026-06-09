# P1.5 corpus acceptance result (2026-06-09)

Ran `CorpusRenderTests` over every `AR_*.fs` in `/Library/Graphics/ISF` through the native
`MetalPreviewController` (ISFMSLKit = VDMX6's engine). Cold PINCache, 5s per-shader poll.

## Headline (final, after the genuine-completion harness fix)
- **Total: 896 — Pass: 776 — Fail: 120 — rate 86.6%** (first pass with a 5s poll read 763/85.2%; the
  difference was a cascade artifact — see Timeout row below.)
- **Zero crashes** across all 896 (validates the crash-safe `ISFMSLSafeBridge` shim — before it,
  the run terminated on the first pathological shader).
- Core hypothesis confirmed corpus-wide: ES3 shaders (dynamic loops/indexing) the WebGL1 engine
  rejected now compile/render.

## Failure breakdown (120)
| Category | Count | Verdict |
|---|---|---|
| `texture2D()` legacy GL function | 67 | Legitimate — ISFMSLKit/VDMX reject it too (needs `texture()`/`IMG_PIXEL`). Matches VDMX. |
| Reserved-word collisions (`active`, …) | 17 | Legitimate — MSL reserved words; VDMX rejects identically. |
| Other GLSL errors (undeclared ident, fn redeclaration, line-continuation, …) | 33 | Mostly genuine shader-side errors; a couple may be ISF-builtin naming worth a later look. |
| Genuinely slow/hang (>20s) | 3 | `day12_v12`, `day12_v13`, `day14_v01` — transpiler is genuinely slow or hangs on these. In the live app they'd sit "compiling" a while; user can switch to WebKit or wait for the PINCache. Worth a deeper look but 0.3% of corpus. |

The 5s→20s harness change (wait for GENUINE per-shader completion) resolved 13 of the original 16
"timeouts": they were cold-transpile latency cascading through the serial transpile queue, not real
failures — they now pass. So ~84/120 failures are **VDMX-equivalent legitimate rejections**: the engine
matches VDMX *including its rejections*, which is the fidelity goal.

## Follow-ups done before merge
1. ✅ Resolved the timeout cascade (harness waits for genuine completion) — 16→3, and the 3 are genuine.
2. ✅ Wrapped `createAndRender` in a C++ try/catch (`ISFMSLSafeRender`) for render-time crash safety.
3. ✅ Added a blit pixel-format adaptive guard in `draw(in:)`.

## Remaining follow-ups (not P1.5 blockers)
- Investigate the 3 genuinely-slow shaders (`day12_v12/v13`, `day14_v01`) — likely a heavy multipass/loop
  the transpiler struggles with.
- Spot-check a few "other" errors (`uvAspect`, `_current_imgRect`) for ISF-builtin naming gaps.

## How to re-run
`echo "" > /tmp/trueisf-corpus.run` then run `-only-testing:TrueISFEditorTests/CorpusRenderTests`
(put an integer in the sentinel file to cap the count). Report is printed + written to the test
process's temp dir as `corpus-report.txt`.
