import XCTest
import Metal

@MainActor
final class LibraryPanelTests: XCTestCase {
    private func makeModel(with names: [String]) throws -> (LibraryModel, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("arshader-lib-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for n in names {
            try """
            /*{
                "ISFVSN": "2.0",
                "DESCRIPTION": "library fixture",
                "CATEGORIES": ["Test"],
                "INPUTS": []
            }*/

            void main() { gl_FragColor = vec4(1.0, 1.0, 1.0, 1.0); }
            """.write(to: dir.appendingPathComponent(n), atomically: true, encoding: .utf8)
        }
        let model = LibraryModel()
        model.addFolder(dir, title: "Test")
        return (model, dir)
    }

    func testSearchRequiresEveryTokenToMatch() throws {
        let (model, dir) = try makeModel(with: [
            "AR_Genuary2026_Day14.fs", "AR_Genuary2026_Day02.fs", "AR_Devolution_Kindling.fs"
        ])
        defer { try? FileManager.default.removeItem(at: dir) }

        let selection = LibrarySelection()
        selection.query = "genuary 14"
        XCTAssertEqual(selection.results(in: model).map(\.name), ["AR_Genuary2026_Day14.fs"])

        selection.query = "genuary"
        XCTAssertEqual(selection.results(in: model).count, 2)

        selection.query = ""
        XCTAssertEqual(selection.results(in: model).count, 3)
    }

    func testSearchIsCaseInsensitiveAndOrderIndependent() throws {
        let (model, dir) = try makeModel(with: ["AR_Genuary2026_Day14.fs"])
        defer { try? FileManager.default.removeItem(at: dir) }
        let selection = LibrarySelection()
        selection.query = "14 GENUARY"
        XCTAssertEqual(selection.results(in: model).count, 1)
    }

    func testSortOrderIsHonoured() throws {
        let (model, dir) = try makeModel(with: ["b.fs", "a.fs", "c.fs"])
        defer { try? FileManager.default.removeItem(at: dir) }
        let selection = LibrarySelection()
        selection.sort = .name
        XCTAssertEqual(selection.results(in: model).map(\.name), ["a.fs", "b.fs", "c.fs"])
    }

    func testLoadingAnEntryPutsItOnTheTargetDeck() throws {
        let (model, dir) = try makeModel(with: ["loadme.fs"])
        defer { try? FileManager.default.removeItem(at: dir) }
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let queue = try XCTUnwrap(device.makeCommandQueue())
        let deck = Deck(id: .one, device: device, queue: queue, clock: RenderClock())

        let entry = try XCTUnwrap(model.filtered(query: "loadme").first)
        let done = expectation(description: "load")
        deck.onCompileFinished = { done.fulfill() }
        deck.load(url: entry.url)
        wait(for: [done], timeout: 30)

        XCTAssertNil(deck.compileError)
        XCTAssertEqual(deck.shaderName, "loadme.fs")
    }

    func testAnUnreadableEntryReportsRatherThanCrashing() throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let queue = try XCTUnwrap(device.makeCommandQueue())
        let deck = Deck(id: .one, device: device, queue: queue, clock: RenderClock())
        deck.load(url: URL(fileURLWithPath: "/nonexistent/nope.fs"))
        XCTAssertNotNil(deck.compileError)
        XCTAssertNil(deck.shaderName)
    }

    func testTheInstrumentLibraryIsSkippedUnderTheTestHarness() {
        // The suite must never scan the user's real folders: a persisted folder in a TCC-protected
        // location would block the run behind a permission prompt.
        XCTAssertTrue(TestHarness.isActive)
        let model = LibraryModel()
        model.loadInstrumentLibraries()
        XCTAssertTrue(model.sources.isEmpty)
    }
}
