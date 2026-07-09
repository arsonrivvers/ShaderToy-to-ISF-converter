---
name: isf-shader-development
description: "Use for ISF (Interactive Shader Format) / VDMX work — the `.fs` files used by VDMX, CoGe, ISF Editor and other VJ/live-performance hosts. Trigger on ISF, `.fs` files, VDMX, CoGe, ISF Editor, PERSISTENT/FLOAT buffers, multi-pass ISF shaders, a `/*{ ... }*/` JSON header, or `PASSINDEX`/`RENDERSIZE`/`IMG_NORM_PIXEL`/`isf_FragNormCoord`/`FRAMEINDEX`/`TIMEDELTA`, or converting a generator to/from a filter for VJ use. Covers the ISF JSON header, INPUT types, PASS structure, host quirks (Metal vs OpenGL; VDMX/CoGe/ISF Editor differences), filter-vs-generator conventions, and ArsonRivvers code style — NOT general GLSL technique (ray marching, SDFs, noise, lighting, palettes, fluid sim, post-processing), which belongs to `shader-dev`. Complement: `shader-dev` is what goes inside the passes; this is how to wire them into a working ISF file."
---

# ISF Shader Development

ISF (Interactive Shader Format) is a GLSL fragment-shader spec with a JSON header that declares inputs, multi-pass structure, and persistent buffers. It's the lingua franca of VJ tooling — VDMX, CoGe, ISF Editor, Resolume (via plugins), TouchDesigner (via bridges). Hosts compile the GLSL and expose the JSON inputs as live controls.

A working ISF shader is *not* just GLSL with a comment on top. The JSON drives the host's UI, the pass structure, and the buffer lifecycle. Get the JSON wrong, the file won't load at all. Get the buffer architecture wrong, the shader compiles but produces visual garbage that looks like a real artistic effect — the worst failure mode.

## Scope — what this skill does and doesn't cover

This skill is the **ISF/VDMX wrapper layer**, not a GLSL technique library. The user also has the `shader-dev` skill installed which covers 36 general GLSL techniques.

**Use this skill for:** the JSON header (INPUTS, PASSES, types, LABELs), ISF's auto-declared uniforms, IMG_*_PIXEL sampling macros, persistent buffer + multi-pass architecture (the ISF-specific mechanics — JSON declaration, PASSINDEX dispatch, last-frame-read semantics), Filter vs Generator conventions, host-specific quirks (VDMX, CoGe, ISF Editor, Metal vs OpenGL backends), VJ workflow patterns (macro/conductor params, coarse/fine pairs, UI section dividers), reset patterns using ISF events, and ArsonRivvers code style.

**Defer to `shader-dev` for:** ray marching internals, 2D/3D SDF primitives and CSG, lighting models (Phong, PBR, toon), procedural noise (Perlin, Simplex, Worley, FBM), color palettes and HSV/RGB math, fluid simulation math (Navier-Stokes), reaction-diffusion *math* (the Gray-Scott equations themselves — the *ISF wiring* around them is here), cellular automata rules, fractals, polar UV / kaleidoscope math, anti-aliasing techniques, generic post-processing kernels (bloom, tone mapping, chromatic aberration), camera matrix math, particle systems.

When a request needs both — "build a raymarched feedback effect in ISF" — load both skills. `shader-dev` answers "how do I write the raymarcher"; this skill answers "how do I put it in three passes with a feedback buffer that decays and survives across frames in VDMX."

**`shader-dev` adapts ShaderToy code to WebGL2** with `#version 300 es`, `out vec4 fragColor`, etc. **Do not apply those rules in ISF.** ISF handles versioning itself, uses `gl_FragColor`, and has its own sampling macros instead of `texture()`. If you find yourself adding a `#version` directive or renaming `gl_FragColor`, you're in the wrong runtime.

## Working style for this user

Before reaching for general defaults: this user is a working VJ/live-performance artist, not a beginner. The expected workflow:

