import SwiftUI
import AppKit

struct RemixChildCardView: View {
    @ObservedObject var model: RemixStudioModel
    let run: RemixChildRunRecord
    let artifact: RemixNode?
    let position: Int
    let total: Int
    let openInEditor: (String) -> Void
    var comparisonCoordinator: RemixComparisonCoordinator?
    var comparisonPreviewID: String?
    var showCompileSummary: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pendingPromotion: ParentSlot?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            preview
                .frame(minHeight: 180)

            Text(artifact?.label ?? run.id)
                .font(.headline)
            Text(run.request.directive)
                .font(RemixAccessibleTextLayout.bodyFont)
                .fixedSize(horizontal: false, vertical: true)

            ViewThatFits {
                HStack { cardActions }
                VStack(alignment: .leading) { cardActions }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.background)
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(
                            model.workspace.focusedChildID == run.id
                                ? Color.accentColor : Color.secondary.opacity(0.25),
                            lineWidth: model.workspace.focusedChildID == run.id ? 3 : 1
                        )
                }
        )
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onTapGesture { model.workspace.focus(run.id) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(RemixWorkspaceState.accessibilitySummary(
            name: artifact?.label ?? run.id,
            status: statusName,
            position: position,
            total: total,
            directive: run.request.directive,
            actions: ["Favorite", "Compare", "Hero", "Promote A", "Promote B", "Open"]
        ))
    }

    @ViewBuilder
    private var preview: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10).fill(Color.black.opacity(0.12))
            switch run.stage {
            case .queued, .starting, .thinking, .receiving, .retrying, .extracting, .compiling:
                ProgressView(run.stage.rawValue.capitalized)
            case .interrupted:
                salvagePanel("Generation interrupted", actions: generationActions)
            case .cancelled:
                salvagePanel("Generation cancelled", actions: generationActions)
            case .failed:
                salvagePanel(
                    run.failureMessage ?? "Generation failed",
                    actions: run.failureBoundary == .compile ? compileActions : generationActions
                )
            case .ready:
                if let diagnostic = run.artifactID.flatMap({ model.previewStates[$0]?.diagnostic }) {
                    salvagePanel("Preview unavailable: \(diagnostic)", actions: previewActions)
                } else if let artifact {
                    RemixThumbnailView(
                        isf: artifact.isfSource,
                        animating: model.shouldAnimate(
                            run.id,
                            on: .canvas,
                            reduceMotion: reduceMotion
                        ),
                        sharedClock: comparisonCoordinator?.clock,
                        renderSize: comparisonCoordinator?.renderSize,
                        inputValues: comparisonPreviewID.map {
                            comparisonCoordinator?.valuesForRenderer($0) ?? [:]
                        } ?? [:],
                        reloadAttempt: model.previewStates[artifact.id]?.attempt ?? 0,
                        onSnapshot: { model.storeSnapshot(id: run.id, image: $0) },
                        onPreviewFailure: {
                            model.markPreviewFailed(artifactID: artifact.id, diagnostic: $0)
                        }
                    ) { valid, error in
                        if valid {
                            model.markPreviewAvailable(artifactID: artifact.id)
                        } else if let error {
                            model.markPreviewFailed(artifactID: artifact.id, diagnostic: error)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
        }
        .confirmationDialog(
            "Promote \(artifact?.label ?? run.id) to Parent \(pendingPromotion == .a ? "A" : "B")?",
            isPresented: Binding(
                get: { pendingPromotion != nil },
                set: { if !$0 { pendingPromotion = nil } }
            )
        ) {
            if let pendingPromotion {
                Button("Confirm Promote to Parent \(pendingPromotion == .a ? "A" : "B")") {
                    model.promoteToParent(pendingPromotion, nodeID: run.id)
                    self.pendingPromotion = nil
                }
            }
            Button("Cancel", role: .cancel) { pendingPromotion = nil }
        } message: {
            Text("This changes the target for the next generation.")
        }
    }

    @ViewBuilder
    private var cardActions: some View {
        Button(model.lineage.isFavorite(run.id) ? "Unfavorite" : "Favorite") {
            model.toggleFavorite(run.id)
        }
        .disabled(artifact == nil)
        Button(model.workspace.comparedChildIDs.contains(run.id) ? "Remove Compare" : "Compare") {
            model.workspace.toggleComparison(run.id)
        }
        .disabled(artifact == nil)
        Button(model.frozenPreviewIDs.contains(run.id) ? "Play Child" : "Freeze Child") {
            model.setPreviewFrozen(!model.frozenPreviewIDs.contains(run.id), for: run.id)
        }
        .disabled(artifact == nil)
        Button("Hero") { model.workspace.showHero(run.id) }
            .disabled(artifact == nil)
        Button("Promote A") { pendingPromotion = .a }
            .disabled(artifact == nil)
        Button("Promote B") { pendingPromotion = .b }
            .disabled(artifact == nil)
        Button("Open") { if let artifact { openInEditor(artifact.isfSource) } }
            .disabled(artifact == nil)
    }

    private var generationActions: [RemixSalvageButton] {
        [
            RemixSalvageButton(title: "Retry Child") {
                Task { await model.retryChild(id: run.id) }
            },
            RemixSalvageButton(title: "Open Source") {
                if let source = run.candidateSource { openInEditor(source) }
            },
        ]
    }

    private var compileActions: [RemixSalvageButton] {
        [
            RemixSalvageButton(title: "View Summary") {
                showCompileSummary()
            },
            RemixSalvageButton(title: "Copy Diagnostic") {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(
                    model.compileDiagnostic(for: run.id) ?? "Compile failed",
                    forType: .string
                )
            },
            RemixSalvageButton(title: "Open to Fix") {
                if let source = run.candidateSource { openInEditor(source) }
            },
            RemixSalvageButton(title: "Retry Child") {
                Task { await model.retryChild(id: run.id) }
            },
        ]
    }

    private var previewActions: [RemixSalvageButton] {
        [
            RemixSalvageButton(title: "Retry Preview") {
                if let artifact { model.retryPreview(artifactID: artifact.id) }
            },
            RemixSalvageButton(title: "Open in Editor") {
                if let artifact { openInEditor(artifact.isfSource) }
            },
        ]
    }

    private func salvagePanel(_ message: String, actions: [RemixSalvageButton]) -> some View {
        VStack(spacing: 10) {
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.orange)
            ForEach(actions) { action in
                Button(action.title, action: action.perform)
            }
        }
        .padding()
    }

    private var statusName: String {
        switch run.stage {
        case .queued, .starting, .thinking, .receiving, .retrying, .extracting, .compiling:
            return run.stage.rawValue.capitalized
        case .interrupted: return "Interrupted"
        case .cancelled: return "Cancelled"
        case .failed: return "Failed"
        case .ready:
            return artifact.flatMap { model.previewStates[$0.id] }?.stage == .failed
                ? "Preview unavailable" : "Ready"
        }
    }
}

struct RemixSalvageButton: Identifiable {
    var id: String { title }
    let title: String
    let perform: () -> Void
}
