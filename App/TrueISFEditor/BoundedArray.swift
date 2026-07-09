import Foundation

extension Array {
    /// Append keeping at most `max` elements — drops from the FRONT (ring-buffer semantics for
    /// transcripts and logs). One shared implementation instead of five hand-rolled copies.
    mutating func appendBounded(_ element: Element, max: Int) {
        append(element)
        if count > max { removeFirst(count - max) }
    }
}
