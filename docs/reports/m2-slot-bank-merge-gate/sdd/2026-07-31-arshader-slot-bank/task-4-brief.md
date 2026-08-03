### Task 4: `ShaderUnit.sourceURL`

**Files:**
- Modify: `App/ARShader/ShaderUnit.swift` (add stored property; set it in `load(url:)` at line ~64)
- Test: `App/ARShaderTests/InstrumentLoadTests.swift` (create — first two tests)

**Interfaces:**
- Produces: `ShaderUnit.sourceURL: URL?`.

**Why this exists:** `load(url:)` currently reads the file and forwards only `url.lastPathComponent`; the `URL` is discarded on the same line. Capture cannot build a `Preset` without it, and reverse-lookup by filename is unsafe — the library truncates names in the middle precisely because long `AR_Genuary` names differ at the END, and a shader may be loaded from outside the scanned corpus.

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import ARShader

@MainActor
final class InstrumentLoadTests: XCTestCase {

    /// A real, compilable ISF file on disk. The unit reads the file, so a fake path will not do.
    func makeShaderFile(_ name: String = "probe") throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(name)-\(UUID().uuidString).fs")
        try """
        /*{ "DESCRIPTION": "test", "ISFVSN": "2", "INPUTS": [
            { "NAME": "speed", "TYPE": "float", "MIN": 0.0, "MAX": 1.0, "DEFAULT": 0.5 }
        ] }*/
        void main() { gl_FragColor = vec4(speed, 0.0, 0.0, 1.0); }
        """.write(to: url, atomically: true, encoding: .utf8)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    func testAFreshUnitHasNoSourceURL() {
        let instrument = Instrument()
        XCTAssertNil(instrument.deck(.one).unit.sourceURL,
                     "Nothing has been loaded, so there is no file behind the deck")
    }

    func testLoadingFromAURLRetainsIt() throws {
        let instrument = Instrument()
        let url = try makeShaderFile()
        instrument.deck(.one).unit.load(url: url)
        XCTAssertEqual(instrument.deck(.one).unit.sourceURL, url,
                       "Capture needs the URL, and lastPathComponent is not enough — filenames "
                       + "are not unique across the corpus")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Expected: FAIL — `value of type 'ShaderUnit' has no member 'sourceURL'`.

- [ ] **Step 3: Write minimal implementation**

In `App/ARShader/ShaderUnit.swift`, add next to `shaderName`:

```swift
    /// The file this unit was loaded from, when there was one.
    ///
    /// `shaderName` is only `lastPathComponent` and cannot be reversed into a URL: filenames are
    /// not unique across the corpus, and a shader can be loaded from outside the scanned folders.
    /// The slot bank captures this; without it a `Preset` cannot name its own shader.
    /// Nil for the `load(source:name:)` path, which has no file behind it.
    @Published private(set) var sourceURL: URL?
```

Then in `load(url:)`, immediately before the existing `load(source:name:)` call:

```swift
        sourceURL = url
```

Leave `load(source:name:)` setting `sourceURL = nil` at its start, so a source-loaded unit never
claims a file it does not have.

- [ ] **Step 4: Run test to verify it passes**

Expected: PASS, 2 tests.

- [ ] **Step 5: Mutation-prove it**

Remove the `sourceURL = url` line. Expected: `testLoadingFromAURLRetainsIt` FAILS. Restore.
Then make `load(source:name:)` NOT clear it, load from a URL and then from source, and confirm the nil-ing matters — if no existing test covers that, it is fine; the clear is defensive.

- [ ] **Step 6: Commit**

```bash
git add App/ARShader/ShaderUnit.swift App/ARShaderTests/InstrumentLoadTests.swift
git commit -m "feat(3b): ShaderUnit retains the URL it loaded

Capture cannot build a Preset without it, and lastPathComponent cannot be
reversed — the library truncates names in the middle precisely because long
AR_Genuary names differ at the end."
```

Expected ARShader count: **227**.

---

