# TrueISFEditor P1.5 — Native ISFMSLKit Preview Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the WebGL1/ISF.js preview with a native ISFMSLKit (Metal) engine as the primary renderer (matching VDMX6, accepting ES3 shaders), keeping WebKit as a manual Metal|WebKit fallback.

**Architecture:** A concrete `PreviewCoordinator: ObservableObject` owns both a `WebKitPreviewController` (today's code, renamed) and a new `MetalPreviewController`, both conforming to a `PreviewEngine` protocol. The coordinator forwards calls to the active engine, re-publishes its compile state, and vends the active engine's `NSView`. ISFMSLKit + its 3 framework deps are vendored as prebuilt, committed, pre-signed binaries and embedded in the app.

**Tech Stack:** Swift / SwiftUI, Metal (MTKView, MTLTexture), Objective-C++ ISFMSLKit (`mrRay/ISFMSLKit` + VVMetalKit + PINCache + PINOperation), xcodegen, XCTest, Combine. Xcode 26 on arm64 macOS.

**Reference docs (read before starting):**
- Spec: `docs/superpowers/specs/2026-06-09-trueisfeditor-p1.5-native-isfmslkit-preview-design.md`
- Skill draft: `~/.claude/c-suite/reports/librarian/skill-drafts/2026-05-29-isfmslkit-macos-app.md`
- Skill draft: `~/.claude/c-suite/reports/librarian/skill-drafts/2026-05-29-swiftui-mtkview-offmain-render.md`

**Build/verify conventions for this repo:**
- Build: `cd App && xcodebuild -project TrueISFEditor.xcodeproj -scheme TrueISFEditor -configuration Debug -derivedDataPath ./ddata-build ARCHS=arm64 ONLY_ACTIVE_ARCH=YES build`
- Test: `cd App && xcodebuild test -project TrueISFEditor.xcodeproj -scheme TrueISFEditor -destination 'platform=macOS,arch=arm64' -derivedDataPath ./ddata-build`
- After any code edit, regenerate the project if `project.yml` changed: `cd App && xcodegen generate`
- Staleness check before claiming "relaunch": grep a known >15-char source string in the staged `.debug.dylib` (see memory `xcode26-debug-dylib-staleness`), NOT the main stub binary.
- Commit convention: conventional commits (`feat(P1.5):` / `chore(P1.5):` / `test(P1.5):` / `docs(P1.5):`), and end every commit body with `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`.

---

## File Structure

**New**
- `vendor/build-isfmslkit.sh` — one-time scripted build of the 4 frameworks.
- `vendor/prebuilt/README.md` — source SHAs, build date, command set.
- `vendor/prebuilt/{ISFMSLKit,VVMetalKit,PINCache,PINOperation}.framework` — committed, pre-signed binaries.
- `App/TrueISFEditor/PreviewEngine.swift` — protocol shared by both engines.
- `App/TrueISFEditor/PreviewCoordinator.swift` — `ObservableObject` owning both engines.
- `App/TrueISFEditor/MetalPreviewController.swift` — native ISFMSLKit engine.
- `App/TrueISFEditor/MetalPreviewView.swift` — MTKView host (or generalize `ISFPreviewView`).
- `App/TrueISFEditor/TrueISFEditor-Bridging-Header.h` — exposes ISFMSLKit headers to Swift.
- `App/TrueISFEditorTests/PreviewCoordinatorTests.swift`
- `App/TrueISFEditorTests/MetalPreviewControllerTests.swift`
- `App/TrueISFEditorTests/CorpusRenderTests.swift` — acceptance harness.
- `App/TrueISFEditorTests/Fakes/FakePreviewEngine.swift` — coordinator test double.

**Modified**
- `App/project.yml` — link/embed 4 frameworks, search paths, rpath, bridging header.
- `App/TrueISFEditor/ISFPreviewController.swift` → renamed `WebKitPreviewController.swift`, conforms to `PreviewEngine`.
- `App/TrueISFEditor/ISFPreviewView.swift` — host the coordinator's `nsView`.
- `App/TrueISFEditor/EditorViewModel.swift`, `Views/EditorScreen.swift`, `Views/PreviewControlsView.swift`, `OutputWindow.swift`, `TrueISFEditorApp.swift` — bind to `PreviewCoordinator`; add renderer toggle.

**Sequencing rationale:** vendor + link frameworks first (prove the build), then refactor the existing engine behind the protocol (behavior-preserving, guarded by existing tests), then build the Metal engine in isolation (TDD), then wire it into the coordinator + toggle, then run the corpus acceptance harness, then the license gate.

---

## Phase A — Vendor & Build Frameworks

### Task 1: Scripted framework build → committed prebuilt binaries

**Files:**
- Create: `vendor/build-isfmslkit.sh`
- Create: `vendor/prebuilt/README.md`
- Create (build output, committed): `vendor/prebuilt/{ISFMSLKit,VVMetalKit,PINCache,PINOperation}.framework`
- Modify: `.gitignore`

- [ ] **Step 1: Write `vendor/build-isfmslkit.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail
# One-time build of ISFMSLKit + framework deps into vendor/prebuilt/.
# Re-run only to update the kit. Output binaries are committed to the repo.
HERE="$(cd "$(dirname "$0")" && pwd)"
WORK="$HERE/_isfmslkit-build"
OUT="$HERE/prebuilt"
rm -rf "$WORK"; mkdir -p "$WORK" "$OUT"

# 1. Clone + recursive submodules (VVMetalKit, PINCache, ISFGLSLGenerator; transpiler dylibs ship in extern/)
git clone --depth 1 https://github.com/mrRay/ISFMSLKit.git "$WORK/ISFMSLKit"
git -C "$WORK/ISFMSLKit" submodule update --init --recursive

# 2. Xcode 26 environment (each blocks the build if missing)
xcodebuild -runFirstLaunch
xcodebuild -downloadComponent MetalToolchain
command -v cmake >/dev/null || brew install cmake

# 3. Patch the Vidvox codesign identity to ad-hoc (their signing identity is not present)
BUILD_SCRIPT="$(find "$WORK/ISFMSLKit" -name 'ISFGLSLGenerator_build_script.sh' | head -1)"
sed -i '' -E 's#codesign .*Developer ID Application: Vidvox, LLC.*#codesign -f -s - "$FRAMEWORK" || true#' "$BUILD_SCRIPT"

# 4. Build frameworks (no signing during build; we sign after)
xcodebuild -workspace "$WORK/ISFMSLKit/ISFMSLKit.xcworkspace" \
  -scheme ISFMSLKit -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath "$WORK/dd" \
  CODE_SIGNING_ALLOWED=NO build

# 5. Collect the 4 frameworks (Syphon intentionally omitted)
PRODUCTS="$WORK/dd/Build/Products/Debug"
for fw in ISFMSLKit VVMetalKit PINCache PINOperation; do
  rm -rf "$OUT/$fw.framework"
  ditto "$PRODUCTS/$fw.framework" "$OUT/$fw.framework"
done

# 6. Pre-sign nested transpiler dylibs (otherwise app embed-codesign fails:
#    "code object is not signed at all in subcomponent")
find "$OUT/ISFMSLKit.framework" -name '*.dylib' -print0 | while IFS= read -r -d '' dylib; do
  codesign -f -s - "$dylib"
done

echo "Done. Frameworks in $OUT"
git -C "$WORK/ISFMSLKit" rev-parse HEAD > "$OUT/.isfmslkit-source-sha"
```

- [ ] **Step 2: Run the build script**

Run: `chmod +x vendor/build-isfmslkit.sh && ./vendor/build-isfmslkit.sh`
Expected: ends with `Done. Frameworks in .../vendor/prebuilt`. If it fails on the codesign-patch `sed`, open the build script path it printed and confirm the regex matched; adjust the `sed` to the real line.

- [ ] **Step 3: Verify the four frameworks exist and nested dylibs are signed**

Run:
```bash
ls -d vendor/prebuilt/*.framework
for d in vendor/prebuilt/ISFMSLKit.framework/Versions/A/Frameworks/*.dylib; do codesign -dv "$d" 2>&1 | head -1; done
```
Expected: 4 `.framework` dirs listed; each nested dylib prints an `Identifier=...`/signed line (no "code object is not signed").

- [ ] **Step 4: Write `vendor/prebuilt/README.md`**

```markdown
# vendor/prebuilt — ISFMSLKit framework binaries

Built once by `../build-isfmslkit.sh`. Committed binaries; do not hand-edit.

- Source: https://github.com/mrRay/ISFMSLKit @ <paste contents of .isfmslkit-source-sha>
- Built: 2026-06-09, Xcode 26, arm64 macOS, Debug, CODE_SIGNING_ALLOWED=NO + ad-hoc nested-dylib signing.
- Frameworks: ISFMSLKit, VVMetalKit, PINCache, PINOperation. (Syphon intentionally excluded — no Syphon in P1.5.)
- To update: re-run `../build-isfmslkit.sh` and commit the changed binaries.
```

- [ ] **Step 5: Update `.gitignore` to ignore the build dir but commit the binaries**

Add to `.gitignore`:
```
vendor/_isfmslkit-build/
```
Confirm `vendor/prebuilt/` is NOT ignored: `git check-ignore vendor/prebuilt/ISFMSLKit.framework` should print nothing.

- [ ] **Step 6: Commit**

```bash
git add vendor/build-isfmslkit.sh vendor/prebuilt .gitignore
git commit -m "chore(P1.5): vendor prebuilt ISFMSLKit frameworks

Scripted one-time build (build-isfmslkit.sh) of ISFMSLKit + VVMetalKit +
PINCache + PINOperation, committed pre-signed to vendor/prebuilt/. Syphon
excluded. Nested transpiler dylibs ad-hoc signed so app embed-codesign passes.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Phase B — Link Frameworks Into the App (build-only)

### Task 2: Embed + link frameworks; prove dyld load with a smoke reference

**Files:**
- Modify: `App/project.yml`
- Create: `App/TrueISFEditor/TrueISFEditor-Bridging-Header.h`
- Modify: `App/TrueISFEditor/TrueISFEditorApp.swift` (temporary smoke reference)

- [ ] **Step 1: Create the bridging header**

`App/TrueISFEditor/TrueISFEditor-Bridging-Header.h`:
```objc
#import <ISFMSLKit/ISFMSLKit.h>
```
(If the umbrella header has a different name, list the real umbrella found at
`vendor/prebuilt/ISFMSLKit.framework/Headers/` — run `ls vendor/prebuilt/ISFMSLKit.framework/Headers/` and import the umbrella.)

- [ ] **Step 2: Add frameworks + settings to `project.yml`**

In `App/project.yml`, under target `TrueISFEditor`, add a `dependencies` entry per framework and extend `settings.base`:
```yaml
    dependencies:
      - package: ShadertoyISFKit
      - framework: ../vendor/prebuilt/ISFMSLKit.framework
        embed: true
        codeSign: true
      - framework: ../vendor/prebuilt/VVMetalKit.framework
        embed: true
        codeSign: true
      - framework: ../vendor/prebuilt/PINCache.framework
        embed: true
        codeSign: true
      - framework: ../vendor/prebuilt/PINOperation.framework
        embed: true
        codeSign: true
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.arsonrivvers.TrueISFEditor
        INFOPLIST_FILE: TrueISFEditor/Info.plist
        CODE_SIGN_ENTITLEMENTS: TrueISFEditor/TrueISFEditor.entitlements
        CODE_SIGN_IDENTITY: "-"
        ENABLE_HARDENED_RUNTIME: YES
        MARKETING_VERSION: "0.1.0"
        GENERATE_INFOPLIST_FILE: NO
        FRAMEWORK_SEARCH_PATHS: $(SRCROOT)/../vendor/prebuilt
        LD_RUNPATH_SEARCH_PATHS: $(inherited) @executable_path/../Frameworks
        SWIFT_OBJC_BRIDGING_HEADER: TrueISFEditor/TrueISFEditor-Bridging-Header.h
```

- [ ] **Step 3: Add a temporary smoke reference in `TrueISFEditorApp.swift`**

At the top of the existing dev-smoke block (the section guarded by the debug print), add a line that forces the linker/dyld to resolve an ISFMSLKit symbol — use the real type confirmed from headers; the skill draft suggests `RenderProperties`:
```swift
// P1.5 smoke: prove ISFMSLKit links + loads. Remove after Task 5.
print("ISFMSLKit device: \(String(describing: RenderProperties.global().device))")
```

- [ ] **Step 4: Regenerate and build**

Run: `cd App && xcodegen generate && xcodebuild -project TrueISFEditor.xcodeproj -scheme TrueISFEditor -configuration Debug -derivedDataPath ./ddata-build ARCHS=arm64 ONLY_ACTIVE_ARCH=YES build`
Expected: `BUILD SUCCEEDED`. If embed-codesign fails on a nested dylib, re-run the pre-sign loop from Task 1 Step 3 and rebuild. If dyld fails at launch under hardened runtime, set `ENABLE_HARDENED_RUNTIME: NO` in `project.yml`, regenerate, rebuild (resolves Open Question §10.2 toward NO).

- [ ] **Step 5: Launch and confirm the symbol resolves at runtime**

Run the built app: `open App/ddata-build/Build/Products/Debug/TrueISFEditor.app` and confirm in Console/stderr the `ISFMSLKit device:` line prints a non-nil device and the app does NOT crash with a dyld "Library not loaded" error.

- [ ] **Step 6: Commit**

```bash
cd App && git add project.yml TrueISFEditor.xcodeproj TrueISFEditor/TrueISFEditor-Bridging-Header.h TrueISFEditor/TrueISFEditorApp.swift
git commit -m "chore(P1.5): link + embed ISFMSLKit frameworks; bridging header

Embeds the 4 prebuilt frameworks, sets framework search path + rpath, adds the
Obj-C bridging header. Temporary smoke reference proves dyld load. Hardened
runtime: <YES|NO — record what actually loaded>.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Phase C — Engine Abstraction (behavior-preserving refactor)

### Task 3: Extract `PreviewEngine`; rename `ISFPreviewController` → `WebKitPreviewController`

**Files:**
- Create: `App/TrueISFEditor/PreviewEngine.swift`
- Rename/Modify: `App/TrueISFEditor/ISFPreviewController.swift` → `WebKitPreviewController.swift`
- Modify: references in `EditorViewModel.swift`, `OutputWindow.swift`, `Views/EditorScreen.swift`, `Views/PreviewControlsView.swift`, `TrueISFEditorApp.swift`

- [ ] **Step 1: Confirm the existing tests pass (safety net before refactor)**

Run: `cd App && xcodebuild test -project TrueISFEditor.xcodeproj -scheme TrueISFEditor -destination 'platform=macOS,arch=arm64' -derivedDataPath ./ddata-build 2>&1 | tail -5`
Expected: existing model tests (8) pass. (This is our regression guard for the refactor.)

- [ ] **Step 2: Create `PreviewEngine.swift`**

```swift
import AppKit

/// Shared surface implemented by both preview engines. The coordinator binds to
/// concrete engines (which keep their own @Published fields) and re-publishes state.
@MainActor
protocol PreviewEngine: AnyObject {
    var compileValid: Bool { get }
    var compileError: String? { get }
    var compileErrorLine: Int? { get }
    var inputs: [ISFPreviewInput] { get }
    var nsView: NSView { get }

    func load(isf: String)
    func setInput(_ name: String, _ jsonValue: String)
    func setRenderSize(width: Int?, height: Int?)

    /// Combine publisher the coordinator subscribes to so it can re-publish
    /// this engine's compile state. Implemented by exposing `objectWillChange`.
    var compileStateWillChange: ObservableObjectPublisher { get }
}
```

- [ ] **Step 3: Rename the file and conform the class**

```bash
cd App && git mv TrueISFEditor/ISFPreviewController.swift TrueISFEditor/WebKitPreviewController.swift
```
In `WebKitPreviewController.swift`: rename `final class ISFPreviewController` → `final class WebKitPreviewController`, add `, PreviewEngine` to its conformance list, and add the protocol's computed members:
```swift
    var nsView: NSView { webView }
    var compileStateWillChange: ObservableObjectPublisher { objectWillChange }
```
Keep `webView` public (the WebKit view host still needs it). Leave all existing behavior untouched.

- [ ] **Step 4: Update all references `ISFPreviewController` → `WebKitPreviewController`**

Run to find them: `cd App && grep -rln "ISFPreviewController" TrueISFEditor`
Replace each occurrence in `EditorViewModel.swift`, `OutputWindow.swift`, `Views/EditorScreen.swift`, `Views/PreviewControlsView.swift`, `TrueISFEditorApp.swift`. (Coordinator rebinding happens in Task 4; for now this is a pure rename so the app still compiles and behaves identically.)

- [ ] **Step 5: Regenerate, build, test**

Run: `cd App && xcodegen generate && xcodebuild test -project TrueISFEditor.xcodeproj -scheme TrueISFEditor -destination 'platform=macOS,arch=arm64' -derivedDataPath ./ddata-build 2>&1 | tail -5`
Expected: `BUILD SUCCEEDED`, existing tests still pass. App still previews via WebKit (unchanged).

- [ ] **Step 6: Commit**

```bash
cd App && git add -A
git commit -m "refactor(P1.5): extract PreviewEngine; rename ISFPreviewController -> WebKitPreviewController

Behavior-preserving. Introduces the protocol both engines will implement and
demotes the WebKit controller to one concrete engine. No functional change.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

### Task 4: Introduce `PreviewCoordinator` (single-engine for now) + a test fake

**Files:**
- Create: `App/TrueISFEditor/PreviewCoordinator.swift`
- Create: `App/TrueISFEditorTests/Fakes/FakePreviewEngine.swift`
- Create: `App/TrueISFEditorTests/PreviewCoordinatorTests.swift`
- Modify: `App/TrueISFEditor/EditorViewModel.swift`, `OutputWindow.swift`, `Views/EditorScreen.swift`, `Views/PreviewControlsView.swift`, `App/TrueISFEditor/ISFPreviewView.swift`
- Modify: `App/project.yml` (add new test sources)

- [ ] **Step 1: Write the failing coordinator test + fake engine**

`App/TrueISFEditorTests/Fakes/FakePreviewEngine.swift`:
```swift
import AppKit
import Combine
@testable import TrueISFEditor

@MainActor
final class FakePreviewEngine: PreviewEngine, ObservableObject {
    @Published var compileValid = false
    @Published var compileError: String?
    @Published var compileErrorLine: Int?
    @Published var inputs: [ISFPreviewInput] = []
    let view = NSView()
    var nsView: NSView { view }
    var compileStateWillChange: ObservableObjectPublisher { objectWillChange }

    private(set) var loadedISF: String?
    private(set) var lastInput: (String, String)?
    private(set) var lastRenderSize: (Int?, Int?)?
    func load(isf: String) { loadedISF = isf }
    func setInput(_ name: String, _ jsonValue: String) { lastInput = (name, jsonValue) }
    func setRenderSize(width: Int?, height: Int?) { lastRenderSize = (width, height) }

    func simulateCompile(valid: Bool, error: String?, line: Int?, inputs: [ISFPreviewInput]) {
        self.compileValid = valid; self.compileError = error
        self.compileErrorLine = line; self.inputs = inputs
        objectWillChange.send()
    }
}
```

`App/TrueISFEditorTests/PreviewCoordinatorTests.swift`:
```swift
import XCTest
import Combine
@testable import TrueISFEditor

@MainActor
final class PreviewCoordinatorTests: XCTestCase {
    func testForwardsLoadToActiveEngine() {
        let fake = FakePreviewEngine()
        let coord = PreviewCoordinator(metal: fake, webkit: FakePreviewEngine())
        coord.load(isf: "/*{}*/ void main(){}")
        XCTAssertEqual(fake.loadedISF, "/*{}*/ void main(){}")
    }

    func testRepublishesActiveEngineCompileState() {
        let fake = FakePreviewEngine()
        let coord = PreviewCoordinator(metal: fake, webkit: FakePreviewEngine())
        fake.simulateCompile(valid: true, error: nil, line: nil, inputs: [])
        XCTAssertTrue(coord.compileValid)
    }

    func testToggleReloadsCurrentSourceOnNewEngine() {
        let metal = FakePreviewEngine(); let webkit = FakePreviewEngine()
        let coord = PreviewCoordinator(metal: metal, webkit: webkit)
        coord.load(isf: "SRC")
        coord.active = .webkit
        XCTAssertEqual(webkit.loadedISF, "SRC")
    }
}
```

- [ ] **Step 2: Add the test sources to `project.yml` and run the test (expect FAIL)**

Add to the `TrueISFEditorTests` target `sources` list in `App/project.yml`:
```yaml
      - TrueISFEditorTests/Fakes/FakePreviewEngine.swift
      - TrueISFEditorTests/PreviewCoordinatorTests.swift
      - TrueISFEditor/PreviewEngine.swift
      - TrueISFEditor/PreviewCoordinator.swift
```
Run: `cd App && xcodegen generate && xcodebuild test -project TrueISFEditor.xcodeproj -scheme TrueISFEditor -destination 'platform=macOS,arch=arm64' -derivedDataPath ./ddata-build 2>&1 | tail -15`
Expected: FAIL — `PreviewCoordinator` / its initializer don't exist yet (compile error).

- [ ] **Step 3: Implement `PreviewCoordinator.swift`**

```swift
import AppKit
import Combine

@MainActor
final class PreviewCoordinator: ObservableObject {
    enum Engine { case metal, webkit }

    @Published var active: Engine = .metal { didSet { switchEngine() } }
    @Published private(set) var compileValid = false
    @Published private(set) var compileError: String?
    @Published private(set) var compileErrorLine: Int?
    @Published private(set) var inputs: [ISFPreviewInput] = []

    private let metal: PreviewEngine
    private let webkit: PreviewEngine
    private var currentSource: String?
    private var currentRenderSize: (Int?, Int?) = (nil, nil)
    private var sub: AnyCancellable?

    init(metal: PreviewEngine, webkit: PreviewEngine) {
        self.metal = metal; self.webkit = webkit
        subscribe()
    }

    var activeEngine: PreviewEngine { active == .metal ? metal : webkit }
    var nsView: NSView { activeEngine.nsView }

    func load(isf: String) { currentSource = isf; activeEngine.load(isf: isf) }
    func setInput(_ name: String, _ jsonValue: String) { activeEngine.setInput(name, jsonValue) }
    func setRenderSize(width: Int?, height: Int?) {
        currentRenderSize = (width, height)
        activeEngine.setRenderSize(width: width, height: height)
    }

    private func subscribe() {
        sub = activeEngine.compileStateWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.mirror() }
        mirror()
    }
    private func mirror() {
        compileValid = activeEngine.compileValid
        compileError = activeEngine.compileError
        compileErrorLine = activeEngine.compileErrorLine
        inputs = activeEngine.inputs
    }
    private func switchEngine() {
        subscribe()
        activeEngine.setRenderSize(width: currentRenderSize.0, height: currentRenderSize.1)
        if let s = currentSource { activeEngine.load(isf: s) }
        objectWillChange.send()
    }
}
```

> Note: the `mirror()` after `objectWillChange.send()` in the fake fires synchronously enough for the test; if `testRepublishesActiveEngineCompileState` flakes on `receive(on:)` timing, change the fake's publisher subscription in the coordinator test to assert after a `RunLoop.main.run(until:)` tick, or have `subscribe()` use `.sink` without `receive(on:)` for the fake. Keep `receive(on: RunLoop.main)` in production for thread-safety.

- [ ] **Step 4: Run the coordinator tests (expect PASS)**

Run: `cd App && xcodebuild test -project TrueISFEditor.xcodeproj -scheme TrueISFEditor -destination 'platform=macOS,arch=arm64' -derivedDataPath ./ddata-build -only-testing:TrueISFEditorTests/PreviewCoordinatorTests 2>&1 | tail -10`
Expected: 3 tests pass.

- [ ] **Step 5: Rebind the app to the coordinator (still WebKit-only until Metal exists)**

Temporarily construct the coordinator with WebKit in both slots so the app runs before `MetalPreviewController` exists:
- `EditorViewModel.swift`: replace `let preview = WebKitPreviewController()` with
  ```swift
  let preview = PreviewCoordinator(metal: WebKitPreviewController(), webkit: WebKitPreviewController())
  ```
  (Metal slot becomes the real `MetalPreviewController()` in Task 8.) Update the Combine pipe at `EditorViewModel.swift:53` to observe `preview.$compileError` / `$compileErrorLine` / `$compileValid` on the coordinator (same property names — should be a drop-in).
- `Views/EditorScreen.swift`: change `ISFPreviewView(webView: vm.preview.webView)` → `ISFPreviewView(coordinator: vm.preview)`; reads of `vm.preview.compileValid/compileError/compileErrorLine` are unchanged.
- `Views/PreviewControlsView.swift`: change `@ObservedObject var controller: ISFPreviewController` → `@ObservedObject var coordinator: PreviewCoordinator`; update `.inputs` reads and `setInput` calls to `coordinator.*`.
- `OutputWindow.swift`: replace its `WebKitPreviewController()` with a `PreviewCoordinator(metal: WebKitPreviewController(), webkit: WebKitPreviewController())`; route `load`/`setRenderSize` through it; host `coordinator.nsView`.

- [ ] **Step 6: Generalize `ISFPreviewView` to host the coordinator's nsView**

`App/TrueISFEditor/ISFPreviewView.swift`:
```swift
import SwiftUI

