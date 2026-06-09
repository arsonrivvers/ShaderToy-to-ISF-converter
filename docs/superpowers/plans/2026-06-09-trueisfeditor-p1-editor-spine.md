# TrueISFEditor P1 Editor Spine — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans (inline) or
> superpowers:subagent-driven-development. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the Shadertoy-converter app into a document-centric ISF editor: open `.fs` from a
library, edit with CodeMirror, see it recompile live with inline errors, and save.

**Architecture:** App-layer only (engine `ShadertoyISFKit` untouched). A `LibraryModel` lists `.fs`
from User/System/added folders. An `ISFFile` is the open document. `CodeEditorView` hosts CodeMirror
6 in a WKWebView. An `EditorViewModel` wires open/edit → debounce → existing `ISFPreviewController`
→ {preview, input controls, gutter diagnostics, warnings}. Save/New/Import are menu commands;
Shadertoy import is a sheet producing an untitled `ISFFile`; preview detaches into its own window.

**Tech Stack:** SwiftUI/AppKit (macOS 13+), WKWebView, CodeMirror 6 (esbuild-bundled like ISF.js),
xcodegen, XCTest.

---

## File Structure

- `vendor/codemirror/` — npm project: `cm-entry.js`, `package.json`; esbuild → bundle.
- `App/TrueISFEditor/Resources/cm.bundle.js` — vendored CodeMirror bundle (committed).
- `App/TrueISFEditor/Resources/code-editor.html` — CodeMirror harness + JS API.
- `App/TrueISFEditor/CodeEditorView.swift` — NSViewRepresentable + WKWebView bridge.
- `App/TrueISFEditor/Models/ISFFile.swift` — open document model.
- `App/TrueISFEditor/Models/LibraryModel.swift` — `.fs` enumeration + sources + filter.
- `App/TrueISFEditor/EditorViewModel.swift` — orchestrates document ↔ editor ↔ preview.
- `App/TrueISFEditor/Views/LibraryView.swift` — sidebar list + filter.
- `App/TrueISFEditor/Views/EditorScreen.swift` — the 3-column editor layout (replaces converter ContentView body).
- `App/TrueISFEditor/Views/ShadertoyImportSheet.swift` — wraps existing convert flow.
- `App/TrueISFEditor/OutputWindow.swift` — detachable preview window.
- `App/TrueISFEditor/TrueISFEditorApp.swift` — Scene + menu commands (modify).
- `App/TrueISFEditorTests/` — `ISFFileTests`, `LibraryModelTests`.
- `App/TrueISFEditor/AppModel.swift` — keep convert logic; demote to import-sheet backing (modify).

---

### Task 1: CodeMirror 6 bundle + editor harness

**Files:**
- Create: `vendor/codemirror/package.json`, `vendor/codemirror/cm-entry.js`
- Create: `App/TrueISFEditor/Resources/cm.bundle.js` (generated)
- Create: `App/TrueISFEditor/Resources/code-editor.html`

- [ ] **Step 1:** `vendor/codemirror/package.json`:
```json
{ "name": "trueisf-codemirror", "private": true, "version": "1.0.0",
  "dependencies": { "codemirror": "^6.0.1", "@codemirror/lang-cpp": "^6.0.2",
    "@codemirror/view": "^6.0.0", "@codemirror/state": "^6.0.0",
    "@codemirror/lint": "^6.0.0", "@codemirror/language": "^6.0.0" } }
```

- [ ] **Step 2:** `vendor/codemirror/cm-entry.js` — exposes a global API for the harness:
```js
import { EditorView, basicSetup } from "codemirror";
import { EditorState, Compartment } from "@codemirror/state";
import { cpp } from "@codemirror/lang-cpp";
import { setDiagnostics } from "@codemirror/lint";
import { oneDark } from "@codemirror/theme-one-dark";

window.__createEditor = function (parent, initialDoc, onChange) {
  const view = new EditorView({
    parent,
    state: EditorState.create({
      doc: initialDoc || "",
      extensions: [
        basicSetup, cpp(), oneDark, EditorView.lineWrapping,
        EditorView.updateListener.of((u) => { if (u.docChanged) onChange(u.state.doc.toString()); }),
      ],
    }),
  });
  return view;
};
window.__cmSetDiagnostics = setDiagnostics;     // (view, [{from,to,severity,message}]) via Transaction
window.__cmEditorState = EditorState;
```
(Add `@codemirror/theme-one-dark` to deps.)