- **Edit in place.** Modify the file the user provided. Do not produce `_v2`, `_fixed`, or `_new` variants unless explicitly asked. Version numbers in filenames belong to the user.
- **No preamble explaining what ISF is** or restating the user's request. Diagnose, edit, hand back the file.
- **Tests happen in VDMX / ISF Editor / CoGe**, not in this conversation. The user will load the shader, observe behavior, and report back with precise feedback ("the slider does nothing past 0.3", "buffer doesn't reset", "edges are wrong on macOS but fine on Linux"). Respond to that feedback specifically; don't ask broad clarifying questions when the report is already concrete.
- **Implementation rationale is only worth including when it informs a creative choice** the user might want to override. "I used `max(prev*decay, current)` because `mix()` causes trails to vanish in dark areas" — yes. "I used `vec3` here because the type system expects it" — no.
- **Preferred conventions are documented in `references/code_style.md`.** Match the surrounding file's style before imposing the conventions on a new file.

If the user uploads a shader and a problem report in the same turn, read the shader first and respond to the report — don't ask which version they want or whether to make a new file.

## When to load reference files

`SKILL.md` (this file) should cover most tasks. Load a reference file only when the task genuinely needs that depth:

- **`references/isf_spec.md`** — when you need to look up an INPUT type you don't recognize, an auto-declared uniform you're unsure about, sampling-function semantics, or PASS attributes (`WIDTH`, `HEIGHT`, `MAG_FILTER`, `MIN_FILTER`, `FLOAT`, `PERSISTENT`).
- **`references/architecture_patterns.md`** — when designing a new multi-pass shader from scratch, converting a generator to a filter (or back), or building a ping-pong simulation. Has full templates.
- **`references/glsl_gotchas.md`** — when something compiles but behaves wrong, when porting between hosts (Metal vs OpenGL backends differ), or when a slider appears not to work.
- **`references/code_style.md`** — for new files where you're choosing conventions, or when the user asks for a refactor.
- **`references/arsonrivvers_technique_catalog.md`** — when designing a NEW shader or remix that should sit natively in this user's library, when hunting for technique ingredients (feedback grammars, sim architectures, control-surface patterns, host-quirk armor beyond the five below), or when judging how ambitious a build should be (complexity ladder). Distilled from a full read of all 964 AR_ shaders — the corpus's own vocabulary; prefer it over generic defaults.

## What every ISF file is made of

```glsl
/*{
  "ISFVSN": "2.0",
  "DESCRIPTION": "what this shader does",
  "CATEGORIES": ["Filter", "Generator", "Stylize", ...],
  "INPUTS": [
    {"NAME":"inputImage", "TYPE":"image"},
    {"NAME":"amount",     "TYPE":"float", "DEFAULT":0.5, "MIN":0.0, "MAX":1.0}
  ],
  "PASSES": [
    {"TARGET":"bufA", "PERSISTENT":true, "FLOAT":true},
    {}
  ]
}*/

void main() {
    vec2 uv = isf_FragNormCoord;

    if (PASSINDEX == 0) {
        // write to bufA
        gl_FragColor = ...;
        return;
    }

    // final pass — writes to host's output
    gl_FragColor = IMG_NORM_PIXEL(bufA, uv);
}
```

The header is a JSON object wrapped in `/*{ ... }*/`. The `{}` empty pass at the end of `PASSES` is the final output pass (no `TARGET`). `PASSINDEX` selects which pass `main()` is currently executing.

## The auto-declared uniforms you'll actually use

| Uniform | Type | Meaning |
|---|---|---|
| `RENDERSIZE` | `vec2` | Pixel dimensions of the **current pass** (passes can have different sizes) |
| `isf_FragNormCoord` | `vec2` | Normalized [0,1] coords, bottom-left origin. Convenience for `gl_FragCoord.xy / RENDERSIZE` |
| `gl_FragCoord` | `vec4` | Standard GLSL — `.xy` is pixel coords |
| `PASSINDEX` | `int` | Which pass is rendering (0-indexed) |
| `FRAMEINDEX` | `int` | Frame counter, 0 on the first frame, increments after each frame |
| `TIME` | `float` | Seconds since shader started, **same value across all passes in one frame** |
| `TIMEDELTA` | `float` | Seconds since last frame. **0.0 on first frame** — always guard with `max(TIMEDELTA, 1e-4)` |
| `DATE` | `vec4` | (year, month, day, seconds-into-day) |

