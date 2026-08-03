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

