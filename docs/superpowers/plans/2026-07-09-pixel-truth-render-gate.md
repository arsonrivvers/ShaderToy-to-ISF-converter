# Pixel-Truth Render Gate Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A compile-clean shader that renders black/NaN/static becomes visible to the corpus harness, the ISF-library acceptance test, and the import report.

**Architecture:** A crash-safe `atTime:` render bridge + a pure byte-level frame analyzer + a pure verdict function, orchestrated by `MetalPreviewController.runPixelGate()` (3 offscreen frames at t=0/0.5/1.5, 320×180, deterministic test pattern bound to image inputs, CPU readback via blit). Three thin surface integrations consume the verdict.

**Tech Stack:** Swift (app target), Obj-C++ (safe bridge), Metal, ISFMSLKit (vendored), XCTest.

**Spec:** `docs/superpowers/specs/2026-07-09-pixel-truth-render-gate-design.md` (approved 2026-07-09).

## Global Constraints

- **Never `git add -A` in this repo** (concurrent sessions edit `App/`) — stage explicit paths only.
- TDD: test first, watch it fail, minimal implementation, watch it pass, commit.
- App tests: `cd App && xcodegen generate && xcodebuild test -project TrueISFEditor.xcodeproj -scheme TrueISFEditor -destination 'platform=macOS,arch=arm64' -derivedDataPath ./ddata 2>&1 | grep -E "Executed|TEST (SUCCEEDED|FAILED)" | tail -5`
- Run `xcodegen generate` in `App/` after adding any new file (project.yml globs).
- FAIL set = {BLACK, NAN, RENDER-ERR}; WARN set = {STATIC, UNSUPPORTED}; black luma floor = 2/255; frames at t = 0.0, 0.5, 1.5; gate size 320×180; pattern 64×64 bgra8.
- The compile pass-list of the discovery corpus must be unchanged by this work (the gate adds information; it must not disturb compilation).

---

### Task 1: `FramePixelStats` — pure byte-level frame analyzer

**Files:**
- Create: `App/TrueISFEditor/FramePixelStats.swift`
- Test: `App/TrueISFEditorTests/FramePixelStatsTests.swift`

**Interfaces:**
- Produces: `struct FramePixelStats { let maxLuma: Double; let nanCount: Int; let isConstant: Bool; let digest: UInt64 }`, `static func supports(_ format: MTLPixelFormat) -> Bool`, `static func analyze(bytes: [UInt8], format: MTLPixelFormat, width: Int, height: Int) -> FramePixelStats?`, `static func analyze(texture: MTLTexture) -> FramePixelStats?` (Task 4 calls the texture variant; Task 2 consumes the struct).

- [ ] **Step 1: Write the failing tests**

```swift
// App/TrueISFEditorTests/FramePixelStatsTests.swift
import XCTest
import Metal
@testable import TrueISFEditor

final class FramePixelStatsTests: XCTestCase {
    // 2×1 helpers
    private func bgra8(_ pixels: [[UInt8]]) -> [UInt8] { pixels.flatMap { $0 } }

    func testBlackFrameBGRA8() {
        let bytes = bgra8([[0, 0, 0, 255], [0, 0, 0, 255]])
        let s = FramePixelStats.analyze(bytes: bytes, format: .bgra8Unorm, width: 2, height: 1)
        XCTAssertNotNil(s)
        XCTAssertEqual(s!.maxLuma, 0)
        XCTAssertEqual(s!.nanCount, 0)
        XCTAssertTrue(s!.isConstant)
    }

    func testBGRAChannelOrderLuma() {
        // Pure red in BGRA byte order: [B,G,R,A] = [0,0,255,255]. Alpha must NOT count as luma.
        let bytes = bgra8([[0, 0, 255, 255], [0, 0, 0, 0]])
        let s = FramePixelStats.analyze(bytes: bytes, format: .bgra8Unorm, width: 2, height: 1)!
        XCTAssertEqual(s.maxLuma, 1.0, accuracy: 0.001)
        XCTAssertFalse(s.isConstant)
    }

    func testAlphaOnlyPixelIsBlack() {
        // Opaque but zero RGB: alpha alone must not lift maxLuma above the black floor.
        let bytes = bgra8([[0, 0, 0, 255]])
        let s = FramePixelStats.analyze(bytes: bytes, format: .bgra8Unorm, width: 1, height: 1)!
        XCTAssertEqual(s.maxLuma, 0)
    }

    func testNaNAndInfDetectedRGBA32Float() {
        var floats: [Float] = [Float.nan, 0, 0, 1,   0, Float.infinity, 0, 1]
        let bytes = floats.withUnsafeBytes { Array($0) }
        let s = FramePixelStats.analyze(bytes: bytes, format: .rgba32Float, width: 2, height: 1)!
        XCTAssertEqual(s.nanCount, 2)
    }

    func testRGBA16FloatLumaAndNaN() {
        var halves: [Float16] = [Float16(0.5), 0, 0, 1,   Float16.nan, 0, 0, 1]
        let bytes = halves.withUnsafeBytes { Array($0) }
        let s = FramePixelStats.analyze(bytes: bytes, format: .rgba16Float, width: 2, height: 1)!
        XCTAssertEqual(s.maxLuma, 0.5, accuracy: 0.001)
        XCTAssertEqual(s.nanCount, 1)
    }

    func testConstantColorNonBlack() {
        let bytes = bgra8([[10, 200, 30, 255], [10, 200, 30, 255]])
        let s = FramePixelStats.analyze(bytes: bytes, format: .bgra8Unorm, width: 2, height: 1)!
        XCTAssertTrue(s.isConstant)
        XCTAssertGreaterThan(s.maxLuma, 0.5)
    }

    func testDigestsDifferForDifferentFrames() {
        let a = FramePixelStats.analyze(bytes: bgra8([[1, 2, 3, 255]]), format: .bgra8Unorm, width: 1, height: 1)!
        let b = FramePixelStats.analyze(bytes: bgra8([[3, 2, 1, 255]]), format: .bgra8Unorm, width: 1, height: 1)!
        XCTAssertNotEqual(a.digest, b.digest)
        let a2 = FramePixelStats.analyze(bytes: bgra8([[1, 2, 3, 255]]), format: .bgra8Unorm, width: 1, height: 1)!
        XCTAssertEqual(a.digest, a2.digest)
    }

    func testUnsupportedFormatReturnsNil() {
        XCTAssertFalse(FramePixelStats.supports(.depth32Float))
        XCTAssertNil(FramePixelStats.analyze(bytes: [0, 0, 0, 0], format: .depth32Float, width: 1, height: 1))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd App && xcodegen generate && xcodebuild test -project TrueISFEditor.xcodeproj -scheme TrueISFEditor -destination 'platform=macOS,arch=arm64' -derivedDataPath ./ddata -only-testing:TrueISFEditorTests/FramePixelStatsTests 2>&1 | tail -5`
