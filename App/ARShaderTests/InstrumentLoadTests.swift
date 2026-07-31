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

    /// `sourceURL` is now stamped in `apply`'s success path, after the background compile —
    /// so tests must await `onCompileFinished` rather than asserting right after `load(url:)`.
    /// Same shape as Task 5's brief helper.
    private func loadAndWait(_ unit: ShaderUnit, _ url: URL) async {
        await withCheckedContinuation { continuation in
            var resumed = false
            unit.onCompileFinished = {
                guard !resumed else { return }
                resumed = true
                continuation.resume()
            }
            unit.load(url: url)
        }
        unit.onCompileFinished = nil
    }

    func testAFreshUnitHasNoSourceURL() {
        let instrument = Instrument()
        XCTAssertNil(instrument.deck(.one).unit.sourceURL,
                     "Nothing has been loaded, so there is no file behind the deck")
    }

    func testLoadingFromAURLRetainsIt() async throws {
        let instrument = Instrument()
        let url = try makeShaderFile()
        await loadAndWait(instrument.deck(.one).unit, url)
        XCTAssertEqual(instrument.deck(.one).unit.sourceURL, url,
                       "Capture needs the URL, and lastPathComponent is not enough — filenames "
                       + "are not unique across the corpus")
    }

    /// Judgment call (Task 4 brief step 5): the brief's two required tests never exercise the
    /// `load(source:name:)` clear. Without this, a unit loaded from a URL and then reloaded from
    /// bare source (e.g. a Remix result with no file behind it) would keep reporting the stale
    /// URL, and a capture built from it would wrongly claim a file the running shader no longer
    /// has behind it.
    func testLoadingFromSourceAfterAURLClearsIt() async throws {
        let instrument = Instrument()
        let url = try makeShaderFile()
        await loadAndWait(instrument.deck(.one).unit, url)
        XCTAssertEqual(instrument.deck(.one).unit.sourceURL, url, "sanity: the URL load landed")

        let done = expectation(description: "compile inline source")
        instrument.deck(.one).unit.onCompileFinished = { done.fulfill() }
        instrument.deck(.one).unit.load(source: """
        /*{ "DESCRIPTION": "test", "ISFVSN": "2", "INPUTS": [] }*/
        void main() { gl_FragColor = vec4(0.0, 0.0, 0.0, 1.0); }
        """, name: "inline")
        await fulfillment(of: [done], timeout: 30)
        instrument.deck(.one).unit.onCompileFinished = nil

        XCTAssertNil(instrument.deck(.one).unit.sourceURL,
                     "A source-loaded unit has no file behind it and must not still claim the "
                     + "previous URL")
    }

    /// The regression this fix (coordinator round 1) exists to prevent: `sourceURL` used to be
    /// stamped synchronously in `load(url:)`, disagreeing with `shaderName` whenever the compile
    /// then failed. `apply` deliberately leaves `shaderName` and the rendering scene on the
    /// previous shader when a compile fails — "compile first, swap only on success" — and
    /// `sourceURL` must honor the same rule, or Task 5's capture would store a shader that does
    /// not compile.
    func testAFailedCompileLeavesSourceURLOnTheShaderThatIsStillPlaying() async throws {
        let instrument = Instrument()
        let good = try makeShaderFile("good")
        await loadAndWait(instrument.deck(.one).unit, good)

        // A file that reads fine but cannot compile — same uncompilable body already proven to
        // fail in ShaderUnitTests (Fixtures/broken.fs: an undefined GLSL symbol).
        let bad = FileManager.default.temporaryDirectory
            .appendingPathComponent("bad-\(UUID().uuidString).fs")
        try """
        /*{ "ISFVSN": "2.0", "DESCRIPTION": "Deliberately uncompilable.", "INPUTS": [] }*/
        void main() { gl_FragColor = this_symbol_does_not_exist(1.0); }
        """.write(to: bad, atomically: true, encoding: .utf8)
        addTeardownBlock { try? FileManager.default.removeItem(at: bad) }
        await loadAndWait(instrument.deck(.one).unit, bad)

        XCTAssertNotNil(instrument.deck(.one).unit.compileError, "the failure must be reported")
        XCTAssertEqual(instrument.deck(.one).unit.sourceURL, good,
                       "A failed compile leaves the previous shader playing, so sourceURL must "
                       + "still name it — capture reads this, and would otherwise store a shader "
                       + "that does not compile")
    }
}
