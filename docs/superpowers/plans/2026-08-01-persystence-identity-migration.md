# PERSYSTENCE Identity Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rename the native ARShader application to PERSYSTENCE across its live product, source, build, test, installation, and forward-documentation surfaces while preserving macOS permissions, persisted layout state, and historical evidence.

**Architecture:** Centralize every user-facing identity string in a small `ProductIdentity` namespace, then rename the Xcode targets, schemes, source directories, test directories, executable, and installed application around that authority. Keep the existing `com.arsonrivvers.ARShader` bundle identifier as an intentional compatibility anchor so the signed application retains its TCC identity and UserDefaults domain; migrate the one legacy preference key inside that domain. Historical specs and smoke reports remain unchanged, while new documents use PERSYSTENCE terminology.

**Tech Stack:** Swift 5, SwiftUI, AppKit, XCTest, XcodeGen, `xcodebuild`, zsh/bash, macOS code signing and TCC.

## Global Constraints

- Canonical product name: `PERSYSTENCE`.
- Displayed wordmark: `PER·SYS·TENCE`.
- Descriptor: `Visual Memory Apparatus`.
- Bundle-safe implementation form: `Persystence`.
- Internal temporal-memory engine name: `REMNANCE`; do not apply this name to existing caches, persistence stores, or render code.
- Preserve `com.arsonrivvers.ARShader` as the bundle identifier in this migration. It is a compatibility identifier, not public product language.
- Preserve the signed application identity and existing camera permission behavior.
- Preserve data stored under `ARShader.surfaceArrangement`, migrate it once to `Persystence.surfaceArrangement`, and prefer the new key thereafter.
- Historical documents, completed plans, test reports, commit history, and legacy TouchDesigner references retain the name used when they were written.
- New product prose uses `PERSYSTENCE`; major visual display uses `PER·SYS·TENCE`; Swift and filesystem identifiers use `Persystence`.
- Do not claim that REMNANCE capabilities exist. This plan reserves the name but builds no temporal-memory engine.
- Do not design or introduce a logo or app icon in this slice. The typographic wordmark is the only visual identity artifact in scope.
- The `.worktrees/m2-slot-bank` branch must be merged or explicitly retired before execution because it modifies the same app and test directories this plan renames.
- Preserve the operator's unrelated modification to the prior-art dossier under `docs/arshader/`.

## File Structure

### New files

- `App/Persystence/ProductIdentity.swift`: one source of truth for public names, window titles, descriptor, and compatibility identifiers.
- `App/PersystenceTests/ProductIdentityTests.swift`: exact product-language contract tests.

### Renamed paths

- `App/ARShader/` → `App/Persystence/`
- `App/ARShaderTests/` → `App/PersystenceTests/`
- `App/Persystence/ARShaderApp.swift` → `App/Persystence/PersystenceApp.swift`
- `App/Persystence/ARShader-Bridging-Header.h` → `App/Persystence/Persystence-Bridging-Header.h`
- `App/Persystence/ARShader.entitlements` → `App/Persystence/Persystence.entitlements`
- `scripts/run-instrument.sh` → `scripts/run-persystence.sh`

### Modified files

- `App/project.yml`: rename targets and scheme, update source/test paths, product names, test host, bridging header, and entitlements; retain the legacy bundle identifiers.
- `App/Persystence/Info.plist`: user-visible bundle name and camera permission copy.
- `App/Persystence/PersystenceApp.swift`: entry type and window title.
- `App/Persystence/OutputWindowController.swift`: output-window title.
- `App/Persystence/SurfaceLayoutStore.swift`: new preference key plus one-time legacy read-through migration.
- `App/PersystenceTests/SurfaceLayoutStoreTests.swift`: migration, precedence, and cleanup coverage.
- `App/Persystence/Instrument.swift`, `App/Persystence/ShaderUnit.swift`, `App/PersystenceTests/SurfaceGeometryTests.swift`, and `App/PersystenceTests/SurfaceRenderHarness.swift`: live path/name comments only.
- `.gitignore`: update live test-baseline paths if the current patterns name `ARShaderTests`.
- Active forward-looking documents created after the naming decision: use PERSYSTENCE terminology while preserving explicit historical references.

