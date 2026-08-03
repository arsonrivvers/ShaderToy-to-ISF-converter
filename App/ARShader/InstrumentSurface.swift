import AppKit
import SwiftUI

/// Carries the panel's measured leading edge (in `InstrumentSurface.coordinateSpace`) up from the
/// panel's own geometry to the resize handle's drag handler.
///
/// Measured rather than assumed: the panel's leading edge sits after the rail AND a `Divider()`,
/// and macOS divider thickness is not a constant worth hardcoding. Reading the real geometry means
/// this stays correct if the divider's rendered width ever changes.
private struct PanelLeadingEdgeKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

/// Carries the surface's own width down to the resize handle, so the panel can be clamped against
/// the window it is actually in rather than against a fixed guess.
private struct SurfaceWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

/// Fixed metrics of the instrument surface.
///
/// A non-generic home because `InstrumentSurface` is generic over its five content slots, and Swift
/// has no stored static properties in generic types — the same reason `coordinateSpace` below is
/// computed rather than stored.
///
/// These were literals scattered across three files until the phase 3a branch review found that the
/// window's declared minimum had never been raised for the rail and handle this phase added, so at
/// the app's own minimum width the mixer strip was drawn 52pt outside the window.
enum SurfaceMetrics {
    /// Rendered thickness of a macOS `Divider()`. Two sit in the surface: after the rail, and
    /// before the mixer strip.
    static let dividerWidth: CGFloat = 1
    static let dividerCount: CGFloat = 2

    /// The grab strip standing in for the panel's trailing divider. Present only while a panel is
    /// open, which is also the only time the panel competes for width.
    static let resizeHandleWidth: CGFloat = 6

    /// Minimum height for a control that gets hit **during** a set, in the dark, without looking.
    ///
    /// 44 is this project's stated floor and the platform HIG's. Nothing in the instrument met it
    /// before 2026-08-03 — the 2026-08-03 Client Success review found the entire sizing inventory
    /// running at 39–59% of it, and no `44` constant existed anywhere outside the panel rail's
    /// width. Note what automated a11y checking does NOT cover: axe and its equivalents have no
    /// target-size rule, so this can only ever be held by a named constant and a reviewer's eye.
    ///
    /// **BLACKOUT and SHOW MODE deliberately do NOT use this yet.** Their current 26/22 came from
    /// an explicit operator decision on 2026-07-30 (the 56pt slab was reverted as wasted space,
    /// on the reasoning that ⌘B and Escape are how blackout actually gets hit). The review argues
    /// that reasoning holds only while the operator's hands are on the keyboard. That is a live
    /// question for the operator, not something to settle by editing a constant.
    static let stageTarget: CGFloat = 44

    /// Minimum height for controls used while setting up rather than while playing — Clear, Set,
    /// the scale fields. Still well above a `.controlSize(.small)` 16pt, still not stage-sized.
    static let secondaryTarget: CGFloat = 32

