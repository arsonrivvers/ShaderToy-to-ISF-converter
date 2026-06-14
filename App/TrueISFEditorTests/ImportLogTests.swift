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
