# ISF Remix Studio — Module 2 (Studio UI + Thumbnails) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the Remix Studio window — Layout A (parents bay + controls, center gallery, right rail) — that drives the Module 1 generation core into a live breed → stream → pick → mutate/promote → step-back loop, with streaming Metal thumbnails and "open winner in editor."

**Architecture:** A new `@MainActor ObservableObject` `RemixStudioModel` owns the studio state (parent node ids, mode, steer, batch size, current batch, lineage graph, favorites, round history) and drives the Module 1 `RemixGenerator`. Parents are real `RemixNode`s in the lineage graph from the first round (external sources become round‑0 "seed" nodes), so children record true parent ids. **Compile validation and the thumbnail are the same object:** each child card hosts a small `MetalPreviewController` (a `PreviewEngine`); its `compileValid`/`compileError` both render the live thumbnail and report back to the model (`markCompileResult`), which sets the node's `.compiled`/`.failed` status. A model-side cap (`livePreviewIDs`) decides which cards animate vs. freeze a frame. Parent sourcing (library file / current editor / pasted Shadertoy link / pasted ISF) is resolved by an injectable `RemixParentResolver`. "Open in editor" calls the existing `EditorViewModel.loadImported` via a closure injected at the App level.

**Tech Stack:** Swift / SwiftUI / Swift Concurrency / Metal (`MetalPreviewController`), XCTest in the `TrueISFEditorTests` target (xcodegen + xcodebuild). macOS 13.0 deployment target.

**Spec:** `docs/superpowers/specs/2026-06-11-isf-remix-studio-design.md`

**Branch:** `isf-remix-studio` (Module 1 already merged into this branch).

**Reuse (exact, verified seams):**
- Module 1: `RemixNode` (`id, isfSource, parents:[String], mode:RemixMode, steer, directive, round, status:.generating/.compiled/.failed(String)`), `RemixMode` (`.crossover/.mutate`), `RemixGenerator(makeProvider:model:maxConcurrent:)` with `func generate(parents:[String], mode:RemixMode, steer:String, batchSize:Int, round:Int, onChild:@escaping (RemixNode)->Void) async`, `RemixLineage` (`insert/node(_:)/children(of:)/isFavorite/toggleFavorite`, `order`, `nodes`, `favorites`).
- Generation provider factory (copy from `ShaderAssistViewModel.makeProvider()`): `ClaudeCodeRunner(binary: ClaudeCodeRunner.locateBinary(override:))` / `CodexRunner(binary: CodexRunner.locateBinary(override:))`, selected by `AssistProviderKind(rawValue: UserDefaults.standard.string(forKey:"assistProvider") ?? "") ?? .claude`; model from `UserDefaults` keys `"assistClaudeModel"` (default `"sonnet"`) / `"assistCodexModel"`.
- Preview: `MetalPreviewController` — `init()`, `func load(isf:String)`, `@Published private(set) var compileValid:Bool`, `@Published private(set) var compileError:String?`, `var nsView:NSView`, `@discardableResult func renderOnce() -> MTLTexture?`. Conforms to `PreviewEngine`. Test double: `FakePreviewEngine` in `TrueISFEditorTests/Fakes/FakePreviewEngine.swift` with `simulateCompile(valid:error:line:inputs:)`.
- Importer: `ShadertoyURL.shaderID(from:String) -> String?`, `FetchStrategy.select(hasKey:Bool) -> FetchStrategy` (`.api`/`.webView`), `ShadertoyClient(key:String).fetchShader(id:String) async throws -> Shader`, `WebKitShaderFetcher().fetchShader(id:String) async throws -> Shader`, `ISFConverter.convert(_ shader:Shader) -> (ISFDocument,[ConversionWarning])`, `ISFDocument.fileText:String`.
- Library: `LibraryModel.filtered(query:String) -> [LibraryEntry]`, `LibraryEntry.url:URL` / `.name:String`; read source via `try String(contentsOf: entry.url, encoding: .utf8)`.
- Editor: `EditorViewModel.loadImported(isf:String, warnings:[ConversionWarning], suggestedName:String)`.
- App: `TrueISFEditorApp.swift` — scenes (`WindowGroup`, `Window("Crash Log", id:"crash-log")`, `Settings`), `.commands { CommandGroup(...) }`, `CrashLogMenuButton` is the existing "open a named window from a menu item" pattern to mirror.

**House rules:** every new app source file must be added to the **explicit** `TrueISFEditorTests` source list in `App/project.yml`, then `cd App && xcodegen generate`. Test classes that touch `@MainActor` types are `@MainActor final class … : XCTestCase`. Build/verify command (warm `ddata-review`):

```
cd App && xcodegen generate && xcodebuild -project TrueISFEditor.xcodeproj -scheme TrueISFEditor -derivedDataPath ./ddata-review -destination 'platform=macOS,arch=arm64' ARCHS=arm64 ONLY_ACTIVE_ARCH=YES test 2>&1 | grep -E 'error:|Executed [0-9]+ tests, with|\*\* TEST'
```

---

## File structure

