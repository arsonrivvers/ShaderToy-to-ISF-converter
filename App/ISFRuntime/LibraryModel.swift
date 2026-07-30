import Foundation

/// A single `.fs` file shown in the library sidebar.
struct LibraryEntry: Identifiable, Hashable {
    let url: URL
    let dateAdded: Date
    let dateModified: Date
    var name: String { url.lastPathComponent }
    var id: URL { url }

    init(url: URL, dateAdded: Date = .distantPast, dateModified: Date = .distantPast) {
        self.url = url
        self.dateAdded = dateAdded
        self.dateModified = dateModified
    }
}

/// Sidebar sort order for library entries.
enum LibrarySort: String, CaseIterable, Identifiable {
    case name = "Name"
    case recentlyAdded = "Recently Added"
    case recentlyModified = "Recently Modified"
    var id: String { rawValue }
}

/// A folder the library lists `.fs` files from (User / System / user-added).
struct LibrarySource: Identifiable, Hashable {
    let title: String
    let url: URL
    var id: URL { url }
}

/// Lists `.fs` files from one or more source folders. Lazy: never parses file contents,
/// only enumerates names — safe for the ~1,400-file System library.
final class LibraryModel: ObservableObject {
    @Published private(set) var sources: [LibrarySource] = []
    private var entriesBySource: [URL: [LibraryEntry]] = [:]
    private let defaultsKey = "TrueISFEditor.addedFolders"