struct ISFPreviewView: NSViewRepresentable {
    @ObservedObject var coordinator: PreviewCoordinator
    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        embed(coordinator.nsView, in: container)
        return container
    }
    func updateNSView(_ nsView: NSView, context: Context) {
        // Swap hosted subview if the active engine's view changed (toggle).
        if nsView.subviews.first !== coordinator.nsView {
            nsView.subviews.forEach { $0.removeFromSuperview() }
            embed(coordinator.nsView, in: nsView)
        }
    }
    private func embed(_ v: NSView, in container: NSView) {
        v.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(v)
        NSLayoutConstraint.activate([
            v.topAnchor.constraint(equalTo: container.topAnchor),
            v.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            v.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            v.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])
    }
}
```

- [ ] **Step 7: Regenerate, build, test, launch**

Run: `cd App && xcodegen generate && xcodebuild test -project TrueISFEditor.xcodeproj -scheme TrueISFEditor -destination 'platform=macOS,arch=arm64' -derivedDataPath ./ddata-build 2>&1 | tail -8`
Expected: `BUILD SUCCEEDED`, all tests pass. Launch the app; confirm preview still works (via WebKit through the coordinator), library loads, controls + gutter behave as before.

- [ ] **Step 8: Commit**

```bash
cd App && git add -A
git commit -m "feat(P1.5): PreviewCoordinator wraps engines; app binds to it (WebKit-only)

