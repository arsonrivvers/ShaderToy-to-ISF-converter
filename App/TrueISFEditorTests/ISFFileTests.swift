import XCTest

final class ISFFileTests: XCTestCase {
    func test_untitled_isDirtyAfterEdit_andNeedsSaveAs() {
        var f = ISFFile.untitled()
        XCTAssertNil(f.url)
        XCTAssertFalse(f.isDirty)
        f.source = "void main(){}"
        XCTAssertTrue(f.isDirty)
        XCTAssertTrue(f.needsSaveAs)
        XCTAssertEqual(f.displayName, "Untitled.fs")
    }

    func test_saveToURL_clearsDirty_andWritesFile() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("isffile-\(UUID()).fs")
        var f = ISFFile.untitled()
        f.source = "X"
        try f.save(to: tmp)
        XCTAssertEqual(f.url, tmp)
        XCTAssertFalse(f.isDirty)
        XCTAssertFalse(f.needsSaveAs)
        XCTAssertEqual(try String(contentsOf: tmp, encoding: .utf8), "X")
    }

    func test_open_loadsSourceClean() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("open-\(UUID()).fs")
        try "BODY".write(to: tmp, atomically: true, encoding: .utf8)
        let f = try ISFFile(contentsOf: tmp)
        XCTAssertEqual(f.source, "BODY")
        XCTAssertFalse(f.isDirty)
        XCTAssertEqual(f.displayName, tmp.lastPathComponent)
    }

    func test_saveAfterReopen_writesBackToSameURL() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("resave-\(UUID()).fs")
        try "ONE".write(to: tmp, atomically: true, encoding: .utf8)
        var f = try ISFFile(contentsOf: tmp)
        f.source = "TWO"
        XCTAssertTrue(f.isDirty)
        try f.save()
        XCTAssertFalse(f.isDirty)
        XCTAssertEqual(try String(contentsOf: tmp, encoding: .utf8), "TWO")
    }
}
