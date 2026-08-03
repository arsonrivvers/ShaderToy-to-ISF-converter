import Foundation

struct RemixLineageRowPresentation: Equatable {
    let label: String
    let value: String
    let help: String
    let actions: [String]
}

struct RemixActivityFailurePresentation: Identifiable, Equatable {
    let id: String
    let title: String
    let message: String
    let actions: [String]
}

enum RemixLineagePresentation {
    enum RowAction: String {
        case expand = "Expand descendants"
        case collapse = "Collapse descendants"
        case selectPrimary = "Select Primary Parent"
        case selectSecondary = "Select Secondary Parent"
        case open = "Open in Editor"
        case promoteA = "Promote to Parent A"
        case promoteB = "Promote to Parent B"
        case favorite = "Favorite"
        case removeFavorite = "Remove Favorite"
        case deselect = "Deselect"
    }

    static func row(
        _ row: RemixTreeRow,
        node: RemixNode,
        lineage: RemixLineage,
        selected: Bool,
        collapsed: Bool,
        hasChildren: Bool
    ) -> RemixLineageRowPresentation {
        let name = displayName(for: node)
        let label = selected ? "\(name), selected" : name
        var values = [
            "Depth \(row.depth + 1)",
            lineage.isFavorite(node.id) ? "Favorite" : "Not favorite",
        ]
        if let primaryID = node.parents.first {
            values.append("Primary parent \(displayName(for: primaryID, lineage: lineage))")
        } else {
            values.append("Root shader")
        }
        if let secondaryID = row.secondaryParentID {
            values.append("Secondary parent \(displayName(for: secondaryID, lineage: lineage))")
        }
        values.append(statusDescription(node.status))
        if hasChildren {
            values.append(collapsed ? "Collapsed" : "Expanded")
        }

        let actions = actionNames(
            for: node,
            favorite: lineage.isFavorite(node.id),
            collapsed: collapsed,
            hasChildren: hasChildren
        )
        return RemixLineageRowPresentation(
            label: label,
            value: values.joined(separator: ". ") + ".",
            help: "Select \(name). Available actions: \(actions.joined(separator: ", ")).",
            actions: actions
        )
    }

    static func activityActions(for state: RemixActivityState) -> [String] {
        switch state {
        case .generating, .quiet:
            return ["Stop", "Copy Activity"]
        case .childFailed, .partialFailure, .cancelled:
            return ["Retry All Failed", "Copy Activity"]
        case .completed(let failed) where failed > 0:
            return ["Retry All Failed", "Copy Activity"]
        case .interrupted:
            return ["Retry Interrupted Batch", "Copy Activity"]
        default:
            return ["Copy Activity"]
        }
    }

    static func activityActions(for summary: RemixRunSummary, canStop: Bool) -> [String] {
        if canStop, summary.terminalCount < summary.totalCount {
            return ["Stop"]
        }
        guard summary.totalCount > 0, summary.terminalCount == summary.totalCount else {
            return []
        }
        var actions: [String] = []
        if summary.stageCounts[.failed, default: 0] > 0 {
            actions.append("Retry All Failed")
        }
        if summary.stageCounts[.interrupted, default: 0] > 0 {
            actions.append("Retry Interrupted Batch")
        }
        return actions
    }

    static func compactActivityStatus(for state: RemixActivityState) -> String {
        state.summary.compactStatus
    }

    static func selectedNodeActions(favorite: Bool) -> [RowAction] {
        [
            .promoteA,
            .promoteB,
            favorite ? .removeFavorite : .favorite,
            .open,
            .deselect,
        ]
    }

    static func announcement(
        from previous: RemixActivityState,
        to current: RemixActivityState
    ) -> String? {
        guard previous != current else { return nil }
        switch (previous, current) {
        case (.generating, .generating), (.quiet, .quiet):
            return nil
        default:
            return current.summary.accessibilityAnnouncement
        }
    }