Coordinator owns both engine slots, forwards calls, re-publishes compile state,
and vends the active nsView. App/editor/controls/pop-out rebound to it. Metal
slot is still WebKit until MetalPreviewController lands. TDD: 3 coordinator tests.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Phase D — MetalPreviewController (TDD against ISFMSLKit)

> **Before Task 5:** read the vendored headers and record the REAL symbols.
> Run: `ls vendor/prebuilt/ISFMSLKit.framework/Headers/` then open `ISFMSLScene.h` and `ISFMSLSceneVal.h`.
> Write the actual init/load/render/inputs/error selectors into a scratch note. The code below uses the
> skill-draft names as the expected shape — substitute the real ones where they differ.

### Task 5: Metal engine — setup, load, compile-state mapping

**Files:**
- Create: `App/TrueISFEditor/MetalPreviewController.swift`
- Create: `App/TrueISFEditor/MetalPreviewView.swift`
- Create: `App/TrueISFEditorTests/MetalPreviewControllerTests.swift`
- Modify: `App/project.yml` (add MetalPreviewController.swift to test target sources)

- [ ] **Step 1: Write the failing compile-state test**

`App/TrueISFEditorTests/MetalPreviewControllerTests.swift`:
```swift
import XCTest
@testable import TrueISFEditor

@MainActor
final class MetalPreviewControllerTests: XCTestCase {
    // Minimal valid ISF generator.
    let goodISF = """
    /*{ "DESCRIPTION": "t", "ISFVSN": "2", "INPUTS": [] }*/
    void main() { gl_FragColor = vec4(1.0); }
    """
    // ES3 dynamic-loop pattern WebGL1 rejects but ISFMSLKit accepts.
    let es3ISF = """
    /*{ "DESCRIPTION": "t", "ISFVSN": "2", "INPUTS": [{"NAME":"n","TYPE":"long","DEFAULT":4}] }*/
    void main() { vec3 c=vec3(0.0); for (int i=0;i<int(n);i++){ c+=vec3(0.1); } gl_FragColor=vec4(c,1.0); }
    """

    func testGoodISFCompiles() async throws {
        let c = MetalPreviewController()
        c.load(isf: goodISF)
        try await waitUntil { c.compileValid == true }
        XCTAssertTrue(c.compileValid)
        XCTAssertNil(c.compileError)
    }

    func testES3ISFCompiles() async throws {
        let c = MetalPreviewController()
        c.load(isf: es3ISF)
        try await waitUntil { c.compileValid == true }
        XCTAssertTrue(c.compileValid, "ISFMSLKit should accept ES3 dynamic loops")
    }

    func testBadISFReportsError() async throws {
        let c = MetalPreviewController()
        c.load(isf: "/*{ \"ISFVSN\":\"2\" }*/ void main(){ this is not glsl }")
        try await waitUntil { c.compileError != nil }
        XCTAssertFalse(c.compileValid)
        XCTAssertNotNil(c.compileError)
    }

    // Poll helper — load is async (off-main transpile).
    private func waitUntil(timeout: TimeInterval = 10, _ cond: @escaping () -> Bool) async throws {
        let start = Date()
        while !cond() {
            if Date().timeIntervalSince(start) > timeout { XCTFail("timed out"); return }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
    }
}
```

