# Phase A + B: Data Safety + ParamStore Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close the four data-safety holes from the 2026-07-17 diagnostic and land the ParamStore keystone (param persistence across recompiles, pop-out parity, time continuity, engine housekeeping).

**Architecture:** Phase A is four independent app-layer fixes. Phase B extracts shader input values from `PreviewControlsView` view-local `@State` into an observable `ParamStore` owned by `EditorViewModel`, which forwards sets to BOTH preview coordinators and replays all values whenever either controller installs a new scene; time continuity comes from switching `MetalRenderCore` to `ISFMSLSafeRenderAtTime` with a core-owned pausable clock that survives scene swaps.

**Tech Stack:** Swift/SwiftUI (macOS 13+), Metal via vendored ISFMSLKit, CodeMirror 6 in WKWebView, XCTest.

## Global Constraints

- This is the plan of record for ROADMAP.md Phases A and B. Plan 2 (Phase D + templates) and Plan 3 (conversion track) follow after this lands.
- Snapshot/preset serialization is **Plan 2** — but ParamStore must be name-keyed `[String: ParamValue]` with defaults, so the codec (null_signal patterns: versioned flat JSON, name-first resolution, validate-and-clamp) bolts on without rework.
- Tests: every task with logic lands with XCTest coverage in `App/TrueISFEditorTests/` (run: `cd App && xcodebuild test -scheme TrueISFEditor -destination 'platform=macOS,arch=arm64' ARCHS=arm64 ONLY_ACTIVE_ARCH=YES -derivedDataPath ./ddata -only-testing:TrueISFEditorTests/<Class>`).
- Stage builds ONLY via `./scripts/run-latest.sh`; verify freshness via compiled string literals or build log + dylib mtime (comments never land in binaries).
- Commit per task; never `git add -A` (concurrent sessions).
- Event inputs stay momentary (pulse-only) in this plan — no held-state modeling (YAGNI until the VJ app).

---

### Task 1 (A1): Clear editor history on document switch

**Files:**
- Modify: `App/TrueISFEditor/Resources/code-editor.html` (add `resetDocument`)
- Modify: `App/TrueISFEditor/CodeEditorView.swift` (add `resetText`)
- Modify: `App/TrueISFEditor/EditorViewModel.swift:120-175` (document-replacement paths call `resetText`)

**Interfaces:**
- Produces: `CodeEditorController.resetText(_ text: String)` — replaces the document AND destroys undo history. `setText` keeps existing semantics (in-document programmatic update, undoable).

- [ ] **Step 1: JS — add `resetDocument`** to `code-editor.html` after `setText`:

```js
  // Replace the document AND drop undo history (document switch — ⌘Z must not
  // resurrect the previous file's text into this one).
  window.resetDocument = function (text) {
    if (!view) { window.initEditor(text); return; }
    view.destroy();
    document.getElementById("root").innerHTML = "";
    window.initEditor(text);
  };
```

Note `initEditor` (line 28) already wires the change callback; `suppressNextChange` is not needed because a fresh editor emits no change event on creation.

- [ ] **Step 2: Swift — add `resetText` to `CodeEditorController`** (below `setText`):

```swift
    /// Replace the document AND drop undo history — for document switches, where ⌘Z must not
    /// restore the previous file's content into the new one (data-corruption class A1).
    func resetText(_ text: String) {
        lastText = text
        guard ready, initialized, let lit = jsStringLiteral(text) else { return }
        webView.evaluateJavaScript("resetDocument(\(lit));")
    }
```

- [ ] **Step 3: Switch the four document-replacement paths** in `EditorViewModel` (`open`, `newUntitled`, `loadImported`, `loadExample`) from `editor.setText(...)` to `editor.resetText(...)`. `replaceSourceFromAssist` and diagnostics flows KEEP `setText`/`applyTextEdit` (in-document, must stay undoable).

- [ ] **Step 4: Test** — in `App/TrueISFEditorTests/EditorViewModelTests.swift`, the existing suite constructs `EditorViewModel` with the real controller; assert behavior at the seam: add a spy assertion that `open` triggers a reset, by exposing `private(set) var lastResetTextForTest: String?` set in `resetText` (mirror how `lastArgsForTest` is done in the runners). Assert `vm.open(entry)` sets it, and `vm.replaceSourceFromAssist` does NOT.

- [ ] **Step 5: Run tests, commit** `feat(editor): drop undo history on document switch (A1)`

### Task 2 (A2): Unsaved-changes guard on quit