---

### Task 1: Identity Authority and Preference Compatibility

**Files:**
- Create: `App/ARShader/ProductIdentity.swift`
- Create: `App/ARShaderTests/ProductIdentityTests.swift`
- Modify: `App/ARShader/SurfaceLayoutStore.swift`
- Modify: `App/ARShaderTests/SurfaceLayoutStoreTests.swift`

**Interfaces:**
- Consumes: existing `SurfaceLayoutStore(defaults:)`, `Arrangement`, and `UserDefaults` injection.
- Produces: `enum ProductIdentity`, `ProductIdentity.canonicalName`, `ProductIdentity.wordmark`, `ProductIdentity.descriptor`, `ProductIdentity.outputWindowTitle`, `ProductIdentity.bundleIdentifier`, `SurfaceLayoutStore.key`, and `SurfaceLayoutStore.legacyKey`.

- [ ] **Step 1: Confirm the execution prerequisite**

Run:

```bash
git worktree list --porcelain
git status --short
git stash list
```

Expected: `.worktrees/m2-slot-bank` is absent or its branch has already been merged, the only pre-existing working-tree modification is the operator-owned prior-art dossier edit, and no unexplained stash exists. Stop and reconcile if those conditions are false.

- [ ] **Step 2: Add failing identity contract tests**

Create `App/ARShaderTests/ProductIdentityTests.swift`:

```swift
import XCTest

final class ProductIdentityTests: XCTestCase {
    func testCanonicalIdentityFormsAreExact() {
        XCTAssertEqual(ProductIdentity.canonicalName, "PERSYSTENCE")
        XCTAssertEqual(ProductIdentity.wordmark, "PER·SYS·TENCE")
        XCTAssertEqual(ProductIdentity.descriptor, "Visual Memory Apparatus")
        XCTAssertEqual(ProductIdentity.bundleSafeName, "Persystence")
    }

    func testOutputTitleUsesCanonicalProductName() {
        XCTAssertEqual(ProductIdentity.outputWindowTitle, "PERSYSTENCE — Output")
    }

    func testLegacyBundleIdentifierIsAnExplicitCompatibilityAnchor() {
        XCTAssertEqual(ProductIdentity.bundleIdentifier, "com.arsonrivvers.ARShader")
    }
}
```

- [ ] **Step 3: Add failing preference-migration tests**

Add these tests to `App/ARShaderTests/SurfaceLayoutStoreTests.swift`:

```swift
func testLegacyArrangementMigratesToThePersystenceKey() throws {
    let defaults = try makeDefaults()
    var legacy = Arrangement.default
    legacy.openPanel = .library
    legacy.panelWidth = 404
    let data = try JSONEncoder().encode(legacy)
    defaults.set(data, forKey: SurfaceLayoutStore.legacyKey)

    XCTAssertEqual(SurfaceLayoutStore(defaults: defaults).load(), legacy)
    XCTAssertEqual(defaults.data(forKey: SurfaceLayoutStore.key), data)
    XCTAssertNil(defaults.object(forKey: SurfaceLayoutStore.legacyKey))
}

func testNewPersystenceKeyWinsWhenBothKeysExist() throws {
    let defaults = try makeDefaults()
    var current = Arrangement.default
    current.openPanel = .settings
    var legacy = Arrangement.default
    legacy.openPanel = .library
    defaults.set(try JSONEncoder().encode(current), forKey: SurfaceLayoutStore.key)
    defaults.set(try JSONEncoder().encode(legacy), forKey: SurfaceLayoutStore.legacyKey)

    XCTAssertEqual(SurfaceLayoutStore(defaults: defaults).load(), current)
}

func testCorruptLegacyDataFallsBackWithoutWritingTheNewKey() throws {
    let defaults = try makeDefaults()
    defaults.set(Data("not json".utf8), forKey: SurfaceLayoutStore.legacyKey)

    XCTAssertEqual(SurfaceLayoutStore(defaults: defaults).load(), .default)
    XCTAssertNil(defaults.object(forKey: SurfaceLayoutStore.key))
}
```

- [ ] **Step 4: Run the focused tests and verify they fail for the intended reasons**

Run:

