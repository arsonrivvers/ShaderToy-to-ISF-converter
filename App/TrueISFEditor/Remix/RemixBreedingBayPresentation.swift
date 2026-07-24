import SwiftUI

enum RemixParentSourceAction: Equatable {
    case library
    case currentEditor
    case paste
    case shadertoy
}

enum RemixParentRecoveryKind: Equatable, Hashable {
    case retryFetch
    case retryCurrentEditor
    case chooseLibrary
    case useAPIKey
    case paste
}

struct RemixParentRecoveryAction: Equatable {
    let title: String
    let kind: RemixParentRecoveryKind
}

enum RemixActionFontContainer: Equatable {
    case breedingBay
    case workspaceToolbar
    case reopenControls
    case resizeMenus
}

enum RemixTextPolicy {
    static let basePointSize: CGFloat = 14
    static let usesRelativeStyles = true
    static let usesRelativeScaling = true
    static let criticalTextLineLimit: Int? = nil
    static let allowsFlexibleVerticalGrowth = true
    static let actionContainers: [RemixActionFontContainer] = [
        .breedingBay,
        .workspaceToolbar,
        .reopenControls,
        .resizeMenus,
    ]
    static let bodyFont = Font.custom(
        ".AppleSystemUIFont",
        size: basePointSize,
        relativeTo: .body
    )

    static func minimumControlHeight(base: Double, textScale: Double) -> Double {
        base * max(textScale, 1)
    }
}

typealias RemixAccessibleTextLayout = RemixTextPolicy

enum RemixWorkspaceFocusToken: Hashable {
    case parentSource(ParentSlot)
    case pasteSource(ParentSlot)
    case collapseZone(RemixZone)
    case reopenZone(RemixZone)
    case crossoverSettings
    case canvas
}

struct RemixBreedingBayPresentation: Equatable {
    let mode: RemixMode
    let parentAID: String?
    let parentBID: String?
    let parentLoadState: RemixParentLoadState

    var heading: String {
        parentAID == nil && parentBID == nil ? "Choose a starting shader" : "Breeding Bay"
    }

    var shortestPath: String {
        switch mode {
        case .mutate:
            return parentAID == nil ? "Add Parent A to begin." : "Ready to generate."
        case .crossover:
            if parentAID == nil { return "Add Parent A, then add Parent B." }
            if parentBID == nil { return "Add Parent B to continue." }
            return "Ready to generate."
        }
    }

    var generateDisabledReason: String? {
        if parentAID == nil { return "Generate unavailable: Parent A is missing." }
        if mode == .crossover && parentBID == nil {
            return "Generate unavailable: Parent B is missing."
        }
        return nil
    }

    var generateResolvingAction: String? {
        if parentAID == nil { return "Use Add Parent A." }
        if mode == .crossover && parentBID == nil { return "Use Add Parent B." }
        return nil
    }

    func parentActionTitle(for slot: ParentSlot) -> String {
        "\(hasParent(slot) ? "Replace" : "Add") \(Self.parentName(slot))"
    }

    func sourceActionLabel(_ source: RemixParentSourceAction, slot: ParentSlot) -> String {
        "\(parentActionTitle(for: slot)) from \(Self.sourceName(source))"
    }

    func actionableSourceLabel(
        _ source: RemixParentSourceAction,
        slot: ParentSlot,
        identity: String
    ) -> String {
        "\(sourceActionLabel(source, slot: slot)): \(identity)"
    }

    var retryRequest: RemixParentRequest? {
        switch parentLoadState {
        case .failed(let request, _), .cancelled(let request):
            return request
        default:
            return nil
        }
    }

    var recoveryActions: [RemixParentRecoveryAction] {
        guard let request = retryRequest else { return [] }
        let parent = Self.parentName(request.slot)
        switch request.spec {
        case .shadertoyLink:
            return [
                RemixParentRecoveryAction(title: "Retry Fetch for \(parent)", kind: .retryFetch),
                RemixParentRecoveryAction(title: "Use API Key for \(parent)", kind: .useAPIKey),
                RemixParentRecoveryAction(title: "Paste ISF for \(parent)", kind: .paste),
            ]
        case .currentEditor:
            return [
                RemixParentRecoveryAction(
                    title: "Retry Current Editor for \(parent)",
                    kind: .retryCurrentEditor
                ),
                RemixParentRecoveryAction(title: "Paste ISF for \(parent)", kind: .paste),
            ]
        case .libraryFile:
            return [
                RemixParentRecoveryAction(
                    title: "Choose Another Library Shader for \(parent)",
                    kind: .chooseLibrary
                ),
                RemixParentRecoveryAction(title: "Paste ISF for \(parent)", kind: .paste),
            ]
        case .pastedISF:
            return [
                RemixParentRecoveryAction(
                    title: "Correct Pasted ISF for \(parent)",
                    kind: .paste
                ),
            ]
        }
    }

    var parentLoadStatus: String? {
        switch parentLoadState {
        case .idle:
            return nil
        case .fetching(let request):
            return "Fetching \(Self.parentName(request.slot))."
        case .verificationRequired(let request), .waitingForHuman(let request):
            return "Verification required for \(Self.parentName(request.slot))."
        case .resuming(let request):
            return "Resuming \(Self.parentName(request.slot)) import."
        case .converting(let request):
            return "Converting \(Self.parentName(request.slot))."
        case .succeeded(let slot, _):
            return "\(Self.parentName(slot)) loaded."
        case .failed(let request, let message):
            return "\(Self.parentName(request.slot)) could not be loaded. \(message)"
        case .cancelled(let request):
            return "\(Self.parentName(request.slot)) import cancelled."
        }
    }

    var parentLoadInstruction: String? {
        switch parentLoadState {
        case .verificationRequired, .waitingForHuman:
            return "Complete the visible security check, then choose Continue Verification."
        case .failed(let request, _):
            switch request.spec {
            case .shadertoyLink:
                return "Retry Fetch, use an API key, or paste ISF code."
            case .currentEditor:
                return "Retry Current Editor or paste ISF code."
            case .libraryFile:
                return "Choose another Library shader or paste ISF code."
            case .pastedISF:
                return "Correct the pasted ISF code."
            }
        default:
            return nil
        }
    }

    static let crossoverPopoverReturnFocus = RemixWorkspaceFocusToken.crossoverSettings

    static func focusAfterCollapsing(_ zone: RemixZone) -> RemixWorkspaceFocusToken {
        .reopenZone(zone)
    }

    static func focusAfterExpanding(_ zone: RemixZone) -> RemixWorkspaceFocusToken {
        .collapseZone(zone)
    }

    static func resizeValueDescription(zone: RemixZone, width: Double) -> String {
        "\(zoneName(zone)) width, \(Int(width.rounded())) points"
    }

    static func resetLayout(_ state: inout RemixWorkspaceState) {
        state = RemixWorkspaceState()
    }

    private func hasParent(_ slot: ParentSlot) -> Bool {
        switch slot {
        case .a: return parentAID != nil
        case .b: return parentBID != nil
        }
    }

    static func parentName(_ slot: ParentSlot) -> String {
        slot == .a ? "Parent A" : "Parent B"
    }

    private static func sourceName(_ source: RemixParentSourceAction) -> String {
        switch source {
        case .library: return "Library"
        case .currentEditor: return "Current Editor"
        case .paste: return "Paste"
        case .shadertoy: return "Shadertoy"
        }
    }

    private static func zoneName(_ zone: RemixZone) -> String {
        switch zone {
        case .breedingBay: return "Breeding Bay"
        case .lineage: return "Lineage"
        case .activity: return "Activity"
        }
    }
}
