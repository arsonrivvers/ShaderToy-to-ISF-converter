import Foundation

/// The two operations `SlotBankStore` actually needs. Exists so tests — and `Instrument` under the
/// XCTest harness — can back the store with memory instead of a real `UserDefaults` suite:
/// `UserDefaults(suiteName:)` materialises a real cfprefsd-backed file in
/// `~/Library/Preferences` the moment anything writes to it, and those files never clean
/// themselves up (coordinator fix round 2: 63 `SlotBankStoreTests-<uuid>.plist` plus 5
/// `ARShader.Instrument.testHarness-<uuid>.plist` had accumulated on the operator's real machine
/// from exactly this). `UserDefaults`'s own `data(forKey:)`/`set(_:forKey:)` signatures need no
/// adjustment to conform — both already use `forKey` as their external label.
protocol KeyValueStoring: AnyObject {
    func data(forKey key: String) -> Data?
    func set(_ value: Any?, forKey key: String)
}

extension UserDefaults: KeyValueStoring {}

/// In-memory `KeyValueStoring` conformer, backing `SlotBankStore` in tests and — under
/// `TestHarness.isActive` — in `Instrument.init()`, so neither ever touches a real preferences
/// file. Deliberately lives in the APP target (not `ARShaderTests`), even though only tests and
/// the harness gate ever construct one: `Instrument.init()` references this type at COMPILE time
/// regardless of `TestHarness.isActive`'s runtime value, and app code cannot import a test target.
/// Same reasoning as `TestHarness` itself (`App/ISFRuntime/TestHarness.swift`). Internal (default)
/// visibility, so `@testable import ARShader` exposes it to `SlotBankStoreTests` and
/// `InstrumentLoadTests` without either redefining it.
final class InMemoryKeyValueStore: KeyValueStoring {
    private var storage: [String: Data] = [:]

    func data(forKey key: String) -> Data? { storage[key] }

    func set(_ value: Any?, forKey key: String) { storage[key] = value as? Data }
}

/// Reads and writes the slot bank as one JSON blob, shaped exactly like `SurfaceLayoutStore`.
///
/// One key rather than one per slot: the slots are restored together or the restore is wrong, and
/// per-slot keys can drift out of sync across app versions.
struct SlotBankStore {
    static let key = "ARShader.slotBank"

    private let defaults: KeyValueStoring

    init(defaults: KeyValueStoring = UserDefaults.standard) { self.defaults = defaults }

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
