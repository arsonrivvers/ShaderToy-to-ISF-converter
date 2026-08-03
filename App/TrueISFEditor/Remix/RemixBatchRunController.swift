import Foundation

enum RemixPipelineUpdate: Equatable {
    case record(RemixChildRunRecord)
    case artifact(RemixNode, record: RemixChildRunRecord)
    case processLiveness(childID: String, isAlive: Bool)
}

/// Owns only the launch gate and provider-owned work for one batch. The scheduler and all local
/// extraction/compile work deliberately live outside this controller, so Stop cannot cancel an
/// authoritative provider result after it has crossed the provider boundary.
@MainActor
final class RemixBatchRunController {
    private(set) var launchGateClosed = false
    private(set) var activeProviderChildIDs: Set<String> = []
    private var providerTasks: [String: Task<AssistRunResult, Error>] = [:]
    private var pendingProviderChildIDs: Set<String>

    init(launchableChildIDs: [String] = []) {
        pendingProviderChildIDs = Set(launchableChildIDs)
    }

    var canLaunch: Bool { !launchGateClosed }
    var hasStoppableWork: Bool {
        !launchGateClosed && !pendingProviderChildIDs.isEmpty
    }

    func registerLaunchableChildren(_ childIDs: [String]) {
        guard !launchGateClosed else { return }
        pendingProviderChildIDs.formUnion(childIDs)
    }

    @discardableResult
    func registerProviderTask(
        _ task: Task<AssistRunResult, Error>,
        childID: String
    ) -> Bool {
        guard !launchGateClosed else {
            task.cancel()
            return false
        }
        pendingProviderChildIDs.insert(childID)
        providerTasks[childID] = task
        return true
    }

    /// Atomically claims provider completion against Stop. A true result means the authoritative
    /// response won the MainActor race and local work may continue. False means Stop closed the gate
    /// and removed the registration first, so a late task result is no longer accepted.
    @discardableResult
    func providerFinished(childID: String) -> Bool {
        let wasRegistered = providerTasks.removeValue(forKey: childID) != nil
        pendingProviderChildIDs.remove(childID)
        activeProviderChildIDs.remove(childID)
        return wasRegistered
    }

    func providerWillNotLaunch(childID: String) {
        pendingProviderChildIDs.remove(childID)
    }

    @discardableResult
    func providerProcessStarted(childID: String) -> Bool {
        guard providerTasks[childID] != nil else { return false }
        return activeProviderChildIDs.insert(childID).inserted
    }

    @discardableResult
    func providerProcessExited(childID: String) -> Bool {
        activeProviderChildIDs.remove(childID) != nil
    }

    func isProviderRegistered(childID: String) -> Bool {
        providerTasks[childID] != nil
    }

    func stop() {
        guard !launchGateClosed else { return }
        launchGateClosed = true
        let tasks = Array(providerTasks.values)
        providerTasks.removeAll()
        pendingProviderChildIDs.removeAll()
        activeProviderChildIDs.removeAll()
        tasks.forEach { $0.cancel() }
    }
}
