# ARShader Milestone 2 phase 3c — thumbnails, drag and drop, and the preview/program split

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the slot bank into a contact sheet of still frames, make drag-and-drop the single verb for moving shaders anywhere, and correct `PREVIEW SCALE` so it can never reach the projector.

**Architecture:** A new `ThumbnailService` actor renders stills offscreen on its own Metal queue, cached to disk by path+mtime, and hands images to slot cells and library rows. The frame graph gains knowledge of whether the program feed is open, which is what lets live decks keep following `PREVIEW SCALE` while output is closed and pin to 100% while it is open. Drag-and-drop is layered onto the existing `Instrument.load(_:onto:thenApply:)` seam without adding a second write path into `SlotBank.capture`.

**Tech Stack:** Swift 6, SwiftUI, Metal, XCTest. macOS app target `ARShader` in `App/TrueISFEditor.xcodeproj` (one generated project, two schemes). Shared `ISFRuntime` target for shader compilation and readback.

**Spec:** `docs/superpowers/specs/2026-07-31-arshader-thumbnails-and-drag-drop-design.md` — **revision 3**. Read the current file, not any earlier summary of it: revision 2 folded the PM review, and revision 3 corrected the master-pin rule after reading the real frame graph.
**PM review:** `~/.claude/c-suite/reports/pm/2026-07-31-arshader-3c-thumbnails-drag-drop-spec-review.md` — returned REWRITE with 8 findings, all resolved.

## Global Constraints

- **Branch:** `m2-slot-bank`, worktree `.worktrees/m2-slot-bank`. Derived data **`/tmp/arshader-ddata-bank`** — NEVER `/tmp/arshader-ddata`, which a concurrent codex session uses in the main checkout.
- **Never `git add -A`.** Concurrent sessions edit `App/`. Stage by explicit path, always. This rule was broken once on 2026-07-31 and swept an implementer's in-flight edit into an unrelated commit.
- **Build:** `xcodebuild -project App/TrueISFEditor.xcodeproj -scheme ARShader -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/arshader-ddata-bank ARCHS=arm64 ONLY_ACTIVE_ARCH=YES`
- **Suite baselines entering this plan:** ARShaderTests **256**, TrueISFEditorTests **514 (3 skipped)**, ShadertoyISFKit **312**. Any DROP in a count means a test was lost — find it before continuing.
- **`xcodebuild test` launches an ARShader window every run** and reads as a freeze. Expected; do not kill it.
- **Under Xcode 26 the real code is in `ARShader.debug.dylib`**, not the 58KB `Contents/MacOS/ARShader` stub. Verify binary freshness against the dylib with `nm`, **not `strings`** — mangled Swift symbol names live in the symbol table, not `__cstring`, so `strings` reports zero hits on code that is demonstrably present.
- **Thumbnail sample time is `t = 2.0` seconds.** Settled, not implementer's choice.
- **`PREVIEW SCALE` may never reach the projector.** While the program feed is OPEN the whole live chain — decks and master alike — is pinned at full output resolution; while it is CLOSED, `PREVIEW SCALE` governs as it always has. Spec revision 3 corrects revision 2's "master pinned unconditionally", which would have composited scaled decks into a full-size target every frame while output was closed.
- **Never a second write path into `SlotBank.capture`.** It has exactly one call site today and that is load-bearing.
- **Custom errors, not `new Error()` equivalents** — follow the existing error types in the target.
- **TDD:** every task writes its failing test first, and every task ends with a mutation proof that the new test CAN fail.
- **Native-Swift Mechanic exception:** Mechanic is a manual read by the controller, never a dispatched subagent.

---

### Task 1: `ThumbnailService`

**Files:**
- Create: `App/ARShader/ThumbnailService.swift`
- Create: `App/ARShader/ThumbnailCache.swift` — the disk layer, separated so it is testable with no GPU at all
- Test: `App/ARShaderTests/ThumbnailServiceTests.swift`, `App/ARShaderTests/ThumbnailCacheTests.swift`

**Interfaces:**
- Consumes: `ISFSceneLoader.load(source:device:)` (`App/ISFRuntime/ISFSceneLoader.swift:37-59`); `ISFMSLSafeRenderAtTime(scene, size, time:, cb, &err)` (`App/ISFRuntime/ISFMSLSafeBridge.h:39-43`); `TextureReadback.managedCopy(of:device:queue:)` (`App/ISFRuntime/TextureReadback.swift:6-24`); `FramePNGEncoder.encodePNG` (`App/ISFRuntime/FramePNGEncoder.swift:14-99`); `LibraryEntry.url` / `.dateModified` (`App/ISFRuntime/LibraryModel.swift:4-16`).
- Produces: `ThumbnailService` with `thumbnail(for:priority:) async -> ThumbnailService.Result`, `cancelInteractive()`, `ThumbnailService.Priority`, and `ThumbnailCache`. Tasks 3 and 7 consume these.

**No UI in this task.** It is fully unit-testable against fixture shaders, and that is the point:
the phase's riskiest component ships behind tests before anything draws it.

**Two deliberate deviations from house convention, both stated so a reviewer sees a decision rather
than an accident:**

1. **This is the first `actor` in the app.** The house pattern is `@MainActor` class plus a
   `nonisolated`/`NSLock` escape hatch with generation-counter cancellation (`ShaderUnit.swift:16-19,
   87-97`), which exists because the renderer must be callable from the CVDisplayLink thread. A
   thumbnail service has no such caller: everything reaching it is `async` and off the main actor,
   so an actor is the natural fit and a hand-rolled lock would be strictly worse. Contained to this
   file.
2. **The device is SHARED; only the queue is separate.** The spec asked for "its own `MTLDevice`
   handle obtained independently". That is wrong on this platform — there is one GPU, and
   `RenderProperties.global()` is the singleton every renderer already uses. What must not be shared
   is the **command queue**: `.renderQueue` is the live path. `RenderProperties.global().bgCmdQueue`
   already exists and is documented for background work. Use it, and assert the separation.

- [ ] **Step 1: Write the failing cache tests** (no GPU, no Metal)

Create `App/ARShaderTests/ThumbnailCacheTests.swift`:

```swift
import XCTest
@testable import ARShader

final class ThumbnailCacheTests: XCTestCase {
    private func makeCache() throws -> (ThumbnailCache, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("thumbcache-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return (try ThumbnailCache(directory: dir), dir)
    }

    private func shaderFile(_ body: String = "// v1") throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("thumb-\(UUID().uuidString).fs")
        try body.write(to: url, atomically: true, encoding: .utf8)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    func testAMissReturnsNil() throws {
        let (cache, _) = try makeCache()
        XCTAssertNil(try cache.entry(for: try shaderFile()))
    }

    func testAStoredImageComesBack() throws {
        let (cache, _) = try makeCache()
        let shader = try shaderFile()
        try cache.store(.image(Data([0x89, 0x50, 0x4E, 0x47])), for: shader)
        guard case .image = try XCTUnwrap(cache.entry(for: shader)) else {
            return XCTFail("stored an image, got something else")
        }
    }

    /// A failure is a cache ENTRY, not a cache miss. Retrying a broken shader on every hover is a
    /// stutter the operator cannot explain and cannot fix.
    func testAFailureIsCachedAsAFailure() throws {
        let (cache, _) = try makeCache()
        let shader = try shaderFile()
        try cache.store(.unavailable, for: shader)
        XCTAssertEqual(try cache.entry(for: shader), .unavailable)
    }

    /// The key is path + modification date, so fixing a broken shader on disk retries it — a
    /// permanently-cached failure would make a fixed shader look broken forever.
    func testEditingTheShaderInvalidatesBothSuccessAndFailure() throws {
        let (cache, _) = try makeCache()
        let shader = try shaderFile("// v1")
        try cache.store(.unavailable, for: shader)
        XCTAssertEqual(try cache.entry(for: shader), .unavailable)

        try "// v2 — fixed".write(to: shader, atomically: true, encoding: .utf8)
        XCTAssertNil(try cache.entry(for: shader),
                     "A newer mtime is a different key, so the fixed shader is retried")
    }

    /// Bounded by COUNT, not bytes: thumbnails are small and fixed-size, so a byte budget would
    /// add arithmetic for no behavioural gain. Swept at launch, never during a set.
    func testEvictionDropsTheLeastRecentlyUsedAboveTheCeiling() throws {
        let (cache, _) = try makeCache()
        var shaders: [URL] = []
        for i in 0..<5 {
            let s = try shaderFile("// \(i)")
            try cache.store(.image(Data([UInt8(i)])), for: s)
            shaders.append(s)
        }
        _ = try cache.entry(for: shaders[4])          // touch the newest
        try cache.evict(keepingAtMost: 2)
        XCTAssertNotNil(try cache.entry(for: shaders[4]), "the most recently used survives")
        XCTAssertNil(try cache.entry(for: shaders[0]), "the least recently used is gone")
    }
}
```

- [ ] **Step 2: Run — expect a compile failure** (`cannot find 'ThumbnailCache' in scope`).

- [ ] **Step 3: Write `ThumbnailCache`**

`App/ARShader/ThumbnailCache.swift`. Follow `SnapshotStore.documentKey(for:)`
(`App/TrueISFEditor/Models/SnapshotStore.swift:57-65`) for the key-derivation convention rather than
inventing one. One file per entry under Application Support, so a stale entry is deletable by hand.

