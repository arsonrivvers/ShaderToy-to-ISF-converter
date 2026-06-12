# Remix Lineage Tree GUI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the Remix Studio right rail's flat Favorites list with an indented lineage tree — snapshot swatches per node, crossover children nested once under Parent A with a ⚭ secondary-parent badge, select→action-strip interaction, ★-only filter — reading the graph `RemixLineage` already records.

**Architecture:** A pure `RemixTreeBuilder.flatten` turns the lineage DAG into `[RemixTreeRow]` (id, depth, secondaryParentID); each node renders exactly once under `parents.first`, so traversal is a true tree. `RemixStudioModel` gains `selectedNodeID` + a `snapshots: [String: CGImage]` cache filled by a new `onSnapshot` hook on `RemixThumbnailView` (one `renderOnce()` frame → `TextureSnapshot` → CGImage at compile time). A new `RemixLineageTreeView` (260px) renders rows in a `LazyVStack` and hosts the rail's single live Metal engine in the selected node's action strip.

**Tech Stack:** Swift / SwiftUI / Metal / Core Image (`CIImage(mtlTexture:)`), XCTest in `TrueISFEditorTests` (xcodegen + xcodebuild). macOS 13.0 target.

**Spec:** `docs/superpowers/specs/2026-06-12-remix-lineage-tree-design.md`

**Branch:** `isf-remix-studio` (continues Modules 1+2; HEAD has the spec commit).

**House rules (same as Module 2):** every new app source file that unit tests touch must be added to the **explicit** `TrueISFEditorTests` source list in `App/project.yml` (after the existing `TrueISFEditor/Remix/...` entries around line 76), then `cd App && xcodegen generate`. Test classes touching `@MainActor` types are `@MainActor final class … : XCTestCase`. Build/verify command (warm `ddata-review`):

```bash
cd App && xcodegen generate && xcodebuild -project TrueISFEditor.xcodeproj -scheme TrueISFEditor -derivedDataPath ./ddata-review -destination 'platform=macOS,arch=arm64' ARCHS=arm64 ONLY_ACTIVE_ARCH=YES test 2>&1 | grep -E 'error:|Executed [0-9]+ tests, with|\*\* TEST'
```

(For a build-only check, replace `test` with `build` and expect `** BUILD SUCCEEDED **`.)

---

## File structure

| File | Responsibility | Tested by |
|---|---|---|
| `App/TrueISFEditor/Remix/RemixTreeBuilder.swift` (new) | Pure DAG→rows flatten: roots/nesting/crossover-dedup/hide-failed/collapse/★-filter | unit |
| `App/TrueISFEditor/Remix/RemixNode.swift` (modify) | `label: String?` field for seed display names | unit |
| `App/TrueISFEditor/Remix/RemixStudioModel.swift` (modify) | `selectedNodeID`, `snapshots` cache, `treeRows`, `setParent(label:)` | unit |
| `App/TrueISFEditor/Remix/TextureSnapshot.swift` (new) | `MTLTexture` → small `CGImage` via Core Image (handles float formats) | unit |
| `App/TrueISFEditor/Remix/RemixThumbnailView.swift` (modify) | additive `onSnapshot` hook fired at first successful compile | build + on-device |
| `App/TrueISFEditor/Remix/RemixLineageTreeView.swift` (new) | The rail: header + ★ filter, tree rows, action strip, Step Back, hints | build + on-device |
| `App/TrueISFEditor/Remix/RemixStudioView.swift` (modify) | swap `rightRail` → `RemixLineageTreeView` (260px); wire `onSnapshot` + seed labels | build + on-device |
| `App/TrueISFEditorTests/RemixTreeBuilderTests.swift` (new) | flatten behaviors | — |
| `App/TrueISFEditorTests/TextureSnapshotTests.swift` (new) | texture→CGImage conversion + scaling + nil fallback | — |
| `App/TrueISFEditorTests/RemixStudioModelTests.swift` (modify) | selection, snapshot store, treeRows pass-through, seed label | — |

---

### Task 1: `RemixTreeBuilder.flatten` (pure, TDD)

**Files:**
- Create: `App/TrueISFEditor/Remix/RemixTreeBuilder.swift`
- Create: `App/TrueISFEditorTests/RemixTreeBuilderTests.swift`
- Modify: `App/project.yml` (test-target source list)

- [ ] **Step 1: Write the failing tests**

`App/TrueISFEditorTests/RemixTreeBuilderTests.swift`:

