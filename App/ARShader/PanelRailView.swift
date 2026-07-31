import SwiftUI

/// The always-visible tool rail. Fixed 44pt, full height, far left.
///
/// It never hides — including in show mode. A rail that could disappear would leave the operator
/// with no way back to a tool except a keyboard shortcut they may not remember mid-set.
///
/// Adding a tool in a later phase is one `PanelID` case. That is the point of a rail over a set of
/// fixed regions: a new tool costs no layout renegotiation and no screen space when closed.
struct PanelRailView: View {
    @ObservedObject var layout: SurfaceLayout

    static let width: CGFloat = 44

    var body: some View {
        VStack(spacing: 4) {
            ForEach(Array(PanelID.allCases.enumerated()), id: \.element) { index, panel in
                Button { layout.select(panel: panel) } label: {
                    Image(systemName: panel.systemImage)
                        .font(.system(size: 15))
                        // 44x44 minimum hit target — this gets aimed at mid-set.
                        .frame(width: Self.width, height: Self.width)
                        .background(layout.openPanel == panel
                                    ? Color.accentColor.opacity(0.30) : .clear)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("\(panel.title) (⌘⌥\(index + 1))")
            }
            Spacer()
        }
        .frame(width: Self.width)
        .background(Color.black)
    }
}
