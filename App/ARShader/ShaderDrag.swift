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
    /// place the never-overwrite invariant lives.
    static func accepts(_ drag: ShaderDrag, on destination: Destination,
                        isSlotFilled: Bool, withOption option: Bool) -> Bool {
        switch drag.source {
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
