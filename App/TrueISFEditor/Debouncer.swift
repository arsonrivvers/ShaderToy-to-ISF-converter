import Foundation

/// Coalesces a burst of calls into one, firing the LAST block after `delayNanos` of quiet.
/// Main-actor-bound: used for UI-driven work (recompiles, persistence) that must not run per keystroke.
@MainActor
final class Debouncer {
    private let delayNanos: UInt64
    private var task: Task<Void, Never>?

    init(delayNanos: UInt64) { self.delayNanos = delayNanos }

    func call(_ block: @escaping @MainActor () -> Void) {
        task?.cancel()
        task = Task { [delayNanos] in
            try? await Task.sleep(nanoseconds: delayNanos)
            if Task.isCancelled { return }
            block()
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }
}
