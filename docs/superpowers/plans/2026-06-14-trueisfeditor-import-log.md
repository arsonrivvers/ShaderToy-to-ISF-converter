# Import Log + inline import summary — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax.

**Goal:** A persistent Import Log (window + JSON store) plus an inline import outcome in the import sheet, recording fetch→parse→convert for every Shadertoy import attempt.

**Architecture:** Mirror the existing CrashLog pattern: a `Codable` `ImportEvent`, a `@MainActor ObservableObject` `ImportLog.shared` persisted under `~/Library/Logs/TrueISFEditor/`, recorded from `AppModel.convert()`, surfaced in a `Window("Import Log")` (clone of CrashLogView) and a one-line summary in `ShadertoyImportSheet`.

**Tech Stack:** Swift, SwiftUI, XCTest. App target `TrueISFEditor`; tests in `App/TrueISFEditorTests/`.

---

### Task 1: `ImportEvent` model + pure formatters

**Files:**
- Create: `App/TrueISFEditor/ImportEvent.swift`
- Test: `App/TrueISFEditorTests/ImportEventTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import TrueISFEditor

final class ImportEventTests: XCTestCase {
    func test_success_summaryLine() {
        let e = ImportEvent(query: "N323DD", shaderID: "N323DD", fetchSource: .webView,
                            httpStatus: 200, stage: .converted, outcome: .success,
                            message: "Converted cleanly.", responseSnippet: nil, warningCount: 0)
        XCTAssertEqual(e.summaryLine, "✓ Converted")
    }
    func test_warning_summaryLine_pluralizes() {
        let e = ImportEvent(query: "x", shaderID: "x", fetchSource: .webView, httpStatus: 200,
                            stage: .converted, outcome: .warning, message: "Converted with 2 warning(s).",
                            responseSnippet: nil, warningCount: 2)
        XCTAssertEqual(e.summaryLine, "✓ Converted (2 warnings)")
    }
    func test_warning_summaryLine_singular() {
        let e = ImportEvent(query: "x", shaderID: "x", fetchSource: .webView, httpStatus: 200,
                            stage: .converted, outcome: .warning, message: "m", responseSnippet: nil, warningCount: 1)
        XCTAssertEqual(e.summaryLine, "✓ Converted (1 warning)")
    }
    func test_error_summaryLine() {
        let e = ImportEvent(query: "x", shaderID: nil, fetchSource: .webView, httpStatus: nil,
                            stage: .urlInvalid, outcome: .error, message: "That doesn't look like a Shadertoy URL or ID.",
                            responseSnippet: nil, warningCount: 0)
        XCTAssertEqual(e.summaryLine, "✗ That doesn't look like a Shadertoy URL or ID.")
    }
    func test_codableRoundTrip() throws {
        let e = ImportEvent(query: "q", shaderID: "id", fetchSource: .api, httpStatus: 403,
                            stage: .fetched, outcome: .error, message: "m", responseSnippet: "body…", warningCount: 0)
        let data = try JSONEncoder().encode(e)
        XCTAssertEqual(try JSONDecoder().decode(ImportEvent.self, from: data), e)
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd ShadertoyISFKit && true` — N/A; build the app test target:
`xcodebuild test -project App/TrueISFEditor.xcodeproj -scheme TrueISFEditor -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/trueisfeditor-ddata -only-testing:TrueISFEditorTests/ImportEventTests ARCHS=arm64 ONLY_ACTIVE_ARCH=YES`
Expected: FAIL — `cannot find 'ImportEvent' in scope`.

- [ ] **Step 3: Implement `ImportEvent`**

```swift
import Foundation

/// One Shadertoy import attempt (fetch → parse → convert), recorded into `ImportLog`.
struct ImportEvent: Codable, Equatable, Identifiable {
    enum FetchSource: String, Codable { case api, webView }
    enum Stage: String, Codable { case urlInvalid, fetched, parsed, converted }
    enum Outcome: String, Codable { case success, warning, error }

    var id = UUID()
    var timestamp = Date()
    let query: String
    let shaderID: String?
    let fetchSource: FetchSource
    let httpStatus: Int?
    let stage: Stage
    let outcome: Outcome
    let message: String
    let responseSnippet: String?
    let warningCount: Int

    /// One-line outcome for the import sheet. Pure; unit-tested.
    var summaryLine: String {
        switch outcome {
        case .success: return "✓ Converted"
        case .warning:
            let unit = warningCount == 1 ? "warning" : "warnings"
            return "✓ Converted (\(warningCount) \(unit))"
        case .error: return "✗ \(message)"
        }
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Run the same `-only-testing:TrueISFEditorTests/ImportEventTests` command. Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add App/TrueISFEditor/ImportEvent.swift App/TrueISFEditorTests/ImportEventTests.swift
git commit -m "feat(import-log): ImportEvent model + summary formatter"
```

