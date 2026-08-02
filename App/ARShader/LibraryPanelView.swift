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

/// Owns the hover preview's resolved image and its generation-guarded loading flag (fix round 2,
/// item 1). An `ObservableObject`, not `@State`, for the same reason `LibrarySelection` above is
/// one: `@State`'s storage only functions inside a LIVE SwiftUI view graph — writes to a `@State`
/// property on a `LibraryPanelView` value constructed directly (as a test must, to reach the real
/// call site rather than a re-derivation of it) are silently discarded, confirmed empirically while
/// building this fix (every write read back as the property's initial value, even within the SAME
/// method call). That made the flag's lifecycle — the one part of F7 that most needed a test —
/// structurally unreachable. This class has ordinary reference semantics: a test constructs one
/// directly, calls `resolveHoverPreview` on it, and reads `isResolvingPreview` back like any other
/// object, no hosting required. `@Published` still drives the same live view updates `@State` did.
@MainActor
final class HoverPreviewResolver: ObservableObject {
    /// The still shown in the foot well. Deliberately NOT cleared when hover leaves the list (see
    /// `LibraryPanelView`'s list-exit `.onHover`) — the last resolved still stays put rather than
    /// flashing blank every time the pointer leaves the rows for the search field, the sort
    /// picker, or the well itself.
    @Published private(set) var hoverPreview: Image?
    /// A request is outstanding right now (final-review F7). Until this existed, the well kept the
    /// PREVIOUS shader's still at full opacity while a new one was being resolved — looking like a
    /// settled answer for the row under the pointer. On a cold cache a deliberate slow scan could
    /// leave the well seconds behind and still read as correct. Smoke leg 28 exists to judge that
    /// load behaviour on device, and judging it against a well that cannot say "still working"
    /// wastes the leg.
    @Published private(set) var isResolvingPreview = false
    /// Generation stamp for `isResolvingPreview` (fix round 2, item 1). `.task(id:)` cancellation
    /// does not stop an already-suspended instance's execution — only its own `Task.isCancelled`
    /// check does, and `ThumbnailService.render` has no suspension point that observes it early
    /// (see `LibraryPanelView.hoveredURL`'s doc comment). So a superseded instance (row A) can
    /// still be suspended inside `thumbnail(for:)` when a newer instance (row B) starts, sets
    /// `isResolvingPreview = true` again, and begins its own render. When A's render finishes, A
    /// resumes, hits `guard !Task.isCancelled`, returns — and WITHOUT this guard its `defer` would
    /// clear `isResolvingPreview` while B is still outstanding, flipping the well to `.settled` on
    /// the PREVIOUS row's still for the whole of B's render. Each call stamps the generation it
    /// started with and only clears the flag if it is still the current one.
    private var previewGeneration = 0

    /// The body of `.task(id:)`, extracted here (rather than left inline in the view) so a test can
    /// drive the REAL generation-guarded flag lifecycle directly instead of merely modelling it.
    /// `render` is never defaulted — the production call site always passes the real
    /// `ThumbnailService` call explicitly — so a test can substitute a controllable stand-in and
    /// reproduce the exact overlap this fix exists to survive, without depending on real GPU render
    /// timing. See `LibraryPanelTests.testASupersededHoverInstanceDoesNotClearTheFlagWhileANewerOneIsOutstanding`.
    func resolveHoverPreview(url: URL, render: (URL) async -> ThumbnailService.Result) async {
        previewGeneration += 1
        let generation = previewGeneration
        isResolvingPreview = true
        // Fix round 2, item 1: only the call that is STILL current may clear the flag. A
        // superseded call (see `previewGeneration`'s doc comment) reaches this same `defer` after
        // a newer request has already taken over — without the generation check it would clear
        // the flag out from under that newer request.
        defer { if previewGeneration == generation { isResolvingPreview = false } }
        let result = await render(url)
        guard !Task.isCancelled else { return }
        if case .image(let data) = result, let decoded = NSImage(data: data) {
            hoverPreview = Image(nsImage: decoded)
        } else {
            hoverPreview = nil
        }
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
    /// Fix round 2, item 1: owns the resolved still and the generation-guarded loading flag — see
    /// `HoverPreviewResolver`'s doc comment for why this is an `ObservableObject` rather than
    /// `@State` (testability).
    @StateObject private var hoverResolver = HoverPreviewResolver()

    /// What the foot well should be saying, given what it holds and whether a request is out.
    ///
    /// A named function rather than a ternary inline in `body`: the MAPPING — the thing that
    /// decides whether a stale still is presented as settled — is pure and this is what
    /// `hoverPreviewWell` calls; there is no second copy of the rule.
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
                // Task 7, corrected fix round 2 (item 3a): a SECOND gesture on a row that is
                // otherwise inert (F12 removed the Button — no click path at all) and carries only
                // a drag (`.draggable`). `.onHover` is a hover-tracking area, not a click/drag
                // gesture recognizer, so it does not compete with the drag — verified by running
                // the existing drag-and-drop test coverage unchanged (ShaderDragTests,
                // LibraryPanelTests) after adding this; not yet verified on-device (see
                // task-7-report.md). Only reacts to hover-IN: hover-OUT of a single row
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
                await hoverResolver.resolveHoverPreview(url: url) { url in
                    await instrument.thumbnailService.thumbnail(for: url, priority: .interactive)
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
        let state = Self.wellState(hasPreview: hoverResolver.hoverPreview != nil,
                                   isResolving: hoverResolver.isResolvingPreview)
        return ZStack {
            if let hoverPreview = hoverResolver.hoverPreview {
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
