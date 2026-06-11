# TrueISFEditor — Filter Input Sources Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a filter ISF shader in the editor receive a real image on each of its image inputs — from a built-in test pattern, another library shader, or the camera — with per-image-input routing.

**Architecture:** A single `ImageSource` protocol (the seam) with conformers `ISFSceneSource` (wraps a second `ISFMSLScene`; powers both test patterns and library chaining), `CameraSource`, and `NoneSource`. A `SourceRouter` (`ObservableObject`) owns `[inputName: ImageSource]`, is exposed through the `PreviewEngine` protocol, and is consulted each frame by `MetalPreviewController.draw` to bind textures via `ISFMSLSceneVal.create(withTexture:)`. Test patterns are ISF generator `.fs` files bundled in the ShadertoyISFKit package.

**Tech Stack:** Swift 6, SwiftUI, Metal/MetalKit, ISFMSLKit (Obj-C++ via `ISFMSLSafeBridge`), AVFoundation (camera), XCTest, SwiftPM resources (`Bundle.module`).

---

## File Structure

**ShadertoyISFKit (pure, testable):**
- Create `ShadertoyISFKit/Sources/ShadertoyISFKit/TestPatterns/*.fs` — 13 bundled ISF generators.
- Create `ShadertoyISFKit/Sources/ShadertoyISFKit/TestPatternCatalog.swift` — `TestPattern` struct + `TestPatternCatalog` enum; loads source text from `Bundle.module`.
- Modify `ShadertoyISFKit/Package.swift` — add `resources: [.copy("TestPatterns")]` to the main target.
- Create `ShadertoyISFKit/Tests/ShadertoyISFKitTests/TestPatternCatalogTests.swift`.

**App (TrueISFEditor):**
- Create `App/TrueISFEditor/ImageSource.swift` — `ImageSource` protocol + `NoneSource`.
- Create `App/TrueISFEditor/ISFSceneSource.swift` — scene-backed source (test patterns + library chaining).
- Create `App/TrueISFEditor/CameraSource.swift` — `AVCaptureSession` → Metal texture (Slice 3).
- Create `App/TrueISFEditor/SourceRouter.swift` — routing map + selection model.
- Create `App/TrueISFEditor/Views/SourceInputControl.swift` — the per-image-input picker view.
- Modify `App/TrueISFEditor/PreviewEngine.swift` — add `var imageSources: SourceRouter { get }`.
- Modify `App/TrueISFEditor/MetalPreviewController.swift` — emit image inputs in `mapInputs`; own a `SourceRouter`; update it on compile; bind textures in `draw`.
- Modify `App/TrueISFEditor/WebKitPreviewController.swift` — hold an inert `SourceRouter` to satisfy the protocol.
- Modify `App/TrueISFEditor/PreviewCoordinator.swift` — expose `var imageSources: SourceRouter`.
- Modify `App/TrueISFEditor/Views/PreviewControlsView.swift` — route the `image` case to `SourceInputControl`.
- Modify `App/TrueISFEditor/Info.plist` + `App/TrueISFEditor/TrueISFEditor.entitlements` — camera usage + entitlement (Slice 3).
- Create `App/TrueISFEditorTests/ISFSceneSourceTests.swift`, `App/TrueISFEditorTests/SourceRouterTests.swift`, `App/TrueISFEditorTests/MapImageInputsTests.swift`.

---

# SLICE 1 — Test-pattern pipeline (end-to-end)

Proves the whole image-input path: detect image inputs → route a source → bind a texture → render the filter. On-device gate after this slice: a filter previews against a moving test pattern.

### Task 1: Test pattern catalog + bundled generators (kit)

**Files:**
- Create: `ShadertoyISFKit/Sources/ShadertoyISFKit/TestPatterns/smpte_bars.fs`
- Create: `ShadertoyISFKit/Sources/ShadertoyISFKit/TestPatterns/grayscale_ramp.fs`
- Create: `ShadertoyISFKit/Sources/ShadertoyISFKit/TestPatterns/scrolling_checker.fs`
- Create: `ShadertoyISFKit/Sources/ShadertoyISFKit/TestPatterns/crosshatch.fs`
- Create: `ShadertoyISFKit/Sources/ShadertoyISFKit/TestPatterns/zone_plate.fs`
- Create: `ShadertoyISFKit/Sources/ShadertoyISFKit/TestPatterns/hue_sweep.fs`
- Create: `ShadertoyISFKit/Sources/ShadertoyISFKit/TestPatterns/bouncing_box.fs`
- Create: `ShadertoyISFKit/Sources/ShadertoyISFKit/TestPatterns/solid_white.fs` (+ black, gray50, red, green, blue)
- Create: `ShadertoyISFKit/Sources/ShadertoyISFKit/TestPatternCatalog.swift`
- Modify: `ShadertoyISFKit/Package.swift`
- Test: `ShadertoyISFKit/Tests/ShadertoyISFKitTests/TestPatternCatalogTests.swift`

- [ ] **Step 1: Create the 13 generator `.fs` files**

`smpte_bars.fs` (the default / reference pattern):
```glsl
/*{
    "DESCRIPTION": "SMPTE 75% color bars",
    "CATEGORIES": ["Test Pattern"],
    "INPUTS": []
}*/
void main() {
    float seg = floor(isf_FragNormCoord.x * 7.0);
    vec3 c = vec3(0.75);
    if      (seg < 0.5) c = vec3(0.75, 0.75, 0.75);
    else if (seg < 1.5) c = vec3(0.75, 0.75, 0.00);
    else if (seg < 2.5) c = vec3(0.00, 0.75, 0.75);
    else if (seg < 3.5) c = vec3(0.00, 0.75, 0.00);
    else if (seg < 4.5) c = vec3(0.75, 0.00, 0.75);
    else if (seg < 5.5) c = vec3(0.75, 0.00, 0.00);
    else                c = vec3(0.00, 0.00, 0.75);
    gl_FragColor = vec4(c, 1.0);
}
```

