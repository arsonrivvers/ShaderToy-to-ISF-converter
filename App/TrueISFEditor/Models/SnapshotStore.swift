import Foundation
import CryptoKit

/// What created a version. `legacy` = a pre-kind snapshot file (decoded tolerant, never migrated).
enum SnapshotKind: Equatable {
    case save(number: Int)
    case aiApply
    case pin(name: String?)
    case safety
    case legacy
}

/// One saved version of a document: full source + the param values at capture time.
struct Snapshot: Identifiable, Equatable {
    let id: String            // filename stem
    let date: Date
    let label: String         // "Opened", "Before AI rewrite", "v03", ...
    let source: String
    let params: ParamSnapshot
    let kind: SnapshotKind

    init(id: String, date: Date, label: String, source: String, params: ParamSnapshot,
         kind: SnapshotKind = .legacy) {
        self.id = id; self.date = date; self.label = label
        self.source = source; self.params = params; self.kind = kind
    }

    /// Row title: saves show their number, pins their name; everything else its stored label.
    var displayTitle: String {
        switch kind {
        case .save(let n): return String(format: "v%02d", n)
        case .pin(let name): return name ?? "Pinned"
        case .aiApply, .safety, .legacy: return label
        }
    }
}

/// Disk-backed version history (D1): one folder per document key, one JSON file per version.
/// Bounded per document, dedupes identical-source captures, and NEVER throws into the editing
/// flow — a failed snapshot must not block an open or an AI apply (capture returns nil).
@MainActor
final class SnapshotStore: ObservableObject {
    let rootURL: URL
    let cap: Int
    @Published private(set) var revision = 0

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
        let kind: String?
        let number: Int?
        let name: String?
    }

    private static func decodeKind(_ kind: String?, number: Int?, name: String?) -> SnapshotKind {
        switch kind {
        case "save": if let n = number { return .save(number: n) }; return .legacy
        case "aiApply": return .aiApply
        case "pin": return .pin(name: name)
        case "safety": return .safety
        default: return .legacy   // absent or unknown → tolerant
        }
    }

    private static func encodeKind(_ k: SnapshotKind) -> (kind: String?, number: Int?, name: String?) {
        switch k {
        case .save(let n): return ("save", n, nil)
        case .aiApply: return ("aiApply", nil, nil)
        case .pin(let name): return ("pin", nil, name)
        case .safety: return ("safety", nil, nil)
        case .legacy: return (nil, nil, nil)
        }
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
                                date: f.date, label: f.label, source: f.source, params: f.params,
                                kind: Self.decodeKind(f.kind, number: f.number, name: f.name))
            }
            .sorted { $0.date != $1.date ? $0.date > $1.date : $0.id > $1.id }
    }

    /// Capture a version. Returns nil (and writes nothing) when the newest existing version has
    /// identical source, or when any file operation fails.
    @discardableResult
    func capture(file: ISFFile, params: ParamSnapshot, label: String,
                 kind: SnapshotKind = .legacy) -> Snapshot? {
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
        let encodedKind = Self.encodeKind(kind)
        guard let data = try? encoder.encode(
            SnapshotFile(date: date, label: label, source: file.source, params: params,
                         kind: encodedKind.kind, number: encodedKind.number, name: encodedKind.name)) else { return nil }
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
        revision += 1
        return Snapshot(id: stem, date: date, label: label, source: file.source, params: params,
                        kind: kind)
    }

    /// v-number the NEXT ⌘S will mint for this document: highest existing save number + 1.
    func nextSaveNumber(for file: ISFFile) -> Int {
        let maxSave = snapshots(for: file).compactMap { snap -> Int? in
            if case .save(let n) = snap.kind { return n } else { return nil }
        }.max() ?? 0
        return maxSave + 1
    }
}
