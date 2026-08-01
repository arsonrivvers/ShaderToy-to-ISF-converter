import Foundation

enum AssistProviderIdentity: String, Codable, Sendable, Equatable {
    case claude
    case codex
}

struct AssistTextBlock: Sendable, Equatable {
    let index: Int
    let text: String
}

enum AssistRunEvent: Sendable, Equatable {
    case sessionStarted(id: String?)
    case processStarted(pid: Int32)
    case thinking
    case textDelta(messageID: String?, blockIndex: Int, text: String)
    case assistantMessage(messageID: String, stopReason: String?, blocks: [AssistTextBlock])
    case apiRetry(attempt: Int?, message: String)
    case successfulResult(String)
    case errorResult(String)
    case timedOut
    case cancelled
    case processExited(Int32)
}

enum AssistResponseSource: String, Codable, Sendable, Equatable {
    case result
    case assistantMessage
    case agentMessage
}

struct AssistRunResult: Sendable, Equatable {
    let provider: AssistProviderIdentity
    let response: String
    let source: AssistResponseSource
    let observedSuccessfulResult: Bool
    let completeAssistantResponse: String?
    let successfulResultText: String?
    let receivedBytes: Int
    let eventCount: Int
}

enum AssistAssemblyError: Error, Sendable, Equatable {
    case providerFailed(String)
    case noAuthoritativeResponse
}

@MainActor
protocol AssistDetailedProvider: AnyObject {
    func runDetailed(
        prompt: String,
        system: String,
        model: String?,
        timeout: TimeInterval,
        onEvent: @escaping @Sendable (AssistRunEvent) -> Void,
        onRawLine: @escaping @Sendable (String) -> Void
    ) async throws -> AssistRunResult
}
