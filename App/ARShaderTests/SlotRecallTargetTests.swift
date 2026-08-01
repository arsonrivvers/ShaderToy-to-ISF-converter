import XCTest
@testable import ARShader

@MainActor
final class SlotRecallTargetTests: XCTestCase {
    /// The type-level constraint, asserted as a type-level fact: recall takes a DeckID, and there
    /// is no LibraryTarget case it can be handed. Phase 3b's hazard was that RECALL TO could hold
    /// `.masterFX`, so every slot click appended an unbounded FX stage to the master chain.
    func testRecallTargetsAreDecksOnly() {
        let targets = SlotBankStripView.recallTargets
        XCTAssertEqual(targets, DeckID.allCases)
        XCTAssertEqual(targets.count, 2, "A slot loads a deck. There is no third answer.")
    }

    /// Falsifiable companion: if someone widens the picker back to LibraryTarget, this catches it.
    func testNoRecallTargetIsAnFXChain() {
        for deck in SlotBankStripView.recallTargets {
            let asLibraryTarget = LibraryTarget.deck(deck)
            if case .deck = asLibraryTarget { continue }
            XCTFail("\(deck) mapped to a non-deck LibraryTarget")
        }
    }
}