`grayscale_ramp.fs`:
```glsl
/*{ "DESCRIPTION": "Grayscale staircase (11 steps)", "CATEGORIES": ["Test Pattern"], "INPUTS": [] }*/
void main() {
    float v = floor(isf_FragNormCoord.x * 11.0) / 10.0;
    gl_FragColor = vec4(vec3(v), 1.0);
}
```

`scrolling_checker.fs` (motion):
```glsl
/*{ "DESCRIPTION": "Scrolling checkerboard", "CATEGORIES": ["Test Pattern"], "INPUTS": [] }*/
void main() {
    vec2 uv = isf_FragNormCoord * 8.0;
    uv.x += TIME * 0.5;
    float c = mod(floor(uv.x) + floor(uv.y), 2.0);
    gl_FragColor = vec4(vec3(c), 1.0);
}
```

`crosshatch.fs`:
```glsl
/*{ "DESCRIPTION": "Crosshatch grid", "CATEGORIES": ["Test Pattern"], "INPUTS": [] }*/
void main() {
    vec2 px = isf_FragNormCoord * RENDERSIZE;
    vec2 g = mod(px, 32.0);
    float line = (g.x < 1.0 || g.y < 1.0) ? 1.0 : 0.15;
    gl_FragColor = vec4(vec3(line), 1.0);
}
```

`zone_plate.fs` (motion):
```glsl
/*{ "DESCRIPTION": "Animated zone plate", "CATEGORIES": ["Test Pattern"], "INPUTS": [] }*/
void main() {
    vec2 p = (isf_FragNormCoord - 0.5) * RENDERSIZE;
    float r2 = dot(p, p);
    float v = 0.5 + 0.5 * sin(r2 * 0.0015 + TIME * 2.0);
    gl_FragColor = vec4(vec3(v), 1.0);
}
```

`hue_sweep.fs` (motion):
```glsl
/*{ "DESCRIPTION": "Hue sweep gradient", "CATEGORIES": ["Test Pattern"], "INPUTS": [] }*/
void main() {
    float h = fract(isf_FragNormCoord.x + TIME * 0.1);
    vec3 c = clamp(abs(mod(h * 6.0 + vec3(0.0, 4.0, 2.0), 6.0) - 3.0) - 1.0, 0.0, 1.0);
    gl_FragColor = vec4(c, 1.0);
}
```

`bouncing_box.fs` (motion):
```glsl
/*{ "DESCRIPTION": "Bouncing box motion test", "CATEGORIES": ["Test Pattern"], "INPUTS": [] }*/
void main() {
    vec2 uv = isf_FragNormCoord;
    vec2 pos = vec2(0.5 + 0.4 * sin(TIME * 1.3), 0.5 + 0.4 * sin(TIME * 1.7));
    vec2 d = abs(uv - pos);
    float box = (d.x < 0.06 && d.y < 0.06) ? 1.0 : 0.0;
    vec3 c = mix(vec3(0.05), vec3(1.0, 0.6, 0.1), box);
    gl_FragColor = vec4(c, 1.0);
}
```

The 6 solids use this template — replace `R, G, B` with the listed values:
```glsl
/*{ "DESCRIPTION": "Solid <NAME>", "CATEGORIES": ["Test Pattern"], "INPUTS": [] }*/
void main() { gl_FragColor = vec4(R, G, B, 1.0); }
```
- `solid_white.fs` → `1.0, 1.0, 1.0`
- `solid_black.fs` → `0.0, 0.0, 0.0`
- `solid_gray50.fs` → `0.5, 0.5, 0.5`
- `solid_red.fs` → `1.0, 0.0, 0.0`
- `solid_green.fs` → `0.0, 1.0, 0.0`
- `solid_blue.fs` → `0.0, 0.0, 1.0`

- [ ] **Step 2: Add the resources line to `Package.swift`**

Change the main target from:
```swift
.target(name: "ShadertoyISFKit"),
```
to:
```swift
.target(name: "ShadertoyISFKit", resources: [.copy("TestPatterns")]),
```

- [ ] **Step 3: Write the catalog**

`TestPatternCatalog.swift`:
```swift
import Foundation

/// A built-in test-pattern source: an ISF generator bundled with the kit.
public struct TestPattern: Identifiable, Equatable, Sendable {
    public let id: String          // resource basename, e.g. "smpte_bars"
    public let name: String        // display name, e.g. "SMPTE Bars"
    public let sourceText: String  // the .fs contents

    public static func == (l: TestPattern, r: TestPattern) -> Bool { l.id == r.id }
}

public enum TestPatternCatalog {
    /// (resource basename, display name) in display order.
    private static let manifest: [(String, String)] = [
        ("smpte_bars", "SMPTE Bars"),
        ("grayscale_ramp", "Grayscale Ramp"),
        ("scrolling_checker", "Scrolling Checker"),
        ("crosshatch", "Crosshatch"),
        ("zone_plate", "Zone Plate"),
        ("hue_sweep", "Hue Sweep"),
        ("bouncing_box", "Bouncing Box"),
        ("solid_white", "Solid White"),
        ("solid_black", "Solid Black"),
        ("solid_gray50", "Solid 50% Gray"),
        ("solid_red", "Solid Red"),
        ("solid_green", "Solid Green"),
        ("solid_blue", "Solid Blue"),
    ]

    /// All patterns in display order. A pattern whose resource is missing is skipped (should never
    /// happen — the catalog tests guard this).
    public static let all: [TestPattern] = manifest.compactMap { basename, name in
        guard let url = Bundle.module.url(forResource: basename, withExtension: "fs", subdirectory: "TestPatterns"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return TestPattern(id: basename, name: name, sourceText: text)
    }

    /// The reference / fallback pattern (used when a source is unavailable). SMPTE bars.
    public static var `default`: TestPattern {
        all.first { $0.id == "smpte_bars" } ?? all[0]
    }

    public static func pattern(id: String) -> TestPattern? { all.first { $0.id == id } }
}
```

