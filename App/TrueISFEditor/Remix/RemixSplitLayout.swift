import Foundation

struct RemixSplitLayout: Equatable {
    var state: RemixWorkspaceState

    mutating func recordPointerWidth(_ width: Double, zone: RemixZone) {
        state.resize(zone, to: width)
    }

    mutating func resizeByKeyboard(_ zone: RemixZone, direction: Int) {
        let currentWidth = appliedWidth(for: zone)
        let step = direction == 0 ? 0 : (direction > 0 ? 20.0 : -20.0)
        state.resize(zone, to: currentWidth + step)
    }

    func appliedWidth(for zone: RemixZone) -> Double {
        let defaultWidth: Double
        switch zone {
        case .breedingBay:
            defaultWidth = 280
        case .lineage:
            defaultWidth = 300
        case .activity:
            defaultWidth = 180
        }
        return RemixWorkspaceState.clampedWidth(
            state.zoneWidths[zone] ?? defaultWidth,
            for: zone
        )
    }
}