```bash
cd App
xcodegen generate
xcodebuild -project TrueISFEditor.xcodeproj -scheme ARShader \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing:ARShaderTests/ProductIdentityTests \
  -only-testing:ARShaderTests/SurfaceLayoutStoreTests test
```

Expected: FAIL because `ProductIdentity` and `SurfaceLayoutStore.legacyKey` do not exist.

- [ ] **Step 5: Implement the identity authority**

Create `App/ARShader/ProductIdentity.swift`:

```swift
import Foundation

enum ProductIdentity {
    static let canonicalName = "PERSYSTENCE"
    static let wordmark = "PER·SYS·TENCE"
    static let descriptor = "Visual Memory Apparatus"
    static let bundleSafeName = "Persystence"
    static let outputWindowTitle = "\(canonicalName) — Output"

    /// Retained across the visible rename so the signed app keeps its TCC identity and
    /// UserDefaults domain. This is compatibility metadata, not public product language.
    static let bundleIdentifier = "com.arsonrivvers.ARShader"
}
```

- [ ] **Step 6: Implement one-time preference migration**

Replace `SurfaceLayoutStore`'s key and `load()` implementation with:

```swift
static let key = "Persystence.surfaceArrangement"
static let legacyKey = "ARShader.surfaceArrangement"

func load() -> Arrangement {
    if let data = defaults.data(forKey: Self.key),
       let decoded = try? JSONDecoder().decode(Arrangement.self, from: data) {
        return decoded
    }

    guard let legacyData = defaults.data(forKey: Self.legacyKey),
          let decoded = try? JSONDecoder().decode(Arrangement.self, from: legacyData)
    else { return .default }

    defaults.set(legacyData, forKey: Self.key)
    defaults.removeObject(forKey: Self.legacyKey)
    return decoded
}
```

Keep `save(_:)` unchanged except that it now writes through `Self.key`.

- [ ] **Step 7: Run the focused tests**

Repeat the Task 1 Step 4 command.

Expected: PASS for `ProductIdentityTests` and `SurfaceLayoutStoreTests`.

- [ ] **Step 8: Commit Task 1**

```bash
git add App/ARShader/ProductIdentity.swift \
  App/ARShader/SurfaceLayoutStore.swift \
  App/ARShaderTests/ProductIdentityTests.swift \
  App/ARShaderTests/SurfaceLayoutStoreTests.swift
git commit -m "feat(identity): establish the PERSYSTENCE product contract"
```

### Task 2: Source, Target, Scheme, and Test Identity

**Files:**
- Rename: `App/ARShader/` → `App/Persystence/`
- Rename: `App/ARShaderTests/` → `App/PersystenceTests/`
- Create: `App/Persystence/Info.plist` (created by the directory rename)
- Create: `App/Persystence/OutputWindowController.swift` (created by the directory rename)
- Rename: `App/Persystence/ARShaderApp.swift` → `App/Persystence/PersystenceApp.swift`
- Rename: `App/Persystence/ARShader-Bridging-Header.h` → `App/Persystence/Persystence-Bridging-Header.h`
- Rename: `App/Persystence/ARShader.entitlements` → `App/Persystence/Persystence.entitlements`
- Modify: `App/project.yml`
- Modify: `.gitignore`
- Modify: live path comments in renamed Swift files

**Interfaces:**
- Consumes: `ProductIdentity` from Task 1 and every existing application/test source unchanged at the Swift type level except the `@main` type.
- Produces: XcodeGen targets and scheme named `Persystence` and `PersystenceTests`, application bundle `Persystence.app`, executable `Persystence`, and test host `Persystence.app/Contents/MacOS/Persystence`.

- [ ] **Step 1: Record the generated-project baseline**

Run:

```bash
cd App
xcodegen generate
xcodebuild -project TrueISFEditor.xcodeproj -scheme ARShader \
  -destination 'platform=macOS,arch=arm64' test
```

Expected: the current ARShader suite passes before path and target changes.

- [ ] **Step 2: Rename the tracked directories and identity-bearing files**

Run:

