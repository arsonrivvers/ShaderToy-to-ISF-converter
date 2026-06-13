import Foundation

enum RemixTrait: String, CaseIterable, Codable { case structure, color, motion, texture }
enum RemixTraitSource: String, Codable { case auto, a, b }

/// The four crossover knobs as a pure value type. Turns into prompt fragments via `promptLines`.
/// `traitSources` is keyed by trait rawValue (Codable-safe; enum-keyed dicts encode badly).
struct RemixCrossoverSettings: Codable, Equatable {
    var balance: Double = 0.5                                   // 0 = all A, 1 = all B
    var variation: Double = 0.4                                 // 0 = faithful, 1 = wild
    var traitSources: [String: RemixTraitSource] = [:]          // trait.rawValue -> source (absent ⇒ auto)
    var enabledDirectives: Set<String> = Set(RemixDirectives.catalog)

    func source(for trait: RemixTrait) -> RemixTraitSource { traitSources[trait.rawValue] ?? .auto }
    mutating func setSource(_ s: RemixTraitSource, for trait: RemixTrait) {
        if s == .auto { traitSources[trait.rawValue] = nil } else { traitSources[trait.rawValue] = s }
    }

    /// Prompt fragments these settings contribute. Crossover-only lines (balance, routing) are
    /// omitted in `.mutate`. Stable order: variation, balance, then routing in RemixTrait order.
    func promptLines(mode: RemixMode) -> [String] {
        var out: [String] = [variationLine]
        guard mode == .crossover else { return out }
        out.append(balanceLine)
        for trait in RemixTrait.allCases {
            let s = source(for: trait)
            guard s != .auto else { continue }
            out.append("Take the \(trait.rawValue) primarily from Parent \(s == .a ? "A" : "B").")
        }
        return out
    }

    private var variationLine: String {
        switch variation {
        case ..<0.25: return "Stay faithful — a recognizable hybrid that clearly reads as both parents."
        case ..<0.5:  return "Balance fidelity and invention."
        case ..<0.75: return "Be adventurous — take real creative liberties while keeping both parents' DNA."
        default:      return "Wild reinterpretation — treat the parents as loose inspiration, not templates."
        }
    }

    private var balanceLine: String {
        let pct = Int((balance * 100).rounded())
        if pct == 50 { return "Weight both parents equally." }
        return "For any aspect not pinned below, weight the blend roughly \(pct)% toward Parent B "
            + "and \(100 - pct)% toward Parent A."
    }

    /// One-line UI summary, e.g. "70% B · adventurous · 1 trait pinned · 2 vectors off".
    var summary: String {
        var parts: [String] = []
        let pct = Int((balance * 100).rounded())
        parts.append(pct == 50 ? "balanced" : (pct > 50 ? "\(pct)% B" : "\(100 - pct)% A"))
        switch variation {
        case ..<0.25: parts.append("faithful")
        case ..<0.5:  parts.append("balanced mix")
        case ..<0.75: parts.append("adventurous")
        default:      parts.append("wild")
        }
        let pinned = RemixTrait.allCases.filter { source(for: $0) != .auto }.count
        if pinned > 0 { parts.append("\(pinned) trait\(pinned == 1 ? "" : "s") pinned") }
        let off = RemixDirectives.catalog.count - enabledDirectives.count
        if off > 0 { parts.append("\(off) vector\(off == 1 ? "" : "s") off") }
        return parts.joined(separator: " · ")
    }
}
