import SwiftUI
import ShadertoyISFKit

/// Per-image-input source picker for the preview toolbar. Renders one compact menu per image input
/// on the current filter (nothing for generators). Test Pattern + Library now; Camera in Slice 3.
struct SourceToolbarControl: View {
    @ObservedObject var router: SourceRouter
    @ObservedObject var library: LibraryModel

    var body: some View {
        ForEach(router.imageInputNames, id: \.self) { name in
            Menu {
                Button("None") { router.setSelection(.none, for: name) }
                Menu("Test Pattern") {
                    ForEach(TestPatternCatalog.all) { p in
                        Button(p.name) { router.setSelection(.testPattern(id: p.id), for: name) }
                    }
                }
                Menu("Shader") {
                    ForEach(library.filtered(query: "")) { entry in
                        Button(entry.name) { router.setSelection(.library(url: entry.url), for: name) }
                    }
                }
            } label: {
                Label(labelText(for: name), systemImage: "photo.on.rectangle")
            }
            .fixedSize()
            .help("Input source for “\(name)”")
        }
    }

    private func labelText(for name: String) -> String {
        let source = router.source(for: name).displayName
        return router.imageInputNames.count > 1 ? "\(name): \(source)" : source
    }
}
