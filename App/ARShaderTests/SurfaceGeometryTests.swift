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

    /// Fix-round-2, task 4, addition 1; rewritten again fix-round-1 (F1). Two prior versions of this
    /// test both asserted "cells are pinned at the floor" and both passed for the wrong reason.
    /// v1 (`testCellWidthIsPinnedAtItsFloorRegardlessOfWindowWidth`, fix-round-1 task 3) gave the
    /// `ScrollView` its own directly-set `.frame(width:)` — not faithful to production, where it is
    /// a flexible sibling in an `HStack`. v2 (this test's previous body) fixed that nesting but
    /// still built its OWN `Color.blue.frame(width: SurfaceMetrics.minCellWidth, height:
    /// SurfaceMetrics.slotCellHeight)` stand-in and compared the result to the SAME constants it was
    /// built from — a tautology. Reverting `SlotBankStripView`'s real cell frame to
    /// `.frame(minWidth:, maxWidth: .infinity)`, or deleting the frame modifier outright, left v2
    /// green (F1 review finding).
    ///
    /// **This version measures the REAL `SlotBankStripView`, not a stand-in, embedded in a real
    /// `InstrumentSurface`.** `.fixedSize(horizontal: true, vertical: false)` forces it to report
    /// its own IDEAL width (chrome + the cells row's natural width) instead of whatever a window's
    /// ambient proposal would proposal it to. If the cells' sizing chain is removed, or reverted to
    /// something that lets width follow an ambient proposal instead of reporting a fixed ideal, the
    /// measured total moves — unlike v2, which could not detect either mutation.
    ///
    /// **Honesty about what this does and does not prove (unchanged from v2, still true here):**
    /// mutation testing found NEITHER version can distinguish the actual old, buggy modifier chain
    /// from the fix, inside this harness. Reverting the REAL `SlotBankStripView`'s cell frame to the
    /// old `.aspectRatio(.fit) + .frame(minWidth:, maxWidth: .infinity)` chain, rendered inside a
    /// real `InstrumentSurface` at real window widths, still measured the total pinned here — the
    /// render harness (`SurfaceRenderHarness`, a single `NSHostingView.layoutSubtreeIfNeeded()`
    /// pass) evidently does not reproduce whatever a live, interactively-resized window did to
    /// produce the operator's screenshot. So this test does not prove the screenshot bug is fixed;
    /// it proves the fix's mechanism is what it claims to be, AND — unlike v2 — that it is coupled
    /// to production: deleting or genuinely breaking the sizing chain (not just reverting to the old
    /// proposal-dependent one, which this harness can't distinguish either way) fails it. Treat the
    /// underlying fix as STAGED, not CONFIRMED, until an operator sees the strip at full window
    /// width live.
    func testSlotBankStripCellsRowWidthIsPinnedRegardlessOfWindowWidth() throws {
        let space = "slotBankStripWidthDiag"
        func surface(instrument: Instrument, layout: SurfaceLayout) -> some View {
            InstrumentSurface(layout: layout) {
                Color.gray
            } monitors: {
                Color.blue.frame(minHeight: Self.stubMonitorIdealHeight, maxHeight: .infinity)
            } slots: {
                SlotBankStripView(instrument: instrument, layout: layout)
                    .fixedSize(horizontal: true, vertical: false)
                    .measured("strip", in: space)
            } strips: {
                Color.green.frame(minWidth: SurfaceMetrics.stripsMinWidth, minHeight: 300)
            } mixer: {
                Color.red.frame(width: SurfaceMetrics.mixerWidth)
            }
            .coordinateSpace(name: space)
        }

        let narrow = SurfaceRenderHarness.frames(
            surface(instrument: Instrument(), layout: SurfaceLayout()),
            size: CGSize(width: SurfaceMetrics.minWindowWidth, height: SurfaceMetrics.minWindowHeight))
        let wide = SurfaceRenderHarness.frames(
            surface(instrument: Instrument(), layout: SurfaceLayout()),
            size: CGSize(width: 2400, height: 1200))

        let narrowWidth = try XCTUnwrap(narrow["strip"], "harness reported no frames").width
        let wideWidth = try XCTUnwrap(wide["strip"], "harness reported no frames").width

        let cellsRowWidth = SurfaceMetrics.minCellWidth * CGFloat(SlotBank.perRow)
            + SurfaceMetrics.slotStripCellSpacing * CGFloat(SlotBank.perRow - 1)
        let expectedTotal = SurfaceMetrics.slotStripLeadingChromeWidth + cellsRowWidth

        XCTAssertEqual(narrowWidth, expectedTotal, accuracy: 1,
                       "The real SlotBankStripView's ideal width should be chrome + the eight-cell "
                       + "row's natural width — got \(narrowWidth), expected \(expectedTotal).")
        XCTAssertEqual(wideWidth, expectedTotal, accuracy: 1,
                       "…and must not move with window width. narrow=\(narrowWidth) "
                       + "wide=\(wideWidth) — a real difference here means the strip's ideal width "
                       + "somehow depends on the window, which should be structurally impossible "
                       + "given .fixedSize(horizontal: true).")
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