- [ ] **Step 2: Add sources, run test (expect FAIL — type missing)**

Add `TrueISFEditor/MetalPreviewController.swift` and `TrueISFEditorTests/MetalPreviewControllerTests.swift` to the test target sources in `project.yml`. Run:
`cd App && xcodegen generate && xcodebuild test -project TrueISFEditor.xcodeproj -scheme TrueISFEditor -destination 'platform=macOS,arch=arm64' -derivedDataPath ./ddata-build -only-testing:TrueISFEditorTests/MetalPreviewControllerTests 2>&1 | tail -12`
Expected: FAIL — `MetalPreviewController` undefined.

- [ ] **Step 3: Implement setup + load + compile mapping**

`App/TrueISFEditor/MetalPreviewController.swift` (substitute real selectors from the headers):
```swift
import AppKit
import Combine
import Metal
import MetalKit

@MainActor
final class MetalPreviewController: NSObject, ObservableObject, PreviewEngine {
    @Published private(set) var compileValid = false
    @Published private(set) var compileError: String?
    @Published private(set) var compileErrorLine: Int?
    @Published private(set) var inputs: [ISFPreviewInput] = []

    private let mtkView = MTKView()
    var nsView: NSView { mtkView }
    var compileStateWillChange: ObservableObjectPublisher { objectWillChange }

    private let device: MTLDevice
    private var scene: ISFMSLScene?           // <- confirm type name in headers
    private let transpileQueue = DispatchQueue(label: "isfmsl.transpile", qos: .userInitiated)
    private var tempURL: URL

    override init() {
        // One-time ISFMSLKit setup (skill draft §6). Confirm exact API in headers.
        let props = RenderProperties.global()
        self.device = props.device
        let cacheDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TrueISFEditor/ISFMSLCache")
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        ISFMSLCache.primary = ISFMSLCache(directoryURL: cacheDir)
        VVMTLPool.global = VVMTLPool(device: device)
        self.tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("trueisf-live-\(UUID().uuidString).fs")
        super.init()
        mtkView.device = device
        mtkView.isPaused = false
        mtkView.enableSetNeedsDisplay = false
        mtkView.framebufferOnly = false
    }

    func load(isf: String) {
        // Off-main transpile (first-sight latency must not block UI).
        let url = tempURL
        transpileQueue.async { [weak self] in
            guard let self else { return }
            do { try isf.write(to: url, atomically: true, encoding: .utf8) } catch { return }
            let s = ISFMSLScene(device: self.device)   // confirm init signature
            s.load(url)                                 // confirm load selector; prefer string-load if present
            let err = s.compilerError                   // confirm property
            Task { @MainActor in self.applyCompile(scene: s, error: err) }
        }
    }

    private func applyCompile(scene s: ISFMSLScene, error: Any?) {
        if let err = error {
            self.compileValid = false
            let (msg, line) = Self.parseError(err)
            self.compileError = msg; self.compileErrorLine = line
            self.scene = nil
            // clear-on-fail (preserve P0 behavior): blank the view on next draw
            self.mtkView.setNeedsDisplay(self.mtkView.bounds)
        } else {
            self.scene = s
            self.compileValid = true
            self.compileError = nil; self.compileErrorLine = nil
            self.inputs = Self.mapInputs(s.inputs)      // implemented in Task 6
        }
    }

    static func parseError(_ raw: Any?) -> (String?, Int?) {
        // ISFMSLScene.compilerError shape TBD-from-headers; default: stringify, no line.
        guard let raw else { return (nil, nil) }
        let msg = String(describing: raw)
        // If the message contains "ERROR: 0:NN:", extract NN as the line.
        if let r = msg.range(of: #"0:(\d+):"#, options: .regularExpression) {
            let digits = msg[r].dropFirst(2).dropLast()
            return (msg, Int(digits))
        }
        return (msg, nil)
    }

    // Stubs filled in Task 6 so this file compiles now:
    static func mapInputs(_ attribs: Any?) -> [ISFPreviewInput] { [] }
    func setInput(_ name: String, _ jsonValue: String) { /* Task 6 */ }
    func setRenderSize(width: Int?, height: Int?) { /* Task 7 */ }
}
```

