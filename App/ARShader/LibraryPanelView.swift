import SwiftUI

/// Where a clicked library shader goes. Clicking loads onto a deck, or APPENDS a stage to a chain.
enum LibraryTarget: Hashable, CaseIterable, Identifiable {
    case deck(DeckID)
    case deckFX(DeckID)
    case masterFX

    /// Hand-written because the associated values stop `CaseIterable` synthesising it. The order
    /// is the picker's order: each deck sits beside its own chain.
    static var allCases: [LibraryTarget] {
        [.deck(.one), .deckFX(.one), .deck(.two), .deckFX(.two), .masterFX]
    }

    var id: Self { self }

    /// Short enough for a five-way segmented picker in a 300pt panel.
    var shortLabel: String {
        switch self {
        case .deck(let d):   return d.displayName
        case .deckFX(let d): return "\(d.displayName) FX"
        case .masterFX:      return "MST FX"
        }
    }
}

/// Search and sort state for the library browser. Separate from `LibraryModel` (which owns the
/// folders and their entries) so the view can filter without the model recooking.
@MainActor
final class LibrarySelection: ObservableObject {
    @Published var query: String = ""
    @Published var sort: LibrarySort = .name

    func results(in model: LibraryModel) -> [LibraryEntry] {
        model.filtered(query: query, sort: sort)
    }
}

/// Browse the corpus, click a shader to load it onto deck A, or drag it onto any deck, FX chain,
/// or slot.
struct LibraryPanelView: View {
    let instrument: Instrument
    @StateObject private var selection = LibrarySelection()
    @ObservedObject private var library: LibraryModel

    init(instrument: Instrument) {
        self.instrument = instrument
        self.library = instrument.library
    }

    private var entries: [LibraryEntry] { selection.results(in: library) }

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                TextField("Search", text: $selection.query)
                    .textFieldStyle(.roundedBorder)
                Picker("", selection: $selection.sort) {
                    ForEach(LibrarySort.allCases) { Text($0.rawValue).tag($0) }
                }
                .labelsHidden()
                .frame(width: 150)
            }

            // Fix-round-1, F3 (operator ruling — overrides task 5's "removes click-to-load
            // entirely"): a plain `Text` dropped the button trait, the activate action, and —
            // with the picker also gone — every keyboard/VoiceOver path to load a shader anywhere
            // in the app. Drag and tap coexist on `.draggable`, same as `SlotCell`'s Button below
            // does with its own drop target. The tap action loads onto deck A specifically — the
            // one target that can never overwrite a saved look, and `InstrumentView`'s historical
            // default for the picker this task removed. Not reconfigurable: reintroducing a
            // target picker is exactly what task 5 removed, and the ruling did not restore it.
            List(entries) { entry in
                Button {
                    instrument.load(entry.url, onto: .deck(.one))
                } label: {
                    Text(entry.name)
                        .font(.system(size: 12, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)   // long AR_Genuary names differ at the END
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .draggable(ShaderDrag(source: .library, url: entry.url, snapshot: nil))
                // Both halves, not one replacing the other (F4): names are EXPECTED to
                // middle-truncate (see the comment above), so the full name is the only way to
                // read a name the row itself cut off, and the drag hint is the only place the
                // gesture is documented at all.
                .help("\(entry.name) — click to load onto deck A, or drag onto a deck, an FX "
                      + "chain, or a slot")
            }
            .listStyle(.inset)

            // Honest absence: while the scan is in flight the count is unknown, so say so rather
            // than print "0 shaders" — which reads as an empty corpus, not a pending one.
            HStack(spacing: 5) {
                if library.isScanning {
                    ProgressView().controlSize(.small).scaleEffect(0.6)
                    Text("Scanning library…")
                } else {
                    Text("\(entries.count) shaders")
                }
            }
            .font(.system(size: 11)).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(8)
    }
}
