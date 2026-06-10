import Foundation

/// A built-in test-pattern source: an ISF generator bundled with the kit.
public struct TestPattern: Identifiable, Equatable, Sendable {
    public let id: String          // resource basename, e.g. "smpte_bars"
    public let name: String        // display name, e.g. "SMPTE Bars"
    public let sourceText: String  // the .fs contents

    public static func == (l: TestPattern, r: TestPattern) -> Bool { l.id == r.id }
}

public enum TestPatternCatalog {
    /// (resource basename, display name) in display order.
    private static let manifest: [(String, String)] = [
        ("smpte_bars", "SMPTE Bars"),
        ("grayscale_ramp", "Grayscale Ramp"),
        ("scrolling_checker", "Scrolling Checker"),
        ("crosshatch", "Crosshatch"),
        ("zone_plate", "Zone Plate"),
        ("hue_sweep", "Hue Sweep"),
        ("bouncing_box", "Bouncing Box"),
        ("solid_white", "Solid White"),
        ("solid_black", "Solid Black"),
        ("solid_gray50", "Solid 50% Gray"),
        ("solid_red", "Solid Red"),
        ("solid_green", "Solid Green"),
        ("solid_blue", "Solid Blue"),
    ]

    /// All patterns in display order. A pattern whose resource is missing is skipped.
    public static let all: [TestPattern] = manifest.compactMap { basename, name in
        guard let url = Bundle.module.url(forResource: basename, withExtension: "fs", subdirectory: "TestPatterns"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return TestPattern(id: basename, name: name, sourceText: text)
    }

    /// The reference / fallback pattern (used when a source is unavailable). SMPTE bars.
    public static var `default`: TestPattern {
        all.first { $0.id == "smpte_bars" } ?? all[0]
    }

    public static func pattern(id: String) -> TestPattern? { all.first { $0.id == id } }
}
