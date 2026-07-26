import SwiftUI

struct RemixWorkspaceView: View {
    @ObservedObject var model: RemixStudioModel
    let resolver: RemixParentResolver
    let openInEditor: (String) -> Void
    let libraryEntries: [LibraryEntry]
    let currentEditorLabel: String

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @AccessibilityFocusState private var focusedControl: RemixWorkspaceFocusToken?
    @State private var dragStartWidths: [RemixZone: Double] = [:]
    @State private var focusModeActive = false

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            GeometryReader { geometry in
                HStack(spacing: 0) {
                    if model.workspace.collapsedZones.contains(.breedingBay) {
                        reopenButton(.breedingBay)
                    } else {
                        RemixBreedingBayView(
                            model: model,
                            resolver: resolver,
                            libraryEntries: libraryEntries,
                            currentEditorLabel: currentEditorLabel
                        )
                        .frame(width: width(.breedingBay))
                        .background(zoneBackground)
                        zoneDivider(.breedingBay)
                    }

                    childrenCanvas
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(zoneBackground)

                    if model.workspace.collapsedZones.contains(.lineage) {
                        reopenButton(.lineage)
                    } else {
                        zoneDivider(.lineage, reversed: true)
                        RemixLineageTreeView(model: model, openInEditor: openInEditor)
                            .frame(width: width(.lineage))
                            .background(zoneBackground)
                            .accessibilityElement(children: .contain)
                            .accessibilityLabel("Lineage Inspector")
                            .accessibilitySortPriority(1)
                    }
                }
                .onAppear {
                    applyNarrowLayout(width: geometry.size.width)
                }
                .onChange(of: geometry.size.width) { newWidth in
                    applyNarrowLayout(width: newWidth)
                }
            }
        }
        .font(RemixTextPolicy.bodyFont)
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            if !model.workspace.collapsedZones.contains(.breedingBay) {
                Button("Collapse Breeding Bay") {
                    collapse(.breedingBay)
                }
                .accessibilityFocused($focusedControl, equals: .collapseZone(.breedingBay))
                resizeMenu(.breedingBay)
            }
            if !model.workspace.collapsedZones.contains(.lineage) {
                Button("Collapse Lineage") {
                    collapse(.lineage)
                }
                .accessibilityFocused($focusedControl, equals: .collapseZone(.lineage))
                resizeMenu(.lineage)
            }
            Button(focusModeActive ? "Exit Focus Canvas" : "Focus Canvas") {
                if focusModeActive {
                    model.workspace.exitFocusMode()
                } else {
                    model.workspace.enterFocusMode()
                }
                focusModeActive.toggle()
                focusedControl = .canvas
            }
            Button("Reset Layout") {
                RemixBreedingBayPresentation.resetLayout(&model.workspace)
                focusModeActive = false
                focusedControl = .canvas
            }
            Spacer()
            Text(model.activity.summary.compactStatus)
                .font(RemixAccessibleTextLayout.bodyFont)
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(.secondary)
                .accessibilityLabel(model.activity.summary.accessibilityAnnouncement)
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 48)
    }

    private var childrenCanvas: some View {
        RemixChildrenCanvasView(model: model, openInEditor: openInEditor)
        .accessibilitySortPriority(2)
        .accessibilityFocused($focusedControl, equals: .canvas)
    }

    private func resizeMenu(_ zone: RemixZone) -> some View {
        Menu("Resize \(zoneName(zone)) (\(Int(width(zone).rounded())) pt)") {
            Button("Decrease width by 20 points") {
                resize(zone, direction: -1)
            }
            Button("Increase width by 20 points") {
                resize(zone, direction: 1)
            }
        }
        .accessibilityValue(RemixBreedingBayPresentation.resizeValueDescription(
            zone: zone,
            width: width(zone)
        ))
    }

    private func reopenButton(_ zone: RemixZone) -> some View {
        Button("Reopen \(zoneName(zone))") {
            model.workspace.expand(zone)
            focusedControl = .collapseZone(zone)
        }
        .padding(8)
        .accessibilityFocused($focusedControl, equals: .reopenZone(zone))
    }

    private func zoneDivider(_ zone: RemixZone, reversed: Bool = false) -> some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.35))
            .frame(width: 8)
            .contentShape(Rectangle())
            .accessibilityHidden(true)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let start = dragStartWidths[zone] ?? width(zone)
                        dragStartWidths[zone] = start
                        let delta = Double(value.translation.width) * (reversed ? -1 : 1)
                        var layout = RemixSplitLayout(state: model.workspace)
                        layout.recordPointerWidth(start + delta, zone: zone)
                        model.workspace = layout.state
                    }
                    .onEnded { _ in dragStartWidths[zone] = nil }
            )
    }

    private var zoneBackground: some ShapeStyle {
        reduceTransparency
            ? AnyShapeStyle(Color(nsColor: .windowBackgroundColor))
            : AnyShapeStyle(.ultraThinMaterial)
    }

    private func width(_ zone: RemixZone) -> Double {
        RemixSplitLayout(state: model.workspace).appliedWidth(for: zone)
    }

    private func resize(_ zone: RemixZone, direction: Int) {
        var layout = RemixSplitLayout(state: model.workspace)
        layout.resizeByKeyboard(zone, direction: direction)
        model.workspace = layout.state
    }

    private func collapse(_ zone: RemixZone) {
        model.workspace.collapse(zone)
        focusedControl = .reopenZone(zone)
    }

    private func applyNarrowLayout(width: Double) {
        let previous = model.workspace.collapsedZones
        model.workspace.applyNarrowLayout(availableWidth: width)
        if !previous.contains(.lineage), model.workspace.collapsedZones.contains(.lineage) {
            focusedControl = .reopenZone(.lineage)
        } else if !previous.contains(.breedingBay),
                  model.workspace.collapsedZones.contains(.breedingBay) {
            focusedControl = .reopenZone(.breedingBay)
        }
    }

    private func zoneName(_ zone: RemixZone) -> String {
        switch zone {
        case .breedingBay: return "Breeding Bay"
        case .lineage: return "Lineage"
        case .activity: return "Activity"
        }
    }

}