```swift
import XCTest
@testable import TrueISFEditor

final class RemixTreeBuilderTests: XCTestCase {
    /// Build a node quickly. Defaults: compiled, no parents.
    private func node(_ id: String, parents: [String] = [],
                      status: RemixNode.Status = .compiled, label: String? = nil) -> RemixNode {
        RemixNode(id: id, isfSource: "/*{}*/", parents: parents, mode: .crossover,
                  steer: "", directive: "d", round: 0, status: status, label: label)
    }
    private func lineage(_ nodes: [RemixNode], favorites: [String] = []) -> RemixLineage {
        var l = RemixLineage()
        nodes.forEach { l.insert($0) }
        favorites.forEach { l.toggleFavorite($0) }
        return l
    }

    func test_roots_areParentlessNodes_inInsertionOrder_atDepth0() {
        let l = lineage([node("seed-0"), node("seed-1")])
        let rows = RemixTreeBuilder.flatten(l, collapsed: [], favoritesOnly: false)
        XCTAssertEqual(rows.map(\.id), ["seed-0", "seed-1"])
        XCTAssertEqual(rows.map(\.depth), [0, 0])
    }

    func test_children_nestUnderFirstParent_depthIncrements() {
        let l = lineage([node("s"), node("r1-0", parents: ["s"]), node("r2-0", parents: ["r1-0"])])
        let rows = RemixTreeBuilder.flatten(l, collapsed: [], favoritesOnly: false)
        XCTAssertEqual(rows.map(\.id), ["s", "r1-0", "r2-0"])
        XCTAssertEqual(rows.map(\.depth), [0, 1, 2])
    }

    func test_crossoverChild_rendersOnce_underParentA_withSecondaryBadge() {
        let l = lineage([node("a"), node("b"), node("r1-0", parents: ["a", "b"])])
        let rows = RemixTreeBuilder.flatten(l, collapsed: [], favoritesOnly: false)
        XCTAssertEqual(rows.map(\.id), ["a", "r1-0", "b"])   // child under a, NOT duplicated under b
        XCTAssertEqual(rows[1].depth, 1)
        XCTAssertEqual(rows[1].secondaryParentID, "b")
        XCTAssertNil(rows[0].secondaryParentID)
    }

    func test_failed_andGenerating_areHidden() {
        let l = lineage([node("s"),
                         node("bad", parents: ["s"], status: .failed("x")),
                         node("pending", parents: ["s"], status: .generating),
                         node("ok", parents: ["s"])])
        let rows = RemixTreeBuilder.flatten(l, collapsed: [], favoritesOnly: false)
        XCTAssertEqual(rows.map(\.id), ["s", "ok"])
    }

    func test_collapse_prunesAllDescendants() {
        let l = lineage([node("s"), node("r1-0", parents: ["s"]),
                         node("r2-0", parents: ["r1-0"]), node("r1-1", parents: ["s"])])
        let rows = RemixTreeBuilder.flatten(l, collapsed: ["r1-0"], favoritesOnly: false)
        XCTAssertEqual(rows.map(\.id), ["s", "r1-0", "r1-1"])   // r2-0 pruned, r1-0 itself stays
        let rows2 = RemixTreeBuilder.flatten(l, collapsed: ["s"], favoritesOnly: false)
        XCTAssertEqual(rows2.map(\.id), ["s"])                  // whole subtree pruned
    }

    func test_favoritesOnly_returnsFlatStarredList_inInsertionOrder() {
        let l = lineage([node("s"), node("r1-0", parents: ["s"]), node("r1-1", parents: ["s"])],
                        favorites: ["r1-1", "s"])
        let rows = RemixTreeBuilder.flatten(l, collapsed: [], favoritesOnly: true)
        XCTAssertEqual(rows.map(\.id), ["s", "r1-1"])           // insertion order, not toggle order
        XCTAssertEqual(rows.map(\.depth), [0, 0])
    }

    func test_flatten_isStable_acrossCalls() {
        let l = lineage([node("s"), node("r1-0", parents: ["s"])])
        XCTAssertEqual(RemixTreeBuilder.flatten(l, collapsed: [], favoritesOnly: false),
                       RemixTreeBuilder.flatten(l, collapsed: [], favoritesOnly: false))
    }
}
```

Note: these tests pass `label:` to the `RemixNode` initializer — that parameter is added in this task (it is a one-line, defaulted field; bundling it here keeps the test helper final).

- [ ] **Step 2: Add the `label` field to `RemixNode`**

`App/TrueISFEditor/Remix/RemixNode.swift` — add one line at the end of the struct:

