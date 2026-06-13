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
    /// `from` restricts the draw to an allowlist (the user's enabled directive pool); an empty pool
    /// falls back to the full catalog so we never produce zero directives.
    static func pick(_ n: Int, seed: Int, from pool: [String] = catalog) -> [String] {
        let source = pool.isEmpty ? catalog : pool
        guard n > 0, !source.isEmpty else { return [] }
        return (0..<n).map { source[(seed + $0) % source.count] }
    }
}
