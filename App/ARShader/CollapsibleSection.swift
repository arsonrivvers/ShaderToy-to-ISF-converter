import SwiftUI

/// A titled section that collapses to a single header row.
///
/// The header ALWAYS carries a summary — `FX 3`, `PARAMETERS 12`, `SOURCES cam→in0`. Collapsing
/// hides detail; it must never hide the fact that detail exists. The failure mode of a collapsible
/// surface is a control the operator cannot find, and a bare header with no count is that failure
/// mode by design. (Phase 2 shipped a disclosure triangle that opened onto nothing; this is the
/// same class caught at the component.)
///
/// The whole header is the hit target, not just the chevron — a 12pt glyph is a poor thing to aim
/// at mid-set.
struct CollapsibleSection<Content: View>: View {
    let title: String
    /// Shown on the header in BOTH states. Empty string is allowed but discouraged.
    let summary: String
    let key: SectionKey
    @ObservedObject var layout: SurfaceLayout
    @ViewBuilder var content: () -> Content

    private var isExpanded: Bool { layout.isExpanded(key) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button { layout.toggle(key) } label: {
                HStack(spacing: 4) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9))
                        .frame(width: 10)
                    Text(title)
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                    Spacer()
                    Text(summary)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                }
                // The full-row hit target is a property of this component and must not depend on
                // a greedy sibling in the consumer. Expand to max width regardless of content.
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(isExpanded ? "Collapse \(title)" : "Expand \(title) — \(summary)")

            if isExpanded { content() }
        }
    }
}