- [ ] **Step 3:** `App/TrueISFEditor/Resources/code-editor.html` — harness with the Swift-facing API:
```html
<!doctype html><html><head><meta charset="utf-8">
<style>html,body,#root{margin:0;height:100%;background:#282c34} .cm-editor{height:100%}</style>
</head><body><div id="root"></div>
<script src="cm.bundle.js"></script>
<script>
(function(){
  var view = null;
  function post(o){ if(window.webkit&&webkit.messageHandlers&&webkit.messageHandlers.editor){ webkit.messageHandlers.editor.postMessage(o);} else { console.info("CM_POST "+JSON.stringify(o)); } }
  window.initEditor = function(doc){
    view = window.__createEditor(document.getElementById("root"), doc||"", function(text){ post({type:"change", text:text}); });
  };
  window.setText = function(text){
    if(!view) return;
    view.dispatch({ changes:{ from:0, to:view.state.doc.length, insert:text } });
  };
  window.setDiagnostics = function(diags){            // diags: [{line, message, severity}]
    if(!view) return;
    var mapped = (diags||[]).map(function(d){
      var lineNo = Math.max(1, Math.min(d.line||1, view.state.doc.lines));
      var ln = view.state.doc.line(lineNo);
      return { from: ln.from, to: ln.to, severity: d.severity||"error", message: d.message||"" };
    });
    view.dispatch(window.__cmSetDiagnostics(view.state, mapped));
  };
  post({type:"ready"});
})();
</script></body></html>
```

- [ ] **Step 4:** Build the bundle:
```bash
cd vendor/codemirror && npm install && \
npx esbuild cm-entry.js --bundle --format=iife \
  --outfile=../../App/TrueISFEditor/Resources/cm.bundle.js
```
Expected: `cm.bundle.js` created (~1MB), exit 0.

- [ ] **Step 5:** Verify in Playwright (serve Resources, navigate to code-editor.html):
  `initEditor("void main(){}")`, then `setText("/*{}*/\nvoid main(){ }")`, read console for `CM_POST {"type":"ready"}` and a `change` post. Then `setDiagnostics([{line:2,message:"x",severity:"error"}])` — no JS error.

- [ ] **Step 6:** Commit `vendor/codemirror/{package.json,cm-entry.js}`, `Resources/{cm.bundle.js,code-editor.html}`. (`node_modules` gitignored.)

---

### Task 2: `ISFFile` document model (TDD)

**Files:** Create `App/TrueISFEditor/Models/ISFFile.swift`, `App/TrueISFEditorTests/ISFFileTests.swift`

- [ ] **Step 1:** Failing tests:
```swift
import XCTest
@testable import TrueISFEditor   // app module
final class ISFFileTests: XCTestCase {
    func test_untitled_isDirtyAfterEdit_andNeedsSaveAs() {
        var f = ISFFile.untitled()
        XCTAssertNil(f.url); XCTAssertFalse(f.isDirty)
        f.source = "void main(){}"
        XCTAssertTrue(f.isDirty)
        XCTAssertTrue(f.needsSaveAs)   // no url yet
    }
    func test_saveToURL_clearsDirty() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("t.fs")
        var f = ISFFile.untitled(); f.source = "X"
        try f.save(to: tmp)
        XCTAssertEqual(f.url, tmp); XCTAssertFalse(f.isDirty); XCTAssertFalse(f.needsSaveAs)
        XCTAssertEqual(try String(contentsOf: tmp, encoding: .utf8), "X")
    }
    func test_open_loadsSourceClean() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("o.fs")
        try "BODY".write(to: tmp, atomically: true, encoding: .utf8)
        let f = try ISFFile(contentsOf: tmp)
        XCTAssertEqual(f.source, "BODY"); XCTAssertFalse(f.isDirty); XCTAssertEqual(f.displayName, "o.fs")
    }
}
```