> If `ISFMSLScene` needs a non-empty `inputs` to compile-detect, the `testES3ISFCompiles` long input `n` is included for that reason. Adjust selector names to the headers; do not invent properties not present.

- [ ] **Step 4: Run the Metal tests (expect PASS)**

Run: `cd App && xcodebuild test -project TrueISFEditor.xcodeproj -scheme TrueISFEditor -destination 'platform=macOS,arch=arm64' -derivedDataPath ./ddata-build -only-testing:TrueISFEditorTests/MetalPreviewControllerTests 2>&1 | tail -12`
Expected: `testGoodISFCompiles`, `testES3ISFCompiles`, `testBadISFReportsError` pass. If `testES3ISFCompiles` fails, the ES3 acceptance premise is wrong — STOP and re-verify against actual ISFMSLKit behavior before continuing (this is the core hypothesis of P1.5).

- [ ] **Step 5: Commit**

```bash
cd App && git add -A
git commit -m "feat(P1.5): MetalPreviewController setup + load + compile-state mapping (TDD)

ISFMSLKit scene setup (cache/pool/device), off-main transpile, compilerError ->
compileError/line. TDD: good ISF compiles, ES3 dynamic-loop compiles (the core
P1.5 win), bad ISF reports error.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

### Task 6: Inputs parsing + setInput

**Files:**
- Modify: `App/TrueISFEditor/MetalPreviewController.swift`
- Modify: `App/TrueISFEditorTests/MetalPreviewControllerTests.swift`

- [ ] **Step 1: Write the failing inputs test**

Add to `MetalPreviewControllerTests`:
```swift
    func testParsesInputs() async throws {
        let isf = """
        /*{ "ISFVSN":"2", "INPUTS":[
          {"NAME":"level","TYPE":"float","DEFAULT":0.5,"MIN":0.0,"MAX":1.0},
          {"NAME":"on","TYPE":"bool","DEFAULT":true},
          {"NAME":"tint","TYPE":"color","DEFAULT":[1,0,0,1]}
        ]}*/
        void main(){ gl_FragColor = tint * level * (on?1.0:0.0); }
        """
        let c = MetalPreviewController()
        c.load(isf: isf)
        try await waitUntil { c.inputs.count == 3 }
        XCTAssertEqual(Set(c.inputs.map { $0.name }), ["level","on","tint"])
        XCTAssertEqual(c.inputs.first { $0.name == "level" }?.type, "float")
    }
