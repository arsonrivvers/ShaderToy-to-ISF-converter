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
                Divider()
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
        .background(Color.black)
    }
}

/// Replaced by the real panel in Task 7.
struct SettingsPanelView: View {
    let instrument: Instrument
    var body: some View { Color.clear }
}
