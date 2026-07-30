import XCTest
import Metal

final class DeckControlsTests: XCTestCase {
    private func input(_ name: String, _ type: String,
                       defaultValue: Any? = nil, min: Any? = nil, max: Any? = nil,
                       labels: [String]? = nil, values: [Double]? = nil) -> ISFPreviewInput {
        ISFPreviewInput(name: name, type: type, defaultValue: defaultValue,
                        min: min, max: max, labels: labels, values: values)
    }

    func testEachISFTypeMapsToItsControl() {
        let rows = DeckControlModel.rows(for: [
            input("amount", "float", defaultValue: 0.5, min: 0.0, max: 1.0),
            input("enabled", "bool", defaultValue: true),
            input("centre", "point2D", defaultValue: [0.5, 0.5], min: [0.0, 0.0], max: [1.0, 1.0]),
            input("tint", "color", defaultValue: [1.0, 0.0, 0.0, 1.0]),
            input("style", "long", defaultValue: 1.0, labels: ["A", "B"], values: [0, 1]),
            input("trigger", "event"),
            input("inputImage", "image"),
        ])
        XCTAssertEqual(rows.map(\.kind),
                       [.slider, .toggle, .point, .color, .menu, .pulse, .routed])
    }

    // MARK: image-input routing

    func testADecksImageInputsAreAllRoutable() {
        // A deck's shader belongs to the operator: every image input is theirs to point at a
        // camera, a pattern, or another shader.
        let rows = DeckControlModel.rows(for: [
            input("inputImage", "image"), input("mask", "image"),
        ], reservesPrimaryInput: false)
        XCTAssertEqual(rows.map(\.kind), [.routed, .routed])
    }

    func testAStagesPrimaryImageInputIsChainFedRatherThanRoutable() {
        // An FX stage's first image input IS the chain feed. Offering a source picker for it would
        // let the operator silently unplug the stage from the chain.
        let rows = DeckControlModel.rows(for: [input("inputImage", "image")],
                                         reservesPrimaryInput: true)
        XCTAssertEqual(rows.map(\.kind), [.chainFed])
    }

    func testOnlyTheFirstImageInputIsChainFed() {
        // A two-input filter used as a stage still needs its SECOND source routed — that is how a
        // blend or mask stage gets its other layer.
        let rows = DeckControlModel.rows(for: [
            input("amount", "float"), input("inputImage", "image"), input("mask", "image"),
        ], reservesPrimaryInput: true)
        XCTAssertEqual(rows.map(\.kind), [.slider, .chainFed, .routed])
    }

    func testUnknownTypesAreSurfacedRatherThanDropped() {
        // Silently dropping an input the engine reports is how an operator discovers mid-set that
        // a control they expected does not exist.
        let rows = DeckControlModel.rows(for: [input("mystery", "audioFFT")])
        XCTAssertEqual(rows.map(\.kind), [.unsupported])
    }

    func testDeclarationOrderIsPreserved() {
        let rows = DeckControlModel.rows(for: [
            input("z", "float"), input("a", "float"), input("m", "bool"),
        ])
        XCTAssertEqual(rows.map(\.input.name), ["z", "a", "m"],
                       "ISF header order is the author's intent — never alphabetise it")
    }

    func testAShaderWithNoInputsProducesNoRows() {
        XCTAssertTrue(DeckControlModel.rows(for: []).isEmpty)
    }

    // MARK: value plumbing

    @MainActor
    func testSettingAControlValueReachesTheParamStoreAndTheEngine() throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let queue = try XCTUnwrap(device.makeCommandQueue())
        let deck = Deck(id: .one, device: device, queue: queue, clock: RenderClock())

        var seen: [(String, String)] = []
        let original = deck.unit.params.onSet
        deck.unit.params.onSet = { name, json in
            seen.append((name, json))
            original?(name, json)
        }
        deck.unit.params.set("amount", .float(0.25))
        XCTAssertEqual(seen.map(\.0), ["amount"])
        XCTAssertEqual(seen.map(\.1), ["0.25"])
    }

    @MainActor
    func testResetRestoresTheHeaderDefault() throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let queue = try XCTUnwrap(device.makeCommandQueue())
        let deck = Deck(id: .one, device: device, queue: queue, clock: RenderClock())
        deck.unit.params.syncInputs([input("amount", "float", defaultValue: 0.5, min: 0.0, max: 1.0)])

        deck.unit.params.set("amount", .float(0.9))
        XCTAssertTrue(deck.unit.params.isModified("amount"))
        deck.unit.params.resetToDefault("amount")
        XCTAssertFalse(deck.unit.params.isModified("amount"))
        guard case .float(let v)? = deck.unit.params.value(for: "amount") else {
            return XCTFail("expected a float")
        }
        XCTAssertEqual(v, 0.5, accuracy: 1e-12)
    }
}
