import Foundation

/// One open ISF document in the editor. The editable artifact whose `source` the preview renders.
/// (Named `ISFFile` to avoid clashing with the engine's `ISFDocument`.)
struct ISFFile {
    /// Stable for this in-memory document's lifetime. Struct copies preserve it across edits/Save As;
    /// every fresh untitled/import/example construction receives a new identity.
    let documentID: UUID
    private(set) var url: URL?
    var source: String { didSet { if source != oldValue { isDirty = true } } }
    private(set) var isDirty: Bool
    /// Name carried by an unsaved document that came from somewhere named (a Shadertoy import) —
    /// the title bar shows it instead of "Untitled.fs" (M43). Cleared implicitly on save (url wins).
    private(set) var suggestedName: String?

    /// File name for the title bar / library row; "Untitled.fs" when not yet saved and unnamed.
    var displayName: String { url?.lastPathComponent ?? suggestedName ?? "Untitled.fs" }
    /// True when a plain Save must fall back to Save As (no backing file yet).
    var needsSaveAs: Bool { url == nil }
    /// Any state whose current editor contents do not yet exist durably at the backing URL.
    var hasUnsavedWork: Bool { isDirty || needsSaveAs }

    private init(url: URL?, source: String, isDirty: Bool, suggestedName: String? = nil,
                 documentID: UUID = UUID()) {
        self.documentID = documentID
        self.url = url; self.source = source; self.isDirty = isDirty
        self.suggestedName = suggestedName
    }

    static func untitled(source: String = "", suggestedName: String? = nil) -> ISFFile {
        // Normalize to a .fs filename so the title reads like a file and Save As prefills right.
        let named = suggestedName.map { $0.hasSuffix(".fs") ? $0 : $0 + ".fs" }
        return ISFFile(url: nil, source: source, isDirty: false, suggestedName: named)
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
