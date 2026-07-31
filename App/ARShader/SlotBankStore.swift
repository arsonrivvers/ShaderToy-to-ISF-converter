import Foundation

/// Reads and writes the slot bank as one JSON blob, shaped exactly like `SurfaceLayoutStore`.
///
/// One key rather than one per slot: the slots are restored together or the restore is wrong, and
/// per-slot keys can drift out of sync across app versions.
struct SlotBankStore {
    static let key = "ARShader.slotBank"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    /// Any failure — absent, truncated, from a future schema, the wrong length — yields an empty
    /// bank. A corrupt bank must never be able to stop the instrument launching.
    func load() -> [Preset?] {
        guard let data = defaults.data(forKey: Self.key),
              let decoded = try? JSONDecoder().decode([Preset?].self, from: data)
        else { return Self.empty }
        return Self.normalised(decoded)
    }

    func save(_ slots: [Preset?]) {
        guard let data = try? JSONEncoder().encode(Self.normalised(slots)) else {
            // Phase 3a's branch review found SurfaceLayoutStore swallowing exactly this: an
            // unencodable value ended persistence for the session with no symptom until the next
            // launch. Loud in debug, still non-fatal in release.
            assertionFailure("Slot bank could not be encoded — persistence is now silently off")
            return
        }
        defaults.set(data, forKey: Self.key)
    }

    private static var empty: [Preset?] { Array(repeating: nil, count: SlotBank.slotCount) }

    /// Always exactly `slotCount` entries, whatever was on disk.
    private static func normalised(_ slots: [Preset?]) -> [Preset?] {
        var out = slots.prefix(SlotBank.slotCount).map { $0 }
        out.append(contentsOf: Array(repeating: nil, count: SlotBank.slotCount - out.count))
        return out
    }
}