- [ ] **Step 4: Write the failing test**

`TestPatternCatalogTests.swift`:
```swift
import XCTest
@testable import ShadertoyISFKit

final class TestPatternCatalogTests: XCTestCase {
    func test_allPatternsPresent() {
        XCTAssertEqual(TestPatternCatalog.all.count, 13)
    }

    func test_defaultIsSMPTE() {
        XCTAssertEqual(TestPatternCatalog.default.id, "smpte_bars")
    }

    func test_everyPatternHasValidISFHeader() {
        for p in TestPatternCatalog.all {
            XCTAssertFalse(p.sourceText.isEmpty, "\(p.id) is empty")
            // Extract the /*{ ... }*/ JSON header and confirm it parses.
            guard let open = p.sourceText.range(of: "/*{"),
                  let close = p.sourceText.range(of: "}*/") else {
                return XCTFail("\(p.id) missing ISF header block")
            }
            let json = "{" + p.sourceText[open.upperBound..<close.lowerBound] + "}"
            let data = Data(json.utf8)
            let obj = try? JSONSerialization.jsonObject(with: data)
            XCTAssertNotNil(obj, "\(p.id) header is not valid JSON")
            XCTAssertTrue(p.sourceText.contains("gl_FragColor"), "\(p.id) has no fragment output")
        }
    }
}
```

- [ ] **Step 5: Run tests — verify they fail then pass**

Run: `cd ShadertoyISFKit && swift test --filter TestPatternCatalogTests`
Expected first run: FAIL (no `TestPatternCatalog`). After Steps 1–3: PASS, 3 tests.

- [ ] **Step 6: Commit**

```bash
git add ShadertoyISFKit/Sources/ShadertoyISFKit/TestPatterns ShadertoyISFKit/Sources/ShadertoyISFKit/TestPatternCatalog.swift ShadertoyISFKit/Package.swift ShadertoyISFKit/Tests/ShadertoyISFKitTests/TestPatternCatalogTests.swift
git commit -m "feat(option-a): test-pattern catalog + 13 bundled ISF generators"
```

### Task 2: `ImageSource` protocol + `NoneSource`

**Files:**
- Create: `App/TrueISFEditor/ImageSource.swift`

- [ ] **Step 1: Write the protocol and the trivial conformer**

```swift
import Metal

/// A source of image data for a filter shader's image input. Conformers vend a Metal texture each
/// frame (test patterns and library shaders render into the caller's command buffer; camera returns
/// its latest captured frame).
@MainActor
protocol ImageSource: AnyObject {
    var displayName: String { get }
    /// Returns a texture for this frame, rendering into `cb` if needed. Nil ⇒ leave the input unbound.
    func texture(size: MTLSize, in cb: MTLCommandBuffer) -> MTLTexture?
}

/// The "no source" selection: the filter input is left unbound (engine default / black).
@MainActor
final class NoneSource: ImageSource {
    var displayName: String { "None" }
    func texture(size: MTLSize, in cb: MTLCommandBuffer) -> MTLTexture? { nil }
}
```

- [ ] **Step 2: Build to verify it compiles**

Run: `cd App && xcodegen generate && xcodebuild -project TrueISFEditor.xcodeproj -scheme TrueISFEditor -derivedDataPath ./ddata -configuration Debug build ARCHS=arm64 ONLY_ACTIVE_ARCH=YES`
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add App/TrueISFEditor/ImageSource.swift
git commit -m "feat(option-a): ImageSource protocol + NoneSource"
```

### Task 3: `ISFSceneSource` (scene-backed source, probe-validated)

**Files:**
- Create: `App/TrueISFEditor/ISFSceneSource.swift`
- Test: `App/TrueISFEditorTests/ISFSceneSourceTests.swift`

- [ ] **Step 1: Write the source**

Mirrors `MetalPreviewController`'s use of `ISFMSLSafeCreateAndLoad` / `ISFMSLSafeRender`, plus the crossfade shell's probe-frame-then-keep discipline.
```swift
import Metal
import Foundation
import ISFMSLKit

/// An ImageSource backed by a second ISFMSLScene loaded from ISF source text. Powers both test
/// patterns and library-shader chaining. Validated by rendering one probe frame on init; if that
/// fails, init returns nil so the router can fall back. Renders into the caller's command buffer.
@MainActor
final class ISFSceneSource: ImageSource {
    let displayName: String
    private let scene: ISFMSLScene
    private let queue: MTLCommandQueue
    private let tempURL: URL
    private var lastGood: MTLTexture?