```

- [ ] **Step 2: Run (expect FAIL — inputs empty)**

Run: `cd App && xcodebuild test ... -only-testing:TrueISFEditorTests/MetalPreviewControllerTests/testParsesInputs 2>&1 | tail -8`
Expected: FAIL — `c.inputs.count` stays 0 (stub returns `[]`).

- [ ] **Step 3: Implement `mapInputs` and `setInput`**

Replace the Task-5 stubs. Use the real `ISFMSLSceneAttrib` / `ISFValType` / `ISFMSLSceneVal` from headers:
```swift
    static func mapInputs(_ attribs: Any?) -> [ISFPreviewInput] {
        guard let attribs = attribs as? [ISFMSLSceneAttrib] else { return [] }
        return attribs.map { a in
            let type: String
            switch a.type.rawValue {   // ISFValType: 1 Event 2 Bool 3 Long 4 Float 5 Point2D 6 Color
            case 1: type = "event"; case 2: type = "bool"; case 3: type = "long"
            case 4: type = "float"; case 5: type = "point2D"; case 6: type = "color"
            default: type = "float"
            }
            return ISFPreviewInput(
                name: a.name, type: type,
                defaultValue: a.currentVal?.doubleValue,
                min: a.minVal?.doubleValue, max: a.maxVal?.doubleValue,
                labels: a.labelArray as? [String],
                values: (a.valArray as? [NSNumber])?.map { $0.doubleValue })
        }
    }

    func setInput(_ name: String, _ jsonValue: String) {
        guard let scene = scene else { return }
        guard let data = jsonValue.data(using: .utf8) else { return }
        let json = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        let val: ISFMSLSceneVal
        switch json {
        case let b as Bool: val = ISFMSLSceneVal.create(with: b)
        case let arr as [Any] where arr.count == 2:
            val = ISFMSLSceneVal.create(withPoint2D: CGPoint(x: (arr[0] as? Double) ?? 0,
                                                             y: (arr[1] as? Double) ?? 0))
        case let arr as [Any] where arr.count == 4:
            let c = NSColor(red: (arr[0] as? Double).map { CGFloat($0) } ?? 0,
                            green: (arr[1] as? Double).map { CGFloat($0) } ?? 0,
                            blue: (arr[2] as? Double).map { CGFloat($0) } ?? 0,
                            alpha: (arr[3] as? Double).map { CGFloat($0) } ?? 1)
            val = ISFMSLSceneVal.create(with: c)
        case let n as NSNumber:
            // long inputs arrive as ints; treat integral as long, else float
            if CFNumberIsFloatType(n) { val = ISFMSLSceneVal.create(withFloat: n.floatValue) }
            else { val = ISFMSLSceneVal.create(withLong: n.intValue) }
        default: return
        }
        scene.setValue(val, forInputNamed: name)   // confirm selector
    }
```

> **iMouse:** ISF mouse is delivered by the host, not as a user INPUT, so it won't appear in `inputs`. Preserve the P0 behavior by setting the scene's mouse to a centered, "pressed" position. Find the mouse-set selector in the headers (e.g. a render-pass mouse property) and apply it once per render in Task 7; if ISFMSLKit auto-supplies iMouse from the MTKView, wire mouse events through instead. Note the chosen mechanism in the commit.

- [ ] **Step 4: Run (expect PASS)**

Run: `cd App && xcodebuild test ... -only-testing:TrueISFEditorTests/MetalPreviewControllerTests/testParsesInputs 2>&1 | tail -8`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
cd App && git add -A
git commit -m "feat(P1.5): MetalPreviewController inputs parsing + setInput (TDD)

ISFMSLSceneAttrib -> ISFPreviewInput (same struct the controls panel consumes);
setInput decodes the controls-panel JSON into ISFMSLSceneVal per type. iMouse
mapping: <mechanism>.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

### Task 7: Render path — MTKView delegate, target texture, setRenderSize, clear-on-fail

**Files:**
- Modify: `App/TrueISFEditor/MetalPreviewController.swift`
- Create: `App/TrueISFEditorTests/MetalPreviewControllerTests.swift` (add a render-produces-texture test)

- [ ] **Step 1: Write the failing render test**

Add to `MetalPreviewControllerTests`:
```swift
    func testRendersTextureForGoodShader() async throws {
        let c = MetalPreviewController()
        c.setRenderSize(width: 64, height: 64)
        c.load(isf: goodISF)
        try await waitUntil { c.compileValid }
        let tex = c.renderOnce()           // test hook: render a single frame, return the texture
        XCTAssertNotNil(tex)
        XCTAssertEqual(tex?.width, 64)
    }
```

- [ ] **Step 2: Run (expect FAIL — renderOnce missing)**

Expected: compile error / FAIL.

- [ ] **Step 3: Implement the render path + `renderOnce` test hook**

Add to `MetalPreviewController`:
```swift
    private var renderSize: MTLSize?    // explicit target; nil = fit to view backing
    private let commandQueue: MTLCommandQueue

    // in init(): self.commandQueue = device.makeCommandQueue()!   (add this line)

    func setRenderSize(width: Int?, height: Int?) {
        if let w = width, let h = height, w > 0, h > 0 {
            renderSize = MTLSize(width: w, height: h, depth: 1)
        } else { renderSize = nil }
        mtkView.setNeedsDisplay(mtkView.bounds)
    }

    private func targetSize() -> MTLSize {
        if let r = renderSize { return r }
        let s = mtkView.drawableSize
        return MTLSize(width: max(Int(s.width), 1), height: max(Int(s.height), 1), depth: 1)
    }

    /// Render one frame into a texture (also used by the MTKView delegate). Returns nil if no scene.
    @discardableResult
    func renderOnce() -> MTLTexture? {
        guard let scene = scene, let cb = commandQueue.makeCommandBuffer() else { return nil }
        let size = targetSize()
        // Confirm exact selector: createAndRender(toTextureSized:in:) -> result with .texture
        let result = scene.createAndRender(toTextureSized: size, in: cb)
        cb.commit()
        return result?.texture
    }
```
Make the controller the MTKView delegate. Add:
```swift
    // in init(): mtkView.delegate = self  (and declare conformance)
