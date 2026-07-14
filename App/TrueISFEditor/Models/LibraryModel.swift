import Foundation

/// A single `.fs` file shown in the library sidebar.
struct LibraryEntry: Identifiable, Hashable {
    let url: URL
    var name: String { url.lastPathComponent }
    var id: URL { url }
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

    private static var userISFDir: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Graphics/ISF")
    }
    private static let systemISFDir = URL(fileURLWithPath: "/Library/Graphics/ISF")

    /// Enumerate `.fs` files in a folder, case-insensitive extension, sorted by name.
    static func scan(folder: URL) -> [LibraryEntry] {
        let fm = FileManager.default
        let items = (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return items
            .filter { $0.pathExtension.lowercased() == "fs" }
            .map { LibraryEntry(url: $0) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func addFolder(_ url: URL, title: String? = nil) {
        guard !sources.contains(where: { $0.url == url }) else { return }
        sources.append(LibrarySource(title: title ?? url.lastPathComponent, url: url))
        entriesBySource[url] = Self.scan(folder: url)
        persist()
    }

    func entries(for source: LibrarySource) -> [LibraryEntry] { entriesBySource[source.url] ?? [] }

    /// All entries across sources, filtered by a case-insensitive name substring.
    func filtered(query: String) -> [LibraryEntry] {
        let all = sources.flatMap { entriesBySource[$0.url] ?? [] }
        guard !query.isEmpty else { return all }
        return all.filter { $0.name.localizedCaseInsensitiveContains(query) }
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
        if fm.fileExists(atPath: Self.userISFDir.path) { addFolder(Self.userISFDir, title: "User") }
        if fm.fileExists(atPath: Self.systemISFDir.path) { addFolder(Self.systemISFDir, title: "System") }
        for path in (UserDefaults.standard.array(forKey: defaultsKey) as? [String] ?? []) {
            let u = URL(fileURLWithPath: path)
            if fm.fileExists(atPath: u.path) { addFolder(u) }
        }
    }

    private func persist() {
        // Bundled samples must never persist as a user-added folder — the bundle path changes
        // per install location and would accumulate stale entries.
        let optionalPaths: [String?] = [Self.userISFDir.path, Self.systemISFDir.path,
                                        Self.bundledSamplesDir?.path]
        let standardPaths = optionalPaths.compactMap { $0 }
        let added = sources.map(\.url.path).filter { !standardPaths.contains($0) }
        UserDefaults.standard.set(added, forKey: defaultsKey)
    }
}
