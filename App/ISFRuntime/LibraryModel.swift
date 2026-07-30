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

    /// The instrument's libraries: the authoritative system corpus at `/Library/Graphics/ISF`
    /// (947 `AR_` originals including the Genuary series) plus the user's own folder.
    ///
    /// Unlike the editor's `loadStandardLibraries`, no bundled samples: a performance instrument
    /// browses the operator's real corpus, not a demo gallery.
    func loadInstrumentLibraries() {
        // Headless test mode: never scan the user's real folders from a test host — a persisted
        // folder in a TCC-protected location blocks the harness behind a permission prompt.
        guard !TestHarness.isActive else { return }
        let fm = FileManager.default
        if fm.fileExists(atPath: Self.systemISFDir.path) {
            addFolder(Self.systemISFDir, title: "System")
        }
        if fm.fileExists(atPath: Self.userISFDir.path) {
            addFolder(Self.userISFDir, title: "User")
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
