import Foundation
import CryptoKit

/// The disk half of the thumbnail pipeline, deliberately split from the render half: everything
/// here is testable with no Metal, no GPU, and no fixture shader that has to compile.
struct ThumbnailCache {
    enum Entry: Equatable {
        case image(Data)        // PNG bytes
        /// A shader that would not compile. Cached so a broken shader is not recompiled on every
        /// hover; invalidated by mtime like any other entry, so fixing it on disk retries it.
        case unavailable
    }

    private let directory: URL

    /// Where entries actually land. Read only through `ThumbnailService.cacheDirectoryForTesting`;
    /// see that property for what it guards.
    var directoryForTesting: URL { directory }

    init(directory: URL) throws {
        self.directory = directory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// Path + modification date. Both, because either alone is wrong: path alone never notices an
    /// edit, and mtime alone collides across the ~1,500-shader library.
    static func key(for shaderURL: URL) throws -> String {
        let attrs = try FileManager.default.attributesOfItem(atPath: shaderURL.path)
        let modified = (attrs[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        let seed = "\(shaderURL.standardizedFileURL.path)|\(modified)"
        let digest = SHA256.hash(data: Data(seed.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    func entry(for shaderURL: URL) throws -> Entry? {
        let base = directory.appendingPathComponent(try Self.key(for: shaderURL))
        let png = base.appendingPathExtension("png")
        let failed = base.appendingPathExtension("failed")
        if let data = try? Data(contentsOf: png) {
            try? touch(png)
            return .image(data)
        }
        if FileManager.default.fileExists(atPath: failed.path) {
            try? touch(failed)
            return .unavailable
        }
        return nil
    }

    func store(_ entry: Entry, for shaderURL: URL) throws {
        let base = directory.appendingPathComponent(try Self.key(for: shaderURL))
        switch entry {
        case .image(let data): try data.write(to: base.appendingPathExtension("png"))
        case .unavailable:     try Data().write(to: base.appendingPathExtension("failed"))
        }
    }

    /// LRU by modification date. Called once at launch and never during a set — a sweep
    /// mid-performance is disk I/O the operator did not ask for at the worst possible moment.
    ///
    /// Deliberately `contentModificationDate`, not `contentAccessDate`: `touch()` below can only
    /// set mtime (`FileManager.setAttributes` has no settable access-date key), and atime updates
    /// are unreliable to begin with — many volumes mount `noatime`/`relatime` and never bump it on
    /// a read. Sorting by a date nothing writes would make eviction order arbitrary.
    func evict(keepingAtMost ceiling: Int) throws {
        let keys: [URLResourceKey] = [.contentModificationDateKey]
        let files = try FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: keys)
        guard files.count > ceiling else { return }
        let sorted = try files.sorted {
            let a = try $0.resourceValues(forKeys: Set(keys)).contentModificationDate ?? .distantPast
            let b = try $1.resourceValues(forKeys: Set(keys)).contentModificationDate ?? .distantPast
            return a > b                                   // newest first
        }
        for stale in sorted.dropFirst(ceiling) {
            try? FileManager.default.removeItem(at: stale)
        }
    }

    private func touch(_ url: URL) throws {
        try FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
    }
}