- [ ] **Step 2:** Run (will fail — type missing). `cd App && xcodebuild -project TrueISFEditor.xcodeproj -scheme TrueISFEditor -derivedDataPath ./ddata test -only-testing:TrueISFEditorTests/ISFFileTests 2>&1 | tail`

- [ ] **Step 3:** Implement `ISFFile`:
```swift
import Foundation
struct ISFFile {
    private(set) var url: URL?
    var source: String { didSet { if source != oldValue { isDirty = true } } }
    private(set) var isDirty: Bool
    var displayName: String { url?.lastPathComponent ?? "Untitled.fs" }
    var needsSaveAs: Bool { url == nil }

    private init(url: URL?, source: String, isDirty: Bool) { self.url = url; self.source = source; self.isDirty = isDirty }
    static func untitled(source: String = "") -> ISFFile { ISFFile(url: nil, source: source, isDirty: false) }
    init(contentsOf url: URL) throws { self.init(url: url, source: try String(contentsOf: url, encoding: .utf8), isDirty: false) }
    mutating func save(to target: URL) throws {
        try source.write(to: target, atomically: true, encoding: .utf8)
        url = target; isDirty = false
    }
    mutating func save() throws { guard let u = url else { return }; try save(to: u) }
}
```

- [ ] **Step 4:** Re-run tests → PASS.
- [ ] **Step 5:** Commit.

---

### Task 3: `LibraryModel` (TDD)

**Files:** Create `App/TrueISFEditor/Models/LibraryModel.swift`, `App/TrueISFEditorTests/LibraryModelTests.swift`

- [ ] **Step 1:** Failing tests (temp-dir fixture):
```swift
import XCTest
@testable import TrueISFEditor
final class LibraryModelTests: XCTestCase {
    func makeDir(_ files: [String]) throws -> URL {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        for f in files { try "x".write(to: d.appendingPathComponent(f), atomically: true, encoding: .utf8) }
        return d
    }
    func test_listsOnlyFSFiles_sorted() throws {
        let d = try makeDir(["b.fs", "a.fs", "note.txt", "c.FS"])
        let entries = LibraryModel.scan(folder: d)
        XCTAssertEqual(entries.map(\.name), ["a.fs", "b.fs", "c.FS"])   // .txt excluded, case-insensitive ext, sorted
    }
    func test_filter_byName_caseInsensitive() throws {
        let d = try makeDir(["Kaleido.fs", "ascii.fs"])
        var m = LibraryModel(); m.addFolder(d)
        XCTAssertEqual(m.filtered(query: "kal").map(\.name), ["Kaleido.fs"])
        XCTAssertEqual(m.filtered(query: "").count, 2)
    }
}
```

- [ ] **Step 2:** Run → fail.
- [ ] **Step 3:** Implement:
```swift
import Foundation
struct LibraryEntry: Identifiable, Hashable { let url: URL; var name: String { url.lastPathComponent }; var id: URL { url } }
struct LibrarySource: Identifiable, Hashable { let title: String; let url: URL; var id: URL { url } }

final class LibraryModel: ObservableObject {
    @Published private(set) var sources: [LibrarySource] = []
    private var entriesBySource: [URL: [LibraryEntry]] = [:]
    private let defaultsKey = "TrueISFEditor.addedFolders"

    static func scan(folder: URL) -> [LibraryEntry] {
        let fm = FileManager.default
        let items = (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return items.filter { $0.pathExtension.lowercased() == "fs" }
            .map { LibraryEntry(url: $0) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
    func addFolder(_ url: URL, title: String? = nil) {
        guard !sources.contains(where: { $0.url == url }) else { return }
        let src = LibrarySource(title: title ?? url.lastPathComponent, url: url)
        sources.append(src); entriesBySource[url] = Self.scan(folder: url); persist()
    }
    func entries(for source: LibrarySource) -> [LibraryEntry] { entriesBySource[source.url] ?? [] }
    func filtered(query: String) -> [LibraryEntry] {
        let all = sources.flatMap { entriesBySource[$0.url] ?? [] }
        guard !query.isEmpty else { return all }
        return all.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }
    func loadStandardLibraries() {
        let std: [(String, URL)] = [
            ("User", FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Graphics/ISF")),
            ("System", URL(fileURLWithPath: "/Library/Graphics/ISF")),
        ]
        for (t, u) in std where FileManager.default.fileExists(atPath: u.path) { addFolder(u, title: t) }
        for p in (UserDefaults.standard.array(forKey: defaultsKey) as? [String] ?? []) {
            addFolder(URL(fileURLWithPath: p))
        }
    }
    private func persist() {
        let standard = ["/Library/Graphics/ISF", FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Graphics/ISF").path]
        let added = sources.map(\.url.path).filter { !standard.contains($0) }
        UserDefaults.standard.set(added, forKey: defaultsKey)
    }
}
```

