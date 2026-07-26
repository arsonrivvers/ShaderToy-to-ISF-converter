import Foundation

enum RemixCanvasMode: String, Codable, Equatable {
    case grid
    case comparison
    case hero
}

enum RemixZone: String, Codable, Hashable, CaseIterable {
    case breedingBay
    case lineage
    case activity
}

enum RemixKeyboardCommand: Equatable {
    case moveLeft
    case moveRight
    case moveUp
    case moveDown
    case toggleComparison
    case favorite
    case hero
    case promoteA
    case promoteB
    case exitCanvasMode
}

struct RemixWorkspaceState: Codable, Equatable {
    var canvasMode: RemixCanvasMode = .grid
    var focusedChildID: String?
    var comparedChildIDs: [String] = []
    var heroChildID: String?
    var collapsedZones: Set<RemixZone> = []
    var zoneWidths: [RemixZone: Double] = [
        .breedingBay: 280,
        .lineage: 300,
        .activity: 180,
    ]
    var previewsPaused = false

    private var preFocusCollapsed: Set<RemixZone>?
    private var preFocusWidths: [RemixZone: Double]?

    mutating func focus(_ childID: String?) {
        focusedChildID = childID
    }

    mutating func toggleComparison(_ childID: String) {
        if let existingIndex = comparedChildIDs.firstIndex(of: childID) {
            comparedChildIDs.remove(at: existingIndex)
        } else {
            comparedChildIDs.append(childID)
            if comparedChildIDs.count > 2 {
                comparedChildIDs.removeFirst(comparedChildIDs.count - 2)
            }
        }

        canvasMode = comparedChildIDs.isEmpty ? .grid : .comparison
    }

    mutating func showHero(_ childID: String) {
        focus(childID)
        heroChildID = childID
        canvasMode = .hero
    }

    mutating func showGrid() {
        canvasMode = .grid
    }

    mutating func showComparison() {
        canvasMode = comparedChildIDs.isEmpty ? .grid : .comparison
    }

    mutating func collapse(_ zone: RemixZone) {
        collapsedZones.insert(zone)
    }

    mutating func expand(_ zone: RemixZone) {
        collapsedZones.remove(zone)
    }

    mutating func resize(_ zone: RemixZone, to width: Double) {
        zoneWidths[zone] = Self.clampedWidth(width, for: zone)
    }

    mutating func enterFocusMode() {
        guard preFocusCollapsed == nil else { return }
        preFocusCollapsed = collapsedZones
        preFocusWidths = zoneWidths
        collapse(.breedingBay)
        collapse(.lineage)
    }

    mutating func exitFocusMode() {
        guard let savedCollapsed = preFocusCollapsed,
              let savedWidths = preFocusWidths
        else {
            return
        }

        collapsedZones = savedCollapsed
        zoneWidths = savedWidths
        preFocusCollapsed = nil
        preFocusWidths = nil
    }

    mutating func applyNarrowLayout(availableWidth: Double) {
        if availableWidth <= 900 {
            collapse(.lineage)
        }
        if availableWidth <= 700 {
            collapse(.breedingBay)
        }
    }

    mutating func moveFocus(
        _ command: RemixKeyboardCommand,
        columns: Int,
        childIDs: [String]
    ) {
        switch command {
        case .moveLeft, .moveRight, .moveUp, .moveDown:
            break
        default:
            return
        }

        guard !childIDs.isEmpty else { return }
        let columnCount = max(columns, 1)
        guard let focusedChildID,
              let currentIndex = childIDs.firstIndex(of: focusedChildID)
        else {
            self.focusedChildID = childIDs[0]
            return
        }

        let rowStart = (currentIndex / columnCount) * columnCount
        let rowEnd = min(rowStart + columnCount - 1, childIDs.count - 1)
        let destination: Int
        switch command {
        case .moveLeft:
            destination = max(currentIndex - 1, rowStart)
        case .moveRight:
            destination = min(currentIndex + 1, rowEnd)
        case .moveUp:
            let candidate = currentIndex - columnCount
            destination = candidate >= 0 ? candidate : currentIndex
        case .moveDown:
            let candidate = currentIndex + columnCount
            destination = candidate < childIDs.count ? candidate : currentIndex
        default:
            destination = currentIndex
        }
        self.focusedChildID = childIDs[destination]
    }

    static func accessibilitySummary(
        name: String,
        status: String,
        position: Int,
        total: Int,
        directive: String,
        actions: [String]
    ) -> String {
        "\(name). \(status). \(position) of \(total). Directive: \(directive). Actions: \(actions.joined(separator: ", "))."
    }

    static func clampedWidth(_ width: Double, for zone: RemixZone) -> Double {
        let bounds: ClosedRange<Double>
        switch zone {
        case .breedingBay:
            bounds = 240...420
        case .lineage:
            bounds = 260...420
        case .activity:
            bounds = 120...320
        }
        return min(max(width, bounds.lowerBound), bounds.upperBound)
    }
}