    /// The deck strips' own minimum. Below this they clip rather than shrink.
    ///
    /// **A hand-chosen usability floor, NOT a measured one — and this has been tried and reverted
    /// once (fix-round-1→2, task 4, F3/F4).** Fix-round-1 raised this 620→830 off
    /// `testTheDeckStripsFloorCoversTheirMeasuredNaturalWidth`, which measured
    /// `deckStripsContent.fixedSize(horizontal: true, vertical: false)` at 815pt (empty
    /// configuration, sections forced open for determinism) or ~993pt populated. **That measurement
    /// technique is wrong for what this constant claims to be.** `.fixedSize(horizontal:)` asks
    /// SwiftUI for a view's IDEAL width — for `Text` with no `lineLimit`, that is its full
    /// single-line, UNWRAPPED width. A MINIMUM width is roughly its widest word. The two differ by
    /// hundreds of points, and the 815/993 figures were almost entirely three explanatory sentences
    /// (`FXChainView`'s "Load a shader with this chain selected in the library.", ×3 for deck A FX /
    /// deck B FX / MASTER FX; `InstrumentView`'s "Applied to the program feed, before blackout.";
    /// `ShaderControlsView`'s "No shader loaded") measured as if they could never wrap. **Nothing
    /// clips at 620pt** — every one of those sentences wraps happily in production, and the deck
    /// strips have no floor-driven clipping at all: `Text` wraps, `Picker`s compress, `Slider`s
    /// shorten. That graceful degradation is exactly the surface's own doctrine (the slot strip
    /// scrolls rather than compress for the same reason). Under the "ideal width" criterion,
    /// `stripsMinWidth` becomes a function of whatever content happens to be loaded — unbounded, and
    /// therefore not a "minimum" in any sense this constant's own doc line ("below this they clip")
    /// claims. It also cost real hardware: 1390 (the raised `minWindowWidth` this drove) does not
    /// fit a 13"/14" MacBook at a common "Larger Text" scaled resolution (1280–1352 logical), and
    /// leaves only 50pt of spare even on a 13" M1 Air at default scaling — with
    /// `OutputDestination.floating` putting the projector preview in a second window on the SAME
    /// screen, that is a real live-VJ regression, not a cosmetic one. Reverted to 620.
    /// `testTheDeckStripsFloorCoversTheirMeasuredNaturalWidth` was deleted rather than retargeted:
    /// the deck strips do not actually have a clip-below-this floor to measure (see above), so a
    /// "no control is clipped or truncated" test on this content would either be vacuous (nothing
    /// ever clips, by design) or require inventing an arbitrary usability threshold no more
    /// principled than this hand-picked 620. If a future review wants to re-derive this number,
    /// start from "at what width does a specific control become genuinely hard to operate" (e.g. a
    /// `Slider` or `Picker` compressed below a usable hit-target), not from an unwrapped-text ideal
    /// width — and re-read this comment first.
    static let stripsMinWidth: CGFloat = 620

    /// The mixer strip — BLACKOUT, SHOW MODE, the crossfader and the OUTPUT destination picker.
    /// Fixed width, and never a region anything else may cover.
    static let mixerWidth: CGFloat = 200

    /// Everything the panel shares the window with, at the panel's widest legal moment.
    static var reservedWidth: CGFloat {
        PanelRailView.width + dividerWidth * dividerCount + resizeHandleWidth
            + stripsMinWidth + mixerWidth
    }

    /// The window's declared minimum, sized so that every region above fits WITH a panel open at
    /// the default 280pt width, plus slack for divider-thickness variation.
    ///
    /// Was 1100 through master, which predates the rail and the handle; raised to 1180 when
    /// `reservedWidth` was 872 (1180 − (872 + 280) = 28pt slack).
    ///
    /// **Tried 1390, rejected (fix-round-1→2, task 4, F3/F4).** Fix-round-1 raised `stripsMinWidth`
    /// 620→830 off a measurement of `deckStripsContent`'s IDEAL (unwrapped) width, which moved
    /// `reservedWidth` to 1082 and, carrying the same 28pt slack, this constant to 1390. Re-review
    /// found the underlying measurement wrong — see `stripsMinWidth`'s doc comment for the full
    /// account — and 1390 alone would have been a real regression even if the arithmetic behind it
    /// had been sound: it does not fit a 13"/14" MacBook at a common "Larger Text" scaled resolution
    /// (1280–1352 logical), the app would refuse to open on hardware it runs on today, and even a
    /// 13" M1 Air at default scaling (1440) would leave too little room for
    /// `OutputDestination.floating`'s second, same-screen preview window. Reverted to 1180. If
    /// `stripsMinWidth` (or any other reserved region) is ever raised again for a REAL reason, redo
    /// this arithmetic from the shipped numbers — do not assume 1180 still holds without checking.
    static let minWindowWidth: CGFloat = 1180
    static let minWindowHeight: CGFloat = 720