| File | Responsibility | Tested by |
|---|---|---|
| `App/TrueISFEditor/Remix/RemixStudioModel.swift` | Studio state + lifecycle; drives `RemixGenerator`; lineage/favorites/promote/step-back; compile-result + live-preview cap | unit (FakeProvider) |
| `App/TrueISFEditor/Remix/RemixParentResolver.swift` | `ParentSpec` → ISF string (library/current/Shadertoy-link/pasted), injectable fetch | unit (fakes) |
| `App/TrueISFEditor/Remix/RemixThumbnailView.swift` | `NSViewRepresentable` Metal thumbnail per child; reports compile result; freeze when not animating | build + on-device |
| `App/TrueISFEditor/Remix/RemixStudioView.swift` | Layout A SwiftUI: parents bay + controls, gallery, right rail, child cards | build + on-device |
| `App/TrueISFEditor/Remix/RemixMenuButton.swift` | Menu button that opens the `remix-studio` window via `@Environment(\.openWindow)` | build |
| `App/TrueISFEditor/TrueISFEditorApp.swift` (modify) | Add `Window("ISF Remix Studio", id:"remix-studio")`, `@StateObject` model, command, open-in-editor wiring | build + on-device |

---

### Task 1: `RemixStudioModel` — state + generation lifecycle + lineage/favorites/promote/step-back

**Files:**
- Create: `App/TrueISFEditor/Remix/RemixStudioModel.swift`
- Test: `App/TrueISFEditorTests/RemixStudioModelTests.swift`
- Modify: `App/project.yml` (add `TrueISFEditor/Remix/RemixStudioModel.swift` to the `TrueISFEditorTests` source list), then `cd App && xcodegen generate`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import TrueISFEditor

/// Canonical fake provider (same shape as RemixGeneratorTests). Returns a scripted ISF per call or throws.
@MainActor
private final class FakeProvider: AssistProvider {
    var scripts: [Result<String, Error>]
    private var i = 0
    init(_ scripts: [Result<String, Error>]) { self.scripts = scripts }
    func run(prompt: String, system: String, model: String?, timeout: TimeInterval,
             onEvent: @escaping @Sendable (String) -> Void) async throws -> String {
        defer { i += 1 }
        switch scripts[min(i, scripts.count - 1)] {
        case .success(let s): return s
        case .failure(let e): throw e
        }
    }
}

@MainActor
final class RemixStudioModelTests: XCTestCase {
    private let isf = "/*{ \"ISFVSN\":\"2.0\" }*/\nvoid main(){ gl_FragColor=vec4(1.0); }"
    private func model(_ scripts: [Result<String, Error>]) -> RemixStudioModel {
        let provider = FakeProvider(scripts)
        return RemixStudioModel(generator: RemixGenerator(makeProvider: { provider }, model: nil))
    }

    func test_setParent_createsSeedNode_inLineage() {
        let m = model([.success(isf)])
        m.setParent(.a, isf: "/*{A}*/ a")
        XCTAssertNotNil(m.parentAID)
        XCTAssertEqual(m.lineage.node(m.parentAID!)?.isfSource, "/*{A}*/ a")
        XCTAssertEqual(m.lineage.node(m.parentAID!)?.round, 0)
    }

    func test_canGenerate_requires_twoParents_forCrossover_oneForMutate() {
        let m = model([.success(isf)])
        m.mode = .crossover
        m.setParent(.a, isf: "a")
        XCTAssertFalse(m.canGenerate)          // crossover needs both
        m.setParent(.b, isf: "b")
        XCTAssertTrue(m.canGenerate)
        m.mode = .mutate                       // mutate needs only A
        let m2 = model([.success(isf)]); m2.mode = .mutate; m2.setParent(.a, isf: "a")
        XCTAssertTrue(m2.canGenerate)
    }

    func test_generate_streamsChildren_recordsParentIDs_andInsertsIntoLineage() async {
        let m = model([.success("```glsl\n\(isf)\n```")])
        m.mode = .crossover
        m.setParent(.a, isf: "/*{A}*/"); m.setParent(.b, isf: "/*{B}*/")
        m.batchSize = 4
        await m.generate()
        XCTAssertEqual(m.currentBatch.count, 4)
        let pids = [m.parentAID!, m.parentBID!]
        XCTAssertTrue(m.currentBatch.allSatisfy { $0.parents == pids })
        XCTAssertTrue(m.currentBatch.allSatisfy { m.lineage.node($0.id) != nil })
        XCTAssertFalse(m.isGenerating)
    }

    func test_markCompileResult_updatesStatus_inBatchAndLineage() async {
        let m = model([.success("```glsl\n\(isf)\n```")])
        m.mode = .mutate; m.setParent(.a, isf: "/*{A}*/"); m.batchSize = 1
        await m.generate()
        let id = m.currentBatch[0].id
        m.markCompileResult(id: id, valid: false, error: "bad GLSL")
        XCTAssertEqual(m.currentBatch[0].status, .failed("bad GLSL"))
        XCTAssertEqual(m.lineage.node(id)?.status, .failed("bad GLSL"))
        m.markCompileResult(id: id, valid: true, error: nil)
        XCTAssertEqual(m.currentBatch[0].status, .compiled)
    }

