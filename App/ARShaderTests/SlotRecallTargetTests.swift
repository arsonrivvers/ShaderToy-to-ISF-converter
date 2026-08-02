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

    // `testNoRecallTargetIsAnFXChain` was DELETED here (final-review F10). It could not fail:
    // `LibraryTarget.deck(deck)` is `.deck` by construction, so `if case .deck` matched for every
    // possible input and the `XCTFail` was unreachable. It was the sixth appearance of this phase's
    // tests-that-cannot-fail class and the last unmanaged one at HEAD. The ledger had recorded it as
    // "verbatim from my brief, so spec-compliant" — spec-compliance is not test value.
    //
    // Not replaced: the falsifiable content is already in `testRecallTargetsAreDecksOnly`'s
    // `count == 2` (which breaks if the picker is widened to `LibraryTarget` or `DeckID` gains a
    // case), and the review's suggested replacement — extracting
    // `recallLibraryTarget(for: DeckID)` and pinning it — would pin a mapping with exactly one
    // production call site inside `recall(_:)`, which is a re-derivation of that line rather than a
    // gate on it.
}
