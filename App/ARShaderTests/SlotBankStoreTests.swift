import XCTest
@testable import ARShader

@MainActor
final class SlotBankStoreTests: XCTestCase {

    private var defaults: InMemoryKeyValueStore!

    override func setUp() {
        super.setUp()
        // In-memory, not a `UserDefaults(suiteName:)` private suite (coordinator fix round 2): a
        // suite still materialises a real file in ~/Library/Preferences the moment anything writes
        // to it, and those files never clean themselves up — this doctrine's OWN prior form left
        // 63 of them behind. `InMemoryKeyValueStore` isolates the same way with nothing on disk.
        defaults = InMemoryKeyValueStore()
    }

    private func preset(_ speed: Double) -> Preset {
        Preset.capturing(url: URL(fileURLWithPath: "/tmp/a.fs"),
                         snapshot: ParamSnapshot(params: ["speed": .float(speed)]))
    }

    func testAnEmptyStoreLoadsAnEmptyBankRatherThanFailing() {
        let loaded = SlotBankStore(defaults: defaults).load()
        XCTAssertEqual(loaded.count, SlotBank.slotCount)
        XCTAssertTrue(loaded.allSatisfy { $0 == nil })
    }

    func testAPopulatedBankRoundTripsWithItsValuesAndPositions() throws {
        let store = SlotBankStore(defaults: defaults)
        var slots = [Preset?](repeating: nil, count: SlotBank.slotCount)
        slots[0] = preset(0.1)
        slots[7] = preset(0.9)
        store.save(slots)

        let loaded = store.load()
        XCTAssertEqual(loaded[0]?.snapshot.params["speed"], .float(0.1))
        XCTAssertEqual(loaded[7]?.snapshot.params["speed"], .float(0.9))
        XCTAssertNil(loaded[3], "Empty slots stay empty and positions are preserved")
    }

    func testCorruptStoredDataLoadsAnEmptyBankRatherThanThrowing() {
        defaults.set(Data("not json".utf8), forKey: SlotBankStore.key)
        let loaded = SlotBankStore(defaults: defaults).load()
        XCTAssertEqual(loaded.count, SlotBank.slotCount)
        XCTAssertTrue(loaded.allSatisfy { $0 == nil },
                      "A corrupt bank must never stop the instrument launching")
    }

    /// F1, the headline: `decode([Preset?].self)` was all-or-nothing across the array, so ONE
    /// unreadable element emptied the whole bank. The trigger is not exotic — `Preset`'s own doc
    /// comment says it expects to grow a property, and every previously-saved element fails to
    /// decode the moment it does. Same fix shape `ParamSnapshot.FailableParamValue` already uses
    /// one layer down.
    func testOneUnreadableSlotCostsOneSlotAndNotTheWholeBank() throws {
        // Hand-built JSON rather than a re-encoded model: a future-schema element is exactly what
        // this must survive, and only raw JSON can express one.
        let good = try JSONEncoder().encode(preset(0.4))
        let json = "[\(String(data: good, encoding: .utf8)!),{\"nonsense\":true},null,"
            + "\(String(data: good, encoding: .utf8)!)]"
        defaults.set(Data(json.utf8), forKey: SlotBankStore.key)

        let loaded = SlotBankStore(defaults: defaults).load()
        XCTAssertEqual(loaded.count, SlotBank.slotCount)
        XCTAssertEqual(loaded[0]?.snapshot.params["speed"], .float(0.4),
                       "the readable slot before the bad one must survive")
        XCTAssertNil(loaded[1], "the unreadable slot — and only it — is lost")
        XCTAssertEqual(loaded[3]?.snapshot.params["speed"], .float(0.4),
                       "a readable slot AFTER the bad one must survive too, at its own index")
    }

    /// The other half of F1, and the one that makes the loss permanent: after a lossy load, the
    /// very next capture used to `save()` over the still-present-but-unreadable bytes.
    func testALossyLoadTakesSaveOutOfServiceRatherThanOverwritingTheStoredBytes() throws {
        let stored = Data("[{\"nonsense\":true}]".utf8)
        defaults.set(stored, forKey: SlotBankStore.key)
        let store = SlotBankStore(defaults: defaults)
        _ = store.load()
        XCTAssertTrue(store.loadFailed)

        var slots = [Preset?](repeating: nil, count: SlotBank.slotCount)
        slots[0] = preset(0.9)
        store.save(slots)

        XCTAssertEqual(defaults.data(forKey: SlotBankStore.key), stored,
                       "A bank this build could not read must survive the next capture untouched — "
                       + "'we cannot read it' must never become 'it is gone'")
        XCTAssertNotNil(store.lastFailureReasonForTesting,
                        "and the refusal has to be observable, not silent")
    }

    /// Wholly-undecodable bytes are the same hazard as a partly-undecodable array, and were already
    /// returning an empty bank before this fix — what they did NOT do was stop the overwrite.
    func testWhollyCorruptStoredDataAlsoTakesSaveOutOfService() {
        let stored = Data("not json".utf8)
        defaults.set(stored, forKey: SlotBankStore.key)
        let store = SlotBankStore(defaults: defaults)
        _ = store.load()
        store.save([preset(0.1)])
        XCTAssertEqual(defaults.data(forKey: SlotBankStore.key), stored)
    }

    /// An EMPTY store is not a failed one — persistence must work normally on a first launch.
    func testAFirstLaunchWithNothingStoredStillPersists() {
        let store = SlotBankStore(defaults: defaults)
        XCTAssertTrue(store.load().allSatisfy { $0 == nil })
        XCTAssertFalse(store.loadFailed)
        store.save([preset(0.2)])
        XCTAssertNotNil(defaults.data(forKey: SlotBankStore.key),
                        "refusing to save must be reserved for a bank we actually failed to read")
    }

    /// F1, folded-in secondary: `JSONEncoder` THROWS on a non-finite Double, and the old handler was
    /// `assertionFailure` — so one NaN param (reachable from a malformed ISF header default) both
    /// TRAPPED a debug build and, in release, ended persistence for the session with no symptom.
    func testANonFiniteParamValueCostsThatParamAndNotThePersistenceOfTheBank() throws {
        let store = SlotBankStore(defaults: defaults)
        let nasty = Preset.capturing(url: URL(fileURLWithPath: "/tmp/a.fs"),
                                     snapshot: ParamSnapshot(params: ["speed": .float(.nan),
                                                                      "gain": .float(0.5)]))
        store.save([nasty])

        let loaded = store.load()
        XCTAssertEqual(loaded[0]?.snapshot.params["gain"], .float(0.5),
                       "the whole bank must still persist — one bad value is not a reason to stop "
                       + "saving the operator's looks")
        XCTAssertNil(loaded[0]?.snapshot.params["speed"],
                     "the non-finite value itself is dropped, so recall falls back to the shader's "
                     + "own header default rather than replaying NaN into a live uniform")
        XCTAssertNil(store.lastFailureReasonForTesting)
    }

    func testAStoredBankOfTheWrongLengthIsNormalisedToSlotCount() throws {
        // A bank saved by a future build with a bigger grid, opened by this one.
        let tooMany = [Preset?](repeating: preset(0.5), count: SlotBank.slotCount + 4)
        defaults.set(try JSONEncoder().encode(tooMany), forKey: SlotBankStore.key)
        XCTAssertEqual(SlotBankStore(defaults: defaults).load().count, SlotBank.slotCount,
                       "Loading must always yield exactly slotCount entries, whatever is on disk")
    }
}
