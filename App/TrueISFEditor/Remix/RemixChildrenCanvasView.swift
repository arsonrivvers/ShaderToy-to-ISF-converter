import SwiftUI
import AppKit

enum RemixCanvasKeyRouter {
    static func shouldHandle(
        canvasFocusActive: Bool,
        firstResponderIsTextInput: Bool
    ) -> Bool {
        canvasFocusActive && !firstResponderIsTextInput
    }

    static func command(for characters: String, canvasFocused: Bool) -> RemixKeyboardCommand? {
        command(for: characters, modifiers: [], canvasFocused: canvasFocused)
    }

    static func command(
        for characters: String,
        modifiers: NSEvent.ModifierFlags,
        canvasFocused: Bool
    ) -> RemixKeyboardCommand? {
        guard canvasFocused else { return nil }
        let disallowed: NSEvent.ModifierFlags = [.command, .option, .control, .shift]
        guard modifiers.intersection(disallowed).isEmpty else { return nil }
        switch characters.lowercased() {
        case " ": return .toggleComparison
        case "f": return .favorite
        case "\r", "\n": return .hero
        case "\u{1b}": return .exitCanvasMode
        default: return nil
        }
    }
}

enum RemixCanvasWidthPolicy {
    enum Presentation: Equatable { case regular, compact }
    static func presentation(for width: CGFloat) -> Presentation {
        width < 720 ? .compact : .regular
    }
}

enum RemixCanvasEmptyStatePolicy {
    static let instructionLineLimit: Int? = nil
    static let usesFixedVerticalSize = true
    static let fillsAvailableHeight = true
    static let horizontalPadding: CGFloat = 16
}

struct RemixCanvasFocusedActionAvailability: Equatable {
    let focusedChildID: String?
    let retainedReadyArtifactID: String?

    var isEnabled: Bool {
        focusedChildID != nil && retainedReadyArtifactID != nil
    }
    var reason: String? {
        if isEnabled { return nil }
        if focusedChildID == nil {
            return "Focus a child card to use focused child actions."
        }
        return "Wait for the focused child to become Ready before using focused child actions."
    }
}

struct RemixChildrenCanvasView: View {
    @ObservedObject var model: RemixStudioModel
    let openInEditor: (String) -> Void

