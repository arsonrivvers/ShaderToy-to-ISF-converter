import XCTest
import SwiftUI

@MainActor
final class SurfaceGeometryTests: XCTestCase {

    private static let windowSize = CGSize(width: 1600, height: 1000)
    private static var space: String {
        InstrumentSurface<Color, Color, Color, Color, Color>.coordinateSpace
    }

    /// Stand-ins for the Metal monitor row and the deck strips: same layout participation, no GPU,
    /// each reporting its own frame.
    ///
    /// The monitor stub is height-FLEXIBLE (an ideal height it will exceed if offered more), and
    /// that is load-bearing rather than incidental. It used to be a rigid `.frame(height: 300)`,
    /// which reports its own height to the `GeometryReader` no matter what the parent proposes —
    /// so both assertions in `testTheMonitorStripDoesNotResizeWhenTheStripsBelowItChange` were true
    /// by construction of the STUB, and the test stayed green even when the production code was
    /// restored to the flexible row the operator rejected. Verified by the phase 3a branch review,
    /// which measured the reverted production code passing the test unchanged.
    ///
    /// A rigid stub can only ever prove the stub is rigid. To detect a flexible monitor row, the
    /// stub has to be something a flexible row would visibly stretch.
    private static let stubMonitorIdealHeight: CGFloat = 160

