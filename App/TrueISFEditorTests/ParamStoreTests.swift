import XCTest

@MainActor
final class ParamStoreTests: XCTestCase {
    private func input(_ name: String, _ type: String, def: Any? = nil,
                       min: Any? = nil, max: Any? = nil) -> ISFPreviewInput {
        ISFPreviewInput(name: name, type: type, defaultValue: def,
                        min: min, max: max, labels: nil, values: nil)
    }

    func testJsonFragments() {
        XCTAssertEqual(ParamValue.float(0.5).jsonFragment, "0.5")
        XCTAssertEqual(ParamValue.bool(true).jsonFragment, "true")
        XCTAssertEqual(ParamValue.bool(false).jsonFragment, "false")
        XCTAssertEqual(ParamValue.long(3).jsonFragment, "3")   // no decimal point — must parse as integer
        XCTAssertEqual(ParamValue.point2D([0.1, 0.2]).jsonFragment, "[0.1, 0.2]")
        XCTAssertEqual(ParamValue.color([1, 0, 0, 1]).jsonFragment, "[1.0, 0.0, 0.0, 1.0]")
    }

    func testSetThenValueRoundTrip_andOnSetFires() {
        let store = ParamStore()
        var fired: [(String, String)] = []
        store.onSet = { fired.append(($0, $1)) }
        store.set("speed", .float(0.7))
        XCTAssertEqual(store.value(for: "speed"), .float(0.7))
        XCTAssertEqual(fired.count, 1)
        XCTAssertEqual(fired[0].0, "speed")
        XCTAssertEqual(fired[0].1, "0.7")
    }

    func testIsModifiedAgainstDefaults_andResetToDefault() {
        let store = ParamStore()
        store.syncInputs([input("speed", "float", def: 1.0)])
        XCTAssertFalse(store.isModified("speed"))
        store.set("speed", .float(2.0))
        XCTAssertTrue(store.isModified("speed"))

        var fired: [(String, String)] = []
        store.onSet = { fired.append(($0, $1)) }
        store.resetToDefault("speed")
        XCTAssertFalse(store.isModified("speed"))
        XCTAssertEqual(store.value(for: "speed"), .float(1.0))   // falls back to default
        XCTAssertEqual(fired.map(\.1), ["1.0"], "reset must push the default to the engines")
    }

    func testSyncInputsPrunesVanishedAndTypeChanged_keepsSurvivors() {
        let store = ParamStore()
        store.syncInputs([input("a", "float", def: 0.0), input("b", "float", def: 0.0)])
        store.set("a", .float(0.9))
        store.set("b", .float(0.4))
        // "b" vanishes; "a" survives but becomes a color (type drift) → both pruned... except
        // survivors with the SAME type stay: re-add "c" to prove keeping works.
        store.syncInputs([input("a", "color", def: [1.0, 1.0, 1.0, 1.0])])
        XCTAssertNil(store.values["b"], "vanished input's value must be pruned")
        XCTAssertNil(store.values["a"], "type-changed input's value must be pruned")

        store.syncInputs([input("c", "float", def: 0.0)])
        store.set("c", .float(0.3))
        store.syncInputs([input("c", "float", def: 0.5)])   // same name+type, new default
        XCTAssertEqual(store.values["c"], .float(0.3), "same-typed survivor must be kept")
    }

    func testReplayAllFiresOncePerStoredValue() {
        let store = ParamStore()
        store.syncInputs([input("x", "float", def: 0.0), input("y", "bool", def: false)])
        store.set("x", .float(0.2))
        store.set("y", .bool(true))
        var fired: [String: String] = [:]
        store.onSet = { fired[$0] = $1 }
        store.replayAll()
        XCTAssertEqual(fired, ["x": "0.2", "y": "true"])
    }

    func testResetAllEmptiesEverything() {
        let store = ParamStore()
        store.syncInputs([input("x", "float", def: 0.0)])
        store.set("x", .float(0.2))
        store.resetAll()
        XCTAssertTrue(store.values.isEmpty)
        XCTAssertNil(store.value(for: "x"))
    }

    func testDefaultCoercionPerType() {
        XCTAssertEqual(ParamStore.defaultValue(for: input("f", "float", def: 0.25)), .float(0.25))
        XCTAssertEqual(ParamStore.defaultValue(for: input("b", "bool", def: true)), .bool(true))
        XCTAssertEqual(ParamStore.defaultValue(for: input("l", "long", def: 2.0)), .long(2))
        XCTAssertEqual(ParamStore.defaultValue(for: input("p", "point2D", def: [0.5, 0.5])),
                       .point2D([0.5, 0.5]))
        XCTAssertEqual(ParamStore.defaultValue(for: input("c", "color", def: [0.0, 1.0, 0.0, 1.0])),
                       .color([0, 1, 0, 1]))
        XCTAssertNil(ParamStore.defaultValue(for: input("i", "image")))
        XCTAssertNil(ParamStore.defaultValue(for: input("e", "event")))
    }
}