---

### Task 2: `ImportLog` store

**Files:**
- Create: `App/TrueISFEditor/ImportLog.swift`
- Test: `App/TrueISFEditorTests/ImportLogTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import TrueISFEditor

@MainActor
final class ImportLogTests: XCTestCase {
    private func tempDir() -> URL {
        let u = FileManager.default.temporaryDirectory.appendingPathComponent("importlog-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }
    private func event(_ msg: String) -> ImportEvent {
        ImportEvent(query: "q", shaderID: "id", fetchSource: .webView, httpStatus: 200,
                    stage: .converted, outcome: .success, message: msg, responseSnippet: nil, warningCount: 0)
    }

    func test_recordPersistsAndReloads() {
        let dir = tempDir()
        let log = ImportLog(directory: dir)
        log.record(event("first"))
        let reloaded = ImportLog(directory: dir)
        XCTAssertEqual(reloaded.events.count, 1)
        XCTAssertEqual(reloaded.events.first?.message, "first")
    }
    func test_noDedup_keepsRepeatedAttempts() {
        let log = ImportLog(directory: tempDir())
        log.record(event("same"))
        log.record(event("same"))
        XCTAssertEqual(log.events.count, 2)
    }
    func test_capAt200() {
        let log = ImportLog(directory: tempDir())
        for i in 0..<250 { log.record(event("e\(i)")) }
        XCTAssertEqual(log.events.count, 200)
        XCTAssertEqual(log.events.last?.message, "e249")
    }
    func test_clearEmptiesAndPersists() {
        let dir = tempDir()
        let log = ImportLog(directory: dir)
        log.record(event("x"))
        log.clear()
        XCTAssertTrue(log.events.isEmpty)
        XCTAssertTrue(ImportLog(directory: dir).events.isEmpty)
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `… -only-testing:TrueISFEditorTests/ImportLogTests …`
Expected: FAIL — `cannot find 'ImportLog' in scope`.

- [ ] **Step 3: Implement `ImportLog`** (clone of CrashLog, no de-dup, cap 200)

```swift
import Foundation
import Combine

/// Persistent, in-memory-mirrored log of Shadertoy import attempts. Singleton because
/// `AppModel.convert()` records into one process-wide log surfaced by the Import Log window.
@MainActor
final class ImportLog: ObservableObject {
    static let shared = ImportLog()

    @Published private(set) var events: [ImportEvent] = []

    private let maxEvents = 200
    let fileURL: URL

    /// `directory` override for tests; defaults to ~/Library/Logs/TrueISFEditor.
    init(directory: URL? = nil) {
        let dir = directory ?? FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs/TrueISFEditor")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.fileURL = dir.appendingPathComponent("import-log.json")
        load()
    }

    /// No de-dup: distinct attempts are individually meaningful (unlike per-keystroke compile spam).
    func record(_ event: ImportEvent) {
        events.append(event)
        if events.count > maxEvents { events.removeFirst(events.count - maxEvents) }
        persist()
    }

    func clear() { events.removeAll(); persist() }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? Self.decoder.decode([ImportEvent].self, from: data) else { return }
        events = decoded
    }
    private func persist() {
        guard let data = try? Self.encoder.encode(events) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
    private static let encoder: JSONEncoder = {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; e.outputFormatting = [.prettyPrinted]; return e
    }()
    private static let decoder: JSONDecoder = {
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d
    }()
}
```

- [ ] **Step 4: Run to verify it passes** — same `-only-testing:TrueISFEditorTests/ImportLogTests`. Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add App/TrueISFEditor/ImportLog.swift App/TrueISFEditorTests/ImportLogTests.swift
git commit -m "feat(import-log): persistent ImportLog store"
```

---

### Task 3: Record events from `AppModel.convert()` + expose latest

**Files:**
- Modify: `App/TrueISFEditor/AppModel.swift` (the `convert()` method, ~lines 61-103, and add a `@Published var lastImport: ImportEvent?`)

- [ ] **Step 1: Add the published property** near the other `@Published` declarations:

```swift
    /// The most recent import attempt, for the inline summary in the import sheet.
    @Published var lastImport: ImportEvent?
```

- [ ] **Step 2: Add a private recording helper** to `AppModel`:

