import AppKit      // NSImage — decoding the hover-preview PNG, matching SlotBankStripView's pattern
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

    /// The row the pointer is over right now, or `nil` once it has left the list entirely. Drives
    /// `.task(id:)` below — every change (including a swap directly from one row to another)
    /// starts a fresh `.interactive` request, which `ThumbnailService` itself supersedes any
    /// request still in flight for (see the service's `Priority.interactive` doc comment).
    @State private var hoveredURL: URL?
    /// The still shown in the foot well. Deliberately NOT cleared when `hoveredURL` goes `nil` on
    /// list-exit (see the list's `.onHover` below) — the last resolved still stays put rather than
    /// flashing blank every time the pointer leaves the rows for the search field, the sort
    /// picker, or the well itself.
    @State private var hoverPreview: Image?

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
                // Task 7: a THIRD gesture on a row that already carries a click (the Button
                // action) and a drag (`.draggable`). `.onHover` is a hover-tracking area, not a
                // click/drag gesture recognizer, so it does not compete with either — verified by
                // running the existing drag-and-drop and click-to-load test coverage unchanged
                // (ShaderDragTests, LibraryPanelTests) after adding this, plus a manual on-device
                // check that click-to-load and drag-to-slot both still work with the hover well
                // live (see task-7-report.md). Only reacts to hover-IN: hover-OUT of a single row
                // is deliberately ignored so moving to an ADJACENT row doesn't cancel the request
                // that adjacency just made — see the list's own `.onHover` below for the one exit
                // that matters (leaving the list entirely).
                .onHover { isHovering in
                    if isHovering { hoveredURL = entry.url }
                }
            }
            .listStyle(.inset)
            // Hover-exit of the WHOLE list, not each row: a superseded request between adjacent
            // rows is handled for free by `ThumbnailService.Priority.interactive` (a new request
            // cancels its predecessor); this is the other half — nothing left in flight once the
            // pointer leaves the rows altogether, which is what the on-device sweep leg is
            // actually proving (FPS must not drop while the pointer crosses the whole library).
            .onHover { isHovering in
                if !isHovering {
                    hoveredURL = nil
                    Task { await instrument.thumbnailService.cancelInteractive() }
                }
            }
            // One request per hover target, started/superseded by `hoveredURL` changing — SwiftUI
            // cancels the previous instance of this task on every id change, but that cancellation
            // doesn't reach into the actor (see ThumbnailService.render's doc comment), so the
            // `Task.isCancelled` check below is what stops a superseded response from clobbering a
            // newer one.
            .task(id: hoveredURL) {
                guard let url = hoveredURL else { return }
                let result = await instrument.thumbnailService.thumbnail(for: url, priority: .interactive)
                guard !Task.isCancelled else { return }
                if case .image(let data) = result, let decoded = NSImage(data: data) {
                    hoverPreview = Image(nsImage: decoded)
                } else {
                    hoverPreview = nil
                }
            }

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

            hoverPreviewWell
        }
        .padding(8)
    }

    /// A fixed-size well at the panel's foot, not a floating popover over the rows — a popover
    /// would sit on top of exactly what the operator is scanning, and reflowing the list to make
    /// room for a preview would shift the row out from under the pointer mid-hover.
    private var hoverPreviewWell: some View {
        ZStack {
            if let hoverPreview {
                hoverPreview
                    .resizable()
                    .aspectRatio(16.0 / 9.0, contentMode: .fill)
                    .clipped()
            } else {
                Rectangle().fill(Color.white.opacity(0.05))
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 120)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.white.opacity(0.12)))
        .accessibilityIdentifier("libraryPanel.hoverPreview")
    }
}
