import AppKit
import SwiftUI

struct RemixBreedingBayView: View {
    @ObservedObject var model: RemixStudioModel
    let resolver: RemixParentResolver
    let libraryEntries: [LibraryEntry]
    let currentEditorLabel: String

    @State private var pasteInputs: [ParentSlot: String] = [:]
    @State private var shadertoyInputs: [ParentSlot: String] = [:]
    @State private var showCrossoverSettings = false
    @AccessibilityFocusState private var focusedControl: RemixWorkspaceFocusToken?

    private var presentation: RemixBreedingBayPresentation {
        RemixBreedingBayPresentation(
            mode: model.mode,
            parentAID: model.parentAID,
            parentBID: model.parentBID,
            parentLoadState: model.parentLoadState
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(presentation.heading)
                    .font(.title2.bold())
                    .accessibilityAddTraits(.isHeader)
                Text(presentation.shortestPath)
                    .font(RemixAccessibleTextLayout.bodyFont)
                    .lineLimit(RemixAccessibleTextLayout.criticalTextLineLimit)
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundStyle(.secondary)

                Picker("Remix mode", selection: $model.mode) {
                    Text("Crossover").tag(RemixMode.crossover)
                    Text("Mutate").tag(RemixMode.mutate)
                }
                .pickerStyle(.segmented)

                parentSlot(.a)
                if model.mode == .crossover {
                    parentSlot(.b)
                }

                TextField("Steer the remix (optional)", text: $model.steer)
                    .textFieldStyle(.roundedBorder)
                Stepper("Batch size: \(model.batchSize)", value: $model.batchSize, in: 1...8)

                Button("Crossover Settings") {
                    showCrossoverSettings = true
                }
                .accessibilityFocused($focusedControl, equals: .crossoverSettings)
                .popover(isPresented: $showCrossoverSettings, arrowEdge: .trailing) {
                    RemixCrossoverPopover(model: model) {
                        focusedControl = .crossoverSettings
                    }
                }

                Button("Generate") {
                    model.startGeneration()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: [])
                .disabled(!model.canGenerate)
                .help(presentation.generateDisabledReason ?? "Generate a new batch")

                if let reason = presentation.generateDisabledReason,
                   let action = presentation.generateResolvingAction {
                    Text("\(reason) \(action)")
                        .font(RemixAccessibleTextLayout.bodyFont)
                        .lineLimit(RemixAccessibleTextLayout.criticalTextLineLimit)
                        .fixedSize(horizontal: false, vertical: true)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("\(reason) \(action)")
                }

                parentLoadStatus
            }
            .padding(16)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Breeding Bay")
        .accessibilitySortPriority(3)
        .font(RemixTextPolicy.bodyFont)
        .onChange(of: model.parentLoadState) { state in
            if case .parentSource(let slot) = state.focusTarget {
                focusedControl = .parentSource(slot)
            }
            restoreDisplayInput(from: state.request)
        }
        .onAppear { restoreDisplayInput(from: model.parentLoadState.request) }
    }