    static var userISFDir: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Graphics/ISF")
    }
    static let systemISFDir = URL(fileURLWithPath: "/Library/Graphics/ISF")

    /// Enumerate `.fs` files in a folder, case-insensitive extension, sorted by name. Fetches file
    /// dates during enumeration (metadata only, still content-lazy) so sort orders have data.
    static func scan(folder: URL) -> [LibraryEntry] {
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.creationDateKey, .contentModificationDateKey]
        let items = (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys)) ?? []
        return items
            .filter { $0.pathExtension.lowercased() == "fs" }
            .map { url -> LibraryEntry in
                let vals = try? url.resourceValues(forKeys: Set(keys))
                return LibraryEntry(url: url,
                                    dateAdded: vals?.creationDate ?? .distantPast,
                                    dateModified: vals?.contentModificationDate ?? .distantPast)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func sorted(_ entries: [LibraryEntry], by sort: LibrarySort) -> [LibraryEntry] {
        switch sort {
        case .name:
            return entries.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .recentlyAdded:
            return entries.sorted { $0.dateAdded > $1.dateAdded }
        case .recentlyModified:
            return entries.sorted { $0.dateModified > $1.dateModified }
        }
    }

    func addFolder(_ url: URL, title: String? = nil) {
        guard !sources.contains(where: { $0.url == url }) else { return }
        sources.append(LibrarySource(title: title ?? url.lastPathComponent, url: url))
        entriesBySource[url] = Self.scan(folder: url)
        persist()
    }

    func entries(for source: LibrarySource, sort: LibrarySort = .name) -> [LibraryEntry] {
        Self.sorted(entriesBySource[source.url] ?? [], by: sort)
    }

    /// All entries across sources, filtered by whitespace-separated tokens — EVERY token must
    /// appear somewhere in the name (case-insensitive), in any order. "genuary 14" matches
    /// "Genuary2026_Day14.fs"; a single token behaves like the old substring filter.
    func filtered(query: String, sort: LibrarySort = .name) -> [LibraryEntry] {
        let tokens = query.split(whereSeparator: \.isWhitespace).map(String.init)
        let all = sources.flatMap { entriesBySource[$0.url] ?? [] }
        let matched = tokens.isEmpty ? all : all.filter { entry in
            tokens.allSatisfy { entry.name.localizedCaseInsensitiveContains($0) }
        }
        return Self.sorted(matched, by: sort)
    }

    /// First-launch: auto-load the standard ISF directories (no prompt) plus any user-added folders.
    /// The app-bundled sample gallery (repo `/samples`, shipped as a folder reference). Nil in
    /// contexts without the resource (unit tests against the bare module).
    static var bundledSamplesDir: URL? {
        guard let url = Bundle.main.resourceURL?.appendingPathComponent("samples"),
              FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    func loadStandardLibraries() {
        let fm = FileManager.default
        if let samples = Self.bundledSamplesDir { addFolder(samples, title: "Samples") }
        // Headless test mode: never scan the user's real folders from a test host — persisted
        // added folders can live in TCC-protected locations (Documents), and the resulting
        // permission prompt blocks the harness until the user clicks it.
        guard !TestHarness.isActive else { return }
        if fm.fileExists(atPath: Self.userISFDir.path) { addFolder(Self.userISFDir, title: "User") }
        if fm.fileExists(atPath: Self.systemISFDir.path) { addFolder(Self.systemISFDir, title: "System") }
        for path in (UserDefaults.standard.array(forKey: defaultsKey) as? [String] ?? []) {
            let u = URL(fileURLWithPath: path)
            if fm.fileExists(atPath: u.path) { addFolder(u) }
        }
    }

    /// True while a background scan is in flight, so the UI can say "Scanning…" rather than
    /// report a count it does not have yet.
    @Published private(set) var isScanning = false

    private let scanQueue = DispatchQueue(label: "isfruntime.library.scan", qos: .userInitiated)

    /// The instrument's libraries: the authoritative system corpus at `/Library/Graphics/ISF`
    /// (the `AR_` originals including the Genuary series) plus the operator's own folder.
    ///
    /// Unlike the editor's `loadStandardLibraries`, no bundled samples: a performance instrument
    /// browses the operator's real corpus, not a demo gallery.
    ///
    /// **Enumeration runs OFF the main thread.** The corpus is ~1,500 files and the scan stats
    /// each one for its dates; doing that inline inside a SwiftUI `.task` (which runs on the main
    /// actor) froze the app at launch and showed "0 shaders" until it finished. Reported on the
    /// Milestone 1 smoke, 2026-07-30 — it only looked instant in testing because the filesystem
    /// cache was warm.
    ///
    /// Call on the main thread; results are applied on the main thread.
    func loadInstrumentLibraries() {
        // Headless test mode: never scan the operator's real folders from a test host — a
        // persisted folder in a TCC-protected location blocks the harness behind a permission
        // prompt.
        guard !TestHarness.isActive else { return }
        let fm = FileManager.default
        let known = Set(sources.map(\.url))
        let candidates: [(url: URL, title: String)] = [
            (url: Self.systemISFDir, title: "System"),
            (url: Self.userISFDir, title: "User"),
        ].filter { fm.fileExists(atPath: $0.url.path) && !known.contains($0.url) }
        guard !candidates.isEmpty else { return }

        // Register the folders immediately so the sidebar shows WHAT is loading, then scan.
        for c in candidates { sources.append(LibrarySource(title: c.title, url: c.url)) }
        isScanning = true

        let urls = candidates.map(\.url)
        scanQueue.async { [weak self] in
            // `scan` is a pure static over the filesystem — no model state is touched here.
            let scanned = urls.map { ($0, Self.scan(folder: $0)) }
            DispatchQueue.main.async {
                guard let self else { return }
                for (url, entries) in scanned { self.entriesBySource[url] = entries }
                self.isScanning = false
                self.objectWillChange.send()
            }
        }
    }

    private func persist() {
        // Headless test mode: the host shares the real defaults domain — a test-launched model
        // (which skips the user's folders above) must never overwrite the user's saved list.
        guard !TestHarness.isActive else { return }
        // Bundled samples must never persist as a user-added folder — the bundle path changes
        // per install location and would accumulate stale entries.
        let optionalPaths: [String?] = [Self.userISFDir.path, Self.systemISFDir.path,
                                        Self.bundledSamplesDir?.path]
        let standardPaths = optionalPaths.compactMap { $0 }
        let added = sources.map(\.url.path).filter { !standardPaths.contains($0) }
        UserDefaults.standard.set(added, forKey: defaultsKey)
    }
}
