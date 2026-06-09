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

    func testToggleReloadsCurrentSourceOnNewEngine() {
        let metal = FakePreviewEngine(); let webkit = FakePreviewEngine()
        let coord = PreviewCoordinator(metal: metal, webkit: webkit)
        coord.load(isf: "SRC")
        coord.active = .webkit
        XCTAssertEqual(webkit.loadedISF, "SRC")
    }
}