```
and an extension:
```swift
extension MetalPreviewController: MTKViewDelegate {
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable else { return }
        guard let tex = renderOnce() else {
            // clear-on-fail: present a blank drawable
            if let cb = commandQueue.makeCommandBuffer(),
               let rpd = view.currentRenderPassDescriptor {
                rpd.colorAttachments[0].loadAction = .clear
                rpd.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
                cb.makeRenderCommandEncoder(descriptor: rpd)?.endEncoding()
                cb.present(drawable); cb.commit()
            }
            return
        }
        // Blit the rendered texture into the drawable.
        if let cb = commandQueue.makeCommandBuffer(), let blit = cb.makeBlitCommandEncoder() {
            let w = min(tex.width, drawable.texture.width)
            let h = min(tex.height, drawable.texture.height)
            blit.copy(from: tex, sourceSlice: 0, sourceLevel: 0,
                      sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                      sourceSize: MTLSize(width: w, height: h, depth: 1),
                      to: drawable.texture, destinationSlice: 0, destinationLevel: 0,
                      destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0))
            blit.endEncoding()
            cb.present(drawable); cb.commit()
        }
    }
}
```
> If the rendered texture size ≠ drawable size and a 1:1 blit looks wrong (letterboxing/scale), render through a textured quad instead of a blit. Start with blit (simplest); switch to a fullscreen-quad draw only if Fit scaling needs it. Note which was used.

- [ ] **Step 4: Run (expect PASS)**

Run: `cd App && xcodebuild test ... -only-testing:TrueISFEditorTests/MetalPreviewControllerTests/testRendersTextureForGoodShader 2>&1 | tail -8`
Expected: PASS (texture 64×64, non-nil).

- [ ] **Step 5: On-device visual check (manual, single change)**

Build + launch. Load a known shader via the library. Confirm: it renders (not black), animates, and the output-dimensions control (Fit / 320×240 / ÷2 / ×2) changes the render target. Per the render-path rule: this is ONE change; if black, revert before stacking. Do NOT claim "relaunch" until the `.debug.dylib` grep confirms the staged binary is fresh.

- [ ] **Step 6: Commit**

```bash
cd App && git add -A
git commit -m "feat(P1.5): MetalPreviewController render path (MTKView, target texture, clear-on-fail)

createAndRender -> texture blitted into the drawable; setRenderSize drives the
target texture (Fit/WxH/÷2/×2); failed compile presents a blank drawable (P0
clear-on-fail parity). Main-thread self-driving MTKView; off-main render deferred.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Phase E — Wire Metal Into the Coordinator + Toggle UI

### Task 8: Activate Metal as primary; add the Metal|WebKit toggle

**Files:**
- Modify: `App/TrueISFEditor/EditorViewModel.swift`, `OutputWindow.swift`, `Views/EditorScreen.swift`
- Modify: `App/TrueISFEditorTests/PreviewCoordinatorTests.swift` (real-engine toggle smoke)

- [ ] **Step 1: Put the real Metal engine in the coordinator's metal slot**

In `EditorViewModel.swift`, change the coordinator construction to:
```swift
let preview = PreviewCoordinator(metal: MetalPreviewController(), webkit: WebKitPreviewController())
```
Same in `OutputWindow.swift`. Default `active` is already `.metal`.

- [ ] **Step 2: Add the renderer toggle to the preview toolbar**

In `Views/EditorScreen.swift`, near the output-dimensions control, add:
```swift
Picker("Renderer", selection: $vm.preview.active) {
    Text("Metal").tag(PreviewCoordinator.Engine.metal)
    Text("WebKit").tag(PreviewCoordinator.Engine.webkit)
}
.pickerStyle(.segmented)
.frame(width: 160)
.help("Metal = VDMX-fidelity (ES3). WebKit = legacy WebGL1 fallback.")
```
(Pop-out `OutputWindow` mirrors the editor's engine by default — Open Question §10.1; no separate toggle unless requested.)

- [ ] **Step 3: Build, launch, manually verify the toggle**

Build + launch. Confirm: app opens with **Metal** preview; loading an `AR_*.fs` that previously failed in WebKit now renders. Flip to **WebKit** → same shader either renders (if WebGL1-compatible) or shows its WebGL error; flip back to **Metal** → renders again. The current source reloads on each switch; no crash, no frozen frame.

- [ ] **Step 4: Add a real-engine toggle smoke test**

```swift
    func testRealEnginesToggleWithoutCrash() async throws {
        let coord = PreviewCoordinator(metal: MetalPreviewController(), webkit: WebKitPreviewController())
        coord.load(isf: "/*{ \"ISFVSN\":\"2\" }*/ void main(){ gl_FragColor=vec4(1.0); }")
        coord.active = .webkit
        coord.active = .metal
        XCTAssertEqual(coord.active, .metal)
    }
```
Run it (expect PASS).

- [ ] **Step 5: Remove the Task-2 temporary smoke print**

Delete the `// P1.5 smoke:` line from `TrueISFEditorApp.swift`. Build to confirm still green.

- [ ] **Step 6: Commit**

```bash
cd App && git add -A
git commit -m "feat(P1.5): activate Metal as primary preview + Metal|WebKit toggle

Coordinator's metal slot is now the real MetalPreviewController; default engine
is Metal. Segmented renderer toggle in the preview toolbar; pop-out mirrors the
editor engine. Removed temporary link-smoke print.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Phase F — Acceptance: Corpus Render-Test

### Task 9: Headless corpus render-test over the AR_*.fs library

**Files:**
- Create: `App/TrueISFEditorTests/CorpusRenderTests.swift`
- Modify: `App/project.yml` (add to test sources)

- [ ] **Step 1: Write the corpus harness test**

`App/TrueISFEditorTests/CorpusRenderTests.swift`:
```swift
import XCTest
@testable import TrueISFEditor

@MainActor
final class CorpusRenderTests: XCTestCase {
    // Opt-in: this walks ~1057 files and is slow. Run explicitly.
    // Enable by setting env CORPUS=1 in the test action.
    func testCorpusCompilePassRate() async throws {
        guard ProcessInfo.processInfo.environment["CORPUS"] == "1" else {
            throw XCTSkip("Set CORPUS=1 to run the full corpus render-test")
        }
        let dir = URL(fileURLWithPath: "/Library/Graphics/ISF")
        let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("AR_") && $0.pathExtension == "fs" }
        XCTAssertGreaterThan(files.count, 500)

        var metalPass = 0, metalFail: [(String,String)] = []
        let c = MetalPreviewController()
        for f in files {
            guard let src = try? String(contentsOf: f, encoding: .utf8) else { continue }
            c.load(isf: src)
            let ok = await pollCompile(c, timeout: 8)
            if ok { metalPass += 1 } else { metalFail.append((f.lastPathComponent, c.compileError ?? "?")) }
        }
        let report = """
        CORPUS RESULT — Metal engine
        total: \(files.count)  pass: \(metalPass)  fail: \(metalFail.count)
        --- failures ---
        \(metalFail.map { "\($0.0): \($0.1)" }.joined(separator: "\n"))
        """
        // Write report next to the repo for inspection.
        let out = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("corpus-report.txt")
        try? report.write(to: out, atomically: true, encoding: .utf8)
        print(report); print("report written: \(out.path)")
        // Gate: Metal must pass the large majority. Tune threshold after first run.
        XCTAssertGreaterThan(metalPass, Int(Double(files.count) * 0.9), "Metal pass-rate < 90%")
    }

    private func pollCompile(_ c: MetalPreviewController, timeout: TimeInterval) async -> Bool {
        let start = Date()
        while Date().timeIntervalSince(start) < timeout {
            if c.compileValid { return true }
            if c.compileError != nil { return false }
            try? await Task.sleep(nanoseconds: 30_000_000)
        }
        return false
    }
}
```

- [ ] **Step 2: Add to test sources, run the corpus test**

Add `TrueISFEditorTests/CorpusRenderTests.swift` to `project.yml` test sources. Run with the env flag:
`cd App && xcodegen generate && CORPUS=1 xcodebuild test -project TrueISFEditor.xcodeproj -scheme TrueISFEditor -destination 'platform=macOS,arch=arm64' -derivedDataPath ./ddata-build -only-testing:TrueISFEditorTests/CorpusRenderTests 2>&1 | tail -40`
Expected: prints the pass/fail counts and a report path. Read the failures.

- [ ] **Step 3: Triage failures, capture the number**

Read `corpus-report.txt`. Categorize failures: (a) genuinely malformed shaders (acceptable fails), (b) multipass/persistent-buffer shaders the single-scene path doesn't drive (note as known-limitation if any), (c) real engine bugs (fix or file follow-up). Confirm the WebKit-rejected ES3 set is in the pass column. Tune the 0.9 threshold to the real baseline if justified, documenting why in the commit.

- [ ] **Step 4: Commit the harness + result**

```bash
cd App && git add -A
git commit -m "test(P1.5): corpus render-test over AR_*.fs (acceptance gate)

