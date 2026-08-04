# Assist Visibility + Versioning Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Numbered save versions with an embedded Versions panel, loud unsaved state after AI applies, in-editor change gutter bars, and a live assist progress strip — per `docs/superpowers/specs/2026-07-18-assist-visibility-versioning-design.md` (PM findings F1–F5 folded).

**Architecture:** Extend the existing `SnapshotStore` with a `kind` (save/aiApply/pin/safety/legacy — Approach A); saves mint per-document version numbers. The bottom Diagnostics strip becomes a `Diagnostics | Versions` toggle (150pt / 280pt). The CodeMirror bundle gains a change gutter fed by `LineDiff` against the newest save. A progress strip observes `ShaderAssistViewModel` stream activity, with a compact twin in the always-visible preview header for the collapsed-editor state.

**Tech Stack:** Swift/SwiftUI (macOS), XCTest, CodeMirror 6 via prebuilt `cm.bundle.js` (hand-extended at its tail — the repo's established pattern, no JS build step).

## Global Constraints

- Test/build command (Defender-safe path, exclusion covers `App/ddata`): `cd App && xcodebuild test -project TrueISFEditor.xcodeproj -scheme TrueISFEditor -derivedDataPath ./ddata ARCHS=arm64 ONLY_ACTIVE_ARCH=YES`
- **Every NEW file requires `cd App && xcodegen generate` before xcodebuild sees it** — a test run without it "succeeds" with zero cases.
- TDD: write the failing test, see it fail, implement, see it pass, commit.
- **NO `git push`** — standing hard stop until the null_signal colleague heads-up. **CLOSED 2026-08-03 — the heads-up was given and the colleague confirmed go-ahead (operator, this session).**
- **No restage/relaunch of the app without announcing to Conner first** (memory rule `no-unannounced-ui-disruption`).
- No absolute operator/file paths in code; match surrounding comment density and style.
- Snapshot JSON stays backward-compatible: files without `kind` decode as `.legacy` — never a migration, never a crash.
- Scope fence: no VJ/performance features; targeted work only (no cleanup sweeps).

---

### Task 1: SnapshotKind model in SnapshotStore

**Files:**
- Modify: `App/TrueISFEditor/Models/SnapshotStore.swift`
- Modify: `App/TrueISFEditor/EditorViewModel.swift` (capture call sites)
- Test: `App/TrueISFEditorTests/SnapshotStoreTests.swift`

**Interfaces:**
- Produces: `enum SnapshotKind: Equatable { case save(number: Int), aiApply, pin(name: String?), safety, legacy }`; `Snapshot.kind: SnapshotKind`; `Snapshot.displayTitle: String`; `SnapshotStore.capture(file:params:label:kind:) -> Snapshot?`; `SnapshotStore.nextSaveNumber(for:) -> Int`; `SnapshotStore.revision: Int` (`@Published`, bumps on successful capture).
- Consumes: existing `Snapshot`, `SnapshotFile`, `ParamSnapshot`.

- [ ] **Step 1: Write the failing tests** — append to `SnapshotStoreTests.swift` (match the file's existing temp-root pattern; if it builds stores differently, keep THESE test bodies and adapt only the store construction):

```swift
    func testKindRoundTripsThroughDisk() {
        let store = SnapshotStore(rootURL: root)
        let file = ISFFile.untitled(source: "a", suggestedName: "Doc.fs")
        store.capture(file: file, params: ParamSnapshot(params: [:]), label: "v01", kind: .save(number: 1))
        var f2 = file; f2.source = "b"
        store.capture(file: f2, params: ParamSnapshot(params: [:]), label: "good strobe feel", kind: .pin(name: "good strobe feel"))
        var f3 = file; f3.source = "c"
        store.capture(file: f3, params: ParamSnapshot(params: [:]), label: "Before AI rewrite", kind: .aiApply)
        let snaps = store.snapshots(for: f3)   // same document key (same suggestedName)
        XCTAssertEqual(snaps.map(\.kind), [.aiApply, .pin(name: "good strobe feel"), .save(number: 1)])
    }

    func testMissingKindDecodesAsLegacy() throws {
        let store = SnapshotStore(rootURL: root)
        let file = ISFFile.untitled(source: "a", suggestedName: "Old.fs")
        // Simulate a pre-kind snapshot file: write JSON without kind/number/name fields.
        let dir = root.appendingPathComponent(SnapshotStore.documentKey(for: file))
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let json = #"{"date":100.5,"label":"Opened","source":"a","params":{"params":{}}}"#
        try json.data(using: .utf8)!.write(to: dir.appendingPathComponent("20260101-000000-000.json"))
        let snaps = store.snapshots(for: file)
        XCTAssertEqual(snaps.count, 1)
        XCTAssertEqual(snaps[0].kind, .legacy)
        XCTAssertEqual(snaps[0].displayTitle, "Opened")   // legacy shows its stored label
    }

    func testNextSaveNumberSkipsNonSavesAndSurvivesGaps() {
        let store = SnapshotStore(rootURL: root)
        var file = ISFFile.untitled(source: "a", suggestedName: "N.fs")
        XCTAssertEqual(store.nextSaveNumber(for: file), 1)   // empty history → v01
        store.capture(file: file, params: ParamSnapshot(params: [:]), label: "v03", kind: .save(number: 3))
        file.source = "b"
        store.capture(file: file, params: ParamSnapshot(params: [:]), label: "Before AI rewrite", kind: .aiApply)
        XCTAssertEqual(store.nextSaveNumber(for: file), 4)   // max save + 1; aiApply doesn't count
    }

    func testDisplayTitles() {
        XCTAssertEqual(Snapshot(id: "s", date: Date(), label: "v03", source: "", params: ParamSnapshot(params: [:]), kind: .save(number: 3)).displayTitle, "v03")
        XCTAssertEqual(Snapshot(id: "s", date: Date(), label: "x", source: "", params: ParamSnapshot(params: [:]), kind: .pin(name: "warm")).displayTitle, "warm")
        XCTAssertEqual(Snapshot(id: "s", date: Date(), label: "x", source: "", params: ParamSnapshot(params: [:]), kind: .pin(name: nil)).displayTitle, "Pinned")
        XCTAssertEqual(Snapshot(id: "s", date: Date(), label: "Before restore", source: "", params: ParamSnapshot(params: [:]), kind: .safety).displayTitle, "Before restore")
    }

    func testCaptureBumpsRevisionOnlyOnWrite() {
        let store = SnapshotStore(rootURL: root)
        let file = ISFFile.untitled(source: "a", suggestedName: "R.fs")
        let r0 = store.revision
        store.capture(file: file, params: ParamSnapshot(params: [:]), label: "v01", kind: .save(number: 1))
        XCTAssertEqual(store.revision, r0 + 1)
        store.capture(file: file, params: ParamSnapshot(params: [:]), label: "v02", kind: .save(number: 2))
        XCTAssertEqual(store.revision, r0 + 1, "identical-source dedup must not bump revision")
    }
```

- [ ] **Step 2: Run to verify failure**

Run: `cd App && xcodebuild test ... -only-testing:TrueISFEditorTests/SnapshotStoreTests` (full flags from Global Constraints)
Expected: compile FAILURE — `SnapshotKind` / `kind:` / `nextSaveNumber` / `revision` not defined.

- [ ] **Step 3: Implement in `SnapshotStore.swift`**

Add above `Snapshot`:

```swift
/// What created a version. `legacy` = a pre-kind snapshot file (decoded tolerant, never migrated).
enum SnapshotKind: Equatable {
    case save(number: Int)
    case aiApply
    case pin(name: String?)
    case safety
    case legacy
}
```

Extend `Snapshot` (explicit init keeps existing call sites compiling via the default):

```swift
struct Snapshot: Identifiable, Equatable {
    let id: String            // filename stem
    let date: Date
    let label: String         // "Opened", "Before AI rewrite", "v03", ...
    let source: String
    let params: ParamSnapshot
    let kind: SnapshotKind

    init(id: String, date: Date, label: String, source: String, params: ParamSnapshot,
         kind: SnapshotKind = .legacy) {
        self.id = id; self.date = date; self.label = label
        self.source = source; self.params = params; self.kind = kind
    }

    /// Row title: saves show their number, pins their name; everything else its stored label.
    var displayTitle: String {
        switch kind {
        case .save(let n): return String(format: "v%02d", n)
        case .pin(let name): return name ?? "Pinned"
        case .aiApply, .safety, .legacy: return label
        }
    }
}
```

In `SnapshotStore`: add `@Published private(set) var revision = 0`. Extend `SnapshotFile` with `let kind: String?`, `let number: Int?`, `let name: String?` and add the codec (separate fields — free-text pin names need no escaping, PM F5):

```swift
    private static func decodeKind(_ kind: String?, number: Int?, name: String?) -> SnapshotKind {
        switch kind {
        case "save": if let n = number { return .save(number: n) }; return .legacy
        case "aiApply": return .aiApply
        case "pin": return .pin(name: name)
        case "safety": return .safety
        default: return .legacy   // absent or unknown → tolerant
        }
    }
    private static func encodeKind(_ k: SnapshotKind) -> (kind: String?, number: Int?, name: String?) {
        switch k {
        case .save(let n): return ("save", n, nil)
        case .aiApply: return ("aiApply", nil, nil)
        case .pin(let name): return ("pin", nil, name)
        case .safety: return ("safety", nil, nil)
        case .legacy: return (nil, nil, nil)
        }
    }
```

Thread `kind` through: `snapshots(for:)` maps `SnapshotStore.decodeKind(f.kind, number: f.number, name: f.name)` into each `Snapshot`; `capture` gains `kind: SnapshotKind = .legacy` as its last parameter, writes the encoded triple into `SnapshotFile`, bumps `revision += 1` just before `return Snapshot(...)` (i.e. only on a successful write), and passes `kind` into the returned `Snapshot`. Add:

```swift
    /// v-number the NEXT ⌘S will mint for this document: highest existing save number + 1.
    func nextSaveNumber(for file: ISFFile) -> Int {
        let maxSave = snapshots(for: file).compactMap { snap -> Int? in
            if case .save(let n) = snap.kind { return n } else { return nil }
        }.max() ?? 0
        return maxSave + 1
    }
```

- [ ] **Step 4: Update EditorViewModel capture call sites with real kinds** — in `EditorViewModel.swift`, exact edits:
  - `open(_:)` line ~188: `label: "Opened"` → `label: "Opened", kind: .safety`
  - `loadImported` line ~217: `label: "Imported"` → `label: "Imported", kind: .safety`
  - `loadExample` line ~234: `label: "Opened"` → `label: "Opened", kind: .safety`
  - `restore(_:)` line ~270: `label: "Before restore"` → `label: "Before restore", kind: .safety`
  - `apply(_:)` line ~292: `label: "Before AI fix"` → `label: "Before AI fix", kind: .aiApply`
  - `replaceSourceFromAssist` line ~300: `label: "Before AI rewrite"` → `label: "Before AI rewrite", kind: .aiApply`

- [ ] **Step 5: Run SnapshotStore + EditorViewModelSnapshot tests**

Run: `... -only-testing:TrueISFEditorTests/SnapshotStoreTests -only-testing:TrueISFEditorTests/EditorViewModelSnapshotTests`
Expected: PASS (existing tests keep passing — labels unchanged; `Snapshot` init default keeps old constructions compiling).

- [ ] **Step 6: Commit**

```bash
git add App/TrueISFEditor/Models/SnapshotStore.swift App/TrueISFEditor/EditorViewModel.swift App/TrueISFEditorTests/SnapshotStoreTests.swift
git commit -m "feat(versions): SnapshotKind (save/aiApply/pin/safety/legacy) + numbered-save plumbing"
```

---

### Task 2: Saves mint numbered versions; cached version state on the VM

**Files:**
- Modify: `App/TrueISFEditor/EditorViewModel.swift`
- Test: `App/TrueISFEditorTests/EditorViewModelSnapshotTests.swift`

**Interfaces:**
- Produces: `EditorViewModel.nextSaveVersion: Int` (`@Published`), `EditorViewModel.lastSaveSource: String?`, `EditorViewModel.versionCount: Int` (`@Published`), `EditorViewModel.refreshVersionState()`, `EditorViewModel.pin(name: String?)`. Saves capture `kind: .save(number:)`.
- Consumes: Task 1's `nextSaveNumber(for:)`, `capture(...kind:)`, `Snapshot.kind`.

- [ ] **Step 1: Write the failing tests** (append to `EditorViewModelSnapshotTests.swift`):

```swift
    func testSaveAsMintsNumberedVersion() throws {
        let vm = makeVM()
        let url = root.appendingPathComponent("mint.fs")
        vm.saveAs(url)
        let snaps = vm.snapshots.snapshots(for: vm.file)
        XCTAssertEqual(snaps.first?.kind, .save(number: 1))
        XCTAssertEqual(snaps.first?.displayTitle, "v01")
        XCTAssertEqual(vm.nextSaveVersion, 2)
        XCTAssertEqual(vm.lastSaveSource, vm.file.source)
    }

    func testUnchangedSaveMintsNothing() throws {
        let vm = makeVM()
        let url = root.appendingPathComponent("same.fs")
        vm.saveAs(url)
        vm.saveInPlace()   // identical source — dedup, no v02
        let saves = vm.snapshots.snapshots(for: vm.file).filter {
            if case .save = $0.kind { return true } else { return false }
        }
        XCTAssertEqual(saves.count, 1)
        XCTAssertEqual(vm.nextSaveVersion, 2)
    }

    func testAIApplyThenSaveNumbersSequentially() throws {
        let vm = makeVM()
        let url = root.appendingPathComponent("seq.fs")
        vm.saveAs(url)                                                    // v01
        vm.replaceSourceFromAssist("/*{}*/ void main(){ gl_FragColor = vec4(0.5); }") // aiApply capture
        vm.saveInPlace()                                                  // v02
        let snaps = vm.snapshots.snapshots(for: vm.file)
        XCTAssertEqual(snaps.first?.kind, .save(number: 2))
        XCTAssertTrue(snaps.contains { $0.kind == .aiApply })
    }

    func testPinCapturesWithName() {
        let vm = makeVM()
        vm.pin(name: "good strobe feel")
        let snaps = vm.snapshots.snapshots(for: vm.file)
        XCTAssertEqual(snaps.first?.kind, .pin(name: "good strobe feel"))
        XCTAssertEqual(snaps.first?.displayTitle, "good strobe feel")
    }
```

- [ ] **Step 2: Run to verify failure** — `-only-testing:TrueISFEditorTests/EditorViewModelSnapshotTests`. Expected: compile FAIL (`nextSaveVersion`, `pin` undefined).

- [ ] **Step 3: Implement in `EditorViewModel.swift`** — add near the versions section:

```swift
    // MARK: version state (cached — snapshots(for:) reads disk; never call it per-render)

    /// v-number the next save mints (drives the "⌘S saves vNN" pill).
    @Published private(set) var nextSaveVersion = 1
    /// Timeline length (drives the Versions tab badge).
    @Published private(set) var versionCount = 0
    /// Source of the newest `save` version — the change-gutter baseline (nil = no saves yet).
    private(set) var lastSaveSource: String?

    /// Re-read version state from the store. Call after anything that captures or switches document.
    func refreshVersionState() {
        let snaps = snapshots.snapshots(for: file)
        versionCount = snaps.count
        nextSaveVersion = (snaps.compactMap { snap -> Int? in
            if case .save(let n) = snap.kind { return n } else { return nil }
        }.max() ?? 0) + 1
        lastSaveSource = snaps.first { if case .save = $0.kind { return true } else { return false } }?.source
    }

    /// Pin the current editor state as a named version (Versions panel + button).
    func pin(name: String?) {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let clean = (trimmed?.isEmpty ?? true) ? nil : trimmed
        snapshots.capture(file: file, params: paramStore.exportSnapshot(),
                          label: clean ?? "Pinned", kind: .pin(name: clean))
        refreshVersionState()
        statusMessage = "Pinned \(clean ?? "current version")"
    }

    /// Successful save → mint the numbered version (dedup-aware status).
    private func mintSaveVersion() {
        let n = snapshots.nextSaveNumber(for: file)
        if let snap = snapshots.capture(file: file, params: paramStore.exportSnapshot(),
                                        label: String(format: "v%02d", n), kind: .save(number: n)) {
            statusMessage = "Saved \(file.displayName) — \(snap.displayTitle)"
        } else {
            statusMessage = "Saved \(file.displayName)"
        }
        assistApplied = false
        refreshVersionState()
    }
```

Rewrite the save funcs (keep `presentSaveError`):

```swift
    func saveInPlace() {
        guard !file.needsSaveAs else { return }   // App routes untitled to Save As
        do { try file.save(); mintSaveVersion() }
        catch { presentSaveError(error) }
    }
    func saveAs(_ url: URL) {
        do { try file.save(to: url); mintSaveVersion() }
        catch { presentSaveError(error) }
    }
```

(`assistApplied` doesn't exist until Task 3 — declare it now as `@Published private(set) var assistApplied = false` with a doc comment "set by replaceSourceFromAssist (Task 3 wires the rest)". Task 3's tests cover its lifecycle.)

Call `refreshVersionState()` at the end of: `init` (after `recompile`), `open`, `newUntitled`, `loadImported`, `loadExample`, `restore`, `apply`, `replaceSourceFromAssist`.

- [ ] **Step 4: Run tests** — same filter. Expected: PASS.
- [ ] **Step 5: Commit**

```bash
git add App/TrueISFEditor/EditorViewModel.swift App/TrueISFEditorTests/EditorViewModelSnapshotTests.swift
git commit -m "feat(versions): saves mint v-numbered versions; cached version state + pin on the VM"
```

---

### Task 3: Loud dirty state — toolbar pill + post-apply save nudge

**Files:**
- Modify: `App/TrueISFEditor/EditorViewModel.swift`
- Modify: `App/TrueISFEditor/Views/EditorScreen.swift`
- Test: `App/TrueISFEditorTests/EditorViewModelSnapshotTests.swift`

**Interfaces:**
- Produces: `EditorViewModel.assistApplied: Bool` full lifecycle; `EditorViewModel.clearAssistNudge()`. EditorScreen: dirty pill + nudge bar; `bottomTab` enum `BottomPanelTab { case diagnostics, versions }` (@State, consumed by Task 4).
- Consumes: `nextSaveVersion` (Task 2).

- [ ] **Step 1: Write the failing tests**:

```swift
    func testAssistAppliedLifecycle() {
        let vm = makeVM()
        XCTAssertFalse(vm.assistApplied)
        vm.replaceSourceFromAssist("/*{}*/ void main(){ gl_FragColor = vec4(0.1); }")
        XCTAssertTrue(vm.assistApplied, "AI apply raises the save-nudge flag")
        vm.clearAssistNudge()
        XCTAssertFalse(vm.assistApplied)
    }

    func testManualEditClearsAssistNudge() {
        let vm = makeVM()
        vm.replaceSourceFromAssist("/*{}*/ void main(){ gl_FragColor = vec4(0.1); }")
        vm.editor.onChange?("/*{}*/ void main(){ gl_FragColor = vec4(0.2); }")  // user typed
        XCTAssertFalse(vm.assistApplied, "a manual edit makes 'Rewrite applied' stale")
        XCTAssertTrue(vm.file.isDirty)
    }

    func testSaveClearsAssistNudge() throws {
        let vm = makeVM()
        vm.replaceSourceFromAssist("/*{}*/ void main(){ gl_FragColor = vec4(0.1); }")
        vm.saveAs(root.appendingPathComponent("nudge.fs"))
        XCTAssertFalse(vm.assistApplied)
    }
```

- [ ] **Step 2: Run to verify failure** — Expected: `clearAssistNudge` undefined / lifecycle asserts fail.
- [ ] **Step 3: Implement** — in `EditorViewModel`:
  - `replaceSourceFromAssist`: set `assistApplied = true` (after `file.source = source`).
  - `sourceEdited`: first line `assistApplied = false` (fires only on real user edits — programmatic `setText` doesn't echo).
  - Add `func clearAssistNudge() { assistApplied = false }`.
  - Document-switch paths (`open`/`newUntitled`/`loadImported`/`loadExample`): `assistApplied = false`.

  In `EditorScreen.swift`, replace the dirty dot (line ~58):

```swift
                        if vm.file.isDirty {
                            Text(vm.assistApplied
                                 ? "Rewrite applied — ⌘S saves v\(String(format: "%02d", vm.nextSaveVersion))"
                                 : (vm.file.needsSaveAs
                                    ? "Edited — unsaved"
                                    : "Edited — ⌘S saves v\(String(format: "%02d", vm.nextSaveVersion))"))
                                .font(.caption)
                                .padding(.horizontal, 7).padding(.vertical, 2)
                                .background((vm.assistApplied ? Color.orange : Color.secondary).opacity(0.18),
                                            in: Capsule())
                                .foregroundStyle(vm.assistApplied ? Color.orange : Color.secondary)
                        }
```

  Add the nudge bar to `shaderAssistSection`'s `switch shaderAssist.state` — in `case .idle, .running:` replace `EmptyView()` with:

```swift
            case .idle, .running:
                if vm.assistApplied, case .idle = shaderAssist.state {
                    HStack(spacing: 6) {
                        Image(systemName: "wand.and.stars")
                        Text("Rewrite applied — unsaved. ⌘S saves v\(String(format: "%02d", vm.nextSaveVersion))")
                        Button("View Changes") { bottomTab = .versions }
                            .controlSize(.small)
                        Spacer()
                    }
                    .font(.caption).foregroundStyle(.orange)
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .background(.orange.opacity(0.1))
                } else {
                    EmptyView()
                }
```

  Declare at the top of `EditorScreen`: `enum BottomPanelTab { case diagnostics, versions }` and `@State private var bottomTab: BottomPanelTab = .diagnostics` (Task 4 wires the panel; `View Changes` compiles against it now). Add `.onChange(of: shaderAssist.state) { s in if case .running = s { vm.clearAssistNudge() } }` next to the existing `.onChange` modifiers (new-run clears the stale nudge, PM F4).

- [ ] **Step 4: Run tests + full EditorViewModel filters** — Expected: PASS.
- [ ] **Step 5: Commit**

```bash
git add App/TrueISFEditor/EditorViewModel.swift App/TrueISFEditor/Views/EditorScreen.swift App/TrueISFEditorTests/EditorViewModelSnapshotTests.swift
git commit -m "feat(versions): loud dirty pill + post-AI-apply save nudge with clear rules"
```

---

### Task 4: Bottom panel `Diagnostics | Versions` toggle + VersionsPanel

**Files:**
- Create: `App/TrueISFEditor/Views/VersionsPanel.swift`
- Modify: `App/TrueISFEditor/Views/EditorScreen.swift`
- Modify: `App/project.yml`? — NO project.yml edit needed; just run `xcodegen generate` (it globs sources).
- Test: `App/TrueISFEditorTests/EditorViewModelSnapshotTests.swift` (restore-through-panel path is `vm.restore` — already covered; new test: revision-driven reload derives from Task 1's revision test. UI list itself is exercised by the app suite building it.)

**Interfaces:**
- Produces: `VersionsPanel(vm:)` SwiftUI view; EditorScreen bottom panel swaps `DiagnosticsPanel` ↔ `VersionsPanel` on `bottomTab`, 150pt/280pt heights (PM F1); `vm.requestVersions` routes to the tab (no more sheet — retirement completes in Task 7).
- Consumes: `vm.snapshots.snapshots(for:)`, `vm.snapshots.$revision`, `vm.restore(_:)`, `vm.pin(name:)`, `Snapshot.displayTitle/kind`, `DiffView`, `BottomPanelTab` (Task 3).

- [ ] **Step 1: Create `VersionsPanel.swift`** (no failing-test cycle for pure view code — the store/VM logic it calls is already tested; the app suite compiles it):

```swift
import SwiftUI

/// The Versions tab of the bottom panel: timeline left, selected-version diff right.
/// Replaces the old ⌘⌥V SnapshotListView sheet (D1) — same data, embedded and always at hand.
struct VersionsPanel: View {
    @ObservedObject var vm: EditorViewModel
    @State private var versions: [Snapshot] = []
    @State private var selectedID: String?
    @State private var pinName = ""
    @State private var showPinField = false

    private var selected: Snapshot? { versions.first { $0.id == selectedID } }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text("Versions (\(versions.count))").font(.headline)
                Spacer()
                if showPinField {
                    TextField("Pin name (optional)", text: $pinName)
                        .textFieldStyle(.roundedBorder).frame(width: 180)
                        .onSubmit { commitPin() }
                    Button("Pin") { commitPin() }.controlSize(.small)
                    Button("Cancel") { showPinField = false; pinName = "" }.controlSize(.small)
                } else {
                    Button {
                        showPinField = true
                    } label: { Label("Pin", systemImage: "pin") }
                        .controlSize(.small)
                        .help("Pin the current editor state as a named version")
                }
            }
            if versions.isEmpty {
                Text("No versions yet — saves (⌘S), AI applies, and pins land here.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HSplitView {
                    List(selection: $selectedID) {
                        ForEach(versions) { s in row(s).tag(s.id) }
                    }
                    .frame(minWidth: 170, idealWidth: 210)
                    VStack(alignment: .leading, spacing: 6) {
                        if let s = selected {
                            HStack {
                                Text("\(s.displayTitle) → current source")
                                    .font(.caption).foregroundStyle(.secondary)
                                Spacer()
                                Button("Restore") { vm.restore(s) }
                                    .buttonStyle(.borderedProminent).controlSize(.small)
                            }
                            DiffView(old: s.source, new: vm.file.source)
                        } else {
                            Text("Select a version to compare and restore.")
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                    .padding(.leading, 6)
                    .frame(minWidth: 320)
                }
            }
        }
        .onAppear(perform: reload)
        .onReceive(vm.snapshots.$revision) { _ in reload() }
        .onChange(of: vm.documentGeneration) { _ in selectedID = nil; reload() }
    }

    private func commitPin() {
        vm.pin(name: pinName)
        pinName = ""; showPinField = false
    }

    private func reload() { versions = vm.snapshots.snapshots(for: vm.file) }

    @ViewBuilder private func row(_ s: Snapshot) -> some View {
        HStack(spacing: 6) {
            Image(systemName: glyph(s.kind))
                .foregroundStyle(tint(s.kind))
                .frame(width: 14)
            VStack(alignment: .leading, spacing: 1) {
                Text(s.displayTitle).font(.callout)
                Text(s.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private func glyph(_ k: SnapshotKind) -> String {
        switch k {
        case .save: return "internaldrive"
        case .aiApply: return "wand.and.stars"
        case .pin: return "pin.fill"
        case .safety, .legacy: return "clock.arrow.circlepath"
        }
    }
    private func tint(_ k: SnapshotKind) -> Color {
        switch k {
        case .save: return .blue
        case .aiApply: return .orange
        case .pin: return .yellow
        case .safety, .legacy: return .secondary
        }
    }
}
```

- [ ] **Step 2: Swap the bottom panel in `EditorScreen.swift`** — replace the `DiagnosticsPanel(...)` block (lines ~36-42) with:

```swift
                        Picker("", selection: $bottomTab) {
                            Text("Diagnostics (\(vm.diagnostics.diagnostics.count))").tag(BottomPanelTab.diagnostics)
                            Text("Versions (\(vm.versionCount))").tag(BottomPanelTab.versions)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .fixedSize()
                        .padding(.top, 6)
                        Group {
                            if bottomTab == .diagnostics {
                                DiagnosticsPanel(
                                    diagnostics: vm.diagnostics.diagnostics,
                                    sourceLines: vm.file.source.components(separatedBy: "\n"),
                                    onJump: { vm.editor.revealLine($0) },
                                    onApply: { vm.apply($0) })
                            } else {
                                VersionsPanel(vm: vm)
                            }
                        }
                        // PM F1: a usable inline diff can't live in the 150pt diagnostics strip.
                        .frame(height: bottomTab == .versions ? 280 : 150)
                        .padding(6)
```

  (Keep `DiagnosticsPanel`'s internal "Diagnostics (N)" headline REMOVED from duplication: pass-through is fine for now — the segmented control carries the count; if the double count reads badly, delete the `Text("Diagnostics…")` headline line inside `DiagnosticsPanel.swift` in this same task.)

  Route the Versions command to the tab — replace the `.sheet(isPresented: $vm.requestVersions) { SnapshotListView(vm: vm) }` modifier with:

```swift
        .onChange(of: vm.requestVersions) { open in
            guard open else { return }
            editorCollapsed = false          // panel lives in the editor column
            bottomTab = .versions
            vm.requestVersions = false
        }
```

  The toolbar clock button and ⌘⌥V menu item keep setting `vm.requestVersions = true` — unchanged.

- [ ] **Step 3: `cd App && xcodegen generate`** (new file!) then run the FULL app suite. Expected: all green, count grows by 0 tests but the new view compiles into the target.
- [ ] **Step 4: Commit**

```bash
git add App/TrueISFEditor/Views/VersionsPanel.swift App/TrueISFEditor/Views/EditorScreen.swift App/TrueISFEditor.xcodeproj/project.pbxproj
git commit -m "feat(versions): embedded Diagnostics|Versions bottom panel with diff, restore, pin"
```

  (If `App/TrueISFEditor.xcodeproj` is gitignored/regenerated, commit without it — check `git status` first.)

---

### Task 5: In-editor change gutter (CodeMirror bridge + LineDiff marks)

**Files:**
- Modify: `App/TrueISFEditor/Resources/cm.bundle.js` (tail — the repo's established hand-extension point)
- Modify: `App/TrueISFEditor/Resources/code-editor.html`
- Modify: `App/TrueISFEditor/CodeEditorView.swift`
- Modify: `App/TrueISFEditor/Models/LineDiff.swift`
- Modify: `App/TrueISFEditor/EditorViewModel.swift`
- Test: `App/TrueISFEditorTests/LineDiffTests.swift`

**Interfaces:**
- Produces: `LineDiff.changeMarks(old:new:) -> (added: [Int], changed: [Int])` (1-based lines in NEW text); `CodeEditorController.setChangeMarks(added:changed:)`; JS `window.setChangeMarks(added, changed)`; VM pushes marks on every recompile using `lastSaveSource` as baseline.
- Consumes: `LineDiff.diff`, `lastSaveSource` (Task 2), the `setDiagnostics` ready-gating pattern.

- [ ] **Step 1: Write the failing tests** (append to `LineDiffTests.swift`):

```swift
    // MARK: changeMarks — gutter bars vs the last save

    func testChangeMarksPureInsertionIsAdded() {
        let m = LineDiff.changeMarks(old: "a\nb", new: "a\nX\nb")
        XCTAssertEqual(m.added, [2])
        XCTAssertEqual(m.changed, [])
    }

    func testChangeMarksReplacementIsChanged() {
        let m = LineDiff.changeMarks(old: "a\nOLD\nc", new: "a\nNEW\nc")
        XCTAssertEqual(m.added, [])
        XCTAssertEqual(m.changed, [2])
    }

    func testChangeMarksReplaceRunPlusGrowth() {
        // 2 lines became 3: the first two pair as changed, the overflow is added.
        let m = LineDiff.changeMarks(old: "a\nx\ny\nz", new: "a\nX2\nY2\nEXTRA\nz")
        XCTAssertEqual(m.changed, [2, 3])
        XCTAssertEqual(m.added, [4])
    }

    func testChangeMarksIdenticalIsEmpty() {
        let m = LineDiff.changeMarks(old: "a\nb", new: "a\nb")
        XCTAssertEqual(m.added, []); XCTAssertEqual(m.changed, [])
    }
```

- [ ] **Step 2: Run to verify failure** — `-only-testing:TrueISFEditorTests/LineDiffTests`. Expected: compile FAIL (`changeMarks` undefined).
- [ ] **Step 3: Implement `changeMarks` in `LineDiff.swift`** (below `rangeSummary`):

```swift
    /// Gutter-bar sets vs a baseline: lines ADDED in `new`, and added lines that pair 1:1 with a
    /// preceding removed run — those read as CHANGED. Line numbers are 1-based in `new`.
    static func changeMarks(old: String, new: String) -> (added: [Int], changed: [Int]) {
        var added: [Int] = [], changed: [Int] = []
        var pendingRemoved = 0
        for line in diff(old: old, new: new) {
            switch line.kind {
            case .same: pendingRemoved = 0
            case .removed: pendingRemoved += 1
            case .added:
                guard let n = line.newLine else { continue }
                if pendingRemoved > 0 { changed.append(n); pendingRemoved -= 1 }
                else { added.append(n) }
            }
        }
        return (added, changed)
    }
```

- [ ] **Step 4: Run LineDiff tests** — Expected: PASS. Commit the model half:

```bash
git add App/TrueISFEditor/Models/LineDiff.swift App/TrueISFEditorTests/LineDiffTests.swift
git commit -m "feat(gutter): LineDiff.changeMarks — added/changed line sets vs a baseline"
```

- [ ] **Step 5: Extend `cm.bundle.js`** — inside the IIFE tail, directly ABOVE the line `window.__createEditor = function(parent, initialDoc, onChange) {`, insert:

```js
  var setChangeMarksEffect = StateEffect.define();
  var ChangeBarMarker = class extends GutterMarker {
    constructor(cls) { super(); this.cls = cls; }
    eq(other) { return other.cls === this.cls; }
    toDOM() { var el = document.createElement("div"); el.className = this.cls; return el; }
  };
  var addedBar = new ChangeBarMarker("cm-changebar cm-changebar-added");
  var changedBar = new ChangeBarMarker("cm-changebar cm-changebar-changed");
  var changeMarksField = StateField.define({
    create: function() { return RangeSet.empty; },
    update: function(set, tr) {
      set = set.map(tr.changes);
      for (var e of tr.effects) if (e.is(setChangeMarksEffect)) set = e.value;
      return set;
    }
  });
  window.__cmChangeGutter = [
    changeMarksField,
    gutter({
      class: "cm-changegutter",
      markers: function(view) { return view.state.field(changeMarksField); }
    })
  ];
  // added/changed: 1-based line numbers in the current doc. Out-of-range lines are dropped.
  window.__cmSetChangeMarks = function(view, added, changed) {
    var doc = view.state.doc, ranges = [];
    function push(lines, marker) {
      (lines || []).forEach(function(n) {
        if (n >= 1 && n <= doc.lines) ranges.push(marker.range(doc.line(n).from));
      });
    }
    push(added || [], addedBar);
    push(changed || [], changedBar);
    ranges.sort(function(a, b) { return a.from - b.from; });
    view.dispatch({ effects: setChangeMarksEffect.of(RangeSet.of(ranges, true)) });
  };
```

  In `__createEditor`'s `extensions: [` array, add `window.__cmChangeGutter,` after `basicSetup,`.

- [ ] **Step 6: Extend `code-editor.html`** — next to `setDiagnostics`, add:

```js
  // added/changed: 1-based line arrays — colored gutter bars vs the last saved version.
  window.setChangeMarks = function (added, changed) {
    if (!view || !window.__cmSetChangeMarks) return;
    window.__cmSetChangeMarks(view, added || [], changed || []);
  };
```

  And in the page's `<style>` block:

```css
    .cm-changegutter { width: 4px; }
    .cm-changebar { width: 3px; height: 100%; border-radius: 1px; }
    .cm-changebar-added { background: #4ec9b0; }
    .cm-changebar-changed { background: #d7ba7d; }
```

- [ ] **Step 7: Bridge in `CodeEditorController`** (mirror the `pendingDiagnostics` pattern exactly):

```swift
    private var pendingChangeMarks: (added: [Int], changed: [Int])?

    /// Colored gutter bars vs the last saved version. Empty arrays clear the gutter.
    func setChangeMarks(added: [Int], changed: [Int]) {
        guard ready, initialized else { pendingChangeMarks = (added, changed); return }
        guard let a = try? JSONEncoder().encode(added), let c = try? JSONEncoder().encode(changed),
              let aj = String(data: a, encoding: .utf8), let cj = String(data: c, encoding: .utf8) else { return }
        webView.evaluateJavaScript("setChangeMarks(\(aj), \(cj));")
    }
```

  In the `"ready"` handler, after the pendingDiagnostics flush add:

```swift
                    if let m = self?.pendingChangeMarks { self?.pendingChangeMarks = nil; self?.setChangeMarks(added: m.added, changed: m.changed) }
```

- [ ] **Step 8: Push marks from `EditorViewModel`** — add:

```swift
    /// Recompute gutter bars vs the last save. No saves yet ⇒ clear.
    private func updateChangeMarks() {
        guard let baseline = lastSaveSource else {
            editor.setChangeMarks(added: [], changed: [])
            return
        }
        let m = LineDiff.changeMarks(old: baseline, new: file.source)
        editor.setChangeMarks(added: m.added, changed: m.changed)
    }
```

  Call `updateChangeMarks()`: at the end of `refreshVersionState()` (covers init/open/save/apply/restore — everything that moves the baseline or the text through those paths) and in `recompile(immediate:)`'s debounced Task after `preview.load(isf: src)` (covers per-keystroke edits at the existing 300 ms cadence, no extra timers).

- [ ] **Step 9: Full app suite** (`cd App && xcodebuild test ...`). Expected: green (Resources changes ride the bundle; no xcodegen needed — no new files).
- [ ] **Step 10: Commit**

```bash
git add App/TrueISFEditor/Resources/cm.bundle.js App/TrueISFEditor/Resources/code-editor.html App/TrueISFEditor/CodeEditorView.swift App/TrueISFEditor/EditorViewModel.swift
git commit -m "feat(gutter): change bars vs last save — CodeMirror gutter bridge + VM wiring"
```

---

### Task 6: Live progress strip + collapsed-editor run badge

**Files:**
- Create: `App/TrueISFEditor/Views/AssistProgressStrip.swift`
- Modify: `App/TrueISFEditor/ShaderAssist/ShaderAssistViewModel.swift`
- Modify: `App/TrueISFEditor/Views/EditorScreen.swift`
- Test: `App/TrueISFEditorTests/ShaderAssistViewModelTests.swift`

**Interfaces:**
- Produces: VM `runStartDate: Date?`, `eventCount: Int`, `lastEventDate: Date?` (all `@Published private(set)`, reset per run, bumped per stream line); `AssistProgressStrip.clock(_ seconds: TimeInterval) -> String`; views `AssistProgressStrip(model:)` and `AssistRunBadge(model:onTap:)`.
- Consumes: `ShaderAssistViewModel.state/.transcript` stream callback, `shaderAssist.cancel()`, `editorCollapsed`.

- [ ] **Step 1: Write the failing tests** (append to `ShaderAssistViewModelTests.swift`, using that file's existing provider-fake pattern — read its head first and reuse its fixture; the assertions to add):

```swift
    func testRunResetsAndCountsStreamEvents() async {
        // Use the file's existing fake-provider fixture that lets the test drive `onLine` callbacks.
        // Assertions:
        //   after run() starts:      runStartDate != nil, eventCount == 0, lastEventDate == nil
        //   after 3 onLine calls:    eventCount == 3, lastEventDate != nil
        //   after a second run():    eventCount == 0 again (reset per run)
    }

    func testClockString() {
        XCTAssertEqual(AssistProgressStrip.clock(0), "0s")
        XCTAssertEqual(AssistProgressStrip.clock(45), "45s")
        XCTAssertEqual(AssistProgressStrip.clock(134), "2m 14s")
        XCTAssertEqual(AssistProgressStrip.clock(3701), "61m 41s")
    }
```

  (Write `testRunResetsAndCountsStreamEvents` as REAL code against the fixture found in the file — the comment block above states the required assertions; do not ship it as comments.)

- [ ] **Step 2: Run to verify failure** — Expected: compile FAIL.
- [ ] **Step 3: VM implementation** — in `ShaderAssistViewModel`:

```swift
    // MARK: run liveness (progress strip)
    @Published private(set) var runStartDate: Date?
    @Published private(set) var eventCount = 0
    @Published private(set) var lastEventDate: Date?
```

  In `run(_:source:diagnostics:)` after `state = .running(t)`: `runStartDate = Date(); eventCount = 0; lastEventDate = nil`.
  In `appendTranscript(_:)`, FIRST lines (before the formatter guard — every raw stream line proves liveness even when the formatter drops it):

```swift
        eventCount += 1
        lastEventDate = Date()
```

- [ ] **Step 4: Create `AssistProgressStrip.swift`**:

```swift
import SwiftUI
import ShadertoyISFKit

/// Liveness strip for a running assist task: honest elapsed/last-activity stats, no fake percent.
struct AssistProgressStrip: View {
    @ObservedObject var model: ShaderAssistViewModel
    let onCancel: () -> Void

    static func clock(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds))
        return s < 60 ? "\(s)s" : "\(s / 60)m \(s % 60)s"
    }

    var body: some View {
        if case .running(let task) = model.state {
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                let elapsed = model.runStartDate.map { ctx.date.timeIntervalSince($0) } ?? 0
                let quiet = model.lastEventDate.map { ctx.date.timeIntervalSince($0) }
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(Self.title(for: task)).bold()
                    Text("\(Self.clock(elapsed)) · \(model.eventCount) events")
                        .foregroundStyle(.secondary)
                    if let q = quiet {
                        Text(q > 30 ? "quiet \(Self.clock(q)) — still running" : "active \(Self.clock(q)) ago")
                            .foregroundStyle(q > 30 ? Color.orange : Color.secondary)
                    } else {
                        Text("starting…").foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Cancel", action: onCancel).controlSize(.small)
                }
                .font(.caption)
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(.quaternary.opacity(0.5))
            }
        }
    }

    static func title(for task: ShaderAssistTask) -> String {
        switch task {
        case .diagnoseAndFix: return "Diagnosing & fixing"
        case .suggestionGoals: return "Reading the shader"
        case .suggestions: return "Generating suggestions"
        case .applySuggestions: return "Rewriting shader"
        case .research: return "Researching upgrades"
        }
    }
}

/// Compact twin for the always-visible preview header while the editor pane is collapsed —
/// "visibly alive at all times" must survive ⌘⌥E (spec PM F2). Tap restores the editor pane.
struct AssistRunBadge: View {
    @ObservedObject var model: ShaderAssistViewModel
    let onTap: () -> Void

    var body: some View {
        if case .running = model.state {
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                let elapsed = model.runStartDate.map { ctx.date.timeIntervalSince($0) } ?? 0
                let quiet = model.lastEventDate.map { ctx.date.timeIntervalSince($0) } ?? 0
                Button(action: onTap) {
                    HStack(spacing: 4) {
                        ProgressView().controlSize(.small)
                        Text(AssistProgressStrip.clock(elapsed))
                            .foregroundStyle(quiet > 30 ? Color.orange : Color.secondary)
                    }
                }
                .buttonStyle(.plain)
                .help("ShaderAssist is running — click to show the editor pane")
            }
        }
    }
}
```

  (Check `ShaderAssistTask`'s exact case list in `ShadertoyISFKit/Sources/ShadertoyISFKit/ShaderAssist/ShaderAssistTypes.swift` before writing `title(for:)` — match every case; associated values are ignored with `case .suggestions:` style patterns.)

- [ ] **Step 5: Wire into `EditorScreen`** — at the end of the editor-column `VStack` (after `shaderAssistSection.padding(6)`):

```swift
                        AssistProgressStrip(model: shaderAssist, onCancel: { shaderAssist.cancel() })
```

  And in the preview-header `HStack` (next to `RenderStatsSlot`):

```swift
                        if editorCollapsed {
                            AssistRunBadge(model: shaderAssist) { editorCollapsed = false }
                        }
```

- [ ] **Step 6: `cd App && xcodegen generate`** (new file!), run `-only-testing:TrueISFEditorTests/ShaderAssistViewModelTests`, then the FULL app suite. Expected: green.
- [ ] **Step 7: Commit**

```bash
git add App/TrueISFEditor/Views/AssistProgressStrip.swift App/TrueISFEditor/ShaderAssist/ShaderAssistViewModel.swift App/TrueISFEditor/Views/EditorScreen.swift App/TrueISFEditorTests/ShaderAssistViewModelTests.swift App/TrueISFEditor.xcodeproj/project.pbxproj
git commit -m "feat(assist): live progress strip + collapsed-pane run badge — honest liveness, cancel in reach"
```

---

### Task 7: Retire the SnapshotListView sheet; full verification

**Files:**
- Delete: `App/TrueISFEditor/Views/SnapshotListView.swift`
- Modify: `App/TrueISFEditor/Views/EditorScreen.swift` (only if any sheet remnant remains from Task 4)
- Test: full app suite + kit suite

- [ ] **Step 1: Delete `SnapshotListView.swift`**; `grep -rn "SnapshotListView" App/` must return ZERO hits (exhaust-the-universe: no `head`, paste the command + count). Remove any lingering `.sheet(isPresented: $vm.requestVersions)` remnant.
- [ ] **Step 2: `cd App && xcodegen generate`** (file removal also changes the project).
- [ ] **Step 3: Full app suite + kit**: `cd App && xcodebuild test ...` then `cd ShadertoyISFKit && swift test` (or the kit's established invocation — check `scripts/` / prior handoffs; if the kit has its own xcodebuild scheme use that). Expected: all green; app suite grows by the new tests.
- [ ] **Step 4: Commit**

```bash
git add -A App/TrueISFEditor/Views App/TrueISFEditor.xcodeproj/project.pbxproj
git commit -m "refactor(versions): retire the SnapshotListView sheet — the embedded panel is the one versions UI"
```

  (NOT `git add -A` at repo root — concurrent-session rule; scope the add to the touched paths.)

- [ ] **Step 5: STAGED gate prep** — do NOT restage without announcing. Report to Conner: feature STAGED pending restage + on-device confirm of: dirty pill w/ next version, save→v01/v02 minting, Versions tab round-trip (diff/restore/pin), gutter bars after AI apply clearing on save, progress strip during a real rewrite, collapsed-pane badge.

---

## Self-Review (performed at write time)

- **Spec coverage:** §1 model+save+dirty → Tasks 1-3; §2 panel+gutter → Tasks 4-5; §3 strip+badge → Task 6; §4 error handling → dedup/tolerant-decode tests (T1), nudge-clear rules (T3), cancel path (T6); §5 testing → each task's tests + T7 full sweep + on-device gate list. Sheet retirement (§2) → T7.
- **Placeholders:** Task 6 Step 1's first test intentionally specifies assertions against a fixture that must be read first — the step explicitly requires shipping real code, not the comment block. No other TBDs.
- **Type consistency:** `SnapshotKind` cases, `capture(...kind:)`, `nextSaveNumber(for:)`, `revision`, `nextSaveVersion`, `lastSaveSource`, `versionCount`, `assistApplied`, `clearAssistNudge()`, `pin(name:)`, `changeMarks(old:new:)`, `setChangeMarks(added:changed:)`, `BottomPanelTab`, `AssistProgressStrip.clock/title` — names match across all tasks.