```swift
import Foundation
import CryptoKit

/// The disk half of the thumbnail pipeline, deliberately split from the render half: everything
/// here is testable with no Metal, no GPU, and no fixture shader that has to compile.
struct ThumbnailCache {
    enum Entry: Equatable {
        case image(Data)        // PNG bytes
        /// A shader that would not compile. Cached so a broken shader is not recompiled on every
        /// hover; invalidated by mtime like any other entry, so fixing it on disk retries it.
        case unavailable
    }

    private let directory: URL

    init(directory: URL) throws {
        self.directory = directory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// Path + modification date. Both, because either alone is wrong: path alone never notices an
    /// edit, and mtime alone collides across the ~1,500-shader library.
    static func key(for shaderURL: URL) throws -> String {
        let attrs = try FileManager.default.attributesOfItem(atPath: shaderURL.path)
        let modified = (attrs[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        let seed = "\(shaderURL.standardizedFileURL.path)|\(modified)"
        let digest = SHA256.hash(data: Data(seed.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    func entry(for shaderURL: URL) throws -> Entry? {
        let base = directory.appendingPathComponent(try Self.key(for: shaderURL))
        let png = base.appendingPathExtension("png")
        let failed = base.appendingPathExtension("failed")
        if let data = try? Data(contentsOf: png) {
            try? touch(png)
            return .image(data)
        }
        if FileManager.default.fileExists(atPath: failed.path) {
            try? touch(failed)
            return .unavailable
        }
        return nil
    }

    func store(_ entry: Entry, for shaderURL: URL) throws {
        let base = directory.appendingPathComponent(try Self.key(for: shaderURL))
        switch entry {
        case .image(let data): try data.write(to: base.appendingPathExtension("png"))
        case .unavailable:     try Data().write(to: base.appendingPathExtension("failed"))
        }
    }

    /// LRU by access date. Called once at launch and never during a set — a sweep mid-performance
    /// is disk I/O the operator did not ask for at the worst possible moment.
    func evict(keepingAtMost ceiling: Int) throws {
        let keys: [URLResourceKey] = [.contentAccessDateKey]
        let files = try FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: keys)
        guard files.count > ceiling else { return }
        let sorted = try files.sorted {
            let a = try $0.resourceValues(forKeys: Set(keys)).contentAccessDate ?? .distantPast
            let b = try $1.resourceValues(forKeys: Set(keys)).contentAccessDate ?? .distantPast
            return a > b                                   // newest first
        }
        for stale in sorted.dropFirst(ceiling) {
            try? FileManager.default.removeItem(at: stale)
        }
    }

    private func touch(_ url: URL) throws {
        try FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
    }
}
```

- [ ] **Step 4: Run the cache tests — expect PASS.**

- [ ] **Step 5: Write the failing service tests**

Create `App/ARShaderTests/ThumbnailServiceTests.swift`. `broken.fs` already exists in
`App/ARShaderTests/Fixtures/` and is the known-failing fixture — do not author a new one.

```swift
import XCTest
import Metal
@testable import ARShader

final class ThumbnailServiceTests: XCTestCase {
    private func temporaryCacheDirectory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("thumbsvc-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return dir
    }

    private func fixtureURL(_ name: String) throws -> URL {
        try XCTUnwrap(Bundle(for: Self.self)
            .url(forResource: name, withExtension: "fs", subdirectory: "Fixtures"))
    }

    func testAValidShaderProducesAnImage() async throws {
        let service = ThumbnailService(cacheDirectory: try temporaryCacheDirectory())
        let result = await service.thumbnail(for: try fixtureURL("solid_red"), priority: .batch)
        guard case .image = result else { return XCTFail("expected an image, got \(result)") }
    }

    /// The whole reason t is not 0: many shaders are black at t=0, and a black thumbnail is worse
    /// than no thumbnail. 2.0s is past nearly every fade-in and early enough that feedback shaders
    /// have not drifted into mush.
    func testTheSampleTimeIsTwoSeconds() {
        XCTAssertEqual(ThumbnailService.sampleTime, 2.0)
    }

    func testABrokenShaderResolvesAsUnavailable() async throws {
        let service = ThumbnailService(cacheDirectory: try temporaryCacheDirectory())
        let result = await service.thumbnail(for: try fixtureURL("broken"), priority: .batch)
        XCTAssertEqual(result, .unavailable)
    }

    /// A broken shader must be compiled ONCE. The second call is a cache read, not a recompile.
    func testABrokenShaderIsNotRecompiledOnEveryRequest() async throws {
        let service = ThumbnailService(cacheDirectory: try temporaryCacheDirectory())
        let broken = try fixtureURL("broken")
        _ = await service.thumbnail(for: broken, priority: .batch)
        let compilesBefore = await service.compileCountForTesting
        _ = await service.thumbnail(for: broken, priority: .batch)
        let compilesAfter = await service.compileCountForTesting
        XCTAssertEqual(compilesBefore, compilesAfter,
                       "the second request must be served from the cached failure")
    }

    /// The safety property that no other test can see, because no unit test has a live render
    /// loop: a thumbnail compile must never share the queue the instrument is drawing on.
    func testTheServiceNeverUsesTheLiveRenderQueue() async throws {
        let service = ThumbnailService(cacheDirectory: try temporaryCacheDirectory())
        let serviceQueue = await service.commandQueueForTesting
        XCTAssertFalse(serviceQueue === RenderProperties.global().renderQueue,
                       "sharing the live queue is how a thumbnail becomes a dropped frame mid-set")
    }
}
```

- [ ] **Step 6: Run — expect a compile failure** (`cannot find 'ThumbnailService' in scope`).

- [ ] **Step 7: Write `ThumbnailService`**

`App/ARShader/ThumbnailService.swift`. Render with `ISFMSLSafeRenderAtTime`, which takes the time as
a plain `Double` — pass `Self.sampleTime` directly; there is no clock object to construct.

```swift
import Foundation
import Metal
import SwiftUI

/// Stills for the slot bank and the library, rendered offscreen and cached to disk.
///
/// An `actor` — the first in this app. The house pattern (`@MainActor` class + `NSLock` escape
/// hatch) exists because the renderer is called from the CVDisplayLink thread; nothing here is,
/// so an actor is the right tool and a hand-rolled lock would be strictly worse.
actor ThumbnailService {
    enum Priority: Sendable {
        /// Library hover. Superseded constantly as the pointer moves, so a newer request cancels
        /// the older one — a thumbnail for a row the pointer has left is wasted work.
        case interactive
        /// Populating the bank on launch or on growing a row. Queued and ALWAYS completed:
        /// cancelling these leaves permanently blank cells that only a resize or relaunch fills.
        case batch
    }

    enum Result: Equatable, Sendable {
        case image(Data)
        case unavailable
    }

    /// Not t=0 — many shaders are black there. See `testTheSampleTimeIsTwoSeconds`.
    static let sampleTime: Double = 2.0

    /// Above the ~1,500-shader library, so a full sweep never thrashes.
    static let cacheCeiling = 2_000

    private let cache: ThumbnailCache
    private let device: MTLDevice
    /// NOT `RenderProperties.global().renderQueue`. `bgCmdQueue` is the singleton's documented
    /// background queue; the live path must never wait behind a thumbnail compile.
    private let queue: MTLCommandQueue
    private var interactiveTask: Task<Result, Never>?

    private(set) var compileCountForTesting = 0
    var commandQueueForTesting: MTLCommandQueue { queue }

    init(cacheDirectory: URL) {
        let properties = RenderProperties.global()
        self.device = properties.device
        self.queue = properties.bgCmdQueue
        self.cache = (try? ThumbnailCache(directory: cacheDirectory))!
    }

    func thumbnail(for shaderURL: URL, priority: Priority) async -> Result {
        if let cached = try? cache.entry(for: shaderURL) {
            switch cached {
            case .image(let data): return .image(data)
            case .unavailable:     return .unavailable
            }
        }
        switch priority {
        case .batch:
            return await render(shaderURL)
        case .interactive:
            interactiveTask?.cancel()
            let task = Task { await self.render(shaderURL) }
            interactiveTask = task
            return await task.value
        }
    }

    /// Drops in-flight hover work only. A queued `.batch` request is untouched — the two consumers
    /// have opposite requirements and this is the line between them.
    func cancelInteractive() {
        interactiveTask?.cancel()
        interactiveTask = nil
    }

    func sweepCache() {
        try? cache.evict(keepingAtMost: Self.cacheCeiling)
    }

    private func render(_ shaderURL: URL) async -> Result {
        compileCountForTesting += 1
        guard !Task.isCancelled,
              let source = try? String(contentsOf: shaderURL, encoding: .utf8),
              let scene = try? ISFSceneLoader.load(source: source, device: device) else {
            try? cache.store(.unavailable, for: shaderURL)
            return .unavailable
        }
        guard let png = renderPNG(scene: scene) else {
            try? cache.store(.unavailable, for: shaderURL)
            return .unavailable
        }
        try? cache.store(.image(png), for: shaderURL)
        return .image(png)
    }
}
```

`renderPNG(scene:)` is the assembly of the pieces that already exist: make a command buffer on
`queue`, call `ISFMSLSafeRenderAtTime(scene, size, Self.sampleTime, cb, &err)`, commit and wait,
`TextureReadback.managedCopy(of:device:queue:)`, then `FramePNGEncoder.encodePNG`. Follow
`App/ARShaderTests/InstrumentRendererTests.swift:1-43` for the isolated-device pattern. Thumbnail
size: 320×180 (16:9, twice the 96pt cell width at 2× backing scale).

- [ ] **Step 8: Run the service tests — expect PASS.**

- [ ] **Step 9: Mutation-prove three separate gates**

Each run, then REVERTED:

1. `sampleTime` → `0.0`. Expected: `testTheSampleTimeIsTwoSeconds` FAILS.
2. In `render`, delete the `cache.store(.unavailable, …)` on the compile-failure path. Expected:
   `testABrokenShaderIsNotRecompiledOnEveryRequest` FAILS.
3. `self.queue = properties.renderQueue`. Expected: `testTheServiceNeverUsesTheLiveRenderQueue`
   FAILS. **This is the one that matters most** — it is the only assertion standing between a
   thumbnail sweep and a dropped frame mid-set, and nothing else in the suite can see it.

Record all three results in the commit message.

- [ ] **Step 10: Full ARShader suite, then commit**

```bash
git add App/ARShader/ThumbnailService.swift App/ARShader/ThumbnailCache.swift \
        App/ARShaderTests/ThumbnailServiceTests.swift App/ARShaderTests/ThumbnailCacheTests.swift
git commit -m "feat(3c): ThumbnailService — offscreen stills at t=2.0s, cached by path+mtime

Failures are cached AS failures and invalidated by mtime, so a broken shader
compiles once and a fixed one retries. Renders on RenderProperties.bgCmdQueue,
never the live renderer's queue — mutation-proven, and the only assertion in
the suite that can see it."
```