    private func parentSlot(_ slot: ParentSlot) -> some View {
        let title = RemixBreedingBayPresentation.parentName(slot)
        let id = slot == .a ? model.parentAID : model.parentBID
        return VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
                .accessibilityAddTraits(.isHeader)

            if let id, let node = model.lineage.node(id) {
                Text(node.label ?? id)
                    .font(RemixAccessibleTextLayout.bodyFont)
                Button("Clear \(title)") { model.clearParent(slot) }
            } else {
                Text("No shader selected")
                    .font(RemixAccessibleTextLayout.bodyFont)
                    .foregroundStyle(.secondary)
            }

            Menu(presentation.parentActionTitle(for: slot)) {
                Menu(presentation.sourceActionLabel(.library, slot: slot)) {
                    ForEach(libraryEntries) { entry in
                        Button(
                            presentation.actionableSourceLabel(
                                .library,
                                slot: slot,
                                identity: entry.name
                            )
                        ) {
                            load(
                                .libraryFile(entry.url),
                                displayInput: entry.name,
                                slot: slot
                            )
                        }
                    }
                }
                Button(
                    presentation.actionableSourceLabel(
                        .currentEditor,
                        slot: slot,
                        identity: currentEditorLabel
                    )
                ) {
                    load(.currentEditor, displayInput: "Current Editor", slot: slot)
                }
            }
            .accessibilityLabel(presentation.parentActionTitle(for: slot))
            .accessibilityFocused($focusedControl, equals: .parentSource(slot))

            TextField(
                presentation.sourceActionLabel(.shadertoy, slot: slot),
                text: inputBinding($shadertoyInputs, slot: slot)
            )
            .textFieldStyle(.roundedBorder)
            Button(presentation.sourceActionLabel(.shadertoy, slot: slot)) {
                let input = shadertoyInputs[slot, default: ""]
                guard !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                load(.shadertoyLink(input), displayInput: input, slot: slot)
            }

            TextEditor(text: inputBinding($pasteInputs, slot: slot))
                .frame(minHeight: 72)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
                .accessibilityLabel("ISF code for \(title)")
                .accessibilityFocused($focusedControl, equals: .pasteSource(slot))
            Button(presentation.sourceActionLabel(.paste, slot: slot)) {
                let input = pasteInputs[slot, default: ""]
                guard !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                load(.pastedISF(input), displayInput: input, slot: slot)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(.background.opacity(0.75)))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }

    @ViewBuilder
    private var parentLoadStatus: some View {
        if let status = presentation.parentLoadStatus {
            VStack(alignment: .leading, spacing: 8) {
                Text(status)
                    .font(.headline)
                    .accessibilityAddTraits(.updatesFrequently)
                if let instruction = presentation.parentLoadInstruction {
                    Text(instruction)
                        .font(RemixAccessibleTextLayout.bodyFont)
                        .lineLimit(RemixAccessibleTextLayout.criticalTextLineLimit)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if case .verificationRequired = model.parentLoadState {
                    continueVerificationButton
                } else if case .waitingForHuman = model.parentLoadState {
                    continueVerificationButton
                }
                if model.parentLoadState.request != nil {
                    Button("Cancel Parent Import") {
                        if case .parentSource(let slot) = model.cancelParentLoad() {
                            focusedControl = .parentSource(slot)
                        }
                    }
                }
                recoveryControls
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.orange.opacity(0.12)))
            .accessibilityElement(children: .contain)
            .accessibilityLabel(status)
        }
    }

    private var continueVerificationButton: some View {
        Button("Continue Verification") {
            _ = model.continueParentVerification(from: resolver)
        }
        .help("Return to the visible security check. The import resumes after legitimate clearance.")
    }

    @ViewBuilder
    private var recoveryControls: some View {
        if let request = presentation.retryRequest {
            ForEach(presentation.recoveryActions, id: \.kind) { action in
                Button(action.title) {
                    switch action.kind {
                    case .retryFetch, .retryCurrentEditor:
                        model.loadParent(request, from: resolver)
                    case .chooseLibrary:
                        focusedControl = .parentSource(request.slot)
                    case .useAPIKey:
                        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                    case .paste:
                        focusedControl = .pasteSource(request.slot)
                    }
                }
                .accessibilityLabel(action.title)
            }
        }
    }

    private func inputBinding(
        _ inputs: Binding<[ParentSlot: String]>,
        slot: ParentSlot
    ) -> Binding<String> {
        Binding(
            get: { inputs.wrappedValue[slot, default: ""] },
            set: { inputs.wrappedValue[slot] = $0 }
        )
    }

    private func load(_ spec: ParentSpec, displayInput: String, slot: ParentSlot) {
        model.loadParent(
            RemixParentRequest(slot: slot, spec: spec, displayInput: displayInput),
            from: resolver
        )
    }

    private func restoreDisplayInput(from request: RemixParentRequest?) {
        guard let request else { return }
        switch request.spec {
        case .shadertoyLink:
            shadertoyInputs[request.slot] = request.displayInput
        case .pastedISF:
            pasteInputs[request.slot] = request.displayInput
        case .libraryFile, .currentEditor:
            break
        }
    }
}