For each image-type input named `foo`, ISF also declares `vec4 _foo_imgRect`, `vec2 _foo_imgSize`, and `bool _foo_flip` — you rarely touch these directly; use the sampling macros.

## Sampling — pick the right macro

- `IMG_NORM_PIXEL(image, vec2 normCoord)` — sample with normalized [0,1] coords. **The default for almost everything**, including persistent buffers and `inputImage`.
- `IMG_PIXEL(image, vec2 pixelCoord)` — sample with raw pixel coords. Use for pixel-accurate kernels.
- `IMG_THIS_PIXEL(image)` / `IMG_THIS_NORM_PIXEL(image)` — sample at the current fragment's location. Handy in simple feedback shaders.
- `IMG_SIZE(image)` — `vec2` size of that specific input/buffer.

`inputImage` is just a conventional name. Any input with `"TYPE":"image"` becomes a sampler in GLSL — the variable name matches the `NAME` field.

## The five things that bite hardest

These are not "best practices" — these are real failures that have happened in this user's shaders. Internalize them before writing or editing anything substantive.

### 1. No ternary operator on vector types

```glsl
// WRONG — compiles on some backends, fails on Metal/macOS
vec2 result = condition ? vecA : vecB;

// CORRECT — branch with if/else, or assign per-component
vec2 result;
if (condition) result = vecA; else result = vecB;
```

This bites hardest when porting from Shadertoy code. The ternary is *technically* legal GLSL but unreliable across ISF host backends. Always use `if/else`. Same applies to ternaries inside `mix()`, function returns, etc.

### 2. Persistent buffer self-referencing reads return *last frame's* data

When pass N writes to `bufA` and pass N also reads from `bufA`, the reads return the **previous frame's** contents, not the partial in-progress write. This is normal ISF behavior — but it means you can't read your own current-frame writes within the same pass.

If you need to read fresh values from this frame's computation, you must write them to *one* buffer and read from *another* in a subsequent pass — the ping-pong pattern. A single `PERSISTENT` buffer cannot be both source and destination of "current frame" data; it's source-of-previous and destination-of-next.

### 3. Trail accumulation: `max()` not `mix()`

```glsl
// WRONG — trails die in dark areas because mix pulls toward zero
vec4 trail = mix(prevTrail, current, decay);

// CORRECT — additive accumulation with decay floor
vec4 trail = max(prevTrail * decay, current);
```

`mix()` is interpolation — it cannot exceed both inputs. For motion trails, persistence-of-vision, glow accumulators, or anything where you want bright values to *linger*, use `max(prev * decay, current)` (decay < 1.0). For full additive: `clamp(current + prev * decay, 0.0, ceiling)`.

### 4. Loop bounds must be a compile-time constant, OR fixed + conditional break

```glsl
// WRONG — non-constant bound, fails on stricter backends
for (int i = 0; i < int(activeFolds); i++) { ... }

// CORRECT — fixed bound covering the worst case, runtime break
const int MAX_FOLDS = 7;  // slider max 4.0 + macro boost 3.0 = 7
for (int i = 0; i < MAX_FOLDS; i++) {
    if (float(i) >= activeFolds) break;
    ...
}
```

The `const int MAX_FOLDS` must literally be `const`. Pick a value that covers the worst case (slider max + any macro/conductor boosts) and break early at runtime.

### 5. `FRAMEINDEX == 0` is fragile — use `< 2`

Some hosts render the first frame more than once, or restart the frame counter on resize. Use `FRAMEINDEX < 2` (or `<= 1`) for first-frame initialization. Combine with a reset event for the canonical pattern:

```glsl
if (FRAMEINDEX < 2 || resetButton) {
    // initialize buffer
    gl_FragColor = vec4(initial_state);
    return;
}
```

## The canonical multi-pass dispatch

