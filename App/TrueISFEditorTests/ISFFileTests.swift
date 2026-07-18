import XCTest

final class ISFFileTests: XCTestCase {
    func test_untitled_hasUnsavedWorkBeforeEdit_andNeedsSaveAs() {
        var f = ISFFile.untitled(suggestedName: "Remixed shader")
        XCTAssertNil(f.url)
        XCTAssertFalse(f.isDirty)
        XCTAssertTrue(f.needsSaveAs)
        XCTAssertTrue(f.hasUnsavedWork,
                      "an imported/untitled document needs a visible Save As cue before any edit")
        f.source = "void main(){}"
        XCTAssertTrue(f.isDirty)
        XCTAssertTrue(f.hasUnsavedWork)
        XCTAssertEqual(f.displayName, "Remixed shader.fs")
    }

    func test_saveToURL_clearsDirtyAndUnsavedWork_andWritesFile() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("isffile-\(UUID()).fs")
        defer { try? FileManager.default.removeItem(at: tmp) }
        var f = ISFFile.untitled()
        f.source = "X"
        try f.save(to: tmp)
        XCTAssertEqual(f.url, tmp)
        XCTAssertFalse(f.isDirty)
        XCTAssertFalse(f.needsSaveAs)
        XCTAssertFalse(f.hasUnsavedWork)
        XCTAssertEqual(try String(contentsOf: tmp, encoding: .utf8), "X")
        f.source = "Y"
        XCTAssertTrue(f.isDirty)
        XCTAssertTrue(f.hasUnsavedWork,
                      "ordinary edits to a saved file must raise the same visible save cue")
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
