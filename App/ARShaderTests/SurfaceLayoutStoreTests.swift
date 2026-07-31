import XCTest

@MainActor
final class SurfaceLayoutStoreTests: XCTestCase {

    private func makeDefaults() throws -> UserDefaults {
        let suite = "arshader-surface-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return defaults
    }

    func testAnUnwrittenStoreReturnsTheDefaultArrangement() throws {
        let store = SurfaceLayoutStore(defaults: try makeDefaults())
        XCTAssertEqual(store.load(), .default,
                       "First launch gets the default arrangement, never an empty one")
    }

    func testASavedArrangementSurvivesAReload() throws {
        let defaults = try makeDefaults()
        var saved = Arrangement.default
        saved.openPanel = .settings
        saved.panelWidth = 412
        saved.expanded[.deck(.two, .fx)] = false

        SurfaceLayoutStore(defaults: defaults).save(saved)

        // A SEPARATE store instance — this is the relaunch, not a cache read.
        XCTAssertEqual(SurfaceLayoutStore(defaults: defaults).load(), saved)
    }

    func testCorruptStoredDataFallsBackToTheDefaultRatherThanCrashing() throws {
        let defaults = try makeDefaults()
        defaults.set(Data("not json".utf8), forKey: SurfaceLayoutStore.key)

        XCTAssertEqual(SurfaceLayoutStore(defaults: defaults).load(), .default,
                       "A corrupt arrangement must not take the instrument down at launch")
    }
}
