import Foundation

/// A bundled starter shader (repo /templates, shipped as a folder reference).
struct ShaderTemplate: Identifiable {
    let id: String        // filename stem, e.g. "NS Layer Blend"
    let name: String      // display name (the stem)
    let sourceText: String
}

enum TemplateCatalog {
    /// Nil in contexts without the resource (bare-module unit tests).
    static var bundledTemplatesDir: URL? {
        guard let url = Bundle.main.resourceURL?.appendingPathComponent("templates"),
              FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    /// All bundled templates, alphabetical. Computed (not cached): the list is tiny and the
    /// menu builds rarely.
    static var all: [ShaderTemplate] {
        guard let dir = bundledTemplatesDir else { return [] }
        let items = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        return items
            .filter { $0.pathExtension.lowercased() == "fs" }
            .sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
            .compactMap { url in
                guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
                let stem = url.deletingPathExtension().lastPathComponent
                return ShaderTemplate(id: stem, name: stem, sourceText: text)
            }
    }
}
