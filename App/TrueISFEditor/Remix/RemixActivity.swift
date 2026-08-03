import Foundation

enum RemixActivityState: Codable, Equatable {
    case idle
    case generating(total: Int, completed: Int, lastEventAt: Date?)
    case quiet(total: Int, completed: Int, lastEventAt: Date?)
    case verificationRequired(slot: ParentSlot, requestID: UUID)
    case resuming(slot: ParentSlot, requestID: UUID)
    case childFailed(id: String, message: String)
    case partialFailure(total: Int, failed: Int)
    case interrupted
    case completed(failed: Int)
    case cancelled
}

struct RemixActivitySummary: Equatable {
    let compactStatus: String
    let accessibilityAnnouncement: String
}

struct RemixRunSummary: Equatable {
    let stageCounts: [RemixChildRunRecord.Stage: Int]
    let terminalCount: Int
    let totalCount: Int
    let activeWorkerCount: Int
    let queueCount: Int
    let earliestStart: Date?
    let latestProviderActivity: Date?

    init(records: [RemixChildRunRecord]) {
        stageCounts = records.reduce(into: [:]) { counts, record in
            counts[record.stage, default: 0] += 1
        }
        terminalCount = records.filter(\.stage.isTerminal).count
        totalCount = records.count
        queueCount = stageCounts[.queued, default: 0]
        activeWorkerCount = records.filter {
            !$0.stage.isTerminal && $0.stage != .queued
        }.count
        earliestStart = records.compactMap(\.startedAt).min()
        latestProviderActivity = records.compactMap(\.lastEventAt).max()
    }

    var terminalProgress: Double {
        guard totalCount > 0 else { return 0 }
        return Double(terminalCount) / Double(totalCount)
    }

    func activitySummary(activeProviderCount: Int) -> RemixActivitySummary {
        guard totalCount > 0 else {
            return RemixActivitySummary(
                compactStatus: "Ready",
                accessibilityAnnouncement: "Remix Studio is ready."
            )
        }
        let compact = "\(terminalCount) of \(totalCount) complete · \(activeWorkerCount) active · \(queueCount) queued"
        let providerClause = activeProviderCount == 1
            ? "One provider process is alive."
            : "\(activeProviderCount) provider processes are alive."
        return RemixActivitySummary(
            compactStatus: compact,
            accessibilityAnnouncement:
                "\(terminalCount) of \(totalCount) children are terminal. "
                + "\(activeWorkerCount) workers are active and \(queueCount) are queued. "
                + providerClause
        )
    }
}

enum RemixCompileSalvageAction: String, Codable, Equatable {
    case viewCompileSummary = "View Compile Summary"
    case openSourceInEditorToFix = "Open Source in Editor to Fix"
    case copyDiagnostic = "Copy Diagnostic"
    case retryThisChild = "Retry This Child"
}

enum RemixPreviewFailureAction: String, Codable, Equatable {
    case retryPreview = "Retry Preview"
    case openInEditor = "Open in Editor"
}

extension RemixActivityState {
    var summary: RemixActivitySummary {
        switch self {
        case .idle:
            return RemixActivitySummary(
                compactStatus: "Ready",
                accessibilityAnnouncement: "Remix Studio is ready."
            )
        case .generating(let total, let completed, _):
            return RemixActivitySummary(
                compactStatus: "Generating \(completed) of \(total)",
                accessibilityAnnouncement:
                    "Generating batch. \(completed) of \(total) children complete."
            )
        case .quiet(let total, let completed, _):
            return RemixActivitySummary(
                compactStatus: "Generating \(completed) of \(total), quiet",
                accessibilityAnnouncement:
                    "Generating batch. \(completed) of \(total) children complete. "
                    + "The provider is quiet but still working."
            )
        case .verificationRequired(let slot, _):
            let parent = Self.parentName(slot)
            return RemixActivitySummary(
                compactStatus: "Verification required for \(parent)",
                accessibilityAnnouncement:
                    "Verification required for \(parent). "
                    + "Complete the visible security check to continue."
            )
        case .resuming(let slot, _):
            let parent = Self.parentName(slot)
            return RemixActivitySummary(
                compactStatus: "Resuming \(parent) import",
                accessibilityAnnouncement:
                    "Verification cleared. Resuming the \(parent) import."
            )
        case .childFailed(let id, let message):
            return RemixActivitySummary(
                compactStatus: "\(id) failed",
                accessibilityAnnouncement: "\(id) failed. \(message)"
            )
        case .partialFailure(let total, let failed):
            return RemixActivitySummary(
                compactStatus: "\(failed) of \(total) children failed",
                accessibilityAnnouncement:
                    "Batch finished with \(failed) of \(total) children failed."
            )
        case .interrupted:
            return RemixActivitySummary(
                compactStatus: "Generation interrupted",
                accessibilityAnnouncement:
                    "Generation was interrupted. The original inputs are available to retry."
            )
        case .completed(let failed):
            if failed > 0 {
                return RemixActivitySummary(
                    compactStatus: "\(failed) children failed",
                    accessibilityAnnouncement:
                        "Generation finished with \(failed) children failed."
                )
            }
            return RemixActivitySummary(
                compactStatus: "Generation complete",
                accessibilityAnnouncement: "Generation complete."
            )
        case .cancelled:
            return RemixActivitySummary(
                compactStatus: "Generation cancelled",
                accessibilityAnnouncement: "Generation cancelled."
            )
        }
    }

    private static func parentName(_ slot: ParentSlot) -> String {
        switch slot {
        case .a: return "Parent A"
        case .b: return "Parent B"
        }
    }
}
