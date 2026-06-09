import Foundation

/// One open ISF document in the editor. The editable artifact whose `source` the preview renders.
/// (Named `ISFFile` to avoid clashing with the engine's `ISFDocument`.)
struct ISFFile {
    private(set) var url: URL?
    var source: String { didSet { if source != oldValue { isDirty = true } } }
    private(set) var isDirty: Bool

    /// File name for the title bar / library row; "Untitled.fs" when not yet saved.
    var displayName: String { url?.lastPathComponent ?? "Untitled.fs" }
    /// True when a plain Save must fall back to Save As (no backing file yet).
    var needsSaveAs: Bool { url == nil }

    private init(url: URL?, source: String, isDirty: Bool) {
        self.url = url; self.source = source; self.isDirty = isDirty
    }

    static func untitled(source: String = "") -> ISFFile {
        ISFFile(url: nil, source: source, isDirty: false)
    }

    init(contentsOf url: URL) throws {
        self.init(url: url, source: try String(contentsOf: url, encoding: .utf8), isDirty: false)
    }

    /// Save to an explicit location (Save As, or first save of an untitled doc).
    mutating func save(to target: URL) throws {
        try source.write(to: target, atomically: true, encoding: .utf8)
        url = target
        isDirty = false
    }

    /// Save to the existing backing file. No-op if untitled (caller should route to Save As).
    mutating func save() throws {
        guard let u = url else { return }
        try save(to: u)
    }
}
