# Phase D — Authoring UX Implementation Plan (Plan 2)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship ROADMAP Phase D items 0–2 plus the null_signal template ports: pop-out editing mode (inline preview pauses + panel expands while the output window is out), version snapshots with restore, a real line diff in the AI apply preview, and a bundled "NS" ISF template pack (Layer Blend + 5 post FX) with MIT attribution.

**Architecture:** All state changes flow through the existing seams — `PreviewEngine` protocol → `PreviewCoordinator` → `EditorViewModel` (the B1 ParamStore keystone). Pop-out mode is a published `isOpen` on `OutputWindowManager` driving a `popOutEditing` flag on the view model. Snapshots are a disk-backed `SnapshotStore` (one JSON file per version, bounded, name-keyed param codec per the null_signal preset doctrine). The diff is a pure `LineDiff` engine + one `DiffView` reused by the apply preview and the versions list. Templates are repo `/templates/*.fs` shipped as a bundle folder reference (same mechanism as `/samples`) with a `TemplateCatalog` + File-menu submenu.

**Tech Stack:** Swift 5 / SwiftUI, macOS 13 target, XcodeGen (`App/project.yml`), XCTest, ISF 2.0 GLSL (Metal via ISFMSLKit).

## Global Constraints

- **Deployment target macOS 13.0** — no macOS-14-only API without an availability fallback (see `settingsGearButton` for the house pattern).
- **Run app tests:** `cd App && xcodebuild test -scheme TrueISFEditor -destination 'platform=macOS,arch=arm64' ARCHS=arm64 ONLY_ACTIVE_ARCH=YES -derivedDataPath ./ddata -only-testing:TrueISFEditorTests/<Class>` (drop `-only-testing:` for the full suite). Kit suite: `cd ShadertoyISFKit && swift test`.
- **After any `App/project.yml` change:** `cd App && xcodegen generate` before building.
- **project.yml test-target trap (bit twice in Plan 1):** the `TrueISFEditorTests` target lists app source files EXPLICITLY. A new app file needs a `project.yml` test-sources entry ONLY if a file already in that list references it. Files tested via `@testable import TrueISFEditor` (the ParamStoreTests pattern) need NO entry. Never add a file to the test-sources list AND reference the same type through `@testable import` in one test file — that's the dual-module type clash; where a clash is unavoidable, qualify as `TrueISFEditor.TypeName` (see the comment at the top of `ParamStoreTests.swift`).
- **Nothing in this plan touches the test-sources list.** `PreviewEngine.swift` / `PreviewCoordinator.swift` (already listed) gain only methods, no new types. All new types (`LineDiff`, `SnapshotStore`, `TemplateCatalog`, …) are tested via `@testable import` only.
- **ISF/GLSL rules for the templates (Metal backend):** no ternary on vector types (rewrite as `if/else`); no `#version` directives; `gl_FragColor` + `IMG_NORM_PIXEL`/`isf_FragNormCoord`, never `texture2D`/`texture`; loop bounds must be `const int`; first-frame init uses `FRAMEINDEX < 2 || resetEvent`, never `FRAMEINDEX == 0`; a PERSISTENT buffer read inside the pass that writes it returns LAST frame's contents.
- **Scope fence (Conner, final):** no VJ features in this editor. null_signal's audio-reactive uniforms (`bass`/`mid`/`high`) are dropped from every port (terms removed or fixed to 0.0). Interactive-performance learnings go to ROADMAP Part 3 only.
- **MIT attribution (required to ship the ports):** every derived `.fs` carries `"CREDIT": "Adapted from null_signal by VJ CYBERPATROLUNIT (MIT)"` in its ISF header; `THIRD_PARTY_LICENSES/null_signal.LICENSE.txt` + an `ACKNOWLEDGEMENTS.md` section carry the full license text. **Do not push template commits to the public remote until Conner has given the colleague a courtesy heads-up (null_signal's repo is private).** **CLOSED 2026-08-03 — the heads-up was given and the colleague confirmed go-ahead (operator, this session).**
- **Commits:** conventional style matching repo history (`feat(app): …`, `fix(engine): …`), no attribution trailers.
- **Native-Metal feature status is two-state:** everything here is **STAGED** until Conner confirms on-device. Final task stages via `scripts/run-latest.sh` and verifies binary freshness by grepping a >15-char source string in the app's `.debug.dylib` (Xcode 26 serves a stub main binary — grep the dylib, not the stub).

---

### Task 1: `setPaused` through the engine seam

The pop-out mode needs to pause the inline preview through the coordinator. `MetalPreviewController.setPaused(_:)` already exists (B4) but is not on the `PreviewEngine` protocol, so `PreviewCoordinator` can't reach it.

**Files:**
- Modify: `App/TrueISFEditor/PreviewEngine.swift` (protocol + default)
- Modify: `App/TrueISFEditor/PreviewCoordinator.swift`
- Modify: `App/TrueISFEditorTests/Fakes/FakePreviewEngine.swift`
- Test: `App/TrueISFEditorTests/PreviewCoordinatorTests.swift`

**Interfaces:**
- Consumes: existing `MetalPreviewController.setPaused(_ paused: Bool)` (freezes the display link AND the B2 render clock).
- Produces: `PreviewCoordinator.setPaused(_ paused: Bool)` and `PreviewCoordinator.isPaused: Bool` (`@Published private(set)`), used by Task 3. `PreviewEngine.setPaused(_:)` with a no-op default (WebKit engine keeps the default).

- [ ] **Step 1: Write the failing tests** — append to `PreviewCoordinatorTests.swift`:

```swift
    // MARK: D0 — pause forwarding (pop-out editing mode)

    func testSetPausedForwardsToActiveEngine() {
        let fake = FakePreviewEngine()
        let coord = PreviewCoordinator(metal: fake, webkit: FakePreviewEngine())
        coord.setPaused(true)
        XCTAssertEqual(fake.pausedStates, [true])
        XCTAssertTrue(coord.isPaused)
        coord.setPaused(false)
        XCTAssertEqual(fake.pausedStates, [true, false])
        XCTAssertFalse(coord.isPaused)
    }

    func testEngineSwitchReappliesPausedState() {
        let metal = FakePreviewEngine(); let webkit = FakePreviewEngine()
        let coord = PreviewCoordinator(metal: metal, webkit: webkit)
        coord.setPaused(true)
        coord.active = .webkit
        XCTAssertEqual(webkit.pausedStates.last, true,
                       "switching engines while paused must pause the new active engine")
    }
```

And record pauses in `FakePreviewEngine` (add alongside `loadedISF`):

```swift
    private(set) var pausedStates: [Bool] = []
    func setPaused(_ paused: Bool) { pausedStates.append(paused) }
```

- [ ] **Step 2: Run to verify failure**

Run: `cd App && xcodebuild test -scheme TrueISFEditor -destination 'platform=macOS,arch=arm64' ARCHS=arm64 ONLY_ACTIVE_ARCH=YES -derivedDataPath ./ddata -only-testing:TrueISFEditorTests/PreviewCoordinatorTests`
Expected: compile FAILURE — `PreviewCoordinator` has no member `setPaused` (protocol not yet extended).

- [ ] **Step 3: Implement.** In `PreviewEngine.swift`, add to the protocol (after `resetTimeline()`):

```swift
    /// D0: pause/resume this engine's live render loop (GPU work + clock). Engines without a
    /// pausable loop no-op.
    func setPaused(_ paused: Bool)
```

and to the `extension PreviewEngine` defaults:

```swift
    /// Default (WebKit path): no pausable loop to stop.
    func setPaused(_ paused: Bool) {}
```

In `PreviewCoordinator.swift`, add below the `inputs` published property:

```swift
    /// D0: true while the render loop is user/pop-out paused. Reapplied on engine switch.
    @Published private(set) var isPaused = false
```

add the forwarding method next to `resetTimeline()`:

```swift
    /// D0: pause/resume the active engine's render loop (pop-out editing mode).
    func setPaused(_ paused: Bool) {
        isPaused = paused
        activeEngine.setPaused(paused)
    }
```

and reapply in `switchEngine()` (before the `load`):

```swift
        activeEngine.setPaused(isPaused)
```

`MetalPreviewController.setPaused` already exists and now witnesses the protocol requirement — no change there.

- [ ] **Step 4: Run to verify pass**

Same command as Step 2. Expected: PASS (all PreviewCoordinatorTests green, including the pre-existing ones).

- [ ] **Step 5: Commit**

```bash
git add App/TrueISFEditor/PreviewEngine.swift App/TrueISFEditor/PreviewCoordinator.swift App/TrueISFEditorTests/Fakes/FakePreviewEngine.swift App/TrueISFEditorTests/PreviewCoordinatorTests.swift
git commit -m "feat(preview): setPaused through the engine seam (D0 plumbing)"
```

---

### Task 2: `OutputWindowManager` publishes open/close

The pop-out's lifecycle must be observable: `isOpen` becomes `@Published`, set true on `show()`, false when the window closes, plus a programmatic `close()` for the restore banner.

**Files:**
- Modify: `App/TrueISFEditor/OutputWindow.swift`
- Test: `App/TrueISFEditorTests/OutputWindowManagerTests.swift` (create)

**Interfaces:**
- Consumes: nothing new.
- Produces: `OutputWindowManager.isOpen: Bool` (`@Published private(set)`, replaces the computed property — call sites in `EditorScreen` keep the same spelling), `OutputWindowManager.close()`.

- [ ] **Step 1: Write the failing test** — create `App/TrueISFEditorTests/OutputWindowManagerTests.swift`:

```swift
import XCTest
@testable import TrueISFEditor

@MainActor
final class OutputWindowManagerTests: XCTestCase {
    func testIsOpenTracksShowAndClose() {
        let manager = OutputWindowManager()
        XCTAssertFalse(manager.isOpen)

        manager.show(source: "/*{ \"ISFVSN\":\"2\" }*/ void main(){ gl_FragColor=vec4(1.0); }")
        XCTAssertTrue(manager.isOpen)

        manager.close()
        // NSWindow.close() posts willClose synchronously on the main thread.
        XCTAssertFalse(manager.isOpen)

        // Reopening the SAME retained window (isReleasedWhenClosed=false) must flip it back.
        manager.show(source: "/*{ \"ISFVSN\":\"2\" }*/ void main(){ gl_FragColor=vec4(1.0); }")
        XCTAssertTrue(manager.isOpen)
        manager.close()
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `cd App && xcodebuild test ... -only-testing:TrueISFEditorTests/OutputWindowManagerTests`
Expected: compile FAILURE — no member `close` (and `isOpen` is currently get-only computed, which the test's flow will also exercise).

- [ ] **Step 3: Implement.** In `OutputWindow.swift`:

Replace the computed `var isOpen` with a stored published property + observer, and add `close()`:

```swift
    /// D0: observable pop-out lifecycle — EditorScreen drives pop-out editing mode off this.
    @Published private(set) var isOpen = false
    private var closeObserver: NSObjectProtocol?
```

In `show(source:)`, inside the `if window == nil` block after `window = w`, register the observer:

```swift
            closeObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification, object: w, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.isOpen = false }
            }
```

and at the end of `show(source:)` (after `makeKeyAndOrderFront`):

```swift
        isOpen = true
```

Add:

```swift
    /// Close the pop-out programmatically (the inline "Restore Preview" affordance).
    /// willCloseNotification flips isOpen.
    func close() {
        window?.close()
    }

    deinit {
        // Block-based observers are not auto-removed (same rule as MetalPreviewController).
        if let o = closeObserver { NotificationCenter.default.removeObserver(o) }
    }
```

`update(source:)`'s `window?.isVisible == true` guard stays as is (visibility is still the right gate for debounced loads).

- [ ] **Step 4: Run to verify pass**

Same command. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add App/TrueISFEditor/OutputWindow.swift App/TrueISFEditorTests/OutputWindowManagerTests.swift
git commit -m "feat(app): OutputWindowManager publishes isOpen + close() (D0)"
```

---

### Task 3: `EditorViewModel.popOutEditing`

The view model owns the mode: one flag that pauses/resumes the inline preview. Keeping it here (not in the view) makes it unit-testable and keeps EditorScreen dumb.

**Files:**
- Modify: `App/TrueISFEditor/EditorViewModel.swift`
- Test: `App/TrueISFEditorTests/EditorViewModelTests.swift`

**Interfaces:**
- Consumes: `PreviewCoordinator.setPaused(_:)` / `.isPaused` (Task 1).
- Produces: `EditorViewModel.popOutEditing: Bool` (`@Published private(set)`), `EditorViewModel.setPopOutOpen(_ open: Bool)` — called by EditorScreen from `output.$isOpen` (Task 4).

