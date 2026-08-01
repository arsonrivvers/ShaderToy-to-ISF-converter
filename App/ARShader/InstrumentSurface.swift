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

    /// The deck strips' own minimum. Below this they clip rather than shrink.
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
    /// Was 1100 through master, which predates the rail and the handle. `reservedWidth` (872) plus
    /// the 280pt default panel is 1152, so 1100 clipped the mixer strip by 52pt at the app's own
    /// stated minimum — with no scroll and no clip indicator.
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

    /// The SOURCE (deck A/B) picker's fixed width.
    static let slotStripSourceWidth: CGFloat = 90

    /// The RECALL TO (five-way) picker's fixed width.
    static let slotStripRecallWidth: CGFloat = 220

    /// The gap between SOURCE and RECALL TO, RECALL TO and the divider, and the divider and the
    /// cells region — three of these.
    static let slotStripGapWidth: CGFloat = 10
    static let slotStripGapCount: CGFloat = 3

    /// Spacing between adjacent cells inside the (scrollable) cells row.
    static let slotStripCellSpacing: CGFloat = 6

    /// Everything in the slot strip that is fixed, BEFORE the cells region: both padding edges,
    /// both pickers, the three gaps around them, and the one `Divider()` separating RECALL TO
    /// from the cells. Derived from its own named parts rather than a single magic number, so a
    /// future change to any one part moves this automatically and the fit test below catches a
    /// regression instead of silently drifting stale.
    static var slotStripLeadingChromeWidth: CGFloat {
        slotStripPadding * 2 + slotStripSourceWidth + slotStripRecallWidth
            + slotStripGapWidth * slotStripGapCount + dividerWidth
    }

    /// A cell's own floor. 56pt (phase 3b/7R) was sized for a bare index-and-name row; phase 3c
    /// (task 3) gave the cell a 16:9 thumbnail instead, and a 16:9 image at 56pt wide is 31pt
    /// tall — unreadable as a still, let alone as a contact-sheet look the operator recognises at
    /// a glance. 96pt keeps the thumbnail legible (54pt tall at the floor) while the cell's
    /// `.contentShape(Rectangle())` still never drops below a size where adjacent cells' hit areas
    /// could overlap — the defect this constant has existed to prevent since 7R.
    static let minCellWidth: CGFloat = 96

    // MARK: Slot strip rows (task 7R)

    /// Feel constant for the row-resize drag's snap-to-whole-rows arithmetic: `SlotCell`'s own
    /// floor height — `minCellWidth` at the 16:9 aspect ratio the thumbnail enforces (96 × 9/16 =
    /// 54pt) — plus the spacing between rows (`slotStripCellSpacing`, 6pt) = 60.
    ///
    /// Computed against the floor deliberately, not as an approximation of it: fix-round-1 (task
    /// 3, F3) found the floor IS the cell's real width at every window size, not just the narrowest
    /// one. `.fixedSize(vertical: true)` (which `InstrumentSurface` wraps the whole `slots()`
    /// region in) makes the row report its own ideal height upward instead of receiving one from
    /// outside, and combined with the `ScrollView(.horizontal)` cells sit in, `.aspectRatio(16/9,
    /// .fit)` resolves to `minCellWidth` regardless of window width — cells do not expand at a
    /// wide window (confirmed:
    /// `SurfaceGeometryTests.testCellWidthIsPinnedAtItsFloorRegardlessOfWindowWidth`). So there is
    /// no second, wider case this constant also needs to satisfy. Not asserted by any layout gate
    /// beyond that — a drag that snaps a few points early or late is a feel issue, not a
    /// correctness one; the correctness invariant is that `bankRows` never touches `SlotBank`,
    /// which is tested directly.
    static let slotStripRowHeight: CGFloat = 60
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
