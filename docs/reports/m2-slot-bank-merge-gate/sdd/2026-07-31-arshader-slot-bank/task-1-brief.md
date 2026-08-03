### Task 1: `Preset`

**Files:**
- Create: `App/ARShader/Preset.swift`
- Test: `App/ARShaderTests/PresetTests.swift`

**Interfaces:**
- Consumes: `ParamSnapshot` from `App/ISFRuntime/ParamStore.swift`.
- Produces: `Preset(id:name:shaderURL:snapshot:)`, `Preset.capturing(url:snapshot:)`.

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import ARShader

final class PresetTests: XCTestCase {

    private func snapshot() -> ParamSnapshot {
        ParamSnapshot(params: ["speed": .float(0.75), "on": .bool(true)])
    }

    func testCapturingNamesThePresetAfterItsShaderFile() {
        let p = Preset.capturing(url: URL(fileURLWithPath: "/tmp/AR_Genuary_17.fs"),
                                 snapshot: snapshot())
        XCTAssertEqual(p.name, "AR_Genuary_17.fs",
                       "3b derives the name from the file; 3c makes it editable")
    }

    func testTwoPresetsOfTheSameShaderAreDistinctThings() {
        let url = URL(fileURLWithPath: "/tmp/same.fs")
        let a = Preset.capturing(url: url, snapshot: snapshot())
        let b = Preset.capturing(url: url, snapshot: snapshot())
        XCTAssertNotEqual(a.id, b.id,
                          "Capturing the same shader twice with different values must produce two "
                          + "slots that can differ, not one identity shared between them")
    }

    func testAPresetSurvivesAJSONRoundTripWithItsValuesIntact() throws {
        let original = Preset.capturing(url: URL(fileURLWithPath: "/tmp/x.fs"), snapshot: snapshot())
        let decoded = try JSONDecoder().decode(
            Preset.self, from: try JSONEncoder().encode(original))
        XCTAssertEqual(decoded, original)
        XCTAssertEqual(decoded.snapshot.params["speed"], .float(0.75),
                       "The dialled values are the whole point of a preset")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project App/TrueISFEditor.xcodeproj -scheme ARShader -derivedDataPath /tmp/arshader-ddata-bank -only-testing:ARShaderTests/PresetTests ARCHS=arm64 ONLY_ACTIVE_ARCH=YES`
Expected: FAIL — compile error, `cannot find 'Preset' in scope`.

- [ ] **Step 3: Write minimal implementation**

```swift
import Foundation

/// A shader together with the parameter values that were dialled when it was captured.
///
/// The unit a slot holds, and — once phase 3c adds naming and browsing, and a later phase adds
/// randomisation — the unit those operate on too. `ParamSnapshot` does the heavy lifting: it is
/// already `Codable`, already survives one corrupt entry without failing the whole decode, and
/// `ParamStore.applySnapshot` already validate-and-clamps it against the LIVE header range, so a
/// preset captured under an older, wider range clamps in rather than replaying out of range.
struct Preset: Codable, Equatable, Identifiable {
    let id: UUID
    /// 3b derives this from the filename and nothing edits it. Stored anyway: adding a property to
    /// a persisted Codable type later is a migration, and adding it now is free.
    var name: String
    let shaderURL: URL
    let snapshot: ParamSnapshot

    /// Capture always mints a NEW identity. Two captures of the same shader are two presets that
    /// happen to share a URL, not one preset in two slots — otherwise editing one would silently
    /// edit the other.
    static func capturing(url: URL, snapshot: ParamSnapshot) -> Preset {
        Preset(id: UUID(), name: url.lastPathComponent, shaderURL: url, snapshot: snapshot)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run the same command. Expected: PASS, 3 tests.

- [ ] **Step 5: Mutation-prove the identity test**

Change `capturing` to derive a stable id from the URL:
```swift
static func capturing(url: URL, snapshot: ParamSnapshot) -> Preset {
    Preset(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
           name: url.lastPathComponent, shaderURL: url, snapshot: snapshot)
}
```
Run the tests. Expected: `testTwoPresetsOfTheSameShaderAreDistinctThings` FAILS. **Restore the real implementation** and confirm PASS again.

- [ ] **Step 6: Add the file to the project and commit**

`App/project.yml` uses directory globs, so a new file in `App/ARShader/` needs no manifest edit — but run `xcodegen generate` from `App/` if the build cannot see it.

```bash
git add App/ARShader/Preset.swift App/ARShaderTests/PresetTests.swift
git commit -m "feat(3b): Preset — a shader plus the values dialled when it was captured"
```

Expected ARShader count after this task: **210**.

---

