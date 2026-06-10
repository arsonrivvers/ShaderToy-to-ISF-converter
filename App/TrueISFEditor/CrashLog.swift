import Foundation
import Combine

/// Persistent, in-memory-mirrored crash/failure log. Singleton (`CrashLog.shared`) because the crash
/// handlers and the preview controller all record into one process-wide log.
@MainActor
final class CrashLog: ObservableObject {
    static let shared = CrashLog()

    @Published private(set) var events: [CrashEvent] = []
    /// True when this launch ingested a hard-crash record left by the previous session.
    @Published private(set) var crashedLastSession = false

    private let maxEvents = 500
    let fileURL: URL
    let pendingURL: URL

    /// `directory` override for tests; defaults to ~/Library/Logs/TrueISFEditor.
    init(directory: URL? = nil) {
        let dir = directory ?? FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs/TrueISFEditor")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.fileURL = dir.appendingPathComponent("crash-log.json")
        self.pendingURL = dir.appendingPathComponent("pending-crash.log")
        load()
        ingestPending()
    }

    func record(_ event: CrashEvent) {
        // De-dup consecutive identical failures (e.g. the same compile error on every keystroke).
        if let last = events.last, last.kind == event.kind,
           last.message == event.message, last.context == event.context { return }
        events.append(event)
        if events.count > maxEvents { events.removeFirst(events.count - maxEvents) }
        persist()
    }

    func clear() {
        events.removeAll()
        crashedLastSession = false
        persist()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? Self.decoder.decode([CrashEvent].self, from: data) else { return }
        events = decoded
    }

    private func persist() {
        guard let data = try? Self.encoder.encode(events) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    /// Convert a pending hard-crash record (written by the signal/exception handler) into an event.
    /// Format: first line `SIGNAL <name> <epoch>` or `EXCEPTION <name> <epoch>`; remainder = detail.
    private func ingestPending() {
        guard let text = try? String(contentsOf: pendingURL, encoding: .utf8), !text.isEmpty else { return }
        let split = text.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
        let header = split.first.map(String.init) ?? ""
        let parts = header.split(separator: " ").map(String.init)
        let kind: CrashEvent.Kind = header.hasPrefix("EXCEPTION") ? .exception : .signal
        let name = parts.count > 1 ? parts[1] : "unknown"
        let epoch = parts.count > 2 ? TimeInterval(parts[2]) : nil
        let detail = split.count > 1 ? String(split[1]) : nil
        let event = CrashEvent(
            timestamp: epoch.map(Date.init(timeIntervalSince1970:)) ?? Date(),
            kind: kind,
            message: "App crashed last session (\(name))",
            context: nil, detail: detail)
        // Bypass de-dup: always surface a hard crash.
        events.append(event)
        if events.count > maxEvents { events.removeFirst(events.count - maxEvents) }
        persist()
        crashedLastSession = true
        try? FileManager.default.removeItem(at: pendingURL)
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; e.outputFormatting = [.prettyPrinted]; return e
    }()
    private static let decoder: JSONDecoder = {
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d
    }()
}