---

### Task 2: The preview/program split

**Files:**
- Modify: `App/ARShader/InstrumentRenderer.swift` — new `isProgramLive` property; one line in `renderFrame()`; `reallocateMastersLocked()`
- Modify: `App/ARShader/OutputWindowController.swift` — push program-live state into the renderer
- Modify: `App/ARShader/OutputDestination.swift` — retire `OutputSharpness.isProjectingUpscaled`
- Modify: `App/ARShader/InstrumentView.swift:473-478` — remove the now-dead `projectingUpscaled` warning
- Test: `App/ARShaderTests/FrameGraphTests.swift`, `App/ARShaderTests/InstrumentRendererTests.swift`, `App/ARShaderTests/OutputDestinationTests.swift`

**Interfaces:**
- Consumes: nothing from Task 1. This task is independent of the whole UI arc and is deliberately first-after-the-service.
- Produces: `InstrumentRenderer.isProgramLive: Bool` (lock-guarded, settable from the main actor, reallocates the master pair on change).

**Do this early.** It is the riskiest change in the phase and touches nothing the UI tasks touch.

Today `renderFrame()` computes, at `InstrumentRenderer.swift:371`:

```swift
let liveRes = renderScale.applied(to: outRes)
```

and *everything* derives from it — deck rasterisation (`line 397`), cue size (`line 377`,
`cueScale.applied(to: liveRes)`), master FX (`line 440`, `renderSize: liveRes.size`), and the master
pair's own allocation in `reallocateMastersLocked()` (`line 288`). So the entire behavioural change
is that one expression becoming conditional. There is no second rule to keep in sync.

- [ ] **Step 1: Write the four failing tests**

Add to `App/ARShaderTests/FrameGraphTests.swift`. They use the existing `setUpWithError` harness
(`device`/`queue`/`mixer`/`renderer`) and the existing `load(_:_:)` helper with the `solid_red` /
`solid_green` fixtures — do not invent new ones.

```swift
    // MARK: The preview/program split (phase 3c task 2)

    func testWithOutputLiveALiveDeckIgnoresPreviewScale() throws {
        try load(.one, "solid_red")
        mixer.crossfadePosition = 0                     // deck 1 LIVE
        renderer.previewScale = RenderScale(percent: 25)
        renderer.isProgramLive = true                   // the projector is open
        renderer.renderFrame()
        XCTAssertEqual(try XCTUnwrap(renderer.deckRasterSize(.one)).width, 1920,
                       "With the projector open, a live deck rasterises full size whatever "
                       + "PREVIEW SCALE says — the operator's rule is that the projector is "
                       + "never affected, ever.")
    }

    func testWithOutputLiveTheMasterIsFullSizeAtAnyPreviewScale() throws {
        renderer.outputResolution = RenderSize(width: 1920, height: 1080)
        renderer.previewScale = RenderScale(percent: 25)
        renderer.isProgramLive = true
        renderer.renderFrame()
        let tex = try XCTUnwrap(renderer.rawMasterTexture())
        XCTAssertEqual(tex.width, 1920)
        XCTAssertEqual(tex.height, 1080,
                       "The master is pinned WITH the decks, on the same condition — a pinned "
                       + "master over scaled decks would composite an upscale every frame.")
    }

    func testOpeningTheOutputDoesNotCostTheCueSaving() throws {
        try load(.one, "solid_red")
        try load(.two, "solid_green")
        mixer.crossfadePosition = 0                     // deck 1 live, deck 2 cued
        renderer.previewScale = RenderScale(percent: 100)
        renderer.cueRenderScale = RenderScale(percent: 25)
        renderer.isProgramLive = true
        renderer.renderFrame()
        XCTAssertEqual(try XCTUnwrap(renderer.deckRasterSize(.one)).width, 1920,
                       "the live deck pays full price")
        XCTAssertEqual(try XCTUnwrap(renderer.deckRasterSize(.two)).width, 480,
                       "the cued deck is not on the projector, so opening it must not make the "
                       + "cued deck full size too")
    }

    func testClosingTheOutputRestoresPreviewScale() throws {
        try load(.one, "solid_red")
        mixer.crossfadePosition = 0
        renderer.previewScale = RenderScale(percent: 25)
        renderer.isProgramLive = true
        renderer.renderFrame()
        XCTAssertEqual(try XCTUnwrap(renderer.deckRasterSize(.one)).width, 1920)

        renderer.isProgramLive = false                  // projector closed again
        renderer.renderFrame()
        XCTAssertEqual(try XCTUnwrap(renderer.deckRasterSize(.one)).width, 480,
                       "Closing the output must give the saving back — this is not a one-way "
                       + "latch, and the operator closes the projector constantly while building.")
    }
```

- [ ] **Step 2: Run them and watch them fail to COMPILE**

Run the ARShader scheme (see Global Constraints for the full command).
Expected: build failure, `value of type 'InstrumentRenderer' has no member 'isProgramLive'`.
That is the correct first failure — the property does not exist yet.

- [ ] **Step 3: Add `isProgramLive` to the renderer**

In `App/ARShader/InstrumentRenderer.swift`, beside the existing stored render state, add the backing
field next to `renderScale` / `cueScale`, and this property in the exact shape of `previewScale`
(lines 239-262) — it guards the no-op set and reallocates, because a change of program-live state
changes the master size:

```swift
    /// Whether the program feed is actually going somewhere — the output window is open on a screen
    /// or floating. Set from the main actor by `OutputWindowController`; read under the lock during
    /// the frame.
    ///
    /// This is the ONLY thing that lifts `previewScale` off the live chain. The operator's rule is
    /// that the projector is never affected by a preview control, ever; while nothing is projected
    /// there is no image to protect and the saving is free. Pinning the master on the SAME
    /// condition as the decks (rather than unconditionally) is what stops a scaled deck being
    /// composited into a full-size target every frame while output is closed.
    var isProgramLive: Bool {
        get { lock.lock(); defer { lock.unlock() }; return programLive }
        set {
            lock.lock()
            guard newValue != programLive else { lock.unlock(); return }
            programLive = newValue
            reallocateMastersLocked()
            lock.unlock()
        }
    }
```

with the backing store declared alongside `renderScale`:

```swift
    private var programLive = false
```

`false` is the correct default: `OutputDestination.launchDefault` is `.off`, so the renderer and the
output controller agree at launch without anyone having to synchronise them.

- [ ] **Step 4: Make the one behavioural change**

`InstrumentRenderer.swift:371`, inside `renderFrame()`, after `let outRes = masterResolution`:

```swift
        // The whole preview/program split, in one expression. With the projector open the live
        // chain ignores PREVIEW SCALE entirely; with it closed, PREVIEW SCALE governs exactly as
        // it always has. Deck rasterisation, cue size, master FX and the master pair's own
        // allocation all derive from this, so there is no second rule that can drift out of sync.
        let liveRes = programLive ? outRes : renderScale.applied(to: outRes)
```

Note it reads `programLive` (the backing field) directly, not `isProgramLive` — the lock is already
held at that point, and going through the property would deadlock.

And the same conditional in `reallocateMastersLocked()` (line 288), which currently reads
`resolution: renderScale.applied(to: masterResolution)`:

```swift
    private func reallocateMastersLocked() {
        let live = programLive ? masterResolution : renderScale.applied(to: masterResolution)
        let fresh = Self.makeMasterPair(device: device, resolution: live)
        if fresh.count == 2 {
            masters = fresh
            masterIndex = 0
        }
    }
```

- [ ] **Step 5: Run the new tests AND the seven existing ones**

Run the ARShader scheme. Expected: the four new tests PASS, and **all seven of these pass unchanged**:
`testRenderScaleResizesTheMaster`, `testMasterIsFixedAt1920x1080`,
`testRenderScaleAppliesToALiveDeckNotJustACuedOne`,
`testALiveAndACuedDeckRasteriseAtDifferentScalesInTheSameFrame`,
`testCueScaleIsAFractionOfTheLiveRenderNotOfTheOutput`,
`testTheInstrumentStillRendersCorrectlyAtAReducedRenderScale`,
`testSettingTheSameRenderScaleIsANoOp`.

They pass because `programLive` defaults to `false` and none of them opens an output — they were
all *already* testing the output-closed row without saying so. **If any of the seven fails, stop and
report; do not "fix" it by editing its assertions.** A failure there means the conditional went the
wrong way round.

- [ ] **Step 6: Make the seven tests state their precondition**

Add one line to each of the six that set a scale (not `testSettingTheSameRenderScaleIsANoOp`, which
is orthogonal), immediately before `renderFrame()`:

```swift
        renderer.isProgramLive = false      // output closed: PREVIEW SCALE governs the live chain
```

This changes no behaviour — it is already the default. It exists because an implicit assumption that
happens to hold is one refactor away from a test that passes for the wrong reason, and this codebase
has already shipped exactly that failure (see the `stubMonitorIdealHeight` comment in
`SurfaceGeometryTests.swift`).

- [ ] **Step 7: Wire the output controller to the renderer**

In `App/ARShader/OutputWindowController.swift`, `setDestination(_:)` (lines 40-43) is the seam — the
whole class is `@MainActor`, so this runs on the main actor and the renderer property is
lock-guarded for exactly this crossing:

```swift
    func setDestination(_ destination: OutputDestination) {
        self.destination = destination
        // The renderer has no knowledge of OutputDestination and must not gain any — it needs one
        // bit, not a concept. Setting it here rather than in applyDestination's branches keeps it
        // beside the published value it mirrors, so the two can never disagree.
        instrument.renderer.isProgramLive = destination != .off
        applyDestination()
    }
```

Check `toggleFullscreen()` (lines 46-54) — the agent-mapped call graph says it routes through
`setDestination`, so it is covered. **Verify that before moving on**; if any path sets `destination`
without going through `setDestination`, it needs the same line, and that is a defect to report.