- [ ] **Step 4:** Run tests → PASS.
- [ ] **Step 5:** Commit.

---

### Task 4: `CodeEditorView` (WKWebView ↔ CodeMirror bridge)

**Files:** Create `App/TrueISFEditor/CodeEditorView.swift`

- [ ] **Step 1:** Implement an `NSViewRepresentable` hosting a WKWebView that loads `code-editor.html`,
  pushes initial text via `initEditor`, applies external text via `setText`, reports edits via a
  `onChange` closure, and applies diagnostics via `setDiagnostics`. Mirror `ISFPreviewController`'s
  message-handler + queue-until-ready pattern. Coordinator conforms to `WKScriptMessageHandler`.
  (Full code written at execution; key contract: `@Binding var text`, `var diagnostics:[EditorDiagnostic]`,
  ready-gating, and guarding against echo loops — when applying external `setText`, suppress the
  resulting `change` post by comparing against last-known text.)

- [ ] **Step 2:** Verify the bridge via Playwright against the harness (set/get/diagnostics round-trip).
- [ ] **Step 3:** Commit.

---

### Task 5: `EditorViewModel` — open/edit → recompile fan-out

**Files:** Create `App/TrueISFEditor/EditorViewModel.swift`

- [ ] **Step 1:** Implement `@MainActor final class EditorViewModel: ObservableObject` holding:
  `@Published var file: ISFFile`, a reference to an `ISFPreviewController`, `@Published var
  diagnostics: [EditorDiagnostic]`, `@Published var conversionWarnings: [ConversionWarning]`.
  - `open(_ entry: LibraryEntry)` → `file = try ISFFile(contentsOf: entry.url)` → `recompile(immediate: true)`.
  - `sourceEdited(_ text: String)` → `file.source = text` → `recompile(immediate: false)` (300ms debounce Task via `Task.sleep`, cancel previous).
  - `recompile` → `preview.load(isf: file.source)`. The preview controller already posts compile
    results; observe `preview.$compileError`/`compileErrorLine`/`compileValid`/`inputs` and translate
    a compile error into `diagnostics = [EditorDiagnostic(line: compileErrorLine ?? 1, message:…, severity:.error)]`,
    else `diagnostics = []`. (Inputs flow to the controls panel already via `preview.inputs`.)
  - `newUntitled(source:)`, `loadImported(_ isf: String)` (from Shadertoy sheet) → set untitled file + recompile.
- [ ] **Step 2:** Wire `preview` publishers with Combine `sink` to recompute `diagnostics`.
- [ ] **Step 3:** Commit.

---

### Task 6: `LibraryView` sidebar + dirty dot + focused filter

**Files:** Create `App/TrueISFEditor/Views/LibraryView.swift`

- [ ] **Step 1:** Sidebar: a `TextField` filter (focused via `@FocusState` `.onAppear`), then a `List`
  grouped by source (`Section(source.title)`), rows = filtered entries. Single-click (`.onTapGesture`
  or selectable `List`) calls `vm.open(entry)`. Show a filled dot when `entry.url == vm.file.url &&
  vm.file.isDirty`. "Add Folder…" button → NSOpenPanel (directories) → `library.addFolder`.
- [ ] **Step 2:** Commit.

---

### Task 7: `EditorScreen` layout + integrate editor/preview/controls/warnings

**Files:** Create `App/TrueISFEditor/Views/EditorScreen.swift`; modify nothing in engine.