- [ ] **Step 1: Write the failing test** — append to `EditorViewModelTests.swift`:

```swift
    // MARK: D0 — pop-out editing mode

    func testSetPopOutOpen_pausesAndResumesInlinePreview() {
        let vm = EditorViewModel(file: .untitled(source: EditorViewModel.blankTemplate))
        XCTAssertFalse(vm.popOutEditing)

        vm.setPopOutOpen(true)
        XCTAssertTrue(vm.popOutEditing)
        XCTAssertTrue(vm.preview.isPaused, "pop-out must pause the inline render loop")

        vm.setPopOutOpen(true)   // idempotent — repeated opens don't stack
        XCTAssertTrue(vm.preview.isPaused)

        vm.setPopOutOpen(false)
        XCTAssertFalse(vm.popOutEditing)
        XCTAssertFalse(vm.preview.isPaused, "closing the pop-out must resume the inline preview")
    }
```

- [ ] **Step 2: Run to verify failure**

Run: `... -only-testing:TrueISFEditorTests/EditorViewModelTests`
Expected: compile FAILURE — no member `popOutEditing`.

- [ ] **Step 3: Implement.** In `EditorViewModel.swift`, add after the `pulseEvent` method in the `params (B1)` section:

```swift
    // MARK: pop-out editing mode (D0)

    /// True while the output window is popped out: the inline preview pauses (GPU + clock) and
    /// EditorScreen collapses the preview pane so Adjust/Inputs/Passes gets the freed space.
    /// Intended use: output on a second monitor, laptop screen becomes a pure editing surface.
    @Published private(set) var popOutEditing = false

    /// Driven by EditorScreen from the output window's published isOpen.
    func setPopOutOpen(_ open: Bool) {
        guard popOutEditing != open else { return }
        popOutEditing = open
        preview.setPaused(open)
    }
```

- [ ] **Step 4: Run to verify pass** — same command, expected PASS.

- [ ] **Step 5: Commit**

```bash
git add App/TrueISFEditor/EditorViewModel.swift App/TrueISFEditorTests/EditorViewModelTests.swift
git commit -m "feat(app): popOutEditing mode state on EditorViewModel (D0)"
```

---

### Task 4: EditorScreen pop-out editing layout

View-layer wiring: collapse the inline preview pane while the pop-out is open, show a banner with a restore affordance, point the FPS readout at the pop-out's coordinator, and drive it all from `output.$isOpen`. Note the pause is belt-and-braces: `setPaused` is the explicit intent (freezes clock + loop), and removing the MTKView from the hierarchy makes `HostAwareMTKView.onWindowChange` stop the driver anyway.

**Files:**
- Modify: `App/TrueISFEditor/Views/EditorScreen.swift`

**Interfaces:**
- Consumes: `vm.popOutEditing` / `vm.setPopOutOpen(_:)` (Task 3), `output.$isOpen` / `output.close()` (Task 2).
- Produces: nothing consumed by later tasks. (UI verified on-device — final task gate.)

- [ ] **Step 1: Implement the layout.** In `EditorScreen.swift`, replace the `VSplitView { ... }` block (currently `ISFPreviewView` over `HeaderPanelView`) with:

```swift
                    // Preview over controls with a user-draggable divider. D0: while the output
                    // window is popped out the preview pane collapses entirely — the panel gets
                    // the full column and the inline render loop is paused (vm.popOutEditing).
                    VSplitView {
                        if !vm.popOutEditing {
                            ISFPreviewView(coordinator: vm.preview)
                                .frame(minHeight: 200, maxHeight: .infinity)
                        }
                        VStack(spacing: 0) {
                            if vm.popOutEditing { popOutBanner }
                            HeaderPanelView(coordinator: vm.preview, model: vm.headerModel,
                                            store: vm.paramStore, onPulse: { vm.pulseEvent($0) })
                        }
                        .frame(minHeight: 180, maxHeight: .infinity)
                        // Fresh @State per document (M30): without this, a new shader whose
                        // inputs share names with the old one keeps the old slider values.
                        .id(vm.documentGeneration)
                    }
```

- [ ] **Step 2: Add the banner** as a private computed property (near `renderControlsBar`):

```swift
    /// D0: shown in place of the inline preview while the output window is popped out.
    private var popOutBanner: some View {
        HStack(spacing: 6) {
            Image(systemName: "rectangle.on.rectangle")
            Text("Output popped out — inline preview paused")
            Spacer()
            Button("Restore Preview") { output.close() }
                .controlSize(.small)
        }
        .font(.caption).foregroundStyle(.secondary)
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(.quaternary.opacity(0.5))
    }
```

- [ ] **Step 3: Drive the mode + retarget the stats readout.** Add alongside the existing `.onReceive` modifiers:

```swift
        .onReceive(output.$isOpen) { vm.setPopOutOpen($0) }
```

and change the header-row stats slot so the readout follows the live window:

```swift
                        RenderStatsSlot(coordinator: vm.popOutEditing ? output.coordinator : vm.preview)
```

Update the pop-out button's `.help` to reflect both states:

```swift
                        .help(vm.popOutEditing
                              ? "Output is popped out — close its window (or Restore Preview) to bring the inline preview back"
                              : "Pop out the output into its own window")
```

- [ ] **Step 4: Build + full app suite** (no new unit tests — view-only; behavior gates on-device in the final task):

Run: `cd App && xcodebuild test -scheme TrueISFEditor -destination 'platform=macOS,arch=arm64' ARCHS=arm64 ONLY_ACTIVE_ARCH=YES -derivedDataPath ./ddata`
Expected: BUILD SUCCEEDED, full suite PASS (287 pre-existing + tasks 1–3 additions).

- [ ] **Step 5: Commit**

```bash
git add App/TrueISFEditor/Views/EditorScreen.swift
git commit -m "feat(app): pop-out editing mode — preview pane collapses, panel expands (D0)"
```

---

### Task 5: `LineDiff` engine

Pure, testable line diff (LCS) with display folding. No UI here.

**Files:**
- Create: `App/TrueISFEditor/Models/LineDiff.swift`
- Test: `App/TrueISFEditorTests/LineDiffTests.swift` (create)

**Interfaces:**
- Consumes: nothing.
- Produces: `DiffLine` (`kind: .same/.removed/.added`, `text`, `oldLine: Int?`, `newLine: Int?`), `DiffRow` (`.line(DiffLine)` / `.fold(count: Int, index: Int)`), `LineDiff.diff(old: String, new: String) -> [DiffLine]`, `LineDiff.displayRows(_ diff: [DiffLine], context: Int = 3) -> [DiffRow]`. Used by Task 6 (`DiffView`) and Task 10 (versions list).

- [ ] **Step 1: Write the failing tests** — create `App/TrueISFEditorTests/LineDiffTests.swift`:

```swift
import XCTest
@testable import TrueISFEditor

final class LineDiffTests: XCTestCase {
    func testIdenticalTextsAreAllSame() {
        let d = LineDiff.diff(old: "a\nb\nc", new: "a\nb\nc")
        XCTAssertEqual(d.map(\.kind), [.same, .same, .same])
        XCTAssertEqual(d.map(\.oldLine), [1, 2, 3])
        XCTAssertEqual(d.map(\.newLine), [1, 2, 3])
    }

    func testPureInsertion() {
        let d = LineDiff.diff(old: "a\nc", new: "a\nb\nc")
        XCTAssertEqual(d.map(\.kind), [.same, .added, .same])
        XCTAssertEqual(d[1].text, "b")
        XCTAssertNil(d[1].oldLine)
        XCTAssertEqual(d[1].newLine, 2)
    }

    func testPureDeletion() {
        let d = LineDiff.diff(old: "a\nb\nc", new: "a\nc")
        XCTAssertEqual(d.map(\.kind), [.same, .removed, .same])
        XCTAssertEqual(d[1].oldLine, 2)
        XCTAssertNil(d[1].newLine)
    }

    func testChangedLineIsRemovePlusAdd() {
        let d = LineDiff.diff(old: "a\nOLD\nc", new: "a\nNEW\nc")
        XCTAssertEqual(d.map(\.kind), [.same, .removed, .added, .same])
        XCTAssertEqual(d[1].text, "OLD")
        XCTAssertEqual(d[2].text, "NEW")
    }

    func testEmptyOldIsAllAdded() {
        let d = LineDiff.diff(old: "", new: "x\ny")
        // "" splits to one empty line — it pairs or removes, but every content line must be added.
        XCTAssertEqual(d.filter { $0.kind == .added }.map(\.text).filter { !$0.isEmpty }, ["x", "y"])
    }

    func testDisplayRowsFoldLongSameRuns() {
        let old = (1...30).map(String.init).joined(separator: "\n")
        let new = old + "\nEXTRA"
        let rows = LineDiff.displayRows(LineDiff.diff(old: old, new: new), context: 3)
        // 30 same lines then one added: the same-run folds to 3 + fold(24) + 3.
        guard case .fold(let count, _)? = rows.first(where: {
            if case .fold = $0 { return true } else { return false }
        }) else { return XCTFail("expected a fold row") }
        XCTAssertEqual(count, 24)
        // Changed line always survives folding.
        XCTAssertTrue(rows.contains { if case .line(let l) = $0 { return l.text == "EXTRA" } else { return false } })
    }

    func testShortSameRunsDoNotFold() {
        let rows = LineDiff.displayRows(LineDiff.diff(old: "a\nb\nc\nX", new: "a\nb\nc\nY"), context: 3)
        XCTAssertFalse(rows.contains { if case .fold = $0 { return true } else { return false } })
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `... -only-testing:TrueISFEditorTests/LineDiffTests`
Expected: compile FAILURE — `LineDiff` not defined.

- [ ] **Step 3: Implement** — create `App/TrueISFEditor/Models/LineDiff.swift`:

```swift
import Foundation

/// One row of a computed line diff.
struct DiffLine: Equatable, Identifiable {
    enum Kind: Equatable { case same, removed, added }
    let kind: Kind
    let text: String
    /// 1-based line number in the old text (nil for added lines).
    let oldLine: Int?
    /// 1-based line number in the new text (nil for removed lines).
    let newLine: Int?
    var id: String { "\(kind)-\(oldLine ?? 0)-\(newLine ?? 0)" }
}

/// A display row: a diff line, or a fold standing in for a run of unchanged lines.
enum DiffRow: Equatable, Identifiable {
    case line(DiffLine)
    case fold(count: Int, index: Int)
    var id: String {
        switch self {
        case .line(let l): return l.id
        case .fold(_, let i): return "fold-\(i)"
        }
    }
}

/// LCS line diff (D2). Shader sources are small (hundreds of lines), so the O(n·m) table is
/// fine; a size guard degrades giant inputs to remove-all/add-all instead of blowing memory.
enum LineDiff {
    static func diff(old: String, new: String) -> [DiffLine] {
        let a = old.components(separatedBy: "\n")
        let b = new.components(separatedBy: "\n")

        // ~2000×2000 lines ≈ 32 MB of Int — anything bigger degrades gracefully.
        guard a.count * b.count <= 4_000_000 else {
            return a.enumerated().map { DiffLine(kind: .removed, text: $1, oldLine: $0 + 1, newLine: nil) }
                 + b.enumerated().map { DiffLine(kind: .added, text: $1, oldLine: nil, newLine: $0 + 1) }
        }

        var table = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in stride(from: a.count - 1, through: 0, by: -1) {
            for j in stride(from: b.count - 1, through: 0, by: -1) {
                table[i][j] = a[i] == b[j] ? table[i + 1][j + 1] + 1
                                           : max(table[i + 1][j], table[i][j + 1])
            }
        }

        var result: [DiffLine] = []
        var i = 0, j = 0
        while i < a.count, j < b.count {
            if a[i] == b[j] {
                result.append(DiffLine(kind: .same, text: a[i], oldLine: i + 1, newLine: j + 1))
                i += 1; j += 1
            } else if table[i + 1][j] >= table[i][j + 1] {
                result.append(DiffLine(kind: .removed, text: a[i], oldLine: i + 1, newLine: nil))
                i += 1
            } else {
                result.append(DiffLine(kind: .added, text: b[j], oldLine: nil, newLine: j + 1))
                j += 1
            }
        }
        while i < a.count {
            result.append(DiffLine(kind: .removed, text: a[i], oldLine: i + 1, newLine: nil)); i += 1
        }
        while j < b.count {
            result.append(DiffLine(kind: .added, text: b[j], oldLine: nil, newLine: j + 1)); j += 1
        }
        return result
    }