    func test_favorites_toggle_throughModel() async {
        let m = model([.success("```glsl\n\(isf)\n```")])
        m.mode = .mutate; m.setParent(.a, isf: "/*{A}*/"); m.batchSize = 1
        await m.generate()
        let id = m.currentBatch[0].id
        m.toggleFavorite(id)
        XCTAssertTrue(m.lineage.isFavorite(id))
        XCTAssertEqual(m.favoriteNodes.map(\.id), [id])
    }

    func test_promoteToParent_setsParentToExistingNode_noNewSeed() async {
        let m = model([.success("```glsl\n\(isf)\n```")])
        m.mode = .mutate; m.setParent(.a, isf: "/*{A}*/"); m.batchSize = 1
        await m.generate()
        let childID = m.currentBatch[0].id
        m.promoteToParent(.a, nodeID: childID)
        XCTAssertEqual(m.parentAID, childID)
    }

    func test_stepBack_restoresPreviousParents() async {
        let m = model([.success("```glsl\n\(isf)\n```")])
        m.mode = .mutate; m.setParent(.a, isf: "/*{A}*/"); m.batchSize = 1
        await m.generate()                       // round 1, parent = seed
        let seedID = m.parentAID
        let childID = m.currentBatch[0].id
        m.promoteToParent(.a, nodeID: childID)
        await m.generate()                       // round 2, parent = child
        XCTAssertEqual(m.parentAID, childID)
        m.stepBack()
        XCTAssertEqual(m.parentAID, seedID)      // restored to the round-1 config
    }
}
```

- [ ] **Step 2: Run test to verify it fails** — Expected: FAIL, `RemixStudioModel` undefined.

- [ ] **Step 3: Write minimal implementation**

```swift
import Foundation
import Combine

/// Which parent slot a source/child fills.
enum ParentSlot { case a, b }

/// Owns the Remix Studio state and drives the Module 1 generator. Parents are real lineage nodes
/// (external sources become round-0 "seed" nodes) so children record true parent ids from round 1.
@MainActor
final class RemixStudioModel: ObservableObject {
    @Published private(set) var parentAID: String?
    @Published private(set) var parentBID: String?
    @Published var mode: RemixMode = .crossover
    @Published var steer: String = ""
    @Published var batchSize: Int = 5
    @Published var maxLivePreviews: Int = 4
    @Published private(set) var currentBatch: [RemixNode] = []
    @Published private(set) var lineage = RemixLineage()
    @Published private(set) var isGenerating = false

    private let generator: RemixGenerator
    private var round = 0
    private var seedCounter = 0
    private var history: [(String?, String?)] = []   // parent (A,B) configs for step-back

    init(generator: RemixGenerator) { self.generator = generator }

    // MARK: derived

    var parentIDs: [String] { [parentAID, parentBID].compactMap { $0 } }
    var parentSources: [String] { parentIDs.compactMap { lineage.node($0)?.isfSource } }
    var canGenerate: Bool {
        guard !isGenerating else { return false }
        let needed = (mode == .crossover) ? 2 : 1
        return parentSources.count >= needed
    }
    var favoriteNodes: [RemixNode] {
        lineage.order.compactMap { lineage.node($0) }.filter { lineage.isFavorite($0.id) }
    }

    // MARK: parents

    /// Set a parent from an external ISF source: creates a round-0 seed node and points the slot at it.
    func setParent(_ slot: ParentSlot, isf: String) {
        let id = "seed-\(seedCounter)"; seedCounter += 1
        let node = RemixNode(id: id, isfSource: isf, parents: [], mode: .crossover,
                             steer: "", directive: "seed", round: 0, status: .compiled)
        lineage.insert(node)
        switch slot { case .a: parentAID = id; case .b: parentBID = id }
    }

    /// Promote an existing lineage node (a child) to a parent slot — no new seed.
    func promoteToParent(_ slot: ParentSlot, nodeID: String) {
        switch slot { case .a: parentAID = nodeID; case .b: parentBID = nodeID }
    }

    func clearParent(_ slot: ParentSlot) {
        switch slot { case .a: parentAID = nil; case .b: parentBID = nil }
    }

    // MARK: generation

    func generate() async {
        guard canGenerate else { return }
        history.append((parentAID, parentBID))
        round += 1
        let r = round
        let pids = parentIDs
        isGenerating = true
        currentBatch = []
        await generator.generate(parents: parentSources, mode: mode, steer: steer,
                                 batchSize: batchSize, round: r) { [weak self] node in
            guard let self else { return }
            var n = node
            n.parents = pids                 // record true parent ids in the lineage graph
            self.currentBatch.append(n)
            self.lineage.insert(n)
        }
        isGenerating = false
    }

    /// Card preview reports the real compile outcome; update status in the batch and the lineage.
    func markCompileResult(id: String, valid: Bool, error: String?) {
        guard var node = lineage.node(id) else { return }
        node.status = valid ? .compiled : .failed(error ?? "compile failed")
        lineage.insert(node)
        if let i = currentBatch.firstIndex(where: { $0.id == id }) { currentBatch[i] = node }
    }

