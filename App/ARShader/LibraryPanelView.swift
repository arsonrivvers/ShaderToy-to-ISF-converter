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

/// The result of waiting out the library hover dwell delay before requesting a thumbnail (F4, fix
/// round 1 on task 7). Extracted to a free function so the cancellation-early-return path is
/// unit-testable without driving SwiftUI or `ThumbnailService`'s actor — see
/// `LibraryPanelTests.testHoverDwellReturnsCancelledEarlyRatherThanSwallowingCancellation`.
enum HoverDwellOutcome: Equatable {
    /// The dwell elapsed without the calling task being cancelled — go ahead and request.
    case dwelled
    /// Cancelled before the dwell elapsed (the pointer moved to a different row, or left the list
    /// entirely, before lingering long enough). MUST short-circuit here rather than fall through
    /// to `.dwelled` — this is the only place a fast sweep down the whole library is actually kept
    /// cheap, since `ThumbnailService` cannot cancel an in-flight render once its actor has
    /// dequeued it (see `LibraryPanelView.hoveredURL`'s doc comment).
    case cancelledEarly
}

/// Sleeps for `duration`, observing cancellation rather than swallowing it. `try? await
/// Task.sleep(...)` would catch the thrown `CancellationError` and fall through to `.dwelled`
/// regardless of cancellation, making the whole dwell a no-op while looking correct — see
/// `LibraryPanelTests.testHoverDwellReturnsCancelledEarlyRatherThanSwallowingCancellation`'s
/// mutation proof for that exact bug going red.
func waitOutHoverDwell(_ duration: Duration) async -> HoverDwellOutcome {
    do {
        try await Task.sleep(for: duration)
        return .dwelled
    } catch {
        return .cancelledEarly
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
    /// F4 (fix round 1, task 7): starting point per the ruling — trivially retuned after an
    /// on-device sweep session.
    static let hoverDwell: Duration = .milliseconds(150)

    let instrument: Instrument
    @StateObject private var selection = LibrarySelection()
    @ObservedObject private var library: LibraryModel

    /// The row the pointer is over right now, or `nil` once it has left the list entirely. Drives
    /// `.task(id:)` below.
    ///
    /// **Corrected, fix round 1 (F2) — stated here as what was OBSERVED, not as a general claim
    /// about `ThumbnailService`:** an earlier draft of this comment claimed `ThumbnailService`
    /// itself supersedes a request still in flight when `hoveredURL` changes, which is false —
    /// `ThumbnailService.render(_:)` has no suspension point between entry and either return path
    /// (confirmed independently against `:150-165` during fix round 1's review), so once the
    /// actor dequeues a render it runs to completion regardless of what `hoveredURL` does
    /// afterward; `cancelInteractive()` cannot reach it either (also actor-isolated, so it cannot
    /// even begin until the actor is free). What actually holds: `.task(id:)`'s OWN cancellation
    /// — a SwiftUI-level guarantee, not an actor one — reliably fires the instant `hoveredURL`
    /// changes, and the dwell delay inside that task (see its own comment below) is what turns
    /// that into "a row merely swept past never reaches the actor at all." See
    /// task-7-report.md's fix-round-1 entry for the full empirical account.
    @State private var hoveredURL: URL?
    /// The still shown in the foot well. Deliberately NOT cleared when `hoveredURL` goes `nil` on
    /// list-exit (see the list's `.onHover` below) — the last resolved still stays put rather than
    /// flashing blank every time the pointer leaves the rows for the search field, the sort
    /// picker, or the well itself.
    @State private var hoverPreview: Image?
    /// A request is outstanding right now (final-review F7). Until this existed, the well kept the
    /// PREVIOUS shader's still at full opacity while a new one was being resolved — looking like a
    /// settled answer for the row under the pointer. On a cold cache a deliberate slow scan could
    /// leave the well seconds behind and still read as correct. Smoke leg 28 exists to judge that
    /// load behaviour on device, and judging it against a well that cannot say "still working"
    /// wastes the leg.
    @State private var isResolvingPreview = false

    /// What the foot well should be saying, given what it holds and whether a request is out.
    ///
    /// A named function rather than a ternary inline in `body` because it is the only part of F7
    /// that can be pinned by a test: the `@State` flag's lifecycle lives inside a `.task(id:)`
    /// closure with no seam a unit test can reach, but the MAPPING — the thing that decides whether
    /// a stale still is presented as settled — is pure. `hoverPreviewWell` calls this; there is no
    /// second copy of the rule.
    enum WellState: Equatable {
        /// Nothing has resolved yet and nothing is pending.
        case empty
        /// Showing a still, nothing outstanding: this IS the answer for the row under the pointer.
        case settled
        /// A request is out. Anything on screen belongs to a PREVIOUS row and must not read as an
        /// answer for this one.
        case resolving

        var imageOpacity: Double { self == .resolving ? 0.35 : 1 }
        var showsProgress: Bool { self == .resolving }
    }

    static func wellState(hasPreview: Bool, isResolving: Bool) -> WellState {
        if isResolving { return .resolving }
        return hasPreview ? .settled : .empty
    }

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

            // **A CLICK ON A LIBRARY ROW IS DELIBERATELY INERT. DRAG IS THE ONLY WAY TO LOAD.**
            // Operator ruling, 2026-08-02.
            //
            // This SUPERSEDES fix-round-1 F3's ruling, which is kept here rather than deleted
            // because the reasoning matters: that round restored a `Button` loading onto deck A,
            // argued entirely on accessibility grounds — a plain `Text` drops the button trait and
            // the activate action, and with the target picker also gone there would be no
            // keyboard/VoiceOver path to load a shader anywhere in the app. That argument was
            // correct on its own terms and has been WAIVED: this is a personal, mouse-and-MIDI
            // driven instrument, and no keyboard or VoiceOver path is wanted. A click that loads is
            // a click that can change what is on the wall by accident.
            //
            // Consequences accepted with the ruling: no button trait, no activate action, no
            // keyboard load path, and smoke leg 35b ("a library row is reachable without the
            // pointer") is struck. `.draggable`, `.help` and `.onHover` all stay, and
            // `.contentShape` keeps the whole row draggable and hoverable rather than just its
            // glyphs.
            List(entries) { entry in
                Text(entry.name)
                    .font(.system(size: 12, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)   // long AR_Genuary names differ at the END
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                .draggable(ShaderDrag(source: .library, url: entry.url, snapshot: nil))
                // Names are EXPECTED to middle-truncate (see above), so the full name is the only
                // way to read one the row itself cut off, and the drag hint is the only place the
                // gesture is documented at all. The "click to load onto deck A" half is gone with
                // the behaviour it described.
                .help("\(entry.name) — drag onto a deck, an FX chain, or a slot")
                // Task 7: a THIRD gesture on a row that already carries a click (the Button
                // action) and a drag (`.draggable`). `.onHover` is a hover-tracking area, not a
                // click/drag gesture recognizer, so it does not compete with either — verified by
                // running the existing drag-and-drop and click-to-load test coverage unchanged
                // (ShaderDragTests, LibraryPanelTests) after adding this; not yet verified
                // on-device (see task-7-report.md). Only reacts to hover-IN: hover-OUT of a single row
                // is deliberately ignored so moving to an ADJACENT row doesn't cancel the request
                // that adjacency just made — see the list's own `.onHover` below for the one exit
                // that matters (leaving the list entirely).
                .onHover { isHovering in
                    if isHovering { hoveredURL = entry.url }
                }
            }
            .listStyle(.inset)
            // Hover-exit of the WHOLE list, not each row. **Corrected, fix round 1 (F2):** an
            // earlier draft of this comment claimed a superseded request between adjacent rows is
            // "handled for free by ThumbnailService.Priority.interactive" — false; see
            // `hoveredURL`'s doc comment above for what was tested and found false, and the dwell
            // delay in `.task(id:)` below for what actually keeps a fast sweep cheap. This call
            // asks the SERVICE to cancel whatever interactive work it's tracking on full list-exit
            // — a best-effort request per `cancelInteractive()`'s own doc comment (it can only
            // land before the actor dequeues a render, not during one), still worth making since
            // it costs nothing and helps the case where nothing has been dequeued yet.
            .onHover { isHovering in
                if !isHovering {
                    hoveredURL = nil
                    Task { await instrument.thumbnailService.cancelInteractive() }
                }
            }
            // One request per hover target. **Corrected, fix round 1 (F2/F4):** an earlier draft
            // of this comment said "superseded by `hoveredURL` changing" as if that made an
            // in-flight render stop — it does not (see `hoveredURL`'s doc comment above). What
            // SwiftUI's cancellation of the PREVIOUS `.task(id:)` instance actually buys us is
            // reliable, cheap: it fires the moment `hoveredURL` changes, before this instance has
            // done anything but sleep. `waitOutHoverDwell` below is what turns that into "a row
            // merely swept past never requests a thumbnail at all" — the dwell delay is F4's real
            // fix for the sweep-performs-N-serialized-renders problem the reviewer identified; the
            // `Task.isCancelled` guard after the dwell is what stops an already-in-flight
            // response, superseded only at the SwiftUI level, from clobbering a newer preview once
            // it does resolve.
            .task(id: hoveredURL) {
                guard let url = hoveredURL else { return }
                guard case .dwelled = await waitOutHoverDwell(Self.hoverDwell) else { return }
                // Set AFTER the dwell, not before it (F7): a row merely swept past never requests
                // anything, so flagging on hover-enter would flicker the whole well on every row
                // the pointer crossed. This flips only once a request is genuinely going out.
                isResolvingPreview = true
                defer { isResolvingPreview = false }
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
        // Dimming and a spinner ON TOP, never a size change: the well's `.frame(height: 120)` is
        // unchanged in every state. "Ideal width is not minimum width" already cost this branch two
        // fix rounds, and a well that resizes while the operator scans the list is the same class
        // of defect on the other axis.
        let state = Self.wellState(hasPreview: hoverPreview != nil, isResolving: isResolvingPreview)
        return ZStack {
            if let hoverPreview {
                hoverPreview
                    .resizable()
                    .aspectRatio(16.0 / 9.0, contentMode: .fill)
                    .clipped()
                    .opacity(state.imageOpacity)
            } else {
                Rectangle().fill(Color.white.opacity(0.05))
            }
            if state.showsProgress {
                ProgressView().controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 120)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.white.opacity(0.12)))
        .accessibilityIdentifier("libraryPanel.hoverPreview")
    }
}