    /// Fold unchanged runs for display: keep `context` lines on each side of a change, collapse
    /// the middle of a longer same-run into a fold row. Changed lines always survive.
    static func displayRows(_ diff: [DiffLine], context: Int = 3) -> [DiffRow] {
        var rows: [DiffRow] = []
        var foldIndex = 0
        var i = 0
        while i < diff.count {
            guard diff[i].kind == .same else {
                rows.append(.line(diff[i])); i += 1; continue
            }
            var runEnd = i
            while runEnd < diff.count, diff[runEnd].kind == .same { runEnd += 1 }
            let run = Array(diff[i..<runEnd])
            if run.count > context * 2 + 2 {
                run.prefix(context).forEach { rows.append(.line($0)) }
                rows.append(.fold(count: run.count - context * 2, index: foldIndex))
                foldIndex += 1
                run.suffix(context).forEach { rows.append(.line($0)) }
            } else {
                run.forEach { rows.append(.line($0)) }
            }
            i = runEnd
        }
        return rows
    }
}
```

- [ ] **Step 4: Run to verify pass** — same command, expected PASS (all 7 tests).

- [ ] **Step 5: Commit**

```bash
git add App/TrueISFEditor/Models/LineDiff.swift App/TrueISFEditorTests/LineDiffTests.swift
git commit -m "feat(app): LineDiff engine — LCS line diff with display folding (D2)"
```

---

### Task 6: `DiffView` + real diff in the apply preview

Replace `ApplyPreviewPanel`'s two raw text columns with a colored unified diff.

**Files:**
- Create: `App/TrueISFEditor/Views/DiffView.swift`
- Modify: `App/TrueISFEditor/Views/ApplyPreviewPanel.swift`

**Interfaces:**
- Consumes: `LineDiff.diff` / `LineDiff.displayRows` / `DiffRow` (Task 5).
- Produces: `DiffView(old: String, new: String)` — reused by Task 10.

- [ ] **Step 1: Create `App/TrueISFEditor/Views/DiffView.swift`:**

```swift
import SwiftUI

/// Unified colored line diff (D2): old → new, folded to changes + context by default.
struct DiffView: View {
    let old: String
    let new: String
    @State private var showUnchanged = false

    var body: some View {
        let diff = LineDiff.diff(old: old, new: new)
        VStack(alignment: .leading, spacing: 4) {
            Toggle("Show unchanged lines", isOn: $showUnchanged)
                .toggleStyle(.checkbox).font(.caption).foregroundStyle(.secondary)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(showUnchanged ? diff.map { DiffRow.line($0) } : LineDiff.displayRows(diff)) { row in
                        rowView(row)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
            }
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
        }
    }

    @ViewBuilder private func rowView(_ row: DiffRow) -> some View {
        switch row {
        case .fold(let count, _):
            Text("··· \(count) unchanged lines ···")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 2)
        case .line(let line):
            HStack(alignment: .top, spacing: 0) {
                Text(line.oldLine.map(String.init) ?? "")
                    .frame(width: 34, alignment: .trailing).foregroundStyle(.secondary)
                Text(line.newLine.map(String.init) ?? "")
                    .frame(width: 34, alignment: .trailing).foregroundStyle(.secondary)
                Text(marker(line.kind)).frame(width: 16)
                Text(line.text.isEmpty ? " " : line.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .font(.system(size: 10, design: .monospaced))
            .padding(.horizontal, 4)
            .background(background(line.kind))
        }
    }

    private func marker(_ kind: DiffLine.Kind) -> String {
        switch kind {
        case .same: return " "
        case .removed: return "−"
        case .added: return "+"
        }
    }

    private func background(_ kind: DiffLine.Kind) -> Color {
        switch kind {
        case .same: return .clear
        case .removed: return .red.opacity(0.14)
        case .added: return .green.opacity(0.16)
        }
    }
}
```

- [ ] **Step 2: Swap it into `ApplyPreviewPanel.swift`.** Replace the two-column block

```swift
            HStack(alignment: .top, spacing: 8) {
                sourceColumn("Current", originalSource)
                sourceColumn("Proposed", result.replacementSource)
            }
```

with

```swift
            DiffView(old: originalSource, new: result.replacementSource)
```

and delete the now-unused `sourceColumn(_:_:)` helper (no unused code left behind).

- [ ] **Step 3: Build + run the full app suite**

Run: full-suite command from Global Constraints.
Expected: BUILD SUCCEEDED, all green (no behavior change under test — view-layer; the diff engine is covered by Task 5).

- [ ] **Step 4: Commit**

```bash
git add App/TrueISFEditor/Views/DiffView.swift App/TrueISFEditor/Views/ApplyPreviewPanel.swift
git commit -m "feat(app): real line diff in the ShaderAssist apply preview (D2)"
```

---

### Task 7: Param snapshot codec

`ParamValue` becomes Codable inside a versioned `ParamSnapshot` envelope — the null_signal preset-codec doctrine in FULL: versioned flat JSON, keyed by input NAME, validate-AND-CLAMP per entry on apply (a snapshot captured under an older, wider header range must clamp to the live range, not replay out-of-range into the engine), skip corrupt entries, never fatal. Clamping needs ranges, so `syncInputs` also captures per-input bounds.

**Files:**
- Modify: `App/TrueISFEditor/Models/ParamStore.swift`
- Test: `App/TrueISFEditorTests/ParamStoreTests.swift`

**Interfaces:**
- Consumes: existing `ParamValue`, `ParamStore.values/defaults/replayAll/sameKind`.
- Produces: `ParamSnapshot` (`version: Int`, `params: [String: ParamValue]`, Codable, Equatable), `ParamStore.exportSnapshot() -> ParamSnapshot`, `ParamStore.applySnapshot(_ snapshot: ParamSnapshot)` (validates types + clamps ranges). Used by Tasks 8–10.

- [ ] **Step 1: Write the failing tests** — append to `ParamStoreTests.swift`:

```swift
    // MARK: D1 — snapshot codec (null_signal preset doctrine)

    func testParamSnapshotRoundTripsAllKinds() throws {
        let snapshot = ParamSnapshot(params: [
            "gain": .float(0.75),
            "invert": .bool(true),
            "mode": .long(3),
            "center": .point2D([0.25, 0.5]),
            "tint": .color([1, 0, 0.5, 1]),
        ])
        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(ParamSnapshot.self, from: data)
        XCTAssertEqual(decoded, snapshot)
        XCTAssertEqual(decoded.version, 1)
    }

    func testDecodingSkipsCorruptEntriesWithoutFailing() throws {
        // point2D with wrong arity + an unknown type tag: both skipped, healthy entry survives.
        let json = """
        {"version":1,"params":{
            "ok":{"type":"float","value":0.5},
            "badPoint":{"type":"point2D","value":[1.0]},
            "future":{"type":"quaternion","value":[0,0,0,1]}
        }}
        """
        let decoded = try JSONDecoder().decode(ParamSnapshot.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.params, ["ok": .float(0.5)])
    }

    @MainActor
    func testExportApplySnapshotReplaysThroughSinks() {
        let store = ParamStore()
        store.syncInputs([input("gain", "float", def: 0.2, min: 0.0, max: 1.0)])
        store.set("gain", .float(0.9))
        let snapshot = store.exportSnapshot()
        XCTAssertEqual(snapshot.params, ["gain": .float(0.9)])

        let fresh = ParamStore()
        fresh.syncInputs([input("gain", "float", def: 0.2, min: 0.0, max: 1.0)])
        var sent: [(String, String)] = []
        fresh.onSet = { sent.append(($0, $1)) }
        fresh.applySnapshot(snapshot)
        XCTAssertEqual(fresh.values, ["gain": .float(0.9)])
        XCTAssertTrue(sent.contains { $0.0 == "gain" && $0.1 == "0.9" },
                      "apply must replay values into the render sinks")
    }

    @MainActor
    func testApplySnapshotSkipsTypeDriftAgainstKnownDefaults() {
        let store = ParamStore()
        store.syncInputs([input("gain", "float", def: 0.2, min: 0.0, max: 1.0)])
        store.applySnapshot(ParamSnapshot(params: ["gain": .bool(true),      // drifted: known input, wrong kind
                                                   "later": .float(0.4)]))   // unknown input: kept, pruned on next syncInputs
        XCTAssertEqual(store.values, ["later": .float(0.4)])
    }

    @MainActor
    func testApplySnapshotClampsToCurrentHeaderRange() {
        let store = ParamStore()
        store.syncInputs([input("gain", "float", def: 0.2, min: 0.0, max: 1.0),
                          input("center", "point2D", def: [0.5, 0.5], min: [0.0, 0.0], max: [1.0, 1.0]),
                          input("tint", "color", def: [1, 1, 1, 1])])
        // Captured under an older, wider header range — must clamp to the LIVE range on apply.
        store.applySnapshot(ParamSnapshot(params: ["gain": .float(2.0),
                                                   "center": .point2D([-0.5, 3.0]),
                                                   "tint": .color([2.0, -1.0, 0.5, 1.0])]))
        XCTAssertEqual(store.values["gain"], .float(1.0))
        XCTAssertEqual(store.values["center"], .point2D([0.0, 1.0]))
        XCTAssertEqual(store.values["tint"], .color([1.0, 0.0, 0.5, 1.0]))
    }
```

(`input(...)` is the existing private helper at the top of `ParamStoreTests`.)

- [ ] **Step 2: Run to verify failure** — `... -only-testing:TrueISFEditorTests/ParamStoreTests`. Expected: compile FAILURE — `ParamSnapshot` not defined.

- [ ] **Step 3: Implement.** In `ParamStore.swift`, add after the `ParamValue` enum:

```swift
// MARK: - snapshot codec (D1)

extension ParamValue: Codable {
    private enum CodingKeys: String, CodingKey { case type, value }
    private enum Kind: String, Codable { case float, bool, long, point2D, color }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(Kind.self, forKey: .type) {
        case .float: self = .float(try c.decode(Double.self, forKey: .value))
        case .bool:  self = .bool(try c.decode(Bool.self, forKey: .value))
        case .long:  self = .long(try c.decode(Double.self, forKey: .value))
        case .point2D:
            let arr = try c.decode([Double].self, forKey: .value)
            guard arr.count == 2 else {
                throw DecodingError.dataCorruptedError(forKey: .value, in: c,
                                                       debugDescription: "point2D needs 2 components")
            }
            self = .point2D(arr)
        case .color:
            let arr = try c.decode([Double].self, forKey: .value)
            guard arr.count == 4 else {
                throw DecodingError.dataCorruptedError(forKey: .value, in: c,
                                                       debugDescription: "color needs 4 components")
            }
            self = .color(arr)
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .float(let v):   try c.encode(Kind.float, forKey: .type); try c.encode(v, forKey: .value)
        case .bool(let v):    try c.encode(Kind.bool, forKey: .type); try c.encode(v, forKey: .value)
        case .long(let v):    try c.encode(Kind.long, forKey: .type); try c.encode(v, forKey: .value)
        case .point2D(let v): try c.encode(Kind.point2D, forKey: .type); try c.encode(v, forKey: .value)
        case .color(let v):   try c.encode(Kind.color, forKey: .type); try c.encode(v, forKey: .value)
        }
    }
}

/// Versioned param snapshot (null_signal preset-codec doctrine: versioned flat JSON keyed by
/// input NAME; corrupt entries are skipped on decode, never fatal; runtime state — window
/// geometry, transport — stays OUT of param snapshots).
struct ParamSnapshot: Equatable {
    var version: Int = 1
    var params: [String: ParamValue]
}

extension ParamSnapshot: Codable {
    private enum CodingKeys: String, CodingKey { case version, params }

    /// Swallows one corrupt entry instead of failing the whole snapshot decode.
    private struct FailableParamValue: Codable {
        let value: ParamValue?
        init(value: ParamValue?) { self.value = value }
        init(from decoder: Decoder) throws { value = try? ParamValue(from: decoder) }
        func encode(to encoder: Encoder) throws { try value?.encode(to: encoder) }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        let raw = try c.decodeIfPresent([String: FailableParamValue].self, forKey: .params) ?? [:]
        params = raw.compactMapValues(\.value)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(version, forKey: .version)
        try c.encode(params.mapValues { FailableParamValue(value: $0) }, forKey: .params)
    }
}
```

And in the `ParamStore` class:

First, bounds capture. Add a stored property next to `defaults`:

```swift
    /// Per-input numeric ranges from the live header (float/long: 1 element; point2D: 2).
    /// Captured by syncInputs so applySnapshot can clamp stale snapshot values (D1 doctrine).
    private(set) var bounds: [String: (lo: [Double], hi: [Double])] = [:]