```bash
git mv App/ARShader App/Persystence
git mv App/ARShaderTests App/PersystenceTests
git mv App/Persystence/ARShaderApp.swift App/Persystence/PersystenceApp.swift
git mv App/Persystence/ARShader-Bridging-Header.h App/Persystence/Persystence-Bridging-Header.h
git mv App/Persystence/ARShader.entitlements App/Persystence/Persystence.entitlements
```

Expected: Git reports renames and no source or baseline file is lost.

- [ ] **Step 3: Rename the Swift application entry point**

In `App/Persystence/PersystenceApp.swift`, change only the type declaration:

```swift
@main
struct PersystenceApp: App {
```

Use `ProductIdentity.canonicalName` for the `WindowGroup` title:

```swift
WindowGroup(ProductIdentity.canonicalName) {
```

- [ ] **Step 4: Replace the application and test target blocks in `App/project.yml`**

Rename the target keys, paths, dependencies, and scheme from `ARShader` / `ARShaderTests` to
`Persystence` / `PersystenceTests`. The application base settings must include:

```yaml
        PRODUCT_NAME: Persystence
        PRODUCT_BUNDLE_IDENTIFIER: com.arsonrivvers.ARShader
        INFOPLIST_FILE: Persystence/Info.plist
        CODE_SIGN_ENTITLEMENTS: Persystence/Persystence.entitlements
        SWIFT_OBJC_BRIDGING_HEADER: Persystence/Persystence-Bridging-Header.h
        USER_HEADER_SEARCH_PATHS: $(SRCROOT)/ISFRuntime $(SRCROOT)/Persystence
```

The test base settings must include:

```yaml
        PRODUCT_NAME: PersystenceTests
        PRODUCT_BUNDLE_IDENTIFIER: com.arsonrivvers.ARShaderTests
        TEST_HOST: "$(BUILT_PRODUCTS_DIR)/Persystence.app/Contents/MacOS/Persystence"
        BUNDLE_LOADER: "$(TEST_HOST)"
        SWIFT_OBJC_BRIDGING_HEADER: Persystence/Persystence-Bridging-Header.h
        USER_HEADER_SEARCH_PATHS: $(SRCROOT)/ISFRuntime $(SRCROOT)/Persystence
```

Keep the legacy bundle identifiers and add adjacent comments explaining that they preserve signed identity and the UserDefaults domain.

- [ ] **Step 5: Update live source-path comments and ignore patterns**

Change comments that describe current paths or target membership from `ARShader` to `Persystence` in:

```text
App/Persystence/Instrument.swift
App/Persystence/ShaderUnit.swift
App/PersystenceTests/SurfaceGeometryTests.swift
App/PersystenceTests/SurfaceRenderHarness.swift
```

Update `.gitignore` only where a live `App/ARShaderTests/…` path now points to `App/PersystenceTests/…`. Do not alter historical documentation references.

- [ ] **Step 6: Regenerate and prove the new scheme exists while the old scheme does not**

Run:

```bash
cd App
xcodegen generate
xcodebuild -project TrueISFEditor.xcodeproj -list
```

Expected: targets and schemes include `Persystence` and `PersystenceTests`; they do not include `ARShader` or `ARShaderTests`.

- [ ] **Step 7: Run the renamed full test target**

Run:

```bash
xcodebuild -project TrueISFEditor.xcodeproj -scheme Persystence \
  -destination 'platform=macOS,arch=arm64' test
```

Expected: all Persystence tests pass with zero failures.

- [ ] **Step 8: Commit Task 2**

```bash
git add .gitignore App/project.yml App/Persystence App/PersystenceTests
git commit -m "refactor(identity): rename the native targets to Persystence"
```

### Task 3: Public Application Copy and Canonical Installation

**Files:**
- Modify: `App/Persystence/Info.plist`
- Modify: `App/Persystence/OutputWindowController.swift`
- Rename: `scripts/run-instrument.sh` → `scripts/run-persystence.sh`
- Create: `scripts/run-persystence.sh` (created by the file rename)
- Modify: `scripts/run-persystence.sh`
- Test: `App/PersystenceTests/ProductIdentityTests.swift`

**Interfaces:**
- Consumes: `ProductIdentity` and the renamed Xcode scheme/product from Tasks 1 and 2.
- Produces: visible app name `PERSYSTENCE`, output title `PERSYSTENCE — Output`, installed app `~/Applications/Persystence.app`, and canonical launcher `scripts/run-persystence.sh`.