- [ ] **Step 8: Retire the upscale warning**

`OutputSharpness.isProjectingUpscaled(destination:scale:)` (`OutputDestination.swift:74-84`) is now
structurally false: the only state that made it true — output open at a reduced scale — no longer
reduces the scale. Replace the whole enum body with a test-facing statement of that fact rather than
deleting it silently, so a future change that reintroduces the hazard fails a test instead of
shipping:

```swift
enum OutputSharpness {
    /// Once TRUE when the program output was live and the chain rasterised below the typed output
    /// resolution. Phase 3c made that unreachable: `InstrumentRenderer.isProgramLive` lifts
    /// PREVIEW SCALE off the whole live chain the moment output opens, so an open projector is
    /// always rasterising at full size.
    ///
    /// Kept, and kept false, deliberately. It is the assertion that the hazard is gone; a change
    /// that lets a preview control reach the projector again turns this true and fails
    /// `testProjectingAnUpscaleIsUnreachable`.
    static func isProjectingUpscaled(destination: OutputDestination, scale: RenderScale) -> Bool {
        false
    }
}
```

Then remove `projectingUpscaled` (`InstrumentView.swift:473-478`) and the warning UI it drives.
Follow its usage to the view that renders it and remove that too — a warning that can never fire is
worse than none, because it teaches the operator to ignore the spot it occupied.

- [ ] **Step 9: Add the unreachability test**

In `App/ARShaderTests/OutputDestinationTests.swift`:

```swift
    /// Phase 3c: a preview control can no longer reach the projector, so this must hold for EVERY
    /// combination rather than only the ones a UI happens to produce today.
    func testProjectingAnUpscaleIsUnreachable() {
        let destinations: [OutputDestination] = [.off, .floating, .screen(id: "1")]
        for destination in destinations {
            for percent in RenderScale.presets {
                XCTAssertFalse(
                    OutputSharpness.isProjectingUpscaled(destination: destination,
                                                         scale: RenderScale(percent: percent)),
                    "\(destination) at \(percent)% must not be an upscale")
            }
        }
    }
```

- [ ] **Step 10: Mutation-prove the new gates**

Two mutations, each run and then REVERTED:

1. In `renderFrame()`, change the conditional to `let liveRes = renderScale.applied(to: outRes)`
   (i.e. remove the pin). Expected: `testWithOutputLiveALiveDeckIgnoresPreviewScale` and
   `testWithOutputLiveTheMasterIsFullSizeAtAnyPreviewScale` FAIL.
2. Change it to `let liveRes = outRes` (i.e. pin unconditionally). Expected:
   `testClosingTheOutputRestoresPreviewScale` and `testRenderScaleResizesTheMaster` FAIL.

Both mutations must produce failures. If mutation 2 produces none, the output-closed row is untested
and the saving could silently disappear. Record both results in the commit message.

- [ ] **Step 11: Full ARShader suite, then commit**

```bash
git add App/ARShader/InstrumentRenderer.swift App/ARShader/OutputWindowController.swift \
        App/ARShader/OutputDestination.swift App/ARShader/InstrumentView.swift \
        App/ARShaderTests/FrameGraphTests.swift App/ARShaderTests/InstrumentRendererTests.swift \
        App/ARShaderTests/OutputDestinationTests.swift
git commit -m "feat(3c): PREVIEW SCALE can no longer reach the projector

The live chain ignores PREVIEW SCALE while the program feed is open and
follows it while closed — one expression in renderFrame(), from which deck
rasterisation, cue size, master FX and the master pair's allocation all
already derive.

All seven existing render-scale tests pass unchanged: launchDefault is .off,
so every one of them was already testing the output-closed row. Six now say
so explicitly."
```

---

### Task 3: Slot cells draw thumbnails, with the three states

**Files:**
- Modify: `App/ARShader/SlotBankStripView.swift` — `SlotCell` (lines 233-308) gains a thumbnail and the three states
- Modify: `App/ARShader/InstrumentSurface.swift:108` — cell metrics grow for an image
- Test: `App/ARShaderTests/SlotCellStateTests.swift` (new)

**Interfaces:**
- Consumes: `ThumbnailService.thumbnail(for:priority:)` and `ThumbnailService.Result` from Task 1.
- Produces: `SlotCellState` (`enum { live(DeckID), idle, unavailable }`) and `SlotCell.state(preset:isAvailable:liveOn:)`, both used by Task 5's drop-target work.

`SlotCell` today is a `Button(action: activate)` wrapping an `HStack` of an index label and a name.
The whole visual body is replaced; **`activate()` (lines 293-301) and the context menu (274-285) are
NOT touched** — that gating is the never-overwrite rule and it is already correct and reviewed.

The state carrier changes from saturation to border+badge, because a thumbnail already spends
colour. See the spec's "Slot cell states" for why desaturation cannot survive photographic cells.

- [ ] **Step 1: Write the failing state test**

Create `App/ARShaderTests/SlotCellStateTests.swift`. The state derivation is pulled OUT of the view
into a pure static function precisely so it is testable without a render harness — the same doctrine
`SurfaceLayout` follows.

```swift
import XCTest
@testable import ARShader

@MainActor
final class SlotCellStateTests: XCTestCase {
    private func preset(_ path: String = "/tmp/a.fs") -> Preset {
        Preset.capturing(url: URL(fileURLWithPath: path), snapshot: ParamSnapshot(params: [:]))
    }

    func testAnEmptySlotIsIdle() {
        XCTAssertEqual(SlotCellState.of(preset: nil, isAvailable: false, liveOn: nil), .idle)
    }

    func testAFilledSlotWhoseFileIsGoneIsUnavailable() {
        XCTAssertEqual(SlotCellState.of(preset: preset(), isAvailable: false, liveOn: nil),
                       .unavailable)
    }

    /// Unavailable OUTRANKS live. A slot whose file vanished while its shader is still playing
    /// must not draw as a healthy live slot — the operator would fire it and get nothing.
    func testUnavailableOutranksLive() {
        XCTAssertEqual(SlotCellState.of(preset: preset(), isAvailable: false, liveOn: .one),
                       .unavailable)
    }

    func testAFilledAvailableSlotPlayingOnADeckIsLiveOnThatDeck() {
        XCTAssertEqual(SlotCellState.of(preset: preset(), isAvailable: true, liveOn: .two),
                       .live(.two))
    }

    func testAFilledAvailableSlotNotPlayingIsIdle() {
        XCTAssertEqual(SlotCellState.of(preset: preset(), isAvailable: true, liveOn: nil), .idle)
    }
}
```

- [ ] **Step 2: Run it — expect a compile failure** (`cannot find 'SlotCellState' in scope`).

- [ ] **Step 3: Add the state type**

In `App/ARShader/SlotBankStripView.swift`, above `SlotCell`:

```swift
/// How one cell reads. Derived rather than stored, so it cannot drift from the bank.
///
/// Border and badge carry the state, NOT saturation. Phase 3b distinguished live from idle by
/// colour-vs-greyscale, which worked when a cell was a flat rectangle and a name. A thumbnail is a
/// photograph and already spends colour: this library runs from near-monochrome ASCII shaders to
/// fully saturated ones, so a greyscale shader's live and idle cells would look identical and a
/// lurid one would read as live while idle. Brightness is the channel a still image does not
/// already own.
enum SlotCellState: Equatable {
    case live(DeckID)
    case idle
    case unavailable

    /// Unavailable outranks live: a slot whose file vanished must never draw as healthy, because
    /// the operator would fire it and get nothing.
    static func of(preset: Preset?, isAvailable: Bool, liveOn: DeckID?) -> SlotCellState {
        guard preset != nil else { return .idle }
        guard isAvailable else { return .unavailable }
        if let deck = liveOn { return .live(deck) }
        return .idle
    }

    var borderColor: Color? {
        switch self {
        case .live(.one): return .cyan
        case .live(.two): return .orange
        case .idle, .unavailable: return nil
        }
    }

    /// Dimming, not desaturation — see the type's doc comment.
    var imageOpacity: Double {
        switch self {
        case .live:        return 1.0
        case .idle:        return 0.65
        case .unavailable: return 0.35
        }
    }

    var badge: String? {
        switch self {
        case .live(let deck): return deck.displayName
        case .idle:           return nil
        case .unavailable:    return "exclamationmark.triangle.fill"
        }
    }
}
```

- [ ] **Step 4: Run the state tests — expect PASS.**

- [ ] **Step 5: Give `SlotCell` the thumbnail**

Add `liveOn: DeckID?` and `thumbnail: Image?` to `SlotCell`'s stored properties, and replace the
`HStack` body (lines 248-267) with the image + overlaid chrome. Keep `.contentShape(Rectangle())`,
`.buttonStyle(.plain)`, the `.contextMenu`, `.help(helpText)` and `.accessibilityLabel` exactly as
they are. An **unavailable cell keeps showing its last-known thumbnail** rather than going blank:
the operator needs to recognise *which* look is broken in order to go remount the drive.

```swift
            ZStack(alignment: .topTrailing) {
                if let thumbnail {
                    thumbnail
                        .resizable()
                        .aspectRatio(16.0 / 9.0, contentMode: .fill)
                        .opacity(state.imageOpacity)
                } else {
                    Rectangle().fill(Color.white.opacity(preset == nil ? 0.03 : 0.08))
                }

                if let badge = state.badge {
                    // A live badge is the deck letter; an unavailable badge is a warning glyph.
                    // They occupy the same corner deliberately — one slot of chrome, one meaning.
                    Group {
                        if case .unavailable = state {
                            Image(systemName: badge).foregroundStyle(.orange)
                        } else {
                            Text(badge).foregroundStyle(.black)
                                .padding(.horizontal, 4)
                                .background(state.borderColor ?? .white, in: Capsule())
                        }
                    }
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .padding(3)
                }

                VStack {
                    Spacer()
                    Text(preset?.name ?? "empty")
                        .font(.system(size: 9, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)   // long AR_Genuary names differ at the END
                        .foregroundStyle(preset == nil ? .tertiary : .primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 3)
                        .background(.black.opacity(0.55))
                }
            }
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 3))
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .strokeBorder(state.borderColor ?? .clear, lineWidth: 2))
            .contentShape(Rectangle())
```

