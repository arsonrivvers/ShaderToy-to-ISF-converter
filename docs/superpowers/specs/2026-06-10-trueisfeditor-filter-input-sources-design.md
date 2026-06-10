# TrueISFEditor — Filter Input Sources (Option A)

**Date:** 2026-06-10
**Status:** Design — pending user review → writing-plans
**Sub-project:** A of a two-part track (A = filter input sources; B = INPUT authoring GUI, next session)

## 1. Summary

Make **filter** ISF shaders first-class in the editor by feeding their image inputs a real
source. Today the native Metal preview only renders generators; any `image`-type INPUT is
dropped from the controls and nothing is bound to it, so a filter shader previews as black /
garbage. This sub-project adds a per-image-input **source picker** with three source types:

1. **Test pattern** — a bundled set of industry-standard patterns (with motion), each
   implemented as a small ISF generator.
2. **Camera** — live webcam via `AVCaptureSession`.
3. **Shader from library** — another ISF (generator) from the user's library, rendered to a
   texture and chained in (the ISF-Editor / VDMX move).

The underlying renderer (ISFMSLKit) already supports all of this; the work is entirely in
TrueISFEditor's own preview layer.

## 2. Motivation & prior art

The sibling project `VJ_Code-crossfade` (`crossfade_codex/apps/syphon-offspring-shell/`)
demonstrates the canonical ISFMSLKit-native pattern for loading `.fs` files and feeding them
image inputs without ever propagating errors. Three patterns we adopt directly:

- **Probe-frame validation + failure isolation** — build a *candidate* `ISFMSLScene`, render
  one frame at `t=0`, check `compilerError` **and** a non-nil texture, and only then swap it in;
  keep the last-good scene on failure.
- **Filter / image-input detection** — read `isFilterInputImage` / `shouldHaveImageBuffer` /
  `type == ISFValType_Image` off each `ISFMSLSceneAttrib`.
- **Image-input binding & shader chaining** — bind a texture with
  `ISFMSLSceneVal.createWithTexture:`; render one scene to a texture and feed it into another.

### Verified API surface (from vendored headers, 2026-06-10)
- `ISFMSLSceneVal`: `+ createWithTexture:(id<MTLTexture>)` and `+ createWithTextureImage:`.
- `ISFMSLSceneAttrib`: `shouldHaveImageBuffer`, `isFilterInputImage`, `isTransProgressFloat`.
- `ISFMSLScene`: `createAndRenderToTextureSized:atTime:inCommandBuffer:` (chaining).

## 3. Goals / Non-goals

**Goals**
- Per-image-input source routing: each image input on the edited filter chooses its own source.
- Three source types for v1: test pattern, camera, shader-from-library.
- A v1 test-pattern set with motion: SMPTE color bars, grayscale ramp/staircase, scrolling
  checkerboard, crosshatch grid, animated zone plate, hue-sweep gradient, bouncing-box motion
  test, solid utility fields (white / black / 50% gray / R / G / B).
- Never black-screen the filter preview: probe-frame validation + keep-last-good everywhere.
- Multi-image filters (transitions, blends) are fully feedable.

**Non-goals (deferred)**
- Still-image / movie-file sources (new `ImageSource` conformer later).
- Persisting source routing across sessions (in-memory only for v1; ISF has no slot for it —
  a sidecar layer can come later).
- Audio / AudioFFT inputs.
- INPUT authoring GUI (that is sub-project B).
- Recursive chaining beyond one level (see nesting rule, §6).

## 4. Architecture

A single new seam — the `ImageSource` protocol — that the preview controller pulls from each
frame. Everything else is a conformer or a small coordinator.

```
PreviewControlsView (image-input case → source picker)
        │ selects
        ▼
SourceRouter  ──  [imageInputName : ImageSource]
        │ owned by
        ▼
MetalPreviewController.draw(in:)
        │ per image input, per frame:
        │   tex = source.texture(atTime:size:in: commandBuffer)
        │   scene.setValue(.createWithTexture(tex), forInputNamed: name)
        ▼
   ISFMSLScene (the edited filter)  → blit → drawable
```

### Units

- **`ImageSource` (protocol)** — `var displayName: String { get }` and
  `func texture(atTime t: TimeInterval, size: MTLSize, in cb: MTLCommandBuffer) -> MTLTexture?`.
  The dependency seam; a fake conformer returning a known texture drives all unit tests with no
  GPU/camera.
- **`ISFSceneSource: ImageSource`** — wraps a second `ISFMSLScene` loaded from a `.fs` URL.
  Powers **both** test patterns and library-shader chaining (only the file differs). Renders into
  the caller's command buffer via the existing `ISFMSLSafeRender` bridge. Probe-frame validated;
  keeps last-good texture on a failed reload. Nesting rule applies (§6).
- **`CameraSource: ImageSource`** — `AVCaptureSession` (front/default device) →
  `CVMetalTextureCache` → `MTLTexture`. Requests camera permission; on denial yields nil so the
  router falls back to the default test pattern. Returns the most recent captured frame each call.