    // MARK: selection

    func toggleFavorite(_ id: String) { lineage.toggleFavorite(id) }

    func stepBack() {
        guard let prev = history.popLast() else { return }
        (parentAID, parentBID) = prev
    }
}
```

- [ ] **Step 4: Run test to verify it passes** — Expected: PASS (8 tests). Note: `RemixGenerator`'s text-extracted status is `.compiled`; `markCompileResult` is what re-confirms via the real engine.

- [ ] **Step 5: Commit**

```bash
git add App/project.yml App/TrueISFEditor/Remix/RemixStudioModel.swift App/TrueISFEditorTests/RemixStudioModelTests.swift
git commit -m "feat(remix): RemixStudioModel — batch lifecycle, lineage, favorites, promote, step-back"
```

---

### Task 2: Live-preview cap (which cards animate vs. freeze)

**Files:**
- Modify: `App/TrueISFEditor/Remix/RemixStudioModel.swift`
- Test: add to `App/TrueISFEditorTests/RemixStudioModelTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
    func test_livePreviewCap_favoritesAlwaysAnimate_othersFillUpToCap() async {
        let m = model([.success("```glsl\n\(isf)\n```")])
        m.mode = .mutate; m.setParent(.a, isf: "/*{A}*/")
        m.batchSize = 6; m.maxLivePreviews = 4
        await m.generate()
        for n in m.currentBatch { m.markCompileResult(id: n.id, valid: true, error: nil) }
        // No favorites yet: exactly maxLivePreviews animate.
        XCTAssertEqual(m.currentBatch.filter { m.shouldAnimate($0.id) }.count, 4)
        // Favorite two of the frozen ones -> both animate even though we're over the cap.
        let frozen = m.currentBatch.filter { !m.shouldAnimate($0.id) }
        m.toggleFavorite(frozen[0].id); m.toggleFavorite(frozen[1].id)
        XCTAssertTrue(m.shouldAnimate(frozen[0].id))
        XCTAssertTrue(m.shouldAnimate(frozen[1].id))
        XCTAssertGreaterThanOrEqual(m.currentBatch.filter { m.shouldAnimate($0.id) }.count, 4)
    }

    func test_failedChildren_neverAnimate() async {
        let m = model([.success("I couldn't.")])   // no ISF -> generator marks .failed
        m.mode = .mutate; m.setParent(.a, isf: "/*{A}*/"); m.batchSize = 2; m.maxLivePreviews = 4
        await m.generate()
        XCTAssertTrue(m.currentBatch.allSatisfy { !m.shouldAnimate($0.id) })
    }
```

- [ ] **Step 2: Run test to verify it fails** — Expected: FAIL, `shouldAnimate` undefined.

- [ ] **Step 3: Write minimal implementation** — add to `RemixStudioModel`:

```swift
    // MARK: live-preview cap (performance)

    /// Favorites always animate; remaining slots up to `maxLivePreviews` go to the most-recent
    /// compiled, non-favorite children. Everything else freezes a single frame. Failed children
    /// never animate.
    func livePreviewIDs() -> Set<String> {
        let compiled = currentBatch.filter { $0.status == .compiled }
        var live = Set(compiled.filter { lineage.isFavorite($0.id) }.map(\.id))
        let slots = max(0, maxLivePreviews - live.count)
        let fillers = compiled.filter { !live.contains($0.id) }.suffix(slots)
        live.formUnion(fillers.map(\.id))
        return live
    }

    func shouldAnimate(_ id: String) -> Bool { livePreviewIDs().contains(id) }
```

- [ ] **Step 4: Run test to verify it passes** — Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add App/TrueISFEditor/Remix/RemixStudioModel.swift App/TrueISFEditorTests/RemixStudioModelTests.swift
git commit -m "feat(remix): live-preview cap (favorites stay live, others freeze)"
```

---

### Task 3: `RemixParentResolver` — source a parent ISF string

**Files:**
- Create: `App/TrueISFEditor/Remix/RemixParentResolver.swift`
- Test: `App/TrueISFEditorTests/RemixParentResolverTests.swift`
- Modify: `App/project.yml` (add `TrueISFEditor/Remix/RemixParentResolver.swift` to test target), `cd App && xcodegen generate`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import TrueISFEditor