    // MARK: Slot strip (task 6R)
    //
    // `SlotBankStripView`'s own leading chrome, hoisted here rather than left as magic numbers
    // in the view — a fix-round-1 review found that at `minWindowWidth` with a panel open, eight
    // cells were squeezed to ~31pt, below `SlotCell`'s own ~32pt floor, so adjacent cells'
    // `.contentShape(Rectangle())` hit areas overlapped and an edge click could fire the WRONG
    // slot on the one surface whose entire safety property is that a click cannot destroy
    // anything. `slotStripLeadingChromeWidth` and `minCellWidth` make that arithmetic testable
    // (`testEightCellsFitAtTheMinimumWindowWidthWithNoPanelOpen`); the cells themselves now sit
    // in a horizontal `ScrollView` so any further squeeze degrades into visible scrolling rather
    // than invisible overlap.

    /// The strip's own outer `.padding(_:)` (same value on all four sides).
    static let slotStripPadding: CGFloat = 8

    /// The RECALL TO (two-way, task 4) picker's fixed width. Reuses phase 3b's SOURCE width: it is
    /// the same widget — a `DeckID` segmented picker with the same "A"/"B" labels — SOURCE is gone
    /// (task 4), not shrunk, so there is no separate SOURCE constant to keep in sync with this one.
    static let slotStripRecallWidth: CGFloat = 90

    /// The gap between RECALL TO and the divider, and the divider and the cells region — two of
    /// these since task 4 removed SOURCE (was three, with a SOURCE-to-RECALL-TO gap too).
    static let slotStripGapWidth: CGFloat = 10
    static let slotStripGapCount: CGFloat = 2

    /// Spacing between adjacent cells inside the (scrollable) cells row.
    static let slotStripCellSpacing: CGFloat = 6

    /// Everything in the slot strip that is fixed, BEFORE the cells region: both padding edges,
    /// the RECALL TO picker, the two gaps around it, and the one `Divider()` separating RECALL TO
    /// from the cells. Derived from its own named parts rather than a single magic number, so a
    /// future change to any one part moves this automatically and the fit test below catches a
    /// regression instead of silently drifting stale.
    static var slotStripLeadingChromeWidth: CGFloat {
        slotStripPadding * 2 + slotStripRecallWidth
            + slotStripGapWidth * slotStripGapCount + dividerWidth
    }

    /// The cell's legibility and hit-target floor (task 3). Below this the 9pt monospaced name is
    /// unreadable and, at ~31.1pt against a 32pt floor, hit areas overlapped badly enough that an
    /// edge click fired the NEIGHBOURING slot (phase 3b) — the one surface whose entire safety
    /// property is that a click cannot destroy anything. Absolute, never a percentage: macOS text
    /// scales with the user's system setting, not with the window.
    ///
    /// An independent literal again (task 4C), not derived from a height constant — task 4 briefly
    /// made width the derived quantity (`slotCellHeight * 16/9`) because it made height the single
    /// exact size every cell reached. Task 4C reopens the width axis into a range
    /// (`minCellWidth`...`maxCellWidth`), so there is no longer one exact height to derive width
    /// from — height instead follows whichever width is DRAWN, via the 16:9 `.aspectRatio` already
    /// on `SlotCell`'s content. This value remains what every other call site (the eight-cell fit
    /// gate, the anti-overlap gate) has always reasoned about it as: a floor a cell must never
    /// render narrower than.
    static let minCellWidth: CGFloat = 96

