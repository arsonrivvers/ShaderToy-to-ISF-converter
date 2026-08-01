import CoreTransferable
import UniformTypeIdentifiers

/// What a drag is carrying, and where it is allowed to land.
///
/// No SwiftUI import: the acceptance rules are the never-overwrite invariant restated for a
/// gesture, and that invariant must be testable with no view and no GPU in play — the same
/// doctrine `SurfaceLayout` and `SlotBank` follow.
struct ShaderDrag: Codable, Transferable, Sendable {
    enum Source: Codable, Equatable, Sendable {
        case library
        case deck(DeckID)
        /// Never a legal source this phase. Present so `accepts` can REJECT it explicitly rather
        /// than by omission — a rule you can read is a rule someone can find later.
        case slot
    }

    enum Destination: Equatable, Sendable {
        case slot
        case deck(DeckID)
        case deckFX(DeckID)
        case masterFX
    }

    let source: Source
    let url: URL
    /// The dialled values. Present only on a deck capture — a library shader has none yet.
    let snapshot: ParamSnapshot?

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .arshaderDrag)
    }

    /// The single acceptance rule. Every drop target asks this and nothing else, so there is one
    /// place the never-overwrite invariant lives. Forwards to the `Source`-only overload below —
    /// the actual decision lives there so a caller that does not yet HAVE a resolved `ShaderDrag`
    /// (SwiftUI's `isTargeted` callback receives only a `Bool`, never the hovering item — see
    /// `FXChainView`'s and `MonitorTile`'s doc comments, fix-round-1 F2) can still ask the real
    /// rule instead of re-deriving it (fix-round-1 F1: an inline `!isSlotFilled || option`
    /// re-implementation at an `isTargeted` closure is exactly how this invariant drifted from
    /// what `accepts` actually decides).
    static func accepts(_ drag: ShaderDrag, on destination: Destination,
                        isSlotFilled: Bool, withOption option: Bool) -> Bool {
        accepts(source: drag.source, on: destination, isSlotFilled: isSlotFilled,
               withOption: option)
    }

    /// The actual decision. Source-only, not the whole payload, because that is all the rule ever
    /// looks at — `url`/`snapshot` never influence acceptance — and it lets a caller with no
    /// resolved drag yet (an `isTargeted` highlight) still go through this ONE function rather
    /// than hand-rolling the predicate.
    static func accepts(source: Source, on destination: Destination,
                        isSlotFilled: Bool, withOption option: Bool) -> Bool {
        switch source {
        case .slot:
            return false
        case .deck:
            guard case .slot = destination else { return false }
            return !isSlotFilled || option
        case .library:
            guard case .slot = destination else { return true }
            return !isSlotFilled || option
        }
    }
}

extension UTType {
    static let arshaderDrag = UTType(exportedAs: "com.arshader.shader-drag")
}