- **`NoneSource: ImageSource`** — yields nil (filter input sees transparent/black). Default for an
  unrouted image input.
- **`TestPatternCatalog`** — enumerates the bundled pattern `.fs` files with display names; vends
  an `ISFSceneSource` for a chosen pattern. Lives in `ShadertoyISFKit` (pure, testable) with the
  `.fs` resources bundled in the app target. Exposes a **`default` pattern = SMPTE color bars**,
  used wherever a fallback source is needed (camera-denied, nesting rule).
- **`SourceRouter`** — `ObservableObject` owning `[inputName: ImageSource]`. Rebuilt when the
  edited shader's image-input set changes; exposes `setSource(_:for:)` for the picker.

### Changes to existing code
- **`MetalPreviewController.mapInputs`** — stop returning `nil` for `.image`; emit a new
  `ISFPreviewInput` of type `"image"`. Surface, per shader, whether it is a filter (any input with
  `isFilterInputImage`).
- **`MetalPreviewController.draw(in:)`** — before rendering the filter, iterate its image inputs
  and bind each routed source's texture (sized to the render target) into the same command buffer.
- **`ISFPreviewInput`** — already lists `"image"` in its type doc; add nothing structural.
- **`PreviewControlsView`** — replace the dead-text `image` fallthrough with a source picker:
  `None / Test Pattern ▸ (catalog submenu) / Camera / Shader ▸ (library submenu)`.

## 5. Data flow (per frame)

1. `draw(in:)` obtains the edited filter `scene` and target `size`.
2. For each image input `name` on `scene`: `tex = router.source(name).texture(atTime:size:in: cb)`.
   - `ISFSceneSource` renders its wrapped scene into `cb` at the current time and returns the texture.
   - `CameraSource` returns the latest captured frame's Metal texture (no render needed).
   - nil → input left unbound (engine default / black).
3. `scene.setValue(ISFMSLSceneVal.createWithTexture(tex), forInputNamed: name)` for each non-nil.
4. Render the filter into `cb` (existing `ISFMSLSafeRender`), blit to the drawable, present, commit.

All source scenes share the filter's command buffer, exactly as the crossfade shell does, so the
whole frame is one commit.

## 6. Error handling & edge cases

- **Probe-frame validation** — `ISFSceneSource` renders one frame on load; if `compilerError` or
  nil texture, the load fails and the prior good source (or the default test pattern) stays. No
  partial swap, no black screen.
- **Camera denied / unavailable** — `CameraSource` yields nil; router falls back to the default
  test pattern and posts a status note. No crash, no permission loop.
- **Mid-stream source failure** — a scene source that throws mid-render keeps its last-good texture
  and logs; the filter keeps previewing.
- **Nesting rule** — if a *library-shader source* is itself a filter (has image inputs), it is fed
  the **default test pattern** for those inputs. One level only; no recursion, no cycles.
- **Generator being edited (not a filter)** — no image inputs → no source pickers shown; behavior
  identical to today.
- **Resolution** — sources render/scale to the filter's current render-target size; camera frames
  are sampled at capture resolution and bound directly (ISF samples in normalized coords).

## 7. Testing strategy

- **`ShadertoyISFKit` unit tests**
  - `TestPatternCatalog`: every bundled pattern `.fs` parses and probe-renders a **non-black**
    texture (guards against a broken bundled shader shipping).
  - `SourceRouter`: routing map rebuilds correctly when the image-input set changes; `setSource`
    updates the right key; defaults to `NoneSource`.
- **App-model tests** with a fake `ImageSource` (known solid-color texture): `MetalPreviewController`
  binds the fake's texture to the right input name; multi-input routing binds each independently.
- **No live camera / live subscription in tests** — `CameraSource` is exercised only on-device.
- **On-device gate (user)** — camera feed renders through a filter; library-shader chaining renders;
  switching sources is live and reversible; no black screen on a bad source. Filed as an action item
  (native app — no automated UI path).

## 8. Build order (sliced; verify on-device between slices)

Per the project's render-path discipline — one change at a time, confirm acceptable before the next:

1. **Slice 1 — Test-pattern source end-to-end.** `ImageSource`, `ISFSceneSource`, `TestPatternCatalog`
   (full pattern set), `SourceRouter`, `mapInputs` change, `draw` binding, `PreviewControlsView`
   picker (Test Pattern + None). Proves the entire image-input pipeline. On-device: a filter
   previews against a moving test pattern.
2. **Slice 2 — Library-shader chaining.** Add the `Shader ▸` library source to the picker (reuses
   `ISFSceneSource`); nesting rule. On-device: a filter processes another library shader live.
3. **Slice 3 — Camera.** `CameraSource` + permission handling + the `Camera` picker entry. On-device:
   a filter processes the webcam.

Same end state as building all at once; no black-screen stacking.

## 9. Open questions

- None blocking. (Sizing/aspect handling for non-square camera frames will be tuned on-device in
  Slice 3; default is bind-at-capture-res and let ISF normalized sampling handle it.)
