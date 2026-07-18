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
/// Bounded per document, dedupes saves against the newest save and legacy captures against the
/// newest entry, and NEVER throws into the editing flow — a failed snapshot must not block an
/// open or an AI apply (capture returns nil).
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

    private struct MigrationEntry {
        let sourceURL: URL
        let originalData: Data
        let date: Double
        let originalSaveNumber: Int?
        var plannedData: Data
        var alreadyRepresented: Bool
    }

    /// A save's identity without its presentation number. This lets an interrupted migration
    /// recognize a save it already renumbered on the previous attempt instead of minting another
    /// copy. Date, source, params, and unknown metadata remain part of the identity.
    private static func saveMetadata(in data: Data) -> (number: Int, date: Double, identity: Data)? {
        guard var object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              object["kind"] as? String == "save",
              let number = (object["number"] as? NSNumber)?.intValue else { return nil }
        let date = (object["date"] as? NSNumber)?.doubleValue ?? 0
        object.removeValue(forKey: "number")
        object.removeValue(forKey: "label")
        guard let identity = try? JSONSerialization.data(withJSONObject: object,
                                                         options: [.sortedKeys]) else { return nil }
        return (number, date, identity)
    }

    /// Renumber only a colliding incoming save. Unknown fields survive; non-colliding entries never
    /// pass through JSONSerialization and therefore remain byte-for-byte unchanged.
    private static func renumberedSave(_ data: Data, to number: Int) -> Data? {
        guard var object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              object["kind"] as? String == "save" else { return nil }
        object["number"] = number
        object["label"] = String(format: "v%02d", number)
        return try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    /// Move a document's raw history when Save As changes its identity key. Best effort and
    /// deliberately nonthrowing: snapshot maintenance must never turn a successful file save into
    /// a reported failure. Existing destination save numbers win; non-conflicting incoming saves
    /// retain their number and raw bytes, while conflicts append oldest-first above the merged max.
    /// Returns true only when the source key is no longer needed, so callers can retain failed work
    /// and retry it after a later successful shader save.
    @discardableResult
    func migrateHistory(from sourceFile: ISFFile, to destinationFile: ISFFile) -> Bool {
        let sourceDirectory = directory(for: sourceFile)
        let destinationDirectory = directory(for: destinationFile)
        guard sourceDirectory.standardizedFileURL != destinationDirectory.standardizedFileURL else {
            return true
        }

        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: sourceDirectory.path, isDirectory: &isDirectory) else {
            return true
        }
        guard isDirectory.boolValue,
              let sourceItems = try? fileManager.contentsOfDirectory(
                  at: sourceDirectory, includingPropertiesForKeys: nil
              ) else { return false }

        let sourceEntries = sourceItems.filter { $0.pathExtension == "json" }.sorted {
            $0.path < $1.path
        }
        let destinationEntries = (try? fileManager.contentsOfDirectory(
            at: destinationDirectory, includingPropertiesForKeys: nil
        ))?.filter { $0.pathExtension == "json" }.sorted { $0.path < $1.path } ?? []
        let destinationEntryPayloads = destinationEntries.compactMap { entry -> (URL, Data)? in
            guard let data = try? Data(contentsOf: entry) else { return nil }
            return (entry, data)
        }
        var destinationPayloads = destinationEntryPayloads.map(\.1)
        var destinationSavePayloadsByIdentity: [Data: Data] = [:]
        var claimedSaveNumbers = Set<Int>()
        for (_, data) in destinationEntryPayloads {
            guard let metadata = Self.saveMetadata(in: data) else { continue }
            claimedSaveNumbers.insert(metadata.number)
            if destinationSavePayloadsByIdentity[metadata.identity] == nil {
                destinationSavePayloadsByIdentity[metadata.identity] = data
            }
        }

        var migrationEntries: [MigrationEntry] = []
        var sourcePayloads: [String: Data] = [:]
        var priorRenumberedNumbers = Set<Int>()
        var materialChange = false
        var migrationViable = sourceEntries.count == sourceItems.count

        for sourceEntry in sourceEntries {
            guard let data = try? Data(contentsOf: sourceEntry) else {
                migrationViable = false
                continue
            }
            sourcePayloads[sourceEntry.path] = data
            let metadata = Self.saveMetadata(in: data)
            let exactDestinationMatch = destinationPayloads.contains(data)
            let priorRenumberedMatch = metadata.flatMap {
                destinationSavePayloadsByIdentity[$0.identity]
            }
            if let priorRenumberedMatch,
               priorRenumberedMatch != data,
               let priorMetadata = Self.saveMetadata(in: priorRenumberedMatch) {
                priorRenumberedNumbers.insert(priorMetadata.number)
            }
            migrationEntries.append(MigrationEntry(
                sourceURL: sourceEntry,
                originalData: data,
                date: metadata?.date ?? 0,
                originalSaveNumber: metadata?.number,
                plannedData: priorRenumberedMatch ?? data,
                alreadyRepresented: exactDestinationMatch || priorRenumberedMatch != nil
            ))
        }

        // Reserve every original number before assigning conflicts so a non-conflicting incoming
        // save never gets displaced by an earlier collision. Example: destination {1,2}, incoming
        // {1,3} keeps incoming v03 raw and renumbers only incoming v01 to v04.
        let incomingSaveIndices = migrationEntries.indices.filter {
            !migrationEntries[$0].alreadyRepresented
                && migrationEntries[$0].originalSaveNumber != nil
        }.sorted {
            let lhs = migrationEntries[$0]
            let rhs = migrationEntries[$1]
            return lhs.date != rhs.date ? lhs.date < rhs.date
                : lhs.sourceURL.path < rhs.sourceURL.path
        }
        let mergedOriginalNumbers = Array(claimedSaveNumbers.subtracting(priorRenumberedNumbers))
            + migrationEntries.compactMap(\.originalSaveNumber)
        var collisionIndices: [Int] = []
        for index in incomingSaveIndices {
            guard let number = migrationEntries[index].originalSaveNumber else { continue }
            if claimedSaveNumbers.contains(number) {
                collisionIndices.append(index)
            } else {
                claimedSaveNumbers.insert(number)
            }
        }
        var nextCollisionNumber = (mergedOriginalNumbers.max() ?? 0) + 1
        for index in collisionIndices {
            while claimedSaveNumbers.contains(nextCollisionNumber) {
                nextCollisionNumber += 1
            }
            guard let data = Self.renumberedSave(migrationEntries[index].originalData,
                                                 to: nextCollisionNumber) else {
                migrationViable = false
                continue
            }
            migrationEntries[index].plannedData = data
            claimedSaveNumbers.insert(nextCollisionNumber)
            nextCollisionNumber += 1
        }

        func availableDestination(for sourceEntry: URL) -> URL {
            let preferred = destinationDirectory.appendingPathComponent(sourceEntry.lastPathComponent)
            guard fileManager.fileExists(atPath: preferred.path) else { return preferred }
            let stem = sourceEntry.deletingPathExtension().lastPathComponent
            var suffix = 1
            while true {
                let candidate = destinationDirectory
                    .appendingPathComponent("\(stem)-migrated-\(suffix).json")
                if !fileManager.fileExists(atPath: candidate.path) { return candidate }
                suffix += 1
            }
        }

        for entry in migrationEntries {
            if destinationPayloads.contains(entry.plannedData) { continue }

            do {
                try fileManager.createDirectory(at: destinationDirectory,
                                                withIntermediateDirectories: true)
                let target = availableDestination(for: entry.sourceURL)
                if entry.plannedData == entry.originalData {
                    // copyItem refuses an externally-created collision instead of replacing it.
                    try fileManager.copyItem(at: entry.sourceURL, to: target)
                } else {
                    // A temporary move gives renumbered data the same no-overwrite collision
                    // guarantee as copyItem.
                    let temporary = destinationDirectory
                        .appendingPathComponent(".snapshot-migration-\(UUID().uuidString).tmp")
                    defer { try? fileManager.removeItem(at: temporary) }
                    try entry.plannedData.write(to: temporary, options: .atomic)
                    try fileManager.moveItem(at: temporary, to: target)
                }
                guard (try? Data(contentsOf: target)) == entry.plannedData else {
                    migrationViable = false
                    continue
                }
                destinationPayloads.append(entry.plannedData)
                materialChange = true
            } catch {
                migrationViable = false
            }
        }

        // Re-read from disk before retiring the old key. A partial write or unreadable destination
        // keeps the source directory intact so a later Save As/retry can finish safely.
        let finalDestinationEntries = (try? fileManager.contentsOfDirectory(
            at: destinationDirectory, includingPropertiesForKeys: nil
        ))?.filter { $0.pathExtension == "json" } ?? []
        let finalDestinationPayloads = finalDestinationEntries.compactMap {
            try? Data(contentsOf: $0)
        }
        let everySourceEntryPresent = migrationViable
            && sourcePayloads.count == sourceEntries.count
            && migrationEntries.allSatisfy {
                finalDestinationPayloads.contains($0.plannedData)
            }
        let currentSourceItems = try? fileManager.contentsOfDirectory(
            at: sourceDirectory, includingPropertiesForKeys: nil
        )
        let sourceDirectoryUnchanged = currentSourceItems.map { currentItems in
            guard Set(currentItems.map(\.path)) == Set(sourceItems.map(\.path)) else {
                return false
            }
            return sourceEntries.allSatisfy { entry in
                guard let expected = sourcePayloads[entry.path] else { return false }
                return (try? Data(contentsOf: entry)) == expected
            }
        } ?? false

        if everySourceEntryPresent && sourceDirectoryUnchanged {
            do {
                try fileManager.removeItem(at: sourceDirectory)
                materialChange = true
            } catch {
                // The save itself remains successful; the old history stays available for retry.
            }

            // The merge is safe now. Bound the destination exactly like capture(), oldest first.
            let merged = snapshots(for: destinationFile)
            if merged.count > cap {
                for stale in merged.suffix(merged.count - cap) {
                    do {
                        try fileManager.removeItem(
                            at: destinationDirectory.appendingPathComponent("\(stale.id).json")
                        )
                        materialChange = true
                    } catch {
                        // Best effort: one failed prune must not block the remaining entries.
                    }
                }
            }
        }

        if materialChange { revision += 1 }
        return !fileManager.fileExists(atPath: sourceDirectory.path)
    }

    /// Capture a version. Saves dedupe against the newest save, legacy captures against the newest
    /// entry, and event kinds always record the event. Returns nil when deduped or on write failure.
    @discardableResult
    func capture(file: ISFFile, params: ParamSnapshot, label: String,
                 kind: SnapshotKind = .legacy) -> Snapshot? {
        let existing = snapshots(for: file)
        switch kind {
        case .save:
            let newestSave = existing.first {
                if case .save = $0.kind { return true } else { return false }
            }
            if newestSave?.source == file.source { return nil }
        case .legacy:
            if existing.first?.source == file.source { return nil }
        case .aiApply, .pin, .safety:
            break
        }

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