    static func announcement(
        from previous: RemixRunSummary,
        to current: RemixRunSummary
    ) -> String? {
        guard current.totalCount > 0,
              current.terminalCount == current.totalCount,
              previous.terminalCount < previous.totalCount
        else {
            return nil
        }
        let readyCount = current.stageCounts[.ready, default: 0]
        if readyCount == current.totalCount {
            return readyCount == 1
                ? "Generation complete. 1 child is ready."
                : "Generation complete. \(readyCount) children are ready."
        }
        return current.activitySummary(activeProviderCount: 0).accessibilityAnnouncement
    }

    static func failureRows(
        nodes: [RemixNode],
        compileDiagnosticsByNodeID: [String: String]
    ) -> [RemixActivityFailurePresentation] {
        nodes.compactMap { node in
            guard case .failed(let message) = node.status else { return nil }
            let compileDiagnostic = compileDiagnosticsByNodeID[node.id]
            return RemixActivityFailurePresentation(
                id: node.id,
                title: displayName(for: node),
                message: compileDiagnostic ?? message,
                actions: compileDiagnostic == nil
                    ? ["Retry This Child"]
                    : [
                        "View Compile Summary",
                        "Copy Diagnostic",
                        "Open Source in Editor to Fix",
                        "Retry This Child",
                    ]
            )
        }
    }

    static func failureRows(records: [RemixChildRunRecord])
        -> [RemixActivityFailurePresentation]
    {
        records.compactMap { record in
            guard record.stage == .failed else { return nil }
            let compileDiagnostic = record.failureBoundary == .compile
                ? record.compileDiagnostic
                : nil
            return RemixActivityFailurePresentation(
                id: record.id,
                title: record.id,
                message: compileDiagnostic ?? record.failureMessage ?? "Failed",
                actions: compileDiagnostic == nil
                    ? ["Retry This Child"]
                    : [
                        "View Compile Summary",
                        "Copy Diagnostic",
                        "Open Source in Editor to Fix",
                        "Retry This Child",
                    ]
            )
        }
    }

    private static func actionNames(
        for node: RemixNode,
        favorite: Bool,
        collapsed: Bool,
        hasChildren: Bool
    ) -> [String] {
        if case .failed = node.status {
            return [
                "View Compile Summary",
                "Copy Diagnostic",
                "Open Source in Editor to Fix",
                "Retry This Child",
            ]
        }
        var actions: [String] = []
        if hasChildren {
            actions.append((collapsed ? RowAction.expand : RowAction.collapse).rawValue)
        }
        if !node.parents.isEmpty {
            actions.append(RowAction.selectPrimary.rawValue)
        }
        if node.parents.count > 1 {
            actions.append(RowAction.selectSecondary.rawValue)
        }
        actions += [
            RowAction.open.rawValue,
            RowAction.promoteA.rawValue,
            RowAction.promoteB.rawValue,
            (favorite ? RowAction.removeFavorite : RowAction.favorite).rawValue,
        ]
        return actions
    }

    private static func displayName(for node: RemixNode) -> String {
        node.label ?? node.id
    }

    private static func displayName(for id: String, lineage: RemixLineage) -> String {
        lineage.node(id).map(displayName(for:)) ?? id
    }

    private static func statusDescription(_ status: RemixNode.Status) -> String {
        switch status {
        case .generating:
            return "Generating"
        case .compiled:
            return "Compiled"
        case .interrupted:
            return "Interrupted"
        case .failed(let message):
            return "Compile failed: \(message)"
        }
    }
}

enum RemixLineageKeyboardRoute {
    enum Result: Equatable {
        case ignore
        case focus(String)
        case select(String)
    }

    static func route(
        keyCode: UInt16,
        modifiersPresent: Bool = false,
        focusedID: String?,
        visibleIDs: [String]
    ) -> Result {
        guard !modifiersPresent, !visibleIDs.isEmpty else { return .ignore }
        guard let focusedID,
              let index = visibleIDs.firstIndex(of: focusedID)
        else {
            return (keyCode == 125 || keyCode == 126)
                ? .focus(visibleIDs[0])
                : .ignore
        }
        switch keyCode {
        case 125:
            return .focus(visibleIDs[min(index + 1, visibleIDs.count - 1)])
        case 126:
            return .focus(visibleIDs[max(index - 1, 0)])
        case 36, 49:
            return .select(focusedID)
        default:
            return .ignore
        }
    }
}
