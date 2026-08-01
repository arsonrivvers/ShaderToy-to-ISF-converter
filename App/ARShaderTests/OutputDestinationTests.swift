import XCTest

final class OutputDestinationTests: XCTestCase {
    private let laptop = ScreenInfo(id: "1", name: "Built-in Display",
                                    frame: CGRect(x: 0, y: 0, width: 1728, height: 1117),
                                    isMain: true)
    private let projector = ScreenInfo(id: "2", name: "EPSON PJ",
                                       frame: CGRect(x: 1728, y: 0, width: 1920, height: 1080),
                                       isMain: false)

    // MARK: projected sharpness

    func testALowScaleIsFreeWhileOutputIsClosed() {
        // Nothing needs full resolution when the only consumers are ~340px monitor tiles, so a low
        // scale there costs no image quality at all and must not nag.
        XCTAssertFalse(OutputSharpness.isProjectingUpscaled(
            destination: .off, scale: RenderScale(percent: 10)))
    }

    func testProjectingAtFullScaleIsNotFlagged() {
        XCTAssertFalse(OutputSharpness.isProjectingUpscaled(
            destination: .screen(id: "2"), scale: .full))
    }

    /// Phase 3c: a preview control can no longer reach the projector, so this must hold for EVERY
    /// combination rather than only the ones a UI happens to produce today.
    func testProjectingAnUpscaleIsUnreachable() {
        let destinations: [OutputDestination] = [.off, .floating, .screen(id: "1")]
        for destination in destinations {
            for scale in RenderScale.presets {
                XCTAssertFalse(
                    OutputSharpness.isProjectingUpscaled(destination: destination, scale: scale),
                    "\(destination) at \(scale.percent)% must not be an upscale")
            }
        }
    }

    func testOffIsClosedNoMatterWhatIsPluggedIn() {
        XCTAssertEqual(OutputPlacement.resolve(.off, screens: [laptop, projector]), .closed)
        XCTAssertEqual(OutputPlacement.resolve(.off, screens: [laptop]), .closed)
    }

    func testFloatingLandsOnTheMainScreen() {
        XCTAssertEqual(OutputPlacement.resolve(.floating, screens: [laptop, projector]),
                       .floating(on: laptop))
    }

    func testAScreenRequestGoesFullscreenOnThatScreen() {
        XCTAssertEqual(OutputPlacement.resolve(.screen(id: "2"), screens: [laptop, projector]),
                       .fullscreen(on: projector))
    }

    func testAnUnpluggedScreenFallsBackToFloatingRatherThanDisappearing() {
        // The unplug-mid-set case. Going .closed here would black the room with no warning;
        // stranding the window on a dead screen would lose the output entirely.
        XCTAssertEqual(OutputPlacement.resolve(.screen(id: "2"), screens: [laptop]),
                       .floating(on: laptop))
    }

    func testReplugRestoresFullscreenOnThatScreen() {
        // Screen ids are NSScreenNumber, stable across a plug cycle of the same display, so the
        // same request resolves back to fullscreen without the operator re-picking.
        let request = OutputDestination.screen(id: "2")
        XCTAssertEqual(OutputPlacement.resolve(request, screens: [laptop]), .floating(on: laptop))
        XCTAssertEqual(OutputPlacement.resolve(request, screens: [laptop, projector]),
                       .fullscreen(on: projector))
    }

    func testWithNoScreensAtAllTheOutputIsClosed() {
        XCTAssertEqual(OutputPlacement.resolve(.screen(id: "2"), screens: []), .closed)
        XCTAssertEqual(OutputPlacement.resolve(.floating, screens: []), .closed)
    }

    func testFloatingFallsBackToTheFirstScreenWhenNoneClaimsToBeMain() {
        let odd = ScreenInfo(id: "9", name: "Odd", frame: .zero, isMain: false)
        XCTAssertEqual(OutputPlacement.resolve(.floating, screens: [odd]), .floating(on: odd))
    }

    // MARK: menu

    func testTheMenuOffersOffFloatingAndEveryScreen() {
        XCTAssertEqual(OutputMenu.options(for: [laptop, projector]),
                       [.off, .floating, .screen(id: "1"), .screen(id: "2")])
    }

    func testTheMenuStillOffersFloatingWithOnlyOneScreen() {
        XCTAssertEqual(OutputMenu.options(for: [laptop]),
                       [.off, .floating, .screen(id: "1")])
    }

    func testADisconnectedScreenIsLabelledAsSuchRatherThanSilentlyRenamed() {
        XCTAssertEqual(OutputMenu.title(for: .screen(id: "2"), screens: [laptop]),
                       "Display 2 (disconnected)")
        XCTAssertEqual(OutputMenu.title(for: .screen(id: "2"), screens: [laptop, projector]),
                       "EPSON PJ")
    }

    func testOffIsTheLaunchDefault() {
        // Nothing is ever projected until the operator asks for it.
        XCTAssertEqual(OutputDestination.launchDefault, .off)
    }
}
