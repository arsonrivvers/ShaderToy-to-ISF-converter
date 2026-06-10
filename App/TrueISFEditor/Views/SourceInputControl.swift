import SwiftUI
import ShadertoyISFKit

/// Per-image-input source picker. Slice 1 offers None + Test Pattern; Library and Camera are
/// added in later slices.
struct SourceInputControl: View {
    @ObservedObject var router: SourceRouter
    let inputName: String

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
            } label: {
                Text(router.source(for: inputName).displayName)
            }
        }
    }
}