Headless harness loads all ~1057 AR_*.fs through MetalPreviewController and
asserts pass-rate. First run: <pass>/<total>; ES3-rejected-by-WebKit shaders now
pass. Known fails: <summary>.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Phase G — License Gate & Cleanup

### Task 10: glslang GPL-3 runtime-path check

**Files:**
- Create: `docs/superpowers/notes/2026-06-09-isfmslkit-license-check.md`

- [ ] **Step 1: Inspect the app's linked + embedded runtime dylibs**

Run:
```bash
APP=App/ddata-build/Build/Products/Debug/TrueISFEditor.app
otool -L "$APP/Contents/MacOS/TrueISFEditor" | sed -n '1,40p'
ls -R "$APP/Contents/Frameworks/ISFMSLKit.framework/Versions/A/Frameworks/"
```
Identify whether `libGLSLangValidatorLib` / glslang code is loaded at runtime (embedded in ISFMSLKit.framework) or only used as a build tool.

- [ ] **Step 2: Determine glslang's license for the embedded component**

Check glslang's license terms for the specific component ISFMSLKit links. glslang core is Apache-2.0/BSD; verify whether any GPL-3 piece (if present) is confined to a build-only tool vs. the linked transpiler dylib. Record the finding and the source (glslang LICENSE files / ISFMSLKit's notes).

- [ ] **Step 3: Write the finding doc**

`docs/superpowers/notes/2026-06-09-isfmslkit-license-check.md`: record (a) which transpiler dylibs are embedded/loaded at runtime, (b) each one's license, (c) conclusion: clear / not-clear for commercial distribution, (d) any action needed (e.g., swap to a permissively-licensed transpile path, or ship transpile as a separate process). This is a **distribution gate**, not a development blocker.

- [ ] **Step 4: Commit**

```bash
git add docs/superpowers/notes/2026-06-09-isfmslkit-license-check.md
git commit -m "docs(P1.5): glslang/ISFMSLKit runtime-path license check

Documents which transpiler dylibs are loaded at runtime and their licenses;
conclusion for commercial distribution: <clear|needs-action>.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

### Task 11: Final integration pass + cleanup

- [ ] **Step 1: Full test suite + build green**

Run: `cd App && xcodebuild test -project TrueISFEditor.xcodeproj -scheme TrueISFEditor -destination 'platform=macOS,arch=arm64' -derivedDataPath ./ddata-build 2>&1 | tail -8`
Expected: all tests pass (model 8 + coordinator 3 + metal 4 + toggle 1; corpus is CORPUS-gated/skipped). `BUILD SUCCEEDED`.

- [ ] **Step 2: Manual end-to-end smoke (the human-hands pass)**

Launch the staged app (after `.debug.dylib` freshness grep). Verify: library loads; click an ES3 `AR_*.fs` that failed before → renders on Metal; edit it live → recompiles; controls drive inputs; gutter shows errors on a bad edit; Save works; pop-out output mirrors; output dimensions work; toggle Metal↔WebKit works.

- [ ] **Step 3: Manual inline Mechanic review (CoS, not subagent)**

Per project rule for native Swift/Metal: the CoS reads the changed files and audits — null safety, the off-main transpile `Task { @MainActor }` hops, the blit bounds, retain cycles in the Combine subscription, drawable presentation correctness. Fix anything flagged.

- [ ] **Step 4: Update the renderer memory**

Update memory `trueisfeditor-renderer-isfmslkit` to reflect that the native engine is implemented and primary, with the corpus pass-rate and any known limitations (e.g., multipass).

- [ ] **Step 5: Final commit (if cleanup changes were made)**

```bash
cd App && git add -A
git commit -m "chore(P1.5): final integration cleanup after Mechanic review

<summary of fixes>

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Self-Review (spec coverage)

- Spec §1 goal / non-goals → Tasks 1–8 (Metal primary, WebKit fallback toggle); Syphon excluded (Task 1 Step 5); off-main deferred (Task 7 Step 3 note). ✔
- Spec §2 acceptance (corpus, spot-check, toggle, no regressions, build hygiene, license) → Task 9 (corpus), Task 7/11 (spot-check), Task 8 (toggle), Task 3/4/11 (no regressions), Task 1–2/11 (build hygiene), Task 10 (license). ✔
- Spec §3 engine seam (PreviewEngine, PreviewCoordinator, view layer) → Tasks 3, 4. ✔
- Spec §4 vendoring/build (script, project.yml, bridge) → Tasks 1, 2. ✔
- Spec §5 Metal internals (setup, load, inputs, render, iMouse) → Tasks 5, 6, 7. ✔
- Spec §6 error handling/latency/clear-on-fail → Task 5 (error/latency), Task 7 (clear-on-fail). ✔
- Spec §7 render-loop phasing (main first, off-main deferred) → Task 7 Step 3 note. ✔
- Spec §8 testing → Tasks 4, 5, 6, 7, 9. ✔
- Spec §10 open questions (pop-out toggle, hardened runtime, string vs URL load) → Task 8 Step 2 (pop-out mirrors), Task 2 Step 4 (hardened runtime), Task 5 header note (load mode). ✔
- Spec §11 risks → mitigations embedded in Tasks 1 (signing), 5 (selectors/latency), 7 (black screen), 10 (license). ✔

**Type consistency:** `PreviewEngine` (compileValid/compileError/compileErrorLine/inputs/nsView/load/setInput/setRenderSize/compileStateWillChange) is identical across the protocol (Task 3), fake (Task 4), WebKit conformance (Task 3), and Metal conformance (Tasks 5–7). `PreviewCoordinator(metal:webkit:)` initializer is used identically in Tasks 4 and 8. `ISFPreviewInput` fields match the existing struct in `ISFPreviewController.swift`. `renderOnce()` defined in Task 7 and used by the corpus test in Task 9 reads only `compileValid`/`compileError` (no dependency on the test hook). ✔

**Known header-dependent substitutions (intentional, not placeholders):** exact ISFMSLKit selector names in Tasks 5–7 are flagged for header verification at the top of Phase D — the code gives the expected skill-draft shape and each call site names the property to confirm. This is a real constraint of integrating a third-party Obj-C++ framework, not an unfilled gap.
