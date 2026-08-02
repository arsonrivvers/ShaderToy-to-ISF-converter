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
///
/// **A class, not a struct (final-review F1).** `load()` now records whether the stored bytes were
/// fully readable, and `save()` reads that flag to decide whether overwriting them is safe. The two
/// calls happen at opposite ends of `Instrument.init` — `load()` inline, `save()` from the
/// `slotBank.onChange` closure — and a struct captured by that closure would carry a COPY taken
/// before the flag was ever set, which is the one thing this fix must not do.
final class SlotBankStore {
    static let key = "ARShader.slotBank"

    private let defaults: KeyValueStoring

    /// True when the last `load()` found stored bytes it could not fully read: either the whole
    /// blob failed to decode, or at least one non-null element inside it did. `save()` refuses to
    /// write while this is set, so unreadable-but-present bytes are never overwritten by the next
    /// capture — the difference between "this build cannot read your bank" and "your bank is gone."
    ///
    /// Deliberately sticky for the life of the store (i.e. the life of the process): the operator's
    /// bytes stay on disk untouched until a build that can read them runs, or the operator clears
    /// the key. Persistence being off for the session is the lesser loss, and
    /// `lastFailureReasonForTesting` is the observable signal that it is off.
    private(set) var loadFailed = false

    /// Why the last `load()`/`save()` failed, or nil if neither did. Named for the
    /// `ThumbnailService.lastFailureReasonForTesting` convention already in this app: a diagnostic
    /// seam a test can assert on and a future UI task can surface, replacing the `assertionFailure`
    /// that used to TRAP a debug build on a merely-unencodable value.
    private(set) var lastFailureReasonForTesting: String?

    init(defaults: KeyValueStoring = UserDefaults.standard) { self.defaults = defaults }

    /// Swallows one unreadable slot instead of failing the whole bank decode. Same wrapper shape as
    /// `ParamSnapshot.FailableParamValue` (`ParamStore.swift`), which exists for exactly this reason
    /// one layer down, and the same motivation as `Arrangement`'s hand-written `init(from:)`
    /// (`SurfaceLayout.swift`): a schema addition to `Preset` — which `Preset`'s own doc comment
    /// says to expect — must cost at most the slots it actually breaks, never all forty.
    private struct FailablePreset: Codable {
        let value: Preset?
        init(from decoder: Decoder) throws { value = try? Preset(from: decoder) }
        func encode(to encoder: Encoder) throws { try value?.encode(to: encoder) }
    }

    /// Absent or wholly-unreadable bytes yield an empty bank; a single unreadable element yields an
    /// empty SLOT. A corrupt bank must never be able to stop the instrument launching — and, since
    /// F1, must never be silently overwritten either: anything lost here sets `loadFailed`, which
    /// takes `save()` out of service for the session.
    func load() -> [Preset?] {
        guard let data = defaults.data(forKey: Self.key) else { return Self.empty }
        guard let decoded = try? JSONDecoder().decode([FailablePreset?].self, from: data) else {
            loadFailed = true
            lastFailureReasonForTesting =
                "Stored slot bank could not be decoded — not overwriting it this session"
            return Self.empty
        }
        // `map`, not `compactMap`: an element that decoded to nothing must leave its slot EMPTY at
        // the same index, not shuffle every later look one position to the left.
        let slots = decoded.map { $0?.value }
        let lost = zip(decoded, slots).filter { $0.0 != nil && $0.1 == nil }.count
        if lost > 0 {
            loadFailed = true
            lastFailureReasonForTesting =
                "\(lost) stored slot(s) could not be decoded — not overwriting the bank this session"
        }
        return Self.normalised(slots)
    }

    func save(_ slots: [Preset?]) {
        guard !loadFailed else {
            // The whole point of F1: the next capture after a lossy load must not be what makes the
            // loss permanent. Non-fatal and non-trapping — the operator keeps working, the session
            // just does not persist.
            lastFailureReasonForTesting =
                "Refusing to overwrite a slot bank this build could not fully read"
            return
        }
        do {
            // Phase 3a's branch review found SurfaceLayoutStore swallowing exactly this: an
            // unencodable value ended persistence for the session with no symptom until the next
            // launch. Recorded rather than `assertionFailure`d (F1): a `ParamValue.float(.nan)` —
            // reachable from a malformed ISF header default — makes `JSONEncoder` throw, and
            // trapping a debug build over one bad param value is a worse answer than dropping it.
            let data = try JSONEncoder().encode(Self.sanitised(Self.normalised(slots)))
            defaults.set(data, forKey: Self.key)
            lastFailureReasonForTesting = nil
        } catch {
            lastFailureReasonForTesting = "Slot bank could not be encoded: \(error)"
        }
    }

    private static var empty: [Preset?] { Array(repeating: nil, count: SlotBank.slotCount) }

    /// Always exactly `slotCount` entries, whatever was on disk.
    private static func normalised(_ slots: [Preset?]) -> [Preset?] {
        var out = slots.prefix(SlotBank.slotCount).map { $0 }
        out.append(contentsOf: Array(repeating: nil, count: SlotBank.slotCount - out.count))
        return out
    }

    /// Drops non-finite param values before encoding. `JSONEncoder` THROWS on NaN or infinity by
    /// default, and one such value anywhere in one preset would otherwise end persistence for the
    /// whole bank. Dropped rather than round-tripped as a string: a dropped param falls back to the
    /// shader's own header default on recall, which is a sane look; a NaN replayed into a live
    /// uniform is not.
    private static func sanitised(_ slots: [Preset?]) -> [Preset?] {
        slots.map { preset in
            guard let preset else { return nil }
            let clean = preset.snapshot.params.compactMapValues(finite)
            guard clean.count != preset.snapshot.params.count else { return preset }
            return Preset(id: preset.id, name: preset.name, shaderURL: preset.shaderURL,
                          snapshot: ParamSnapshot(version: preset.snapshot.version, params: clean))
        }
    }

    private static func finite(_ value: ParamValue) -> ParamValue? {
        switch value {
        case .bool:                          return value
        case .float(let v), .long(let v):    return v.isFinite ? value : nil
        case .point2D(let a), .color(let a): return a.allSatisfy(\.isFinite) ? value : nil
        }
    }
}