Expected: build FAILURE — `cannot find 'FramePixelStats' in scope`.

- [ ] **Step 3: Write the implementation**

```swift
// App/TrueISFEditor/FramePixelStats.swift
import Metal

/// Per-frame pixel statistics for the pixel-truth render gate. The byte-level `analyze` is pure —
/// unit tests feed synthetic frames with no GPU. See
/// docs/superpowers/specs/2026-07-09-pixel-truth-render-gate-design.md.
struct FramePixelStats: Equatable {
    /// Max over pixels of max(R,G,B) (alpha excluded), normalized 0–1. NaN/Inf components are
    /// excluded here — they are counted separately in `nanCount`.
    let maxLuma: Double
    /// NaN/Inf color-component count (float formats only; always 0 for 8-bit).
    let nanCount: Int
    /// True when every pixel's raw bytes equal the first pixel's.
    let isConstant: Bool
    /// FNV-1a 64 hash of the raw bytes, for cross-frame comparison.
    let digest: UInt64

    /// Formats the analyzer understands (mirrors TextureSnapshot's supported set).
    static func supports(_ format: MTLPixelFormat) -> Bool {
        switch format {
        case .bgra8Unorm, .bgra8Unorm_srgb, .rgba8Unorm, .rgba8Unorm_srgb,
             .rgba16Float, .rgba32Float:
            return true
        default:
            return false
        }
    }

    private static func bytesPerPixel(_ format: MTLPixelFormat) -> Int {
        switch format {
        case .rgba32Float: return 16
        case .rgba16Float: return 8
        default: return 4
        }
    }

    /// Reads a CPU-accessible texture back and analyzes it. The caller must have committed and
    /// waited on the command buffer that produced it (the gate blits into a readback texture
    /// first — pool textures aren't guaranteed CPU-readable).
    static func analyze(texture: MTLTexture) -> FramePixelStats? {
        guard supports(texture.pixelFormat) else { return nil }
        let w = texture.width, h = texture.height
        let bytesPerRow = w * bytesPerPixel(texture.pixelFormat)
        var bytes = [UInt8](repeating: 0, count: bytesPerRow * h)
        bytes.withUnsafeMutableBytes {
            texture.getBytes($0.baseAddress!, bytesPerRow: bytesPerRow,
                             from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0)
        }
        return analyze(bytes: bytes, format: texture.pixelFormat, width: w, height: h)
    }

    /// Pure byte-level analysis. `bytes` is tightly packed (bytesPerRow == width × bpp).
    static func analyze(bytes: [UInt8], format: MTLPixelFormat,
                        width: Int, height: Int) -> FramePixelStats? {
        guard supports(format) else { return nil }
        let bpp = bytesPerPixel(format)
        let pixelCount = width * height
        guard bytes.count >= pixelCount * bpp, pixelCount > 0 else { return nil }

        var maxLuma = 0.0
        var nanCount = 0
        var isConstant = true
        var digest: UInt64 = 0xcbf29ce484222325            // FNV-1a offset basis
        for byte in bytes[..<(pixelCount * bpp)] {
            digest = (digest ^ UInt64(byte)) &* 0x100000001b3
        }

        // RGB component byte offsets within one pixel (alpha excluded from luma).
        let rgbOffsets: [Int]
        switch format {
        case .bgra8Unorm, .bgra8Unorm_srgb: rgbOffsets = [2, 1, 0]
        default: rgbOffsets = [0, 1, 2]                    // rgba8 / rgba16F / rgba32F
        }

        bytes.withUnsafeBytes { raw in
            for p in 0..<pixelCount {
                let base = p * bpp
                if isConstant && p > 0 {
                    for i in 0..<bpp where raw[base + i] != raw[i] { isConstant = false; break }
                }
                switch format {
                case .rgba32Float:
                    for c in 0..<4 {
                        let v = raw.loadUnaligned(fromByteOffset: base + c * 4, as: Float.self)
                        if !v.isFinite { nanCount += 1 }
                        else if c < 3 { maxLuma = max(maxLuma, Double(v)) }
                    }
                case .rgba16Float:
                    for c in 0..<4 {
                        let v = raw.loadUnaligned(fromByteOffset: base + c * 2, as: Float16.self)
                        if !v.isFinite { nanCount += 1 }
                        else if c < 3 { maxLuma = max(maxLuma, Double(v)) }
                    }
                default:
                    for off in rgbOffsets {
                        maxLuma = max(maxLuma, Double(raw[base + off]) / 255.0)
                    }
                }
            }
        }
        return FramePixelStats(maxLuma: maxLuma, nanCount: nanCount,
                               isConstant: isConstant, digest: digest)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: same command as Step 2. Expected: `TEST SUCCEEDED`, 8 tests pass.

- [ ] **Step 5: Commit**

```bash
git add App/TrueISFEditor/FramePixelStats.swift App/TrueISFEditorTests/FramePixelStatsTests.swift
git commit -m "feat(gate): FramePixelStats — pure byte-level frame analyzer (Task 3.1)"
```

---

### Task 2: `PixelGate` — verdict + import-outcome mapping

**Files:**
- Create: `App/TrueISFEditor/PixelGate.swift`
- Test: `App/TrueISFEditorTests/PixelGateTests.swift`

**Interfaces:**
- Consumes: `FramePixelStats` (Task 1), `ImportEvent.Outcome` (existing).
- Produces: `enum PixelVerdict: String { case ok = "OK", black = "BLACK", nan = "NAN", constant = "STATIC", renderError = "RENDER-ERR", unsupported = "UNSUPPORTED" }` with `var isFail: Bool`; `PixelGate.verdict(_ frames: [FramePixelStats?]) -> PixelVerdict`; `PixelGate.importOutcome(_ v: PixelVerdict) -> (outcome: ImportEvent.Outcome, message: String)?`.

- [ ] **Step 1: Write the failing tests**

```swift
// App/TrueISFEditorTests/PixelGateTests.swift
import XCTest
@testable import TrueISFEditor

