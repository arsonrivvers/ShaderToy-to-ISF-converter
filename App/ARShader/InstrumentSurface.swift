import AppKit
import SwiftUI

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
    }

    /// A 6pt grab strip standing in for the panel's trailing divider.
    ///
    /// Wider than the 1pt Divider it replaces because this is aimed at with a mouse mid-session; a
    /// 1pt target is the same mistake as a 12pt chevron. It still READS as a divider — the visible
    /// rule is 1pt, the hit area is 6.
    private var panelResizeHandle: some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.001))   // hit-testable, visually absent
            .frame(width: 6)
            .overlay(Divider(), alignment: .center)
            .contentShape(Rectangle())
            .accessibilityIdentifier("surface.panelResizeHandle")
            .onHover { inside in
                if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
            .gesture(
                DragGesture(coordinateSpace: .named(Self.coordinateSpace))
                    .onChanged { value in
                        // Absolute, not incremental: the handle sits at the panel's trailing edge,
                        // so the drag's x IN THE SURFACE's space IS the intended width minus the
                        // rail. Accumulating deltas drifts when a frame is dropped mid-drag.
                        layout.setPanelWidth(Double(value.location.x) - Double(PanelRailView.width))
                    }
            )
    }

    static var coordinateSpace: String { "instrumentSurface" }
}

/// Replaced by the real panel in Task 7.
struct SettingsPanelView: View {
    let instrument: Instrument
    var body: some View { Color.clear }
}
