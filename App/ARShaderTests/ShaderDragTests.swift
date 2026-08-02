import XCTest
import UniformTypeIdentifiers   // UTType — the exported drag identifier assertion below
@testable import ARShader

@MainActor
final class ShaderDragTests: XCTestCase {
    private let url = URL(fileURLWithPath: "/tmp/a.fs")
    private var fromLibrary: ShaderDrag { .init(source: .library, url: url, snapshot: nil) }
    private var fromDeck: ShaderDrag {
        .init(source: .deck(.one), url: url, snapshot: ParamSnapshot(params: [:]))
    }

    // MARK: The never-overwrite rule, now under a drag

    func testADropOnAnEmptySlotIsAccepted() {
        XCTAssertTrue(ShaderDrag.accepts(fromLibrary, on: .slot, isSlotFilled: false,
                                         withOption: false))
    }

    /// The rule phase 3b was built around, restated for a gesture that is a BIGGER mis-click risk
    /// than a click: the operator is crossing the surface with a payload attached and a slot is a
    /// small target beside seven identical ones.
    func testADropOnAFilledSlotIsRejectedWithoutOption() {
        XCTAssertFalse(ShaderDrag.accepts(fromLibrary, on: .slot, isSlotFilled: true,
                                          withOption: false))
        XCTAssertFalse(ShaderDrag.accepts(fromDeck, on: .slot, isSlotFilled: true,
                                         withOption: false))
    }

    /// ⌥ is the ONE "I mean it" gesture on this surface. It already means overwrite for a click;
    /// it means the same for a drop rather than inventing a second modifier.
    func testOptionDragReplacesAFilledSlot() {
        XCTAssertTrue(ShaderDrag.accepts(fromLibrary, on: .slot, isSlotFilled: true,
                                         withOption: true))
    }

    // MARK: Which sources may reach which destinations

    func testALibraryShaderMayReachEveryNonSlotDestination() {
        for destination: ShaderDrag.Destination in [.deck(.one), .deck(.two),
                                                    .deckFX(.one), .deckFX(.two), .masterFX] {
            XCTAssertTrue(ShaderDrag.accepts(fromLibrary, on: destination,
                                             isSlotFilled: false, withOption: false),
                          "the library must be able to fill \(destination)")
        }
    }

    /// A deck is a source for CAPTURE and nothing else. Dropping deck A onto deck B is not a
    /// copy-shader gesture — it reads like one and would silently discard the dialled values that
    /// are the entire reason a look is worth capturing.
    func testADeckMayOnlyBeDroppedOnASlot() {
        XCTAssertTrue(ShaderDrag.accepts(fromDeck, on: .slot, isSlotFilled: false,
                                         withOption: false))
        for destination: ShaderDrag.Destination in [.deck(.two), .deckFX(.one), .masterFX] {
            XCTAssertFalse(ShaderDrag.accepts(fromDeck, on: destination,
                                              isSlotFilled: false, withOption: false),
                           "a deck must not be droppable on \(destination)")
        }
    }

    /// Banned this phase. Clicking a slot already loads it onto a deck; a drag would be a second
    /// way to fire a slot mid-set with no new capability, and twice the ways to do it by accident.
    func testASlotIsNotADragSource() {
        let fromSlot = ShaderDrag(source: .slot, url: url, snapshot: nil)
        for destination: ShaderDrag.Destination in [.slot, .deck(.one), .deckFX(.one), .masterFX] {
            XCTAssertFalse(ShaderDrag.accepts(fromSlot, on: destination,
                                              isSlotFilled: false, withOption: false))
        }
    }

    /// A capture carries the dialled values; a library drag cannot, because there are none yet.
    func testOnlyADeckDragCarriesASnapshot() {
        XCTAssertNil(fromLibrary.snapshot)
        XCTAssertNotNil(fromDeck.snapshot)
    }

    // MARK: Task 6 — deck monitor → slot

    /// Dragging a deck monitor to a slot must capture the LOOK — the shader AND the values dialled
    /// into it. A capture that carried only the URL would recall at header defaults, which is
    /// exactly the re-dialling-on-stage problem the slot bank exists to remove.
    func testADeckDragCarriesTheDialledValuesNotJustTheURL() throws {
        let snapshot = ParamSnapshot(params: ["speed": .float(0.87)])
        let drag = ShaderDrag(source: .deck(.one), url: url, snapshot: snapshot)
        let captured = Preset.capturing(url: drag.url,
                                        snapshot: try XCTUnwrap(drag.snapshot))
        XCTAssertEqual(captured.snapshot.params["speed"], .float(0.87))
    }