    /// Returns nil if the shader fails to compile or render a probe frame.
    init?(displayName: String, sourceText: String, device: MTLDevice, queue: MTLCommandQueue) {
        self.displayName = displayName
        self.queue = queue
        self.tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("trueisf-src-\(UUID().uuidString).fs")
        do { try sourceText.write(to: tempURL, atomically: true, encoding: .utf8) } catch { return nil }

        var compileError: ObjCBool = false
        var message: NSString?
        guard let s = ISFMSLSafeCreateAndLoad(device, tempURL, &compileError, &message),
              !compileError.boolValue else { return nil }
        self.scene = s

        // Probe frame: confirm it actually renders before we accept this source.
        guard let cb = queue.makeCommandBuffer() else { return nil }
        var err: NSString?
        let tex = ISFMSLSafeRender(s, NSSize(width: 320, height: 180), cb, &err)
        cb.commit()
        cb.waitUntilCompleted()
        guard tex != nil, !s.compilerError else { return nil }
    }

    func texture(size: MTLSize, in cb: MTLCommandBuffer) -> MTLTexture? {
        var err: NSString?
        let tex = ISFMSLSafeRender(scene, NSSize(width: size.width, height: size.height), cb, &err)
        if let tex { lastGood = tex; return tex }
        return lastGood   // keep-last-good on a transient render failure
    }
}
```

- [ ] **Step 2: Write the failing test**

`ISFSceneSourceTests.swift` (runs against a real device — CI/local Macs have one):
```swift
import XCTest
import Metal
import ShadertoyISFKit
@testable import TrueISFEditor

@MainActor
final class ISFSceneSourceTests: XCTestCase {
    func test_validPatternProducesTexture() throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let queue = try XCTUnwrap(device.makeCommandQueue())
        let smpte = TestPatternCatalog.default
        let src = try XCTUnwrap(
            ISFSceneSource(displayName: smpte.name, sourceText: smpte.sourceText, device: device, queue: queue))
        let cb = try XCTUnwrap(queue.makeCommandBuffer())
        let tex = src.texture(size: MTLSize(width: 64, height: 64, depth: 1), in: cb)
        cb.commit(); cb.waitUntilCompleted()
        XCTAssertNotNil(tex)
    }

    func test_garbageSourceFailsInit() throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let queue = try XCTUnwrap(device.makeCommandQueue())
        let bad = ISFSceneSource(displayName: "bad", sourceText: "not a shader", device: device, queue: queue)
        XCTAssertNil(bad)
    }
}
```

- [ ] **Step 3: Run the tests**

Run: `cd App && xcodebuild test -project TrueISFEditor.xcodeproj -scheme TrueISFEditor -derivedDataPath ./ddata -only-testing:TrueISFEditorTests/ISFSceneSourceTests ARCHS=arm64 ONLY_ACTIVE_ARCH=YES`
Expected: 2 tests PASS.

- [ ] **Step 4: Commit**

```bash
git add App/TrueISFEditor/ISFSceneSource.swift App/TrueISFEditorTests/ISFSceneSourceTests.swift
git commit -m "feat(option-a): ISFSceneSource with probe-frame validation"
```

### Task 4: `SourceRouter` (routing map + selection model)

**Files:**
- Create: `App/TrueISFEditor/SourceRouter.swift`
- Test: `App/TrueISFEditorTests/SourceRouterTests.swift`

- [ ] **Step 1: Write the router**

```swift
import Metal
import Combine
import ShadertoyISFKit

/// The user's chosen source for one image input. `.library` carries a file URL (Slice 2);
/// `.camera` (Slice 3) selects the shared camera source.
enum SourceSelection: Equatable {
    case none
    case testPattern(id: String)
    case library(url: URL)
    case camera
}

/// Owns the `[imageInputName: ImageSource]` map for the edited filter. Rebuilt when the shader's
/// image-input set changes. Lives in the Metal engine; views mutate it via `setSelection`.
@MainActor
final class SourceRouter: ObservableObject {
    private let device: MTLDevice
    private let queue: MTLCommandQueue

    /// Image-input names on the current shader, in declaration order (drives the UI).
    @Published private(set) var imageInputNames: [String] = []
    @Published private(set) var selections: [String: SourceSelection] = [:]
    private var sources: [String: ImageSource] = [:]

    init(device: MTLDevice, queue: MTLCommandQueue) {
        self.device = device
        self.queue = queue
    }

    /// Called by the engine on each successful compile. Adds defaults for new image inputs and
    /// prunes routes for inputs that no longer exist.
    func updateInputs(_ inputs: [ISFPreviewInput]) {
        let names = inputs.filter { $0.type == "image" }.map { $0.name }
        imageInputNames = names
        let nameSet = Set(names)
        selections = selections.filter { nameSet.contains($0.key) }
        sources = sources.filter { nameSet.contains($0.key) }
        for n in names where selections[n] == nil {
            selections[n] = .none
            sources[n] = NoneSource()
        }
    }

    func selection(for name: String) -> SourceSelection { selections[name] ?? .none }

    func setSelection(_ sel: SourceSelection, for name: String) {
        selections[name] = sel
        sources[name] = makeSource(sel)
    }

    /// The live source for an input (NoneSource if unrouted).
    func source(for name: String) -> ImageSource { sources[name] ?? NoneSource() }

    private func makeSource(_ sel: SourceSelection) -> ImageSource {
        switch sel {
        case .none:
            return NoneSource()   // user explicitly chose nothing — correct to leave unbound
        case .testPattern(let id):
            guard let p = TestPatternCatalog.pattern(id: id),
                  let s = ISFSceneSource(displayName: p.name, sourceText: p.sourceText, device: device, queue: queue)
            else { return defaultPatternSource() }
            return s
        case .library(let url):
            // Slice 2 wires the picker; a bad pick falls back to the default test pattern (never black).
            guard let text = try? String(contentsOf: url, encoding: .utf8),
                  let s = ISFSceneSource(displayName: url.lastPathComponent, sourceText: text, device: device, queue: queue)
            else { return defaultPatternSource() }
            return s
        case .camera:
            return defaultPatternSource()   // Slice 3 replaces this with the shared CameraSource.
        }
    }

