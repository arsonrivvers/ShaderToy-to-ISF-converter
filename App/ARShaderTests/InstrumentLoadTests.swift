import XCTest
@testable import ARShader

@MainActor
final class InstrumentLoadTests: XCTestCase {

    /// A real, compilable ISF file on disk. The unit reads the file, so a fake path will not do.
    /// Non-private: Task 5's capture tests reuse this to produce loadable fixtures.
    func makeShaderFile(_ name: String = "probe") throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(name)-\(UUID().uuidString).fs")
        try """
        /*{ "DESCRIPTION": "test", "ISFVSN": "2", "INPUTS": [
            { "NAME": "speed", "TYPE": "float", "MIN": 0.0, "MAX": 1.0, "DEFAULT": 0.5 }
        ] }*/
        void main() { gl_FragColor = vec4(speed, 0.0, 0.0, 1.0); }
        """.write(to: url, atomically: true, encoding: .utf8)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    func testAFreshUnitHasNoSourceURL() {
        let instrument = Instrument()
        XCTAssertNil(instrument.deck(.one).unit.sourceURL,
                     "Nothing has been loaded, so there is no file behind the deck")
    }

    func testLoadingFromAURLRetainsIt() throws {
        let instrument = Instrument()
        let url = try makeShaderFile()
        instrument.deck(.one).unit.load(url: url)
        XCTAssertEqual(instrument.deck(.one).unit.sourceURL, url,
                       "Capture needs the URL, and lastPathComponent is not enough — filenames "
                       + "are not unique across the corpus")
    }

    /// Judgment call (Task 4 brief step 5): the brief's two required tests never exercise the
    /// `load(source:name:)` clear. Without this, a unit loaded from a URL and then reloaded from
    /// bare source (e.g. a Remix result with no file behind it) would keep reporting the stale
    /// URL, and a capture built from it would wrongly claim a file the running shader no longer
    /// has behind it.
    func testLoadingFromSourceAfterAURLClearsIt() throws {
        let instrument = Instrument()
        let url = try makeShaderFile()
        instrument.deck(.one).unit.load(url: url)
        XCTAssertEqual(instrument.deck(.one).unit.sourceURL, url, "sanity: the URL load landed")

        instrument.deck(.one).unit.load(source: """
        /*{ "DESCRIPTION": "test", "ISFVSN": "2", "INPUTS": [] }*/
        void main() { gl_FragColor = vec4(0.0, 0.0, 0.0, 1.0); }
        """, name: "inline")
        XCTAssertNil(instrument.deck(.one).unit.sourceURL,
                     "A source-loaded unit has no file behind it and must not still claim the "
                     + "previous URL")
    }
}