with `private var state: SlotCellState { .of(preset: preset, isAvailable: isAvailable, liveOn: liveOn) }`.

The name stays, under the image. The spec replaces name-as-primary-identifier with the still, not
the name entirely — at 56pt a thumbnail alone cannot disambiguate two variants of the same shader.

- [ ] **Step 6: Feed thumbnails and live state from the strip**

In `SlotBankStripView.content`, the `ForEach` at lines 146-158 gains the two new arguments. The
thumbnail comes from a `@State private var thumbnails: [Int: Image]` populated in a `.task` that
asks the service at `.batch` priority for every filled slot — **batch, not interactive**, because
cancelling these leaves permanently blank cells (spec, "Two consumers, two concurrency policies").

`liveOn` compares each slot's `shaderURL` to what each deck is actually playing:

```swift
    /// Which deck, if any, is playing this slot's shader right now. Compares `sourceURL`, which is
    /// stamped only on a SUCCESSFUL compile — so a slot whose recall failed to compile does not
    /// light up as live while the previous shader is still on screen.
    private func liveDeck(for preset: Preset?) -> DeckID? {
        guard let preset else { return nil }
        return DeckID.allCases.first {
            instrument.deck($0).unit.sourceURL == preset.shaderURL
        }
    }
```

- [ ] **Step 7: Grow the cell metrics**

`SurfaceMetrics.minCellWidth` is `56` (`InstrumentSurface.swift:108`). A 16:9 thumbnail at 56pt is
31pt tall — unreadable. Raise it to `96`, and re-check the row height constant the resize drag uses
(`SurfaceMetrics.slotStripRowHeight`) so a row still snaps cleanly. **Then re-run the existing
geometry gates**: `testTheMonitorStripIsUnmovedByTheSlotStripBelowIt` and both phase 3a monitor
gates must still pass — the strip is content-sized, and a taller strip must still not move the
monitors.

- [ ] **Step 8: Mutation-prove the state gate**

Change `SlotCellState.of` so `isAvailable` is checked AFTER `liveOn` (i.e. live wins over
unavailable). Expected: `testUnavailableOutranksLive` FAILS. Revert.

- [ ] **Step 9: Full suite, re-record PNG baselines, commit**

The three surface baselines change — the strip now draws images. Re-record via the `RECORD`
sentinel, and **confirm the pairwise-distinctness assertion in `testSurfaceBaselines` still passes
before accepting them**: three baselines that became identical would mean the strip renders nothing.

```bash
git add App/ARShader/SlotBankStripView.swift App/ARShader/InstrumentSurface.swift \
        App/ARShaderTests/SlotCellStateTests.swift App/ARShaderTests/Baselines
git commit -m "feat(3c): slot cells draw thumbnails, with border and badge carrying state"
```

---

### Task 4: `RECALL TO: A | B`, and slot recall constrained to decks

**Files:**
- Modify: `App/ARShader/SlotBankStripView.swift` — RECALL TO becomes `DeckID`; SOURCE picker removed
- Modify: `App/ARShader/InstrumentView.swift` — the shared `libraryTarget` binding is no longer shared
- Test: `App/ARShaderTests/SlotRecallTargetTests.swift` (new)

**Interfaces:**
- Consumes: `Instrument.load(_:onto:thenApply:)` (`Instrument.swift:90`), unchanged.
- Produces: `SlotBankStripView` no longer takes a `LibraryTarget` binding; it owns `@State private var recallTarget: DeckID`.

`LibraryTarget` keeps all five `allCases` entries — Task 5's drag-and-drop still needs FX
destinations. What changes is that **slot recall can no longer express them.** The constraint is at
the type level: the strip's picker binds `DeckID`, so `MST FX` is not a value it can hold, and the
phase 3b hazard (a slot click silently appending an unbounded FX stage) stops being reachable rather
than being merely avoided.

The SOURCE picker is removed in this task; Task 6 replaces it with the deck-monitor drag. **Between
task 4 and task 6 there is no way to capture a look** — that is a real gap, and the two tasks
therefore land in the same review cycle, not weeks apart.

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import ARShader

@MainActor
final class SlotRecallTargetTests: XCTestCase {
    /// The type-level constraint, asserted as a type-level fact: recall takes a DeckID, and there
    /// is no LibraryTarget case it can be handed. Phase 3b's hazard was that RECALL TO could hold
    /// `.masterFX`, so every slot click appended an unbounded FX stage to the master chain.
    func testRecallTargetsAreDecksOnly() {
        let targets = SlotBankStripView.recallTargets
        XCTAssertEqual(targets, DeckID.allCases)
        XCTAssertEqual(targets.count, 2, "A slot loads a deck. There is no third answer.")
    }

    /// Falsifiable companion: if someone widens the picker back to LibraryTarget, this catches it.
    func testNoRecallTargetIsAnFXChain() {
        for deck in SlotBankStripView.recallTargets {
            let asLibraryTarget = LibraryTarget.deck(deck)
            if case .deck = asLibraryTarget { continue }
            XCTFail("\(deck) mapped to a non-deck LibraryTarget")
        }
    }
}
```

- [ ] **Step 2: Run it — expect a compile failure** (`recallTargets` does not exist).

- [ ] **Step 3: Change the strip**

Remove the `@Binding var target: LibraryTarget` and the `@State private var source: DeckID`. Add:

```swift
    /// Where a recall WRITES. Two answers, because a slot holds a shader and shaders go on decks —
    /// "they will always be shaders not fx". Typed as `DeckID` rather than `LibraryTarget` so the
    /// phase 3b hazard is unreachable: there is no value of this picker that appends an FX stage.
    @State private var recallTarget: DeckID = .one

    static var recallTargets: [DeckID] { DeckID.allCases }
```

Delete the SOURCE `VStack` (lines 104-115) entirely. Change the RECALL TO picker (117-128) to
iterate `Self.recallTargets`, and `recall(_:)` (214-217) to:

```swift
    private func recall(_ index: Int) {
        guard let preset = bank.recall(index) else { return }
        instrument.load(preset.shaderURL, onto: .deck(recallTarget), thenApply: preset.snapshot)
    }
```

- [ ] **Step 4: Update the call site.** `InstrumentView` constructs `SlotBankStripView(instrument:target:layout:)`; drop the `target:` argument. The `@State private var libraryTarget` it still feeds to `LibraryPanelView` stays until Task 5 removes that too.

- [ ] **Step 5: Run the tests — expect PASS.** Also run `SurfaceGeometryTests`: the strip lost a control and is narrower, so `SurfaceMetrics.stripsMinWidth` may now be wrong in the other direction. See the Known Issues section.

- [ ] **Step 6: Mutation-prove.** Change `recallTargets` to return `DeckID.allCases + DeckID.allCases`. Expected: `testRecallTargetsAreDecksOnly` FAILS on the count. Revert.

- [ ] **Step 7: Commit**

```bash
git add App/ARShader/SlotBankStripView.swift App/ARShader/InstrumentView.swift \
        App/ARShaderTests/SlotRecallTargetTests.swift
git commit -m "feat(3c): RECALL TO is A|B, typed as DeckID so FX targets are unreachable"
```

---

### Task 5: Drag and drop — library → slot / deck / deck FX / master FX

**Files:**
- Create: `App/ARShader/ShaderDrag.swift` — the payload type and drop-acceptance rules
- Modify: `App/ARShader/LibraryPanelView.swift` — rows become draggable; the five-way picker and click-to-load are REMOVED
- Modify: `App/ARShader/SlotBankStripView.swift` — cells become drop targets
- Modify: `App/ARShader/MonitorView.swift` — deck tiles become drop targets
- Modify: `App/ARShader/FXChainView.swift` — FX sections become drop targets
- Modify: `App/ARShader/InstrumentView.swift` — the `libraryTarget` state is now dead; remove it
- Test: `App/ARShaderTests/ShaderDragTests.swift` (new)

**Interfaces:**
- Consumes: `Instrument.load(_:onto:thenApply:)`; `SlotBank.capture(_:into:)`; `SlotCellState` from Task 3.
- Produces: `ShaderDrag` (a `Transferable` payload) and `ShaderDrag.accepts(_:on:isSlotFilled:withOption:) -> Bool`, reused verbatim by Task 6.

**There is no drag-and-drop anywhere in this codebase today** — confirmed by exhaustive grep for
`.draggable`, `.dropDestination`, `onDrag`, `onDrop`, `NSItemProvider`, `UTType`, `Transferable`.
This task establishes the pattern; Task 6 extends it. Follow SwiftUI's `Transferable` +
`.dropDestination(for:action:isTargeted:)`, not the older `NSItemProvider` API.

**The acceptance rules are a pure function**, deliberately: the whole never-overwrite invariant is
expressible without a view, and therefore testable without one.

- [ ] **Step 1: Write the failing acceptance tests**

Create `App/ARShaderTests/ShaderDragTests.swift`:

```swift
import XCTest
@testable import ARShader

@MainActor
final class ShaderDragTests: XCTestCase {
    private let url = URL(fileURLWithPath: "/tmp/a.fs")
    private var fromLibrary: ShaderDrag { .init(source: .library, url: url, snapshot: nil) }
    private var fromDeck: ShaderDrag {
        .init(source: .deck(.one), url: url, snapshot: ParamSnapshot(params: [:]))
    }

    // MARK: The never-overwrite rule, now under a drag

    func testADropOnAnEmptySlotIsAccepted() {
        XCTAssertTrue(ShaderDrag.accepts(fromLibrary, on: .slot, isSlotFilled: false,
                                         withOption: false))
    }

