import Foundation

struct RemixChildRunRecord: Identifiable, Codable, Equatable {
    enum Stage: String, Codable, CaseIterable, Hashable {
        case queued, starting, thinking, receiving, retrying, extracting, compiling
        case ready, failed, cancelled, interrupted

        var isTerminal: Bool {
            [.ready, .failed, .cancelled, .interrupted].contains(self)
        }
    }

    enum FailureBoundary: String, Codable, Equatable {
        case provider, response, extraction, compile
    }

    let id: String
    let round: Int
    let slot: Int
    let request: RemixGenerationRequestSnapshot
    var stage: Stage
    var queuedAt: Date
    var startedAt: Date?
    var lastEventAt: Date?
    var providerCompletedAt: Date?
    var terminalAt: Date?
    var provider: AssistProviderIdentity?
    var model: String?
    var workerLabel: String?
    var queuePosition: Int?
    var receivedBytes: Int
    var apiRetryCount: Int
    var lastProviderNotice: String?
    var candidateSource: String?
    var diagnosticResponse: String?
    var failureBoundary: FailureBoundary?
    var failureMessage: String?
    var compileDiagnostic: String?
    var artifactID: String?

    private static let maximumDiagnosticBytes = 262_144

    init(
        id: String,
        round: Int,
        slot: Int,
        request: RemixGenerationRequestSnapshot,
        stage: Stage = .queued,
        queuedAt: Date,
        startedAt: Date? = nil,
        lastEventAt: Date? = nil,
        providerCompletedAt: Date? = nil,
        terminalAt: Date? = nil,
        provider: AssistProviderIdentity? = nil,
        model: String? = nil,
        workerLabel: String? = nil,
        queuePosition: Int? = nil,
        receivedBytes: Int = 0,
        apiRetryCount: Int = 0,
        lastProviderNotice: String? = nil,
        candidateSource: String? = nil,
        diagnosticResponse: String? = nil,
        failureBoundary: FailureBoundary? = nil,
        failureMessage: String? = nil,
        compileDiagnostic: String? = nil,
        artifactID: String? = nil
    ) {
        self.id = id
        self.round = round
        self.slot = slot
        self.request = request
        self.stage = stage
        self.queuedAt = queuedAt
        self.startedAt = startedAt
        self.lastEventAt = lastEventAt
        self.providerCompletedAt = providerCompletedAt
        self.terminalAt = terminalAt
        self.provider = provider
        self.model = model
        self.workerLabel = workerLabel
        self.queuePosition = queuePosition
        self.receivedBytes = max(0, receivedBytes)
        self.apiRetryCount = max(0, apiRetryCount)
        self.lastProviderNotice = Self.boundedDiagnostic(lastProviderNotice)
        self.candidateSource = candidateSource
        self.diagnosticResponse = Self.boundedDiagnostic(diagnosticResponse)
        self.failureBoundary = failureBoundary
        self.failureMessage = Self.boundedDiagnostic(failureMessage)
        self.compileDiagnostic = Self.boundedDiagnostic(compileDiagnostic)
        self.artifactID = artifactID
    }

    @discardableResult
    mutating func transition(to next: Stage, at date: Date) -> Bool {
        guard !stage.isTerminal, Self.canTransition(from: stage, to: next) else {
            return false
        }

        stage = next
        lastEventAt = date
        if next == .starting, startedAt == nil {
            startedAt = date
        }
        if next == .extracting, providerCompletedAt == nil {
            providerCompletedAt = date
        }
        if next.isTerminal {
            terminalAt = date
        }
        return true
    }

    mutating func recordProviderActivity(bytes: Int, at date: Date) {
        guard !stage.isTerminal else { return }
        receivedBytes += max(0, bytes)
        if stage == .starting || stage == .thinking || stage == .retrying {
            _ = transition(to: .receiving, at: date)
        } else {
            lastEventAt = date
        }
    }

    mutating func recordAPIRetry(attempt: Int?, message: String, at date: Date) {
        guard !stage.isTerminal,
              stage == .thinking || stage == .receiving || stage == .retrying
        else {
            return
        }

        let reportedAttempt = max(0, attempt ?? 0)
        apiRetryCount = max(apiRetryCount + 1, reportedAttempt)
        lastProviderNotice = Self.boundedDiagnostic(message)
        stage = .retrying
        lastEventAt = date
    }

    mutating func recordDiagnosticResponse(_ response: String) {
        guard !stage.isTerminal else { return }
        diagnosticResponse = Self.boundedDiagnostic(response)
    }

    @discardableResult
    mutating func fail(boundary: FailureBoundary, message: String, at date: Date) -> Bool {
        guard !stage.isTerminal else { return false }
        let boundedMessage = Self.boundedDiagnostic(message)
        failureBoundary = boundary
        failureMessage = boundedMessage
        if boundary == .compile {
            compileDiagnostic = boundedMessage
        }
        stage = .failed
        lastEventAt = date
        terminalAt = date
        return true
    }

    @discardableResult
    mutating func finishReady(artifactID: String, at date: Date) -> Bool {
        guard !stage.isTerminal, stage == .compiling else { return false }
        self.artifactID = artifactID
        stage = .ready
        lastEventAt = date
        terminalAt = date
        return true
    }

    func boundedForPersistence() -> RemixChildRunRecord {
        var bounded = self
        bounded.lastProviderNotice = Self.boundedDiagnostic(lastProviderNotice)
        bounded.diagnosticResponse = Self.boundedDiagnostic(diagnosticResponse)
        bounded.failureMessage = Self.boundedDiagnostic(failureMessage)
        bounded.compileDiagnostic = Self.boundedDiagnostic(compileDiagnostic)
        return bounded
    }

