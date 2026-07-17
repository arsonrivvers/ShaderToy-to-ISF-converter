import XCTest
@testable import TrueISFEditor

/// B1c: the EditorViewModel ↔ ParamStore ↔ render-sink wiring.
@MainActor
final class ParamStoreWiringTests: XCTestCase {
    func testSetReachesOutputSink() {
        let vm = EditorViewModel(file: .untitled(source: EditorViewModel.blankTemplate))
        var sunk: [(String, String)] = []
        vm.outputParamSink = { sunk.append(($0, $1)) }
        vm.paramStore.set("speed", .float(0.7))
        XCTAssertEqual(sunk.count, 1)
        XCTAssertEqual(sunk[0].0, "speed")
        XCTAssertEqual(sunk[0].1, "0.7")
    }

    func testSceneInstallSyncsPrunesAndFeedsValidatedSource() {
        let vm = EditorViewModel(file: .untitled(source: EditorViewModel.blankTemplate))
        // A value for an input the compiled scene does NOT declare: scene-install must resync
        // defaults from the live engine and prune it (name-keyed survival is only for inputs
        // that still exist — ParamStoreTests covers the replay of survivors).
        vm.paramStore.set("ghost", .float(0.7))
        var validated: [String] = []
        vm.onValidatedSource = { validated.append($0) }

        vm.preview.onSceneInstalled?()   // what the engine fires after a successful compile

        XCTAssertTrue(vm.paramStore.values.isEmpty,
                      "values for inputs the scene doesn't declare must be pruned on install")
        XCTAssertEqual(validated, [vm.file.source],
                       "the pop-out feed fires on validated compiles")
    }

    func testPulseForwardsToOutputSink() {
        let vm = EditorViewModel(file: .untitled(source: EditorViewModel.blankTemplate))
        var pulses: [String] = []
        vm.outputPulseSink = { pulses.append($0) }
        vm.pulseEvent("boom")
        XCTAssertEqual(pulses, ["boom"])
    }

    func testDocumentSwitchResetsStore() {
        let vm = EditorViewModel(file: .untitled(source: EditorViewModel.blankTemplate))
        vm.paramStore.set("speed", .float(0.9))
        vm.newUntitled()
        XCTAssertTrue(vm.paramStore.values.isEmpty,
                      "a new document must not inherit the previous document's param values")
    }
}
