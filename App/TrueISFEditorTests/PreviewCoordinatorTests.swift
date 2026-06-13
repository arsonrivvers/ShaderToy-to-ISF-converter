import XCTest
import Combine

@MainActor
final class PreviewCoordinatorTests: XCTestCase {
    func testForwardsLoadToActiveEngine() {
        let fake = FakePreviewEngine()
        let coord = PreviewCoordinator(metal: fake, webkit: FakePreviewEngine())
        coord.load(isf: "/*{}*/ void main(){}")
        XCTAssertEqual(fake.loadedISF, "/*{}*/ void main(){}")
    }

    func testRepublishesActiveEngineCompileState() {
        let fake = FakePreviewEngine()
        let coord = PreviewCoordinator(metal: fake, webkit: FakePreviewEngine())
        fake.simulateCompile(valid: true, error: nil, line: nil, inputs: [])
        XCTAssertTrue(coord.compileValid)
    }

    /// Regression: opening a populated shader programmatically (Remix "open in editor") left the
    /// Adjust panel empty until the user edited the code. Root cause — the coordinator mirrored
    /// engine state inside the will-change handler and read inputs BEFORE the engine stored them.
    /// With real @Published ordering (no trailing signal) the coordinator must still surface inputs.
    func testSurfacesInputsWithRealPublishedOrdering() async {
        let fake = FakePreviewEngine()
        let coord = PreviewCoordinator(metal: fake, webkit: FakePreviewEngine())
        let inputs = [ISFPreviewInput(name: "amount", type: "float", defaultValue: 0.0,
                                      min: 0.0, max: 1.0, labels: nil, values: nil)]
        fake.simulateCompileLikePublished(valid: true, error: nil, line: nil, inputs: inputs)
        await Task.yield(); await Task.yield()
        XCTAssertEqual(coord.inputs.map(\.name), ["amount"])
        XCTAssertTrue(coord.compileValid)
    }

    func testToggleReloadsCurrentSourceOnNewEngine() {
        let metal = FakePreviewEngine(); let webkit = FakePreviewEngine()
        let coord = PreviewCoordinator(metal: metal, webkit: webkit)
        coord.load(isf: "SRC")
        coord.active = .webkit
        XCTAssertEqual(webkit.loadedISF, "SRC")
    }

    func testRealEnginesToggleWithoutCrash() async throws {
        let coord = PreviewCoordinator(metal: MetalPreviewController(), webkit: WebKitPreviewController())
        coord.load(isf: "/*{ \"ISFVSN\":\"2\" }*/ void main(){ gl_FragColor=vec4(1.0); }")
        coord.active = .webkit
        coord.active = .metal
        XCTAssertEqual(coord.active, .metal)
    }
}
