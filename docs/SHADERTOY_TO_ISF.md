# Shadertoy → ISF conversion: discoveries & gap map

Living record of what we've learned converting real Shadertoy shaders to ISF (Interactive Shader
Format) in this project. Two audiences: engineers working on the converter (`ShadertoyISFKit`), and
anyone hand-porting a shader. Generalizable porting knowledge here is a candidate to fold into the
`isf-shader-development` skill (see [§Skill fold](#folding-into-the-isf-shader-development-skill)).

## The core problem

A Shadertoy import can "convert cleanly" (the text rewrite ran) yet render **black**, because the
converter (`ShadertoyISFKit`, text rewriting) and the GPU transpiler (`ISFMSLKit`, glslang→Metal) are
**separate stages**. "Converted cleanly" only means the rewrite succeeded — not that glslang/Metal will
accept the result. Every unhandled GLSL/Shadertoy feature slips through to a runtime compile failure.
So conformance is measured by transpiling, not by converting.

## The conversion pipeline (order matters)

`ISFConverter.convert` runs these stages (see `ShadertoyISFKit/Sources/ShadertoyISFKit/`):

1. **`PassBuilder`** — split renderpasses into image/buffer passes + the Common tab; assign buffer names (bufA…). Sound/cubemap passes are dropped.
2. **Per pass**, in order:
   - `GLSLLineContinuation.splice` — join `\` continued lines (glslang rejects them).
   - `UniformRewriter` — Shadertoy uniforms → ISF builtins (table below), incl. `iChannelResolution[N]`/`iChannelTime[N]`.
   - iMouse → `vec4(mouse * RENDERSIZE, …)`.
   - auto-stub any `iChannelN` used but undeclared.
   - `SamplerRewriter` — `texture`/`texelFetch`/`textureLod(iChannelN,…)` → `IMG_*_PIXEL(boundName,…)`; cubemap → equirect; bias/LOD dropped.
3. **Common tab**:
   - stub Common-only channels;
   - **`CommonChannelRewriter`** — `iChannelN` sampling in Common → generated `_chN_texel`/`_chN_tex` **PASSINDEX dispatchers** (Common is shared but a channel can bind a different buffer per pass);
   - `CommonUniformRewriter` — scope-aware uniform rewrite (file scope only; leaves helper params alone).
4. **`GLSLBodyBuilder`** — `GLSLPassNamespace` (rename same-name/different-body helpers per pass), rename `mainImage`→`passN_mainImage`, build the `PASSINDEX` dispatch in `main()`, prepend Common + dispatchers.
5. **`GLSLFunctionDedup`** — drop byte-identical duplicate helpers merged across passes.
6. **`OutputInitializer`** — init accumulated outputs (`for(O*=i;…)`) to avoid NaN→black.
7. **`GLSLCompat`** — polyfills (`tanh`/`round`/…), packing `#extension`, `_dirToEquirect` cubemap helper.
8. **`GLSLLint`** + **`HeaderBuilder`** (emit the ISF JSON header).

Shared parsing utilities: `GLSLFunctionScanner` (function defs), `GLSLCallParser` (call sites).

## Shadertoy → ISF mapping reference

### Uniforms
| Shadertoy | ISF | Notes |
|---|---|---|
| `iResolution` | `vec3(RENDERSIZE, 1.0)` | |
| `iTime` | `TIME` | |
| `iTimeDelta` | `max(TIMEDELTA, 1e-4)` | guard first-frame 0.0 |
| `iFrame` | `FRAMEINDEX` | |
| `iFrameRate` | `60.0` | constant approximation |
| `iDate` | `DATE` | |
| `iSampleRate` | `44100.0` | constant |
| `iMouse` | `vec4(mouse*RENDERSIZE, mouse*RENDERSIZE)` | ISF `mouse` point2D, normalized; zw mirrored so click-gated shaders engage |
| `iChannelResolution[N]` | `vec3(RENDERSIZE, 1.0)` | exact for buffer channels; approximate for image inputs |
| `iChannelTime[N]` | `TIME` | loses per-channel playback offset |

### Channels & sampling
| Shadertoy | ISF |
|---|---|
| `texture(iChannelN, uv)` | `IMG_NORM_PIXEL(name, uv)` |
| `texelFetch(iChannelN, p, lod)` | `IMG_PIXEL(name, vec2(p))` (lod dropped) |
| `textureLod(iChannelN, uv, lod)` | `IMG_NORM_PIXEL(name, uv)` (lod dropped) |
| cubemap `texture(iChannelN, dir3)` | `IMG_NORM_PIXEL(name, _dirToEquirect(dir3))` — supply an equirect image |
| Buffer A–D | ISF `PASSES` targets bufA… (PERSISTENT+FLOAT) |
| `iChannelN` in Common (sampling) | `_chN_texel`/`_chN_tex` PASSINDEX dispatcher |
| webcam / video / keyboard / volume | stubbed as a static `image` input (+warning) |
| music / mic / musicstream (audio) | ISF `audioFFT` + `audio` (two samplers). A read `texture(iChannelN, C)` → `mix(IMG_NORM_PIXEL(fft, vec2(C.x,.5)), IMG_NORM_PIXEL(wave, vec2(C.x,.5)), step(0.5, C.y))` — FFT below the halfway row, waveform above (Shadertoy's 512×2 layout). Host must supply audio. |

### Gotchas that black-screen on Metal/ISF (not just Shadertoy quirks)
- **No ternary on vector types** (`cond ? vecA : vecB`) — unreliable on Metal; use `if/else` or `mix`+`step`.
- Persistent-buffer self-reads return **last frame's** data (ping-pong for fresh values).
- Loop bounds must be compile-time `const` (or fixed bound + runtime `break`).
- `FRAMEINDEX == 0` is fragile — use `< 2`.

## Gap classes

### Fixed (each has a generic rewriter + unit tests)
internal-endpoint `type` vs REST `ctype`; `\` line-continuations; `packHalf2x16`/pack family
(`#extension GL_ARB_shading_language_packing`); bare/threaded `iChannelN` as args; unbound `iChannelN`
auto-stub; uninitialized output accumulators; cubemap→equirect; Common-tab parameterized uniforms;
`#define` header-macro brace-scope; byte-identical cross-pass helper dedup; **per-pass same-name
different-body helper namespacing** (`GLSLPassNamespace`); **`iChannelResolution`/`iChannelTime`**;
**Common-tab `iChannelN` sampling via PASSINDEX dispatchers** (`CommonChannelRewriter`); **Common
header-macro `mainImage`** (`HeaderMacroExpander`); **audio inputs** (music/mic → ISF `audioFFT`+`audio`);
**Allman-brace / multi-line / array-param function-header detection** (`GLSLFunctionScanner` — `)` then
newline `{`; excludes `else if`-style control keywords); **transitive helper namespacing** (an identical
helper that calls a per-pass-differing callee, e.g. `calcNormal`→`map`, is namespaced too so dedup can't
strand the now-diverged copies); **file-scope global / const / array collisions** (`GLSLGlobalScanner` +
`GLSLPassNamespace`/`GLSLFunctionDedup` — distinct-value globals like per-pass `float f` namespaced,
byte-identical ones like `palAppleII` deduped to one shared copy); **MSL-reserved user identifiers**
(`GLSLReservedIdentifierRewriter` — `char`/`coord`/C++ keywords renamed; legal GLSL, rejected by Metal).

### Remaining (from the 78-shader discovery corpus — ranked by impact)
1. **Bare `iChannelN` in Common** (~2: `3cyGWG`/`tcKGWD`) — a sampler threaded as a value; GLSL can't return a sampler from a dispatcher.
2. **Misc** (~2) — `t3tyDM` (`sampler` struct-tag, surfaces as `unused variable 'v'`), `w3GGRy` (generic "Shader failed to compile").

**Closed in the 74/78 step (per-pass macro scoping):**
- ~~`syntax error, unexpected FLOATCONSTANT`~~ (`4ldGDB`/`4XXGDl`/`ftGXzz`/`Ndc3zj`) — NOT `step`-as-variable as previously guessed. Root cause: one pass `#define`s an object macro (`_G0`) and another pass declares a same-named identifier (`const float _G0 = 0.25;`); the file-global macro rewrites the declaration into `const float 0.25 = …`. Fixed by `GLSLPassMacroScoper`.
- ~~Macro redefined across passes~~ (`M3cGW2` `bb`, `tlX3zs` `A`) — two passes `#define` the same function-like macro; `SamplerRewriter` rewrites each `iChannelN` to a per-pass sampler so glslang sees "different substitutions". Same fix — a trailing `#undef` per defining pass makes the redefinition clean.

## Discovery harness

The browse-based in-app harvester plateaus on ~12 popular shaders. For real coverage use the curated,
feature-diverse list and the batch runner:

```
./scripts/corpus-run.sh                      # corpus/discovery-ids.txt through the real transpiler
./scripts/corpus-run.sh -o /tmp/raw ids.txt  # also dump raw shader JSON
```

Debug hooks (set on the built app binary): `SHADERTOY_DEBUG_FETCH=<id>` (fetch+convert, print .fs),
`SHADERTOY_DEBUG_ISFMSL=<path.fs>` (transpile one file, print compile error),
`SHADERTOY_DEBUG_CORPUS=<ids-file|browse:popular:N>` (batch report).

### Conformance baseline
- Curated 78-shader corpus: **54/78 (69%)** → **57/78** (`CommonChannelRewriter`) → **61/78 (78%)** (`HeaderMacroExpander`) → **68/78 (87%)** (function/global-redefinition cluster + MSL-reserved identifiers) → **74/78 (95%)** (`GLSLPassMacroScoper` — per-pass `#undef`), zero regressions throughout. The +6 step closed BOTH the FLOATCONSTANT class (object macro vs same-named declaration across passes) and the macro-redefinition class (function-like macro `#define`d in 2+ passes, made distinct by per-pass sampler rewriting) — one root cause: Shadertoy's per-pass preprocessor isolation is lost when passes are concatenated into one ISF file. The +7 step before it closed: Allman/multi-line function-header detection (`gather8FromB`/`B`), transitive helper namespacing (`calcNormal`/`textb`), file-scope global collisions (`f`/`pi`/`palAppleII`), and MSL-reserved identifiers (`char`/`coord`).
- NOTE: the WebKit fetch in the corpus harness is **flaky run-to-run** — a few IDs intermittently `FETCH-FAIL` (network, not conversion). Always re-run the fetch-failures before trusting a headline count; the real OK count excludes them.
- Popular-plateau corpus: ~10/12 (the 2 fails are deferred `ssjyWc`/`wXdfzj`-class).

## Folding into the `isf-shader-development` skill

The **mapping reference** and **gotchas** sections above are general Shadertoy→ISF porting knowledge,
not converter-internals — strong candidates for a new `references/shadertoy_porting.md` in the
`isf-shader-development` skill (it currently covers ISF authoring but not porting *from* Shadertoy).
Converter pipeline/gap-class detail stays here (project-specific). See the skill's `SKILL.md` "When to
load reference files" for where a porting reference would slot in.
