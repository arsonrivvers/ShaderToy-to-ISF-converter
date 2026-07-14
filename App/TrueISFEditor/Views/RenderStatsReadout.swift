import SwiftUI

/// Small monospaced live readout: "60 FPS · 1.3 ms GPU". Renders nothing until the first snapshot.
struct RenderStatsReadout: View {
    @ObservedObject var model: RenderStatsModel

    var body: some View {
        if let s = model.stats {
            Text(s.readoutLabel)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
                .help("Live render rate · mean GPU frame time")
        }
    }
}

/// Resolves the active engine's stats model off the coordinator (nil for WebKit → shows nothing)
/// and re-resolves when the renderer switches.
struct RenderStatsSlot: View {
    @ObservedObject var coordinator: PreviewCoordinator

    var body: some View {
        if let model = coordinator.renderStats {
            RenderStatsReadout(model: model)
        }
    }
}
