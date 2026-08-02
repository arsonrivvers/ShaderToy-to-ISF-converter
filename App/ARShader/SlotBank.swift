import Foundation

/// The eight slots and what is in them.
///
/// No SwiftUI import and no `Instrument` reference, following `SurfaceLayout`'s doctrine from phase
/// 3a: every invariant below is then testable with no view and no GPU in play, which is the only
/// kind of test that has been cheap on this surface.
///
/// `capture` takes a finished `Preset` rather than a `DeckID`, because reading a deck's live values
/// requires the `Instrument` — and a bank that holds one is no longer testable without one. Reading
/// the deck is `Instrument.currentPreset(of:)`'s job; this type only stores what it is handed.
@MainActor
final class SlotBank: ObservableObject {
    /// The full grid, always. `bankRows` on `Arrangement` (task 7R) decides how many of these are
    /// DRAWN — never how many exist. That is what makes "shrinking rows can never destroy a
    /// captured look" structural rather than a promise: there is no code path from a resize to
    /// this model, because this model has no concept of rows at all.
    static let slotCount = perRow * maxRows

    /// One row of an APC40 MkII.
    static let perRow = 8

    /// The most rows the strip can be resized to.
    static let maxRows = 5

    @Published private(set) var slots: [Preset?]

    /// Fired after any mutation, so the owner can persist. Not a `sink` on `$slots`, because the
    /// owner needs to know a WRITE happened — a recall republishes nothing and must not cause a
    /// disk write mid-set.
    var onChange: (() -> Void)?

    init(slots: [Preset?] = []) {
        var padded = slots.prefix(Self.slotCount).map { $0 }
        padded.append(contentsOf: Array(repeating: nil, count: Self.slotCount - padded.count))
        self.slots = padded
    }

    /// A look this bank destroyed, kept so exactly one of them can be put back.
    ///
    /// One deep, not a stack (operator ruling, 2026-08-02). The gesture being guarded is a
    /// right-click landing on a menu with one destructive item under the pointer, mid-set; the
    /// answer to that is a way back, not an edit history.
    struct UndoableSlotChange: Equatable {
        enum Kind: Equatable {
            /// The context menu's Clear.
            case cleared
            /// An ⌥-drop that overwrote a filled slot.
            case replaced
        }
        let index: Int
        let preset: Preset
        let kind: Kind

        /// Reads on the menu item that restores it. Names the slot, because the operator fires this
        /// bank by position and "Undo" alone does not say which cell is about to change.
        var menuTitle: String {
            switch kind {
            case .cleared:  return "Undo clear slot \(index + 1)"
            case .replaced: return "Undo replace slot \(index + 1)"
            }
        }
    }

    /// The one look that can be restored, or nil when there is nothing to put back.
    ///
    /// Armed by `clear` and by a `capture` that overwrote something; disarmed by `undo()` and by any
    /// later write to the SAME index. That last rule is what keeps `undo()` from destroying
    /// something the operator captured after the fact: the undoable always describes the most
    /// recent destructive event at an index nothing has touched since.
    @Published private(set) var undoable: UndoableSlotChange?

    private func isValid(_ index: Int) -> Bool { slots.indices.contains(index) }

    func capture(_ preset: Preset, into index: Int) {
        guard isValid(index) else { return }
        if let overwritten = slots[index] {
            undoable = UndoableSlotChange(index: index, preset: overwritten, kind: .replaced)
        } else if undoable?.index == index {
            // Whatever was armed here has been superseded by a fresh capture into the same slot;
            // restoring it now would silently destroy the look just captured.
            undoable = nil
        }
        slots[index] = preset
        onChange?()
    }

    /// Returns what to apply; applying is the caller's job. Nil when the slot is empty OR its file
    /// has gone — firing an unavailable slot is a no-op, not a crash and not a silent partial load.
    func recall(_ index: Int) -> Preset? {
        guard isValid(index), isAvailable(index) else { return nil }
        return slots[index]
    }

    /// Arms `undoable` before emptying the slot (final-review F3). Until this, the only
    /// permanently-destructive slot gesture in the app was the one with no guard at all: the whole
    /// phase is organised around "a drag must never silently replace a dialled-in look" and builds
    /// real machinery for it, while a single context-menu click called this and persisted the loss
    /// before the menu had finished dismissing.
    ///
    /// No dialog and no confirmation sheet, deliberately (operator ruling): this is a live
    /// instrument, and a modal mid-set is the thing being avoided. The way back is a second menu
    /// item, not a gate on the way out.
    func clear(_ index: Int) {
        guard isValid(index) else { return }
        if let cleared = slots[index] {
            undoable = UndoableSlotChange(index: index, preset: cleared, kind: .cleared)
        }
        slots[index] = nil
        onChange?()
    }

    /// Puts the one undoable look back where it was. A no-op when there is nothing to restore, so
    /// the caller needs no guard of its own.
    ///
    /// Disarms afterwards: one deep, and never a redo stack.
    func undo() {
        guard let change = undoable, isValid(change.index) else { return }
        undoable = nil
        slots[change.index] = change.preset
        onChange?()
    }

    /// Filled slots the strip is not currently drawing. Never lost: drawing more rows reveals them
    /// unchanged, because nothing about rows reaches this model.
    ///
    /// Takes rows DRAWN, not rows set, so a collapsed strip (zero drawn) reports every captured
    /// look as hidden. Callers pass `SurfaceLayout.drawnBankRows`; passing `bankRows` is the bug
    /// this parameter name exists to make obvious.
    func hiddenFilledCount(drawnRows: Int) -> Int {
        let visible = max(drawnRows, 0) * Self.perRow
        let start = min(visible, slots.count)
        return slots[start...].lazy.filter { $0 != nil }.count
    }

    /// False for an empty slot and for one whose shader file is no longer on disk. The slot is
    /// deliberately NOT cleared in the second case: an unmounted drive comes back, and destroying
    /// the operator's bank over a bad mount is worse than a dark cell.
    func isAvailable(_ index: Int) -> Bool {
        guard isValid(index), let preset = slots[index] else { return false }
        return FileManager.default.fileExists(atPath: preset.shaderURL.path)
    }
}