- [ ] **Step 1: Extend the copy contract test**

Add to `ProductIdentityTests`:

```swift
func testCameraUsageCopyNamesTheProductAndTheAction() {
    XCTAssertEqual(
        ProductIdentity.cameraUsageDescription,
        "PERSYSTENCE uses the camera as a live source for visual processing."
    )
}
```

Add this property to the expected Task 1 interface, but do not implement it yet.

- [ ] **Step 2: Run the focused test and verify failure**

Run:

```bash
cd App
xcodebuild -project TrueISFEditor.xcodeproj -scheme Persystence \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing:PersystenceTests/ProductIdentityTests test
```

Expected: FAIL because `cameraUsageDescription` does not exist.

- [ ] **Step 3: Add the camera copy to `ProductIdentity` and `Info.plist`**

Add:

```swift
static let cameraUsageDescription =
    "PERSYSTENCE uses the camera as a live source for visual processing."
```

Set the relevant plist values to:

```xml
<key>CFBundleName</key><string>PERSYSTENCE</string>
<key>CFBundleDisplayName</key><string>PERSYSTENCE</string>
<key>CFBundleIdentifier</key><string>com.arsonrivvers.ARShader</string>
<key>NSCameraUsageDescription</key>
<string>PERSYSTENCE uses the camera as a live source for visual processing.</string>
```

The legacy identifier is intentional; do not replace it with a new identifier in this task.

- [ ] **Step 4: Centralize the output-window title**

In `OutputWindowController.swift`, replace the literal title with:

```swift
w.title = ProductIdentity.outputWindowTitle
```

- [ ] **Step 5: Rename and update the canonical launch script**

Run:

```bash
git mv scripts/run-instrument.sh scripts/run-persystence.sh
```

Update its values to:

```bash
DDATA="/tmp/persystence-ddata"
BUILT="${DDATA}/Build/Products/Debug/Persystence.app"
DEST="${HOME}/Applications/Persystence.app"
```

Build with `-scheme Persystence`; quit via `quit app "PERSYSTENCE"`; match only the explicit process path `Persystence.app/Contents/MacOS/Persystence`; and report PERSYSTENCE in every user-facing line. Do not delete `~/Applications/ARShader.app` in the script. The legacy app remains recoverable until the new staged binary passes the live smoke.

- [ ] **Step 6: Run tests and shell syntax validation**

Run:

```bash
bash -n scripts/run-persystence.sh
cd App
xcodebuild -project TrueISFEditor.xcodeproj -scheme Persystence \
  -destination 'platform=macOS,arch=arm64' test
```

Expected: shell syntax check exits 0 and all Persystence tests pass.

- [ ] **Step 7: Build and stage the renamed app**

Run:

```bash
./scripts/run-persystence.sh
```

Expected: `~/Applications/Persystence.app` exists and launches; the script reports `BUILD SUCCEEDED`.

- [ ] **Step 8: Verify the staged artifact, including a positive control**

Run:

```bash
plutil -p "$HOME/Applications/Persystence.app/Contents/Info.plist"
codesign -dvv "$HOME/Applications/Persystence.app" 2>&1
strings "$HOME/Applications/Persystence.app/Contents/MacOS/Persystence.debug.dylib" \
  | rg -n 'PERSYSTENCE|PER·SYS·TENCE|Visual Memory Apparatus|ARShader'
```

Expected:

- `CFBundleName` and `CFBundleDisplayName` are `PERSYSTENCE`.
- `CFBundleIdentifier` remains `com.arsonrivvers.ARShader`.
- the signed identifier is unchanged;
- the debug dylib contains the new product strings;
- any remaining `ARShader` string is either the explicit compatibility identifier/key or a source comment, not visible UI copy.

The `PERSYSTENCE` match is the positive control proving the strings probe reads the correct debug dylib.

- [ ] **Step 9: Commit Task 3**

```bash
git add App/Persystence/Info.plist \
  App/Persystence/OutputWindowController.swift \
  App/Persystence/ProductIdentity.swift \
  App/PersystenceTests/ProductIdentityTests.swift \
  scripts/run-persystence.sh
git commit -m "feat(identity): present and install PERSYSTENCE"
```