final class PixelGateTests: XCTestCase {
    private func stats(luma: Double = 0.8, nan: Int = 0, constant: Bool = false,
                       digest: UInt64 = 1) -> FramePixelStats {
        FramePixelStats(maxLuma: luma, nanCount: nan, isConstant: constant, digest: digest)
    }

    func testEmptyOrNilFrameIsRenderError() {
        XCTAssertEqual(PixelGate.verdict([]), .renderError)
        XCTAssertEqual(PixelGate.verdict([stats(), nil, stats()]), .renderError)
    }

    func testNaNBeatsBlack() {
        let black = stats(luma: 0, nan: 1, digest: 2)
        XCTAssertEqual(PixelGate.verdict([black, black, black]), .nan)
    }

    func testAllFramesBlackIsBlack() {
        let f = stats(luma: 0.001, digest: 3)
        XCTAssertEqual(PixelGate.verdict([f, f, f]), .black)
    }

    func testFadeInIsNotBlack() {
        // Black only at t=0, lit and changing afterwards → OK.
        let v = PixelGate.verdict([stats(luma: 0, digest: 1),
                                   stats(luma: 0.5, digest: 2),
                                   stats(luma: 0.9, digest: 3)])
        XCTAssertEqual(v, .ok)
    }

    func testEqualDigestsIsStatic() {
        let f = stats(digest: 7)
        XCTAssertEqual(PixelGate.verdict([f, f, f]), .constant)
    }

    func testDifferentDigestsIsOK() {
        XCTAssertEqual(PixelGate.verdict([stats(digest: 1), stats(digest: 2), stats(digest: 3)]), .ok)
    }

    func testFailSet() {
        XCTAssertTrue(PixelVerdict.black.isFail)
        XCTAssertTrue(PixelVerdict.nan.isFail)
        XCTAssertTrue(PixelVerdict.renderError.isFail)
        XCTAssertFalse(PixelVerdict.ok.isFail)
        XCTAssertFalse(PixelVerdict.constant.isFail)
        XCTAssertFalse(PixelVerdict.unsupported.isFail)
    }

