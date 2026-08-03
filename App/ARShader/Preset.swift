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

    /// `name` with the parts every entry shares removed — what a slot cell shows.
    ///
    /// A slot cell is ~96–160pt wide and truncates in the MIDDLE, on the reasoning that long
    /// `AR_Genuary` names differ at the end. Against the real corpus that reasoning inverts: nine
    /// consecutive `AR_Beautiful_Kaleido…` entries differ in the middle, and the 2026-08-03 review
    /// found two slots rendering byte-identical labels (`AR_Beautif…Alt_v03.fs`). Middle truncation
    /// deletes exactly the discriminating token.
    ///
    /// Dropping a shared `AR_` prefix and the `.fs` suffix buys back ~6 characters at zero layout
    /// cost, which is what makes raising the cell's type from 9pt to 11pt free rather than a trade
    /// of legibility for truncation. Anything not carrying the prefix keeps its whole name.
    var shortLabel: String {
        var label = name
        if label.hasSuffix(".fs") { label.removeLast(3) }
        if label.hasPrefix("AR_") { label.removeFirst(3) }
        // A name that was ONLY the shared parts would leave nothing to read; keep the original.
        return label.isEmpty ? name : label
    }
}
