import XCTest
@testable import TrueISFEditor

final class LineDiffTests: XCTestCase {
    // MARK: changeMarks — gutter bars vs the last save

    func testChangeMarksPureInsertionIsAdded() {
        let m = LineDiff.changeMarks(old: "a\nb", new: "a\nX\nb")
        XCTAssertEqual(m.added, [2])
        XCTAssertEqual(m.changed, [])
    }

    func testChangeMarksReplacementIsChanged() {
        let m = LineDiff.changeMarks(old: "a\nOLD\nc", new: "a\nNEW\nc")
        XCTAssertEqual(m.added, [])
        XCTAssertEqual(m.changed, [2])
    }

    func testChangeMarksReplaceRunPlusGrowth() {
        // 2 lines became 3: the first two pair as changed, the overflow is added.
        let m = LineDiff.changeMarks(old: "a\nx\ny\nz", new: "a\nX2\nY2\nEXTRA\nz")
        XCTAssertEqual(m.changed, [2, 3])
        XCTAssertEqual(m.added, [4])
    }

    func testChangeMarksIdenticalIsEmpty() {
        let m = LineDiff.changeMarks(old: "a\nb", new: "a\nb")
        XCTAssertEqual(m.added, []); XCTAssertEqual(m.changed, [])
    }

    // MARK: rangeSummary — collapses the changed-lines wall of numbers into ranges

    func testRangeSummaryCollapsesConsecutiveRuns() {
        XCTAssertEqual(LineDiff.rangeSummary([7, 17, 18, 29, 30, 64]), "7, 17–18, 29–30, 64")
    }

    func testRangeSummarySortsAndDeduplicates() {
        XCTAssertEqual(LineDiff.rangeSummary([3, 1, 2, 2, 10]), "1–3, 10")
    }

    func testRangeSummarySingleAndEmpty() {
        XCTAssertEqual(LineDiff.rangeSummary([5]), "5")
        XCTAssertEqual(LineDiff.rangeSummary([]), "")
    }

    func testIdenticalTextsAreAllSame() {
        let d = LineDiff.diff(old: "a\nb\nc", new: "a\nb\nc")
        XCTAssertEqual(d.map(\.kind), [.same, .same, .same])
        XCTAssertEqual(d.map(\.oldLine), [1, 2, 3])
        XCTAssertEqual(d.map(\.newLine), [1, 2, 3])
    }

    func testPureInsertion() {
        let d = LineDiff.diff(old: "a\nc", new: "a\nb\nc")
        XCTAssertEqual(d.map(\.kind), [.same, .added, .same])
        XCTAssertEqual(d[1].text, "b")
        XCTAssertNil(d[1].oldLine)
        XCTAssertEqual(d[1].newLine, 2)
    }

    func testPureDeletion() {
        let d = LineDiff.diff(old: "a\nb\nc", new: "a\nc")
        XCTAssertEqual(d.map(\.kind), [.same, .removed, .same])
        XCTAssertEqual(d[1].oldLine, 2)
        XCTAssertNil(d[1].newLine)
    }

    func testChangedLineIsRemovePlusAdd() {
        let d = LineDiff.diff(old: "a\nOLD\nc", new: "a\nNEW\nc")
        XCTAssertEqual(d.map(\.kind), [.same, .removed, .added, .same])
        XCTAssertEqual(d[1].text, "OLD")
        XCTAssertEqual(d[2].text, "NEW")
    }

    func testEmptyOldIsAllAdded() {
        let d = LineDiff.diff(old: "", new: "x\ny")
        // "" splits to one empty line — it pairs or removes, but every content line must be added.
        XCTAssertEqual(d.filter { $0.kind == .added }.map(\.text).filter { !$0.isEmpty }, ["x", "y"])
    }

    func testDisplayRowsFoldLongSameRuns() {
        let old = (1...30).map(String.init).joined(separator: "\n")
        let new = old + "\nEXTRA"
        let rows = LineDiff.displayRows(LineDiff.diff(old: old, new: new), context: 3)
        // 30 same lines then one added: the same-run folds to 3 + fold(24) + 3.
        guard case .fold(let count, _)? = rows.first(where: {
            if case .fold = $0 { return true } else { return false }
        }) else { return XCTFail("expected a fold row") }
        XCTAssertEqual(count, 24)
        // Changed line always survives folding.
        XCTAssertTrue(rows.contains { if case .line(let l) = $0 { return l.text == "EXTRA" } else { return false } })
    }

    func testShortSameRunsDoNotFold() {
        let rows = LineDiff.displayRows(LineDiff.diff(old: "a\nb\nc\nX", new: "a\nb\nc\nY"), context: 3)
        XCTAssertFalse(rows.contains { if case .fold = $0 { return true } else { return false } })
    }
}
