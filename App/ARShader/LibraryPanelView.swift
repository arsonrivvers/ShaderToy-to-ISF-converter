import SwiftUI

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

/// Browse the corpus and load a shader onto a deck.
struct LibraryPanelView: View {
    let instrument: Instrument
    @Binding var targetDeck: DeckID
    @StateObject private var selection = LibrarySelection()
    @ObservedObject private var library: LibraryModel

    init(instrument: Instrument, targetDeck: Binding<DeckID>) {
        self.instrument = instrument
        self._targetDeck = targetDeck
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

            Picker("Load onto", selection: $targetDeck) {
                ForEach(DeckID.allCases) { Text("Deck \($0.displayName)").tag($0) }
            }
            .pickerStyle(.segmented)

            List(entries) { entry in
                Button {
                    instrument.deck(targetDeck).load(url: entry.url)
                } label: {
                    Text(entry.name)
                        .font(.system(size: 12, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)   // long AR_Genuary names differ at the END
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(entry.name)
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
