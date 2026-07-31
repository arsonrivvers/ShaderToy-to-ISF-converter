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
    /// The monitor stub carries an intrinsic height, because the real one does: a `MonitorTile`
    /// derives its height from its 16:9 ratio against the offered width. A bare `Color` has no
    /// intrinsic height and would collapse to nothing under `fixedSize`, testing a shape the app
    /// never has.
    private static let stubMonitorHeight: CGFloat = 300

    private func stubSurface(layout: SurfaceLayout, stripHeight: CGFloat) -> some View {
        InstrumentSurface(layout: layout) {
            Color.gray.measured("panel", in: Self.space)
        } monitors: {
            Color.blue.frame(height: Self.stubMonitorHeight).measured("monitors", in: Self.space)
        } strips: {
            Color.green.frame(height: stripHeight).measured("strips", in: Self.space)
        } mixer: {
            Color.red.frame(width: 200).measured("mixer", in: Self.space)
        }
    }

    /// THE gate, and it is the opposite of what this phase first shipped.
    ///
    /// The monitor strip must NOT resize when the content below it changes. The first version made
    /// it flexible so collapsing a section would hand its height to the picture; on device that
    /// meant the previews jumped every time PARAMETERS was opened or closed, and the operator
    /// rejected it on sight (2026-07-31). Stability beat size. If this test ever fails, the strip
    /// has gone flexible again and the previews will move under the operator's hands mid-set.
    func testTheMonitorStripDoesNotResizeWhenTheStripsBelowItChange() throws {
        let layout = SurfaceLayout()

        let tall = SurfaceRenderHarness.frames(
            stubSurface(layout: layout, stripHeight: 600), size: Self.windowSize)
        let short = SurfaceRenderHarness.frames(
            stubSurface(layout: layout, stripHeight: 120), size: Self.windowSize)

        let tallMonitors = try XCTUnwrap(tall["monitors"], "harness reported no frames").height
        let shortMonitors = try XCTUnwrap(short["monitors"], "harness reported no frames").height

        XCTAssertEqual(shortMonitors, tallMonitors, accuracy: 0.5,
                       "A 480pt change below the monitor strip must not move it by even a point")
        XCTAssertEqual(tallMonitors, Self.stubMonitorHeight, accuracy: 0.5,
                       "The strip takes its height from its content, not from what is left over")
    }

    /// The other half of "doesn't jump": the strip must not MOVE either.
    ///
    /// A strip that keeps its height but slides down the window when content below it grows is
    /// just as disorienting as one that resizes. It is pinned to the top of the content column, so
    /// its origin is fixed regardless of what is below it.
    func testTheMonitorStripStaysPinnedToTheTop() throws {
        let layout = SurfaceLayout()

        let tall = SurfaceRenderHarness.frames(
            stubSurface(layout: layout, stripHeight: 600), size: Self.windowSize)
        let short = SurfaceRenderHarness.frames(
            stubSurface(layout: layout, stripHeight: 120), size: Self.windowSize)

        let tallY = try XCTUnwrap(tall["monitors"], "harness reported no frames").minY
        let shortY = try XCTUnwrap(short["monitors"], "harness reported no frames").minY

        XCTAssertEqual(tallY, shortY, accuracy: 0.5,
                       "The monitor strip must not slide when the content below it changes")
        XCTAssertLessThan(tallY, 1.0,
                          "It sits at the very top of the content column, not floating below it")
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
        // The section measures ITSELF as well as its content. The header is present in both
        // states, so "section" reported is proof the harness ran — without it the collapsed
        // half of this test would pass on an empty dictionary, i.e. verify nothing. Applied
        // before `.coordinateSpace` so the reader resolves inside the space it names.
        func section(_ l: SurfaceLayout) -> some View {
            CollapsibleSection(title: "FX", summary: "3", key: .masterFX, layout: l) {
                VStack { ForEach(0..<5, id: \.self) { _ in Slider(value: .constant(0.5)) } }
                    .measured("content", in: space)
            }
            .measured("section", in: space)
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
        // Ordered deliberately: prove the harness ran BEFORE concluding anything from an absence.
        // A starved dictionary fails here rather than passing the nil check for the wrong reason.
        XCTAssertNotNil(collapsed["section"], "harness reported no frames")
        XCTAssertNil(collapsed["content"], "a collapsed section must not render its content")
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
