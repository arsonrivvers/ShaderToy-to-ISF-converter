import Foundation
import Combine
import ShadertoyISFKit

/// Drives the Inputs/Passes authoring tabs. The code editor text is canonical; this is a live
/// projection of its `/*{…}*/` header. `syncFromText` reflects the text into the GUI (hand edits,
/// document loads); `update` applies a structured edit and pushes the rewritten full source back out
/// via `onRewrite`. No feedback loop: `syncFromText` never calls `onRewrite`, and the host pushes our
/// rewrite through `editor.setText`, which does not re-fire the editor's change handler.
@MainActor
final class HeaderAuthoringModel: ObservableObject {
    enum ParseState: Equatable { case valid, noHeader, malformed }

    @Published private(set) var header = ISFHeader()
    @Published private(set) var state: ParseState = .noHeader

    /// Wired by the host (EditorViewModel) to: set file.source, push to the editor, and recompile.
    var onRewrite: ((String) -> Void)?

    /// The canonical source the GUI last saw — mutations are spliced into this.
    private var currentSource = ""

    /// Reflect the canonical text into the GUI. Keeps the last good `header` when the JSON is
    /// malformed so the fields stay visible (read-only) instead of blanking.
    func syncFromText(_ source: String) {
        currentSource = source
        do {
            header = try ISFHeader.parse(source)
            state = .valid
        } catch ISFHeaderError.noHeader {
            state = .noHeader
        } catch {
            state = .malformed
        }
    }

    /// Apply a structured mutation, then emit the rewritten full source. Refuses to write over a
    /// malformed header (we'd clobber JSON we couldn't parse). From `.noHeader`, seeds a minimal header.
    func update(_ mutate: (inout ISFHeader) -> Void) {
        guard state != .malformed else { return }
        var h = (state == .noHeader) ? ISFHeader.empty : header
        mutate(&h)
        header = h
        state = .valid
        let newSource = h.write(into: currentSource)
        currentSource = newSource
        onRewrite?(newSource)
    }

    /// True when `name` would collide with another input (case-sensitive) or is empty — the views use
    /// this to block an invalid rename before it writes broken ISF.
    func nameIsValid(_ name: String, atInputIndex index: Int) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }
        for (i, input) in header.inputs.enumerated() where i != index {
            if input.name == trimmed { return false }
        }
        return true
    }
}
