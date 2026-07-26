import SwiftUI
import AppKit

struct RemixChildCardView: View {
    @ObservedObject var model: RemixStudioModel
    let node: RemixNode
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

            Text(node.label ?? node.id)
                .font(.headline)
            Text(node.directive)
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
                            model.workspace.focusedChildID == node.id
                                ? Color.accentColor : Color.secondary.opacity(0.25),
                            lineWidth: model.workspace.focusedChildID == node.id ? 3 : 1
                        )
                }
        )
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onTapGesture { model.workspace.focus(node.id) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(RemixWorkspaceState.accessibilitySummary(
            name: node.label ?? node.id,
            status: statusName,
            position: position,
            total: total,
            directive: node.directive,
            actions: ["Favorite", "Compare", "Hero", "Promote A", "Promote B", "Open"]
        ))
    }

    @ViewBuilder
    private var preview: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10).fill(Color.black.opacity(0.12))
            switch node.status {
            case .generating:
                ProgressView("Generating")
            case .interrupted:
                salvagePanel("Generation interrupted", actions: generationActions)
            case .failed(let message):
                salvagePanel("Compile failed: \(message)", actions: compileActions)
            case .compiled:
                if let failure = model.previewFailuresByNodeID[node.id] {
                    salvagePanel("Preview unavailable: \(failure)", actions: previewActions)
                } else {
                    RemixThumbnailView(
                        isf: node.isfSource,
                        animating: model.shouldAnimate(
                            node.id,
                            on: .canvas,
                            reduceMotion: reduceMotion
                        ),
                        sharedClock: comparisonCoordinator?.clock,
                        renderSize: comparisonCoordinator?.renderSize,
                        inputValues: comparisonPreviewID.map {
                            comparisonCoordinator?.valuesForRenderer($0) ?? [:]
                        } ?? [:],
                        onSnapshot: { model.storeSnapshot(id: node.id, image: $0) },
                        onPreviewFailure: {
                            model.markPreviewFailure(id: node.id, message: $0)
                        }
                    ) { valid, error in
                        model.markCompileResult(id: node.id, valid: valid, error: error)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
        }
        .confirmationDialog(
            "Promote \(node.label ?? node.id) to Parent \(pendingPromotion == .a ? "A" : "B")?",
            isPresented: Binding(
                get: { pendingPromotion != nil },
                set: { if !$0 { pendingPromotion = nil } }
            )
        ) {
            if let pendingPromotion {
                Button("Confirm Promote to Parent \(pendingPromotion == .a ? "A" : "B")") {
                    model.promoteToParent(pendingPromotion, nodeID: node.id)
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
        Button(model.lineage.isFavorite(node.id) ? "Unfavorite" : "Favorite") {
            model.toggleFavorite(node.id)
        }
        Button(model.workspace.comparedChildIDs.contains(node.id) ? "Remove Compare" : "Compare") {
            model.workspace.toggleComparison(node.id)
        }
        Button(model.frozenPreviewIDs.contains(node.id) ? "Play Child" : "Freeze Child") {
            model.setPreviewFrozen(!model.frozenPreviewIDs.contains(node.id), for: node.id)
        }
        Button("Hero") { model.workspace.showHero(node.id) }
        Button("Promote A") { pendingPromotion = .a }
        Button("Promote B") { pendingPromotion = .b }
        Button("Open") { openInEditor(node.isfSource) }
    }

    private var generationActions: [RemixSalvageButton] {
        [
            RemixSalvageButton(title: "Retry Child") {
                Task { await model.retryChild(id: node.id) }
            },
            RemixSalvageButton(title: "Open Source") { openInEditor(node.isfSource) },
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
                    model.compileDiagnostic(for: node.id) ?? "Compile failed",
                    forType: .string
                )
            },
            RemixSalvageButton(title: "Open to Fix") { openInEditor(node.isfSource) },
            RemixSalvageButton(title: "Retry Child") {
                Task { await model.retryChild(id: node.id) }
            },
        ]
    }

    private var previewActions: [RemixSalvageButton] {
        [
            RemixSalvageButton(title: "Retry Preview") { model.retryPreview(id: node.id) },
            RemixSalvageButton(title: "Open in Editor") { openInEditor(node.isfSource) },
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
        switch node.status {
        case .generating: return "Generating"
        case .interrupted: return "Interrupted"
        case .failed: return "Failed"
        case .compiled:
            return model.previewFailuresByNodeID[node.id] == nil ? "Compiled" : "Preview unavailable"
        }
    }
}

private struct RemixSalvageButton: Identifiable {
    let id = UUID()
    let title: String
    let perform: () -> Void
}