    /// Fallback source — never black-screen. The default SMPTE test pattern, or NoneSource only if
    /// even that fails to build (should never happen; catalog tests guard the bundled patterns).
    private func defaultPatternSource() -> ImageSource {
        let p = TestPatternCatalog.default
        return ISFSceneSource(displayName: p.name, sourceText: p.sourceText, device: device, queue: queue) ?? NoneSource()
    }
}
```

- [ ] **Step 2: Write the failing test**

`SourceRouterTests.swift`:
```swift
import XCTest
import Metal
@testable import TrueISFEditor

@MainActor
final class SourceRouterTests: XCTestCase {
    private func makeRouter() throws -> SourceRouter {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let queue = try XCTUnwrap(device.makeCommandQueue())
        return SourceRouter(device: device, queue: queue)
    }

    private func imageInput(_ name: String) -> ISFPreviewInput {
        ISFPreviewInput(name: name, type: "image", defaultValue: nil, min: nil, max: nil, labels: nil, values: nil)
    }

    func test_updateInputsAddsDefaultsAndPrunes() throws {
        let r = try makeRouter()
        r.updateInputs([imageInput("inputImage"), imageInput("mask")])
        XCTAssertEqual(Set(r.imageInputNames), ["inputImage", "mask"])
        XCTAssertEqual(r.selection(for: "inputImage"), .none)

        // Switching to a shader with only "inputImage" prunes "mask".
        r.updateInputs([imageInput("inputImage")])
        XCTAssertEqual(r.imageInputNames, ["inputImage"])
        XCTAssertEqual(r.selection(for: "mask"), .none)   // pruned ⇒ default
    }

    func test_setSelectionBuildsTestPatternSource() throws {
        let r = try makeRouter()
        r.updateInputs([imageInput("inputImage")])
        r.setSelection(.testPattern(id: "smpte_bars"), for: "inputImage")
        XCTAssertEqual(r.selection(for: "inputImage"), .testPattern(id: "smpte_bars"))
        XCTAssertEqual(r.source(for: "inputImage").displayName, "SMPTE Bars")
    }

    func test_nonImageInputsIgnored() throws {
        let r = try makeRouter()
        let floatInput = ISFPreviewInput(name: "amount", type: "float", defaultValue: 0.0, min: 0.0, max: 1.0, labels: nil, values: nil)
        r.updateInputs([floatInput])
        XCTAssertTrue(r.imageInputNames.isEmpty)
    }
}
```

- [ ] **Step 3: Run the tests**

Run: `cd App && xcodebuild test -project TrueISFEditor.xcodeproj -scheme TrueISFEditor -derivedDataPath ./ddata -only-testing:TrueISFEditorTests/SourceRouterTests ARCHS=arm64 ONLY_ACTIVE_ARCH=YES`
Expected: 3 tests PASS.

- [ ] **Step 4: Commit**

```bash
git add App/TrueISFEditor/SourceRouter.swift App/TrueISFEditorTests/SourceRouterTests.swift
git commit -m "feat(option-a): SourceRouter routing map + selection model"
```

### Task 5: Surface image inputs from `mapInputs` + own the router

**Files:**
- Modify: `App/TrueISFEditor/MetalPreviewController.swift`
- Test: `App/TrueISFEditorTests/MapImageInputsTests.swift`

- [ ] **Step 1: Write the failing test**

`MapImageInputsTests.swift` — verifies `mapInputs` now emits `"image"` for image attribs. Uses the real kit by loading a tiny filter ISF through a controller and reading `inputs`.
```swift
import XCTest
@testable import TrueISFEditor

@MainActor
final class MapImageInputsTests: XCTestCase {
    func test_filterImageInputIsSurfaced() {
        let controller = MetalPreviewController()
        let filter = """
        /*{ "DESCRIPTION": "passthrough", "CATEGORIES": ["Filter"], "INPUTS": [ { "NAME": "inputImage", "TYPE": "image" } ] }*/
        void main() { gl_FragColor = IMG_THIS_PIXEL(inputImage); }
        """
        let expect = expectation(description: "compiled")
        controller.load(isf: filter)
        // load() transpiles async; poll briefly.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            XCTAssertTrue(controller.inputs.contains { $0.name == "inputImage" && $0.type == "image" })
            expect.fulfill()
        }
        wait(for: [expect], timeout: 4.0)
    }
}
```

- [ ] **Step 2: Update `mapInputs` to emit image inputs**

In `MetalPreviewController.mapInputs(_:)`, change the `switch attrib.type` that returns `nil` for unsupported types. Replace:
```swift
            default:       return nil   // image/audio/cube: unsupported in P1.5 controls
```
with:
```swift
            case .image:   typeStr = "image"
            default:       return nil   // audio/cube: still unsupported
```
And in the value-extraction `switch attrib.type` below it, add an `image` case that carries no default/min/max (before the `default:` branch):
```swift
            case .image:
                defaultValue = nil; minVal = nil; maxVal = nil
```

- [ ] **Step 3: Add the router property and update it on compile**

Add a stored property near the other lets in `MetalPreviewController`:
```swift
    let imageSources: SourceRouter
```
Initialize it in `init()` after `self.renderQueue` is set (it already reads `props`):
```swift
        self.imageSources = SourceRouter(device: props.device, queue: props.renderQueue)
