import XCTest
import SwiftUI

@MainActor
final class SurfaceGeometryTests: XCTestCase {

    private static let windowSize = CGSize(width: 1600, height: 1000)
    private static var space: String {
        InstrumentSurface<Color, Color, Color, Color>.coordinateSpace
    }

    /// Stand-ins for the Metal monitor row and the deck strips: same layout participation, no GPU,
    /// each reporting its own frame.
    private func stubSurface(layout: SurfaceLayout, stripHeight: CGFloat) -> some View {
        InstrumentSurface(layout: layout) {
            Color.gray.measured("panel", in: Self.space)
        } monitors: {
            Color.blue.measured("monitors", in: Self.space)
        } strips: {
            Color.green.frame(height: stripHeight).measured("strips", in: Self.space)
        } mixer: {
            Color.red.frame(width: 200).measured("mixer", in: Self.space)
        }
    }

    /// THE gate. Collapsing must hand height to the picture, not leave grey space.
    func testTheMonitorRowGrowsWhenTheStripsShrink() throws {
        let layout = SurfaceLayout()

        let tall = SurfaceRenderHarness.frames(
            stubSurface(layout: layout, stripHeight: 600), size: Self.windowSize)
        let short = SurfaceRenderHarness.frames(
            stubSurface(layout: layout, stripHeight: 120), size: Self.windowSize)

        let tallMonitors = try XCTUnwrap(tall["monitors"], "harness reported no frames").height
        let shortMonitors = try XCTUnwrap(short["monitors"], "harness reported no frames").height

        XCTAssertGreaterThan(shortMonitors, tallMonitors + 400,
                             "Every point the strips give up must reach the monitor row. If this "
                             + "fails, collapsing frees space nothing uses and the whole feature "
                             + "is cosmetic.")
    }

    func testTheMonitorRowNeverGoesBelowItsFloor() throws {
        let layout = SurfaceLayout()
        let frames = SurfaceRenderHarness.frames(
            stubSurface(layout: layout, stripHeight: 5000), size: Self.windowSize)

        XCTAssertGreaterThanOrEqual(
            try XCTUnwrap(frames["monitors"], "harness reported no frames").height,
            InstrumentSurface<Color, Color, Color, Color>.minMonitorHeight,
            "A very tall strip column must not squeeze the picture to nothing")
    }

    func testClosingThePanelGivesItsWidthToTheContent() throws {
        let layout = SurfaceLayout()
        layout.select(panel: .library)
        let open = SurfaceRenderHarness.frames(
            stubSurface(layout: layout, stripHeight: 300), size: Self.windowSize)
        XCTAssertNotNil(open["panel"], "harness reported no frames")
        let openMonitorWidth = try XCTUnwrap(open["monitors"]).width

        layout.select(panel: .library)   // close
        let closed = SurfaceRenderHarness.frames(
            stubSurface(layout: layout, stripHeight: 300), size: Self.windowSize)

        XCTAssertNil(closed["panel"], "A closed panel is absent, not zero-width")
        XCTAssertGreaterThan(try XCTUnwrap(closed["monitors"]).width, openMonitorWidth,
                             "The closed panel's width reaches the content column")
    }

    /// The phase-2 defect, caught at the component: a section that "opens" onto nothing.
    func testAnExpandedSectionHasRealHeightAndACollapsedOneIsAbsent() throws {
        let layout = SurfaceLayout()
        let space = "sectionTest"
        func section(_ l: SurfaceLayout) -> some View {
            CollapsibleSection(title: "FX", summary: "3", key: .masterFX, layout: l) {
                VStack { ForEach(0..<5, id: \.self) { _ in Slider(value: .constant(0.5)) } }
                    .measured("content", in: space)
            }
            .coordinateSpace(name: space)
        }

        layout.setExpanded(true, for: .masterFX)
        let expanded = SurfaceRenderHarness.frames(
            section(layout), size: CGSize(width: 300, height: 400))
        XCTAssertGreaterThan(
            try XCTUnwrap(expanded["content"], "harness reported no frames").height, 60,
            "An expanded section must contain something visible — a disclosure that opens onto "
            + "nothing shipped in phase 2")

        layout.setExpanded(false, for: .masterFX)
        let collapsed = SurfaceRenderHarness.frames(
            section(layout), size: CGSize(width: 300, height: 400))
        XCTAssertNil(collapsed["content"])
    }

    /// The resize affordance must be reachable — the defect a spec review caught was a panel width
    /// that nothing could write.
    func testTheResizeHandleLeavesRoomAtThePanelEdge() throws {
        let layout = SurfaceLayout()
        layout.select(panel: .library)
        let frames = SurfaceRenderHarness.frames(
            stubSurface(layout: layout, stripHeight: 300), size: Self.windowSize)

        let panel = try XCTUnwrap(frames["panel"], "harness reported no frames")
        let monitors = try XCTUnwrap(frames["monitors"])
        XCTAssertGreaterThanOrEqual(monitors.minX - panel.maxX, 5,
                                    "A gap of at least the 6pt handle must sit between the panel's "
                                    + "trailing edge and the content column. A 1pt drag target is "
                                    + "the same mistake as a 12pt chevron.")
    }

    // MARK: PNG baselines
    //
    // Supplementary, NOT the load-bearing gate — the geometry assertions above are. Regenerate by
    // creating an empty `ARShaderTests/Baselines/RECORD` file and re-running (see
    // `SurfaceRenderHarness.recordSentinel` for why a file and not an environment variable).

    func testSurfaceBaselines() throws {
        let recording = SurfaceRenderHarness.isRecording

        let cases: [(String, () -> SurfaceLayout)] = [
            ("panel-closed",  { SurfaceLayout() }),
            ("panel-library", { let l = SurfaceLayout(); l.select(panel: .library); return l }),
            ("show-mode",     { let l = SurfaceLayout(); l.toggleShowMode(); return l }),
        ]
        for (name, make) in cases {
            let data = try XCTUnwrap(SurfaceRenderHarness.png(
                stubSurface(layout: make(), stripHeight: 300), size: Self.windowSize))
            if let reason = SurfaceRenderHarness.compareBaseline(data, named: name) {
                XCTFail(reason)
            }
        }

        // A recording run verified nothing, so it must never report green — otherwise "the suite
        // passed" would mean "the suite overwrote its own evidence." Consume the sentinel so the
        // very next run is a real comparison.
        if recording {
            try? FileManager.default.removeItem(at: SurfaceRenderHarness.recordSentinel)
            XCTFail("Baselines were RE-RECORDED, not verified. Sentinel consumed — re-run to gate.")
        }
    }
}