@MainActor
final class RemixParentResolverTests: XCTestCase {
    func test_pastedISF_returnsVerbatim() async throws {
        let r = RemixParentResolver(currentEditorSource: { nil }, fetchShadertoy: { _ in "X" })
        let out = try await r.resolve(.pastedISF("/*{}*/ body"))
        XCTAssertEqual(out, "/*{}*/ body")
    }
    func test_currentEditor_usesClosure_orThrows() async throws {
        let r = RemixParentResolver(currentEditorSource: { "/*{E}*/" }, fetchShadertoy: { _ in "X" })
        XCTAssertEqual(try await r.resolve(.currentEditor), "/*{E}*/")
        let empty = RemixParentResolver(currentEditorSource: { nil }, fetchShadertoy: { _ in "X" })
        do { _ = try await empty.resolve(.currentEditor); XCTFail("expected throw") }
        catch RemixParentError.noEditorShader {} catch { XCTFail("wrong error: \(error)") }
    }
    func test_libraryFile_readsFromDisk() async throws {
        let dir = FileManager.default.temporaryDirectory
        let url = dir.appendingPathComponent("remix-test-\(UUID().uuidString).fs")
        try "/*{L}*/ lib".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }
        let r = RemixParentResolver(currentEditorSource: { nil }, fetchShadertoy: { _ in "X" })
        XCTAssertEqual(try await r.resolve(.libraryFile(url)), "/*{L}*/ lib")
    }
    func test_shadertoyLink_delegatesToFetchClosure() async throws {
        let r = RemixParentResolver(currentEditorSource: { nil },
                                    fetchShadertoy: { url in "ISF for \(url)" })
        XCTAssertEqual(try await r.resolve(.shadertoyLink("https://shadertoy.com/view/abc")),
                       "ISF for https://shadertoy.com/view/abc")
    }
}
```

- [ ] **Step 2: Run test to verify it fails** — Expected: FAIL, `RemixParentResolver` undefined.

- [ ] **Step 3: Write minimal implementation**

```swift
import Foundation

/// Where a parent shader comes from.
enum ParentSpec: Equatable {
    case pastedISF(String)
    case libraryFile(URL)
    case shadertoyLink(String)   // pasted URL or bare id
    case currentEditor
}

enum RemixParentError: Error, Equatable {
    case noEditorShader
    case badShadertoyURL
}

/// Resolves a `ParentSpec` to an ISF source string. Network/editor access is injected so the
/// non-network paths are unit-testable and the Shadertoy path can be faked.
struct RemixParentResolver {
    /// Returns the main editor's current shader source, or nil if there isn't one.
    var currentEditorSource: () -> String?
    /// Fetches + converts a Shadertoy URL/id to ISF source. Default wires the real importer chain.
    var fetchShadertoy: (String) async throws -> String

    func resolve(_ spec: ParentSpec) async throws -> String {
        switch spec {
        case .pastedISF(let s):
            return s
        case .currentEditor:
            guard let s = currentEditorSource(), !s.isEmpty else { throw RemixParentError.noEditorShader }
            return s
        case .libraryFile(let url):
            return try String(contentsOf: url, encoding: .utf8)
        case .shadertoyLink(let urlText):
            return try await fetchShadertoy(urlText)
        }
    }

    /// The real importer chain used in production (exercised on-device, faked in unit tests).
    /// `apiKey` reads the user's Shadertoy API key (empty -> WebKit fetch path).
    static func liveFetch(apiKey: @escaping () -> String) -> (String) async throws -> String {
        { urlText in
            guard let id = ShadertoyURL.shaderID(from: urlText) else { throw RemixParentError.badShadertoyURL }
            let key = apiKey()
            let shader: Shader
            switch FetchStrategy.select(hasKey: !key.isEmpty) {
            case .api:     shader = try await ShadertoyClient(key: key).fetchShader(id: id)
            case .webView: shader = try await WebKitShaderFetcher().fetchShader(id: id)
            }
            let (doc, _) = ISFConverter.convert(shader)
            return doc.fileText
        }
    }
}
```

> **Verified seam:** `WebKitShaderFetcher` has an argument-free `init()` (WebKitShaderFetcher.swift:33), and `FetchStrategy.select(hasKey:)` returns `.api`/`.webView` — `liveFetch` as written is correct. This default runs only on-device (units use the injected fake).

- [ ] **Step 4: Run test to verify it passes** — Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add App/project.yml App/TrueISFEditor/Remix/RemixParentResolver.swift App/TrueISFEditorTests/RemixParentResolverTests.swift
git commit -m "feat(remix): parent resolver (library/current/shadertoy-link/pasted -> ISF)"
```

---

### Task 4: `RemixThumbnailView` — Metal thumbnail per child + compile-result callback