    /// `slotHeight` defaults so the many callers that only care about `stripHeight` need no change;
    /// only the new gate below passes it explicitly.
    private func stubSurface(layout: SurfaceLayout, stripHeight: CGFloat,
                              slotHeight: CGFloat = 40) -> some View {
        InstrumentSurface(layout: layout) {
            Color.gray.measured("panel", in: Self.space)
        } monitors: {
            Color.blue
                .frame(minHeight: Self.stubMonitorIdealHeight, maxHeight: .infinity)
                .measured("monitors", in: Self.space)
        } slots: {
            // Flexible, like the monitor stub, and for the same reason (fix-round-1): a rigid
            // stub can only ever prove the STUB is rigid, not that the production `slots()`
            // wrapping still applies `.fixedSize(vertical: true)`. This one has an ideal height
            // (`slotHeight`) it will exceed if `InstrumentSurface` ever proposes more — exactly
            // what a regression to a flexible slots row would do.
            Color.yellow
                .frame(minHeight: slotHeight, maxHeight: .infinity)
                .measured("slots", in: Self.space)
        } strips: {
            // The 620pt minimum is production's (`deckStrips`), and the stub must carry it: without
            // it the strips compress instead of pushing, the surface never overflows, and
            // testTheMixerStripFitsAtTheWindowsDeclaredMinimum passes for the wrong reason —
            // caught by mutating the window minimum back to 1100 and seeing it stay green.
            Color.green
                .frame(minWidth: SurfaceMetrics.stripsMinWidth, minHeight: stripHeight)
                .measured("strips", in: Self.space)
        } mixer: {
            Color.red.frame(width: SurfaceMetrics.mixerWidth).measured("mixer", in: Self.space)
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
        XCTAssertEqual(tallMonitors, Self.stubMonitorIdealHeight, accuracy: 0.5,
                       "The strip takes its height from its content, not from what is left over. "
                       + "The stub is height-flexible on purpose, so a flexible monitor row would "
                       + "stretch it past its ideal and fail here.")
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

    /// Task 6R's own gate, extending the §2.1 reversal to the strip inserted below the monitors.
    /// The slot strip sits BETWEEN the monitors and the deck strips, so it is the new region most
    /// likely to accidentally take height from — or give height to — the monitor row above it.
    func testTheMonitorStripIsUnmovedByTheSlotStripBelowIt() throws {
        let layout = SurfaceLayout()
        let short = SurfaceRenderHarness.frames(
            stubSurface(layout: layout, stripHeight: 300, slotHeight: 40), size: Self.windowSize)
        let tall = SurfaceRenderHarness.frames(
            stubSurface(layout: layout, stripHeight: 300, slotHeight: 200), size: Self.windowSize)

        let a = try XCTUnwrap(short["monitors"], "harness reported no frames")
        let b = try XCTUnwrap(tall["monitors"], "harness reported no frames")
        XCTAssertEqual(a.height, b.height, accuracy: 0.5,
                       "A 160pt change in the slot strip must not resize the monitors")
        XCTAssertEqual(a.minY, b.minY, accuracy: 0.5,
                       "…nor slide them. This is the §2.1 reversal, extended to the new strip.")

        // Fix-round-1: the slots stub is now flexible (see stubSurface), so this also detects the
        // slots region ITSELF going flexible — a rigid stub could only ever prove the stub was
        // rigid, never that production's `.fixedSize(vertical: true)` wrapping still applies.
        XCTAssertEqual(try XCTUnwrap(short["slots"], "harness reported no frames").height, 40,
                       accuracy: 0.5,
                       "The slot strip is content-sized too: a flexible slots region would "
                       + "stretch this stub past its ideal.")
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
        XCTAssertGreaterThanOrEqual(monitors.minX - panel.maxX, SurfaceMetrics.resizeHandleWidth,
                                    "A gap of at least the full handle width must sit between the "
                                    + "panel's trailing edge and the content column. A 1pt drag "
                                    + "target is the same mistake as a 12pt chevron. Asserted "
                                    + "against the production constant, not a hand-copied number "
                                    + "one point below it.")
    }

    /// The window's declared minimum must actually fit the surface it declares a minimum for.
    ///
    /// `minWidth` was 1100 from master and was never raised when this phase added a 44pt rail and
    /// a 6pt resize handle. With a panel open at its 280pt default the surface needs 1152, so at
    /// the app's OWN stated minimum the mixer strip — BLACKOUT, SHOW MODE, the OUTPUT destination
    /// picker — was drawn 52pt outside the window, with no scroll and no clip indicator. The smoke
    /// legs all passed because they ran on a laptop plus an external display at generous sizes.
    ///
    /// This is the assertion the deferred `measured("mixer")` should always have carried: it was
    /// reported by the stub and never asserted, so it could not catch anything.
    func testTheMixerStripFitsAtTheWindowsDeclaredMinimum() throws {
        let layout = SurfaceLayout()
        layout.select(panel: .library)          // the panel open is the widest legal case

        let minimum = CGSize(width: SurfaceMetrics.minWindowWidth,
                             height: SurfaceMetrics.minWindowHeight)
        let frames = SurfaceRenderHarness.frames(
            stubSurface(layout: layout, stripHeight: 300), size: minimum)

        let mixer = try XCTUnwrap(frames["mixer"], "harness reported no frames")
        XCTAssertLessThanOrEqual(
            mixer.maxX, SurfaceMetrics.minWindowWidth + 0.5,
            "At the app's own minimum window width, with a panel open, the mixer strip is drawn "
            + "off-window. That strip holds the panic controls, so this is not a cosmetic clip.")
    }

    /// `SurfaceLayout.reservedSurfaceWidth` is a hardcoded number standing in for a sum of regions.
    /// If a region changes width and the number does not, the panel ceiling silently stops
    /// protecting the mixer strip — the exact defect this pair was written to close.
    func testTheReservedWidthMatchesTheRegionsItClaimsToCover() {
        XCTAssertEqual(Double(SurfaceMetrics.reservedWidth),
                       SurfaceLayout.reservedSurfaceWidth, accuracy: 0.001,
                       "SurfaceLayout.reservedSurfaceWidth must equal the sum of the regions in "
                       + "SurfaceMetrics. One of them changed without the other.")
    }

    /// **Retired, fix-round-2 (task 4, F3).** This slot briefly held
    /// `testTheDeckStripsFloorCoversTheirMeasuredNaturalWidth` (fix-round-1, addition 2 / F3+F4),
    /// which measured `deckStripsContent.fixedSize(horizontal: true, vertical: false)` against
    /// `SurfaceMetrics.stripsMinWidth`. Deleted, not retargeted: `.fixedSize(horizontal:)` asks
    /// SwiftUI for a view's IDEAL width, and for `Text` with no `lineLimit` that is its full
    /// single-line, UNWRAPPED width — hundreds of points more than its actual MINIMUM (roughly its
    /// widest word), which is what `stripsMinWidth`'s own doc comment claims to be ("below this they
    /// clip rather than shrink"). The 815pt (empty) / ~993pt (populated) figures that test produced
    /// were almost entirely three explanatory sentences measured as if they could never wrap —
    /// `FXChainView`'s "Load a shader with this chain selected in the library.", `InstrumentView`'s
    /// "Applied to the program feed, before blackout.", `ShaderControlsView`'s "No shader loaded".
    /// Every one wraps happily in production; nothing clips at 620pt. Raising `stripsMinWidth` off
    /// that measurement (620→830, cascading to `minWindowWidth` 1180→1390) briefly shipped in
    /// fix-round-1 and was reverted in fix-round-2 — it would have broken the app on a 13"/14"
    /// MacBook at a common "Larger Text" scaled resolution. Full account, including why a
    /// "no control is clipped" retarget was considered and rejected (the deck strips degrade
    /// gracefully — `Text` wraps, `Picker`s compress, `Slider`s shorten — so there is no clip-below-
    /// this floor to measure in the first place, only an arbitrary usability threshold no more
    /// principled than the existing hand-picked number), lives on `SurfaceMetrics.stripsMinWidth`'s
    /// own doc comment. The F4 determinism technique this test introduced — call
    /// `SurfaceLayout.setExpanded(_:for:)` explicitly before measuring, for EVERY `SectionKey` the
    /// measurement depends on, so the arrangement is known rather than inherited from real,
    /// persisted `UserDefaults` — is not lost with it. It is the same underlying API (though not the
    /// identical `SectionKey.all`-driven usage) `testAnExpandedSectionHasRealHeightAndACollapsedOneIsAbsent`
    /// (above, in this file) already relies on for its own single-section determinism, and remains
    /// the pattern for any future test that needs a known section-expand arrangement.
    ///
    /// `InstrumentView.deckStripsContent`, split out from `deckStrips` solely to give this retired
    /// test something un-floored to measure, is reverted to private alongside this deletion — no
    /// other caller needs it exposed.

    /// Fix-round-1, task 3, F6; recomputed fix-round-2, task 4. Task 3 raised `minCellWidth`
    /// 56→96 (thumbnail legibility), opening a real gap between the cell region needed and the
    /// cell region available at the window minimum. The prior fix round handled this with `throw
    /// XCTSkip(...)`, which review rejected: it made the test permanently two-valued (pass or
    /// skip) with no way to ever FAIL again, so a later change that widened the gap further would
    /// sit silently skipped forever.
    ///
    /// **Rewritten to bound the gap instead of hiding it.** The SAFETY property this test has
    /// always guarded — a cell can never render below its own floor, so adjacent
    /// `.contentShape(Rectangle())` hit areas cannot overlap and an edge click cannot fire the
    /// neighbouring slot — rests on `SlotCell`'s call site using an EXACT `.frame(width:
    /// SurfaceMetrics.minCellWidth, height: SurfaceMetrics.slotCellHeight)`, not a `minWidth` floor:
    /// SwiftUI's documented behaviour for an exact `.frame(width:height:)` is to report precisely
    /// that size regardless of any ambient proposal, so a cell can be neither narrower NOR wider
    /// than `minCellWidth`, by construction of the modifier — this is a property of the code, not
    /// something a test empirically discovers. **Correction (fix-round-1, F2): an earlier version of
    /// this comment named `testCellSizeIsPinnedRegardlessOfWindowWidth` as structural proof of that
    /// pinning — that test built its own stand-in rectangle sized from the SAME constants it then
    /// compared against, so it proved nothing about `SlotCell`.** Its replacement,
    /// `testSlotBankStripCellsRowWidthIsPinnedRegardlessOfWindowWidth`, measures the REAL
    /// `SlotBankStripView` and is a genuine regression gate on the sizing chain — but per its own
    /// doc comment, mutation testing found the render harness cannot distinguish the fixed chain
    /// from the old, buggy one either, so it does not independently "prove" the anti-overlap
    /// property beyond what the modifier's own documented semantics already guarantee. This test
    /// does not need to re-derive either claim — it only bounds the SIZE of the shortfall against
    /// `knownCellOverflow`, a named, explicit number instead of a silently accepted or silently
    /// skipped gap.
    ///
    /// **Recomputed for task 4's shipped chrome; briefly recomputed again and reverted (fix-round-2,
    /// F3).** Task 4 removed SOURCE and narrowed RECALL TO to a 2-segment `DeckID` picker at 90pt
    /// (`slotStripRecallWidth`) with one fewer gap (`slotStripGapCount` 3→2): chrome is now
    /// 16 + 90 + 20 + 1 = 127pt (was 357pt with SOURCE). At `minWindowWidth` (1180) with no panel
    /// open, `contentColumn` is 934pt, so `cellsRegion` = 934 − 127 = 807pt. `needed` is unchanged by
    /// task 4 — `minCellWidth` (96, now derived from `slotCellHeight` rather than an independent
    /// literal, see `SurfaceMetrics.minCellWidth`) × 8 + `slotStripCellSpacing` (6) × 7 = 810pt.
    /// Shortfall = 810 − 807 = **3pt** — down from 233, but NOT fully closed: reaching zero needed
    /// RECALL TO at ≤87pt, and 90pt (task 4's actual, shipped width — reusing SOURCE's own, not a
    /// hypothetical floor) is 3pt over that.
    ///
    /// Fix-round-1 briefly raised `minWindowWidth` to 1390 off a `stripsMinWidth` measurement that
    /// turned out to be wrong (measured a `Text`'s unwrapped IDEAL width, not a real minimum — see
    /// `SurfaceMetrics.stripsMinWidth`'s doc comment for the full account), which as a side effect
    /// dropped this shortfall to a comfortably negative −207pt and `knownCellOverflow` to 0.
    /// Fix-round-2 reverted `minWindowWidth` to 1180, so this constant reverts to 3 too — its true
    /// value never actually changed; only `minWindowWidth`'s (wrongly) did. A regression that makes
    /// the shortfall WORSE fails loudly, here, always — never skipped; one that makes it better needs
    /// no edit here, only a WIDER gap does.
    private static let knownCellOverflow: CGFloat = 3

    func testEightCellsFitAtTheMinimumWindowWidthWithNoPanelOpen() {
        let contentColumn = SurfaceMetrics.minWindowWidth
            - PanelRailView.width
            - SurfaceMetrics.dividerWidth * SurfaceMetrics.dividerCount
            - SurfaceMetrics.mixerWidth
        let cellsRegion = contentColumn - SurfaceMetrics.slotStripLeadingChromeWidth
        let needed = SurfaceMetrics.minCellWidth * CGFloat(SlotBank.perRow)
            + SurfaceMetrics.slotStripCellSpacing * CGFloat(SlotBank.perRow - 1)
        let shortfall = needed - cellsRegion
        XCTAssertLessThanOrEqual(shortfall, Self.knownCellOverflow,
                                 "The slot strip's eight-cell shortfall at the window minimum grew "
                                 + "past the known, accepted \(Self.knownCellOverflow)pt gap "
                                 + "(task 3's minCellWidth raise, 56→96, for thumbnail legibility). "
                                 + "cellsRegion=\(cellsRegion) needed=\(needed) "
                                 + "shortfall=\(shortfall). If this widening is intentional, raise "
                                 + "knownCellOverflow explicitly and say why; if the gap narrowed, "
                                 + "lower it so the next regression is caught at the tighter bound.")
    }

    /// **Retired, task 4C.** This slot held
    /// `testSlotBankStripCellsRowWidthIsPinnedRegardlessOfWindowWidth` (fix-round-2, task 4,
    /// addition 1; rewritten fix-round-1, F1), which asserted the strip's ideal width is IDENTICAL
    /// at a narrow and a wide window — "cells are pinned regardless of window width." That was
    /// exactly right for what task 4 shipped (an exact, forever-fixed cell size) and is exactly
    /// WRONG for what task 4C ships: cell width is now a genuine range, and the whole point of this
    /// task is that it stops being pinned — it grows with the window, up to a ceiling. Deleted
    /// rather than retargeted: a "must not move" assertion cannot be repaired into a "must grow, up
    /// to a point" one without inverting its own claim, and `testTheCellGrowsWithTheWindowUpToItsCeiling`
    /// (below) already covers the new invariant, reusing the SAME production-coupled construction
    /// technique this test introduced (a real `SlotBankStripView` inside a real `InstrumentSurface`,
    /// not a stand-in).
    ///
    /// One thing this test's own doc comment established is worth carrying forward rather than
    /// losing with it: `.fixedSize(horizontal: true, vertical: false)`, used to force a view to
    /// report its own IDEAL width, was measured NOT to reproduce a real, interactively-resized
    /// window's proposal-driven layout in this harness (`SurfaceRenderHarness`, a single
    /// `NSHostingView.layoutSubtreeIfNeeded()` pass) — mutation testing back then found it could not
    /// distinguish the fixed-cell fix from the pre-fix buggy chain either way. `measuredCellWidth`/
    /// `measuredRowPitch` (below) deliberately do NOT use `.fixedSize` for exactly this reason: task
    /// 4C needs the REAL, proposal-driven width a window actually gives the strip, which `.fixedSize`
    /// structurally cannot supply.
    ///
    /// **A second, harder-won harness lesson from THIS task, worth recording for the next one —
    /// corrected once already (fix round 1, F2), so read the correction, not the first draft.** The
    /// first draft of this note claimed `PreferenceKey`/`.onPreferenceChange` silently reports 0 for
    /// ANY key, from ANY branch of the tree, the instant a `ScrollView` exists ANYWHERE in that
    /// tree. That is FALSE: `DrawnCellWidthKey`/`DrawnRowHeightKey`, reported from
    /// `SlotBankStripView`'s own top level — whose subtree contains the cells `ScrollView` — resolve
    /// correctly, refuting it directly. A proposed alternative (the earlier failures just needed a
    /// longer settle loop; two fixed `layoutSubtreeIfNeeded()` passes were confirmed to under-settle
    /// a genuinely different case, see `SurfaceRenderHarness.preferenceValue`'s doc comment) was
    /// retried against BOTH original failures with up to 60 settle passes: both stayed at 0. Neither
    /// claim survived re-verification.
    ///
    /// **What was actually, repeatedly OBSERVED, across two independent reproductions in this same
    /// task (`InstrumentSurface`'s content-column measurement, and `SlotBankStripView.renderedCellWidth`,
    /// fix round 1 F1) — recorded here as what these SPECIFIC reproductions showed, not asserted as a
    /// settled rule about how SwiftUI's `PreferenceKey` system works in general:** a `PreferenceKey`
    /// value established by measuring something and bubbling it UP THROUGH a `ScrollView` boundary —
    /// either reported from WITHIN the `ScrollView`'s own content, or from an ancestor wrapping a
    /// descendant that contains one — did not reach an external `.onPreferenceChange` listener in
    /// this harness, in either reproduction, at any settle-loop length tried (up to 60 passes). A
    /// `PreferenceKey` whose value has no such link resolved fine in every case tried, `ScrollView`
    /// present in the same tree or not. `SlotBankStripView` and `InstrumentSurface` both route their
    /// `ScrollView`-crossing measurements through `.onAppear`/`.onChange` (an imperative side effect,
    /// not a value bubbling through `reduce`) for exactly this reason — see `InstrumentSurface.body`'s
    /// doc comment, at the content-column measurement, for the fullest account, including the
    /// original overgeneralised claim and the "just needs more settle passes" alternative, both
    /// stated there alongside what actually held up under retest. `DrawnCellWidthKey`/`DrawnRowHeightKey`
    /// (used by `measuredCellWidth`/`measuredRowPitch` below) remain ordinary `PreferenceKey`s and
    /// still resolved correctly in every reproduction, because what they report was already computed
    /// by `.onChange` upstream — they never needed to cross the `ScrollView` boundary themselves.

    // MARK: Cell clamp (task 4C)

    /// Builds the same real-`SlotBankStripView`-inside-real-`InstrumentSurface` arrangement
    /// `testSlotBankStripCellsRowWidthIsPinnedRegardlessOfWindowWidth` uses, reused rather than
    /// duplicated so `measuredCellWidth`/`measuredRowPitch` below share one construction path. No
    /// panel open — the widest the cells region ever gets at a given window width — matching
    /// `testEightCellsFitAtTheMinimumWindowWidthWithNoPanelOpen`'s own scenario.
    ///
    /// **`isFilled` defaults to TRUE (final-review F6).** Both geometry tests built `Instrument()`,
    /// which under `TestHarness.isActive` gets an `InMemoryKeyValueStore` — so every one of the
    /// forty slots was empty, and `SlotCell`'s filled branch (the name plate, the 0.22 fill plate,
    /// the `state.borderColor` overlay, the `.offset`/`.animation` shake, the help text and the
    /// accessibility label) had never been laid out by ANY test. Row 0 / column 0 is the cell
    /// `RenderedCellWidthKey` reports from, so with this default every rendered-geometry assertion
    /// in this file now measures a FILLED cell rather than an empty one.
    private func slotBankSurface(instrument: Instrument, layout: SurfaceLayout,
                                 isFilled: Bool = true) -> some View {
        if isFilled {
            instrument.slotBank.capture(
                Preset.capturing(url: URL(fileURLWithPath: "/tmp/harness-filled-slot.fs"),
                                 snapshot: ParamSnapshot(params: [:])),
                into: 0)
        }
        return InstrumentSurface(layout: layout) {
            Color.gray
        } monitors: {
            Color.blue.frame(minHeight: Self.stubMonitorIdealHeight, maxHeight: .infinity)
        } slots: {
            SlotBankStripView(instrument: instrument, layout: layout)
                .measured("slots", in: Self.space)
        } strips: {
            Color.green.frame(minWidth: SurfaceMetrics.stripsMinWidth, minHeight: 300)
        } mixer: {
            Color.red.frame(width: SurfaceMetrics.mixerWidth)
        }
    }

    /// The COMPUTED clamp result — `SlotBankStripView.cellWidth` — read from `DrawnCellWidthKey`,
    /// reported by the REAL `SlotBankStripView`, not a stand-in. Deliberately NOT `.fixedSize`: that
    /// asks a view for its IDEAL size, an unconstrained query that decouples the result from the
    /// real, window-width-driven proposal this is meant to observe — the same reason
    /// `testSlotBankStripCellsRowWidthIsPinnedRegardlessOfWindowWidth`'s `.fixedSize`-based
    /// technique cannot be reused here.
    ///
    /// **Does not, on its own, prove anything about what got DRAWN** (fix round 1 finding, F1): this
    /// reports the clamp arithmetic's output, not the frame SwiftUI actually applied to `SlotCell`.
    /// A mutation that disconnects the two — hardcoding `SlotCell`'s `.frame(width:height:)` while
    /// leaving `cellWidth` untouched — leaves this helper reporting the SAME healthy numbers it
    /// always did. `measuredRenderedCellWidth`, below, is what closes that gap.
    private func measuredCellWidth(windowWidth: CGFloat) -> CGFloat {
        SurfaceRenderHarness.preferenceValue(
            slotBankSurface(instrument: Instrument(), layout: SurfaceLayout()),
            key: DrawnCellWidthKey.self,
            size: CGSize(width: windowWidth, height: SurfaceMetrics.minWindowHeight))
    }

    /// The ACTUAL rendered width of a `SlotCell`, read from `RenderedCellWidthKey` — reported by a
    /// `.background(GeometryReader)` attached directly to `SlotCell`'s own `.frame(width:height:)`
    /// call site in production, not by a computed property that feeds it. This is the gate that
    /// observes real rendered geometry rather than the arithmetic that is supposed to drive it — see
    /// `RenderedCellWidthKey`'s doc comment (`SlotBankStripView.swift`) for why `DrawnCellWidthKey`
    /// alone cannot catch the render coming loose from the computation.
    private func measuredRenderedCellWidth(windowWidth: CGFloat) -> CGFloat {
        SurfaceRenderHarness.preferenceValue(
            slotBankSurface(instrument: Instrument(), layout: SurfaceLayout()),
            key: RenderedCellWidthKey.self,
            size: CGSize(width: windowWidth, height: SurfaceMetrics.minWindowHeight))
    }

    /// The row pitch `SlotBankStripView` itself hands its resize drag, read from
    /// `DrawnRowHeightKey` — reported independently of `DrawnCellWidthKey` (see that key's doc
    /// comment) so a reader can catch the two falling out of sync.
    private func measuredRowPitch(windowWidth: CGFloat) -> CGFloat {
        SurfaceRenderHarness.preferenceValue(
            slotBankSurface(instrument: Instrument(), layout: SurfaceLayout()),
            key: DrawnRowHeightKey.self,
            size: CGSize(width: windowWidth, height: SurfaceMetrics.minWindowHeight))
    }

    /// The cell grows with the window, and STOPS. Task 3 shipped a floor with infinite growth and
    /// the operator rejected the result on device; task 4 shipped an exact size and the reviewer
    /// flagged that it is tiny on a large display. Both extremes are wrong; this is the range.
    ///
    /// **Asserts on BOTH the computed clamp (`measuredCellWidth`) and the actually-rendered cell
    /// (`measuredRenderedCellWidth`), and requires them to agree** (fix round 1, F1). The computed
    /// side alone could not distinguish a correct implementation from one where `SlotCell`'s
    /// `.frame(width:height:)` had been quietly disconnected from `cellWidth` — task 4's shipped
    /// defect, restated as: the arithmetic is right but nothing draws it. Mutation 2 (brief, Step 6)
    /// specifically targets the RENDER, not the arithmetic — see this file's mutation-proof section.
    func testTheCellGrowsWithTheWindowUpToItsCeiling() throws {
        let narrow = measuredCellWidth(windowWidth: SurfaceMetrics.minWindowWidth)
        let wide   = measuredCellWidth(windowWidth: 2560)
        let renderedNarrow = measuredRenderedCellWidth(windowWidth: SurfaceMetrics.minWindowWidth)
        let renderedWide   = measuredRenderedCellWidth(windowWidth: 2560)

        XCTAssertEqual(narrow, SurfaceMetrics.minCellWidth, accuracy: 0.5,
                       "At the window minimum the cell sits on its legibility/hit-target floor")
        XCTAssertGreaterThan(wide, narrow,
                             "A wider window must give a bigger cell — a fixed cell wastes a "
                             + "large display, which is what task 4 shipped")
        XCTAssertLessThanOrEqual(wide, SurfaceMetrics.maxCellWidth,
                                 "…but never past the ceiling, or the strip eats the monitors "
                                 + "again — the defect the operator reported on device")

        XCTAssertEqual(renderedNarrow, narrow, accuracy: 0.5,
                       "The cell SwiftUI actually laid out at the window minimum must match the "
                       + "clamp's own computed floor — a mismatch means the frame has come loose "
                       + "from cellWidth")
        XCTAssertGreaterThan(renderedWide, renderedNarrow,
                             "The RENDERED cell, not just the computed one, must be bigger at a "
                             + "wider window — task 4 shipped a `.frame(width:height:)` pinned "
                             + "regardless of what any computed clamp said, and this is the gate "
                             + "that specific defect requires")
        XCTAssertEqual(renderedWide, wide, accuracy: 0.5,
                       "The cell SwiftUI actually laid out at a wide window must match the clamp's "
                       + "own computed ceiling — a mismatch means the frame has come loose from "
                       + "cellWidth")
    }

    /// **The axis the operator actually rejected** (final-review F5). `maxCellWidth`'s own doc
    /// comment ends by saying that nothing in this suite bounds the strip's resulting HEIGHT at any
    /// window width. Task 3's shipped defect was `.aspectRatio(16/9)` turning window WIDTH into row
    /// HEIGHT — "I can see us shrinking this bar a lot" — and task 4C then added two real
    /// rendered-geometry gates, both on width. A future change to `maxCellWidth`, to
    /// `slotStripCellSpacing`, to the header padding, or to `bankRows`' default could reintroduce a
    /// tall bar at wide windows with this suite fully green, and the operator would find it on
    /// device for the third time.
    ///
    /// Measures the WHOLE `slots()` region — the real `SlotBankStripView` inside the real
    /// `InstrumentSurface` at 2560pt, via `.measured("slots",…)` — against the ceiling that is
    /// supposed to bound it: one row of cells at `maxCellWidth`, plus the strip's own named chrome
    /// budget. Both terms are named constants, so this reads as "the ceiling bounds the STRIP", not
    /// as "the strip is whatever it happened to be the day this was written."
    /// Everything the strip spends on HEIGHT that is not the cell: the row-resize handle, the
    /// header row (its 9pt label plus vertical padding) and the content padding above and below the
    /// cells row. **Measured at 41pt** at the time of writing (a 131pt strip at 2560pt, of which
    /// `maxCellWidth * 9/16` = 90pt is the cell); budgeted at 56 so ordinary text-metric drift does
    /// not fail the gate. A named, explicit number rather than a silently accepted one — the same
    /// tripwire treatment as `knownCellOverflow`.
    ///
    /// Test-local rather than a `SurfaceMetrics` constant: nothing in production reads it, and a
    /// production constant with only a test consumer is coverage of dead code wearing the costume
    /// of a shared value.
    private static let slotStripChromeBudget: CGFloat = 56

    func testTheStripsHeightIsBoundedByTheCellCeilingAtAWideWindow() throws {
        let frames = SurfaceRenderHarness.frames(
            slotBankSurface(instrument: Instrument(), layout: SurfaceLayout()),
            size: CGSize(width: 2560, height: SurfaceMetrics.minWindowHeight))
        let strip = try XCTUnwrap(frames["slots"], "harness reported no frames")

        let ceiling = SurfaceMetrics.maxCellWidth * 9.0 / 16.0 + Self.slotStripChromeBudget
        XCTAssertLessThanOrEqual(strip.height, ceiling,
                                 "At 2560pt the one-row strip must still be bounded by the cell "
                                 + "ceiling plus its own chrome. A strip that keeps growing with "
                                 + "the window is the exact defect the operator rejected on device.")
        XCTAssertGreaterThan(strip.height, SurfaceMetrics.minCellWidth * 9.0 / 16.0,
                             "…and it must still be at least a cell tall, or this gate would pass "
                             + "just as happily on a strip that had collapsed to nothing")
    }

    // F6 adds NO new test here, deliberately, and that is a correction to the review that asked for
    // one. The review's proposed assertion was "seed a slot, then assert `measuredRenderedCellWidth`
    // is unchanged from the empty case." **That assertion cannot fail.** `SlotCell` is sized by
    // `.frame(width: cellWidth, height: cellWidth * 9/16)` applied at the `ForEach` call site,
    // OUTSIDE the cell; `.frame(width:height:)` with both dimensions non-nil reports exactly that
    // size to its parent regardless of what the child does, so no change inside `SlotCell` — not an
    // overflowing `.fill` thumbnail, not a padded ZStack, not a taller name plate — can move the
    // number. Verified by mutation, not by argument: `.padding(preset == nil ? 0 : 20)` inside the
    // cell left every assertion in this file green. Writing it anyway would have been the seventh
    // instance of this phase's tests-that-cannot-fail class.
    //
    // What F6 DOES buy, and what the mutation proof in the fix-wave report demonstrates: every
    // rendered-geometry assertion in this file now lays out a FILLED cell (row 0 / column 0 is both
    // the seeded slot and the cell `RenderedCellWidthKey` reports from), so the name plate, the
    // 0.22 fill plate, the `state.borderColor` overlay, the shake modifiers, the help text and the
    // accessibility label are executed on every run instead of never. A trap or a crash in that
    // branch is now caught here; its GEOMETRY is structurally unobservable, which is a property of
    // the pinned frame rather than a gap in this suite.

    /// The row height must follow the DRAWN cell, not a constant, or the resize drag desyncs from
    /// what it is dragging. Task 4 found the drag reading 60 against a real ~122pt pitch.
    func testTheRowHeightTracksTheDrawnCell() throws {
        for windowWidth in [SurfaceMetrics.minWindowWidth, 1600, 2560] as [CGFloat] {
            let cell = measuredCellWidth(windowWidth: windowWidth)
            let row  = measuredRowPitch(windowWidth: windowWidth)
            XCTAssertEqual(row, cell * 9.0 / 16.0 + SurfaceMetrics.slotStripCellSpacing,
                           accuracy: 0.5,
                           "row pitch must equal the drawn cell's height plus the row gap")
        }
    }

    /// The ceiling has to leave the default panel intact at the minimum window, or the app ships a
    /// window size at which opening a panel instantly narrows it.
    func testTheDefaultPanelStillFitsAtTheMinimumWindowWidth() {
        let ceiling = SurfaceLayout.panelWidthCeiling(
            inSurfaceOfWidth: Double(SurfaceMetrics.minWindowWidth))
        XCTAssertGreaterThanOrEqual(ceiling, Arrangement.default.panelWidth,
                                    "At the minimum window size the ceiling must still allow the "
                                    + "default panel width, or a fresh launch resized to minimum "
                                    + "would shrink the panel the operator never touched.")
    }

    // MARK: PNG baselines
    //
    // Supplementary, NOT the load-bearing gate — the geometry assertions above are. Regenerate by
    // creating an empty `ARShaderTests/Baselines/RECORD` file and re-running (see
    // `SurfaceRenderHarness.recordSentinel` for why a file and not an environment variable).

    /// The baseline stub differs from the geometry stub in exactly one way: its strips slot holds a
    /// real `CollapsibleSection` bound to `layout`.
    ///
    /// Without it, show mode had NO visible effect on the render — the geometry stub is four solid
    /// `Color`s that do not read `layout.showMode`, and `toggleShowMode()`'s only other act is
    /// closing a panel that is already closed by default. `show-mode.png` was therefore
    /// byte-identical to `panel-closed.png` and could never differ, whatever the code did. Two of
    /// three baselines were the same image, and one of them was a test incapable of failing.
    private func stubSurfaceForBaselines(layout: SurfaceLayout) -> some View {
        InstrumentSurface(layout: layout) {
            Color.gray
        } monitors: {
            // Rigid on purpose, unlike the geometry stub: a baseline wants a stable image, and
            // this stub's job is to make show mode VISIBLE (via the section below), not to detect
            // a flexible monitor row — that is the geometry gate's job.
            Color.blue.frame(height: 300)
        } slots: {
            // Rigid, same reasoning as the monitor stub above. The real strip's content is not
            // exercised here — the geometry gate covers layout, this covers the pixel diff.
            Color.yellow.frame(height: 40)
        } strips: {
            CollapsibleSection(title: "FX", summary: "3", key: .masterFX, layout: layout) {
                VStack { ForEach(0..<5, id: \.self) { _ in Slider(value: .constant(0.5)) } }
            }
        } mixer: {
            Color.red.frame(width: SurfaceMetrics.mixerWidth)
        }
    }

    func testSurfaceBaselines() throws {
        let recording = SurfaceRenderHarness.isRecording

        let cases: [(String, () -> SurfaceLayout)] = [
            ("panel-closed",  { SurfaceLayout() }),
            ("panel-library", { let l = SurfaceLayout(); l.select(panel: .library); return l }),
            ("show-mode",     { let l = SurfaceLayout(); l.toggleShowMode(); return l }),
        ]

        var rendered: [String: Data] = [:]
        for (name, make) in cases {
            let data = try XCTUnwrap(SurfaceRenderHarness.png(
                stubSurfaceForBaselines(layout: make()), size: Self.windowSize))
            rendered[name] = data
            if let reason = SurfaceRenderHarness.compareBaseline(data, named: name) {
                XCTFail(reason)
            }
        }

        // The three states must actually LOOK different. This is the assertion whose absence let
        // an identical pair sit in the suite unnoticed: comparing each render to its own baseline
        // is green even when two renders are the same image, so the duplication is invisible to
        // the comparison and only visible across it. Checked on every run, including a recording
        // one — a re-record is exactly when a stub could silently stop distinguishing states.
        for (a, b) in [("panel-closed", "panel-library"),
                       ("panel-closed", "show-mode"),
                       ("panel-library", "show-mode")] {
            XCTAssertNotEqual(rendered[a], rendered[b],
                              "\(a) and \(b) rendered byte-identically. A baseline that cannot "
                              + "differ from another cannot fail, so it gates nothing — the stub "
                              + "no longer distinguishes these two states.")
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