```swift
    private func recordImport(stage: ImportEvent.Stage, outcome: ImportEvent.Outcome,
                              id: String?, source: ImportEvent.FetchSource,
                              httpStatus: Int?, snippet: String?, warnings: Int) {
        let event = ImportEvent(query: urlText, shaderID: id, fetchSource: source,
                                httpStatus: httpStatus, stage: stage, outcome: outcome,
                                message: statusMessage, responseSnippet: snippet, warningCount: warnings)
        lastImport = event
        ImportLog.shared.record(event)
    }
```

- [ ] **Step 3: Call it on every path of `convert()`.** The existing method sets `statusMessage` in each branch; record AFTER setting it so `message` matches. Concretely:
  - After the `guard let id = ShadertoyURL.shaderID(...)` failure (before `return`): `recordImport(stage: .urlInvalid, outcome: .error, id: nil, source: .webView, httpStatus: nil, snippet: nil, warnings: 0)`
  - In the success path (after `statusMessage` is set): `recordImport(stage: .converted, outcome: w.isEmpty ? .success : .warning, id: id, source: strategy == .api ? .api : .webView, httpStatus: webFetcher.lastResponseStatus == -1 ? nil : webFetcher.lastResponseStatus, snippet: nil, warnings: w.count)`
  - In `catch ShadertoyInternalParserError.malformed(let detail)`: `recordImport(stage: .fetched, outcome: .error, id: id, source: .webView, httpStatus: webFetcher.lastResponseStatus == -1 ? nil : webFetcher.lastResponseStatus, snippet: String(webFetcher.lastResponseBody.prefix(300)), warnings: 0)`
  - In every other `catch` branch (api not-accessible/http/decoding, webFetch http/noData/challenge, internalParser.shaderNotFound, generic): `recordImport(stage: .fetched, outcome: .error, id: id, source: strategy == .api ? .api : .webView, httpStatus: webFetcher.lastResponseStatus == -1 ? nil : webFetcher.lastResponseStatus, snippet: nil, warnings: 0)`

  NOTE: `webFetcher` is `private lazy`; reading `lastResponseStatus`/`lastResponseBody` is safe (defaults `-1`/`"(none)"` when the API path was used). Map `-1` → `nil`. For the API path use `httpStatus: nil`.

- [ ] **Step 4: Build the app target**

Run: `xcodebuild build -project App/TrueISFEditor.xcodeproj -scheme TrueISFEditor -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/trueisfeditor-ddata ARCHS=arm64 ONLY_ACTIVE_ARCH=YES`
Expected: `BUILD SUCCEEDED`. (Recording logic itself is exercised by the pure ImportEvent tests; the wiring is verified by build + on-device.)

- [ ] **Step 5: Commit**

```bash
git add App/TrueISFEditor/AppModel.swift
git commit -m "feat(import-log): record an ImportEvent on every convert() path"
```

---

### Task 4: `Import Log` window + menu button

**Files:**
- Create: `App/TrueISFEditor/Views/ImportLogView.swift`
- Modify: `App/TrueISFEditor/TrueISFEditorApp.swift` (add `Window("Import Log", id: "import-log")` next to the crash-log window ~line 167; add `ImportLogMenuButton()` in the `CommandGroup(after: .windowArrangement)` next to `CrashLogMenuButton()` ~line 160)

- [ ] **Step 1: Create `ImportLogView.swift`** (mirrors CrashLogView)

```swift
import SwiftUI
import AppKit

struct ImportLogView: View {
    @ObservedObject private var log = ImportLog.shared

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Import Log").font(.headline)
                Spacer()
                Button("Reveal Log") { NSWorkspace.shared.activateFileViewerSelecting([log.fileURL]) }
                Button("Clear") { log.clear() }
            }
            .padding(8)
            Divider()
            if log.events.isEmpty {
                Spacer(); Text("No imports recorded").foregroundStyle(.secondary); Spacer()
            } else {
                List(log.events.reversed()) { ImportRow(event: $0) }
            }
        }
        .frame(minWidth: 480, minHeight: 360)
    }
}

private struct ImportRow: View {
    let event: ImportEvent
    @State private var expanded = false

    private var icon: String {
        switch event.outcome { case .success: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"; case .error: return "xmark.octagon.fill" }
    }
    private var tint: Color {
        switch event.outcome { case .success: return .green; case .warning: return .orange; case .error: return .red }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Image(systemName: icon).foregroundStyle(tint)
                Text(event.query).font(.callout).bold().lineLimit(1)
                Spacer()
                Text(event.timestamp, style: .time).font(.caption2).foregroundStyle(.secondary)
            }
            Text(event.message).font(.caption).foregroundStyle(.secondary).lineLimit(expanded ? nil : 2)
            DisclosureGroup("Details", isExpanded: $expanded) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Source: \(event.fetchSource.rawValue)\(event.httpStatus.map { " · HTTP \($0)" } ?? "") · stage: \(event.stage.rawValue)")
                        .font(.caption2).foregroundStyle(.secondary)
                    if let snip = event.responseSnippet, !snip.isEmpty {
                        Text("Response (first 300):").font(.caption2).bold()
                        Text(snip).font(.system(.caption2, design: .monospaced)).textSelection(.enabled)
                    }
                }
            }
            .font(.caption2)
        }
        .padding(.vertical, 2)
    }
}

/// Opens the Import Log window from a menu command (mirrors CrashLogMenuButton).
struct ImportLogMenuButton: View {
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Button("Import Log") { openWindow(id: "import-log") }
            .keyboardShortcut("i", modifiers: [.command, .shift])
    }
}
```

