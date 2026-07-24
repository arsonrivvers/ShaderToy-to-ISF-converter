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