This task is a SwiftUI/Metal view; it is **build-verified here and behavior-verified at the Task 7 on-device gate** (Metal rendering can't be unit-tested). No XCTest step.

**Files:**
- Create: `App/TrueISFEditor/Remix/RemixThumbnailView.swift`
- Modify: `App/project.yml` only if a later test needs it (not now — UI file, app target picks it up via the `TrueISFEditor` directory path).

- [ ] **Step 1: Implement the view**

```swift
import SwiftUI
import AppKit
import Combine

/// A small Metal preview of one child ISF. Hosts a `MetalPreviewController`, loads the source once,
/// and reports the compile outcome back via `onCompile`. When `animating` is false it renders a single
/// frozen frame instead of running continuously (performance cap from the studio model).
struct RemixThumbnailView: NSViewRepresentable {
    let isf: String
    let animating: Bool
    /// Called on the main actor with (valid, errorMessage) once the engine finishes compiling.
    let onCompile: (Bool, String?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onCompile: onCompile) }

    func makeNSView(context: Context) -> NSView {
        let controller = context.coordinator.controller
        controller.load(isf: isf)
        context.coordinator.observe(controller)
        return controller.nsView
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        let controller = context.coordinator.controller
        if context.coordinator.loadedISF != isf {
            context.coordinator.loadedISF = isf
            controller.load(isf: isf)
        }
        // Freeze when not animating: render one frame and stop driving updates.
        if !animating { controller.renderOnce() }
    }

    @MainActor
    final class Coordinator {
        let controller = MetalPreviewController()
        let onCompile: (Bool, String?) -> Void
        var loadedISF: String?
        private var bag = Set<AnyCancellable>()
        private var reported = false

        init(onCompile: @escaping (Bool, String?) -> Void) { self.onCompile = onCompile }

        func observe(_ c: MetalPreviewController) {
            // Fire once when compile resolves (valid true, or an error string appears).
            c.$compileValid
                .combineLatest(c.$compileError)
                .sink { [weak self] valid, error in
                    guard let self, !self.reported else { return }
                    if valid { self.reported = true; self.onCompile(true, nil) }
                    else if let error, !error.isEmpty { self.reported = true; self.onCompile(false, error) }
                }
                .store(in: &bag)
        }
    }
}
```

- [ ] **Step 2: Verify it builds** — run the build/verify command from the header. Expected: `** TEST SUCCEEDED **` (no new tests; this confirms it compiles into the app + test targets).

- [ ] **Step 3: Commit**

```bash
git add App/TrueISFEditor/Remix/RemixThumbnailView.swift
git commit -m "feat(remix): Metal thumbnail view (compile-result callback + freeze)"
```

---

### Task 5: `RemixStudioView` — Layout A

Build-verified here; behavior at the Task 7 on-device gate. No XCTest step.

**Files:**
- Create: `App/TrueISFEditor/Remix/RemixStudioView.swift`

- [ ] **Step 1: Implement the view**

```swift
import SwiftUI

/// Layout A: parents bay + controls on top, a streaming child gallery in the center, and a right rail
/// (favorites + lineage breadcrumb). Entirely driven by `RemixStudioModel`.
struct RemixStudioView: View {
    @ObservedObject var model: RemixStudioModel
    /// Resolves a chosen parent source to ISF text (injected at the App level).
    let resolver: RemixParentResolver
    /// Opens a winning child in the main editor (wired to EditorViewModel.loadImported).
    let openInEditor: (String) -> Void
    /// Library entries for the parent picker.
    let libraryEntries: [LibraryEntry]

    @State private var pasteText = ""
    @State private var linkText = ""
    @State private var resolveError: String?

    var body: some View {
        VStack(spacing: 0) {
            parentsBay
            Divider()
            gallery
        }
        .frame(minWidth: 900, minHeight: 600)
        .toolbar { } // reserved
    }

    // MARK: parents bay + controls

    private var parentsBay: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 16) {
                parentSlot("Parent A", id: model.parentAID, slot: .a)
                if model.mode == .crossover { parentSlot("Parent B", id: model.parentBID, slot: .b) }
                Divider().frame(height: 80)
                controls
            }
            sourceRow
            if let resolveError { Text(resolveError).font(.caption).foregroundStyle(.red) }
        }
        .padding(12)
    }

    private func parentSlot(_ title: String, id: String?, slot: ParentSlot) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            ZStack {
                RoundedRectangle(cornerRadius: 8).strokeBorder(.quaternary)
                if let id, let node = model.lineage.node(id) {
                    RemixThumbnailView(isf: node.isfSource, animating: true) { _, _ in }
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    Text("Empty").font(.caption2).foregroundStyle(.tertiary)
                }
            }
            .frame(width: 120, height: 80)
            if id != nil {
                Button("Clear") { model.clearParent(slot) }.font(.caption2).buttonStyle(.link)
            }
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Mode", selection: $model.mode) {
                Text("Crossover").tag(RemixMode.crossover)
                Text("Mutate").tag(RemixMode.mutate)
            }.pickerStyle(.segmented).frame(width: 220)
            TextField("Steer (optional): e.g. 'wavy, neon'", text: $model.steer).frame(width: 280)
            HStack {
                Stepper("Batch: \(model.batchSize)", value: $model.batchSize, in: 1...8).frame(width: 160)
                Button {
                    Task { await model.generate() }
                } label: { Label("Generate", systemImage: "bolt.fill") }
                .keyboardShortcut(.return, modifiers: [])
                .disabled(!model.canGenerate)
            }
            if model.isGenerating { ProgressView().controlSize(.small) }
        }
    }

    private var sourceRow: some View {
        HStack(spacing: 8) {
            Menu("Add from Library") {
                ForEach(libraryEntries) { entry in
                    Button(entry.name) { resolveParent(.libraryFile(entry.url)) }
                }
            }.frame(width: 160)
            Button("Use Current Editor") { resolveParent(.currentEditor) }
            TextField("Shadertoy link…", text: $linkText, onCommit: {
                guard !linkText.isEmpty else { return }
                resolveParent(.shadertoyLink(linkText)); linkText = ""
            }).frame(width: 220)
            TextField("Paste ISF…", text: $pasteText, onCommit: {
                guard !pasteText.isEmpty else { return }
                resolveParent(.pastedISF(pasteText)); pasteText = ""
            }).frame(width: 220)
        }
    }

    /// Fills the first empty slot (A, then B for crossover) with the resolved source.
    private func resolveParent(_ spec: ParentSpec) {
        let slot: ParentSlot = (model.parentAID == nil) ? .a
            : (model.mode == .crossover && model.parentBID == nil) ? .b : .a
        Task {
            do {
                let isf = try await resolver.resolve(spec)
                model.setParent(slot, isf: isf)
                resolveError = nil
            } catch { resolveError = "Couldn't load parent: \(error)" }
        }
    }

    // MARK: gallery

    private let columns = [GridItem(.adaptive(minimum: 180), spacing: 12)]

    private var gallery: some View {
        HStack(spacing: 0) {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(model.currentBatch) { node in childCard(node) }
                }.padding(12)
            }
            Divider()
            rightRail.frame(width: 220)
        }
    }

    private func childCard(_ node: RemixNode) -> some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(.black.opacity(0.05))
                switch node.status {
                case .generating:
                    ProgressView().controlSize(.small)
                case .failed(let msg):
                    VStack { Image(systemName: "exclamationmark.triangle"); Text(msg).font(.caption2).lineLimit(2) }
                        .foregroundStyle(.orange).padding(4)
                case .compiled:
                    RemixThumbnailView(isf: node.isfSource, animating: model.shouldAnimate(node.id)) { valid, err in
                        model.markCompileResult(id: node.id, valid: valid, error: err)
                    }.clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
            .frame(height: 130)
            HStack(spacing: 10) {
                Button { model.toggleFavorite(node.id) } label: {
                    Image(systemName: model.lineage.isFavorite(node.id) ? "star.fill" : "star")
                }.help("Favorite")
                Button { model.promoteToParent(.a, nodeID: node.id) } label: {
                    Image(systemName: "arrow.up.circle")
                }.help("Promote to Parent A")
                Button { openInEditor(node.isfSource) } label: {
                    Image(systemName: "square.and.pencil")
                }.help("Open in editor")
            }
            .buttonStyle(.borderless)
            Text(node.directive).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 10).fill(.background).shadow(radius: 1))
    }

    private var rightRail: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Favorites").font(.headline)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(model.favoriteNodes) { node in
                        HStack {
                            RemixThumbnailView(isf: node.isfSource, animating: true) { _, _ in }
                                .frame(width: 60, height: 40).clipShape(RoundedRectangle(cornerRadius: 4))
                            Button("Promote") { model.promoteToParent(.a, nodeID: node.id) }.font(.caption2)
                        }
                    }
                }
            }
            Divider()
            Button { model.stepBack() } label: { Label("Step Back", systemImage: "arrow.uturn.backward") }
            Text("Lineage: \(model.lineage.order.count) nodes").font(.caption2).foregroundStyle(.secondary)
        }
        .padding(10)
    }
}
```

- [ ] **Step 2: Verify it builds** — run the build/verify command. Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add App/TrueISFEditor/Remix/RemixStudioView.swift
git commit -m "feat(remix): Studio view (Layout A — parents bay, gallery, right rail)"
```

---

### Task 6: App integration — menu, window, open-in-editor wiring

Build-verified here; behavior at Task 7. No XCTest step.

**Files:**
- Create: `App/TrueISFEditor/Remix/RemixMenuButton.swift`
- Modify: `App/TrueISFEditor/TrueISFEditorApp.swift`

- [ ] **Step 1: Add the menu button** (mirrors the existing `CrashLogMenuButton` open-named-window pattern)

```swift
import SwiftUI

/// Opens the Remix Studio window from a menu command. Mirrors CrashLogMenuButton — a view is used
/// (rather than a bare command closure) so it can read `\.openWindow` from the environment.
struct RemixMenuButton: View {
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Button("Remix ISF…") { openWindow(id: "remix-studio") }
            .keyboardShortcut("r", modifiers: [.command, .shift])
    }
}
```

- [ ] **Step 2: Wire the scene + command + open-in-editor** in `TrueISFEditorApp.swift`

Add the studio model as a `@StateObject` near the existing ones:

```swift
    @StateObject private var remixModel = RemixStudioModel(
        generator: RemixGenerator(
            makeProvider: {
                switch AssistProviderKind(rawValue: UserDefaults.standard.string(forKey: "assistProvider") ?? "") ?? .claude {
                case .claude:
                    return ClaudeCodeRunner(binary: ClaudeCodeRunner.locateBinary(
                        override: UserDefaults.standard.string(forKey: "claudeBinaryPath")))
                case .codex:
                    return CodexRunner(binary: CodexRunner.locateBinary(
                        override: UserDefaults.standard.string(forKey: "codexBinaryPath")))
                }
            },
            model: UserDefaults.standard.string(forKey: "assistClaudeModel") ?? "sonnet"
        )
    )