```
(Place this before `super.init()`.)

In `applyCompile(scene:hadError:message:)`, after `inputs = Self.mapInputs(s.inputs)` in the success branch, add:
```swift
            imageSources.updateInputs(inputs)
```
And in the failure branch, after `inputs` is left unchanged, add:
```swift
            imageSources.updateInputs(inputs)
```

- [ ] **Step 4: Run the test**

Run: `cd App && xcodebuild test -project TrueISFEditor.xcodeproj -scheme TrueISFEditor -derivedDataPath ./ddata -only-testing:TrueISFEditorTests/MapImageInputsTests ARCHS=arm64 ONLY_ACTIVE_ARCH=YES`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add App/TrueISFEditor/MetalPreviewController.swift App/TrueISFEditorTests/MapImageInputsTests.swift
git commit -m "feat(option-a): surface image inputs + own SourceRouter in MetalPreviewController"
```

### Task 6: Bind source textures each frame in `draw`

**Files:**
- Modify: `App/TrueISFEditor/MetalPreviewController.swift`

- [ ] **Step 1: Bind sources before rendering the filter**

In `draw(in:)`, after obtaining `cb` and `size` and BEFORE the `ISFMSLSafeRender(scene, ...)` call for the main filter, insert:
```swift
        // Bind each image input's routed source (rendered into the same command buffer).
        for input in inputs where input.type == "image" {
            let src = imageSources.source(for: input.name)
            if let tex = src.texture(size: size, in: cb),
               let val = ISFMSLSceneVal.create(with: tex) as? ISFMSLSceneVal {   // Swift folds createWithTexture: → create(with:)
                scene.setValue(val, forInputNamed: input.name)
            }
        }
```
(`scene` and `size` are already in scope at that point; `inputs` is the published property.)

- [ ] **Step 2: Build**

Run: `cd App && xcodebuild -project TrueISFEditor.xcodeproj -scheme TrueISFEditor -derivedDataPath ./ddata -configuration Debug build ARCHS=arm64 ONLY_ACTIVE_ARCH=YES`
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add App/TrueISFEditor/MetalPreviewController.swift
git commit -m "feat(option-a): bind routed image-source textures each frame"
```

### Task 7: Expose the router through the protocol + coordinator + WebKit

**Files:**
- Modify: `App/TrueISFEditor/PreviewEngine.swift`
- Modify: `App/TrueISFEditor/WebKitPreviewController.swift`
- Modify: `App/TrueISFEditor/PreviewCoordinator.swift`

- [ ] **Step 1: Add to the protocol**

In `PreviewEngine.swift`, add to the protocol body:
```swift
    var imageSources: SourceRouter { get }
```

- [ ] **Step 2: Give WebKit an inert router**

In `WebKitPreviewController.swift`, add a stored property (WebKit cannot bind textures; this only satisfies the protocol):
```swift
    let imageSources: SourceRouter = {
        let p = RenderProperties.global()
        return SourceRouter(device: p.device, queue: p.renderQueue)
    }()
```
(If `RenderProperties.global()` is not already imported/used in this file, add `import Metal` and `import VVMetalKit` as needed — match `MetalPreviewController`'s imports.)

- [ ] **Step 3: Expose from the coordinator**

In `PreviewCoordinator.swift`, add a computed property next to `nsView`:
```swift
    var imageSources: SourceRouter { activeEngine.imageSources }
```

- [ ] **Step 4: Build**

Run: `cd App && xcodebuild -project TrueISFEditor.xcodeproj -scheme TrueISFEditor -derivedDataPath ./ddata -configuration Debug build ARCHS=arm64 ONLY_ACTIVE_ARCH=YES`
Expected: BUILD SUCCEEDED.

- [ ] **Step 5: Commit**

```bash
git add App/TrueISFEditor/PreviewEngine.swift App/TrueISFEditor/WebKitPreviewController.swift App/TrueISFEditor/PreviewCoordinator.swift
git commit -m "feat(option-a): expose SourceRouter via PreviewEngine + coordinator"
```

### Task 8: The source picker UI

**Files:**
- Create: `App/TrueISFEditor/Views/SourceInputControl.swift`
- Modify: `App/TrueISFEditor/Views/PreviewControlsView.swift`

- [ ] **Step 1: Write the picker view (Slice-1 entries: None + Test Pattern)**

`SourceInputControl.swift`:
```swift
import SwiftUI
import ShadertoyISFKit

/// Per-image-input source picker. Slice 1 offers None + Test Pattern; Library and Camera are
/// added in later slices.
struct SourceInputControl: View {
    @ObservedObject var router: SourceRouter
    let inputName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(inputName) (image)").font(.caption)
            Menu {
                Button("None") { router.setSelection(.none, for: inputName) }
                Menu("Test Pattern") {
                    ForEach(TestPatternCatalog.all) { p in
                        Button(p.name) { router.setSelection(.testPattern(id: p.id), for: inputName) }
                    }
                }
            } label: {
                Text(router.source(for: inputName).displayName)
            }
        }
    }
}
```

- [ ] **Step 2: Route the `image` case in `PreviewControlsView`**

`PreviewControlsView` already takes `@ObservedObject var coordinator: PreviewCoordinator`. In the `switch input.type` inside `ForEach`, add an `image` case before `default`:
```swift
                    case "image": SourceInputControl(router: coordinator.imageSources, inputName: input.name)