    /// The view-seam assertion Task 6 Step 5 calls for. `testADeckDragCarriesTheDialledValuesNotJustTheURL`
    /// tests the payload TYPE, which survives a mutation that hardcodes `snapshot: nil` in
    /// `MonitorTile.draggableIfCapturable` — that mutation never touches `ShaderDrag` or `Preset` at
    /// all. This test instead reconstructs exactly what `draggableIfCapturable` builds — a
    /// `ShaderDrag` from `Instrument.currentPreset(of:)` — so a regression AT THAT CALL SITE (not
    /// just in the type) turns this red.
    func testDeckMonitorDragPayloadCarriesTheCurrentPresetsSnapshot() async throws {
        let instrument = Instrument()
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("shaderdrag-view-seam-\(UUID().uuidString).fs")
        try """
        /*{ "DESCRIPTION": "test", "ISFVSN": "2", "INPUTS": [
            { "NAME": "speed", "TYPE": "float", "MIN": 0.0, "MAX": 1.0, "DEFAULT": 0.5 }
        ] }*/
        void main() { gl_FragColor = vec4(speed, 0.0, 0.0, 1.0); }
        """.write(to: url, atomically: true, encoding: .utf8)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }

        await withCheckedContinuation { continuation in
            var resumed = false
            instrument.onLoadSettledForTesting = {
                guard !resumed else { return }
                resumed = true
                continuation.resume()
            }
            instrument.load(url, onto: .deck(.one))
        }
        instrument.onLoadSettledForTesting = nil
        instrument.deck(.one).unit.params.set("speed", .float(0.42))

        // The ACTUAL production call site, not a reconstruction of it: `MonitorTile.body` builds
        // its `.draggable` payload by calling this exact static function. A test that instead
        // rebuilt a `ShaderDrag` by hand here would pass under the Step 5 mutation regardless of
        // what `dragPayload` does — the trap `dragPayload` was extracted out of
        // `draggableIfCapturable` to close (see that function's doc comment).
        let payload = try XCTUnwrap(MonitorTile.dragPayload(for: .deck(.one), instrument: instrument))

        XCTAssertNotNil(payload.snapshot, "a deck monitor drag must carry the dialled values")
        XCTAssertEqual(payload.snapshot?.params["speed"], .float(0.42),
                       "the carried snapshot must reflect what is dialled NOW, not header defaults")
    }

    /// The gate half of `dragPayload`: an empty deck must not be a drag source at all (no sentinel
    /// payload that starts a drag only to be rejected wherever it lands).
    func testMonitorDragPayloadIsNilForAnEmptyDeck() {
        XCTAssertNil(MonitorTile.dragPayload(for: .deck(.one), instrument: Instrument()))
    }

    /// PROGRAM is never a drag source: `currentPreset(of:)` takes a `DeckID`, and the master
    /// composite has no shader of its own to hand back.
    func testMonitorDragPayloadIsNilForProgram() {
        XCTAssertNil(MonitorTile.dragPayload(for: .master, instrument: Instrument()))
    }

    // MARK: the exported UTI (final-review F13c / L79)

    /// The drag type is EXPORTED — `UTType(exportedAs:)` plus a `UTExportedTypeDeclarations` entry
    /// — which means an installed build registers it with LaunchServices for the whole system. It
    /// was declared as `com.arshader.shader-drag`, a reverse-DNS prefix this app does not own, and
    /// the next step in the plan installs the app. Apple's rule is that an exported identifier must
    /// sit under a domain the declarer controls; the bundle's own is `com.arsonrivvers.ARShader`.
    ///
    /// Asserts against the HOST APP's real `Info.plist`, not against a literal repeated in the test:
    /// the failure this guards is the code and the plist drifting apart, and a test that only
    /// checked the Swift constant could not see that at all. `Bundle.main` is the ARShader host app
    /// under XCTest (`TEST_HOST` in `project.yml`).
    func testTheExportedDragUTIIsDeclaredUnderTheAppsOwnBundleIdentifier() throws {
        let bundleID = try XCTUnwrap(Bundle.main.bundleIdentifier)
        XCTAssertTrue(UTType.arshaderDrag.identifier.hasPrefix(bundleID + "."),
                      "an exported UTI must sit under a reverse-DNS prefix this app owns — "
                      + "\(UTType.arshaderDrag.identifier) is not under \(bundleID)")

        let declarations = try XCTUnwrap(
            Bundle.main.object(forInfoDictionaryKey: "UTExportedTypeDeclarations") as? [[String: Any]],
            "the app must still EXPORT the type, not merely name it in Swift")
        let declared = declarations.compactMap { $0["UTTypeIdentifier"] as? String }
        XCTAssertTrue(declared.contains(UTType.arshaderDrag.identifier),
                      "the code's identifier and the exported declaration must not drift apart — "
                      + "Swift says \(UTType.arshaderDrag.identifier), Info.plist says \(declared)")
    }
}