For any shader with more than ~2 passes, prefer this dispatch pattern in `main()` — it keeps the file readable as complexity grows:

```glsl
vec4 pass0_simulate(vec2 uv) { /* ... */ return result; }
vec4 pass1_postprocess(vec2 uv) { /* ... */ return result; }
vec3 renderFinal(vec2 uv) { /* ... */ return color; }

void main() {
    vec2 fragCoord = gl_FragCoord.xy;
    vec2 uv = fragCoord / RENDERSIZE.xy;

    if (PASSINDEX == 0) { gl_FragColor = pass0_simulate(uv);    return; }
    if (PASSINDEX == 1) { gl_FragColor = pass1_postprocess(uv); return; }

    // Final pass — no early return
    gl_FragColor = vec4(renderFinal(uv), 1.0);
}
```

For 1–2 passes the inline `if (PASSINDEX == 0) { ... }` style is fine; for 3+ passes, extract per-pass functions. Detailed templates (ping-pong, filter vs. generator, raymarched feedback) live in `references/architecture_patterns.md`.

## Filter vs. Generator — the practical distinction

- **Generator**: produces imagery from scratch. No required `inputImage`. `CATEGORIES` includes `"Generator"`. Common use: standalone visual sources.
- **Filter**: processes incoming video. Has an `inputImage` (or named equivalent like `videoSource`, `videoInput`) as the first INPUT. `CATEGORIES` includes `"Filter"`, `"Stylize"`, `"Color Effect"`, etc.

When converting a generator to a filter, the work is rarely "add an image input" — it's deciding *where in the existing logic the video should drive the system*. Treat the video as one of: a feed-rate modulator, a seed source, a color drive, a luminance mask for blending, or all of the above. Each placement gives a different artistic result. Get the user's intent before guessing.

## Frame-rate independence

If a shader runs a physical simulation (reaction-diffusion, particle flow, feedback decay), tie the update to `TIMEDELTA`, not frame count:

```glsl
float dt = max(TIMEDELTA, 1e-4);          // guard against first-frame 0.0
color += reactionRate * delta * dt * 60.0; // 60.0 normalizes to "per-second" feel
```

For simple visual effects with no physical interpretation, frame-rate dependence is fine and often desirable (the look responds to performance).

## Common INPUT types — minimum viable knowledge

| TYPE | Purpose | Required fields |
|---|---|---|
| `image` | Video / image input or buffer reference | `NAME` |
| `float` | Continuous slider | `NAME`, `DEFAULT`, `MIN`, `MAX` |
| `bool` | Toggle | `NAME`, `DEFAULT` |
| `event` | Momentary trigger (button) | `NAME` |
| `long` | Enum / popup | `NAME`, `VALUES`, `LABELS`, `DEFAULT` |
| `color` | RGBA color picker | `NAME`, `DEFAULT` (4-element array) |
| `point2D` | 2D position | `NAME`, `DEFAULT`, `MIN`, `MAX` (2-element arrays) |
| `audio` / `audioFFT` | Audio data as 1D texture — sample like an image | `NAME` |

`LABEL` is optional on every input and controls the host's UI label (defaults to `NAME`). For the full reference and edge cases, see `references/isf_spec.md`.

## Bare-minimum file to test before writing anything substantial

When the host isn't loading a shader at all (JSON parse fail, GLSL compile fail), reduce to this minimal-known-good and add complexity back incrementally:

```glsl
/*{
  "ISFVSN": "2.0",
  "DESCRIPTION": "minimal test",
  "CATEGORIES": ["Test"],
  "INPUTS": [
    {"NAME":"inputImage", "TYPE":"image"}
  ]
}*/

void main() {
    gl_FragColor = IMG_NORM_PIXEL(inputImage, isf_FragNormCoord);
}
```

If this doesn't load, the problem is host configuration, not the shader. If this loads and your real shader doesn't, bisect: comment out half the JSON inputs, half the passes, half the GLSL — repeat until the failure point is isolated. The ISF Editor's error console is the source of truth; trust its line numbers over your intuition.