    /// The rule phase 3b was built around, restated for a gesture that is a BIGGER mis-click risk
    /// than a click: the operator is crossing the surface with a payload attached and a slot is a
    /// small target beside seven identical ones.
    func testADropOnAFilledSlotIsRejectedWithoutOption() {
        XCTAssertFalse(ShaderDrag.accepts(fromLibrary, on: .slot, isSlotFilled: true,
                                          withOption: false))
        XCTAssertFalse(ShaderDrag.accepts(fromDeck, on: .slot, isSlotFilled: true,
                                         withOption: false))
    }

    /// ⌥ is the ONE "I mean it" gesture on this surface. It already means overwrite for a click;
    /// it means the same for a drop rather than inventing a second modifier.
    func testOptionDragReplacesAFilledSlot() {
        XCTAssertTrue(ShaderDrag.accepts(fromLibrary, on: .slot, isSlotFilled: true,
                                         withOption: true))
    }

    // MARK: Which sources may reach which destinations

    func testALibraryShaderMayReachEveryNonSlotDestination() {
        for destination: ShaderDrag.Destination in [.deck(.one), .deck(.two),
                                                    .deckFX(.one), .deckFX(.two), .masterFX] {
            XCTAssertTrue(ShaderDrag.accepts(fromLibrary, on: destination,
                                             isSlotFilled: false, withOption: false),
                          "the library must be able to fill \(destination)")
        }
    }

    /// A deck is a source for CAPTURE and nothing else. Dropping deck A onto deck B is not a
    /// copy-shader gesture — it reads like one and would silently discard the dialled values that
    /// are the entire reason a look is worth capturing.
    func testADeckMayOnlyBeDroppedOnASlot() {
        XCTAssertTrue(ShaderDrag.accepts(fromDeck, on: .slot, isSlotFilled: false,
                                         withOption: false))
        for destination: ShaderDrag.Destination in [.deck(.two), .deckFX(.one), .masterFX] {
            XCTAssertFalse(ShaderDrag.accepts(fromDeck, on: destination,
                                              isSlotFilled: false, withOption: false),
                           "a deck must not be droppable on \(destination)")
        }
    }

    /// Banned this phase. Clicking a slot already loads it onto a deck; a drag would be a second
    /// way to fire a slot mid-set with no new capability, and twice the ways to do it by accident.
    func testASlotIsNotADragSource() {
        let fromSlot = ShaderDrag(source: .slot, url: url, snapshot: nil)
        for destination: ShaderDrag.Destination in [.slot, .deck(.one), .deckFX(.one), .masterFX] {
            XCTAssertFalse(ShaderDrag.accepts(fromSlot, on: destination,
                                              isSlotFilled: false, withOption: false))
        }
    }

    /// A capture carries the dialled values; a library drag cannot, because there are none yet.
    func testOnlyADeckDragCarriesASnapshot() {
        XCTAssertNil(fromLibrary.snapshot)
        XCTAssertNotNil(fromDeck.snapshot)
    }
}
```

- [ ] **Step 2: Run it — expect a compile failure** (`cannot find 'ShaderDrag' in scope`).

- [ ] **Step 3: Create the payload and the rules**

`App/ARShader/ShaderDrag.swift`:

```swift
import CoreTransferable
import UniformTypeIdentifiers

/// What a drag is carrying, and where it is allowed to land.
///
/// No SwiftUI import: the acceptance rules are the never-overwrite invariant restated for a
/// gesture, and that invariant must be testable with no view and no GPU in play — the same
/// doctrine `SurfaceLayout` and `SlotBank` follow.
struct ShaderDrag: Codable, Transferable, Sendable {
    enum Source: Codable, Equatable, Sendable {
        case library
        case deck(DeckID)
        /// Never a legal source this phase. Present so `accepts` can REJECT it explicitly rather
        /// than by omission — a rule you can read is a rule someone can find later.
        case slot
    }

    enum Destination: Equatable, Sendable {
        case slot
        case deck(DeckID)
        case deckFX(DeckID)
        case masterFX
    }

    let source: Source
    let url: URL
    /// The dialled values. Present only on a deck capture — a library shader has none yet.
    let snapshot: ParamSnapshot?

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .arshaderDrag)
    }

    /// The single acceptance rule. Every drop target asks this and nothing else, so there is one
    /// place the never-overwrite invariant lives.
    static func accepts(_ drag: ShaderDrag, on destination: Destination,
                        isSlotFilled: Bool, withOption option: Bool) -> Bool {
        switch drag.source {
        case .slot:
            return false
        case .deck:
            guard case .slot = destination else { return false }
            return !isSlotFilled || option
        case .library:
            guard case .slot = destination else { return true }
            return !isSlotFilled || option
        }
    }
}

