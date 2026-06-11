import Foundation

/// Distinct "creative vectors" appended per child so a batch from the same parents diverges
/// instead of producing N lookalikes.
enum RemixDirectives {
    static let catalog: [String] = [
        "lean chaotic and high-energy",
        "lean minimal and restrained",
        "emphasize bold color and palette shifts",
        "emphasize motion and flow over time",
        "emphasize geometric structure and symmetry",
        "introduce organic, noise-driven texture",
        "push contrast and negative space",
        "blend the two parents evenly and faithfully",
    ]
    /// `seed` rotates the starting point so successive rounds don't always lead with the same vector.
    static func pick(_ n: Int, seed: Int) -> [String] {
        guard n > 0, !catalog.isEmpty else { return [] }
        return (0..<n).map { catalog[(seed + $0) % catalog.count] }
    }
}
