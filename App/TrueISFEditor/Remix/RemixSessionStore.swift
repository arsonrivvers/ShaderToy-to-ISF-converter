import Foundation

enum RemixSessionRecovery: Equatable {
    case noSession
    case session(RemixSession)
    case corruptPayload(quarantinedURL: URL)
}

struct RemixSessionStore {
    private let fileURL: URL
    private let fileManager: FileManager
    private let now: () -> Date

    init(
        fileURL: URL,
        fileManager: FileManager = .default,
        now: @escaping () -> Date = Date.init
    ) {
        self.fileURL = fileURL
        self.fileManager = fileManager
        self.now = now
    }

    func load() throws -> RemixSessionRecovery {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return .noSession
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let session = try JSONDecoder().decode(RemixSession.self, from: data)
            return .session(session)
        } catch {
            let quarantinedURL = availableQuarantineURL()
            try fileManager.moveItem(at: fileURL, to: quarantinedURL)
            return .corruptPayload(quarantinedURL: quarantinedURL)
        }
    }

    func save(_ session: RemixSession) throws {
        try fileManager.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        var bounded = session.boundedForPersistence()
        bounded.batchHistory = Array(bounded.batchHistory.suffix(20))
        bounded.transcript = Array(bounded.transcript.suffix(2_000))

        let temporaryURL = fileURL.deletingLastPathComponent()
            .appendingPathComponent(".\(fileURL.lastPathComponent).\(UUID().uuidString).tmp")
        defer { try? fileManager.removeItem(at: temporaryURL) }

        try JSONEncoder().encode(bounded).write(to: temporaryURL)
        if fileManager.fileExists(atPath: fileURL.path) {
            _ = try fileManager.replaceItemAt(fileURL, withItemAt: temporaryURL)
        } else {
            try fileManager.moveItem(at: temporaryURL, to: fileURL)
        }
    }

    private func availableQuarantineURL() -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"

        let directory = fileURL.deletingLastPathComponent()
        let stem = fileURL.deletingPathExtension().lastPathComponent
        let timestamp = formatter.string(from: now())
        var candidate = directory.appendingPathComponent("\(stem).\(timestamp).corrupt")
        var suffix = 2
        while fileManager.fileExists(atPath: candidate.path) {
            candidate = directory
                .appendingPathComponent("\(stem).\(timestamp)-\(suffix).corrupt")
            suffix += 1
        }
        return candidate
    }
}