```

> Verified keys (EditorScreen.swift:9, ShaderAssistViewModel.swift:41): Claude override = `"claudeBinaryPath"`, Codex = `"codexBinaryPath"` — both as written above. `makeProvider` lives `private` inside `ShaderAssistViewModel`; if this closure proves worth sharing, extract a small `AssistProviderFactory` both call (DRY) — optional, not required for Module 2.

Add the command (inside the existing `.commands { }`, after `.newItem`):

```swift
            CommandGroup(after: .newItem) { RemixMenuButton() }
```

Add the window scene (alongside the `Window("Crash Log", …)`), wiring the resolver and open-in-editor to the existing `vm`/`library`:

```swift
        Window("ISF Remix Studio", id: "remix-studio") {
            RemixStudioView(
                model: remixModel,
                resolver: RemixParentResolver(
                    currentEditorSource: { vm.file.source },   // verified: EditorViewModel.file.source is canonical
                    fetchShadertoy: RemixParentResolver.liveFetch(
                        apiKey: { UserDefaults.standard.string(forKey: "shadertoyAPIKey") ?? "" })
                ),
                openInEditor: { isf in
                    vm.loadImported(isf: isf, warnings: [], suggestedName: "Remixed shader")
                },
                libraryEntries: library.filtered(query: "")
            )
        }