    @StateObject private var comparison = RemixComparisonCoordinator()
    @FocusState private var canvasFocused: Bool
    @FocusState private var focusedChildID: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var gridColumnCount = 1
    @State private var availableWidth: CGFloat = 900
    @State private var diagnosticSummary: String?

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 12), count: gridColumnCount)
    }

    var body: some View {
        VStack(spacing: 0) {
            controls
            Divider()
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .focusable()
        .focused($canvasFocused)
        .background(
            RemixCanvasKeyCapture(active: canvasFocused || focusedChildID != nil) { characters in
                guard let command = RemixCanvasKeyRouter.command(
                    for: characters,
                    canvasFocused: canvasFocused || focusedChildID != nil
                ) else {
                    return false
                }
                model.routeCanvasCommand(command, columns: gridColumnCount)
                restoreFocus()
                return true
            }
        )
        .background(
            GeometryReader { geometry in
                Color.clear
                    .onAppear { availableWidth = geometry.size.width }
                    .onChange(of: geometry.size.width) { availableWidth = $0 }
            }
        )
        .onMoveCommand { direction in
            let command: RemixKeyboardCommand
            switch direction {
            case .left: command = .moveLeft
            case .right: command = .moveRight
            case .up: command = .moveUp
            case .down: command = .moveDown
            @unknown default: return
            }
            model.routeCanvasCommand(command, columns: gridColumnCount)
            focusedChildID = model.workspace.focusedChildID
        }
        .onAppear {
            restoreFocus()
            configureComparison()
        }
        .onChange(of: model.workspace.canvasMode) { _ in restoreFocus() }
        .onChange(of: focusedChildID) { id in
            if let id { model.workspace.focusedChildID = id }
        }
        .onChange(of: model.workspace.comparedChildIDs) { _ in configureComparison() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Children Canvas")
        .accessibilityHint("Use arrow keys to move among children. Use the labeled commands to compare, favorite, promote, or open the focused child.")
        .sheet(isPresented: Binding(
            get: { diagnosticSummary != nil },
            set: { if !$0 { diagnosticSummary = nil } }
        )) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Compile Summary").font(.title2.bold())
                Text(diagnosticSummary ?? "")
                    .textSelection(.enabled)
                HStack {
                    Spacer()
                    Button("Close") { diagnosticSummary = nil }
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(24)
            .frame(minWidth: 480, minHeight: 240)
        }
    }

    private var controls: some View {
        Group {
            if RemixCanvasWidthPolicy.presentation(for: availableWidth) == .regular {
                HStack(spacing: 10) { primaryControls }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Picker("Canvas layout", selection: $model.workspace.canvasMode) {
                        Text("Grid").tag(RemixCanvasMode.grid)
                        Text("Compare 2").tag(RemixCanvasMode.comparison)
                        Text("Hero").tag(RemixCanvasMode.hero)
                    }
                    .pickerStyle(.segmented)
                    HStack(spacing: 8) {
                        playbackControls
                        Spacer()
                        Menu("Focused Child Actions") { focusedCommands }
                    }
                }
            }
        }
        .padding(10)
    }

    @ViewBuilder
    private var primaryControls: some View {
            Picker("Canvas layout", selection: $model.workspace.canvasMode) {
                Text("Grid").tag(RemixCanvasMode.grid)
                Text("Compare 2").tag(RemixCanvasMode.comparison)
                Text("Hero").tag(RemixCanvasMode.hero)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 360)

            playbackControls
            Spacer()
            focusedCommands
    }

    @ViewBuilder
    private var playbackControls: some View {
            Button(previewsArePaused ? "Play Previews" : "Pause Previews") {
                if previewsArePaused {
                    model.explicitlyPlayPreviews()
                } else {
                    model.workspace.previewsPaused = true
                }
                comparison.setPaused(model.workspace.previewsPaused)
            }
            Button("Reset Time") { comparison.resetTime() }
    }

    @ViewBuilder
    private var focusedCommands: some View {
        let availability = RemixCanvasFocusedActionAvailability(
            focusedChildID: model.workspace.focusedChildID,
            retainedReadyArtifactID: model.focusedReadyArtifactID
        )
        Button("Compare Focused") {
            model.routeCanvasCommand(.toggleComparison, columns: gridColumnCount)
        }
        .disabled(!availability.isEnabled)
        .help(availability.reason ?? "Space while a child card is focused")
        .accessibilityHint(availability.reason ?? "Space while a child card is focused")
        Button("Favorite Focused") {
            model.routeCanvasCommand(.favorite, columns: gridColumnCount)
        }
        .disabled(!availability.isEnabled)
        .help(availability.reason ?? "F while a child card is focused")
        .accessibilityHint(availability.reason ?? "F while a child card is focused")
        Button("Show Focused as Hero") {
            model.routeCanvasCommand(.hero, columns: gridColumnCount)
        }
        .disabled(!availability.isEnabled)
        .help(availability.reason ?? "Return while a child card is focused")
        .accessibilityHint(availability.reason ?? "Return while a child card is focused")
    }

    @ViewBuilder
    private var content: some View {
        if model.childViewItems.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "sparkles.rectangle.stack")
                    .font(.largeTitle)
                    .accessibilityHidden(true)
                Text("Choose a starting shader")
                    .font(.title2.bold())
                Text("Add the required parents in the Breeding Bay, then choose Generate.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(RemixCanvasEmptyStatePolicy.instructionLineLimit)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, RemixCanvasEmptyStatePolicy.horizontalPadding)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            switch model.workspace.canvasMode {
            case .grid:
                grid
            case .comparison:
                comparisonView
            case .hero:
                heroView
            }
        }
    }

    private var grid: some View {
        GeometryReader { geometry in
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(Array(model.childViewItems.enumerated()), id: \.element.id) { index, item in
                        card(item, index: index, coordinator: nil, previewID: nil)
                            .focusable()
                            .focused($focusedChildID, equals: item.id)
                            .onTapGesture {
                                focusedChildID = item.id
                                model.workspace.focus(item.id)
                            }
                    }
                }
                .padding(16)
            }
            .onAppear { updateGridColumns(for: geometry.size.width) }
            .onChange(of: geometry.size.width) { updateGridColumns(for: $0) }
        }
    }

    @ViewBuilder
    private var comparisonView: some View {
        let selected = model.workspace.comparedChildIDs.compactMap(item)
        if selected.count == 2 {
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                card(selected[0], index: index(of: selected[0]), coordinator: comparison, previewID: "left")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .focusable()
                    .focused($focusedChildID, equals: selected[0].id)
                card(selected[1], index: index(of: selected[1]), coordinator: comparison, previewID: "right")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .focusable()
                    .focused($focusedChildID, equals: selected[1].id)
                }
                comparisonControls
            }
            .padding(16)
            .accessibilityLabel("Synchronized two child comparison")
        } else {
            emptyMode(
                title: "Choose Two Children",
                systemImage: "rectangle.split.2x1",
                description: "Select Compare on two child cards. Your current focus is preserved."
            )
        }
    }

    @ViewBuilder
    private var heroView: some View {
        if let id = model.workspace.heroChildID ?? model.workspace.focusedChildID,
           let item = item(id) {
            card(item, index: index(of: item), coordinator: nil, previewID: nil)
                .padding(16)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .focusable()
                .focused($focusedChildID, equals: item.id)
        } else {
            emptyMode(
                title: "Choose a Hero",
                systemImage: "rectangle.inset.filled",
                description: "Focus a child and choose Show Focused as Hero."
            )
        }
    }

    private func card(
        _ item: RemixChildViewItem,
        index: Int,
        coordinator: RemixComparisonCoordinator?,
        previewID: String?
    ) -> some View {
        RemixChildCardView(
            model: model,
            run: item.run,
            artifact: item.artifact,
            position: index + 1,
            total: model.childViewItems.count,
            openInEditor: openInEditor,
            comparisonCoordinator: coordinator,
            comparisonPreviewID: previewID,
            showCompileSummary: {
                diagnosticSummary = model.compileSummary(for: item.id)
            }
        )
    }

    private func emptyMode(title: String, systemImage: String, description: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.largeTitle)
                .accessibilityHidden(true)
            Text(title).font(.title2.bold())
            Text(description)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var previewsArePaused: Bool {
        model.workspace.previewsPaused || (reduceMotion && !model.reduceMotionPlaybackEnabled)
    }

    private func item(_ id: String) -> RemixChildViewItem? {
        model.childViewItems.first { $0.id == id }
    }

    private func index(of item: RemixChildViewItem) -> Int {
        model.childViewItems.firstIndex { $0.id == item.id } ?? 0
    }

    private func restoreFocus() {
        if model.workspace.focusedChildID == nil {
            model.workspace.focusedChildID = model.childViewItems.first?.id
        }
        focusedChildID = model.workspace.focusedChildID
        DispatchQueue.main.async {
            focusedChildID = model.workspace.focusedChildID
            canvasFocused = focusedChildID == nil
        }
    }

    private func configureComparison() {
        let selected = model.workspace.comparedChildIDs.compactMap(item)
        guard selected.count == 2,
              let left = selected[0].artifact,
              let right = selected[1].artifact
        else { return }
        comparison.configure(leftISF: left.isfSource, rightISF: right.isfSource)
        comparison.setPaused(model.workspace.previewsPaused)
    }

    private func updateGridColumns(for width: CGFloat) {
        gridColumnCount = max(1, Int((width + 12) / (240 + 12)))
    }

    @ViewBuilder
    private var comparisonControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(comparison.compatibleInputNames.sorted(), id: \.self) { name in
                parameterControl(name, previewID: "left", label: "Shared \(name)", shared: true)
                .accessibilityElement(children: .combine)
            }
            ForEach(comparison.incompatibleInputNames, id: \.self) { name in
                VStack(alignment: .leading, spacing: 6) {
                    Text(comparison.incompatibilityExplanation(for: name) ?? "")
                        .foregroundStyle(.secondary)
                    childInputControl(name, previewID: "left", label: "Left \(name)")
                    childInputControl(name, previewID: "right", label: "Right \(name)")
                }
            }
        }
        .padding(.horizontal)
    }

    private func sharedFloatBinding(_ name: String) -> Binding<Double> {
        Binding(
            get: {
                if case .float(let value) = comparison.value(for: name, previewID: "left") {
                    return value
                }
                return 0.5
            },
            set: { comparison.setSharedValue(.float($0), for: name) }
        )
    }

    private func sharedBoolBinding(_ name: String) -> Binding<Bool> {
        Binding(
            get: {
                if case .bool(let value) = comparison.value(for: name, previewID: "left") {
                    return value
                }
                return false
            },
            set: { comparison.setSharedValue(.bool($0), for: name) }
        )
    }

    private func childFloatBinding(_ name: String, previewID: String) -> Binding<Double> {
        Binding(
            get: {
                if case .float(let value) = comparison.value(for: name, previewID: previewID) {
                    return value
                }
                return 0.5
            },
            set: { comparison.setValue(.float($0), for: name, previewID: previewID) }
        )
    }

    private func childBoolBinding(_ name: String, previewID: String) -> Binding<Bool> {
        Binding(
            get: {
                if case .bool(let value) = comparison.value(for: name, previewID: previewID) {
                    return value
                }
                return false
            },
            set: { comparison.setValue(.bool($0), for: name, previewID: previewID) }
        )
    }

    @ViewBuilder
    private func childInputControl(_ name: String, previewID: String, label: String) -> some View {
        if comparison.inputType(for: name, previewID: previewID) != nil {
            parameterControl(name, previewID: previewID, label: label, shared: false)
        }
    }

    @ViewBuilder
    private func parameterControl(
        _ name: String,
        previewID: String,
        label: String,
        shared: Bool
    ) -> some View {
        if let type = comparison.inputType(for: name, previewID: previewID) {
            switch RemixComparisonCoordinator.controlKind(for: type) {
            case .bool:
                Toggle(
                    label,
                    isOn: shared ? sharedBoolBinding(name) : childBoolBinding(name, previewID: previewID)
                )
            case .float:
                HStack {
                    Text(label)
                    Slider(
                        value: shared ? sharedFloatBinding(name) : childFloatBinding(name, previewID: previewID),
                        in: 0...1
                    )
                }
            case .long:
                Stepper(
                    "\(label): \(integerValue(name, previewID: previewID))",
                    value: integerBinding(name, previewID: previewID, shared: shared)
                )
            case .point2D:
                VStack(alignment: .leading) {
                    Text(label)
                    Slider(value: pointBinding(name, previewID: previewID, component: 0, shared: shared), in: 0...1)
                    Slider(value: pointBinding(name, previewID: previewID, component: 1, shared: shared), in: 0...1)
                }
            case .color:
                VStack(alignment: .leading) {
                    Text(label)
                    ForEach(0..<4, id: \.self) { component in
                        Slider(
                            value: colorBinding(
                                name,
                                previewID: previewID,
                                component: component,
                                shared: shared
                            ),
                            in: 0...1
                        )
                    }
                }
            case .unsupported(let explanation):
                Text("\(label): \(explanation)")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func integerValue(_ name: String, previewID: String) -> Int {
        if case .integer(let value) = comparison.value(for: name, previewID: previewID) {
            return value
        }
        return 0
    }

    private func integerBinding(_ name: String, previewID: String, shared: Bool) -> Binding<Int> {
        Binding(
            get: { integerValue(name, previewID: previewID) },
            set: {
                if shared { comparison.setSharedValue(.integer($0), for: name) }
                else { comparison.setValue(.integer($0), for: name, previewID: previewID) }
            }
        )
    }

    private func pointBinding(
        _ name: String,
        previewID: String,
        component: Int,
        shared: Bool
    ) -> Binding<Double> {
        Binding(
            get: {
                guard case .point(let x, let y) = comparison.value(for: name, previewID: previewID)
                else { return 0 }
                return component == 0 ? x : y
            },
            set: { newValue in
                var x = 0.0, y = 0.0
                if case .point(let oldX, let oldY) = comparison.value(for: name, previewID: previewID) {
                    x = oldX; y = oldY
                }
                if component == 0 { x = newValue } else { y = newValue }
                if shared { comparison.setSharedValue(.point(x, y), for: name) }
                else { comparison.setValue(.point(x, y), for: name, previewID: previewID) }
            }
        )
    }

    private func colorBinding(
        _ name: String,
        previewID: String,
        component: Int,
        shared: Bool
    ) -> Binding<Double> {
        Binding(
            get: {
                guard case .color(let r, let g, let b, let a) =
                        comparison.value(for: name, previewID: previewID)
                else { return component == 3 ? 1 : 0 }
                return [r, g, b, a][component]
            },
            set: { newValue in
                var values = [0.0, 0.0, 0.0, 1.0]
                if case .color(let r, let g, let b, let a) =
                    comparison.value(for: name, previewID: previewID) {
                    values = [r, g, b, a]
                }
                values[component] = newValue
                let value = RemixParameterValue.color(values[0], values[1], values[2], values[3])
                if shared { comparison.setSharedValue(value, for: name) }
                else { comparison.setValue(value, for: name, previewID: previewID) }
            }
        )
    }
}

private struct RemixCanvasKeyCapture: NSViewRepresentable {
    let active: Bool
    let handler: (String) -> Bool

    func makeNSView(context: Context) -> KeyView {
        KeyView(handler: handler)
    }

    func updateNSView(_ view: KeyView, context: Context) {
        view.handler = handler
        view.active = active
    }

    final class KeyView: NSView {
        var handler: (String) -> Bool
        var active = false
        private var monitor: Any?
        init(handler: @escaping (String) -> Bool) {
            self.handler = handler
            super.init(frame: .zero)
        }
        required init?(coder: NSCoder) { nil }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window != nil, monitor == nil {
                monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                    guard let self,
                          let window = self.window,
                          event.window === window
                    else {
                        return event
                    }
                    let responder = window.firstResponder
                    let isTextInput = responder is NSTextView || responder is NSTextField
                    guard RemixCanvasKeyRouter.shouldHandle(
                        canvasFocusActive: self.active,
                        firstResponderIsTextInput: isTextInput
                    ),
                    let characters = event.charactersIgnoringModifiers,
                    RemixCanvasKeyRouter.command(
                        for: characters,
                        modifiers: event.modifierFlags,
                        canvasFocused: true
                    ) != nil,
                    self.handler(characters)
                    else {
                        return event
                    }
                    return nil
                }
            }
        }

        deinit {
            if let monitor { NSEvent.removeMonitor(monitor) }
        }
    }
}