### Task 4: Forward Documentation and Naming Enforcement

**Files:**
- Modify: `docs/superpowers/specs/2026-08-01-arshader-modulation-expression-layer-design.md`
- Modify: `docs/superpowers/plans/2026-08-01-arshader-modulation-expression-layer.md`
- Modify: `docs/superpowers/specs/2026-08-01-persystence-naming-system-design.md` only if implementation reveals an actual compatibility correction
- Do not modify: completed specs/plans, `docs/reports/**`, `docs/arshader/legacy-cockpit/**`, or the operator-owned prior-art dossier edit

**Interfaces:**
- Consumes: naming rules from the approved dossier and the actual compatibility decisions implemented in Tasks 1–3.
- Produces: current forward-development documents that name the product PERSYSTENCE while retaining code-history context where needed.

- [ ] **Step 1: Classify every non-historical legacy-name occurrence without truncation**

Run:

```bash
rg -n --hidden --glob '!.git/**' --glob '!vendor/**' \
  'ARShader|AR_Shader|com\.arsonrivvers\.ARShader' . \
  > /tmp/persystence-legacy-name-inventory.txt
wc -l /tmp/persystence-legacy-name-inventory.txt
```

Expected: a complete count, with no `head`, narrow output filter, or early termination. Classify each live-code hit as compatibility metadata, stale public copy, or historical reference.

- [ ] **Step 2: Update only forward-development prose**

In the two named modulation documents, introduce the product once as:

```text
PERSYSTENCE (then ARShader)
```

Use `PERSYSTENCE` thereafter for product concepts. Keep literal filenames, target names, and code identifiers accurate to the task in which they existed. Do not rewrite completed implementation plans or reports to simulate a history that did not happen.

- [ ] **Step 3: Add an explicit rename note to the migration plan's eventual completion record**

Record these facts in the execution summary or smoke report:

```text
Public product identity: PERSYSTENCE
Displayed wordmark: PER·SYS·TENCE
Descriptor: Visual Memory Apparatus
Compatibility bundle identifier: com.arsonrivvers.ARShader
Legacy preference key: migrated once, then removed
REMNANCE engine: reserved, not implemented
```

- [ ] **Step 4: Prove no stale public copy remains in live surfaces**

Run:

```bash
rg -n 'ARShader|AR_Shader' App/Persystence App/PersystenceTests scripts/run-persystence.sh App/project.yml
```

Expected remaining hits are limited to:

```text
com.arsonrivvers.ARShader
com.arsonrivvers.ARShaderTests
ARShader.surfaceArrangement
comments immediately explaining those compatibility anchors
```

Any other hit must be corrected or explicitly justified in the completion summary.

- [ ] **Step 5: Commit Task 4 with explicit paths**

Stage only documents intentionally updated in this task. Do not stage
the prior-art dossier under `docs/arshader/`.

```bash
git add docs/superpowers/specs/2026-08-01-arshader-modulation-expression-layer-design.md \
  docs/superpowers/plans/2026-08-01-arshader-modulation-expression-layer.md
git commit -m "docs(identity): adopt PERSYSTENCE in forward development"
```

If no forward document requires an update, skip the commit and record that historical material was intentionally preserved.

### Task 5: Full Verification and Operator Smoke

**Files:**
- Create: `docs/reports/live-smoke-persystence-identity-migration.md`
- Modify: only files required to fix findings from the verification below

**Interfaces:**
- Consumes: renamed targets, staged app, compatibility migration, and documentation rules from Tasks 1–4.
- Produces: evidence that the renamed application builds, tests, launches, retains state, displays correct identity, and keeps safety behavior intact.

- [ ] **Step 1: Run all automated suites**

Run:

```bash
cd App
xcodegen generate
xcodebuild -project TrueISFEditor.xcodeproj -scheme Persystence \
  -destination 'platform=macOS,arch=arm64' test
xcodebuild -project TrueISFEditor.xcodeproj -scheme TrueISFEditor \
  -destination 'platform=macOS,arch=arm64' test
cd ../ShadertoyISFKit
swift test
```

