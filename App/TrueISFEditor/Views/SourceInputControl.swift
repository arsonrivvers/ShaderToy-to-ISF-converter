import SwiftUI
import ShadertoyISFKit

/// Per-image-input source picker. Slice 1 offers None + Test Pattern; Slice 2 adds Library.
struct SourceInputControl: View {
    @ObservedObject var router: SourceRouter
    let inputName: String
    @ObservedObject var library: LibraryModel

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(inputName) (image)").font(.caption)
            Menu {
                Button("None") { router.setSelection(.none, for: inputName) }
                Menu("Test Pattern") {
                    ForEach(TestPatternCatalog.all) { p in
                        Button(p.name) { router.setSelection(.testPattern(id: p.id), for: inputName) }
                    }
                }
                Menu("Shader") {
                    ForEach(library.filtered(query: "")) { entry in
                        Button(entry.name) { router.setSelection(.library(url: entry.url), for: inputName) }
                    }
                }
            } label: {
                Text(router.source(for: inputName).displayName)
            }
        }
    }
}