```

- [ ] **Step 3: Build**

Run: `cd App && xcodebuild -project TrueISFEditor.xcodeproj -scheme TrueISFEditor -derivedDataPath ./ddata -configuration Debug build ARCHS=arm64 ONLY_ACTIVE_ARCH=YES`
Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Run the full app test suite**

Run: `cd App && xcodebuild test -project TrueISFEditor.xcodeproj -scheme TrueISFEditor -derivedDataPath ./ddata ARCHS=arm64 ONLY_ACTIVE_ARCH=YES` and `cd ShadertoyISFKit && swift test`
Expected: all green.

- [ ] **Step 5: Commit + stage app for on-device test**

```bash
git add App/TrueISFEditor/Views/SourceInputControl.swift App/TrueISFEditor/Views/PreviewControlsView.swift
git commit -m "feat(option-a): per-image-input source picker (None + Test Pattern)"
```
Then stage a fresh build per the project's native-app hygiene (grep a known >15-char string from `SourceInputControl` in the staged binary before claiming it's ready) and hand to the user for the Slice-1 on-device gate.

**Slice 1 on-device gate (user):** open a filter shader (one with an `image` input) → its picker appears → choose a moving test pattern (e.g. Scrolling Checker) → the filter previews the pattern processed, animating. Switching patterns is live. A generator (no image input) shows no picker.

---

# SLICE 2 — Library-shader chaining

Adds the `Shader ▸` library submenu to the picker. `ISFSceneSource` already handles `.library` selections in `SourceRouter.makeSource`; this slice only wires the UI to the library list and the device that builds the source. Nesting rule: a library source that is itself a filter gets the default test pattern for its own image inputs.

### Task 9: Feed the library list to the picker

**Files:**
- Modify: `App/TrueISFEditor/Views/SourceInputControl.swift`
- Modify: `App/TrueISFEditor/Views/PreviewControlsView.swift` (pass the `LibraryModel` down)

- [ ] **Step 1: Add a `LibraryModel` parameter to the picker**

In `SourceInputControl`, add:
```swift
    @ObservedObject var library: LibraryModel
```
and add a `Shader` submenu inside the `Menu { ... }`, after the Test Pattern menu:
```swift
                Menu("Shader") {
                    ForEach(library.filtered(query: "")) { entry in
                        Button(entry.name) { router.setSelection(.library(url: entry.url), for: inputName) }
                    }
                }
```

- [ ] **Step 2: Pass the library model from `PreviewControlsView`**

`PreviewControlsView` must receive the `LibraryModel` (already constructed at the app/editor level — pass it in where `PreviewControlsView` is instantiated, in `EditorScreen.swift`). Add `@ObservedObject var library: LibraryModel` to `PreviewControlsView`, forward it: 
```swift
                    case "image": SourceInputControl(router: coordinator.imageSources, inputName: input.name, library: library)
```
Update the `PreviewControlsView(...)` call site in `EditorScreen.swift` to pass the existing `LibraryModel` instance.

- [ ] **Step 3: Apply the nesting rule in `ISFSceneSource`**

When an `ISFSceneSource` is built for a library shader that is itself a filter, feed its image inputs the default test pattern so it renders. In `ISFSceneSource.init`, after a successful load and before the probe frame, bind defaults:
```swift
        // Nesting rule: if this source shader is itself a filter, feed its image inputs the
        // default test pattern (one level, no recursion).
        if let patternSource = ISFSceneSource.defaultPatternTexture(device: device, queue: queue, size: NSSize(width: 320, height: 180)) {
            for attrib in s.inputs where attrib.isFilterInputImage || attrib.shouldHaveImageBuffer || attrib.type == .image {
                if let val = ISFMSLSceneVal.create(with: patternSource) as? ISFMSLSceneVal {
                    s.setValue(val, forInputNamed: attrib.name)
                }
            }
        }
```
Add the helper (renders the default SMPTE pattern once to a standalone texture):
```swift
    private static func defaultPatternTexture(device: MTLDevice, queue: MTLCommandQueue, size: NSSize) -> MTLTexture? {
        let p = TestPatternCatalog.default
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("trueisf-nest-\(UUID().uuidString).fs")
        guard (try? p.sourceText.write(to: url, atomically: true, encoding: .utf8)) != nil else { return nil }
        var ce: ObjCBool = false; var msg: NSString?
        guard let scene = ISFMSLSafeCreateAndLoad(device, url, &ce, &msg), !ce.boolValue,
              let cb = queue.makeCommandBuffer() else { return nil }
        var err: NSString?
        let tex = ISFMSLSafeRender(scene, size, cb, &err)
        cb.commit(); cb.waitUntilCompleted()
        return tex
    }
```
(`device` is not currently stored on `ISFSceneSource` — add `private let device: MTLDevice` and assign it in `init`.)

- [ ] **Step 4: Build, test, commit**

Run the build + full test suite (commands as in Task 8). Then:
```bash
git add App/TrueISFEditor/Views/SourceInputControl.swift App/TrueISFEditor/Views/PreviewControlsView.swift App/TrueISFEditor/Views/EditorScreen.swift App/TrueISFEditor/ISFSceneSource.swift
git commit -m "feat(option-a): library-shader image source + nesting rule"
```

**Slice 2 on-device gate (user):** pick a generator from the library as a filter's source → the filter processes that shader live. Pick a filter as a source → it renders (fed the default pattern), no black screen.

---

# SLICE 3 — Camera

### Task 10: `CameraSource`

**Files:**
- Create: `App/TrueISFEditor/CameraSource.swift`
- Modify: `App/TrueISFEditor/Info.plist` (add `NSCameraUsageDescription`)
- Modify: `App/TrueISFEditor/TrueISFEditor.entitlements` (add `com.apple.security.device.camera`)

- [ ] **Step 1: Add camera usage + entitlement**

In `Info.plist` add:
```xml
    <key>NSCameraUsageDescription</key>
    <string>TrueISFEditor uses the camera as a live input source for filter shaders.</string>