- [ ] **Step 2: Wire the window** in `TrueISFEditorApp.body`, immediately after the `Window("Crash Log", id: "crash-log") { CrashLogView() }`:

```swift
        Window("Import Log", id: "import-log") {
            ImportLogView()
        }
```

- [ ] **Step 3: Wire the menu button** in the `CommandGroup(after: .windowArrangement)` block, right after `CrashLogMenuButton()`:

```swift
                ImportLogMenuButton()
```

- [ ] **Step 4: Build** — same `xcodebuild build …` command. Expected: `BUILD SUCCEEDED`.

- [ ] **Step 5: Commit**

```bash
git add App/TrueISFEditor/Views/ImportLogView.swift App/TrueISFEditor/TrueISFEditorApp.swift
git commit -m "feat(import-log): Import Log window + menu (⇧⌘I)"
```

---

### Task 5: Inline summary in the import sheet

**Files:**
- Modify: `App/TrueISFEditor/Views/ShadertoyImportSheet.swift` (the `statusMessage` block ~lines 76-77)

- [ ] **Step 1: Add the inline summary** right after the existing `statusMessage` Text. Replace:

```swift
                if !model.statusMessage.isEmpty {
                    Text(model.statusMessage).font(.caption).foregroundStyle(.secondary)
                }
```

with:

```swift
                if !model.statusMessage.isEmpty {
                    Text(model.statusMessage).font(.caption).foregroundStyle(.secondary)
                }
                if let last = model.lastImport {
                    HStack(spacing: 6) {
                        Text(last.summaryLine)
                            .font(.caption).bold()
                            .foregroundStyle(last.outcome == .error ? .red : .green)
                        Button("Import Log ▸") { openWindow(id: "import-log") }
                            .buttonStyle(.link).font(.caption)
                    }
                }
```

- [ ] **Step 2: Add the environment accessor** to `ShadertoyImportSheet` (near its other properties):

```swift
    @Environment(\.openWindow) private var openWindow
```

- [ ] **Step 3: Build** — same `xcodebuild build …`. Expected: `BUILD SUCCEEDED`.

- [ ] **Step 4: Commit**

```bash
git add App/TrueISFEditor/Views/ShadertoyImportSheet.swift
git commit -m "feat(import-log): inline import outcome + link in the import sheet"
```

---

### Task 6: Full verification + stage

- [ ] **Step 1: Run the full app test suite**

Run: `xcodebuild test -project App/TrueISFEditor.xcodeproj -scheme TrueISFEditor -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/trueisfeditor-ddata ARCHS=arm64 ONLY_ACTIVE_ARCH=YES`
Expected: `TEST SUCCEEDED`, 156 + new tests, 0 failures.

- [ ] **Step 2: Stage the canonical app**

```bash
osascript -e 'quit app "TrueISFEditor"' 2>/dev/null || true
rm -rf "$HOME/Applications/TrueISFEditor.app"
ditto /tmp/trueisfeditor-ddata/Build/Products/Debug/TrueISFEditor.app "$HOME/Applications/TrueISFEditor.app"
```

- [ ] **Step 3: On-device verify** — open TrueISFEditor, import `N323DD` (expect `✓ Converted (1 warning)` inline + a row in ⇧⌘I Import Log), and import a bogus ID like `ZZZZZZ` (expect `✗ …` inline + an error row with stage/HTTP detail). Client Success live UX review tracked as deferred.

## Self-Review notes
- Spec coverage: ImportEvent (T1), ImportLog persist/cap/clear/no-dedup (T2), recording all paths (T3), window (T4), inline summary (T5), tests + on-device (T1/T2/T6). All spec sections covered.
- Types consistent: `ImportEvent` fields/enums identical across T1–T5; `ImportLog.record/clear/events/fileURL` used consistently; window id `"import-log"` matches in T4 + T5.
- No placeholders: all steps carry real code/commands.
