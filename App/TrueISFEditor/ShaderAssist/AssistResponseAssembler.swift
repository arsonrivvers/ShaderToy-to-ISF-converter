import Foundation

struct AssistResponseAssembler {
    let provider: AssistProviderIdentity
    private let accumulator = AssistRunAccumulator()

    init(provider: AssistProviderIdentity) {
        self.provider = provider
    }

    mutating func consume(_ event: AssistRunEvent) {
        accumulator.consume(event)
    }

    mutating func resolve(processExitSucceeded: Bool) throws -> AssistRunResult {
        try accumulator.resolve(provider: provider, processExitSucceeded: processExitSucceeded)
    }
}

/// Owns mutable stream state independently from the main actor because process output arrives on a
/// background reader queue.
private final class AssistRunAccumulator: @unchecked Sendable {
    private struct CompleteAssistant {
        let text: String
        let stopReason: String?
    }

    private let lock = NSLock()
    private var deltasByMessageID: [String: [Int: String]] = [:]
    private var completeAssistantsByMessageID: [String: CompleteAssistant] = [:]
    private var lastCompleteAssistant: CompleteAssistant?
    private var providerError: String?
    private var observedSuccessfulResult = false
    private var resultText: String?
    private var receivedBytes = 0
    private var eventCount = 0

    func consume(_ event: AssistRunEvent) {
        lock.lock()
        defer { lock.unlock() }

        eventCount += 1
        receivedBytes += event.payloadByteCount

        switch event {
        case let .textDelta(messageID, blockIndex, text):
            let key = messageID ?? ""
            var blocks = deltasByMessageID[key] ?? [:]
            blocks[blockIndex, default: ""] += text
            deltasByMessageID[key] = blocks

        case let .assistantMessage(messageID, stopReason, blocks):
            let text = blocks
                .sorted { $0.index < $1.index }
                .map(\.text)
                .joined()
            let assistant = CompleteAssistant(text: text, stopReason: stopReason)
            completeAssistantsByMessageID[messageID] = assistant
            deltasByMessageID.removeValue(forKey: messageID)
            lastCompleteAssistant = assistant

        case let .successfulResult(text):
            observedSuccessfulResult = true
            resultText = text

        case let .errorResult(message):
            providerError = message

        default:
            break
        }
    }

    func resolve(provider: AssistProviderIdentity, processExitSucceeded: Bool) throws -> AssistRunResult {
        lock.lock()
        defer { lock.unlock() }

        if let providerError {
            throw AssistAssemblyError.providerFailed(providerError)
        }

        if let resultText, !resultText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return makeResult(provider: provider, response: resultText, source: .result)
        }

        if observedSuccessfulResult,
           let assistant = lastCompleteAssistant,
           !assistant.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return makeResult(
                provider: provider,
                response: assistant.text,
                source: provider == .codex ? .agentMessage : .assistantMessage
            )
        }

        if processExitSucceeded,
           let assistant = lastCompleteAssistant,
           assistant.stopReason == "end_turn",
           !assistant.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return makeResult(
                provider: provider,
                response: assistant.text,
                source: provider == .codex ? .agentMessage : .assistantMessage
            )
        }

        throw AssistAssemblyError.noAuthoritativeResponse
    }

    private func makeResult(
        provider: AssistProviderIdentity,
        response: String,
        source: AssistResponseSource
    ) -> AssistRunResult {
        AssistRunResult(
            provider: provider,
            response: response,
            source: source,
            observedSuccessfulResult: observedSuccessfulResult,
            completeAssistantResponse: lastCompleteAssistant?.text,
            successfulResultText: resultText,
            receivedBytes: receivedBytes,
            eventCount: eventCount
        )
    }
}

private extension AssistRunEvent {
    var payloadByteCount: Int {
        switch self {
        case let .sessionStarted(id):
            return id?.utf8.count ?? 0
        case let .textDelta(_, _, text), let .apiRetry(_, text), let .successfulResult(text), let .errorResult(text):
            return text.utf8.count
        case let .assistantMessage(messageID, _, blocks):
            return messageID.utf8.count + blocks.reduce(0) { $0 + $1.text.utf8.count }
        case .processStarted, .thinking, .timedOut, .cancelled, .processExited:
            return 0
        }
    }
}
