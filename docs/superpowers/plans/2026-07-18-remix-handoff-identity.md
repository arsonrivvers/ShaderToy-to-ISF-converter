# Remix Handoff Identity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give every unsaved editor document a stable unique history identity so same-named Remix winners stay isolated through first Save As, and show the existing save-state pill immediately whenever a document still needs Save As.

**Architecture:** Add one immutable UUID to the value-semantic `ISFFile`; copies retain it across edits and Save As, while each `untitled(...)` construction receives a new identity. `SnapshotStore` uses that full UUID only for unsaved keys and preserves the existing path-derived key algorithm for saved files, so durable histories remain backward-compatible. The existing header pill renders from a tested `hasUnsavedWork` model predicate (`isDirty || needsSaveAs`) without adding a new Remix or versioning surface.

**Tech Stack:** Swift 6, SwiftUI, CryptoKit, XCTest, XcodeGen-generated macOS project.

---

## Scope and invariants

- Keep Remix lineage, favorites, and Step Back separate from editor file versions.
- Do not pass `RemixNode.id` into the editor: Remix IDs reset with each studio model and belong to
  lineage, not durable editor-document identity.
- Do not make display names artificially unique; multiple children may continue to display as `Remixed shader.fs` before first save.
- Do not change the saved-document snapshot key algorithm: reopening a saved path must still find its existing history.
- Do not persist unsaved UUIDs across launches; unsaved editor documents do not survive process termination.
- Do not auto-migrate old display-name-keyed untitled folders: they may already contain histories
  merged from unrelated documents. Saved path-keyed histories remain compatible and reachable.
- Do not add files under `App/`; all implementation and tests modify existing files, so `xcodegen generate` is not required unless execution deviates from this file map.
- Use `-derivedDataPath ./ddata` for every app test/build. Do not push.

## File map

- Modify `App/TrueISFEditor/Models/ISFFile.swift`: own the immutable per-document UUID and expose the aggregate unsaved-work predicate.
- Modify `App/TrueISFEditor/Models/SnapshotStore.swift`: key unsaved histories by the full UUID while retaining saved path keys byte-for-byte.
- Modify `App/TrueISFEditor/Views/EditorScreen.swift`: show the existing pill for `needsSaveAs` even when `isDirty == false` and use accurate Save-As copy.
- Modify `App/TrueISFEditorTests/ISFFileTests.swift`: prove identity stability and the immediate unsaved-work state.
- Modify `App/TrueISFEditorTests/SnapshotStoreTests.swift`: prove same-named untitled documents have distinct keys while value copies stay on one key.
- Modify `App/TrueISFEditorTests/EditorViewModelSnapshotTests.swift`: exercise the production `loadImported` and `saveAs` path with two same-named children.

### Task 1: Isolate same-named unsaved histories and migrate only the active child

**Files:**
- Modify: `App/TrueISFEditor/Models/ISFFile.swift:5-30`
- Modify: `App/TrueISFEditor/Models/SnapshotStore.swift:55-63`
- Modify: `App/TrueISFEditorTests/SnapshotStoreTests.swift:126-155`
- Modify: `App/TrueISFEditorTests/EditorViewModelSnapshotTests.swift:29-35`

- [ ] **Step 1: Write the failing identity-key test**

Add this test after `testDocumentsKeepSeparateHistories` in `SnapshotStoreTests.swift`:

```swift
func testSameNamedUntitledDocumentsUseDistinctStableKeys() {
    let first = TrueISFEditor.ISFFile.untitled(source: "first", suggestedName: "Remixed shader")
    let second = TrueISFEditor.ISFFile.untitled(source: "second", suggestedName: "Remixed shader")
    var editedFirst = first
    editedFirst.source = "first edited"

    XCTAssertNotEqual(first.documentID, second.documentID)
    XCTAssertEqual(first.documentID, editedFirst.documentID,
                   "value-semantic edits must retain the document identity")
    XCTAssertNotEqual(SnapshotStore.documentKey(for: first),
                      SnapshotStore.documentKey(for: second))
    XCTAssertEqual(SnapshotStore.documentKey(for: first),
                   SnapshotStore.documentKey(for: editedFirst))
}
```

- [ ] **Step 2: Write the failing production-path isolation tests**

Add these tests after `testImportCapturesOpenedSnapshot` in `EditorViewModelSnapshotTests.swift`:

```swift
func testSameNamedImportsBeforeFirstSaveHaveIsolatedHistories() {
    let vm = makeVM()
    let firstSource = "/*{}*/ void main(){ gl_FragColor = vec4(0.1); }"
    let secondSource = "/*{}*/ void main(){ gl_FragColor = vec4(0.9); }"

    vm.loadImported(isf: firstSource, warnings: [], suggestedName: "Remixed shader")
    let firstChild = vm.file
    vm.pin(name: "first child")

    vm.loadImported(isf: secondSource, warnings: [], suggestedName: "Remixed shader")
    let secondChild = vm.file
    vm.pin(name: "second child")

    let firstBeforeSave = vm.snapshots.snapshots(for: firstChild)
    let secondBeforeSave = vm.snapshots.snapshots(for: secondChild)
    XCTAssertEqual(firstBeforeSave.count, 2)
    XCTAssertEqual(Set(firstBeforeSave.map(\.source)), Set([firstSource]))
    XCTAssertTrue(firstBeforeSave.contains { $0.kind == .pin(name: "first child") })
    XCTAssertEqual(secondBeforeSave.count, 2)
    XCTAssertEqual(Set(secondBeforeSave.map(\.source)), Set([secondSource]))
    XCTAssertTrue(secondBeforeSave.contains { $0.kind == .pin(name: "second child") })
}

func testSaveAsMigratesOnlyCurrentSameNamedImportHistory() {
    let vm = makeVM()
    let firstSource = "/*{}*/ void main(){ gl_FragColor = vec4(0.1); }"
    let secondSource = "/*{}*/ void main(){ gl_FragColor = vec4(0.9); }"

    vm.loadImported(isf: firstSource, warnings: [], suggestedName: "Remixed shader")
    let firstChild = vm.file
    vm.pin(name: "first child")

    vm.loadImported(isf: secondSource, warnings: [], suggestedName: "Remixed shader")
    let secondChild = vm.file
    vm.pin(name: "second child")

    vm.saveAs(root.appendingPathComponent("Second-child.fs"))

    let savedSecond = vm.snapshots.snapshots(for: vm.file)
    XCTAssertEqual(savedSecond.count, 3)
    XCTAssertEqual(Set(savedSecond.map(\.source)), Set([secondSource]))
    XCTAssertTrue(savedSecond.contains { $0.kind == .safety })
    XCTAssertTrue(savedSecond.contains { $0.kind == .pin(name: "second child") })
    XCTAssertTrue(savedSecond.contains { $0.kind == .save(number: 1) })
    XCTAssertTrue(vm.snapshots.snapshots(for: secondChild).isEmpty,
                  "Save As must retire only the active child's temporary key")

    let untouchedFirst = vm.snapshots.snapshots(for: firstChild)
    XCTAssertEqual(untouchedFirst.count, 2)
    XCTAssertEqual(Set(untouchedFirst.map(\.source)), Set([firstSource]))
    XCTAssertTrue(untouchedFirst.contains { $0.kind == .pin(name: "first child") })
}
```

- [ ] **Step 3: Run the focused tests and verify RED**

Run:

```bash
cd App
xcodebuild test -project TrueISFEditor.xcodeproj -scheme TrueISFEditor \
  -destination 'platform=macOS,arch=arm64' ARCHS=arm64 ONLY_ACTIVE_ARCH=YES \
  -derivedDataPath ./ddata \
  -only-testing:TrueISFEditorTests/SnapshotStoreTests \
  -only-testing:TrueISFEditorTests/EditorViewModelSnapshotTests
```

Expected: FAIL because `ISFFile` has no `documentID`; if the first test is temporarily reduced to key assertions, both same-named untitled keys collide and the production-path histories co-mingle.

- [ ] **Step 4: Add the immutable document identity**

In `ISFFile.swift`, add the property and initialize it once:

```swift
struct ISFFile {
    /// Stable for this in-memory document's lifetime. Struct copies preserve it across edits/Save As;
    /// every fresh untitled/import/example construction receives a new identity.
    let documentID: UUID
    private(set) var url: URL?
    // existing properties unchanged

    private init(url: URL?, source: String, isDirty: Bool, suggestedName: String? = nil,
                 documentID: UUID = UUID()) {
        self.documentID = documentID
        self.url = url; self.source = source; self.isDirty = isDirty
        self.suggestedName = suggestedName
    }
}
```

Do not regenerate the UUID in `save(to:)`, `save()`, or source mutation paths.

- [ ] **Step 5: Key unsaved histories by the full UUID without changing saved keys**

Replace `SnapshotStore.documentKey(for:)` with:

