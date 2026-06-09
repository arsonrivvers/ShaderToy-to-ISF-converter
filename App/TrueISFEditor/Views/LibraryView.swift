import SwiftUI

/// File-library sidebar: a focused filter field over `.fs` files grouped by source.
/// Single-click loads; a dirty dot marks the open file when unsaved.
struct LibraryView: View {
    @ObservedObject var library: LibraryModel
    @ObservedObject var vm: EditorViewModel
    var addFolder: () -> Void

    @State private var query = ""
    @State private var selection: URL?
    @FocusState private var filterFocused: Bool

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                TextField("Filter…", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .focused($filterFocused)
                Button(action: addFolder) { Image(systemName: "folder.badge.plus") }
                    .help("Add a folder of .fs files")
            }
            .padding(.horizontal, 6)
            .padding(.top, 6)

            List(selection: $selection) {
                if query.isEmpty {
                    ForEach(library.sources) { src in
                        Section("\(src.title) (\(library.entries(for: src).count))") {
                            ForEach(library.entries(for: src)) { row($0) }
                        }
                    }
                } else {
                    Section("Results") {
                        ForEach(library.filtered(query: query)) { row($0) }
                    }
                }
            }
            .onChange(of: selection) { sel in
                guard let sel, let entry = entry(for: sel) else { return }
                vm.open(entry)
            }
        }
        .onAppear { filterFocused = true }
    }

    @ViewBuilder private func row(_ entry: LibraryEntry) -> some View {
        HStack {
            Text(entry.name).lineLimit(1).truncationMode(.middle)
            Spacer()
            if entry.url == vm.file.url, vm.file.isDirty {
                Circle().fill(Color.secondary).frame(width: 6, height: 6)
            }
        }
        .tag(entry.url)
    }

    private func entry(for url: URL) -> LibraryEntry? {
        library.sources.lazy.flatMap { library.entries(for: $0) }.first { $0.url == url }
    }
}