Expected: every suite passes with zero failures; record exact test counts rather than copying old expected counts.

- [ ] **Step 2: Pre-flight the human-in-the-loop smoke**

State the hypotheses explicitly:

```text
H1: the renamed signed app launches as PERSYSTENCE while retaining the legacy bundle identity.
H2: a layout written under ARShader.surfaceArrangement is restored and migrated on first launch.
H3: camera access does not regress because the signed bundle identity is unchanged.
H4: blackout and output-window behavior are unchanged by the identity migration.
```

Before asking the operator to interact, verify:

```bash
test -d "$HOME/Applications/Persystence.app"
pgrep -f 'Persystence.app/Contents/MacOS/Persystence'
plutil -extract CFBundleIdentifier raw \
  "$HOME/Applications/Persystence.app/Contents/Info.plist"
```

Expected: staged app exists, its process is live, and identifier output is `com.arsonrivvers.ARShader`.

- [ ] **Step 3: Run the identity smoke legs**

Record PASS/FAIL and evidence for each:

1. Finder and Spotlight display `PERSYSTENCE` for the staged application.
2. The control window title displays `PERSYSTENCE`.
3. The output window title displays `PERSYSTENCE — Output`.
4. Existing surface arrangement is restored after relaunch.
5. A changed arrangement survives a second relaunch under the new key.
6. Camera input opens without an unexpected new permission prompt; if macOS prompts because prior permission was absent, record that distinction.
7. Blackout still clears the program output to opaque black.
8. Output open, close, floating, and external-display routing retain their previous behavior where hardware is available.
9. `~/Applications/ARShader.app` remains untouched during verification.

- [ ] **Step 4: Manually run the native Mechanic checklist**

Verify:

- no crash on launch, output open/close, or relaunch;
- no stale executable or stale generated project is being tested;
- every visible product string uses the correct identity form;
- the title change does not truncate controls or alter minimum-window behavior;
- the staged debug dylib contains the changed strings, with a known control string proving the probe works.

Record findings in the smoke report.

- [ ] **Step 5: Manually run the Client Success checklist**

Verify:

- the launch identity clearly reads as a fabricated visual machine;
- `PERSYSTENCE` is used for ordinary product naming and `PER·SYS·TENCE` only for major identity display;
- `Visual Memory Apparatus` is not presented as proof of unbuilt memory features;
- REMNANCE is not exposed as a working engine before implementation;
- camera permission copy is understandable and exact;
- no safety or output control is obscured by branding.

Record findings in the smoke report.

- [ ] **Step 6: Complete the live-smoke report**

Write `docs/reports/live-smoke-persystence-identity-migration.md` with:

- commit and staged-binary identity;
- exact suite counts;
- plist and codesign evidence;
- each smoke leg and its evidence;
- preference migration result;
- Mechanic and Client Success findings;
- remaining compatibility anchors;
- explicit statement that REMNANCE is reserved but not implemented.

- [ ] **Step 7: Run the final exhaustive live-surface sweep**

Run:

```bash
rg -n 'ARShader|AR_Shader' App/Persystence App/PersystenceTests scripts/run-persystence.sh App/project.yml
```

Expected: only the four allowed compatibility categories from Task 4 Step 4. Paste the actual command and result count into the completion summary.

- [ ] **Step 8: Commit verification evidence and any fixes**

```bash
git add docs/reports/live-smoke-persystence-identity-migration.md
git commit -m "test(identity): confirm the PERSYSTENCE migration live"
```

If verification required code fixes, commit each fix with its regression test before committing the final report.

## Execution Stop Conditions

Stop rather than improvising if any of these occur:

- the slot-bank worktree or another active branch still modifies the paths being renamed;
- the current bundle identifier differs from `com.arsonrivvers.ARShader` at execution time;
- changing `PRODUCT_NAME` changes the signed identifier or causes a new camera permission identity;
- legacy layout data exists outside the current bundle's UserDefaults domain;
- XcodeGen cannot produce the renamed test host without changing the TrueISFEditor target;
- an exhaustive live-surface sweep finds user-facing legacy copy whose role is ambiguous.

These conditions require a focused design correction because they affect compatibility or scope.
