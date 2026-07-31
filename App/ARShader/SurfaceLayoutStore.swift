import Foundation

/// Reads and writes the surface `Arrangement` as one JSON blob.
///
/// One key, not N `@AppStorage` keys: the flags are restored together or the restore is wrong, and
/// separate keys can drift out of sync with each other across app versions.
struct SurfaceLayoutStore {
    static let key = "ARShader.surfaceArrangement"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    /// Any failure — absent, truncated, from a future schema — yields the default arrangement.
    /// A corrupt layout must never be able to stop the instrument launching.
    func load() -> Arrangement {
        guard let data = defaults.data(forKey: Self.key),
              let decoded = try? JSONDecoder().decode(Arrangement.self, from: data)
        else { return .default }
        return decoded
    }

    func save(_ arrangement: Arrangement) {
        guard let data = try? JSONEncoder().encode(arrangement) else { return }
        defaults.set(data, forKey: Self.key)
    }
}