```swift
struct RemixNode: Identifiable, Equatable {
    enum Status: Equatable { case generating, compiled, failed(String) }
    let id: String
    var isfSource: String
    var parents: [String]
    var mode: RemixMode
    var steer: String
    var directive: String
    var round: Int
    var status: Status = .generating
    var label: String? = nil          // display name for seeds (library name / "editor" / "pasted")
}
```

Defaulted last ⇒ every existing memberwise-init call site compiles unchanged.

- [ ] **Step 3: Register the new files in `App/project.yml` and regenerate**

In the `TrueISFEditorTests` target's explicit source list (after `- TrueISFEditor/Remix/RemixParentResolver.swift`), add:

```yaml
      - TrueISFEditor/Remix/RemixTreeBuilder.swift
```

Then run: `cd App && xcodegen generate`

- [ ] **Step 4: Run tests to verify they fail**

Create an EMPTY `App/TrueISFEditor/Remix/RemixTreeBuilder.swift` first (so the target compiles the file reference), then run the house build/test command.
Expected: compile errors — `RemixTreeBuilder` / `RemixTreeRow` not found. (A compile failure of the new test file is the failing state for type-level TDD in Swift.)

- [ ] **Step 5: Implement `RemixTreeBuilder`**

`App/TrueISFEditor/Remix/RemixTreeBuilder.swift`:

```swift
import Foundation

/// One row of the flattened lineage tree (the right rail renders these in order).
struct RemixTreeRow: Identifiable, Equatable {
    let id: String                  // node id
    let depth: Int                  // indent level
    let secondaryParentID: String?  // parents[1] for crossover children → ⚭ badge
}

/// Flattens the lineage DAG into displayable rows. Each node renders exactly once, under
/// `parents.first`, so traversal is a true tree even though crossover children have two parents
/// (the second parent surfaces as `secondaryParentID`). Failed and still-generating nodes are
/// hidden — the gallery owns in-flight/failed visibility; the tree is the album of what worked.
enum RemixTreeBuilder {
    static func flatten(_ lineage: RemixLineage,
                        collapsed: Set<String>,
                        favoritesOnly: Bool) -> [RemixTreeRow] {
        let visible = lineage.order.compactMap { lineage.node($0) }.filter { $0.status == .compiled }
        if favoritesOnly {
            return visible.filter { lineage.isFavorite($0.id) }
                .map { RemixTreeRow(id: $0.id, depth: 0, secondaryParentID: secondary($0)) }
        }
        var rows: [RemixTreeRow] = []
        func emit(_ node: RemixNode, depth: Int) {
            rows.append(RemixTreeRow(id: node.id, depth: depth, secondaryParentID: secondary(node)))
            guard !collapsed.contains(node.id) else { return }
            for child in visible where child.parents.first == node.id { emit(child, depth: depth + 1) }
        }
        for root in visible where root.parents.isEmpty { emit(root, depth: 0) }
        return rows
    }

    /// True when a node has at least one compiled child that RENDERS under it (parents.first) —
    /// drives the view's disclosure triangle. Children where this node is only the secondary
    /// parent render elsewhere and don't count.
    static func hasRenderedChildren(_ lineage: RemixLineage, id: String) -> Bool {
        lineage.order.compactMap { lineage.node($0) }
            .contains { $0.parents.first == id && $0.status == .compiled }
    }

    private static func secondary(_ n: RemixNode) -> String? {
        n.parents.count >= 2 ? n.parents[1] : nil
    }
}
```

- [ ] **Step 6: Add a disclosure test, run the suite, verify green**

Append to `RemixTreeBuilderTests.swift`:

```swift
    func test_hasRenderedChildren_countsOnlyFirstParentCompiledChildren() {
        let l = lineage([node("a"), node("b"),
                         node("r1-0", parents: ["a", "b"]),
                         node("bad", parents: ["b"], status: .failed("x"))])
        XCTAssertTrue(RemixTreeBuilder.hasRenderedChildren(l, id: "a"))
        XCTAssertFalse(RemixTreeBuilder.hasRenderedChildren(l, id: "b"))  // secondary + failed don't count
    }
```

Run the house test command. Expected: `Executed 107 tests, with 0 failures` (99 existing + 8 new).

- [ ] **Step 7: Commit**

