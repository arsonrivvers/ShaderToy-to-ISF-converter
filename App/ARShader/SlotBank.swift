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
    /// One row of an APC40 MkII. The full 8x5 grid is a change of this constant plus a layout,
    /// never a change of model.
    static let slotCount = 8

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

    private func isValid(_ index: Int) -> Bool { slots.indices.contains(index) }

    func capture(_ preset: Preset, into index: Int) {
        guard isValid(index) else { return }
        slots[index] = preset
        onChange?()
    }

    /// Returns what to apply; applying is the caller's job. Nil when the slot is empty OR its file
    /// has gone — firing an unavailable slot is a no-op, not a crash and not a silent partial load.
    func recall(_ index: Int) -> Preset? {
        guard isValid(index), isAvailable(index) else { return nil }
        return slots[index]
    }

    func clear(_ index: Int) {
        guard isValid(index) else { return }
        slots[index] = nil
        onChange?()
    }

    /// False for an empty slot and for one whose shader file is no longer on disk. The slot is
    /// deliberately NOT cleared in the second case: an unmounted drive comes back, and destroying
    /// the operator's bank over a bad mount is worse than a dark cell.
    func isAvailable(_ index: Int) -> Bool {
        guard isValid(index), let preset = slots[index] else { return false }
        return FileManager.default.fileExists(atPath: preset.shaderURL.path)
    }
}