    private static func canTransition(from current: Stage, to next: Stage) -> Bool {
        switch current {
        case .queued:
            return [.starting, .cancelled, .interrupted].contains(next)
        case .starting:
            return [.thinking, .receiving, .extracting, .failed, .cancelled, .interrupted]
                .contains(next)
        case .thinking:
            return [.receiving, .retrying, .extracting, .failed, .cancelled, .interrupted]
                .contains(next)
        case .receiving:
            return [.retrying, .extracting, .failed, .cancelled, .interrupted].contains(next)
        case .retrying:
            return [.thinking, .receiving, .extracting, .failed, .cancelled, .interrupted]
                .contains(next)
        case .extracting:
            return [.compiling, .failed, .cancelled, .interrupted].contains(next)
        case .compiling:
            return [.ready, .failed, .cancelled, .interrupted].contains(next)
        case .ready, .failed, .cancelled, .interrupted:
            return false
        }
    }

    private static func boundedDiagnostic(_ value: String?) -> String? {
        guard let value else { return nil }
        guard value.utf8.count > maximumDiagnosticBytes else { return value }

        var bytes = Data(value.utf8.prefix(maximumDiagnosticBytes))
        while !bytes.isEmpty {
            if let bounded = String(data: bytes, encoding: .utf8) {
                return bounded
            }
            bytes.removeLast()
        }
        return ""
    }

    private enum CodingKeys: String, CodingKey {
        case id, round, slot, request, stage, queuedAt, startedAt, lastEventAt
        case providerCompletedAt, terminalAt, provider, model, workerLabel, queuePosition
        case receivedBytes, apiRetryCount, lastProviderNotice, candidateSource
        case diagnosticResponse, failureBoundary, failureMessage, compileDiagnostic, artifactID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(String.self, forKey: .id),
            round: try container.decode(Int.self, forKey: .round),
            slot: try container.decode(Int.self, forKey: .slot),
            request: try container.decode(RemixGenerationRequestSnapshot.self, forKey: .request),
            stage: try container.decode(Stage.self, forKey: .stage),
            queuedAt: try container.decode(Date.self, forKey: .queuedAt),
            startedAt: try container.decodeIfPresent(Date.self, forKey: .startedAt),
            lastEventAt: try container.decodeIfPresent(Date.self, forKey: .lastEventAt),
            providerCompletedAt: try container.decodeIfPresent(Date.self, forKey: .providerCompletedAt),
            terminalAt: try container.decodeIfPresent(Date.self, forKey: .terminalAt),
            provider: try container.decodeIfPresent(AssistProviderIdentity.self, forKey: .provider),
            model: try container.decodeIfPresent(String.self, forKey: .model),
            workerLabel: try container.decodeIfPresent(String.self, forKey: .workerLabel),
            queuePosition: try container.decodeIfPresent(Int.self, forKey: .queuePosition),
            receivedBytes: try container.decode(Int.self, forKey: .receivedBytes),
            apiRetryCount: try container.decodeIfPresent(Int.self, forKey: .apiRetryCount) ?? 0,
            lastProviderNotice: try container.decodeIfPresent(String.self, forKey: .lastProviderNotice),
            candidateSource: try container.decodeIfPresent(String.self, forKey: .candidateSource),
            diagnosticResponse: try container.decodeIfPresent(String.self, forKey: .diagnosticResponse),
            failureBoundary: try container.decodeIfPresent(FailureBoundary.self, forKey: .failureBoundary),
            failureMessage: try container.decodeIfPresent(String.self, forKey: .failureMessage),
            compileDiagnostic: try container.decodeIfPresent(String.self, forKey: .compileDiagnostic),
            artifactID: try container.decodeIfPresent(String.self, forKey: .artifactID)
        )
    }

    func encode(to encoder: Encoder) throws {
        let bounded = boundedForPersistence()
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(bounded.id, forKey: .id)
        try container.encode(bounded.round, forKey: .round)
        try container.encode(bounded.slot, forKey: .slot)
        try container.encode(bounded.request, forKey: .request)
        try container.encode(bounded.stage, forKey: .stage)
        try container.encode(bounded.queuedAt, forKey: .queuedAt)
        try container.encodeIfPresent(bounded.startedAt, forKey: .startedAt)
        try container.encodeIfPresent(bounded.lastEventAt, forKey: .lastEventAt)
        try container.encodeIfPresent(bounded.providerCompletedAt, forKey: .providerCompletedAt)
        try container.encodeIfPresent(bounded.terminalAt, forKey: .terminalAt)
        try container.encodeIfPresent(bounded.provider, forKey: .provider)
        try container.encodeIfPresent(bounded.model, forKey: .model)
        try container.encodeIfPresent(bounded.workerLabel, forKey: .workerLabel)
        try container.encodeIfPresent(bounded.queuePosition, forKey: .queuePosition)
        try container.encode(bounded.receivedBytes, forKey: .receivedBytes)
        try container.encode(bounded.apiRetryCount, forKey: .apiRetryCount)
        try container.encodeIfPresent(bounded.lastProviderNotice, forKey: .lastProviderNotice)
        try container.encodeIfPresent(bounded.candidateSource, forKey: .candidateSource)
        try container.encodeIfPresent(bounded.diagnosticResponse, forKey: .diagnosticResponse)
        try container.encodeIfPresent(bounded.failureBoundary, forKey: .failureBoundary)
        try container.encodeIfPresent(bounded.failureMessage, forKey: .failureMessage)
        try container.encodeIfPresent(bounded.compileDiagnostic, forKey: .compileDiagnostic)
        try container.encodeIfPresent(bounded.artifactID, forKey: .artifactID)
    }
}