- [ ] **Step 1:** Three-column `NavigationSplitView` (or `HSplitView`): `LibraryView` | center VStack
  (`CodeEditorView(text:diagnostics:onChange:)` over `WarningsView(warnings: vm.conversionWarnings,
  previewError:…)`) | right VStack (`ISFPreviewView` + `PreviewControlsView(controller: vm.preview)` +
  pop-out button). `CodeEditorView.text` bound to `vm.file.source`; edits call `vm.sourceEdited`.
- [ ] **Step 2:** Commit.

---

### Task 8: Shadertoy import as a sheet

**Files:** Create `App/TrueISFEditor/Views/ShadertoyImportSheet.swift`; modify `AppModel.swift` (keep
convert/convertPastedCode; expose the produced ISF + warnings).

- [ ] **Step 1:** Sheet presents URL field + paste box + Convert buttons (reuse `AppModel`). On a
  successful convert, call back `onImport(isf: String, warnings: [ConversionWarning], suggestedName: String)`
  → `EditorViewModel.loadImported` creates an untitled `ISFFile`, sets warnings, recompiles; dismiss sheet.
- [ ] **Step 2:** Commit.

---

### Task 9: Menu commands, detachable output, app scene

**Files:** Modify `App/TrueISFEditor/TrueISFEditorApp.swift`; create `App/TrueISFEditor/OutputWindow.swift`.

- [ ] **Step 1:** Replace the scene with the editor. `WindowGroup { EditorScreen() }` owning shared
  `LibraryModel` + `EditorViewModel`. Add `.commands`:
  - `CommandGroup(replacing: .newItem)`: "New" (blank template), "New from Shadertoy…" (`Cmd-Shift-N`, toggles sheet).
  - Save (`Cmd-S` → `vm.save()`, routes to Save As/NSSavePanel if `needsSaveAs`), Save As (`Cmd-Shift-S`).
  - Open Folder… (adds a library source).
- [ ] **Step 2:** Blank template string (compilable ISF skeleton) as a constant.
- [ ] **Step 3:** Detachable output: a button in the preview column opens a second `Window`
  (`WindowGroup(id:"output")` or `NSWindow`) bound to the same `vm.preview.webView` mirror — simplest:
  a new `ISFPreviewController` that loads `vm.file.source` and stays synced via the VM. Resizable.
- [ ] **Step 4:** Commit.

---

### Task 10: Build, test, launch-verify

- [ ] **Step 1:** `cd App && xcodegen generate` (picks up new files), then `xcodebuild … build`.
- [ ] **Step 2:** `cd ShadertoyISFKit && swift test` → 57/57. App tests: `xcodebuild … test`.
- [ ] **Step 3:** Verify staged `.debug.dylib` contains new strings (e.g. "TrueISFEditor.ISFFile", template marker).
- [ ] **Step 4:** Launch, confirm: sidebar pre-populated (System/User), single-click loads + renders +
  controls populate, edit shows live recompile + gutter error on a bad edit, Save works, pop-out opens.
  Screenshot. Refresh repo-root `TrueISFEditor.app`.
- [ ] **Step 5:** Final commit.

---

## Self-Review

- **Spec coverage:** library (T3,T6), CodeMirror editor (T1,T2), live recompile + controls-on-open +
  gutter errors (T5), save/dirty/untitled→SaveAs (T2,T9), first-launch auto-load std dirs
  (T3 `loadStandardLibraries`, T9), detachable output (T9), Shadertoy-as-sheet (T8), cut imported pane
  (T7 layout), single-click load + dirty dot + focused filter (T6). All covered.
- **Placeholder scan:** T4/T5/T7–T9 describe SwiftUI/bridge code with explicit contracts but defer
  full boilerplate to execution; logic-bearing units (T2,T3) have complete code + tests. Acceptable
  for inline execution by the author; tighten if handed to a cold subagent.
- **Type consistency:** `ISFFile` (source/isDirty/url/needsSaveAs/save), `LibraryModel`
  (scan/addFolder/filtered/loadStandardLibraries), `LibraryEntry.url/name`, `EditorDiagnostic(line,
  message,severity)`, `EditorViewModel.open/sourceEdited/loadImported/save` — used consistently.