    func testImportOutcomeMapping() {
        XCTAssertNil(PixelGate.importOutcome(.ok))
        XCTAssertEqual(PixelGate.importOutcome(.constant)?.outcome, .warning)
        XCTAssertEqual(PixelGate.importOutcome(.unsupported)?.outcome, .warning)
        XCTAssertEqual(PixelGate.importOutcome(.black)?.outcome, .error)
        XCTAssertEqual(PixelGate.importOutcome(.nan)?.outcome, .error)
        XCTAssertEqual(PixelGate.importOutcome(.renderError)?.outcome, .error)
        XCTAssertTrue(PixelGate.importOutcome(.black)!.message.contains("BLACK"))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd App && xcodegen generate && xcodebuild test -project TrueISFEditor.xcodeproj -scheme TrueISFEditor -destination 'platform=macOS,arch=arm64' -derivedDataPath ./ddata -only-testing:TrueISFEditorTests/PixelGateTests 2>&1 | tail -5`
Expected: build FAILURE — `cannot find 'PixelGate' in scope`.

- [ ] **Step 3: Write the implementation**

```swift
// App/TrueISFEditor/PixelGate.swift
import Foundation

/// Outcome of the pixel-truth render gate for one shader.
/// FAIL set blocks the corpus pass-list; WARN set is reported only.
enum PixelVerdict: String {
    case ok = "OK"
    case black = "BLACK"                // all frames under the luma floor
    case nan = "NAN"                    // any NaN/Inf component in any frame
    case constant = "STATIC"            // renders, but no frame ever changes (WARN)
    case renderError = "RENDER-ERR"     // threw or produced no readable frame
    case unsupported = "UNSUPPORTED"    // engine output format not analyzable (WARN)

    var isFail: Bool { self == .black || self == .nan || self == .renderError }
}

enum PixelGate {
    /// Luma floor under which a frame counts as black.
    static let blackLumaFloor = 2.0 / 255.0

    /// Maps the analyzed frames to a verdict. Precedence: render-err > nan > black > static > ok.
    /// `nil` entries mean a frame failed to render/read back.
    static func verdict(_ frames: [FramePixelStats?]) -> PixelVerdict {
        let stats = frames.compactMap { $0 }
        guard !frames.isEmpty, stats.count == frames.count else { return .renderError }
        if stats.contains(where: { $0.nanCount > 0 }) { return .nan }
        if stats.allSatisfy({ $0.maxLuma < blackLumaFloor }) { return .black }
        if Set(stats.map(\.digest)).count == 1 { return .constant }
        return .ok
    }

    /// ImportLog mapping (spec §C): OK records nothing; WARN set → .warning; FAIL set → .error.
    static func importOutcome(_ v: PixelVerdict) -> (outcome: ImportEvent.Outcome, message: String)? {
        switch v {
        case .ok:
            return nil
        case .constant:
            return (.warning, "pixel gate: STATIC — renders, but no frame ever changes")
        case .unsupported:
            return (.warning, "pixel gate: UNSUPPORTED — engine output format not analyzable")
        case .black:
            return (.error, "pixel gate: BLACK — compiled but renders black")
        case .nan:
            return (.error, "pixel gate: NAN — compiled but renders NaN/Inf pixels")
        case .renderError:
            return (.error, "pixel gate: RENDER-ERR — compiled but failed at render time")
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: same command as Step 2. Expected: `TEST SUCCEEDED`, 8 tests pass.

- [ ] **Step 5: Commit**

```bash
git add App/TrueISFEditor/PixelGate.swift App/TrueISFEditorTests/PixelGateTests.swift
git commit -m "feat(gate): PixelVerdict + PixelGate verdict/import-outcome mapping"
```

---

### Task 3: `ISFMSLSafeRenderAtTime` bridge + `GateInputPattern`

**Files:**
- Modify: `App/TrueISFEditor/ISFMSLSafeBridge.h` (add declaration), `App/TrueISFEditor/ISFMSLSafeBridge.mm` (add function)
- Create: `App/TrueISFEditor/GateInputPattern.swift`
- Test: `App/TrueISFEditorTests/GateInputPatternTests.swift` (bridge itself is exercised by Task 4's GPU tests)

**Interfaces:**
- Produces: `ISFMSLSafeRenderAtTime(scene, size, time, cb, &err) -> id<MTLTexture> _Nullable`; `GateInputPattern.size == 64`, `GateInputPattern.bytes() -> [UInt8]` (bgra8, 64×64), `GateInputPattern.makeTexture(device:) -> MTLTexture?`.

- [ ] **Step 1: Write the failing tests**

```swift
// App/TrueISFEditorTests/GateInputPatternTests.swift
import XCTest
import Metal
@testable import TrueISFEditor

final class GateInputPatternTests: XCTestCase {
    func testBytesDeterministicNonBlackNonConstant() {
        let a = GateInputPattern.bytes()
        let b = GateInputPattern.bytes()
        XCTAssertEqual(a, b, "pattern must be identical every run — the pass-list is a baseline")
        let s = FramePixelStats.analyze(bytes: a, format: .bgra8Unorm,
                                        width: GateInputPattern.size, height: GateInputPattern.size)!
        XCTAssertGreaterThan(s.maxLuma, 0.5, "pattern must be clearly non-black")
        XCTAssertFalse(s.isConstant, "pattern must vary spatially to exercise sampling")
    }

    func testMakeTextureUploadsPattern() throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let tex = try XCTUnwrap(GateInputPattern.makeTexture(device: device))
        XCTAssertEqual(tex.width, GateInputPattern.size)
        XCTAssertEqual(tex.pixelFormat, .bgra8Unorm)
        let s = try XCTUnwrap(FramePixelStats.analyze(texture: tex))
        XCTAssertGreaterThan(s.maxLuma, 0.5)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd App && xcodegen generate && xcodebuild test -project TrueISFEditor.xcodeproj -scheme TrueISFEditor -destination 'platform=macOS,arch=arm64' -derivedDataPath ./ddata -only-testing:TrueISFEditorTests/GateInputPatternTests 2>&1 | tail -5`
Expected: build FAILURE — `cannot find 'GateInputPattern' in scope`.

- [ ] **Step 3: Implement `GateInputPattern`**

```swift
// App/TrueISFEditor/GateInputPattern.swift
import Metal

/// Deterministic 64×64 bgra8 texture bound to every image input before a pixel-gate render
/// (offscreen gate renders bind nothing, so texture-sampling shaders would false-fail black).
/// Gradient-checker with distinct hue quadrants — non-black everywhere, no symmetry that could
/// mask flipped or wrong-scaled sampling. Same bytes every run: the pixel pass-list is a baseline.
enum GateInputPattern {
    static let size = 64

    static func bytes() -> [UInt8] {
        var out = [UInt8]()
        out.reserveCapacity(size * size * 4)
        for y in 0..<size {
            for x in 0..<size {
                // Intensity ramp 32…223 (never black) + an 8px checker for spatial variation.
                let ramp = UInt8(32 + (x + y) * 191 / (2 * (size - 1)))
                let checker: UInt8 = ((x / 8 + y / 8) % 2 == 0) ? 224 : 96
                let top = y < size / 2
                let left = x < size / 2
                // Quadrant hues (BGRA byte order): TL red, TR green, BL blue, BR magenta.
                let r: UInt8 = (top && left) || (!top && !left) ? checker : ramp
                let g: UInt8 = (top && !left) ? checker : ramp
                let b: UInt8 = (!top) ? checker : ramp
                out.append(contentsOf: [b, g, r, 255])
            }
        }
        return out
    }

    static func makeTexture(device: MTLDevice) -> MTLTexture? {
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: size, height: size, mipmapped: false)
        desc.usage = .shaderRead
        guard let tex = device.makeTexture(descriptor: desc) else { return nil }
        let b = bytes()
        b.withUnsafeBytes {
            tex.replace(region: MTLRegionMake2D(0, 0, size, size), mipmapLevel: 0,
                        withBytes: $0.baseAddress!, bytesPerRow: size * 4)
        }
        return tex
    }
}
```

- [ ] **Step 4: Implement the bridge function**

Append to `App/TrueISFEditor/ISFMSLSafeBridge.h` (before `#ifdef __cplusplus }` close):

```objc
/// Renders `scene` at an explicit time (non-realtime rendering — the pixel-truth gate), catching
/// any C++ exception thrown at render time. Same contract as ISFMSLSafeRender otherwise.
id<MTLTexture> _Nullable ISFMSLSafeRenderAtTime(ISFMSLScene *scene,
                                                NSSize size,
                                                double time,
                                                id<MTLCommandBuffer> commandBuffer,
                                                NSString * _Nullable * _Nullable errorOut);
```

Append to `App/TrueISFEditor/ISFMSLSafeBridge.mm`:

```objc
id<MTLTexture> _Nullable ISFMSLSafeRenderAtTime(ISFMSLScene *scene,
                                                NSSize size,
                                                double time,
                                                id<MTLCommandBuffer> commandBuffer,
                                                NSString * _Nullable * _Nullable errorOut)
{
    if (errorOut) { *errorOut = nil; }
    try {
        id<VVMTLTextureImage> img = [scene createAndRenderToTextureSized:size
                                                                  atTime:time
                                                         inCommandBuffer:commandBuffer];
        if (img == nil) { return nil; }
        // Same pool-recycle guard as ISFMSLSafeRender: keep the VVMTLTextureImage wrapper alive
        // until the GPU is done, or VVMTLPool may recycle the backing texture mid-render.
        [commandBuffer addCompletedHandler:^(id<MTLCommandBuffer> _Nonnull cb) { (void)img; }];
        return img.texture;
    }
    catch (const std::exception &e) {
        if (errorOut) { *errorOut = [NSString stringWithFormat:@"Render exception: %s", e.what()]; }
        return nil;
    }
    catch (...) {
        if (errorOut) { *errorOut = @"Unknown render exception."; }
        return nil;
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: same command as Step 2. Expected: `TEST SUCCEEDED`, 2 tests pass (bridge compiles; its behavior is covered in Task 4).

- [ ] **Step 6: Commit**

```bash
git add App/TrueISFEditor/GateInputPattern.swift App/TrueISFEditorTests/GateInputPatternTests.swift \
        App/TrueISFEditor/ISFMSLSafeBridge.h App/TrueISFEditor/ISFMSLSafeBridge.mm
git commit -m "feat(gate): ISFMSLSafeRenderAtTime bridge + deterministic GateInputPattern"
```

---

### Task 4: `MetalPreviewController.runPixelGate()` + GPU integration tests

**Files:**
- Modify: `App/TrueISFEditor/MetalPreviewController.swift` (add method at the end of the class, before the `MTKViewDelegate` extension — it must live in this file: `scene` is `private`)
- Test: `App/TrueISFEditorTests/PixelGateIntegrationTests.swift`

**Interfaces:**
- Consumes: `ISFMSLSafeRenderAtTime` (Task 3), `GateInputPattern` (Task 3), `FramePixelStats` (Task 1), `PixelGate` (Task 2), existing `scene`/`device`/`renderQueue`/`inputs`.
- Produces: `func runPixelGate(size: CGSize = CGSize(width: 320, height: 180), times: [Double] = [0.0, 0.5, 1.5]) -> PixelVerdict` on `MetalPreviewController` (@MainActor).

- [ ] **Step 1: Write the failing tests**

```swift
// App/TrueISFEditorTests/PixelGateIntegrationTests.swift
import XCTest
@testable import TrueISFEditor

/// End-to-end pixel gate through the real ISFMSLKit render path (GPU). Same compile-poll pattern
/// as MetalPreviewControllerTests.
@MainActor
final class PixelGateIntegrationTests: XCTestCase {
    private func compile(_ isf: String, timeout: TimeInterval = 20) async -> MetalPreviewController? {
        let c = MetalPreviewController()
        c.load(isf: isf)
        let start = Date()
        while Date().timeIntervalSince(start) < timeout {
            if c.compileValid { return c }
            if c.compileError != nil { return nil }
            try? await Task.sleep(nanoseconds: 25_000_000)
        }
        return nil
    }

    private let header = """
    /*{ "DESCRIPTION": "gate test", "CREDIT": "test", "CATEGORIES": ["Generator"], "INPUTS": [] }*/
    """

    func testAnimatedShaderIsOK() async throws {
        let c = try XCTUnwrap(await compile(header + """

        void main() { gl_FragColor = vec4(fract(isf_FragNormCoord.x + TIME), 0.5, 0.5, 1.0); }
        """))
        XCTAssertEqual(c.runPixelGate(), .ok)
    }

    func testBlackShaderFailsBlack() async throws {
        let c = try XCTUnwrap(await compile(header + """

        void main() { gl_FragColor = vec4(0.0, 0.0, 0.0, 1.0); }
        """))
        XCTAssertEqual(c.runPixelGate(), .black)
    }

    func testStaticShaderWarnsStatic() async throws {
        let c = try XCTUnwrap(await compile(header + """

        void main() { gl_FragColor = vec4(isf_FragNormCoord.x, 0.3, 0.2, 1.0); }
        """))
        XCTAssertEqual(c.runPixelGate(), .constant)
    }

    func testNaNShaderFails() async throws {
        // 0.0/0.0 at runtime (TIME*0.0 defeats constant folding). On a float output this is NAN;
        // if the engine output is 8-bit the NaN clamps to black — either way it must FAIL.
        let c = try XCTUnwrap(await compile(header + """

        void main() { gl_FragColor = vec4(0.0 / max(TIME * 0.0, 0.0)); }
        """))
        XCTAssertTrue(c.runPixelGate().isFail)
    }

    func testImageInputGetsPatternBound() async throws {
        // Passthrough of the bound pattern: must NOT be black (proves the binding worked).
        // It renders the same static pattern every frame, so STATIC (or OK) is the pass.
        let isf = """
        /*{ "DESCRIPTION": "gate test", "CREDIT": "test", "CATEGORIES": ["Filter"],
            "INPUTS": [{ "NAME": "inputImage", "TYPE": "image" }] }*/

        void main() { gl_FragColor = IMG_NORM_PIXEL(inputImage, isf_FragNormCoord); }
        """
        let c = try XCTUnwrap(await compile(isf))
        let v = c.runPixelGate()
        XCTAssertFalse(v.isFail, "bound pattern must prevent false-black (got \(v.rawValue))")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd App && xcodegen generate && xcodebuild test -project TrueISFEditor.xcodeproj -scheme TrueISFEditor -destination 'platform=macOS,arch=arm64' -derivedDataPath ./ddata -only-testing:TrueISFEditorTests/PixelGateIntegrationTests 2>&1 | tail -5`
Expected: build FAILURE — `value of type 'MetalPreviewController' has no member 'runPixelGate'`.

- [ ] **Step 3: Implement `runPixelGate`**

Add to `MetalPreviewController` (end of the main class body in `MetalPreviewController.swift`):

```swift
    /// Pixel-truth render gate: renders `times.count` frames offscreen at explicit times on the
    /// current scene and analyzes the pixels. Frames render sequentially on the SAME scene so
    /// persistent/feedback buffers accumulate — multipass shaders warm up honestly. Synchronous
    /// (~ms for 3 small frames); callers are the headless corpus harness and the post-import hook.
    /// See docs/superpowers/specs/2026-07-09-pixel-truth-render-gate-design.md.
    func runPixelGate(size: CGSize = CGSize(width: 320, height: 180),
                      times: [Double] = [0.0, 0.5, 1.5]) -> PixelVerdict {
        guard let scene = scene else { return .renderError }
        // Bind the deterministic pattern to every image input (offscreen renders bind nothing,
        // so texture-sampling shaders would false-fail as black).
        if inputs.contains(where: { $0.type == "image" }) {
            guard let pattern = GateInputPattern.makeTexture(device: device) else {
                return .renderError   // don't silently render unbound
            }
            for input in inputs where input.type == "image" {
                if let val = ISFMSLSceneVal.create(with: pattern) as? ISFMSLSceneVal {
                    scene.setValue(val, forInputNamed: input.name)
                }
            }
        }
        var frames: [FramePixelStats?] = []
        for t in times {
            guard let cb = renderQueue.makeCommandBuffer() else { return .renderError }
            var err: NSString?
            guard let tex = ISFMSLSafeRenderAtTime(
                scene, NSSize(width: size.width, height: size.height), t, cb, &err) else {
                return .renderError
            }
            guard FramePixelStats.supports(tex.pixelFormat) else {
                cb.commit()
                return .unsupported
            }
            // Blit into a CPU-readable copy — pool textures aren't guaranteed CPU-accessible.
            let desc = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: tex.pixelFormat, width: tex.width, height: tex.height, mipmapped: false)
            desc.storageMode = .managed
            guard let readback = device.makeTexture(descriptor: desc),
                  let blit = cb.makeBlitCommandEncoder() else {
                cb.commit()
                return .renderError
            }
            blit.copy(from: tex, to: readback)
            blit.synchronize(resource: readback)
            blit.endEncoding()
            cb.commit()
            cb.waitUntilCompleted()
            frames.append(FramePixelStats.analyze(texture: readback))
        }
        return PixelGate.verdict(frames)
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: same command as Step 2. Expected: `TEST SUCCEEDED`, 5 tests pass.
If `testImageInputGetsPatternBound` fails BLACK: the binding didn't take — check whether the engine expects the value set *before* the first render of the frame loop and whether `inputs` names match the scene attribs (debug with `scene.inputs`). Do not weaken the assertion.

- [ ] **Step 5: Run the full app suite (no regressions)**

Run: `cd App && xcodebuild test -project TrueISFEditor.xcodeproj -scheme TrueISFEditor -destination 'platform=macOS,arch=arm64' -derivedDataPath ./ddata 2>&1 | grep -E "Executed|TEST (SUCCEEDED|FAILED)" | tail -5`
Expected: `TEST SUCCEEDED`, 200 existing + new tests, 3 env-gated skips.

- [ ] **Step 6: Commit**

```bash
git add App/TrueISFEditor/MetalPreviewController.swift App/TrueISFEditorTests/PixelGateIntegrationTests.swift
git commit -m "feat(gate): MetalPreviewController.runPixelGate — 3-frame offscreen pixel-truth check"
```

---

### Task 5: Corpus surfaces — discovery harness + ISF-library test

**Files:**
- Modify: `App/TrueISFEditor/TrueISFEditorApp.swift` (corpus loop, ~lines 150–175)
- Modify: `App/TrueISFEditorTests/CorpusRenderTests.swift` (after `pollCompile` success)
- Modify: `scripts/corpus-run.sh` (header comment only — the grep already matches the new lines)

**Interfaces:**
- Consumes: `runPixelGate()` (Task 4), `PixelVerdict.isFail` (Task 2).
- Produces: corpus line format `<id>\tOK\tpixel=<VERDICT>\twarnings=<n>` / `<id>\tFAIL\tpixel=<VERDICT>`; summary `=== CORPUS compile X/N · pixel Y/N OK ===`. (Compile-fail lines unchanged: `<id>\tFAIL\t<error>`.)

- [ ] **Step 1: Update the discovery-corpus loop**

In `TrueISFEditorApp.swift`, replace the `line = valid ? ... : ...` assignment with:

```swift
                        if valid {
                            let pixel = preview.runPixelGate()
                            line = pixel.isFail
                                ? "\(id)\tFAIL\tpixel=\(pixel.rawValue)"
                                : "\(id)\tOK\tpixel=\(pixel.rawValue)\twarnings=\(warnings.count)"
                        } else {
                            line = "\(id)\tFAIL\t\((err ?? "timeout").split(separator: "\n").first.map(String.init) ?? "")"
                        }
```

And replace the summary computation (`let ok = ...` and the `report` line) with:

```swift
                let compileOK = lines.filter { $0.contains("\tOK\t") || $0.contains("\tFAIL\tpixel=") }.count
                let pixelOK = lines.filter { $0.contains("\tOK\t") }.count
                let report = "=== CORPUS compile \(compileOK)/\(ids.count) · pixel \(pixelOK)/\(ids.count) OK ===\n"
                    + lines.joined(separator: "\n")
```

- [ ] **Step 2: Update `CorpusRenderTests`**

In the loop, replace `if ok { pass += 1 }` with:

```swift
            if ok {
                pass += 1
                let v = controller.runPixelGate()
                pixelCounts[v.rawValue, default: 0] += 1
                if v.isFail { pixelFailures.append((f.lastPathComponent, v.rawValue)) }
            }
```

Add alongside `var failures`:

```swift
        var pixelCounts: [String: Int] = [:]
        var pixelFailures: [(String, String)] = []
```

Extend the report string with a pixel section (after the failures section):

```swift
        --- pixel gate (compiled files) ---
        \(pixelCounts.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value)" }.joined(separator: "  "))
        --- pixel failures (\(pixelFailures.count)) ---
        \(pixelFailures.map { "\($0.0): \($0.1)" }.joined(separator: "\n"))
        """
```

(The lenient `XCTAssertGreaterThan(pass, 0)` stays — this corpus is exploratory until the Phase 4 modernizer tightens it.)

- [ ] **Step 3: Update `corpus-run.sh` header comment**

Add one line to the header comment block: `# Each compiled shader is also pixel-gated (3 offscreen frames; black/NaN = FAIL, static = WARN).`

- [ ] **Step 4: Build + full app suite green**

Run: `cd App && xcodegen generate && xcodebuild test -project TrueISFEditor.xcodeproj -scheme TrueISFEditor -destination 'platform=macOS,arch=arm64' -derivedDataPath ./ddata 2>&1 | grep -E "Executed|TEST (SUCCEEDED|FAILED)" | tail -5`
Expected: `TEST SUCCEEDED` (CorpusRenderTests skips without its sentinel — compile check only).

- [ ] **Step 5: Commit**

```bash
git add App/TrueISFEditor/TrueISFEditorApp.swift App/TrueISFEditorTests/CorpusRenderTests.swift scripts/corpus-run.sh
git commit -m "feat(gate): pixel column in discovery corpus + ISF-library corpus reports"
```

---

### Task 6: Import-report surface — `.rendered` stage + `AppModel` hook

**Files:**
- Modify: `App/TrueISFEditor/ImportEvent.swift` (add `case rendered` to `Stage`)
- Modify: `App/TrueISFEditor/AppModel.swift` (post-conversion hook)
- Test: `App/TrueISFEditorTests/ImportEventTests.swift` (add codable round-trip for `.rendered`)

**Interfaces:**
- Consumes: `PixelGate.importOutcome` (Task 2), `MetalPreviewController` (existing), `ImportLog.shared.record` (existing).
- Produces: `.rendered`-stage `ImportEvent` records after conversions whose pixel gate is not OK.

- [ ] **Step 1: Write the failing test**

Add to `ImportEventTests.swift`:

```swift
    func testRenderedStageRoundTripsCodable() throws {
        let e = ImportEvent(query: "q", shaderID: "abc", fetchSource: .webView, httpStatus: nil,
                            stage: .rendered, outcome: .error,
                            message: "pixel gate: BLACK — compiled but renders black",
                            responseSnippet: nil, warningCount: 0)
        let data = try JSONEncoder().encode(e)
        let back = try JSONDecoder().decode(ImportEvent.self, from: data)
        XCTAssertEqual(back.stage, .rendered)
        XCTAssertEqual(back, e)
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd App && xcodebuild test -project TrueISFEditor.xcodeproj -scheme TrueISFEditor -destination 'platform=macOS,arch=arm64' -derivedDataPath ./ddata -only-testing:TrueISFEditorTests/ImportEventTests 2>&1 | tail -5`
Expected: build FAILURE — `type 'ImportEvent.Stage' has no member 'rendered'`.

- [ ] **Step 3: Implement**

`ImportEvent.swift`: `enum Stage: String, Codable { case urlInvalid, fetched, parsed, converted, rendered }`

`AppModel.swift`: add a dedicated headless gate controller + hook. After BOTH successful-conversion sites (the fetch path that sets `isfOutput = doc.fileText` and records the `converted` event, and the pasted-code path near line 136–144), call `runPixelGateAndRecord(isfText: doc.fileText, shaderID: <the id in scope, or nil for pasted>, source: <the FetchSource in scope>)`. Implementation:

```swift
    /// Dedicated headless Metal controller for the post-import pixel gate — deliberately NOT the
    /// live preview (which may be showing another document or toggled to WebKit). One shared
    /// instance; `load()`'s generation counter makes rapid re-imports supersede cleanly.
    private static let gatePreview = MetalPreviewController()

    /// Post-conversion pixel-truth check (spec §C): compile the converted ISF headlessly, render
    /// 3 frames, and record a `.rendered` ImportEvent when the result is not OK. Fire-and-forget;
    /// OK records nothing (the `converted` event already said ✓). Compile failures record nothing
    /// here either — the editor preview reports those in context.
    private func runPixelGateAndRecord(isfText: String, shaderID: String?,
                                       source: ImportEvent.FetchSource) {
        let query = urlText
        Task { @MainActor in
            let preview = Self.gatePreview
            preview.load(isf: isfText)
            for _ in 0..<200 {                       // ≤10 s; typical transpile ≪ 1 s
                if preview.compileValid || preview.compileError != nil { break }
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
            guard preview.compileValid else { return }
            let verdict = preview.runPixelGate()
            guard let (outcome, message) = PixelGate.importOutcome(verdict) else { return }
            ImportLog.shared.record(ImportEvent(
                query: query, shaderID: shaderID, fetchSource: source, httpStatus: nil,
                stage: .rendered, outcome: outcome, message: message,
                responseSnippet: nil, warningCount: 0))
        }
    }
```

(Check `AppModel`'s actor isolation while implementing: if the class is not `@MainActor`, isolate `gatePreview` and the hook with `@MainActor`.)

- [ ] **Step 4: Run the full app suite**

Run: `cd App && xcodegen generate && xcodebuild test -project TrueISFEditor.xcodeproj -scheme TrueISFEditor -destination 'platform=macOS,arch=arm64' -derivedDataPath ./ddata 2>&1 | grep -E "Executed|TEST (SUCCEEDED|FAILED)" | tail -5`
Expected: `TEST SUCCEEDED`.

- [ ] **Step 5: Amend the spec's hook sentence + commit**

In the spec §C, replace the sentence "When an import-originated document's first compile completes in the preview, run the gate and record a second event:" with "After each successful conversion, a dedicated headless Metal controller compiles the converted ISF and runs the gate (fire-and-forget), recording a second event:". Then:

```bash
git add App/TrueISFEditor/ImportEvent.swift App/TrueISFEditor/AppModel.swift \
        App/TrueISFEditorTests/ImportEventTests.swift \
        docs/superpowers/specs/2026-07-09-pixel-truth-render-gate-design.md
git commit -m "feat(gate): .rendered ImportEvent — post-import pixel verdict in the Import Log"
```

---

### Task 7: Live smoke + full-corpus pixel baseline

Live smoke is a numbered task (global rule 12b): the gate crosses a protocol boundary (real GPU + real Shadertoy fetch) that unit tests can't see.

**Files:**
- Create: none (uses `scripts/corpus-run.sh`)
- Modify: `DESLOPPIFY.md` (header note recording the pixel baseline), `docs/superpowers/plans/2026-07-08-launch-hardening-and-elevation.md` (Task 3.1 checkbox/notes)

- [ ] **Step 1: Pre-flight assertions** (state hypotheses the way they can fail)

- `pkill -f "TrueISFEditor/Contents/MacOS/TrueISFEditor" || true` (no stale instance holding the port/WebKit)
- `ping -c1 www.shadertoy.com` succeeds (fetch path live; Cloudflare flakes are a known waster)
- Hypothesis 1: the 3-id smoke prints a `pixel=` column on every OK line.
- Hypothesis 2: the full run's compile pass-list is IDENTICAL to the 74/78 baseline (gate must not disturb compilation).

- [ ] **Step 2: 3-id smoke run**

```bash
head -5 corpus/discovery-ids.txt | grep -v '^#' | head -3 > /tmp/gate-smoke-ids.txt
./scripts/corpus-run.sh --build /tmp/gate-smoke-ids.txt
```

Expected: three lines each carrying `pixel=`, summary `=== CORPUS compile 3/3 · pixel N/3 OK ===`.

- [ ] **Step 3: Full discovery corpus run**

```bash
./scripts/corpus-run.sh
```

Expected: compile pass-list identical to baseline (74/78, same IDs). Pixel column populates; some previously-OK shaders may now FAIL pixel — that is the gate working. Save the report; diff compile results against the previous baseline list.

- [ ] **Step 4: Record the pixel baseline**

- `DESLOPPIFY.md` header: append `· pixel gate live 2026-07-09: compile 74/78 · pixel <X>/78 (report: docs/corpus-analysis-…)` with the real numbers.
- Plan `2026-07-08-launch-hardening-and-elevation.md`: mark Task 3.1 done, note the baseline + that C5/M1/M2/M3 are now unlocked.
- Copy the report into `docs/corpus-analysis-2026-07-09-pixel-baseline.txt` (create).

- [ ] **Step 5: Commit**

```bash
git add DESLOPPIFY.md docs/superpowers/plans/2026-07-08-launch-hardening-and-elevation.md \
        docs/corpus-analysis-2026-07-09-pixel-baseline.txt
git commit -m "docs(gate): pixel-truth baseline recorded — Task 3.1 done, C5/M1/M2/M3 unlocked"
```

---

## Self-review notes

- Spec coverage: components §1–5 → Tasks 3/2/1/4; surfaces A/B/C → Tasks 5/5/6; error handling → Tasks 2/4; testing → Tasks 1–4; baseline → Task 7. Spec hook-sentence amendment folded into Task 6 Step 5.
- Type consistency: `PixelVerdict.constant.rawValue == "STATIC"` used by all surfaces; `runPixelGate` signature identical in Tasks 4/5/6.
- The `Float16` API requires arm64 — the repo already builds `ARCHS=arm64 ONLY_ACTIVE_ARCH=YES` everywhere.