```bash
git add App/TrueISFEditor/Remix/RemixTreeBuilder.swift App/TrueISFEditor/Remix/RemixNode.swift App/TrueISFEditorTests/RemixTreeBuilderTests.swift App/project.yml
git commit -m "feat(remix): RemixTreeBuilder — flatten lineage DAG to tree rows (+ RemixNode.label)

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 2: Model additions — selection, snapshots, treeRows, seed labels (TDD)

**Files:**
- Modify: `App/TrueISFEditor/Remix/RemixStudioModel.swift`
- Modify: `App/TrueISFEditorTests/RemixStudioModelTests.swift`

- [ ] **Step 1: Write the failing tests**

Append to `RemixStudioModelTests.swift` (inside the existing `@MainActor final class RemixStudioModelTests`):

```swift
    func test_setParent_recordsLabel_onSeedNode() {
        let m = model([.success(isf)])
        m.setParent(.a, isf: "a", label: "plasma")
        XCTAssertEqual(m.lineage.node(m.parentAID!)?.label, "plasma")
        m.setParent(.b, isf: "b")                       // label optional, defaults nil
        XCTAssertNil(m.lineage.node(m.parentBID!)?.label)
    }

    func test_selectedNodeID_defaultsNil_andPublishesSelection() {
        let m = model([.success(isf)])
        XCTAssertNil(m.selectedNodeID)
        m.selectedNodeID = "r1-0"
        XCTAssertEqual(m.selectedNodeID, "r1-0")
    }

    func test_storeSnapshot_cachesByID() {
        let m = model([.success(isf)])
        let ctx = CGContext(data: nil, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let img = ctx.makeImage()!
        m.storeSnapshot(id: "r1-0", image: img)
        XCTAssertNotNil(m.snapshots["r1-0"])
        XCTAssertNil(m.snapshots["r9-9"])
    }

    func test_treeRows_passesThrough_toBuilder() {
        let m = model([.success(isf)])
        m.setParent(.a, isf: "a", label: "plasma")
        let rows = m.treeRows(collapsed: [], favoritesOnly: false)
        XCTAssertEqual(rows.map(\.id), [m.parentAID!])
        XCTAssertEqual(m.treeRows(collapsed: [], favoritesOnly: true), [])  // nothing starred yet
    }
```

Also add `import CoreGraphics` at the top of the test file if not already present.

- [ ] **Step 2: Run tests to verify they fail**

Run the house test command. Expected: compile errors — `setParent(_:isf:label:)`, `selectedNodeID`, `storeSnapshot`, `treeRows` not found.

- [ ] **Step 3: Implement the model additions**

`App/TrueISFEditor/Remix/RemixStudioModel.swift`:

Add `import CoreGraphics` under `import Combine`.

Add two published properties after `@Published private(set) var transcript: [String] = []`:

```swift
    /// Lineage-tree selection; the right rail's action strip renders while non-nil.
    @Published var selectedNodeID: String?
    /// One static frame per node id, captured at compile time — the tree's row swatches.
    @Published private(set) var snapshots: [String: CGImage] = [:]
```

Replace the `setParent` function with:

```swift
    /// Set a parent from an external ISF source: creates a round-0 seed node and points the slot at it.
    /// `label` is the human display name for the tree (library entry name / "editor" / "pasted").
    func setParent(_ slot: ParentSlot, isf: String, label: String? = nil) {
        let id = "seed-\(seedCounter)"; seedCounter += 1
        let node = RemixNode(id: id, isfSource: isf, parents: [], mode: .crossover,
                             steer: "", directive: "seed", round: 0, status: .compiled, label: label)
        lineage.insert(node)
        switch slot { case .a: parentAID = id; case .b: parentBID = id }
    }
```

Add after `func toggleFavorite`:

```swift
    func storeSnapshot(id: String, image: CGImage) { snapshots[id] = image }

    func treeRows(collapsed: Set<String>, favoritesOnly: Bool) -> [RemixTreeRow] {
        RemixTreeBuilder.flatten(lineage, collapsed: collapsed, favoritesOnly: favoritesOnly)
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run the house test command. Expected: `Executed 111 tests, with 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add App/TrueISFEditor/Remix/RemixStudioModel.swift App/TrueISFEditorTests/RemixStudioModelTests.swift
git commit -m "feat(remix): model selection, snapshot cache, treeRows, seed labels

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 3: `TextureSnapshot` — MTLTexture → small CGImage (TDD)

**Files:**
- Create: `App/TrueISFEditor/Remix/TextureSnapshot.swift`
- Create: `App/TrueISFEditorTests/TextureSnapshotTests.swift`
- Modify: `App/project.yml` (test-target source list)

- [ ] **Step 1: Write the failing tests**

`App/TrueISFEditorTests/TextureSnapshotTests.swift`:

```swift
import XCTest
import Metal
@testable import TrueISFEditor

final class TextureSnapshotTests: XCTestCase {
    private func makeTexture(_ device: MTLDevice, width: Int, height: Int,
                             format: MTLPixelFormat = .bgra8Unorm) -> MTLTexture? {
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: format,
                                                         width: width, height: height, mipmapped: false)
        d.usage = [.shaderRead]
        d.storageMode = .shared
        return device.makeTexture(descriptor: d)
    }

    func test_bgra8Texture_convertsToCGImage_atFullSize() throws {
        guard let device = MTLCreateSystemDefaultDevice(),
              let tex = makeTexture(device, width: 8, height: 6) else { throw XCTSkip("no Metal") }
        var pixels = [UInt8](repeating: 0, count: 8 * 6 * 4)
        for i in stride(from: 0, to: pixels.count, by: 4) { pixels[i + 2] = 255; pixels[i + 3] = 255 } // red, opaque
        tex.replace(region: MTLRegionMake2D(0, 0, 8, 6), mipmapLevel: 0,
                    withBytes: pixels, bytesPerRow: 8 * 4)
        let img = TextureSnapshot.cgImage(from: tex, maxDimension: 64)
        XCTAssertNotNil(img)
        XCTAssertEqual(img?.width, 8)
        XCTAssertEqual(img?.height, 6)
    }

    func test_largeTexture_downscalesToMaxDimension() throws {
        guard let device = MTLCreateSystemDefaultDevice(),
              let tex = makeTexture(device, width: 128, height: 64) else { throw XCTSkip("no Metal") }
        let img = TextureSnapshot.cgImage(from: tex, maxDimension: 64)
        XCTAssertEqual(img?.width, 64)
        XCTAssertEqual(img?.height, 32)
    }

    func test_floatTexture_converts() throws {
        guard let device = MTLCreateSystemDefaultDevice(),
              let tex = makeTexture(device, width: 4, height: 4, format: .rgba16Float)
        else { throw XCTSkip("no Metal") }
        XCTAssertNotNil(TextureSnapshot.cgImage(from: tex, maxDimension: 64))
    }

    func test_unsupportedFormat_returnsNil_notCrash() throws {
        guard let device = MTLCreateSystemDefaultDevice(),
              let tex = makeTexture(device, width: 4, height: 4, format: .depth32Float)
        else { throw XCTSkip("no Metal") }
        XCTAssertNil(TextureSnapshot.cgImage(from: tex, maxDimension: 64))
    }
}
```

- [ ] **Step 2: Register files in `App/project.yml` and regenerate**

Add to the `TrueISFEditorTests` explicit source list (next to the other Remix entries):

```yaml
      - TrueISFEditor/Remix/TextureSnapshot.swift
```

Create an EMPTY `App/TrueISFEditor/Remix/TextureSnapshot.swift`, then `cd App && xcodegen generate`.

- [ ] **Step 3: Run tests to verify they fail**

Run the house test command. Expected: compile error — `TextureSnapshot` not found.

- [ ] **Step 4: Implement `TextureSnapshot`**

`App/TrueISFEditor/Remix/TextureSnapshot.swift`:

```swift
import CoreGraphics
import CoreImage
import Metal

/// Converts a Metal texture into a small CGImage for lineage-tree row swatches. Core Image
/// handles the engine's output formats uniformly (bgra8 and float alike); unsupported formats
/// (e.g. depth) return nil and callers fall back to a glyph — never an error, never a crash.
enum TextureSnapshot {
    private static let context = CIContext(options: [.cacheIntermediates: false])

    static func cgImage(from texture: MTLTexture, maxDimension: CGFloat = 64) -> CGImage? {
        guard let ci = CIImage(mtlTexture: texture,
                               options: [.colorSpace: CGColorSpaceCreateDeviceRGB()])
        else { return nil }
        // Metal textures are top-left origin; CIImage is bottom-left — flip vertically.
        let flipped = ci.transformed(by: CGAffineTransform(scaleX: 1, y: -1)
            .translatedBy(x: 0, y: -ci.extent.height))
        let scale = min(1, maxDimension / max(flipped.extent.width, flipped.extent.height))
        let scaled = flipped.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        return context.createCGImage(scaled, from: scaled.extent)
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run the house test command. Expected: `Executed 115 tests, with 0 failures`.

If `test_unsupportedFormat_returnsNil_notCrash` fails because `CIImage(mtlTexture:)` accepts depth textures on this OS, change the implementation to gate explicitly instead:

```swift
        let supported: Set<MTLPixelFormat> = [.bgra8Unorm, .bgra8Unorm_srgb, .rgba8Unorm,
                                              .rgba8Unorm_srgb, .rgba16Float, .rgba32Float]
        guard supported.contains(texture.pixelFormat) else { return nil }
```

(insert before the `CIImage` guard; keep the test as written).

- [ ] **Step 6: Commit**

```bash
git add App/TrueISFEditor/Remix/TextureSnapshot.swift App/TrueISFEditorTests/TextureSnapshotTests.swift App/project.yml
git commit -m "feat(remix): TextureSnapshot — MTLTexture to swatch CGImage via Core Image

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 4: `RemixThumbnailView.onSnapshot` hook

**Files:**
- Modify: `App/TrueISFEditor/Remix/RemixThumbnailView.swift`

No unit test (needs a real Metal compile) — build-verified here, exercised on-device at the gate.

- [ ] **Step 1: Add the hook**

In `RemixThumbnailView`, add the new property ABOVE `onCompile` (ordering matters: `onCompile` must stay the LAST closure parameter so existing trailing-closure call sites — `RemixThumbnailView(isf:animating:) { valid, err in … }` — still bind to it):

```swift
struct RemixThumbnailView: NSViewRepresentable {
    let isf: String
    let animating: Bool
    /// Optional: receives one downscaled CGImage frame at first successful compile (tree swatches).
    var onSnapshot: ((CGImage) -> Void)? = nil
    /// Called on the main actor with (valid, errorMessage) once the engine finishes compiling.
    let onCompile: (Bool, String?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onCompile: onCompile, onSnapshot: onSnapshot) }
```

Update `Coordinator`:

```swift
    @MainActor
    final class Coordinator {
        let controller = MetalPreviewController()
        let onCompile: (Bool, String?) -> Void
        let onSnapshot: ((CGImage) -> Void)?
        var loadedISF: String?
        private var bag = Set<AnyCancellable>()
        private var reported = false

        init(onCompile: @escaping (Bool, String?) -> Void, onSnapshot: ((CGImage) -> Void)?) {
            self.onCompile = onCompile
            self.onSnapshot = onSnapshot
        }

        func observe(_ c: MetalPreviewController) {
            // Fire once when compile resolves (valid true, or an error string appears).
            c.$compileValid
                .combineLatest(c.$compileError)
                .sink { [weak self] valid, error in
                    guard let self, !self.reported else { return }
                    if valid {
                        self.reported = true
                        self.onCompile(true, nil)
                        if let onSnapshot = self.onSnapshot,
                           let tex = self.controller.renderOnce(),
                           let img = TextureSnapshot.cgImage(from: tex) {
                            onSnapshot(img)
                        }
                    } else if let error, !error.isEmpty {
                        self.reported = true
                        self.onCompile(false, error)
                    }
                }
                .store(in: &bag)
        }
    }
```

Also add `import CoreGraphics` to the file's imports.

- [ ] **Step 2: Build-verify (existing call sites must compile unchanged)**

Run the house command with `build` instead of `test`. Expected: `** BUILD SUCCEEDED **` with zero changes to `RemixStudioView.swift` — proving the parameter is additive.

- [ ] **Step 3: Run the full test suite**

Run the house test command. Expected: `Executed 115 tests, with 0 failures`.

- [ ] **Step 4: Commit**

```bash
git add App/TrueISFEditor/Remix/RemixThumbnailView.swift
git commit -m "feat(remix): additive onSnapshot hook on RemixThumbnailView (one frame at compile)

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 5: `RemixLineageTreeView` + studio integration

**Files:**
- Create: `App/TrueISFEditor/Remix/RemixLineageTreeView.swift`
- Modify: `App/TrueISFEditor/Remix/RemixStudioView.swift`

Build-verified; interaction joins the on-device gate. (View file is NOT added to the test target — views aren't unit-tested in this project.)

- [ ] **Step 1: Create the tree view**

`App/TrueISFEditor/Remix/RemixLineageTreeView.swift`:

```swift
import SwiftUI

/// The right rail: flattened lineage tree (snapshot swatches, ⚭ secondary-parent badges, ★),
/// a [★ only] filter, the selected node's action strip — the rail's ONLY live Metal engine —
/// and Step Back. Rows come from RemixTreeBuilder via model.treeRows.
struct RemixLineageTreeView: View {
    @ObservedObject var model: RemixStudioModel
    let openInEditor: (String) -> Void

    @State private var collapsed: Set<String> = []
    @State private var favoritesOnly = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            treeList
            if let id = model.selectedNodeID, let node = model.lineage.node(id) {
                Divider()
                actionStrip(node)
            }
            Divider()
            Button { model.stepBack() } label: { Label("Step Back", systemImage: "arrow.uturn.backward") }
            Text("Lineage: \(model.lineage.order.count) nodes").font(.caption2).foregroundStyle(.secondary)
        }
        .padding(10)
    }

    private var header: some View {
        HStack {
            Text("Lineage").font(.headline)
            Spacer()
            Toggle("★ only", isOn: $favoritesOnly)
                .toggleStyle(.button).font(.caption).controlSize(.small)
        }
    }

    private var treeList: some View {
        let rows = model.treeRows(collapsed: collapsed, favoritesOnly: favoritesOnly)
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                if rows.isEmpty {
                    Text(emptyHint)
                        .font(.caption).foregroundStyle(.tertiary)
                        .padding(.top, 8)
                } else {
                    ForEach(rows) { row in treeRow(row) }
                }
            }
        }
    }

    private var emptyHint: String {
        if model.lineage.order.isEmpty { return "Add parents and Generate — the family tree grows here." }
        if favoritesOnly { return "No favorites yet — ★ a child to pin it here." }
        return "No compiled shaders yet."
    }

    private func treeRow(_ row: RemixTreeRow) -> some View {
        let node = model.lineage.node(row.id)
        let isSelected = model.selectedNodeID == row.id
        return HStack(spacing: 4) {
            if RemixTreeBuilder.hasRenderedChildren(model.lineage, id: row.id) {
                Button {
                    if collapsed.contains(row.id) { collapsed.remove(row.id) }
                    else { collapsed.insert(row.id) }
                } label: {
                    Image(systemName: collapsed.contains(row.id) ? "chevron.right" : "chevron.down")
                }
                .buttonStyle(.borderless).font(.caption2).frame(width: 14)
            } else {
                Spacer().frame(width: 14)
            }
            swatch(row.id)
            Text(node?.label ?? row.id).font(.caption).lineLimit(1)
            if let sec = row.secondaryParentID, let secNode = model.lineage.node(sec) {
                Button { model.selectedNodeID = sec } label: {
                    Text("⚭\(secNode.label ?? sec)").font(.caption2)
                }
                .buttonStyle(.borderless).foregroundStyle(.secondary)
                .help("Second parent — click to select it")
            }
            if model.lineage.isFavorite(row.id) {
                Image(systemName: "star.fill").font(.caption2).foregroundStyle(.yellow)
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, CGFloat(row.depth) * 12)
        .padding(.vertical, 2).padding(.horizontal, 4)
        .background(RoundedRectangle(cornerRadius: 4)
            .fill(isSelected ? Color.accentColor.opacity(0.18) : Color.clear))
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { if let n = node { openInEditor(n.isfSource) } }
        .onTapGesture { model.selectedNodeID = row.id }
    }

    private func swatch(_ id: String) -> some View {
        Group {
            if let img = model.snapshots[id] {
                Image(decorative: img, scale: 1).resizable().aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: "photo").font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .frame(width: 24, height: 16)
        .clipShape(RoundedRectangle(cornerRadius: 3))
    }

    /// Compact actions for the selected node. Hosts the rail's only live Metal preview.
    private func actionStrip(_ node: RemixNode) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(node.label ?? node.id).font(.caption.bold()).lineLimit(1)
                Spacer()
                Button { model.selectedNodeID = nil } label: { Image(systemName: "xmark.circle") }
                    .buttonStyle(.borderless).help("Deselect")
            }
            RemixThumbnailView(isf: node.isfSource, animating: true,
                               onSnapshot: { img in model.storeSnapshot(id: node.id, image: img) }) { _, _ in }
                .frame(height: 90)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            Text(node.directive).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
            HStack(spacing: 10) {
                Button { model.promoteToParent(.a, nodeID: node.id) } label: {
                    Label("A", systemImage: "arrow.up.circle")
                }.help("Promote to Parent A")
                Button { model.promoteToParent(.b, nodeID: node.id) } label: {
                    Label("B", systemImage: "arrow.up.circle")
                }.help("Promote to Parent B")
                Button { model.toggleFavorite(node.id) } label: {
                    Image(systemName: model.lineage.isFavorite(node.id) ? "star.fill" : "star")
                }.help("Favorite")
                Button { openInEditor(node.isfSource) } label: {
                    Image(systemName: "square.and.pencil")
                }.help("Open in editor")
            }
            .buttonStyle(.borderless)
        }
    }
}
```

- [ ] **Step 2: Swap the rail into `RemixStudioView` and wire snapshots + labels**

In `App/TrueISFEditor/Remix/RemixStudioView.swift`:

(a) In `gallery`, replace `rightRail.frame(width: 220)` with:

```swift
            RemixLineageTreeView(model: model, openInEditor: openInEditor).frame(width: 260)
```

(b) DELETE the entire `private var rightRail: some View { … }` computed property (the old Favorites list, Step Back and node count now live in `RemixLineageTreeView`).

(c) In `childCard`, the `.compiled` case gains the snapshot hook:

```swift
                case .compiled:
                    RemixThumbnailView(isf: node.isfSource, animating: model.shouldAnimate(node.id),
                                       onSnapshot: { img in model.storeSnapshot(id: node.id, image: img) }) { valid, err in
                        model.markCompileResult(id: node.id, valid: valid, error: err)
                    }.clipShape(RoundedRectangle(cornerRadius: 8))
```

(d) In `parentSlot`, the thumbnail gains the same hook (seeds get swatches too):

```swift
                if let id, let node = model.lineage.node(id) {
                    RemixThumbnailView(isf: node.isfSource, animating: true,
                                       onSnapshot: { img in model.storeSnapshot(id: node.id, image: img) }) { _, _ in }
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
```

(e) In `resolveParent`, pass a human label per source. Replace the function body:

```swift
    /// Fills the first empty slot (A, then B for crossover) with the resolved source.
    private func resolveParent(_ spec: ParentSpec) {
        let slot: ParentSlot = (model.parentAID == nil) ? .a
            : (model.mode == .crossover && model.parentBID == nil) ? .b : .a
        let label: String
        switch spec {
        case .libraryFile(let url): label = url.deletingPathExtension().lastPathComponent
        case .currentEditor:        label = "editor"
        case .shadertoyLink:        label = "shadertoy"
        case .pastedISF:            label = "pasted"
        }
        Task {
            do {
                let isf = try await resolver.resolve(spec)
                model.setParent(slot, isf: isf, label: label)
                resolveError = nil
            } catch { resolveError = "Couldn't load parent: \(error)" }
        }
    }
```

(Case names verified against the existing `resolveParent` call sites: `.libraryFile(URL)`, `.currentEditor`, `.shadertoyLink(String)`, `.pastedISF(String)`.)

- [ ] **Step 3: Build-verify**

Run the house command with `build`. Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Run the full test suite**

Run the house test command. Expected: `Executed 115 tests, with 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add App/TrueISFEditor/Remix/RemixLineageTreeView.swift App/TrueISFEditor/Remix/RemixStudioView.swift
git commit -m "feat(remix): lineage tree right rail — swatch rows, ⚭ badges, action strip, ★ filter

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 6: Verification + gates

**Files:** none new.

- [ ] **Step 1: Full clean verification**

```bash
cd App && xcodegen generate && xcodebuild -project TrueISFEditor.xcodeproj -scheme TrueISFEditor -derivedDataPath ./ddata-review -destination 'platform=macOS,arch=arm64' ARCHS=arm64 ONLY_ACTIVE_ARCH=YES test 2>&1 | grep -E 'error:|Executed [0-9]+ tests, with|\*\* TEST'
```

Expected: `Executed 115 tests, with 0 failures` and `** TEST SUCCEEDED **`.

- [ ] **Step 2: Binary freshness check (memory: xcode26-debug-dylib-staleness)**

Verify with a string UNIQUE to this change (not pre-existing):

```bash
grep -c "the family tree grows here" App/ddata-review/Build/Products/Debug/TrueISFEditor.app/Contents/MacOS/TrueISFEditor.debug.dylib
```

Expected: `1` (grep the `.debug.dylib`, NOT the main stub binary).

- [ ] **Step 3: Manual Mechanic review (native-Swift exception — CoS reads the diff inline, no subagent)**

Audit the changed files for: optional force-unwraps in view code, retain cycles in closures capturing `model`, `@State` mutation off the main actor, tap-gesture ordering (double-tap before single-tap), and the trailing-closure binding on `RemixThumbnailView` call sites.

- [ ] **Step 4: Update the on-device gate action item**

Append the tree loop to the existing "On-device gate — ISF Remix Studio" item in `~/.claude/c-suite/inbox/action-items.json` (id `16e8c45f-1d12-465d-b345-fb02bfc81d69`): select a node → action strip appears with live preview → ⚭ badge selects parent B → promote A/B works → ★ filter → collapse/expand → double-click opens editor → swatches appear as children compile.

- [ ] **Step 5: Launch on-device (by absolute binary path — never `open`)**

```bash
App/ddata-review/Build/Products/Debug/TrueISFEditor.app/Contents/MacOS/TrueISFEditor &
```

Hand to the user for the interactive gate.
