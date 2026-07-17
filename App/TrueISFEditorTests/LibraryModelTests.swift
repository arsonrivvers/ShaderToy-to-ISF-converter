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

    /// Multi-word queries are token-AND, any order, case-insensitive — "genuary 14" must match
    /// "Genuary2026_Day14.fs" (the old single-substring filter returned nothing for it).
    func test_filter_tokensMatchInAnyOrder() throws {
        let d = try makeDir(["Genuary2026_Day14.fs", "Genuary2026_Day02.fs", "ascii_14.fs"])
        let m = LibraryModel()
        m.addFolder(d)
        XCTAssertEqual(m.filtered(query: "genuary 14").map(\.name), ["Genuary2026_Day14.fs"])
        XCTAssertEqual(m.filtered(query: "14 genuary").map(\.name), ["Genuary2026_Day14.fs"])
        XCTAssertEqual(m.filtered(query: "14").count, 2)
        XCTAssertEqual(m.filtered(query: "genuary zzz").count, 0)
    }

    func test_sort_recentlyAddedAndModified() {
        let old = LibraryEntry(url: URL(fileURLWithPath: "/a/old.fs"),
                               dateAdded: Date(timeIntervalSince1970: 100),
                               dateModified: Date(timeIntervalSince1970: 900))
        let new = LibraryEntry(url: URL(fileURLWithPath: "/a/new.fs"),
                               dateAdded: Date(timeIntervalSince1970: 500),
                               dateModified: Date(timeIntervalSince1970: 200))
        XCTAssertEqual(LibraryModel.sorted([old, new], by: .recentlyAdded).map(\.name),
                       ["new.fs", "old.fs"])
        XCTAssertEqual(LibraryModel.sorted([new, old], by: .recentlyModified).map(\.name),
                       ["old.fs", "new.fs"])
        XCTAssertEqual(LibraryModel.sorted([old, new], by: .name).map(\.name),
                       ["new.fs", "old.fs"])
    }

    func test_scan_populatesFileDates() throws {
        let d = try makeDir(["a.fs"])
        let entry = try XCTUnwrap(LibraryModel.scan(folder: d).first)
        XCTAssertGreaterThan(entry.dateAdded, .distantPast)
        XCTAssertGreaterThan(entry.dateModified, .distantPast)
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
