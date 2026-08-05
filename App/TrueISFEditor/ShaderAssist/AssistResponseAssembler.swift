import Foundation

struct AssistResponseAssembler: Sendable {
    let provider: AssistProviderIdentity
    private let accumulator = AssistRunAccumulator()

    init(provider: AssistProviderIdentity) {
        self.provider = provider
    }

    func consume(_ event: AssistRunEvent) {
        accumulator.consume(event)
    }

    func resolve(processExitSucceeded: Bool) throws -> AssistRunResult {
        try accumulator.resolve(provider: provider, processExitSucceeded: processExitSucceeded)
    }

    var observedSuccessfulResult: Bool { accumulator.didObserveSuccessfulResult }
}

/// Owns mutable stream state independently from the main actor because process output arrives on a
/// background reader queue.
private final class AssistRunAccumulator: @unchecked Sendable {
    private struct CompleteAssistant {
        let text: String
        let stopReason: String?
    }

    private let lock = NSLock()
    private var deltaBytesByMessageID: [String: [Int: Int]] = [:]
    private var lastCompleteAssistant: CompleteAssistant?
    private var providerError: String?
    private var observedSuccessfulResult = false
    private var resultText: String?
    private var receivedBytes = 0
    private var eventCount = 0

    var didObserveSuccessfulResult: Bool {
        lock.lock()
        defer { lock.unlock() }
        return observedSuccessfulResult
    }

    func consume(_ event: AssistRunEvent) {
        lock.lock()
        defer { lock.unlock() }

        eventCount += 1
        switch event {
        case let .textDelta(messageID, blockIndex, text):
            let byteCount = text.utf8.count
            receivedBytes += byteCount
            guard let messageID else { return }
            var blocks = deltaBytesByMessageID[messageID] ?? [:]
            blocks[blockIndex, default: 0] += byteCount
            deltaBytesByMessageID[messageID] = blocks

        case let .assistantMessage(messageID, stopReason, blocks):
            let text = blocks
                .sorted { $0.index < $1.index }
                .map(\.text)
                .joined()
            let replacedDeltaBytes = deltaBytesByMessageID.removeValue(forKey: messageID)?
                .values
                .reduce(0) { $0 + $1 } ?? 0
            receivedBytes += text.utf8.count - replacedDeltaBytes
            let assistant = CompleteAssistant(text: text, stopReason: stopReason)
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
