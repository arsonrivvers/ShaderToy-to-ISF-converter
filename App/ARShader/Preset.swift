import Foundation

/// A shader together with the parameter values that were dialled when it was captured.
///
/// The unit a slot holds, and — once phase 3c adds naming and browsing, and a later phase adds
/// randomisation — the unit those operate on too. `ParamSnapshot` does the heavy lifting: it is
/// already `Codable`, already survives one corrupt entry without failing the whole decode, and
/// `ParamStore.applySnapshot` already validate-and-clamps it against the LIVE header range, so a
/// preset captured under an older, wider range clamps in rather than replaying out of range.
struct Preset: Codable, Equatable, Identifiable {
    let id: UUID
    /// 3b derives this from the filename and nothing edits it. Stored anyway: adding a property to
    /// a persisted Codable type later is a migration, and adding it now is free.
    var name: String
    let shaderURL: URL
    let snapshot: ParamSnapshot

    /// Capture always mints a NEW identity. Two captures of the same shader are two presets that
    /// happen to share a URL, not one preset in two slots — otherwise editing one would silently
    /// edit the other.
    static func capturing(url: URL, snapshot: ParamSnapshot) -> Preset {
        Preset(id: UUID(), name: url.lastPathComponent, shaderURL: url, snapshot: snapshot)
    }
}