```

Extend `syncInputs(_:)` — inside the existing `for input in inputs` loop, capture bounds, and assign at the end (full replacement of the method body shown):

```swift
    func syncInputs(_ inputs: [ISFPreviewInput]) {
        var newDefaults: [String: ParamValue] = [:]
        var newBounds: [String: (lo: [Double], hi: [Double])] = [:]
        for input in inputs {
            if let d = Self.defaultValue(for: input) { newDefaults[input.name] = d }
            switch input.type {
            case "float", "long":
                if let lo = input.min as? Double, let hi = input.max as? Double, hi > lo {
                    newBounds[input.name] = ([lo], [hi])
                }
            case "point2D":
                let lo = Self.doubles(input.min, count: 2, fallback: [])
                let hi = Self.doubles(input.max, count: 2, fallback: [])
                if lo.count == 2, hi.count == 2 { newBounds[input.name] = (lo, hi) }
            default:
                break
            }
        }
        defaults = newDefaults
        bounds = newBounds
        values = values.filter { name, value in
            guard let d = newDefaults[name] else { return false }
            return value.sameKind(as: d)
        }
    }
```

Extend `resetAll()` to also clear bounds (`bounds = [:]`).

Then the snapshot API, after `replayAll()`:

```swift
    // MARK: snapshots (D1)

    /// User-set values only — defaults are derived from the header, not stored.
    func exportSnapshot() -> ParamSnapshot {
        ParamSnapshot(params: values)
    }

    /// Replace user values from a snapshot — the null_signal apply doctrine: per-entry
    /// validate-and-clamp, never fatal. Type-drifted entries (known input, wrong kind) are
    /// skipped; surviving numeric values clamp to the LIVE header range (a snapshot captured
    /// under an older, wider range must not replay out-of-range into the engine); unknown
    /// names are kept as-is (the next syncInputs prunes them). Everything surviving replays
    /// into the render sinks.
    func applySnapshot(_ snapshot: ParamSnapshot) {
        var applied: [String: ParamValue] = [:]
        for (name, value) in snapshot.params {
            if let d = defaults[name] {
                guard value.sameKind(as: d) else { continue }
                applied[name] = clamped(value, name: name)
            } else {
                applied[name] = value
            }
        }
        values = applied
        replayAll()
    }

    /// Clamp a value to the live header range. Colors clamp per-component to [0, 1]; inputs
    /// without declared bounds pass through; bools have nothing to clamp.
    private func clamped(_ value: ParamValue, name: String) -> ParamValue {
        switch value {
        case .color(let c):
            return .color(c.map { min(max($0, 0), 1) })
        case .float(let v):
            guard let b = bounds[name] else { return value }
            return .float(min(max(v, b.lo[0]), b.hi[0]))
        case .long(let v):
            guard let b = bounds[name] else { return value }
            return .long(min(max(v, b.lo[0]), b.hi[0]))
        case .point2D(let p):
            guard let b = bounds[name], p.count == 2 else { return value }
            return .point2D([min(max(p[0], b.lo[0]), b.hi[0]),
                             min(max(p[1], b.lo[1]), b.hi[1])])
        case .bool:
            return value
        }
    }
```

- [ ] **Step 4: Run to verify pass** — same command, expected PASS.

- [ ] **Step 5: Commit**

```bash
git add App/TrueISFEditor/Models/ParamStore.swift App/TrueISFEditorTests/ParamStoreTests.swift
git commit -m "feat(params): versioned ParamSnapshot codec — export/apply with per-entry validation (D1)"
```

---

### Task 8: `SnapshotStore`

Disk-backed version history: one folder per document, one JSON file per version, bounded, deduped, never throws into the editing flow.

**Files:**
- Create: `App/TrueISFEditor/Models/SnapshotStore.swift`
- Test: `App/TrueISFEditorTests/SnapshotStoreTests.swift` (create)

**Interfaces:**
- Consumes: `ParamSnapshot` (Task 7), `ISFFile` (`url`, `displayName`, `source`).
- Produces:
  - `Snapshot` — `id: String`, `date: Date`, `label: String`, `source: String`, `params: ParamSnapshot` (Identifiable, Equatable).
  - `SnapshotStore(rootURL: URL? = nil, cap: Int = 30)` (`@MainActor`, ObservableObject).
  - `@discardableResult func capture(file: ISFFile, params: ParamSnapshot, label: String) -> Snapshot?` — nil on dedupe (identical source to newest) or write failure.
  - `func snapshots(for file: ISFFile) -> [Snapshot]` — newest first, corrupt files skipped.
  - `static func documentKey(for file: ISFFile) -> String`.
  Used by Tasks 9–10.

- [ ] **Step 1: Write the failing tests** — create `App/TrueISFEditorTests/SnapshotStoreTests.swift`:

```swift
import XCTest
@testable import TrueISFEditor

@MainActor
final class SnapshotStoreTests: XCTestCase {
    private var root: URL!

    override func setUp() {
        super.setUp()
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("snapshot-tests-\(UUID().uuidString)")
    }
    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
        super.tearDown()
    }

    func testCaptureAndListRoundTrip() {
        let store = SnapshotStore(rootURL: root)
        let file = ISFFile.untitled(source: "v1", suggestedName: "Doc")
        let snap = store.capture(file: file, params: ParamSnapshot(params: ["gain": .float(0.5)]),
                                 label: "Opened")
        XCTAssertNotNil(snap)
        let listed = store.snapshots(for: file)
        XCTAssertEqual(listed.count, 1)
        XCTAssertEqual(listed[0].source, "v1")
        XCTAssertEqual(listed[0].label, "Opened")
        XCTAssertEqual(listed[0].params.params, ["gain": .float(0.5)])
    }

    func testCaptureDedupesIdenticalSource() {
        let store = SnapshotStore(rootURL: root)
        let file = ISFFile.untitled(source: "same", suggestedName: "Doc")
        XCTAssertNotNil(store.capture(file: file, params: ParamSnapshot(params: [:]), label: "Opened"))
        XCTAssertNil(store.capture(file: file, params: ParamSnapshot(params: [:]), label: "Opened"),
                     "identical source must not stack duplicate versions")
        XCTAssertEqual(store.snapshots(for: file).count, 1)
    }

    func testCapIsEnforcedOldestPruned() {
        let store = SnapshotStore(rootURL: root, cap: 3)
        var file = ISFFile.untitled(source: "v0", suggestedName: "Doc")
        for i in 1...5 {
            file.source = "v\(i)"
            XCTAssertNotNil(store.capture(file: file, params: ParamSnapshot(params: [:]),
                                          label: "step \(i)"))
        }
        let listed = store.snapshots(for: file)
        XCTAssertEqual(listed.count, 3)
        XCTAssertEqual(listed.first?.source, "v5", "newest first")
        XCTAssertEqual(listed.last?.source, "v3", "oldest beyond cap pruned")
    }

    func testDocumentsKeepSeparateHistories() {
        let store = SnapshotStore(rootURL: root)
        let a = ISFFile.untitled(source: "aaa", suggestedName: "A")
        let b = ISFFile.untitled(source: "bbb", suggestedName: "B")
        store.capture(file: a, params: ParamSnapshot(params: [:]), label: "Opened")
        store.capture(file: b, params: ParamSnapshot(params: [:]), label: "Opened")
        XCTAssertEqual(store.snapshots(for: a).map(\.source), ["aaa"])
        XCTAssertEqual(store.snapshots(for: b).map(\.source), ["bbb"])
    }

    func testCorruptSnapshotFileIsSkippedNotFatal() throws {
        let store = SnapshotStore(rootURL: root)
        let file = ISFFile.untitled(source: "good", suggestedName: "Doc")
        store.capture(file: file, params: ParamSnapshot(params: [:]), label: "Opened")
        let dir = root.appendingPathComponent(SnapshotStore.documentKey(for: file))
        try Data("not json".utf8).write(to: dir.appendingPathComponent("zzz-corrupt.json"))
        XCTAssertEqual(store.snapshots(for: file).count, 1, "corrupt file skipped, list survives")
    }
}
```

- [ ] **Step 2: Run to verify failure** — `... -only-testing:TrueISFEditorTests/SnapshotStoreTests`. Expected: compile FAILURE — `SnapshotStore` not defined.

- [ ] **Step 3: Implement** — create `App/TrueISFEditor/Models/SnapshotStore.swift`:

```swift
import Foundation
import CryptoKit

/// One saved version of a document: full source + the param values at capture time.
struct Snapshot: Identifiable, Equatable {
    let id: String            // filename stem
    let date: Date
    let label: String         // "Opened", "Before AI rewrite", "Before restore", ...
    let source: String
    let params: ParamSnapshot
}

/// Disk-backed version history (D1): one folder per document key, one JSON file per version.
/// Bounded per document, dedupes identical-source captures, and NEVER throws into the editing
/// flow — a failed snapshot must not block an open or an AI apply (capture returns nil).
@MainActor
final class SnapshotStore: ObservableObject {
    let rootURL: URL
    let cap: Int

    init(rootURL: URL? = nil, cap: Int = 30) {
        self.rootURL = rootURL ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TrueISFEditor/Snapshots")
        self.cap = cap
    }

    /// Stable, filesystem-safe per-document folder name. Saved docs key on their path; untitled
    /// docs on their display name (an unsaved import keeps one history while it stays unsaved).
    static func documentKey(for file: ISFFile) -> String {
        let identity = file.url?.path ?? "untitled:\(file.displayName)"
        let digest = SHA256.hash(data: Data(identity.utf8))
        let hex = digest.prefix(6).map { String(format: "%02x", $0) }.joined()
        let safeName = String(file.displayName.map { $0.isLetter || $0.isNumber ? $0 : "-" })
        return "\(safeName)-\(hex)"
    }

    private struct SnapshotFile: Codable {
        let date: Date
        let label: String
        let source: String
        let params: ParamSnapshot
    }

    private func directory(for file: ISFFile) -> URL {
        rootURL.appendingPathComponent(Self.documentKey(for: file))
    }

    /// Newest first. Corrupt or unreadable files are skipped.
    func snapshots(for file: ISFFile) -> [Snapshot] {
        let dir = directory(for: file)
        let items = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return items
            .filter { $0.pathExtension == "json" }
            .compactMap { url -> Snapshot? in
                guard let data = try? Data(contentsOf: url),
                      let f = try? decoder.decode(SnapshotFile.self, from: data) else { return nil }
                return Snapshot(id: url.deletingPathExtension().lastPathComponent,
                                date: f.date, label: f.label, source: f.source, params: f.params)
            }
            .sorted { $0.date > $1.date }
    }

    /// Capture a version. Returns nil (and writes nothing) when the newest existing version has
    /// identical source, or when any file operation fails.
    @discardableResult
    func capture(file: ISFFile, params: ParamSnapshot, label: String) -> Snapshot? {
        let existing = snapshots(for: file)
        if existing.first?.source == file.source { return nil }

        let dir = directory(for: file)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let date = Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        var stem = formatter.string(from: date)
        // Same-millisecond captures (rapid fix applies) get a monotonic suffix.
        var counter = 1
        while FileManager.default.fileExists(atPath: dir.appendingPathComponent("\(stem).json").path) {
            stem = "\(formatter.string(from: date))-\(counter)"
            counter += 1
        }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(
            SnapshotFile(date: date, label: label, source: file.source, params: params)) else { return nil }
        do {
            try data.write(to: dir.appendingPathComponent("\(stem).json"), options: .atomic)
        } catch { return nil }

        // Prune oldest beyond the cap.
        let all = snapshots(for: file)
        if all.count > cap {
            for stale in all.suffix(all.count - cap) {
                try? FileManager.default.removeItem(
                    at: dir.appendingPathComponent("\(stale.id).json"))
            }
        }
        return Snapshot(id: stem, date: date, label: label, source: file.source, params: params)
    }
}
```

- [ ] **Step 4: Run to verify pass** — same command, expected PASS (all 5 tests).

- [ ] **Step 5: Commit**

```bash
git add App/TrueISFEditor/Models/SnapshotStore.swift App/TrueISFEditorTests/SnapshotStoreTests.swift
git commit -m "feat(app): SnapshotStore — bounded disk-backed version history (D1)"
```

---

### Task 9: Auto-snapshot wiring + restore in `EditorViewModel`

Capture points per the roadmap: on open (all three document-arrival paths) and before every AI apply (both the per-edit fix path and the whole-file rewrite path), plus before restore so restore is always undoable — which is why restore needs no confirmation dialog.

**Files:**
- Modify: `App/TrueISFEditor/EditorViewModel.swift`
- Test: `App/TrueISFEditorTests/EditorViewModelSnapshotTests.swift` (create)

**Interfaces:**
- Consumes: `SnapshotStore` (Task 8), `ParamStore.exportSnapshot/applySnapshot` (Task 7).
- Produces: `EditorViewModel.snapshots: SnapshotStore` (init-injectable), `EditorViewModel.restore(_ snapshot: Snapshot)`, `@Published var requestVersions: Bool` (sheet trigger for Task 10).

- [ ] **Step 1: Write the failing tests** — create `App/TrueISFEditorTests/EditorViewModelSnapshotTests.swift`:

```swift
import XCTest
import ShadertoyISFKit
@testable import TrueISFEditor