    /// The cell's growth ceiling (task 4C). Without one, task 3's `.frame(minWidth: 96, maxWidth:
    /// .infinity)` let `.aspectRatio(16/9)` turn window width into row HEIGHT, and the operator
    /// rejected it on device ("I can see us shrinking this bar a lot"). The brief, the responsive
    /// spec, and the task-4 review all quoted a specific figure for how bad it got — ~207pt cells,
    /// ~116pt rows — but that figure does not reconcile against the operator's actual display
    /// (confirmed, fix round 2: see below): task 3's chain gives ≈164pt cells at the operator's real
    /// scaling, not 207. **Corrected rather than repeated: the ~207/~116 figure was read off a
    /// screenshot IMAGE's pixel width, not logical points, and should not be re-derived from — the
    /// operator's complaint and this task's fix both stand regardless, only that specific number was
    /// wrong.** Task 4 swung to the opposite extreme, an exact `.frame(width: 96, height: 54)` that
    /// never moved at all, which review flagged as "cell area drops ~4.6x in one step to a size
    /// never seen on device." `.frame(minWidth:maxWidth:)` is `clamp()`; a floor with no ceiling, or
    /// an exact size with neither, are both a clamp missing one of its three values.
    ///
    /// **160, chosen against the operator's ACTUAL display — 16" MacBook Pro at Default scaling,
    /// 1728×1117 logical points, confirmed by the operator directly (fix round 2), not assumed or
    /// read off a screenshot (fix round 1, F3, briefly carried a "state both readings" version of
    /// this comment before that answer arrived; the "More Space" alternative it hedged against is
    /// now known not to apply and has been removed).** With no panel open — the widest the cells
    /// region ever gets — `contentColumn` is 1482pt (1728 − rail 44 − dividers 2 − mixer 200);
    /// `cellsRegion` is 1482 − `slotStripLeadingChromeWidth` (127) = 1355pt. Eight cells' natural,
    /// unclamped share of that is `(1355 − spacing×7) / 8` ≈ 164pt. A 160pt ceiling lands just under
    /// that: eight cells at 160 plus seven 6pt gaps is 1322pt, **33pt of slack** in the 1355pt
    /// available — close to an exact fit on the operator's own machine, no scroll needed. With a
    /// panel open at its default 280pt, the same arithmetic gives ≈128pt per cell — comfortably
    /// inside the range, growing less because there is less room, exactly the intended behaviour.
    ///
    /// **If the target scaling ever changes, re-derive this constant — do not assume 33pt of slack
    /// still holds.** At "More Space" scaling (2056pt logical) the SAME arithmetic gives ≈205pt
    /// unclamped, and a 160pt ceiling would leave ~361pt dead to the right of the strip instead —
    /// the top-end failure this task exists to prevent, on that reading. The operator does not run
    /// that scaling today, which is the only reason 160 is a close-to-exact fit rather than a
    /// generous one.
    ///
    /// **Smoke leg 45 (Task 8) is still the on-device confirmation step** — the arithmetic above is
    /// now grounded in the operator's stated real resolution, not a screenshot estimate, but the
    /// strip has not yet been SEEN rendering at full window width live.
    ///
    /// **Secondary, and worth keeping separate from the width arithmetic above:** the operator's
    /// actual complaint was HEIGHT ("I can see us **shrinking** this bar a lot"), and this ceiling
    /// was chosen to maximise WIDTH fill — at 160, the row pitch (`maxCellWidth * 9/16 +
    /// slotStripCellSpacing` = 96pt) is a real fraction of the row height the operator actually
    /// rejected, even setting the exact rejected number aside. The strip cannot structurally repeat
    /// that specific failure (both the monitor row and this strip are `.fixedSize(vertical: true)`;
    /// a taller strip takes space from the flexible deck strips below it, not from the monitors),
    /// but nothing in this suite bounds the strip's resulting HEIGHT at any window width — the axis
    /// that was actually rejected on device.
    static let maxCellWidth: CGFloat = 160

    // MARK: Slot strip rows (task 7R, revised task 4C)
    //
    // `slotStripRowHeight` used to live here as a constant (`slotCellHeight + slotStripCellSpacing`)
    // — task 4's fix-round-2 found that even that formula did not hold in production, because the
    // "cell width is pinned regardless of window" premise it rested on did not survive contact with
    // a real, interactively-resized window (see `SurfaceGeometryTests`'s extensive account). Task 4C
    // makes cell width a genuine range rather than a single value, so a constant row height is not
    // just fragile now, it is categorically wrong — the resize drag divides by it, and dividing by a
    // number that no longer matches the DRAWN pitch desyncs the drag from what it is dragging (task
    // 4 found the drag reading 60 against a real ~122pt pitch from exactly this kind of drift).
    // `SlotBankStripView.slotStripRowHeight` is now an instance property computed from `cellWidth`,
    // the SAME clamped value every cell in the strip actually draws at (see that property's doc
    // comment in `SlotBankStripView.swift`), not a constant anywhere in this enum.
}

