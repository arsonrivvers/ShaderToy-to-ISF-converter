# ISFMSLKit — real API (verified from vendored headers, 2026-06-09)

Captured from `vendor/prebuilt/ISFMSLKit.framework/Headers/` + `VVMetalKit.framework/Headers/`.
**Use these exact symbols** — they differ from the skill-draft guesses. Swift names shown.

## Setup (once, on the main controller)
```swift
let props = RenderProperties.global()          // VVMetalKit; auto-creates MTLCreateSystemDefaultDevice()
let device = props.device                       // id<MTLDevice>
let renderQueue = props.renderQueue             // id<MTLCommandQueue>  (use this; no need to make our own)
VVMTLPool.global = VVMTLPool(device: device)    // REQUIRED before rendering (scene uses the pool)
ISFMSLCache.primary = ISFMSLCache(directoryURL: cacheDir)   // initWithDirectoryURL:
```
`cacheDir`: `~/Library/Application Support/TrueISFEditor/ISFMSLCache` (create it first).

## Scene lifecycle
```swift
let scene = ISFMSLScene(device: device)         // initWithDevice:
scene.loadURL(url)                               // URL ONLY — no string-load. Write source to a temp .fs, load that.
// scene.loadURL(url, resetTimer: true)          // variant that resets the time uniform
let hadError = scene.compilerError               // BOOL (NOT an error object!)
let attribs = scene.inputs                        // [ISFMSLSceneAttrib]
scene.setValue(val, forInputNamed: name)          // val is id<ISFMSLSceneVal>
```

## Compile error detail (compilerError is just a BOOL)
To get the message + line, build a transpiler-error object for the same URL:
```swift
if scene.compilerError {
    let te = ISFMSLTranspilerError(url: url, device: device)   // createWithURL:device: / initWithURL:device:
    // ISF compile errors are almost always GLSL->SPIR-V on the fragment stage:
    let msg = te.fragGLSLErrString ?? te.fragSPIRVErrString ?? te.fragMSLErrString
           ?? te.vertGLSLErrString ?? te.generateStringForLogFile()
    // Line: parse "ERROR: 0:NN:" out of msg (glslang format). te also has
    // .glslFragSrcWithLineNumbers for display if useful.
}
```
Flags to pick the right string: `fragGLSLErrFlag`, `fragSPIRVErrFlag`, `fragMSLErrFlag`, `vert*ErrFlag`.

## Render
```swift
// Returns id<VVMTLTextureImage>, NOT a result wrapper.
let img = scene.createAndRenderToTextureSized(size, inCommandBuffer: cb)   // NSSize, MTLCommandBuffer
// atTime: variant for deterministic time:
// scene.createAndRenderToTextureSized(size, atTime: t, inCommandBuffer: cb)
let texture: MTLTexture = img.texture            // VVMTLTextureImage.texture (strong, readwrite)
```
`VVMTLPool` also vends scratch textures if needed: `VVMTLPool.global.bgra8TexSized(size)` → `VVMTLTextureImage`.

## Inputs — ISFMSLSceneAttrib
```swift
attrib.name        // String
attrib.label       // String
attrib.type        // ISFValType
attrib.currentVal  // id<ISFMSLSceneVal>  -> read .doubleValue / .boolValue / .point2DVal / .colorValueByIndex(i)
attrib.minVal      // id<ISFMSLSceneVal>
attrib.maxVal      // id<ISFMSLSceneVal>
attrib.defaultVal  // id<ISFMSLSceneVal>
attrib.labelArray  // [String]   (long enum display names)
attrib.valArray    // [NSNumber] (long enum underlying values)
```

## ISFValType (exact raw values — None is 0, so the visible types are 1..6)
```
None=0, Event=1, Bool=2, Long=3, Float=4, Point2D=5, Color=6, Cube=7, Image=8, Audio=9, AudioFFT=10
```
Prefer the named Swift cases (`.event`, `.bool`, `.long`, `.float`, `.point2D`, `.color`) over raw ints.
Map 1..6 to our `ISFPreviewInput.type` strings; treat 7..10 (image/audio/cube) as unsupported-in-controls (default branch) for P1.5.

## ISFMSLSceneVal — constructing values for setValue
```swift
ISFMSLSceneVal.createWithFloat(d)        // double
ISFMSLSceneVal.createWithBool(b)
ISFMSLSceneVal.createWithLong(i)         // Int32
ISFMSLSceneVal.createWithPoint2D(p)      // NSPoint
ISFMSLSceneVal.createWithColor(nscolor)  // NSColor
ISFMSLSceneVal.createWithColorVals(ptr)  // double* RGBA
ISFMSLSceneVal.createWithEvent()
```
Read back: `.doubleValue`, `.boolValue`, `.longValue`, `.point2DVal`, `.colorValueByIndex(i)`, `.type`.

## Gotchas
- `loadURL:` is URL-only → keep a stable temp `.fs` per controller; rewrite + reload on each recompile.
- Set `VVMTLPool.global` and `ISFMSLCache.primary` BEFORE first render or you'll crash/misrender.
- The nested transpiler dylibs (libGLSLangValidatorLib/libSPIRVCrossLib/libISFGLSLGenerator) live inside
  `ISFMSLKit.framework/.../Frameworks/` and are ad-hoc signed — embedding ISFMSLKit.framework carries them.
- `compilerError` reflects the CURRENTLY loaded URL; build the `ISFMSLTranspilerError` against the SAME temp URL.