extension UTType {
    static let arshaderDrag = UTType(exportedAs: "com.arshader.shader-drag")
}
```

The custom `UTType` must also be declared in the app target's `Info.plist` under
`UTExportedTypeDeclarations`, or the drag will silently never register. `App/project.yml` generates
the target — add it there, not to a generated plist.

- [ ] **Step 4: Run the tests — expect PASS.**

- [ ] **Step 5: Make library rows draggable and remove the picker**

In `LibraryPanelView`, delete the `Picker("Load onto", …)` block (lines 66-74) and the
`@Binding var target: LibraryTarget` with it. The row `Button` (77-88) loses its action —
`instrument.load(entry.url, onto: target)` goes — and becomes a plain draggable label:

```swift
            List(entries) { entry in
                Text(entry.name)
                    .font(.system(size: 12, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)   // long AR_Genuary names differ at the END
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .draggable(ShaderDrag(source: .library, url: entry.url, snapshot: nil))
                    .help("Drag onto a deck, an FX chain, or a slot")
            }
```

**This removes click-to-load entirely** — the spec's decision, and the reason the drag targets must
all land in this one task rather than being spread across several. A half-migrated library where
clicking does nothing and only some targets accept drops is unusable.

Then delete `@State private var libraryTarget` from `InstrumentView` and the argument from the
`LibraryPanelView(instrument:target:)` call site. Task 4 already removed the strip's use of it, so
this is the last reference.

- [ ] **Step 6: Add the drop targets**

Each target applies the same shape. Slot cells, in `SlotBankStripView`'s `ForEach`:

```swift
                                    .dropDestination(for: ShaderDrag.self) { items, _ in
                                        guard let drag = items.first,
                                              ShaderDrag.accepts(
                                                drag, on: .slot,
                                                isSlotFilled: bank.slots[index] != nil,
                                                withOption: NSEvent.modifierFlags.contains(.option))
                                        else {
                                            rejected = index      // drives the shake
                                            return false
                                        }
                                        bank.capture(Preset.capturing(url: drag.url,
                                                                      snapshot: drag.snapshot
                                                                        ?? ParamSnapshot(params: [:])),
                                                     into: index)
                                        return true
                                    } isTargeted: { targetedSlot = $0 ? index : nil }
```

Deck monitor tiles use `.deck(id)` and call `instrument.load(drag.url, onto: .deck(id), thenApply: drag.snapshot)`.
FX sections use `.deckFX(id)` / `.masterFX` and call `instrument.load` with the matching
`LibraryTarget` — the existing seam already appends a stage for those cases (`Instrument.swift:96-99`),
so no new append path is created.

- [ ] **Step 7: Both rejection signals**

Returning `false` from `dropDestination` already yields the no-entry cursor — that is the baseline,
not the answer. Add the second: a `@State private var rejected: Int?` that a refused drop sets, with
a brief `.offset` shake keyed on it, cleared after ~0.4s. **No dialog, no alert, nothing that steals
focus.** A rejected drop mid-set must cost zero attention beyond "that didn't take". The
highlight-on-valid-target comes from `isTargeted:` and must NOT fire for a target that would reject.

- [ ] **Step 8: Mutation-prove the invariant**

Change `accepts`'s `.library` branch to `return true` unconditionally. Expected:
`testADropOnAFilledSlotIsRejectedWithoutOption` FAILS. Revert. This is the single most important
mutation proof in the phase — it is the one that stops a mid-set drag destroying a dialled-in look.

- [ ] **Step 9: Full suite, re-record baselines, commit**

The library panel lost a control, so the panel baselines change. Same distinctness check as Task 3.

```bash
git add App/ARShader/ShaderDrag.swift App/ARShader/LibraryPanelView.swift \
        App/ARShader/SlotBankStripView.swift App/ARShader/MonitorView.swift \
        App/ARShader/FXChainView.swift App/ARShader/InstrumentView.swift \
        App/project.yml App/ARShaderTests/ShaderDragTests.swift App/ARShaderTests/Baselines
git commit -m "feat(3c): drag and drop from the library; a drop never overwrites a filled slot"
```

---

### Task 6: Drag and drop — deck monitor → slot

**Files:**
- Modify: `App/ARShader/MonitorView.swift` — deck tiles become drag SOURCES
- Test: `App/ARShaderTests/ShaderDragTests.swift` — capture-carries-values test

**Interfaces:**
- Consumes: `ShaderDrag` and `ShaderDrag.accepts` from Task 5, unchanged; `Instrument.currentPreset(of:)` (`Instrument.swift:138`).
- Produces: nothing new. This task adds one `.draggable` and the test that it carries the values.

This restores the capability Task 4 removed with the SOURCE picker, and **must land in the same
review cycle as Task 4** — between them there is no way to capture a look at all.

`MonitorTile` is keyed by `MonitorSource` (`InstrumentRenderer.swift:7-19`). Only deck tiles get
`.draggable`; **PROGRAM does not**, because `Instrument.currentPreset(of:)` takes a `DeckID` and
there is no such thing as the master's shader — the program feed is a composite of two decks and an
FX chain, and a "look" of it is not a `Preset`. Do not widen `currentPreset` to make this work.

- [ ] **Step 1: Write the failing test**

```swift
    /// Dragging a deck monitor to a slot must capture the LOOK — the shader AND the values dialled
    /// into it. A capture that carried only the URL would recall at header defaults, which is
    /// exactly the re-dialling-on-stage problem the slot bank exists to remove.
    func testADeckDragCarriesTheDialledValuesNotJustTheURL() throws {
        let snapshot = ParamSnapshot(params: ["speed": .float(0.87)])
        let drag = ShaderDrag(source: .deck(.one), url: url, snapshot: snapshot)
        let captured = Preset.capturing(url: drag.url,
                                        snapshot: try XCTUnwrap(drag.snapshot))
        XCTAssertEqual(captured.snapshot.params["speed"], .float(0.87))
    }
```

- [ ] **Step 2: Run it — expect PASS or FAIL depending on Task 5's shape.** If it already passes, that is fine and expected: Task 5 built the payload. Its value here is as a regression guard on the `snapshot` field surviving future edits — say so in the commit rather than pretending it was red first.

- [ ] **Step 3: Make deck tiles draggable**

In `MonitorTile`, for deck sources only:

```swift
            .draggable(dragPayload ?? ShaderDrag(source: .slot, url: URL(fileURLWithPath: "/"),
                                                 snapshot: nil))
```

is WRONG — a sentinel payload would be a rejected-drag that still starts a drag. Instead gate the
modifier itself, so a deck with no shader loaded is simply not draggable:

```swift
    @ViewBuilder
    private func draggableIfCapturable<V: View>(_ view: V) -> some View {
        if case .deck(let id) = source, let preset = instrument.currentPreset(of: id) {
            view.draggable(ShaderDrag(source: .deck(id), url: preset.shaderURL,
                                      snapshot: preset.snapshot))
        } else {
            view
        }
    }
```

`currentPreset(of:)` returns nil when the deck has no file behind it (`Instrument.swift:140`), so an
empty deck is not a drag source and no empty capture is possible.

- [ ] **Step 4: Run the full suite.**

- [ ] **Step 5: Mutation-prove.** Change the `.draggable` payload to pass `snapshot: nil`. Expected: `testADeckDragCarriesTheDialledValuesNotJustTheURL` still passes (it tests the type, not the view), so **add a second assertion at the view seam** — a test that builds the payload the way `draggableIfCapturable` does and asserts the snapshot is non-nil for a deck with a loaded shader. If you cannot make that test fail under the mutation, report it as structurally untestable rather than claiming a proof you do not have.

- [ ] **Step 6: Commit**

```bash
git add App/ARShader/MonitorView.swift App/ARShaderTests/ShaderDragTests.swift
git commit -m "feat(3c): drag a deck monitor to a slot to capture the live look"
```

---

### Task 7: Library hover preview

**Files:**
- Modify: `App/ARShader/LibraryPanelView.swift` — hover shows the still
- Test: `App/ARShaderTests/ThumbnailServiceTests.swift` — interactive-priority cancellation

**Interfaces:**
- Consumes: `ThumbnailService.thumbnail(for:priority:)` at `.interactive`, and `cancelInteractive()`.
- Produces: nothing downstream.

- [ ] **Step 1: Write the failing test** — a hover sweep must not leave queued work behind:

```swift
    /// Hover is superseded constantly as the pointer moves; a thumbnail for a row the pointer has
    /// left is wasted work. This is the OPPOSITE of the bank's requirement, which is why priority
    /// is a parameter rather than a policy baked into the service.
    func testAnInteractiveRequestSupersedesItsPredecessor() async throws {
        let service = ThumbnailService(cacheDirectory: try temporaryCacheDirectory())
        async let first = service.thumbnail(for: fixtureURL("slow"), priority: .interactive)
        await service.cancelInteractive()
        let result = await first
        XCTAssertEqual(result, .unavailable,
                       "a cancelled interactive request resolves as unavailable, never hangs")
    }

    /// And the guard that matters: cancelling hover work must not touch the bank's queue.
    func testCancellingInteractiveWorkLeavesBatchWorkAlone() async throws {
        let service = ThumbnailService(cacheDirectory: try temporaryCacheDirectory())
        async let batch = service.thumbnail(for: fixtureURL("solid_red"), priority: .batch)
        await service.cancelInteractive()
        if case .unavailable = await batch {
            XCTFail("Cancelling hover work must never drop a queued bank thumbnail — that leaves "
                    + "permanently blank cells only a resize or relaunch would fill.")
        }
    }
```

- [ ] **Step 2: Run — expect FAIL** until the hover path exists and the priorities are honoured.

- [ ] **Step 3: Add the hover preview.** `.onHover` on each library row requests at `.interactive` and shows the still in a fixed-size well at the panel's foot — not a floating popover, which would sit over the rows the operator is scanning. On hover-exit of the whole list, call `cancelInteractive()`.

- [ ] **Step 4: Run the suite. Mutation-prove:** make `cancelInteractive()` cancel everything. Expected: `testCancellingInteractiveWorkLeavesBatchWorkAlone` FAILS. Revert.

- [ ] **Step 5: Commit**

```bash
git add App/ARShader/LibraryPanelView.swift App/ARShaderTests/ThumbnailServiceTests.swift
git commit -m "feat(3c): library hover shows the shader's still"
```

---

### Task 8: Full regression, install, and the combined smoke report

**Files:**
- Modify: `docs/reports/live-smoke-instrument-m2-phase3b.md` — mark it superseded by the combined report
- Create: `docs/reports/live-smoke-instrument-m2-phase3c.md`

This task carries **phase 3b's unrun legs as well as phase 3c's**. Phase 3b was installed and its
report written, but only leg 17 was signed on device before 3c began; the remaining eighteen legs
would otherwise be run against a much larger diff, which is exactly how a defect gets attributed to
the wrong phase. Folding them here means one device session signs both phases, and the merge of
`m2-slot-bank` is gated on that one session rather than two.

- [ ] **Step 1: Run all three suites, foreground**

```bash
xcodebuild test -project App/TrueISFEditor.xcodeproj -scheme ARShader \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/arshader-ddata-bank \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=YES
xcodebuild test -project App/TrueISFEditor.xcodeproj -scheme TrueISFEditor \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/arshader-ddata-bank \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=YES
swift test --package-path ShadertoyISFKit --scratch-path /tmp/stkit-build-bank
```

Entering this plan the counts are ARShader **256**, TrueISFEditor **514 (3 skipped)**,
ShadertoyISFKit **312**. ARShader must be well ABOVE 256 by now; a count at or below it means a
task's tests were lost. TrueISFEditor and ShadertoyISFKit must be unchanged — this phase touches
neither, so any movement there is a real regression.

- [ ] **Step 2: Write the combined report with every leg UNRUN**

Legs 1–18 are phase 3b's, carried over verbatim from
`docs/reports/live-smoke-instrument-m2-phase3b.md` minus leg 17, which was signed 2026-07-31.
Legs 19–34 are phase 3c's. State every hypothesis so it can fail.

**Phase 3b, carried over (18 legs)**

| # | Leg | Hypothesis |
|---|---|---|
| 1 | Strip is always there | The bank is a strip under the monitors, not a panel. No third rail icon, no shortcut opens it. `⌘⌥1`/`⌘⌥2` still reach Library and Settings |
| 2 | Capture names the look | Clicking an empty cell captures the loaded shader and the cell takes that shader's name |
| 3 | Recall restores the LOOK | Dial a parameter well off its default before capturing. Recall: the shader loads AND the dialled values come back |
| 4 | Recall never overwrites | Click a filled slot ten times. It recalls ten times and its contents never change |
| 5 | Replace and Clear are deliberate | ⌥-click replaces; hover ▸ Replace replaces; hover ▸ Clear empties. The hover-revealed Replace sits OUTSIDE the recall click target |
| 6 | SOURCE picks the read deck | **Superseded by task 5 — the SOURCE picker is gone.** Re-scoped: dragging DECK B's monitor to a slot captures B's look, whatever is on A |
| 7 | RECALL TO picks the write target | **Re-scoped by task 4** — RECALL TO is now A\|B only. Set it to B and fire a slot: it loads onto deck B, never onto an FX chain |
| 8 | The bank persists | Quit and relaunch: every captured look is back, and so are the row count and the collapsed state |
| 9 | A missing file is dark, not destroyed | Rename a captured shader's file on disk, relaunch: the slot draws unavailable, clicking does nothing, and the slot is still there. Rename back: it works again |
| 10 | Eight cells legible at full width | At a normal window size all eight cells in a row are readable |
| 11 | Cells never overlap when narrow | Minimum window, Library panel open at its 260pt floor. Cells scroll horizontally rather than compressing. Clicking the extreme left and right edge of a cell fires THAT cell, never its neighbour |
| 12 | Recall twice does not black-frame | Fire the same slot twice. A brief recompile flash is accepted; a persistent black frame is a defect |
| 13 | Resize adds rows, monitors hold still | Drag the strip's top edge upward: whole rows, up to five. The monitor row does not resize and does not slide |
| 14 | Shrinking never destroys a look | Capture into row 2, shrink to one row, grow back: the look is there, unchanged |
| 15 | Show mode cannot collapse the bank | Collapse by hand, then `⌘⇧P`: show mode leaves the bank exactly as it is |
| 16 | Collapse remembers the rows | Three rows, collapse, expand: three rows come back |
| 18 | A failed compile does not corrupt a slot | Recall a slot whose shader has been edited into something that will not compile. The previous shader keeps playing, its dialled values are NOT overwritten, and a subsequent capture names the shader actually PLAYING |
| 19 | The suite never touches the real bank | After running the automated suite, relaunch: the operator's bank is untouched |

Leg 17 (the collapsed bank marks every hidden look) was signed on device 2026-07-31 and is not
repeated. Legs 6 and 7 are re-scoped rather than dropped, because this phase removes the controls
they tested — an unmodified leg 6 would be untestable and would read as a failure.

- [ ] **Step 3: Do NOT install without announcing**

Installing quits the operator's running ARShader. Announce first and install on his word.
**Then present the rebuild before handing over the legs:** what this build adds over the one he is
running, the single fastest gesture that discriminates new from old, and what is deliberately not in
it yet. A build whose changes are invisible at rest needs this most.

- [ ] **Step 4: Commit**

```bash
git add docs/reports/live-smoke-instrument-m2-phase3c.md \
        docs/reports/live-smoke-instrument-m2-phase3b.md
git commit -m "docs(3c): combined live smoke report — 3b's remaining legs folded in, all PENDING"
```

**Phase 3c legs (16 new)**

| # | Leg | Hypothesis |
|---|---|---|
| 20 | Slots show pictures | Every filled slot draws a still frame of its shader, not a name-only cell. A slot captured this session gets one within a second or two, not on next launch |
| 21 | The still is not black | Sample time is 2.0s specifically because many shaders are black at t=0. Fill eight slots with visually different shaders: eight distinguishable, non-black stills |
| 22 | Live reads as live at a glance | With a slot's shader loaded on deck A, that cell has a coloured border and an **A** badge. Load the same shader on B: the badge follows. This must be readable without leaning in |
| 23 | Idle vs live survives a photo | **The finding-8 leg.** Use a near-monochrome shader (an ASCII one) AND a fully saturated one. Both must read as clearly live-vs-idle. Saturation is no longer the carrier — if you cannot tell, that is a real defect, not a preference |
| 24 | Unavailable is obvious and keeps its picture | Rename a captured shader's file, relaunch: that cell is dimmed with a warning glyph, **still shows its last thumbnail**, and does not fire. You can tell WHICH look is broken |
| 25 | Thumbnails survive relaunch | Quit and relaunch: stills appear immediately from cache, not regenerated |
| 26 | A broken shader does not stutter | Point a slot at a shader that will not compile. Hover and re-hover its library row repeatedly: no repeated hitch. It compiles once and the failure is remembered |
| 27 | Fixing a shader on disk retries it | Fix that shader in an editor and save. Its thumbnail regenerates rather than staying a permanent placeholder |
| 28 | Thumbnails never cost a frame | With the instrument playing and output OPEN, sweep the pointer down the whole library. **FPS must not drop and the program feed must not hitch.** This is the leg the entire GPU-queue isolation exists for |
| 29 | Library drag to a deck | Drag a library row onto DECK A's monitor: it loads there. Same onto B |
| 30 | Library drag to FX | Drag a library row onto a deck's FX section, and onto MASTER FX: each appends a stage |
| 31 | Library drag to an empty slot | Drop fills it, no confirmation |
| 32 | **A drag never destroys a look** | Dial a look, capture it, then drag a DIFFERENT library shader onto that filled slot. **The drop is refused, the slot is unchanged, and you see it refuse** — cursor during the drag, and a shake on the attempt. Then ⌥-drag the same shader: now it replaces |
| 33 | Deck monitor to slot captures the look | Dial deck B well off defaults, drag B's monitor to an empty slot, change B, then fire the slot: the dialled values come back |
| 34 | Rejected drops are visibly rejected | Drag a deck monitor onto MASTER FX, and onto another deck. Both refuse, visibly. Drag a slot anywhere: nothing drags at all |
| 35 | Clicking the library does nothing | Click-to-load is gone. A click on a library row must not load anything anywhere — if it does, the removal was incomplete |
| 36 | Projector is never soft | Open the output on the external display. Set PREVIEW SCALE to 25%. **The projected image stays sharp** while the app's monitor tiles get cheap. Close the output: the saving comes back. This is the phase's behavioural correction and the one leg with a wall as its assertion |
| 37 | Panel has a ceiling, not just a floor | **Phase 3a fix, merged to master unsigned.** Drag the panel divider hard right, past the window edge: the panel stops at a ceiling clamped against the window rather than starving the deck strips and pushing the mixer off-screen |
| 38 | Window minimum holds | **Phase 3a fix, unsigned.** Shrink the window as far as macOS allows: the mixer strip still fits and nothing is clipped |
| 39 | Panel width survives a window shrink | **Phase 3a fix, unsigned.** Set a wide panel, shrink the window so the panel must give way, then widen the window again: the panel returns to the width you set rather than staying pinned at its floor |

---

## Known Issues Entering This Plan

Carried from phase 3b's handoff. Neither blocks execution; both should be resolved before the merge.

- **`SurfaceMetrics.stripsMinWidth` (620) is stale.** The slot strip's own intrinsic minimum is ~655,
  and `testTheReservedWidthMatchesTheRegionsItClaimsToCover` compares two constants **to each other**
  rather than either to reality — the same failure mode `minWindowWidth`'s own comment documents.
  Task 4 removes a control from the strip and Task 3 widens the cells, so this number moves twice
  during this plan. **Fix it in Task 4**, after the strip's final width is known, and change the
  test to measure the rendered strip rather than compare constants.
- **Five Client Success reviews are stacked, unrun.** The standing recommendation is ONE combined
  review of the whole instrument surface rather than five overlapping ones. Phase 3c changes the
  surface substantially, so the combined review belongs after Task 8, not before.

---

## Self-Review

**Spec coverage.** Still frames → Tasks 1, 3, 7. Drag and drop as the universal verb → Tasks 5, 6,
including the occupancy rule and the full rejected-drop matrix. Library hover preview and picker
removal → Tasks 5, 7. `RECALL TO: A | B` with a type-level constraint → Task 4. The preview/program
split → Task 2. Thumbnail cache key, invalidation, eviction, concurrency bound, queue isolation,
`t = 2.0s` → Task 1. The re-derived three cell states → Task 3, with the visual leg in Task 8
(leg 23) because "distinguishable at a glance" is not a unit assertion. Out-of-scope items (MIDI,
randomisation, named presets, animated previews) are touched by no task.

**Placeholder scan.** No TBD/TODO. Every code step carries real code. Task 6 Step 2 explicitly says
its test may pass immediately and instructs the implementer to say so rather than fake a red-green
cycle; Task 6 Step 5 says to report a mutation as structurally unprovable rather than claim a proof.
Those are honest reports, not placeholders.

**Type consistency.** `ThumbnailService.Result` (`.image(Data)` / `.unavailable`) and
`ThumbnailCache.Entry` are deliberately separate types with the same shape — the cache's is a disk
concern, the service's is an API concern — and Task 1 converts between them explicitly in
`thumbnail(for:priority:)`. `ThumbnailService.Priority` is used identically in Tasks 1, 3, 7.
`ShaderDrag.accepts(_:on:isSlotFilled:withOption:)` is used identically in Tasks 5 and 6.
`SlotCellState.of(preset:isAvailable:liveOn:)` is used identically in Tasks 3 and 5.
`InstrumentRenderer.isProgramLive` is used identically in Task 2's tests and
`OutputWindowController`. `Instrument.load(_:onto:thenApply:)` is unchanged by every task.

**Symbols verified against the tree before this plan was committed** — none of these are assumed:

| Symbol | Confirmed at |
|---|---|
| `let liveRes = renderScale.applied(to: outRes)` | `InstrumentRenderer.swift:371` |
| `let isLive = layer.effectiveOpacity > 0` | `InstrumentRenderer.swift:396` |
| `reallocateMastersLocked()` | `InstrumentRenderer.swift:284-294` |
| `previewScale` (the lock-guarded property template) | `InstrumentRenderer.swift:239-262` |
| `OutputWindowController.setDestination(_:)` | `OutputWindowController.swift:40-43` |
| `OutputSharpness.isProjectingUpscaled(destination:scale:)` | `OutputDestination.swift:74-84` |
| `OutputDestination.launchDefault == .off` | `OutputDestination.swift` |
| `RenderScale` (`percent`, `applied(to:)`, `presets`) | `App/ISFRuntime/RenderScale.swift:12` |
| `SlotCell` (init, `activate()`, context menu) | `SlotBankStripView.swift:233-308` |
| `SurfaceMetrics.minCellWidth = 56` | `InstrumentSurface.swift:108` |
| `LibraryTarget` (3 cases, 5 `allCases`) | `LibraryPanelView.swift:4-25` |
| The five-way picker and click-to-load | `LibraryPanelView.swift:66-89` |
| `Instrument.load(_:onto:thenApply:)` | `Instrument.swift:90-101` |
| `Instrument.currentPreset(of:)` | `Instrument.swift:138-142` |
| `FXChain.append(_:)` via `Instrument.append` | `Instrument.swift:103-108`, `FXChain.swift:33-36` |
| `MonitorTile` / `MonitorSource` | `MonitorView.swift:169-257`, `InstrumentRenderer.swift:7-19` |
| `ISFSceneLoader.load(source:device:)` | `App/ISFRuntime/ISFSceneLoader.swift:37-59` |
| `ISFMSLSafeRenderAtTime(scene, size, time:, cb, &err)` | `App/ISFRuntime/ISFMSLSafeBridge.h:39-43` |
| `TextureReadback.managedCopy(of:device:queue:)` | `App/ISFRuntime/TextureReadback.swift:6-24` |
| `FramePNGEncoder.encodePNG` | `App/ISFRuntime/FramePNGEncoder.swift:14-99` |
| `RenderProperties.global()` → `.device`, `.renderQueue`, `.bgCmdQueue` | `vendor/prebuilt/VVMetalKit.framework` |
| `LibraryEntry` (`url`, `dateModified`) | `App/ISFRuntime/LibraryModel.swift:4-16` |
| `SnapshotStore.documentKey(for:)` (cache-key precedent) | `App/TrueISFEditor/Models/SnapshotStore.swift:57-65` |
| Fixtures `solid_red.fs`, `solid_green.fs`, `broken.fs` | `App/ARShaderTests/Fixtures/` |
| The seven render-scale tests | `FrameGraphTests.swift:320-418`, `InstrumentRendererTests.swift:13-20` |

**Two facts an implementer would otherwise have to discover the hard way:**

1. **There is no drag-and-drop anywhere in this codebase** — confirmed by exhaustive grep for
   `.draggable`, `.dropDestination`, `onDrag`, `onDrop`, `NSItemProvider`, `UTType`, `Transferable`.
   Task 5 establishes the pattern from nothing.
2. **There are no `actor` types anywhere in this app.** Task 1 introduces the first, and says why.

**One ordering constraint that is not negotiable:** Tasks 4 and 6 must land in the same review
cycle. Task 4 removes the SOURCE picker and Task 6 replaces it with the deck-monitor drag; between
them there is no way to capture a look at all.
