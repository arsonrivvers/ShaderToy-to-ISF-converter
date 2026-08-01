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
    ///
    /// I5 (round-1 review): the original version touched `shaders[4]` — already the newest by
    /// WRITE order — so the assertions held even with the read-touch deleted entirely; it proved
    /// FIFO-by-write-order, not LRU-by-use. This version touches the OLDEST entry (`shaders[0]`)
    /// so it becomes the most recently MODIFIED despite being the least recently WRITTEN. If the
    /// touch in `entry()` did nothing, `shaders[0]` would be evicted (it's the oldest write) and
    /// `shaders[3]` would survive (the second-newest write) — the opposite of what's asserted.
    func testEvictionDropsTheLeastRecentlyUsedAboveTheCeiling() throws {
        let (cache, _) = try makeCache()
        var shaders: [URL] = []
        for i in 0..<5 {
            let s = try shaderFile("// \(i)")
            try cache.store(.image(Data([UInt8(i)])), for: s)
            shaders.append(s)
        }
        _ = try cache.entry(for: shaders[0])          // touch the OLDEST write
        try cache.evict(keepingAtMost: 2)
        XCTAssertNotNil(try cache.entry(for: shaders[0]),
                        "touched after being written oldest — survives because it was USED, not written, last")
        XCTAssertNotNil(try cache.entry(for: shaders[4]), "the most recently WRITTEN entry survives")
        XCTAssertNil(try cache.entry(for: shaders[3]),
                     "would have survived under write-order alone (2nd-newest write), but was never touched")
        XCTAssertNil(try cache.entry(for: shaders[1]), "never touched, never recently written — gone")
    }
}