**Files:**
- Modify: `App/TrueISFEditor/TrueISFEditorApp.swift`

**Interfaces:**
- Produces: `AppQuitGuard` (NSApplicationDelegate) with `var hasUnsavedChanges: () -> Bool` and `var confirmDiscard: () -> Bool`.

- [ ] **Step 1: Add the delegate class** (new type at bottom of `TrueISFEditorApp.swift`):

```swift
/// A2: ⌘Q guard. SwiftUI Window scenes have no native terminate hook; this delegate asks the
/// EditorViewModel (via closures, set in the App init) whether edits would be lost.
final class AppQuitGuard: NSObject, NSApplicationDelegate {
    var hasUnsavedChanges: () -> Bool = { false }
    var confirmDiscard: () -> Bool = { true }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard hasUnsavedChanges() else { return .terminateNow }
        return confirmDiscard() ? .terminateNow : .terminateCancel
    }
}
```

- [ ] **Step 2: Wire it** in `TrueISFEditorApp`:

```swift
    @NSApplicationDelegateAdaptor(AppQuitGuard.self) private var quitGuard
```

and at the END of `init()` (after the debug harness block):

```swift
        // Closures capture the StateObject's wrapped instance; safe — both outlive the app run.
        let vmRef = _vm.wrappedValue
        quitGuard.hasUnsavedChanges = { MainActor.assumeIsolated { vmRef.file.isDirty } }
        quitGuard.confirmDiscard = { MainActor.assumeIsolated { vmRef.canReplaceDocument() } }
```

(`canReplaceDocument()` already runs the standard "Discard Changes / Cancel" NSAlert — `EditorViewModel.swift:103-118`; make it `internal` if currently `private`.)

