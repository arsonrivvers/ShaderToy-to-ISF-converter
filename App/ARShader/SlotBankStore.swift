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
/// **A class, not a struct (final-review F1).** `load()` records whether the stored bytes were fully
/// readable and, if not, backs the raw bytes up under a dated key before returning (fix round 2,
/// item 2 — see `loadFailed`'s doc comment for why `save()` no longer refuses to write). The two
/// calls happen at opposite ends of `Instrument.init` — `load()` inline, `save()` from the
/// `slotBank.onChange` closure — and a struct captured by that closure would carry a COPY taken
/// before the flag was ever set, which is the one thing this fix must not do.
final class SlotBankStore {
    static let key = "ARShader.slotBank"

    private let defaults: KeyValueStoring

    /// True when the last `load()` found stored bytes it could not fully read: either the whole
    /// blob failed to decode, or at least one non-null element inside it did. Purely informational
    /// since fix round 2 (item 2) — it no longer gates `save()`.
    ///
    /// **History:** the original F1 fix left this sticky for the life of the process and had
    /// `save()` refuse to write while it was set, so unreadable-but-present bytes could never be
    /// overwritten. That traded one bug for a worse one: the exact schema-migration scenario F1 was
    /// built to survive (a future non-optional `Preset` property) would fail every stored element,
    /// set this permanently, and lock the operator out of persistence for good — every capture made
    /// for the rest of that install, forever, silently discarded on relaunch, recoverable only via
    /// `defaults delete` in Terminal. See `backUpUnreadableBytes(_:reason:)` for the fix.
    private(set) var loadFailed = false

    /// Why the last `load()`/`save()` failed, or nil if neither did. Named for the
    /// `ThumbnailService.lastFailureReasonForTesting` convention already in this app: a diagnostic
    /// seam a test can assert on and a future UI task can surface, replacing the `assertionFailure`
    /// that used to TRAP a debug build on a merely-unencodable value.
    private(set) var lastFailureReasonForTesting: String?

    /// The `UserDefaults`/`KeyValueStoring` key the most recent unreadable-bytes backup was written
    /// under, or nil if `load()` has never had to back anything up. Unlike
    /// `lastFailureReasonForTesting` (which `save()` clears on its own success), this is NOT
    /// cleared — it is the only handle a test (or an operator reading `defaults read`) has on WHICH
    /// key the original bytes now live under, since `unreadableBackupKey()` is dated.
    private(set) var lastUnreadableBackupKeyForTesting: String?

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
    /// F1, must never be silently DISCARDED either: anything lost here is backed up first (see
    /// `backUpUnreadableBytes(_:reason:)`), so persistence can resume immediately rather than being
    /// refused for the rest of the process.
    func load() -> [Preset?] {
        guard let data = defaults.data(forKey: Self.key) else { return Self.empty }
        guard let decoded = try? JSONDecoder().decode([FailablePreset?].self, from: data) else {
            backUpUnreadableBytes(data, reason: "Stored slot bank could not be decoded")
            return Self.empty
        }
        // `map`, not `compactMap`: an element that decoded to nothing must leave its slot EMPTY at
        // the same index, not shuffle every later look one position to the left.
        let slots = decoded.map { $0?.value }
        let lost = zip(decoded, slots).filter { $0.0 != nil && $0.1 == nil }.count
        if lost > 0 {
            backUpUnreadableBytes(data, reason: "\(lost) stored slot(s) could not be decoded")
        }
        return Self.normalised(slots)
    }

    /// The dated key `load()` backs up unreadable bytes under. Dated rather than per-failure-unique
    /// so repeated failures on the same day (e.g. relaunching against the same corrupt bytes)
    /// collapse into one backup instead of littering a new key on every launch.
    static func unreadableBackupKey(on date: Date = Date()) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        return "\(key)-unreadable-\(formatter.string(from: date))"
    }

    /// Fix round 2, item 2. The original fix here (F1) refused every future `save()` once
    /// `loadFailed` was set, with no way to clear it — a future `Preset` schema change (the exact
    /// trigger F1 was written for) would fail every stored element and lock the operator out of
    /// persistence permanently and silently. Instead: preserve the RAW unreadable bytes once, under
    /// a dated key, then let `save()` proceed normally. Nothing is lost — the original bytes survive
    /// under the backup key for manual recovery — and nothing is silently refused forever.
    private func backUpUnreadableBytes(_ data: Data, reason: String) {
        loadFailed = true
        let backupKey = Self.unreadableBackupKey()
        defaults.set(data, forKey: backupKey)
        lastUnreadableBackupKeyForTesting = backupKey
        lastFailureReasonForTesting =
            "\(reason) — original bytes preserved under '\(backupKey)'; persistence continues normally"
    }

    func save(_ slots: [Preset?]) {
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