@MainActor
final class EditorViewModelSnapshotTests: XCTestCase {
    private var root: URL!

    override func setUp() {
        super.setUp()
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("vm-snapshot-tests-\(UUID().uuidString)")
    }
    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
        super.tearDown()
    }

    private func makeVM() -> EditorViewModel {
        EditorViewModel(file: .untitled(source: EditorViewModel.blankTemplate),
                        snapshots: SnapshotStore(rootURL: root))
    }

    func testImportCapturesOpenedSnapshot() {
        let vm = makeVM()
        vm.loadImported(isf: "/*{}*/ void main(){}", warnings: [], suggestedName: "Imported")
        let snaps = vm.snapshots.snapshots(for: vm.file)
        XCTAssertEqual(snaps.map(\.label), ["Imported"])
        XCTAssertEqual(snaps[0].source, "/*{}*/ void main(){}")
    }

    func testAIRewriteCapturesPreApplySource() {
        let vm = makeVM()
        let original = vm.file.source
        vm.replaceSourceFromAssist("/*{}*/ void main(){ gl_FragColor = vec4(0.0); }")
        let snaps = vm.snapshots.snapshots(for: vm.file)
        XCTAssertEqual(snaps.first?.label, "Before AI rewrite")
        XCTAssertEqual(snaps.first?.source, original,
                       "the version captured must be the PRE-apply source")
    }

    func testFixApplyCapturesPreApplySource() {
        let vm = makeVM()
        let original = vm.file.source
        // blankTemplate line 1 is "/*{" — an edit that passes the expectedContains guard.
        vm.apply(TextEdit(fromLine: 1, toLine: 1, replacement: "/*{ ", expectedContains: "/*{"))
        let snaps = vm.snapshots.snapshots(for: vm.file)
        XCTAssertEqual(snaps.first?.label, "Before AI fix")
        XCTAssertEqual(snaps.first?.source, original)
    }

    func testGuardedFixApplyDoesNotSnapshot() {
        let vm = makeVM()
        vm.apply(TextEdit(fromLine: 1, toLine: 1, replacement: "x", expectedContains: "NOT-IN-SOURCE"))
        XCTAssertTrue(vm.snapshots.snapshots(for: vm.file).isEmpty,
                      "a rejected stale fix must not pollute the version history")
    }

    func testRestoreReplacesSourceParamsAndCapturesPreRestoreVersion() {
        let vm = makeVM()
        let restored = ParamSnapshot(params: ["gain": .float(0.9)])
        let snapshot = Snapshot(id: "s1", date: Date(), label: "Opened",
                                source: "/*{}*/ void main(){ gl_FragColor = vec4(1.0); }",
                                params: restored)
        let current = vm.file.source
        vm.restore(snapshot)
        XCTAssertEqual(vm.file.source, snapshot.source)
        XCTAssertEqual(vm.paramStore.values, ["gain": .float(0.9)])
        let labels = vm.snapshots.snapshots(for: vm.file).map(\.label)
        XCTAssertTrue(labels.contains("Before restore"))
        XCTAssertTrue(vm.snapshots.snapshots(for: vm.file).contains { $0.source == current })
    }
}
```

Note: `TextEdit` is ShadertoyISFKit's public type (`FixSuggestion.swift:3`) with init `(fromLine:toLine:replacement:expectedContains:)` — the plain kit import above resolves it; no dual-module qualification needed.

- [ ] **Step 2: Run to verify failure** — `... -only-testing:TrueISFEditorTests/EditorViewModelSnapshotTests`. Expected: compile FAILURE — no `snapshots:` init parameter.

- [ ] **Step 3: Implement.** In `EditorViewModel.swift`:

Init gains the injectable store — change the signature and add the property (near `paramStore`):

```swift
    /// D1: version history. Injectable so tests point it at a temp directory.
    let snapshots: SnapshotStore

    init(file: ISFFile? = nil, snapshots: SnapshotStore = SnapshotStore()) {
        self.snapshots = snapshots
        self.file = file ?? .untitled(source: Self.blankTemplate)
        ...
```

(keep the rest of init unchanged).

Add the sheet trigger next to `requestImport`:

```swift
    /// Set by the Versions… command / toolbar button; EditorScreen presents the sheet.
    @Published var requestVersions = false
```

Capture on the three document-arrival paths — add one line to each, right after `headerModel.syncFromText(...)` and before `recompile(immediate: true)`:

- in `open(_:)`: `snapshots.capture(file: file, params: paramStore.exportSnapshot(), label: "Opened")`
- in `loadImported(...)`: `snapshots.capture(file: file, params: paramStore.exportSnapshot(), label: "Imported")`
- in `loadExample(...)`: `snapshots.capture(file: file, params: paramStore.exportSnapshot(), label: "Opened")`

(`newUntitled()` intentionally does NOT capture — a blank template needs no version.)

Capture before both AI apply paths:

In `apply(_ edit:)`, after the `expectedContains` guard passes and before `editor.applyTextEdit(...)`:

```swift
        // D1: every AI mutation is preceded by a restorable version.
        snapshots.capture(file: file, params: paramStore.exportSnapshot(), label: "Before AI fix")
```

In `replaceSourceFromAssist(...)`, as the FIRST line:

```swift
        snapshots.capture(file: file, params: paramStore.exportSnapshot(), label: "Before AI rewrite")
```

Add restore (new `MARK: versions (D1)` section after the save section):

```swift
    // MARK: versions (D1)

    /// Restore a snapshot: source + params. No discard confirmation — the current state is
    /// itself captured first, so restore is always undoable via the same list.
    func restore(_ snapshot: Snapshot) {
        snapshots.capture(file: file, params: paramStore.exportSnapshot(), label: "Before restore")
        file.source = snapshot.source
        editor.setText(snapshot.source)
        headerModel.syncFromText(snapshot.source)
        paramStore.applySnapshot(snapshot.params)
        recompile(immediate: true)
        statusMessage = "Restored version — \(snapshot.label), \(snapshot.date.formatted(date: .abbreviated, time: .shortened))"
    }
```

- [ ] **Step 4: Run to verify pass** — snapshot tests + the pre-existing `EditorViewModelTests` (init signature changed; default argument keeps existing call sites compiling):

Run: `... -only-testing:TrueISFEditorTests/EditorViewModelSnapshotTests -only-testing:TrueISFEditorTests/EditorViewModelTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add App/TrueISFEditor/EditorViewModel.swift App/TrueISFEditorTests/EditorViewModelSnapshotTests.swift
git commit -m "feat(app): auto-snapshot on open + before AI applies, restore with pre-restore capture (D1)"
```

---

### Task 10: Versions UI — `SnapshotListView` + menu

The versions list: sheet with the history on the left, a diff of the selected version against the current source on the right, one prominent Restore button. Entry points: a toolbar clock button and File ▸ Versions… (⌘⌥V).

**Files:**
- Create: `App/TrueISFEditor/Views/SnapshotListView.swift`
- Modify: `App/TrueISFEditor/Views/EditorScreen.swift` (sheet + toolbar button)
- Modify: `App/TrueISFEditor/TrueISFEditorApp.swift` (File menu command)

**Interfaces:**
- Consumes: `vm.snapshots` / `vm.restore(_:)` / `vm.requestVersions` (Task 9), `DiffView` (Task 6).
- Produces: nothing consumed later. (UI verified on-device.)

- [ ] **Step 1: Create `App/TrueISFEditor/Views/SnapshotListView.swift`:**

```swift
import SwiftUI

/// D1: the versions list — history left, selected-version diff right, one Restore action.
struct SnapshotListView: View {
    @ObservedObject var vm: EditorViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var versions: [Snapshot] = []
    @State private var selectedID: String?

    private var selected: Snapshot? { versions.first { $0.id == selectedID } }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Versions — \(vm.file.displayName)").font(.headline)
                Spacer()
                Button("Close") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            .padding(10)
            Divider()
            HSplitView {
                List(selection: $selectedID) {
                    ForEach(versions) { s in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(s.label).font(.callout)
                            Text(s.date.formatted(date: .abbreviated, time: .standard))
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        .tag(s.id)
                    }
                }
                .frame(minWidth: 190, idealWidth: 230)
                VStack(alignment: .leading, spacing: 8) {
                    if let s = selected {
                        HStack {
                            Text("Selected version → current source")
                                .font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Button("Restore This Version") { vm.restore(s); dismiss() }
                                .buttonStyle(.borderedProminent).controlSize(.small)
                        }
                        DiffView(old: s.source, new: vm.file.source)
                    } else {
                        Text(versions.isEmpty
                             ? "No versions yet — versions are captured when a shader is opened and before every AI apply."
                             : "Select a version to compare and restore.")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .padding(10)
                .frame(minWidth: 420)
            }
        }
        .frame(minWidth: 720, minHeight: 440)
        .onAppear { versions = vm.snapshots.snapshots(for: vm.file) }
    }
}
```

- [ ] **Step 2: Present it from `EditorScreen.swift`.** Add a sheet next to the existing ones:

```swift
        .sheet(isPresented: $vm.requestVersions) {
            SnapshotListView(vm: vm)
        }
```

and a toolbar button in the header `HStack`, before the pop-out button:

```swift
                        Button { vm.requestVersions = true } label: {
                            Image(systemName: "clock.arrow.circlepath")
                        }
                        .help("Versions — restore an earlier state of this shader (⌘⌥V)")
```

- [ ] **Step 3: Add the File-menu command** in `TrueISFEditorApp.swift`, inside `CommandGroup(replacing: .saveItem)` after Save As…:

```swift
                Button("Versions…") { vm.requestVersions = true }
                    .keyboardShortcut("v", modifiers: [.command, .option])
```

- [ ] **Step 4: Build + full app suite** — full-suite command. Expected: BUILD SUCCEEDED, all green.

- [ ] **Step 5: Commit**

```bash
git add App/TrueISFEditor/Views/SnapshotListView.swift App/TrueISFEditor/Views/EditorScreen.swift App/TrueISFEditor/TrueISFEditorApp.swift
git commit -m "feat(app): versions list with diff + restore, toolbar and File menu entry (D1)"
```

---

### Task 11: Template pack infrastructure + attribution

The `/templates` repo folder ships into the bundle exactly like `/samples`; a `TemplateCatalog` lists it; File ▸ New from Template opens a template as a fresh untitled document (`loadExample` path — user edits a copy, never the bundle file). Attribution lands before any ported math does.

**Files:**
- Create: `templates/README.md`
- Create: `THIRD_PARTY_LICENSES/null_signal.LICENSE.txt`
- Modify: `App/TrueISFEditor/Resources/ACKNOWLEDGEMENTS.md` (append section)
- Modify: `App/project.yml` (app-target resources folder)
- Create: `App/TrueISFEditor/Models/TemplateCatalog.swift`
- Modify: `App/TrueISFEditor/TrueISFEditorApp.swift` (menu)
- Modify: `App/TrueISFEditorTests/LaunchPackTests.swift` (acknowledgements component list)
- Test: `App/TrueISFEditorTests/TemplatePackTests.swift` (create)

**Interfaces:**
- Consumes: `vm.loadExample(name:source:)` (existing).
- Produces: `ShaderTemplate` (`id`, `name`, `sourceText`), `TemplateCatalog.bundledTemplatesDir: URL?`, `TemplateCatalog.all: [ShaderTemplate]`. Tasks 12–13 drop `.fs` files into `templates/`.

- [ ] **Step 1: Create `templates/README.md`:**

```markdown
# Bundled starter templates

Shipped into the app bundle as `Resources/templates/` (folder reference — see `App/project.yml`)
and surfaced via **File ▸ New from Template**. Opening a template creates a fresh untitled
document; the bundle file is never edited.

Files prefixed `NS ` are adapted from **null_signal** by VJ CYBERPATROLUNIT (MIT) — each carries
a `CREDIT` field in its ISF header, and the full license text lives in
`THIRD_PARTY_LICENSES/null_signal.LICENSE.txt`.
```

- [ ] **Step 2: Create `THIRD_PARTY_LICENSES/null_signal.LICENSE.txt`:**

```text
null_signal
https://github.com/vjcyberpatrolunit (private at time of porting — shared with permission)

MIT License

Copyright (c) 2026 VJ CYBERPATROLUNIT

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

(Replace the URL line with the repo's real URL if it differs — check with Conner; the placeholder must not ship wrong.)

- [ ] **Step 3: Append to `App/TrueISFEditor/Resources/ACKNOWLEDGEMENTS.md`** (match the file's existing section format — read it first; append at the end):

```markdown
## null_signal

The bundled "NS" template shaders adapt GLSL from null_signal by VJ CYBERPATROLUNIT,
used under the MIT License.

MIT License

Copyright (c) 2026 VJ CYBERPATROLUNIT

[same full MIT text as THIRD_PARTY_LICENSES/null_signal.LICENSE.txt]
```

(Paste the full license text, not the bracket placeholder — the LaunchPack test asserts >10k chars of real license content overall.)

- [ ] **Step 4: Add the resources folder to `App/project.yml`** — in the `TrueISFEditor` target's `sources`, after the `../samples` entry:

```yaml
      # Bundled starter templates (repo /templates, folder reference → Resources/templates/*.fs).
      - path: ../templates
        buildPhase: resources
        type: folder
```

Then regenerate: `cd App && xcodegen generate`. Expected: no errors, project regenerated.

- [ ] **Step 5: Create `App/TrueISFEditor/Models/TemplateCatalog.swift`:**

```swift
import Foundation

/// A bundled starter shader (repo /templates, shipped as a folder reference).
struct ShaderTemplate: Identifiable {
    let id: String        // filename stem, e.g. "NS Layer Blend"
    let name: String      // display name (the stem)
    let sourceText: String
}

enum TemplateCatalog {
    /// Nil in contexts without the resource (bare-module unit tests).
    static var bundledTemplatesDir: URL? {
        guard let url = Bundle.main.resourceURL?.appendingPathComponent("templates"),
              FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    /// All bundled templates, alphabetical. Computed (not cached): the list is tiny and the
    /// menu builds rarely.
    static var all: [ShaderTemplate] {
        guard let dir = bundledTemplatesDir else { return [] }
        let items = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        return items
            .filter { $0.pathExtension.lowercased() == "fs" }
            .sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
            .compactMap { url in
                guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
                let stem = url.deletingPathExtension().lastPathComponent
                return ShaderTemplate(id: stem, name: stem, sourceText: text)
            }
    }
}
```

- [ ] **Step 6: Add the menu** in `TrueISFEditorApp.swift`, right after the `Menu("Open Example") { ... }` block:

```swift
                Menu("New from Template") {
                    ForEach(TemplateCatalog.all) { t in
                        Button(t.name) { vm.loadExample(name: t.name, source: t.sourceText) }
                    }
                }
```

- [ ] **Step 7: Write the tests.** Create `App/TrueISFEditorTests/TemplatePackTests.swift`:

```swift
import XCTest
import Metal
@testable import TrueISFEditor

@MainActor
final class TemplatePackTests: XCTestCase {
    func testTemplatesFolderIsBundled() {
        XCTAssertNotNil(TemplateCatalog.bundledTemplatesDir, "templates folder missing from bundle")
    }

    func testCatalogListsOnlyFSFiles() {
        // README.md rides along in the folder reference; the catalog must ignore it.
        XCTAssertTrue(TemplateCatalog.all.allSatisfy { !$0.name.contains("README") })
    }

    func testEveryNSTemplateCarriesCredit() {
        for t in TemplateCatalog.all where t.name.hasPrefix("NS ") {
            XCTAssertTrue(t.sourceText.contains("Adapted from null_signal by VJ CYBERPATROLUNIT (MIT)"),
                          "\(t.name) is missing its CREDIT header")
        }
    }

    func testEveryTemplateCompilesAndRendersNonBlack() async throws {
        guard MTLCreateSystemDefaultDevice() != nil else { throw XCTSkip("No Metal device") }
        for t in TemplateCatalog.all {
            let controller = MetalPreviewController()
            controller.setPaused(true)
            controller.load(isf: t.sourceText)
            for _ in 0..<200 where !(controller.compileValid || controller.compileError != nil) {
                try await Task.sleep(nanoseconds: 50_000_000)
            }
            XCTAssertTrue(controller.compileValid,
                          "template \(t.name) failed to compile: \(controller.compileError ?? "?")")
            // The gate renders these frames SEQUENTIALLY on the SAME scene, so persistent
            // buffers accumulate across them — 4 frames pushes a PERSISTENT-buffer template
            // (NS Feedback Echo) past its FRAMEINDEX < 2 init and executes the accumulate
            // path, not just the first-frame passthrough. (Trail DEPTH is an eyeball check —
            // Task 14 on-device list.)
            let verdict = controller.runPixelGate(times: [0.0, 0.4, 0.8, 1.2])
            XCTAssertFalse(verdict.isFail, "template \(t.name) rendered \(verdict.rawValue)")
        }
    }
}
```

And in `LaunchPackTests.testAcknowledgementsResourceBundlesAllComponents`, add `"null_signal"` to the component array.

- [ ] **Step 8: Run to verify**

Run: `... -only-testing:TrueISFEditorTests/TemplatePackTests -only-testing:TrueISFEditorTests/LaunchPackTests`
Expected: PASS — folder bundles (README only, zero `.fs` yet, so the compile loop is vacuous), acknowledgements test sees null_signal.

- [ ] **Step 9: Commit**

```bash
git add templates/ THIRD_PARTY_LICENSES/null_signal.LICENSE.txt App/TrueISFEditor/Resources/ACKNOWLEDGEMENTS.md App/project.yml App/TrueISFEditor/Models/TemplateCatalog.swift App/TrueISFEditor/TrueISFEditorApp.swift App/TrueISFEditorTests/TemplatePackTests.swift App/TrueISFEditorTests/LaunchPackTests.swift App/TrueISFEditor.xcodeproj
git commit -m "feat(app): template pack infrastructure — bundled /templates, catalog, menu, null_signal attribution"
```

---

### Task 12: Templates wave 1a — NS Layer Blend + NS Feedback Echo

The two structurally interesting ports: the 13-blend-mode two-input filter (composite.js:33–76) and the PERSISTENT-buffer feedback template (drawClassicFeedback math, main.js:2209). Deliberate deviations from the source, both worth knowing: audio-reactive terms are dropped (scope fence), and the echo accumulator uses `max(tail·persist, live)` instead of the p5 alpha-mix so trails survive dark input (the ISF house doctrine for trail persistence).

**Files:**
- Create: `templates/NS Layer Blend.fs`
- Create: `templates/NS Feedback Echo.fs`
- Test: `App/TrueISFEditorTests/TemplatePackTests.swift` (existing tests now execute over 2 templates)

**Interfaces:**
- Consumes: catalog + tests from Task 11.
- Produces: two bundled `.fs` files.

- [ ] **Step 1: Create `templates/NS Layer Blend.fs`:**

```glsl
/*{
  "ISFVSN": "2.0",
  "DESCRIPTION": "Blend a second layer over the input: 13 blend modes with alpha-weighted opacity. Blend math written for cross-GPU consistency (dodge/burn divide guards included).",
  "CREDIT": "Adapted from null_signal by VJ CYBERPATROLUNIT (MIT)",
  "CATEGORIES": ["Filter", "Blending"],
  "INPUTS": [
    {"NAME": "inputImage", "TYPE": "image"},
    {"NAME": "blendImage", "TYPE": "image", "LABEL": "Blend Layer"},
    {"NAME": "blendMode", "TYPE": "long", "LABEL": "Mode",
     "VALUES": [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12],
     "LABELS": ["Add", "Screen", "Multiply", "Difference", "Normal", "Lighten", "Darken",
                "Exclusion", "Overlay", "Hard Light", "Soft Light", "Dodge", "Burn"],
     "DEFAULT": 4},
    {"NAME": "opacity", "TYPE": "float", "DEFAULT": 1.0, "MIN": 0.0, "MAX": 1.0}
  ]
}*/

vec3 blendScreen(vec3 b, vec3 s) { return 1.0 - (1.0 - b) * (1.0 - s); }
vec3 blendOverlay(vec3 b, vec3 s) {
    return mix(2.0 * b * s, 1.0 - 2.0 * (1.0 - b) * (1.0 - s), step(0.5, b));
}
vec3 blendHardLight(vec3 b, vec3 s) {
    return mix(2.0 * b * s, 1.0 - 2.0 * (1.0 - b) * (1.0 - s), step(0.5, s));
}
vec3 blendSoftLight(vec3 b, vec3 s) { return (1.0 - 2.0 * s) * b * b + 2.0 * s * b; }
vec3 blendDodge(vec3 b, vec3 s) { return min(b / max(vec3(0.001), 1.0 - s), 1.0); }
vec3 blendBurn(vec3 b, vec3 s) { return 1.0 - min((1.0 - b) / max(vec3(0.001), s), 1.0); }

vec3 applyBlend(vec3 b, vec3 s, int mode) {
    if (mode == 0) return min(b + s, 1.0);
    if (mode == 1) return blendScreen(b, s);
    if (mode == 2) return b * s;
    if (mode == 3) return abs(b - s);
    if (mode == 4) return s;
    if (mode == 5) return max(b, s);
    if (mode == 6) return min(b, s);
    if (mode == 7) return b + s - 2.0 * b * s;
    if (mode == 8) return blendOverlay(b, s);
    if (mode == 9) return blendHardLight(b, s);
    if (mode == 10) return blendSoftLight(b, s);
    if (mode == 11) return blendDodge(b, s);
    return blendBurn(b, s);
}

void main() {
    vec2 uv = isf_FragNormCoord;
    vec4 base = IMG_NORM_PIXEL(inputImage, uv);
    vec4 src = IMG_NORM_PIXEL(blendImage, uv);
    // Blend weight is source alpha x opacity: transparent blend-layer regions leave the
    // base untouched regardless of mode (the null_signal compositeOne formula).
    float a = clamp(src.a * opacity, 0.0, 1.0);
    vec3 blended = applyBlend(base.rgb, src.rgb, blendMode);
    gl_FragColor = vec4(mix(base.rgb, blended, a), base.a);
}
```

- [ ] **Step 2: Create `templates/NS Feedback Echo.fs`:**

```glsl
/*{
  "ISFVSN": "2.0",
  "DESCRIPTION": "Classic video-feedback echo: last frame is zoomed, drifted, and rotated back under the live input. Persistence uses max() so bright trails survive dark input; the upper half of the drift knob adds a darkening wash so long echoes decay instead of saturating.",
  "CREDIT": "Adapted from null_signal by VJ CYBERPATROLUNIT (MIT)",
  "CATEGORIES": ["Filter", "Feedback"],
  "INPUTS": [
    {"NAME": "inputImage", "TYPE": "image"},
    {"NAME": "amount", "TYPE": "float", "DEFAULT": 0.5, "MIN": 0.0, "MAX": 1.0, "LABEL": "Feedback"},
    {"NAME": "knob", "TYPE": "float", "DEFAULT": 0.5, "MIN": 0.0, "MAX": 1.0, "LABEL": "Drift / Persist"},
    {"NAME": "boost", "TYPE": "bool", "DEFAULT": false, "LABEL": "Boost"},
    {"NAME": "resetBuffer", "TYPE": "event", "LABEL": "Reset"}
  ],
  "PASSES": [
    {"TARGET": "echoBuf", "PERSISTENT": true, "FLOAT": true},
    {}
  ]
}*/

vec4 accumulate(vec2 uv) {
    vec4 live = IMG_NORM_PIXEL(inputImage, uv);
    if (FRAMEINDEX < 2 || resetBuffer) return live;

    float button = 0.0;
    if (boost) button = 1.0;

    // drawClassicFeedback transform, normalized-UV domain (audio terms dropped).
    float zoom = 1.0 + amount * (0.018 + knob * 0.042 + button * 0.025);
    vec2 drift = vec2(sin(TIME * (0.36 + knob * 1.1)), cos(TIME * (0.42 + knob * 1.15)))
               * amount * (0.004 + knob * 0.014 + button * 0.014);
    float rot = sin(TIME * (0.24 + knob * 0.6)) * amount * (0.002 + knob * 0.012 + button * 0.01);

    // Inverse-map: sample where this pixel came from last frame.
    vec2 c = uv - 0.5;
    float cs = cos(-rot);
    float sn = sin(-rot);
    vec2 p = vec2(c.x * cs - c.y * sn, c.x * sn + c.y * cs) / zoom + 0.5 - drift;

    vec4 prev = vec4(0.0);
    if (p.x >= 0.0 && p.x <= 1.0 && p.y >= 0.0 && p.y <= 1.0) {
        prev = IMG_NORM_PIXEL(echoBuf, p);   // PERSISTENT read = LAST frame's contents
    }

    float persist = mix(0.46, 0.965, amount);   // p5 alpha lerp(118, 246)/255
    // Upper-half knob: translucent darkening wash (the null_signal "SOMETHING" persistence
    // style) so long echo tails decay toward black instead of saturating.
    float washStyle = clamp((knob - 0.48) / 0.52, 0.0, 1.0);
    float wash = mix(0.27, 0.10, knob) * amount * washStyle;
    vec3 tail = prev.rgb * (1.0 - wash);

    // max() not mix(): trails must survive dark input regions.
    return vec4(max(tail * persist, live.rgb), 1.0);
}

void main() {
    if (PASSINDEX == 0) {
        gl_FragColor = accumulate(isf_FragNormCoord);
        return;
    }
    gl_FragColor = IMG_NORM_PIXEL(echoBuf, isf_FragNormCoord);
}
```

- [ ] **Step 3: Rebuild + run the template tests** (folder-reference resources re-copy on build):

Run: `... -only-testing:TrueISFEditorTests/TemplatePackTests`
Expected: PASS — both templates compile through the Metal engine and pass the pixel gate. The gate binds the deterministic test pattern to BOTH image inputs of Layer Blend, and its 4 explicit times render sequentially on the same scene, so NS Feedback Echo executes its accumulate path (frames 3–4 are past the `FRAMEINDEX < 2` init). Residual: the gate proves the path runs and renders non-black; whether the echo LOOKS like an echo is the Task 14 on-device check.

- [ ] **Step 4: Commit**

```bash
git add "templates/NS Layer Blend.fs" "templates/NS Feedback Echo.fs"
git commit -m "feat(templates): NS Layer Blend (13 modes) + NS Feedback Echo (persistent buffer) — null_signal ports"
```

---

### Task 13: Templates wave 1b — Mirror Kaleido, Pixel Sort, Chroma Leak, Bayer Dither

Four single-input post FX from post.js. Port rules applied throughout: `texture2D(tex0, …)` → `IMG_NORM_PIXEL(inputImage, …)`, `time` → `TIME`, `resolution` → `RENDERSIZE`, `accent` → an `accentColor` input defaulting to null_signal's `#FF003C`, audio uniforms dropped, every scalar/vector ternary rewritten (`halfMirror` collapses to `min(v, 1.0 - v)`, which is exactly `v < 0.5 ? v : 1.0 - v`), loop bounds already constant in the source.

**Files:**
- Create: `templates/NS Mirror Kaleido.fs`
- Create: `templates/NS Pixel Sort.fs`
- Create: `templates/NS Chroma Leak.fs`
- Create: `templates/NS Bayer Dither.fs`

**Interfaces:** consumes Task 11 infrastructure; produces four bundled `.fs` files.

- [ ] **Step 1: Create `templates/NS Mirror Kaleido.fs`** (post.js `mirrorUvPreset`, lines 112–200 — 24 systems on one knob):

```glsl
/*{
  "ISFVSN": "2.0",
  "DESCRIPTION": "24 mirror and kaleidoscope systems on one preset knob — half-frame mirrors, diagonal folds, 4/6/8/10-segment kaleidoscopes, radial folds, and grids. Glitch adds animated slice displacement.",
  "CREDIT": "Adapted from null_signal by VJ CYBERPATROLUNIT (MIT)",
  "CATEGORIES": ["Filter", "Stylize"],
  "INPUTS": [
    {"NAME": "inputImage", "TYPE": "image"},
    {"NAME": "preset", "TYPE": "float", "DEFAULT": 0.55, "MIN": 0.0, "MAX": 1.0, "LABEL": "Preset (24 systems)"},
    {"NAME": "glitch", "TYPE": "bool", "DEFAULT": false, "LABEL": "Glitch Slices"}
  ]
}*/

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123); }
float mirrorFold(float v) { return 1.0 - abs(fract(v) * 2.0 - 1.0); }
// Half-frame mirror preserves source scale: v < 0.5 ? v : 1.0 - v, branch-free.
float halfMirror(float v) { return min(v, 1.0 - v); }
vec2 safeUv(vec2 uv) { return clamp(uv, vec2(0.001), vec2(0.999)); }

vec2 kaleido(float a, float r, float seg, float aspect) {
    float aa = abs(mod(a + 3.14159265 / seg, 6.2831853 / seg) - 3.14159265 / seg);
    vec2 q = vec2(cos(aa), sin(aa)) * r;
    q.x /= aspect;
    return q + 0.5;
}

vec2 mirrorUvPreset(vec2 uv, float presetK, float button) {
    vec2 c = uv - 0.5;
    float aspect = RENDERSIZE.x / max(RENDERSIZE.y, 1.0);
    c.x *= aspect;
    float a = atan(c.y, c.x);
    float r = length(c);
    vec2 outUv = uv;
    float p = floor(presetK * 23.999);
    float drift = button * 0.06 * sin(TIME * 9.0 + floor(uv.y * 12.0));

    if (p < 0.5) outUv.x = halfMirror(uv.x + drift);
    else if (p < 1.5) outUv.y = halfMirror(uv.y + drift);
    else if (p < 2.5) outUv = vec2(halfMirror(uv.x), halfMirror(uv.y));
    else if (p < 3.5) {
        if (uv.x > uv.y) outUv = vec2(uv.y, uv.x);
        else outUv = uv;
    }
    else if (p < 4.5) {
        if (uv.x + uv.y > 1.0) outUv = vec2(1.0 - uv.y, 1.0 - uv.x);
        else outUv = uv;
    }
    else if (p < 5.5) outUv = vec2(halfMirror(fract(uv.x * 2.0)) * 0.5, uv.y);
    else if (p < 6.5) outUv = vec2(uv.x, halfMirror(fract(uv.y * 2.0)) * 0.5);
    else if (p < 7.5) outUv = vec2(halfMirror(fract(uv.x * 2.0)) * 0.5, halfMirror(fract(uv.y * 2.0)) * 0.5);
    else if (p < 8.5) outUv = vec2(halfMirror(fract(uv.x * 2.0 + drift)) * 0.5, uv.y);
    else if (p < 9.5) outUv = vec2(uv.x, halfMirror(fract(uv.y * 2.0 + drift)) * 0.5);
    else if (p < 10.5) outUv = vec2(halfMirror(fract(uv.x * 2.0)) * 0.5, halfMirror(uv.y));
    else if (p < 11.5) outUv = vec2(halfMirror(uv.x), halfMirror(fract(uv.y * 2.0)) * 0.5);
    else if (p < 12.5) outUv = kaleido(a, r, 4.0, aspect);
    else if (p < 13.5) outUv = kaleido(a, r, 6.0, aspect);
    else if (p < 14.5) outUv = kaleido(a, r, 8.0, aspect);
    else if (p < 15.5) outUv = kaleido(a, r, 10.0, aspect);
    else if (p < 16.5) outUv = vec2(halfMirror(fract((uv.x + uv.y) * 1.0)) * 0.7,
                                    halfMirror(fract((uv.x - uv.y) * 1.0)) * 0.7 + 0.15);
    else if (p < 17.5) outUv = vec2(halfMirror(fract((uv.x + uv.y) * 1.35 + drift)) * 0.65,
                                    halfMirror(fract((uv.x - uv.y) * 1.35)) * 0.65 + 0.17);
    else if (p < 18.5) outUv = vec2(halfMirror(fract(uv.x * 2.0 + floor(uv.y * 2.0) * 0.5)) * 0.5,
                                    halfMirror(fract(uv.y * 2.0)) * 0.5);
    else if (p < 19.5) outUv = vec2(halfMirror(fract(uv.x * 3.0)) * 0.5,
                                    halfMirror(fract(uv.y * 2.0 + floor(uv.x * 3.0) * 0.5)) * 0.5);
    else if (p < 20.5) {
        float rr = mirrorFold(r * 2.4 + button * sin(TIME * 2.0) * 0.22);
        vec2 q = vec2(cos(a), sin(a)) * rr * 0.55;
        q.x /= aspect;
        outUv = q + 0.5;
    }
    else if (p < 21.5) {
        float aa = mirrorFold((a / 6.2831853) * 7.0 + drift) * 6.2831853;
        vec2 q = vec2(cos(aa), sin(aa)) * mirrorFold(r * 2.1) * 0.55;
        q.x /= aspect;
        outUv = q + 0.5;
    }
    else if (p < 22.5) {
        vec2 grid = floor(uv * 3.0);
        outUv = vec2(halfMirror(fract(uv.x * 3.0 + mod(grid.y, 2.0) * 0.5)) * 0.55,
                     halfMirror(fract(uv.y * 3.0 + mod(grid.x, 2.0) * 0.5)) * 0.55);
    }
    else {
        vec2 grid = floor(uv * 4.0);
        float h = hash(grid + floor(TIME * (1.2 + button * 7.0)));
        outUv = vec2(halfMirror(fract(uv.x * (2.0 + floor(h * 3.0)))) * 0.6,
                     halfMirror(fract(uv.y * (2.0 + floor(h * 3.0)))) * 0.6);
    }

    if (button > 0.001) {
        float slice = floor(uv.y * mix(4.0, 28.0, presetK));
        outUv.x += (hash(vec2(slice, floor(TIME * 12.0))) - 0.5) * button * 0.08;
    }
    return safeUv(outUv);
}

void main() {
    float button = 0.0;
    if (glitch) button = 1.0;
    // Coordinates are remapped, never interpolated: halfway coordinate blends collapse the
    // image toward the mirror seam (the null_signal lesson baked into the source comment).
    gl_FragColor = IMG_NORM_PIXEL(inputImage, mirrorUvPreset(isf_FragNormCoord, preset, button));
}
```

- [ ] **Step 2: Create `templates/NS Pixel Sort.fs`** (post.js `sampleSort`, lines 223–238):

```glsl
/*{
  "ISFVSN": "2.0",
  "DESCRIPTION": "Pixel-sort approximation: luma-driven horizontal smears on hashed rows, with an accent-colored edge lift. Density/Span shapes how many rows smear and how far.",
  "CREDIT": "Adapted from null_signal by VJ CYBERPATROLUNIT (MIT)",
  "CATEGORIES": ["Filter", "Glitch", "Stylize"],
  "INPUTS": [
    {"NAME": "inputImage", "TYPE": "image"},
    {"NAME": "amount", "TYPE": "float", "DEFAULT": 0.6, "MIN": 0.0, "MAX": 1.0},
    {"NAME": "knob", "TYPE": "float", "DEFAULT": 0.5, "MIN": 0.0, "MAX": 1.0, "LABEL": "Density / Span"},
    {"NAME": "boost", "TYPE": "bool", "DEFAULT": false, "LABEL": "Boost"},
    {"NAME": "accentColor", "TYPE": "color", "DEFAULT": [1.0, 0.0, 0.235, 1.0]}
  ]
}*/

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123); }
vec2 safeUv(vec2 uv) { return clamp(uv, vec2(0.001), vec2(0.999)); }

vec3 sampleSort(vec2 uv, float amt, float k, float button) {
    vec2 px = 1.0 / RENDERSIZE;
    vec3 base = IMG_NORM_PIXEL(inputImage, uv).rgb;
    float rowHash = hash(vec2(floor(uv.y * RENDERSIZE.y * mix(0.12, 0.55, k)),
                              floor(TIME * (3.0 + button * 12.0))));
    float density = mix(0.18, 0.72, k) + button * 0.25;
    if (rowHash > density) return base;
    float l = dot(base, vec3(0.299, 0.587, 0.114));
    float span = mix(8.0, 96.0, amt * (0.45 + k * 0.75 + button * 0.55));
    float dir = 1.0;
    if (rowHash <= 0.5) dir = -1.0;
    vec2 offset = vec2(dir * span * px.x * smoothstep(0.12, 0.96, l), 0.0);
    vec3 a = IMG_NORM_PIXEL(inputImage, safeUv(uv + offset)).rgb;
    vec3 b = IMG_NORM_PIXEL(inputImage, safeUv(uv - offset * 0.45)).rgb;
    float edge = abs(l - dot(a, vec3(0.299, 0.587, 0.114)));
    vec3 sorted = mix(min(a, b), max(a, b), step(0.5, fract(k * 2.0 + rowHash)));
    return mix(base, sorted + edge * accentColor.rgb * (0.25 + button), amt * (0.55 + edge * 1.4));
}

void main() {
    float button = 0.0;
    if (boost) button = 1.0;
    vec2 uv = isf_FragNormCoord;
    float alpha = IMG_NORM_PIXEL(inputImage, uv).a;
    gl_FragColor = vec4(sampleSort(uv, amount, knob, button), alpha);
}
```

- [ ] **Step 3: Create `templates/NS Chroma Leak.fs`** (post.js `sampleChromaLeak`, lines 240–253):

```glsl
/*{
  "ISFVSN": "2.0",
  "DESCRIPTION": "Directional RGB channel separation: R/G/B sample along a radial or tangential axis with a scanline-modulated spread. Knob selects axis character and spread; Boost widens and speeds the scan.",
  "CREDIT": "Adapted from null_signal by VJ CYBERPATROLUNIT (MIT)",
  "CATEGORIES": ["Filter", "Glitch", "Color Effect"],
  "INPUTS": [
    {"NAME": "inputImage", "TYPE": "image"},
    {"NAME": "amount", "TYPE": "float", "DEFAULT": 0.6, "MIN": 0.0, "MAX": 1.0},
    {"NAME": "knob", "TYPE": "float", "DEFAULT": 0.5, "MIN": 0.0, "MAX": 1.0, "LABEL": "Axis / Spread"},
    {"NAME": "boost", "TYPE": "bool", "DEFAULT": false, "LABEL": "Boost"}
  ]
}*/

vec2 safeUv(vec2 uv) { return clamp(uv, vec2(0.001), vec2(0.999)); }

vec3 sampleChromaLeak(vec2 uv, float amt, float k, float button) {
    vec2 centered = uv - 0.5;
    vec2 dir = normalize(centered + vec2(0.0001));
    float scan = sin(uv.y * RENDERSIZE.y * mix(0.018, 0.09, k) + TIME * (2.0 + button * 18.0));
    vec2 tangent = normalize(vec2(-dir.y, dir.x) + vec2(0.0001));
    vec2 axis = mix(dir, tangent, step(0.5, fract(k * 3.0)));
    float spread = amt * (1.5 + k * 26.0 + button * 18.0) / min(RENDERSIZE.x, RENDERSIZE.y);
    spread *= 0.65 + 0.35 * scan;
    float r = IMG_NORM_PIXEL(inputImage, safeUv(uv + axis * spread * 1.2)).r;
    float g = IMG_NORM_PIXEL(inputImage, safeUv(uv - axis * spread * 0.35)).g;
    float b = IMG_NORM_PIXEL(inputImage, safeUv(uv - axis * spread * 1.35)).b;
    return mix(IMG_NORM_PIXEL(inputImage, uv).rgb, vec3(r, g, b), amt);
}

void main() {
    float button = 0.0;
    if (boost) button = 1.0;
    vec2 uv = isf_FragNormCoord;
    float alpha = IMG_NORM_PIXEL(inputImage, uv).a;
    gl_FragColor = vec4(sampleChromaLeak(uv, amount, knob, button), alpha);
}
```

- [ ] **Step 4: Create `templates/NS Bayer Dither.fs`** (post.js `bayer4` + `applyDither`, lines 262–310; the audio `high` term is dropped):

```glsl
/*{
  "ISFVSN": "2.0",
  "DESCRIPTION": "Ordered Bayer dither blended with animated noise, luma two-tone at high strength, and an edge-aware accent lift. Knob trades cell size against quantization depth.",
  "CREDIT": "Adapted from null_signal by VJ CYBERPATROLUNIT (MIT)",
  "CATEGORIES": ["Filter", "Stylize", "Retro"],
  "INPUTS": [
    {"NAME": "inputImage", "TYPE": "image"},
    {"NAME": "amount", "TYPE": "float", "DEFAULT": 0.6, "MIN": 0.0, "MAX": 1.0},
    {"NAME": "knob", "TYPE": "float", "DEFAULT": 0.5, "MIN": 0.0, "MAX": 1.0, "LABEL": "Cell / Depth"},
    {"NAME": "boost", "TYPE": "bool", "DEFAULT": false, "LABEL": "Boost"},
    {"NAME": "accentColor", "TYPE": "color", "DEFAULT": [1.0, 0.0, 0.235, 1.0]}
  ]
}*/

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123); }

float bayer4(vec2 p) {
    vec2 q = mod(floor(p), 4.0);
    float x = q.x;
    float y = q.y;
    float v = 0.0;
    if (y < 0.5) {
        if (x < 0.5) v = 0.0;
        else if (x < 1.5) v = 8.0;
        else if (x < 2.5) v = 2.0;
        else v = 10.0;
    } else if (y < 1.5) {
        if (x < 0.5) v = 12.0;
        else if (x < 1.5) v = 4.0;
        else if (x < 2.5) v = 14.0;
        else v = 6.0;
    } else if (y < 2.5) {
        if (x < 0.5) v = 3.0;
        else if (x < 1.5) v = 11.0;
        else if (x < 2.5) v = 1.0;
        else v = 9.0;
    } else {
        if (x < 0.5) v = 15.0;
        else if (x < 1.5) v = 7.0;
        else if (x < 2.5) v = 13.0;
        else v = 5.0;
    }
    return (v + 0.5) / 16.0;
}

vec3 applyDither(vec3 color, vec2 uv, float amt, float k, float button) {
    vec3 accent = accentColor.rgb;
    float cell = mix(0.75, 5.5, amt * (0.45 + k * 0.9 + button * 0.45));
    vec2 grid = floor(uv * RENDERSIZE / cell);
    float ordered = bayer4(grid);
    float blueish = hash(grid + vec2(TIME * 13.0, TIME * 7.0));
    float threshold = mix(ordered, blueish, 0.12 + k * 0.45 + button * 0.3);
    float levels = mix(48.0, 2.5, amt * (0.5 + k * 0.8 + button * 0.45));
    vec3 shifted = color + (threshold - 0.5) / levels * (1.0 + amt * (1.0 + k * 3.0 + button * 2.0));
    vec3 quant = floor(clamp(shifted, 0.0, 1.0) * levels) / max(levels - 1.0, 1.0);
    float luma = dot(color, vec3(0.299, 0.587, 0.114));
    float mono = step(threshold, luma);
    vec3 twoTone = mix(accent * 0.18, mix(vec3(1.0), accent, 0.35), mono);
    float neighborX = dot(IMG_NORM_PIXEL(inputImage, uv + vec2(1.0 / RENDERSIZE.x, 0.0)).rgb,
                          vec3(0.299, 0.587, 0.114));
    float neighborY = dot(IMG_NORM_PIXEL(inputImage, uv + vec2(0.0, 1.0 / RENDERSIZE.y)).rgb,
                          vec3(0.299, 0.587, 0.114));
    float edge = min(abs(luma - neighborX) + abs(luma - neighborY), 1.0);
    vec3 edged = mix(quant, twoTone, smoothstep(0.08, 0.8, amt) * (0.35 + edge * 1.2));
    return mix(color, edged, amt);
}

void main() {
    float button = 0.0;
    if (boost) button = 1.0;
    vec2 uv = isf_FragNormCoord;
    vec4 base = IMG_NORM_PIXEL(inputImage, uv);
    vec3 color = base.rgb;
    if (amount > 0.001) color = applyDither(color, uv, amount, knob, button);
    gl_FragColor = vec4(color, base.a);
}
```

- [ ] **Step 5: Rebuild + run the template tests**

Run: `... -only-testing:TrueISFEditorTests/TemplatePackTests`
Expected: PASS — all 6 templates compile and pass the pixel gate. If Mirror Kaleido fails the gate at default preset, the failure is real (check `atan(0,0)` at dead-center is avoided by aspect scaling — it isn't a NaN source here because `atan(y, x)` with both 0 is defined-implementation but only affects one pixel; the gate tolerates single-pixel anomalies since it aggregates frame stats).

- [ ] **Step 6: Commit**

```bash
git add "templates/NS Mirror Kaleido.fs" "templates/NS Pixel Sort.fs" "templates/NS Chroma Leak.fs" "templates/NS Bayer Dither.fs"
git commit -m "feat(templates): NS Mirror Kaleido, Pixel Sort, Chroma Leak, Bayer Dither — null_signal post FX ports"
```

---

### Task 14: Integration — suites, roadmap, staging, gate

**Files:**
- Modify: `docs/ROADMAP.md`
- No other source changes.

- [ ] **Step 1: Full suites**

Run: `cd App && xcodebuild test -scheme TrueISFEditor -destination 'platform=macOS,arch=arm64' ARCHS=arm64 ONLY_ACTIVE_ARCH=YES -derivedDataPath ./ddata`
Expected: PASS — 287 pre-existing + 30 new (coordinator ×2, output manager ×1, vm pop-out ×1, LineDiff ×7, ParamStore codec ×5, SnapshotStore ×5, vm snapshots ×5, templates ×4).

Run: `cd ShadertoyISFKit && swift test`
Expected: PASS — 306, untouched by this plan.

- [ ] **Step 2: Update `docs/ROADMAP.md`** (per the maintenance note at its foot):
  - Phase D items 0, 1, 2: mark landed (Plan 2, 2026-07-17) with one-line pointers to the mechanisms (popOutEditing/setPaused seam; SnapshotStore + ParamSnapshot codec; LineDiff/DiffView).
  - Appendix "Into the editor" items 1–4: mark what shipped — codec doctrine (item 1) folded into ParamSnapshot; affordances (item 2) were Plan 1; post.js ports (item 3) wave 1 = mirror/sort/chromaLeak/dither/feedback echo, wave 2 remaining = wind, ink, burn/scan/jitter, strobe; composite.js (item 4) = NS Layer Blend shipped, strobe variant not.
  - D-item 10 note: template *mechanism* now exists (bundled folder + catalog + menu); filter/multipass/persistent starters and header autocomplete remain open.

- [ ] **Step 3: Stage the build**

Run: `scripts/run-latest.sh`
Then verify freshness (Xcode 26: grep the `.debug.dylib`, NOT the stub main binary):

```bash
grep -c "Output popped out — inline preview paused" \
  ~/Applications/TrueISFEditor.app/Contents/MacOS/TrueISFEditor.debug.dylib 2>/dev/null \
  || find ~/Applications/TrueISFEditor.app -name '*.debug.dylib' -exec grep -lc "Output popped out" {} \;
```

Expected: at least one match — the staged binary contains this plan's strings. Zero matches = stale binary; do NOT tell Conner to relaunch.

- [ ] **Step 4: Commit the roadmap + report status**

```bash
git add docs/ROADMAP.md
git commit -m "docs(roadmap): Phase D items 0-2 + null_signal wave-1 ports landed (Plan 2)"
```

Report to Conner with status **STAGED (not CONFIRMED)** and this on-device checklist:
  1. Pop out the output window → inline preview pane collapses, Adjust/Inputs/Passes fills the column, banner shows, GPU/fps readout follows the pop-out window.
  2. Edit while popped out → pop-out updates (debounced), diagnostics still live, no inline GPU burn (Activity Monitor GPU% if curious).
  3. Close the pop-out (or Restore Preview) → inline preview returns and animates (TIME continued, no restart flash).
  4. ⌘⌥V → versions list shows "Opened"/"Before AI…" entries; select one → diff renders; Restore works and is itself undoable via "Before restore".
  5. Run a ShaderAssist rewrite → apply preview now shows a colored folded diff.
  6. File ▸ New from Template → six NS templates open as untitled docs and render against the camera/test-pattern inputs. Specifically: NS Feedback Echo shows visible motion trails that decay (the machine gate only proves the persistent-buffer path executes non-black — trail behavior is this eyeball check).

**Do not push to the public remote until Conner has pinged the null_signal colleague (license courtesy — see Global Constraints).** **CLOSED 2026-08-03 — the heads-up was given and the colleague confirmed go-ahead (operator, this session).**

---

## Out of scope (recorded, not built)

- **null_signal wave 2 ports:** wind (luma-gated smear), ink (water refraction finish), burn/scan/jitter CRT block, shader-side strobe template. Same infrastructure; port when wave 1 proves out.
- **Phase D items 3–11** (media inputs, transport, resolution scaling, movie export, write-to-header, library management, point2D pad, header autocomplete, shortcut pass) — later plans.
- **Param-only presets UI** (named presets independent of source versions) — the codec now exists; UI deferred until write-back-to-header (D7) gives it a payoff moment.
- **WebKit engine pause** — `setPaused` no-ops there; the WebKit preview is a legacy fallback and its WKWebView keeps its own throttling.
