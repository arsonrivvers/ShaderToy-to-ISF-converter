import XCTest

@MainActor
final class CrashLogTests: XCTestCase {
    private func tempDir() -> URL {
        let u = FileManager.default.temporaryDirectory.appendingPathComponent("crashlog-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    func test_recordPersistsAndReloads() {
        let dir = tempDir()
        let log = CrashLog(directory: dir)
        log.record(CrashEvent(kind: .compile, message: "boom", context: "ShaderA"))
        let reloaded = CrashLog(directory: dir)
        XCTAssertEqual(reloaded.events.count, 1)
        XCTAssertEqual(reloaded.events.first?.message, "boom")
        XCTAssertEqual(reloaded.events.first?.context, "ShaderA")
    }

    func test_consecutiveDuplicatesDeduped() {
        let log = CrashLog(directory: tempDir())
        log.record(CrashEvent(kind: .compile, message: "same", context: "X"))
        log.record(CrashEvent(kind: .compile, message: "same", context: "X"))
        log.record(CrashEvent(kind: .render, message: "same", context: "X")) // different kind ⇒ kept
        XCTAssertEqual(log.events.count, 2)
    }

    func test_capAt500() {
        let log = CrashLog(directory: tempDir())
        for i in 0..<600 { log.record(CrashEvent(kind: .compile, message: "e\(i)")) }
        XCTAssertEqual(log.events.count, 500)
        XCTAssertEqual(log.events.last?.message, "e599")
    }

    func test_codableRoundTrip() throws {
        let e = CrashEvent(kind: .signal, message: "SIGSEGV", context: nil, detail: "frame0\nframe1")
        let data = try JSONEncoder().encode(e)
        let back = try JSONDecoder().decode(CrashEvent.self, from: data)
        XCTAssertEqual(back, e)
    }

    func test_ingestPendingCreatesEventAndDeletesFile() {
        let dir = tempDir()
        let pending = dir.appendingPathComponent("pending-crash.log")
        try? "SIGNAL SIGSEGV 1700000000\nframe0\nframe1".write(to: pending, atomically: true, encoding: .utf8)
        let log = CrashLog(directory: dir)
        XCTAssertTrue(log.crashedLastSession)
        XCTAssertEqual(log.events.count, 1)
        XCTAssertEqual(log.events.first?.kind, .signal)
        XCTAssertEqual(log.events.first?.detail, "frame0\nframe1")
        XCTAssertFalse(FileManager.default.fileExists(atPath: pending.path))
    }

    func test_clearEmptiesAndPersists() {
        let dir = tempDir()
        let log = CrashLog(directory: dir)
        log.record(CrashEvent(kind: .render, message: "x"))
        log.clear()
        XCTAssertTrue(log.events.isEmpty)
        XCTAssertTrue(CrashLog(directory: dir).events.isEmpty)
    }
}
