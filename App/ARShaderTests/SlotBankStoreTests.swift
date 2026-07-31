import XCTest
@testable import ARShader

@MainActor
final class SlotBankStoreTests: XCTestCase {

    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        // A private suite so tests never read or clobber the real bank.
        defaults = UserDefaults(suiteName: "SlotBankStoreTests-\(UUID().uuidString)")
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

    func testAStoredBankOfTheWrongLengthIsNormalisedToSlotCount() throws {
        // A bank saved by a future build with a bigger grid, opened by this one.
        let tooMany = [Preset?](repeating: preset(0.5), count: SlotBank.slotCount + 4)
        defaults.set(try JSONEncoder().encode(tooMany), forKey: SlotBankStore.key)
        XCTAssertEqual(SlotBankStore(defaults: defaults).load().count, SlotBank.slotCount,
                       "Loading must always yield exactly slotCount entries, whatever is on disk")
    }
}
