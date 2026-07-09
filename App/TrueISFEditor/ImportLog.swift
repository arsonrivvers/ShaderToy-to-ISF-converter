import Foundation
import Combine

/// Persistent, in-memory-mirrored log of Shadertoy import attempts. Singleton because
/// `AppModel.convert()` records into one process-wide log surfaced by the Import Log window.
@MainActor
final class ImportLog: ObservableObject {
    static let shared = ImportLog()

    @Published private(set) var events: [ImportEvent] = []

    private let maxEvents = 200
    let fileURL: URL

    /// `directory` override for tests; defaults to ~/Library/Logs/TrueISFEditor.
    init(directory: URL? = nil) {
        let dir = directory ?? FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs/TrueISFEditor")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.fileURL = dir.appendingPathComponent("import-log.json")
        load()
    }

    /// No de-dup: distinct attempts are individually meaningful (unlike per-keystroke compile spam).
    func record(_ event: ImportEvent) {
        events.appendBounded(event, max: maxEvents)
        persist()
    }

    func clear() { events.removeAll(); persist() }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? Self.decoder.decode([ImportEvent].self, from: data) else { return }
        events = decoded
    }
    private func persist() {
        guard let data = try? Self.encoder.encode(events) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
    private static let encoder: JSONEncoder = {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; e.outputFormatting = [.prettyPrinted]; return e
    }()
    private static let decoder: JSONDecoder = {
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d
    }()
}
