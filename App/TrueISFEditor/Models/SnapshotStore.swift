import Foundation
import CryptoKit

/// One saved version of a document: full source + the param values at capture time.
struct Snapshot: Identifiable, Equatable {
    let id: String            // filename stem
    let date: Date
    let label: String         // "Opened", "Before AI rewrite", "Before restore", ...
    let source: String
    let params: ParamSnapshot
}

/// Disk-backed version history (D1): one folder per document key, one JSON file per version.
/// Bounded per document, dedupes identical-source captures, and NEVER throws into the editing
/// flow — a failed snapshot must not block an open or an AI apply (capture returns nil).
@MainActor
final class SnapshotStore: ObservableObject {
    let rootURL: URL
    let cap: Int

    init(rootURL: URL? = nil, cap: Int = 30) {
        self.rootURL = rootURL ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TrueISFEditor/Snapshots")
        self.cap = cap
    }

    /// Stable, filesystem-safe per-document folder name. Saved docs key on their path; untitled
    /// docs on their display name (an unsaved import keeps one history while it stays unsaved).
    static func documentKey(for file: ISFFile) -> String {
        let identity = file.url?.path ?? "untitled:\(file.displayName)"
        let digest = SHA256.hash(data: Data(identity.utf8))
        let hex = digest.prefix(6).map { String(format: "%02x", $0) }.joined()
        let safeName = String(file.displayName.map { $0.isLetter || $0.isNumber ? $0 : "-" })
        return "\(safeName)-\(hex)"
    }

    private struct SnapshotFile: Codable {
        let date: Date
        let label: String
        let source: String
        let params: ParamSnapshot
    }

    private func directory(for file: ISFFile) -> URL {
        rootURL.appendingPathComponent(Self.documentKey(for: file))
    }

    /// Newest first. Corrupt or unreadable files are skipped.
    func snapshots(for file: ISFFile) -> [Snapshot] {
        let dir = directory(for: file)
        let items = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        let decoder = JSONDecoder()
        // secondsSince1970 keeps full Double precision — .iso8601 truncates to whole seconds,
        // which made same-second captures (rapid fix applies) sort unstably.
        decoder.dateDecodingStrategy = .secondsSince1970
        return items
            .filter { $0.pathExtension == "json" }
            .compactMap { url -> Snapshot? in
                guard let data = try? Data(contentsOf: url),
                      let f = try? decoder.decode(SnapshotFile.self, from: data) else { return nil }
                return Snapshot(id: url.deletingPathExtension().lastPathComponent,
                                date: f.date, label: f.label, source: f.source, params: f.params)
            }
            .sorted { $0.date != $1.date ? $0.date > $1.date : $0.id > $1.id }
    }

    /// Capture a version. Returns nil (and writes nothing) when the newest existing version has
    /// identical source, or when any file operation fails.
    @discardableResult
    func capture(file: ISFFile, params: ParamSnapshot, label: String) -> Snapshot? {
        let existing = snapshots(for: file)
        if existing.first?.source == file.source { return nil }

        let dir = directory(for: file)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let date = Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        var stem = formatter.string(from: date)
        // Same-millisecond captures (rapid fix applies) get a monotonic suffix.
        var counter = 1
        while FileManager.default.fileExists(atPath: dir.appendingPathComponent("\(stem).json").path) {
            stem = "\(formatter.string(from: date))-\(counter)"
            counter += 1
        }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        guard let data = try? encoder.encode(
            SnapshotFile(date: date, label: label, source: file.source, params: params)) else { return nil }
        do {
            try data.write(to: dir.appendingPathComponent("\(stem).json"), options: .atomic)
        } catch { return nil }

        // Prune oldest beyond the cap.
        let all = snapshots(for: file)
        if all.count > cap {
            for stale in all.suffix(all.count - cap) {
                try? FileManager.default.removeItem(
                    at: dir.appendingPathComponent("\(stale.id).json"))
            }
        }
        return Snapshot(id: stem, date: date, label: label, source: file.source, params: params)
    }
}
