import SwiftUI

/// Composition root for the persistent, accessible Remix Studio workspace.
struct RemixStudioView: View {
    @ObservedObject var model: RemixStudioModel
    let resolver: RemixParentResolver
    let openInEditor: (String) -> Void
    let libraryEntries: [LibraryEntry]
    let currentEditorLabel: String

    var body: some View {
        RemixWorkspaceView(
            model: model,
            resolver: resolver,
            openInEditor: openInEditor,
            libraryEntries: libraryEntries,
            currentEditorLabel: currentEditorLabel
        )
        .frame(minWidth: 720, minHeight: 600)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Remix Studio")
    }
}
