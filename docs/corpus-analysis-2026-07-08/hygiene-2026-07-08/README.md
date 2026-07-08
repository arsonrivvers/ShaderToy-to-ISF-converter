# ISF corpus hygiene backup — 2026-07-08

Durable backup of the 5 broken/dead files flagged during the 2026-07-08 corpus analysis.
Source library: `/Library/Graphics/ISF` (no git there — this is the restore path).

## Layout
- `originals/` — the **pre-edit** files, exactly as they were before any change (6 files, incl. the two deleted below).
- `fixed/` — the **edited** state of the 4 shaders that were repaired in place.

## What changed

| File | Fix applied (in `fixed/`) |
|---|---|
| `AR_MeltingCam1_HallofMirrors.fs` | INPUT names `PressureScale`/`FluidIntensity`/`BlendStrength` → camelCase to match the GLSL body (were undeclared-identifier compile errors). |
| `ArsonRivvers_Kick_Neon_alt.fs` | Local `vec4 sample` → `trailAccum` (decl + 2 uses); `sample` is a reserved word and dies on Metal. |
| `AR_SeparationGlitch_v02.fs` | 3× `texture(sTD2DInputs[0], …)` → `IMG_NORM_PIXEL(inputImage, …)` (TouchDesigner sampler doesn't exist in ISF); removed the redundant `uniform float …` block that collides with ISF's auto-declared uniforms on Metal. |
| `ArsonRivvers_ImpoShapeDistortion.fs` | Header was transplanted (declared torus/knot inputs + an unused 2-pass feedback buffer). Rewrote INPUTS + DESCRIPTION to the actual fractal-kaleidoscope body (`distortionMix`, `complexity`, `symmetry`, `shape` popup, `rotationSpeed`, `zoomSpeed`) and made it single-pass. Slider ranges are sensible defaults — tune on-device. |

## Deleted from the library (originals preserved here)
- `AR_Horizontal-Line_grid_remix_v01.fs` — was 0 bytes (empty).
- `ArsonRivvers_Kick_Neon_alt` (no extension) — byte-identical duplicate of the `.fs`; can't load without the extension.

## Status
STAGED — the 4 fixes are statically verified (valid JSON headers, blockers removed, identifier↔INPUT
parity) but NOT yet confirmed rendering in VDMX/ISF Editor. GLSL→Metal wasn't compilable at edit time.

## Restore
```bash
# revert a shader to its original (broken) state:
cp docs/corpus-analysis-2026-07-08/hygiene-2026-07-08/originals/<file> /Library/Graphics/ISF/<file>

# re-apply a fix if the library copy is lost/overwritten:
cp docs/corpus-analysis-2026-07-08/hygiene-2026-07-08/fixed/<file> /Library/Graphics/ISF/<file>

# restore a deleted file:
cp docs/corpus-analysis-2026-07-08/hygiene-2026-07-08/originals/AR_Horizontal-Line_grid_remix_v01.fs /Library/Graphics/ISF/
```