```swift
/// Stable, filesystem-safe per-document folder name. Saved docs retain the historical path-based
/// key so their timelines survive reopen; unsaved docs use their full in-memory document UUID.
static func documentKey(for file: ISFFile) -> String {
    let safeName = String(file.displayName.map { $0.isLetter || $0.isNumber ? $0 : "-" })
    guard let path = file.url?.path else {
        return "\(safeName)-\(file.documentID.uuidString.lowercased())"
    }
    let digest = SHA256.hash(data: Data(path.utf8))
    let hex = digest.prefix(6).map { String(format: "%02x", $0) }.joined()
    return "\(safeName)-\(hex)"
}
```

Update the comment in `testKindRoundTripsThroughDisk` from “same suggestedName” to “same document identity”; its `var f2 = file` / `var f3 = file` copies are the regression proof.

- [ ] **Step 6: Run the focused tests and verify GREEN**

Run the exact command from Step 3.

Expected: both test classes pass. The two `Remixed shader.fs` documents have different unsaved keys; Save As moves only the active child's safety/pin history and then mints its `v01`.

- [ ] **Step 7: Commit Task 1**

```bash
git add App/TrueISFEditor/Models/ISFFile.swift \
  App/TrueISFEditor/Models/SnapshotStore.swift \
  App/TrueISFEditorTests/SnapshotStoreTests.swift \
  App/TrueISFEditorTests/EditorViewModelSnapshotTests.swift
git commit -m "fix(versions): isolate untitled histories by document identity" \
  -m "Co-Authored-By: OpenAI Codex <noreply@openai.com>"
```

### Task 2: Surface Save-As state immediately and run the native verification gate

**Files:**
- Modify: `App/TrueISFEditor/Models/ISFFile.swift:13-17`
- Modify: `App/TrueISFEditor/Views/EditorScreen.swift:78-90`
- Modify: `App/TrueISFEditorTests/ISFFileTests.swift:3-24`

- [ ] **Step 1: Write the failing aggregate-state assertions**

Update the first two `ISFFileTests` so they prove both halves of the UI predicate:

```swift
func test_untitled_hasUnsavedWorkBeforeEdit_andNeedsSaveAs() {
    var f = ISFFile.untitled(suggestedName: "Remixed shader")
    XCTAssertNil(f.url)
    XCTAssertFalse(f.isDirty)
    XCTAssertTrue(f.needsSaveAs)
    XCTAssertTrue(f.hasUnsavedWork,
                  "an imported/untitled document needs a visible Save As cue before any edit")
    f.source = "void main(){}"
    XCTAssertTrue(f.isDirty)
    XCTAssertTrue(f.hasUnsavedWork)
    XCTAssertEqual(f.displayName, "Remixed shader.fs")
}

func test_saveToURL_clearsDirtyAndUnsavedWork_andWritesFile() throws {
    let tmp = FileManager.default.temporaryDirectory
        .appendingPathComponent("isffile-\(UUID()).fs")
    defer { try? FileManager.default.removeItem(at: tmp) }
    var f = ISFFile.untitled()
    f.source = "X"
    try f.save(to: tmp)
    XCTAssertEqual(f.url, tmp)
    XCTAssertFalse(f.isDirty)
    XCTAssertFalse(f.needsSaveAs)
    XCTAssertFalse(f.hasUnsavedWork)
    XCTAssertEqual(try String(contentsOf: tmp, encoding: .utf8), "X")
    f.source = "Y"
    XCTAssertTrue(f.isDirty)
    XCTAssertTrue(f.hasUnsavedWork,
                  "ordinary edits to a saved file must raise the same visible save cue")
}
```

- [ ] **Step 2: Run `ISFFileTests` and verify RED**

Run:

```bash
cd App
xcodebuild test -project TrueISFEditor.xcodeproj -scheme TrueISFEditor \
  -destination 'platform=macOS,arch=arm64' ARCHS=arm64 ONLY_ACTIVE_ARCH=YES \
  -derivedDataPath ./ddata \
  -only-testing:TrueISFEditorTests/ISFFileTests
```

Expected: FAIL because `ISFFile` has no `hasUnsavedWork` member.

- [ ] **Step 3: Implement the aggregate state and wire the existing pill**

Add this next to `needsSaveAs` in `ISFFile.swift`:

```swift
/// Any state whose current editor contents do not yet exist durably at the backing URL.
var hasUnsavedWork: Bool { isDirty || needsSaveAs }
```

In `EditorScreen.swift`, change only the existing pill's outer condition and untitled copy:

