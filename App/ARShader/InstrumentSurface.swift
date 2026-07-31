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

/// The four-region geometry of the instrument window: rail | panel | content | mixer, with the
/// content column split into a flexible monitor row over a content-sized deck-strip row.
///
/// Generic over its content so tests can render this exact layout code with stub views — the live
/// monitors are Metal-backed and cannot be rendered in a unit test, and a layout gate that skips
/// the layout is worthless.
struct InstrumentSurface<Panel: View, Monitors: View, Strips: View, Mixer: View>: View {
    @ObservedObject var layout: SurfaceLayout
    @ViewBuilder var panel: () -> Panel
    @ViewBuilder var monitors: () -> Monitors
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

    /// The monitors never shrink below this, however much is expanded below them.
    static var minMonitorHeight: CGFloat { 160 }
    // The panel's floor lives on SurfaceLayout, not here — it is clamped where the width is
    // written (`setPanelWidth`), so there is one source of truth rather than a view-local copy
    // that a second call site could bypass.

    var body: some View {
        HStack(spacing: 0) {
            PanelRailView(layout: layout)
            Divider()

            if layout.openPanel != nil {
                panel()
                    .frame(width: CGFloat(layout.panelWidth))
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
                // Flexible, and FIRST in the greedy order: the monitor row takes whatever the deck
                // strips are not using. Collapsing a section hands its height straight to the
                // picture — without this the feature frees space nothing uses, and "the monitors
                // are too small" is untouched no matter how much collapses.
                monitors()
                    .frame(minHeight: Self.minMonitorHeight, maxHeight: .infinity)
                Divider()
                // Content-sized: shrinks as sections collapse rather than holding its height.
                strips()
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)

            Divider()
            mixer()
        }
        .coordinateSpace(name: Self.coordinateSpace)
        .background(Color.black)
        .onPreferenceChange(PanelLeadingEdgeKey.self) { panelLeadingEdge = $0 }
    }

    /// A 6pt grab strip standing in for the panel's trailing divider.
    ///
    /// Wider than the 1pt Divider it replaces because this is aimed at with a mouse mid-session; a
    /// 1pt target is the same mistake as a 12pt chevron. It still READS as a divider — the visible
    /// rule is 1pt, the hit area is 6.
    private var panelResizeHandle: some View {
        Rectangle()
            .fill(Color.clear)   // genuinely invisible; contentShape below is what makes it hit-testable
            .frame(width: 6)
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
                        layout.setPanelWidth(Double(value.location.x) - Double(panelLeadingEdge))
                    }
            )
    }

    static var coordinateSpace: String { "instrumentSurface" }
}