/// The four-region geometry of the instrument window: rail | panel | content | mixer, with the
/// content column split into a content-sized monitor row, a content-sized slot strip, and a
/// flexible deck-strip row.
///
/// Generic over its content so tests can render this exact layout code with stub views — the live
/// monitors are Metal-backed and cannot be rendered in a unit test, and a layout gate that skips
/// the layout is worthless.
struct InstrumentSurface<Panel: View, Monitors: View, Slots: View, Strips: View,
                          Mixer: View>: View {
    @ObservedObject var layout: SurfaceLayout
    @ViewBuilder var panel: () -> Panel
    @ViewBuilder var monitors: () -> Monitors
    @ViewBuilder var slots: () -> Slots
    @ViewBuilder var strips: () -> Strips
    @ViewBuilder var mixer: () -> Mixer

    /// The panel's measured leading-edge X, in `Self.coordinateSpace`. Written by the
    /// `PanelLeadingEdgeKey` preference from the panel's own geometry; read by the resize handle's
    /// drag handler so the arithmetic never has to assume a divider's rendered width.
    @State private var panelLeadingEdge: CGFloat = 0

    /// Whether the resize handle currently holds a pushed `NSCursor`. Tracked so push/pop stay
    /// balanced: a bare hover-in/hover-out pair assumes hover-out always fires, but SwiftUI can
    /// remove the handle (panel closes mid-hover, e.g. ⌘⌥1) without ever calling `onHover(false)`,
    /// which would leave the resize cursor stuck for the rest of the session.
    @State private var isResizeCursorPushed = false

    /// The surface's own width, in points. Read by the resize handle so a drag is clamped against
    /// the real window rather than an assumed one. Zero until the first preference lands, which the
    /// drag handler treats as "unknown" rather than as a zero-width window.
    @State private var surfaceWidth: CGFloat = 0

    /// The content column's (monitors/slots/strips) own resolved width, republished to
    /// `SlotBankStripView` via `@Environment(\.slotBankContentColumnWidth)` — see the `.onAppear`/
    /// `.onChange` measurement below (in `body`) for why this is fed imperatively rather than via a
    /// `PreferenceKey` like `surfaceWidth` above. Zero until the first measurement lands, same
    /// "unknown" convention as `surfaceWidth`.
    @State private var contentColumnWidth: CGFloat = 0

    // No monitor-height floor: the strip is content-sized, so its height comes from the tiles'
    // aspect ratio and nothing below it can squeeze it. A floor existed while the row was
    // flexible; it went with that design.
    //
    // The panel's floor lives on SurfaceLayout, not here — it is clamped where the width is
    // written (`setPanelWidth`), so there is one source of truth rather than a view-local copy
    // that a second call site could bypass.

    var body: some View {
        HStack(spacing: 0) {
            PanelRailView(layout: layout)
            Divider()

            if layout.openPanel != nil {
                panel()
                    // The DRAWN width, not the stored one: the window can be shrunk after the
                    // drag, and a stored width that no longer fits must not push the mixer strip
                    // off-screen. The operator's preference is kept, not rewritten.
                    .frame(width: CGFloat(layout.drawnPanelWidth(
                        inSurfaceOfWidth: surfaceWidth > 0 ? Double(surfaceWidth) : .infinity)))
                    .frame(minWidth: CGFloat(SurfaceLayout.minPanelWidth))
                    .accessibilityIdentifier("surface.panel")
                    .background(
                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: PanelLeadingEdgeKey.self,
                                value: proxy.frame(in: .named(Self.coordinateSpace)).minX)
                        }
                    )
                panelResizeHandle
            }

            VStack(spacing: 0) {
                // CONTENT-SIZED, deliberately. The monitor strip takes its height from the tiles'
                // 16:9 ratio against the available width, so it changes only when the WINDOW
                // changes — never when a section below it collapses.
                //
                // This reverses an earlier version of this phase, which made the row flexible so
                // freed height would flow to the picture. It did, and on device that read as the
                // previews jumping every time PARAMETERS was opened or closed. Stability beat
                // size: a preview that moves when you touch an unrelated control is worse than a
                // smaller one that stays put (operator, 2026-07-31). What collapsing buys now is
                // less scrolling in the strips.
                monitors()
                    .fixedSize(horizontal: false, vertical: true)
                Divider()
                // Also CONTENT-SIZED, for the same reason as the monitors above: the slot strip
                // (task 6R) sits between the monitors and the deck strips, and it must take height
                // from the flexible region below it — never from the monitors above. Both the
                // monitor row and this strip are pinned; only the deck strips give.
                slots()
                    .fixedSize(horizontal: false, vertical: true)
                Divider()
                // Flexible, and TOP-ALIGNED: the strips absorb whatever the monitor strip and the
                // slot strip do not take, and scroll within it when a parameter list is long — but
                // their content hangs from the top of that region rather than centring in it.
                // Centred, a collapsed surface left a large empty band under the monitor strip with
                // the deck controls floating in the middle of the window.
                //
                // Top alignment is also what makes room for the strips the operator expects to add
                // below this one: a centred region would push its content around every time a new
                // strip appeared underneath.
                strips()
                    .frame(maxHeight: .infinity, alignment: .top)
            }
            .frame(maxWidth: .infinity)
            // Measured HERE, on the content column itself — not by `SlotBankStripView` measuring
            // itself from inside `slots()`. Republished to the slot strip via `.environment`, below.
            //
            // `.onAppear`/`.onChange`, NOT `.preference`/`.onPreferenceChange`.
            //
            // **Corrected, fix round 1 (F2): the original version of this comment overgeneralised —
            // stated as a rule about SwiftUI, when it should have been stated as what was observed in
            // this specific reproduction.** It claimed "a `ScrollView` present ANYWHERE in the
            // rendered tree" breaks ANY unrelated `PreferenceKey`. `SlotBankStripView`'s
            // `DrawnCellWidthKey`/`DrawnRowHeightKey` are ordinary `PreferenceKey`s, reported from
            // `SlotBankStripView.body`'s own top level — whose subtree CONTAINS the cells
            // `ScrollView` — and they resolve correctly, which the rule as originally stated cannot
            // explain.
            //
            // A specific alternative was then proposed and TESTED, not just considered: that the
            // original 0-result was an under-settled harness (two fixed `layoutSubtreeIfNeeded()`
            // passes had separately been confirmed to under-settle a DIFFERENT case — see
            // `SurfaceRenderHarness.preferenceValue`'s own doc comment), and a longer fixed-point
            // settle loop would resolve it. Retried directly against this exact measurement (restored
            // the `PreferenceKey` route here, read through `SurfaceRenderHarness.preferenceValue`)
            // at the loop's normal 10-pass cap, then again with the cap temporarily raised to 60: BOTH
            // runs still measured 0 at every window width tested. That specific alternative did not
            // hold in this reproduction either.
            //
            // **What was actually, repeatedly OBSERVED, in two independent reproductions in this same
            // task (this measurement, and `SlotBankStripView.renderedCellWidth`'s own investigation,
            // fix round 1 F1) — stated as what was seen, not asserted as a settled fact about how
            // SwiftUI's `PreferenceKey` system works in general:** a `PreferenceKey` value established
            // by a `.background(GeometryReader)` measuring something and then bubbling that value UP
            // THROUGH an ancestor that wraps a `ScrollView`-containing descendant, or reported from
            // WITHIN the `ScrollView`'s own content, did not reach an external `.onPreferenceChange`
            // listener in this harness, in either reproduction, at any settle-loop length tried up to
            // 60 passes. A `PreferenceKey` whose value has no such link (`DrawnCellWidthKey`, sourced
            // from an `@Environment` value; `SurfaceWidthKey`, this `HStack`'s own ambient-proposal-
            // driven size, read directly from outside with nothing measured across a `ScrollView`
            // boundary) resolved fine in every configuration tried. `.onChange(of:)` is an imperative
            // side effect at the `GeometryReader` itself, not a value bubbling through `PreferenceKey`'s
            // `reduce`, and it reported correctly everywhere the `.preference` route did not. Neither
            // the original blanket claim nor the "just needs more passes" alternative survived direct
            // retesting; this is the narrower claim that did, and it is offered as evidence from a
            // specific reproduction for the next person to judge, not as a general SwiftUI rule.
            .background(
                GeometryReader { proxy in
                    Color.clear
                        .onAppear { contentColumnWidth = proxy.size.width }
                        .onChange(of: proxy.size.width) { newValue in contentColumnWidth = newValue }
                }
            )
            .environment(\.slotBankContentColumnWidth, contentColumnWidth)

            Divider()
            mixer()
        }
        .coordinateSpace(name: Self.coordinateSpace)
        .background(
            GeometryReader { proxy in
                Color.black.preference(key: SurfaceWidthKey.self, value: proxy.size.width)
            }
        )
        .onPreferenceChange(PanelLeadingEdgeKey.self) { panelLeadingEdge = $0 }
        .onPreferenceChange(SurfaceWidthKey.self) { surfaceWidth = $0 }
    }

    /// A 6pt grab strip standing in for the panel's trailing divider.
    ///
    /// Wider than the 1pt Divider it replaces because this is aimed at with a mouse mid-session; a
    /// 1pt target is the same mistake as a 12pt chevron. It still READS as a divider — the visible
    /// rule is 1pt, the hit area is 6.
    private var panelResizeHandle: some View {
        Rectangle()
            .fill(Color.clear)   // genuinely invisible; contentShape below is what makes it hit-testable
            .frame(width: SurfaceMetrics.resizeHandleWidth)
            .overlay(Divider(), alignment: .center)
            .contentShape(Rectangle())
            .accessibilityIdentifier("surface.panelResizeHandle")
            .onHover { inside in
                // Balanced and idempotent: only push if we don't already hold a push, only pop if
                // we do. See `isResizeCursorPushed`'s doc comment for why an unguarded pop can be
                // skipped entirely.
                if inside {
                    guard !isResizeCursorPushed else { return }
                    NSCursor.resizeLeftRight.push()
                    isResizeCursorPushed = true
                } else {
                    guard isResizeCursorPushed else { return }
                    NSCursor.pop()
                    isResizeCursorPushed = false
                }
            }
            .onDisappear {
                // Backstop for the case `onHover(false)` never fires: the panel closes (⌘⌥1, or
                // clicking the active rail icon) while the pointer is still over the handle, and
                // SwiftUI tears the view down without a final hover-out.
                guard isResizeCursorPushed else { return }
                NSCursor.pop()
                isResizeCursorPushed = false
            }
            .gesture(
                DragGesture(coordinateSpace: .named(Self.coordinateSpace))
                    .onChanged { value in
                        // Absolute, not incremental: the drag's x IN THE SURFACE's space, minus the
                        // panel's MEASURED leading edge (not an assumed rail-width + divider-width
                        // constant), is the intended width. Accumulating deltas drifts when a frame
                        // is dropped mid-drag.
                        // Clamped against the surface's real width so a drag past the window edge
                        // cannot hand the panel the whole window. `surfaceWidth` is 0 until the
                        // first preference lands; that is "unknown", not "zero-width", so it falls
                        // back to the model's absolute ceiling rather than pinning to the floor.
                        layout.setPanelWidth(
                            Double(value.location.x) - Double(panelLeadingEdge),
                            availableWidth: surfaceWidth > 0 ? Double(surfaceWidth) : .infinity)
                    }
            )
    }

    static var coordinateSpace: String { "instrumentSurface" }
}