```

> All accessors above are verified against the codebase (`vm.file.source`, `"claudeBinaryPath"`/`"codexBinaryPath"`, `WebKitShaderFetcher()`); no open unknowns remain for this task.

- [ ] **Step 3: Verify it builds** — run the build/verify command. Expected: `** TEST SUCCEEDED **`, full suite still green.

- [ ] **Step 4: Commit**

```bash
git add App/TrueISFEditor/Remix/RemixMenuButton.swift App/TrueISFEditor/TrueISFEditorApp.swift
git commit -m "feat(remix): app integration — Remix menu, studio window, open-in-editor"
```

---

### Task 7: Full verification + on-device gate

- [ ] **Step 1: Full suite green**

Run the build/verify command. Expected: `** TEST SUCCEEDED **`, App suite up by ~14 tests (Task 1: 8, Task 2: 2, Task 3: 4), 0 failures.

- [ ] **Step 2: Staged binary embeds the new code**

```bash
strings App/ddata-review/Build/Products/Debug/TrueISFEditor.app/Contents/MacOS/TrueISFEditor.debug.dylib | grep -c 'ISF Remix Studio'
```
Expected: ≥ 1.

- [ ] **Step 3: Build a runnable .app and launch it**

```bash
cd App && xcodebuild -project TrueISFEditor.xcodeproj -scheme TrueISFEditor -derivedDataPath ./ddata-review -destination 'platform=macOS,arch=arm64' ARCHS=arm64 ONLY_ACTIVE_ARCH=YES build 2>&1 | tail -3
open ./ddata-review/Build/Products/Debug/TrueISFEditor.app
```

- [ ] **Step 4: On-device gate (manual — this is the render-heavy part the spec flags).** Verify in the running app:
  1. **⌘⇧R** (or File ▸ Remix ISF…) opens the Studio window.
  2. Add Parent A from the library and Parent B from another library entry; both thumbnails render.
  3. Mode = Crossover, batch = 5, **Generate** → cards stream in: ⚙ → live thumbnail (or ⚠ on a failed compile). Partial failures don't block the rest.
  4. **Thumbnail performance:** with 5+ live cards, the window stays responsive. Favorite 2 cards, scroll — confirm only favorites + up to `maxLivePreviews` animate; the rest are frozen frames (no fan-spin / beachball).
  5. **★** favorite persists to the right rail; **⬆ promote** a child to Parent A; Generate again → new round breeds from it.
  6. **Step Back** restores the previous parents.
  7. **↗ open-in-editor** routes the child into the main editor with code + preview + sliders.
  8. Paste a **Shadertoy link** as a parent → it fetches/converts and fills a slot.

- [ ] **Step 5: Security gate (CSO trifecta).** Module 2 introduces the live path: untrusted parent shader source → LLM → editor write. Before merge, run a CSO defensive review (per CLAUDE.md): confirm the untrusted-parent guard in `RemixPrompt.system()` is intact end-to-end, that pasted/linked parent source is never executed except through the existing sandboxed Metal compile, and that nothing from a parent or child is written outside the user-initiated editor load. Verdict SHIP / FIX-FIRST.

- [ ] **Step 6:** After gates pass, use `superpowers:finishing-a-development-branch` to decide merge of the whole `isf-remix-studio` branch (Modules 1 + 2) to `master`.

---

## What Module 2 deliberately does NOT do (→ Phase 2)

- No lineage **tree GUI** in the right rail (v1 = favorites shelf + step-back; the graph is already recorded for the tree to read later).
- No **auto-repair** of failed children (v1 = ⚠ + manual retry / re-generate).
- No persistence of a remix session across app launches.
- No per-card model/provider override (uses the global ShaderAssist provider/model settings).