- [ ] **Step 3: Manual verification** (NSApplication terminate isn't unit-testable): edit without saving, ⌘Q → alert appears; Cancel keeps the app; clean file → ⌘Q quits immediately. Record result in the commit message.

- [ ] **Step 4: Commit** `feat(app): unsaved-changes guard on quit (A2)`

### Task 3 (A3): Fingerprint the Diagnose & Fix flow + reset assist on document switch

**Files:**
- Modify: `App/TrueISFEditor/ShaderAssist/ShaderAssistViewModel.swift`
- Modify: `App/TrueISFEditor/Views/EditorScreen.swift`
- Test: `App/TrueISFEditorTests/ShaderAssistViewModelTests.swift`

**Interfaces:**
- Produces: `ShaderAssistViewModel.fixSourceFingerprint: String?` (set when `.fix` state is entered, from the source the fix was generated against); `func resetForDocumentSwitch()` (cancels + clears ALL state incl. lastRun).

- [ ] **Step 1: Failing tests:**

```swift
    func testFixResultCarriesSourceFingerprint() async {
        let provider = FakeAssistProvider([.success(#"{"explanation":"E","edits":[{"fromLine":1,"toLine":1,"replacement":"x","rationale":"r"}]}"#)])
        let vm = ShaderAssistViewModel(providerOverride: provider)
        let src = "/*{}*/\nvoid main(){}"
        vm.run(.diagnoseAndFix, source: src, diagnostics: [])
        await settle()
        XCTAssertEqual(vm.fixSourceFingerprint, ShaderAssistViewModel.sourceFingerprint(src))
    }

    func testResetForDocumentSwitchClearsFixAndRetry() async {
        let provider = FakeAssistProvider([.success(#"{"explanation":"E","edits":[]}"#)])
        let vm = ShaderAssistViewModel(providerOverride: provider)
        vm.run(.diagnoseAndFix, source: "/*{}*/\nvoid main(){}", diagnostics: [])
        await settle()
        vm.resetForDocumentSwitch()
        if case .idle = vm.state {} else { XCTFail("expected idle") }
        XCTAssertNil(vm.fixSourceFingerprint)
        XCTAssertFalse(vm.canRetry)
    }
```

- [ ] **Step 2: Implement.** In `ShaderAssistViewModel`: add `@Published private(set) var fixSourceFingerprint: String?`; in `run`'s `.diagnoseAndFix` success arm set it to `Self.sourceFingerprint(source)` before `state = .fix(r)`; add:

```swift
    /// A3: a fix generated against one document must not survive into another.
    func resetForDocumentSwitch() {
        task?.cancel()
        lastRun = nil
        fixSourceFingerprint = nil
        handledEdits = []
        startSuggestionFlowOver()
    }
```

- [ ] **Step 3: Guard at apply + reset on switch.** In `EditorScreen`'s `.fix` case, wrap the apply closure:

```swift
                handled: $shaderAssist.handledEdits) { edit in
                    guard shaderAssist.fixSourceFingerprint ==
                          ShaderAssistViewModel.sourceFingerprint(vm.file.source) else {
                        shaderAssist.resetForDocumentSwitch()
                        return
                    }
                    vm.apply(ShaderAssistViewModel.textEdit(from: edit, source: vm.file.source))
                }
```

and on the screen's root view add `.onChange(of: vm.documentGeneration) { _ in shaderAssist.resetForDocumentSwitch() }`.

(Within-document edits after fix generation: intentionally still allowed — `TextEdit.expectedContains` line-content guard in `EditorViewModel.apply` handles line drift; the fingerprint guards *document identity*.)

- [ ] **Step 4: Run tests, commit** `fix(assist): fingerprint Diagnose&Fix + reset assist on document switch (A3)`

### Task 4 (A4): Surface save failures loudly

**Files:**
- Modify: `App/TrueISFEditor/EditorViewModel.swift:181-189`

- [ ] **Step 1:** Replace the two `catch { statusMessage = "Save failed: ..." }` arms with a modal alert (matching `canReplaceDocument`'s NSAlert idiom):

```swift
        catch { presentSaveError(error) }
```
```swift
    /// A4: a failed save is data loss pending — a 5s toast is not enough.
    private func presentSaveError(_ error: Error) {
        statusMessage = "Save failed: \(error.localizedDescription)"
        let alert = NSAlert()
        alert.messageText = "Save failed"
        alert.informativeText = "\(error.localizedDescription)\n\nYour changes are still in the editor. Try Save As… to a writable location."
        alert.alertStyle = .critical
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
```

- [ ] **Step 2: Manual verification:** open a System-library shader (`/Library/Graphics/ISF` is read-only), edit, ⌘S → alert. Commit `fix(app): modal alert on save failure (A4)`

### Task 5 (B1a): ParamStore model

**Files:**
- Create: `App/TrueISFEditor/Models/ParamStore.swift`
- Test: `App/TrueISFEditorTests/ParamStoreTests.swift`

**Interfaces (produces — later tasks depend on these exact signatures):**

```swift
enum ParamValue: Equatable {
    case float(Double), bool(Bool), long(Double), point2D([Double]), color([Double])
    /// The JSON fragment `PreviewCoordinator.setInput` expects.
    var jsonFragment: String { ... }
}

@MainActor final class ParamStore: ObservableObject {
    @Published private(set) var values: [String: ParamValue]   // name-keyed (survives input reorder)
    private(set) var defaults: [String: ParamValue]            // from the current header
    /// Fired on every set/reset — EditorViewModel forwards to both coordinators.
    var onSet: ((_ name: String, _ jsonFragment: String) -> Void)?

    func set(_ name: String, _ value: ParamValue)              // records + fires onSet
    func value(for name: String) -> ParamValue?                // user value, else default, else nil
    func isModified(_ name: String) -> Bool                    // user value differs from default
    func resetToDefault(_ name: String)                        // removes user value + fires onSet with default
    func syncInputs(_ inputs: [ISFPreviewInput])               // rebuild defaults; PRUNE values whose
                                                               // name no longer exists; KEEP survivors
    func resetAll()                                            // document switch: clear values+defaults
    /// Replay every stored user value into a freshly-installed scene (B keystone).
    func replayAll()                                           // fires onSet for each stored value
}
```

`syncInputs` builds `defaults` from `ISFPreviewInput.defaultValue` per type (float/long → `.float/.long`, bool → `.bool`, point2D/color → arrays via the same coercion `PreviewControlsView.doubles` uses today — move that helper here as `ParamStore.doubles`). Image/event inputs get no entry.

- [ ] **Step 1: Failing tests** (`ParamStoreTests`): set-then-value round-trip per type; `jsonFragment` exact strings (`.float(0.5)` → `"0.5"`, `.bool(true)` → `"true"`, `.long(3)` → `"3"`, `.point2D([0.1, 0.2])` → `"[0.1, 0.2]"`, `.color([1,0,0,1])` → `"[1.0, 0.0, 0.0, 1.0]"`); `isModified` false at default, true after set, false after `resetToDefault`; `syncInputs` prunes vanished names, keeps survivors; `replayAll` fires `onSet` once per stored value with correct fragments; `resetAll` empties everything.
- [ ] **Step 2: Implement** (pure model, no coordinator import beyond `ISFPreviewInput`).
- [ ] **Step 3: Run tests, commit** `feat(params): ParamStore model (B1a)`

### Task 6 (B1b): Rewire PreviewControlsView onto ParamStore

**Files:**
- Modify: `App/TrueISFEditor/Views/PreviewControlsView.swift` (delete the five `@State` dicts)

**Interfaces:**
- Consumes: `ParamStore` from Task 5. View signature becomes `PreviewControlsView(coordinator:store:)`.

- [ ] **Step 1:** Replace each control's binding to read/write the store. Pattern (float; others analogous):

```swift
    @ObservedObject var store: ParamStore

    let binding = Binding<Double>(
        get: { if case .float(let v)? = store.value(for: input.name) { return v }
               return (input.defaultValue as? Double) ?? lo },
        set: { store.set(input.name, .float($0)) })
```

The view NO LONGER calls `coordinator.setInput` — the store's `onSet` does (Task 7). `eventControl` keeps calling `coordinator.pulseEvent` directly (events are not stored).

- [ ] **Step 2: null_signal affordances:** every row gets (a) double-click reset: `.onTapGesture(count: 2) { store.resetToDefault(input.name) }` on the `labelRow`; (b) modified marker: in `labelRow`, before the name, `if store.isModified(name) { Circle().fill(.tint).frame(width: 5, height: 5) }` — pass `input.name` into `labelRow`.
- [ ] **Step 3:** Update the two call sites (`EditorScreen` HeaderPanelView plumbing — find `PreviewControlsView(` usages and pass `vm.paramStore`). Build, commit `feat(params): controls read/write ParamStore + dblclick reset + modified dot (B1b)`

### Task 7 (B1c): EditorViewModel wiring — forward, reset, replay

**Files:**
- Modify: `App/TrueISFEditor/EditorViewModel.swift`
- Modify: `App/TrueISFEditor/MetalPreviewController.swift` (add `onSceneInstalled`)
- Modify: `App/TrueISFEditor/PreviewCoordinator.swift` (surface the hook)
- Modify: `App/TrueISFEditor/Views/EditorScreen.swift` (pop-out wiring)
- Test: `App/TrueISFEditorTests/ParamStoreWiringTests.swift`

**Interfaces:**
- Produces: `EditorViewModel.paramStore: ParamStore`; `MetalPreviewController.onSceneInstalled: (() -> Void)?` (called at the END of the `applyCompile` success arm); `PreviewCoordinator.onSceneInstalled` forwarding to the active engine's controller.

- [ ] **Step 1:** `EditorViewModel` owns `let paramStore = ParamStore()`. In its init wiring section:

```swift
        paramStore.onSet = { [weak self] name, json in
            self?.preview.setInput(name, json)
            self?.outputSink?(name, json)          // pop-out, when open (set by EditorScreen)
        }
        preview.onSceneInstalled = { [weak self] in
            guard let self else { return }
            self.paramStore.syncInputs(self.preview.inputs)
            self.paramStore.replayAll()
        }
```

`outputSink: ((String, String) -> Void)?` is a var on EditorViewModel; `EditorScreen` sets it to `{ output.coordinator.setInput($0, $1) }` in `onAppear`.

- [ ] **Step 2:** All four document-replacement paths call `paramStore.resetAll()` (same places as Task 1 Step 3).
- [ ] **Step 3:** Pop-out replay: `OutputWindowManager` gets `var onSceneInstalled: (() -> Void)?` passthrough on its coordinator too; `EditorScreen.onAppear` sets `output.coordinator.onSceneInstalled = { vm.paramStore.replayAll() }` — one store, two sinks, both replayed on their own compile cadence. Event pulses: in `EditorScreen`, the event control path goes through `vm.pulseEvent(name)` which calls `preview.pulseEvent` AND `output.coordinator.pulseEvent` when open (add the tiny forwarder to EditorViewModel; update `PreviewControlsView` to call a closure `onPulse` instead of the coordinator directly).
- [ ] **Step 4: Tests** (`ParamStoreWiringTests`): fake sinks record (name, json); assert a `store.set` reaches both sinks; assert `onSceneInstalled` → all values replayed; assert `resetAll` on document switch (via `vm.newUntitled()` with dirty-guard bypassed as existing tests do).
- [ ] **Step 5: Run tests + `./scripts/run-latest.sh`; on-device check:** drag slider → edit code → value HOLDS after recompile; pop-out reflects slider drags live. Commit `feat(params): store wiring — dual-sink forward + replay on scene install (B1c)`

### Task 8 (B2): Time continuity across recompiles

**Files:**
- Modify: `App/TrueISFEditor/MetalRenderCore.swift` (clock + `ISFMSLSafeRenderAtTime`)
- Modify: `App/TrueISFEditor/MetalPreviewController.swift` (reset hook on document switch)
- Modify: `App/TrueISFEditor/EditorViewModel.swift` (call reset on the four document paths)
- Test: `App/TrueISFEditorTests/RenderClockTests.swift`

**Interfaces:**
- Produces: `RenderClock` (small struct/final class, testable): `var now: Double { get }` (elapsed, pause-aware), `func pause()`, `func resume()`, `func reset()`. `MetalRenderCore.resetClock()` and `MetalRenderCore` renders via `ISFMSLSafeRenderAtTime(scene, size, clock.now, ...)` instead of `ISFMSLSafeRender`.

- [ ] **Step 1: Failing tests** for `RenderClock` (inject a `nowSource: () -> Double` for determinism): advances with source; pause freezes; resume continues without jump; reset returns to 0.
- [ ] **Step 2: Implement RenderClock** (CACurrentMediaTime default source) + switch `MetalRenderCore.draw`'s render call to `ISFMSLSafeRenderAtTime` with `clock.now`. The clock lives on the core (render thread reads it inside the existing lock — make it lock-free: store `startHostTime`/`pausedAt` as atomics or read under the existing coarse lock, matching current style).
- [ ] **Step 3: Reset semantics:** `MetalPreviewController.load` NO LONGER implies a time reset (scene swap keeps the clock). Add `func resetTimeline()` on controller+coordinator → `core.resetClock()`. The four document-replacement paths in `EditorViewModel` call `preview.resetTimeline()` (document switch = fresh time; recompile of same document = continuous time). Also pause/resume the clock inside `setPaused` so pausing stops time (not just frames).
- [ ] **Step 4: Known limitation (document in code comment + ROADMAP):** persistent buffers still reset on recompile (new scene, new targets) — full buffer continuity is out of scope; the win here is TIME + params.
- [ ] **Step 5: Tests green, stage, on-device check:** animated shader keeps its phase while typing (no restart flash); pixel gate (`runPixelGate` uses `ISFMSLSafeRenderAtTime` already — unaffected). Commit `feat(engine): app-owned render clock — time survives recompiles (B2)`

### Task 9 (B4): Engine housekeeping

**Files:**
- Modify: `App/TrueISFEditor/EditorViewModel.swift:34-37` (size cap)
- Modify: `App/TrueISFEditor/MetalPreviewController.swift` (pool housekeeping + occlusion)
- Modify: `App/TrueISFEditor/ISFSceneSource.swift:70-75` (lastGood copy)

- [ ] **Step 1: Size cap:** clamp `doubleRenderSize()` to 8192 per axis (`min(w*2, 8192)`); test in `EditorViewModelTests` (double from 8000 → 8192, not 16000).
- [ ] **Step 2: Pool housekeeping:** in `applyCompile` success arm and in `setRenderSize`, call `VVMTLPool.global.housekeeping()` (check exact API name in `vendor/prebuilt/.../VVMTLRecyclingPool.h:32` — it's `- (void) housekeeping;`).
- [ ] **Step 3: Occlusion pause:** in `MetalPreviewController.updateDriverRunning`, also require `mtkView?.window?.occlusionState.contains(.visible) != false`; observe `NSWindow.didChangeOcclusionStateNotification` for the view's window and call `updateDriverRunning()` on fire.
- [ ] **Step 4: lastGood aliasing fix:** in `ISFSceneSource.texture(size:in:)`, replace caching the raw scene output with a blit into an owned texture (create once per size, `MTLTextureDescriptor` matching format, `blitEncoder.copy(from:to:)` on the passed command buffer) so a pool-recycled texture can never be displayed as the fallback frame.
- [ ] **Step 5: Build + full app test suite green; stage; commit** `fix(engine): size cap, pool housekeeping, occlusion pause, lastGood copy (B4)`

### Task 10: Phase A+B close-out gate

- [ ] Full suite: kit (`swift test` in ShadertoyISFKit) + app (xcodebuild test) — all green
- [ ] `./scripts/run-latest.sh`, binary freshness verified via a compiled literal
- [ ] Mechanic manual review (CoS reads the whole diff) + CS live UX pass on the param panel changes
- [ ] Update `docs/ROADMAP.md` (mark A/B done), memory note, handoff for Plan 2 (Phase D)
