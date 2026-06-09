import XCTest

final class LibraryModelTests: XCTestCase {
    private func makeDir(_ files: [String]) throws -> URL {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        for f in files {
            try "x".write(to: d.appendingPathComponent(f), atomically: true, encoding: .utf8)
        }
        return d
    }

    func test_scan_listsOnlyFSFiles_sortedCaseInsensitive() throws {
        let d = try makeDir(["b.fs", "a.fs", "note.txt", "c.FS"])
        let entries = LibraryModel.scan(folder: d)
        XCTAssertEqual(entries.map(\.name), ["a.fs", "b.fs", "c.FS"])
    }

    func test_filter_byName_caseInsensitive() throws {
        let d = try makeDir(["Kaleido.fs", "ascii.fs"])
        let m = LibraryModel()
        m.addFolder(d)
        XCTAssertEqual(m.filtered(query: "kal").map(\.name), ["Kaleido.fs"])
        XCTAssertEqual(m.filtered(query: "").count, 2)
    }

    func test_addFolder_isIdempotent() throws {
        let d = try makeDir(["a.fs"])
        let m = LibraryModel()
        m.addFolder(d)
        m.addFolder(d)
        XCTAssertEqual(m.sources.count, 1)
    }

    func test_entriesForSource() throws {
        let d = try makeDir(["x.fs", "y.fs"])
        let m = LibraryModel()
        m.addFolder(d, title: "T")
        let src = try XCTUnwrap(m.sources.first)
        XCTAssertEqual(src.title, "T")
        XCTAssertEqual(m.entries(for: src).map(\.name), ["x.fs", "y.fs"])
    }
}