```
In `TrueISFEditor.entitlements` add:
```xml
    <key>com.apple.security.device.camera</key>
    <true/>
```

- [ ] **Step 2: Write `CameraSource`**

```swift
import AVFoundation
import Metal
import CoreVideo

/// A live-camera ImageSource. Captures BGRA frames into a CVMetalTextureCache and vends the latest
/// frame's Metal texture. Requests permission on first use; yields nil until a frame arrives or if
/// permission is denied (the router then falls back to the default test pattern).
@MainActor
final class CameraSource: NSObject, ImageSource, AVCaptureVideoDataOutputSampleBufferDelegate {
    var displayName: String { "Camera" }

    private let session = AVCaptureSession()
    private let output = AVCaptureVideoDataOutput()
    private let queue = DispatchQueue(label: "trueisf.camera")
    private var textureCache: CVMetalTextureCache?
    private var latest: MTLTexture?

    init?(device: MTLDevice) {
        super.init()
        var cache: CVMetalTextureCache?
        guard CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &cache) == kCVReturnSuccess,
              let cache else { return nil }
        textureCache = cache
        configure()
    }

    private func configure() {
        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            guard granted, let self else { return }
            Task { @MainActor in self.start() }
        }
    }

    private func start() {
        session.beginConfiguration()
        guard let cam = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: cam),
              session.canAddInput(input) else { session.commitConfiguration(); return }
        session.addInput(input)
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.setSampleBufferDelegate(self, queue: queue)
        if session.canAddOutput(output) { session.addOutput(output) }
        session.commitConfiguration()
        session.startRunning()
    }

    nonisolated func captureOutput(_ out: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                                   from connection: AVCaptureConnection) {
        guard let pixel = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let w = CVPixelBufferGetWidth(pixel), h = CVPixelBufferGetHeight(pixel)
        var cvTex: CVMetalTexture?
        Task { @MainActor in
            guard let cache = self.textureCache else { return }
            let status = CVMetalTextureCacheCreateTextureFromImage(
                kCFAllocatorDefault, cache, pixel, nil, .bgra8Unorm, w, h, 0, &cvTex)
            if status == kCVReturnSuccess, let cvTex, let tex = CVMetalTextureGetTexture(cvTex) {
                self.latest = tex
            }
        }
    }

    func texture(size: MTLSize, in cb: MTLCommandBuffer) -> MTLTexture? { latest }
}
```
> Note for the implementer: the `captureOutput` → `Task { @MainActor }` hop is intentional to keep `latest`/`textureCache` access on the main actor. If profiling shows frame drops, move texture-cache access to the capture queue with explicit locking in a follow-up; do not prematurely optimize.

- [ ] **Step 3: Wire camera into the router and picker**

In `SourceRouter`, make the camera a shared lazily-created instance (so all inputs share one capture session). Add:
```swift
    private lazy var sharedCamera: ImageSource? = CameraSource(device: device)
```
and in `makeSource`, replace the `.camera` case body:
```swift
        case .camera:
            return sharedCamera ?? defaultPatternSource()   // camera unavailable ⇒ default pattern, never black
```
In `SourceInputControl`, add to the `Menu`:
```swift
                Button("Camera") { router.setSelection(.camera, for: inputName) }
```

- [ ] **Step 4: Build, test, commit**

Build + full test suite (camera itself is on-device only — no automated test). Then:
```bash
git add App/TrueISFEditor/CameraSource.swift App/TrueISFEditor/SourceRouter.swift App/TrueISFEditor/Views/SourceInputControl.swift App/TrueISFEditor/Info.plist App/TrueISFEditor/TrueISFEditor.entitlements
git commit -m "feat(option-a): live camera image source"
```

**Slice 3 on-device gate (user):** choose Camera as a filter's source → grant permission → the filter processes the live webcam. Denying permission falls back to the default test pattern, no crash.

---

## Self-Review

**Spec coverage:**
- Per-image-input routing → `SourceRouter` (Task 4) + picker (Task 8). ✓
- Three source types → test pattern (Slice 1), library (Slice 2), camera (Slice 3). ✓
- Test-pattern set with motion → Task 1 (13 generators; checker/zone-plate/hue/box animate). ✓
- Probe-frame validation + keep-last-good → `ISFSceneSource` (Task 3). ✓
- Never black-screen → NoneSource default, keep-last-good, nesting rule (Task 9), camera fallback (Task 10). ✓
- Multi-image filters feedable → router keys by input name; `MapImageInputsTests` + `SourceRouterTests` cover multiple inputs. ✓
- Default fallback = SMPTE bars → `TestPatternCatalog.default` (Task 1), used by nesting rule + camera fallback. ✓
- Stop dropping image inputs → `mapInputs` change (Task 5). ✓
- Texture binding path → `draw` binding (Task 6). ✓

**Placeholder scan:** No "TBD"/"handle edge cases"/"similar to". The `.library` and `.camera` cases in `SourceRouter` (Task 4) are deliberately inert-with-fallback and are completed in Slices 2/3 — each shows full code. ✓

**Type consistency:** `SourceSelection` cases (`.none/.testPattern(id:)/.library(url:)/.camera`) match across Tasks 4, 8, 9, 10. `ISFSceneSource.init(displayName:sourceText:device:queue:)` signature matches its callers in `SourceRouter`. `ImageSource.texture(size:in:)` matches every conformer and the `draw` call site. `imageSources` named identically on the protocol, both engines, and the coordinator. ✓