```swift
if vm.file.hasUnsavedWork {
    Text(vm.assistApplied
         ? "Rewrite applied — ⌘S saves v\(String(format: "%02d", vm.nextSaveVersion))"
         : (vm.file.needsSaveAs
            ? "Unsaved — Save As required"
            : "Edited — ⌘S saves v\(String(format: "%02d", vm.nextSaveVersion))"))
        // existing styling unchanged
}
```

Do not add a new badge, toolbar action, or Remix-specific UI.

- [ ] **Step 4: Run the focused identity/history/pill tests and verify GREEN**

Run:

```bash
cd App
xcodebuild test -project TrueISFEditor.xcodeproj -scheme TrueISFEditor \
  -destination 'platform=macOS,arch=arm64' ARCHS=arm64 ONLY_ACTIVE_ARCH=YES \
  -derivedDataPath ./ddata \
  -only-testing:TrueISFEditorTests/ISFFileTests \
  -only-testing:TrueISFEditorTests/SnapshotStoreTests \
  -only-testing:TrueISFEditorTests/EditorViewModelSnapshotTests
```

Expected: all three classes pass.

- [ ] **Step 5: Commit Task 2**

```bash
git add App/TrueISFEditor/Models/ISFFile.swift \
  App/TrueISFEditor/Views/EditorScreen.swift \
  App/TrueISFEditorTests/ISFFileTests.swift
git commit -m "fix(editor): show Save As state for clean untitled documents" \
  -m "Co-Authored-By: OpenAI Codex <noreply@openai.com>"
```

- [ ] **Step 6: Run full suites and an explicit arm64 build**

Run:

```bash
cd App
xcodebuild test -project TrueISFEditor.xcodeproj -scheme TrueISFEditor \
  -destination 'platform=macOS,arch=arm64' ARCHS=arm64 ONLY_ACTIVE_ARCH=YES \
  -derivedDataPath ./ddata
xcodebuild -project TrueISFEditor.xcodeproj -scheme TrueISFEditor \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=YES -derivedDataPath ./ddata build
cd ../ShadertoyISFKit
swift test
```

Expected: app tests and build succeed with zero failures; kit tests remain green. Extract the exact app counts from the newest `.xcresult` rather than inferring them from exit status.

- [ ] **Step 7: Run the native manual review and completion gate**

Manual Mechanic review (native exception; do not dispatch the web Mechanic):

- `ISFFile.documentID` is immutable and copied, never regenerated on save/edit.
- Saved path keys are unchanged; only `url == nil` keys use UUIDs.
- The production `loadImported` test opens two same-named children before either save.
- Save As retires only the active unsaved key and leaves the sibling history intact.
- The existing pill layout/styling is unchanged; only its visibility predicate and accurate unsaved copy change.
- No synchronous modal, Remix lineage, VJ-host, cache, or conversion-pipeline code changed.

Then invoke `/gate` at the build-done transition. Keep `trueisf-remix-handoff-identity-20260718` open until the patched binary is staged and accepted on-device. Keep both pre-existing live Client Success items open unless their full rendered-state review actually completes.

- [ ] **Step 8: Stage only after an explicit announce, then verify binary freshness**

Before invoking the staging script, announce it in conversation. Then run from the repo root:

```bash
./scripts/run-latest.sh
strings /Users/arsonrivvers/Applications/TrueISFEditor.app/Contents/MacOS/TrueISFEditor.debug.dylib \
  | rg -F "Save As required"
stat -f '%Sm %N' -t '%Y-%m-%d %H:%M:%S %Z' \
  /Users/arsonrivvers/Applications/TrueISFEditor.app/Contents/MacOS/TrueISFEditor.debug.dylib
```

Expected: staging succeeds, `Save As required` is present in the installed debug dylib, and the dylib timestamp matches this build. Status remains **STAGED** until Conner opens two Remix winners, confirms distinct version histories after Save As, and sees the immediate unsaved pill; only then mark the action item done/CONFIRMED. Do not push.

## Self-review

- **Requirements coverage:** Task 1 covers stable per-document identity, two same-named children before first save, isolated histories, and exact active-child Save As migration. Task 2 covers a `needsSaveAs || isDirty` pill, focused/full verification, binary freshness, and the native confirmation gate.
- **Placeholder scan:** no TBD/TODO/“similar to” implementation steps; every edit and command is explicit.
- **Type consistency:** `documentID`, `hasUnsavedWork`, `SnapshotStore.documentKey(for:)`, `loadImported`, and `saveAs` use the existing concrete types and call sites throughout.
- **Scope check:** no new files under the Xcode project, no xcodegen requirement, no Remix lineage duplication, no conversion-integrity work, no broad cleanup, and no push.
