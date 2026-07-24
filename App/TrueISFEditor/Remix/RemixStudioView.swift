import SwiftUI
import AppKit

/// Layout A: parents bay + controls on top, a streaming child gallery in the center, and a right rail
/// (favorites + lineage breadcrumb). Entirely driven by `RemixStudioModel`.
struct RemixStudioView: View {
    @ObservedObject var model: RemixStudioModel
    /// Resolves a chosen parent source to ISF text (injected at the App level).
    let resolver: RemixParentResolver
    /// Opens a winning child in the main editor (wired to EditorViewModel.loadImported).
    let openInEditor: (String) -> Void
    /// Library entries for the parent picker.
    let libraryEntries: [LibraryEntry]

    @State private var pasteText = ""
    @State private var linkText = ""
    @State private var resolveError: String?
    @State private var showCrossoverSettings = false
    @AppStorage("remixTerminalExpanded") private var terminalExpanded = true

    var body: some View {
        VStack(spacing: 0) {
            parentsBay
            Divider()
            gallery
            Divider()
            terminal
        }
        .frame(minWidth: 900, minHeight: 600)
    }

    // MARK: terminal (live Claude/Codex activity)

    private var terminal: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Button {
                    terminalExpanded.toggle()
                } label: {
                    Image(systemName: terminalExpanded ? "chevron.down" : "chevron.right")
                    Text("Generation terminal")
                }
                .buttonStyle(.borderless)
                Spacer()
                if model.isGenerating {
                    ProgressView().controlSize(.small)
                    Text("\(model.generatingCount) generating · \(model.currentBatch.count - model.generatingCount) done")
                        .font(.caption).foregroundStyle(.secondary)
                } else if !model.currentBatch.isEmpty {
                    Text("idle · \(model.currentBatch.count - model.generatingCount) returned")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(model.transcript.joined(separator: "\n"),
                                                   forType: .string)
                } label: { Image(systemName: "doc.on.doc") }
                .buttonStyle(.borderless)
                .disabled(model.transcript.isEmpty)
                .help("Copy full terminal transcript")
                Text("Claude/Codex · subscription").font(.caption2).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            if terminalExpanded {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 1) {
                            // Stable row ids: `transcriptDropped + offset` — raw offsets shift once
                            // the 2000-line bound starts dropping from the front, breaking identity.
                            ForEach(Array(model.transcript.enumerated())
                                        .map { (id: model.transcriptDropped + $0.offset, line: $0.element) },
                                    id: \.id) { row in
                                Text(row.line)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .id(row.id)
                            }
                            if model.transcript.isEmpty {
                                Text(model.isGenerating ? "Waiting for output…" : "No activity yet — hit Generate.")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .padding(.horizontal, 12).padding(.bottom, 8)
                    }
                    .frame(height: 150)
                    .onChange(of: model.transcript.count) { _ in
                        if let last = model.transcript.indices.last {
                            withAnimation(.linear(duration: 0.1)) {
                                proxy.scrollTo(model.transcriptDropped + last, anchor: .bottom)
                            }
                        }
                    }
                }
            }
        }
        .background(.black.opacity(0.03))
    }

    // MARK: parents bay + controls

    private var parentsBay: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 16) {
                parentSlot("Parent A", id: model.parentAID, slot: .a)
                if model.mode == .crossover { parentSlot("Parent B", id: model.parentBID, slot: .b) }
                Divider().frame(height: 80)
                controls
            }
            sourceRow
            if let resolveError { Text(resolveError).font(.caption).foregroundStyle(.red) }
        }
        .padding(12)
    }

    private func parentSlot(_ title: String, id: String?, slot: ParentSlot) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            ZStack {
                RoundedRectangle(cornerRadius: 8).strokeBorder(.quaternary)
                if let id, let node = model.lineage.node(id) {
                    RemixThumbnailView(isf: node.isfSource, animating: true,
                                       onSnapshot: { img in model.storeSnapshot(id: node.id, image: img) }) { _, _ in }
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    Text("Empty").font(.caption2).foregroundStyle(.tertiary)
                }
            }
            .frame(width: 120, height: 80)
            if id != nil {
                Button("Clear") { model.clearParent(slot) }.font(.caption2).buttonStyle(.link)
            }
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Mode", selection: $model.mode) {
                Text("Crossover").tag(RemixMode.crossover)
                Text("Mutate").tag(RemixMode.mutate)
            }.pickerStyle(.segmented).frame(width: 220)
            TextField("Steer (optional): e.g. 'wavy, neon'", text: $model.steer).frame(width: 280)
            HStack {
                Stepper("Batch: \(model.batchSize)", value: $model.batchSize, in: 1...8).frame(width: 160)
                Button {
                    model.startGeneration()
                } label: { Label("Generate", systemImage: "bolt.fill") }
                .keyboardShortcut(.return, modifiers: [])
                .disabled(!model.canGenerate)
                if model.isGenerating {
                    Button(role: .destructive) {
                        model.cancelGeneration()
                    } label: { Label("Stop", systemImage: "stop.fill") }
                }
                Button { showCrossoverSettings.toggle() } label: { Label("Crossover", systemImage: "gearshape") }
                    .popover(isPresented: $showCrossoverSettings, arrowEdge: .bottom) {
                        RemixCrossoverPopover(model: model)
                    }
            }
            Text(model.crossoverSettings.summary)
                .font(.caption2).foregroundStyle(.secondary)
            if model.isGenerating { ProgressView().controlSize(.small) }
        }
    }

    private var sourceRow: some View {
        HStack(spacing: 8) {
            Menu("Add from Library") {
                ForEach(libraryEntries) { entry in
                    Button(entry.name) { resolveParent(.libraryFile(entry.url)) }
                }
            }.frame(width: 160)
            Button("Use Current Editor") { resolveParent(.currentEditor) }
            TextField("Shadertoy link…", text: $linkText, onCommit: {
                guard !linkText.isEmpty else { return }
                resolveParent(.shadertoyLink(linkText)); linkText = ""
            }).frame(width: 220)
            TextField("Paste ISF…", text: $pasteText, onCommit: {
                guard !pasteText.isEmpty else { return }
                resolveParent(.pastedISF(pasteText)); pasteText = ""
            }).frame(width: 220)
        }
    }

    /// Fills the first empty slot (A, then B for crossover) with the resolved source.
    private func resolveParent(_ spec: ParentSpec) {
        let slot: ParentSlot = (model.parentAID == nil) ? .a
            : (model.mode == .crossover && model.parentBID == nil) ? .b : .a
        let label: String
        switch spec {
        case .libraryFile(let url): label = url.deletingPathExtension().lastPathComponent
        case .currentEditor:        label = "editor"
        case .shadertoyLink:        label = "shadertoy"
        case .pastedISF:            label = "pasted"
        }
        Task {
            do {
                let isf = try await resolver.resolve(spec)
                model.setParent(slot, isf: isf, label: label)
                resolveError = nil
            } catch { resolveError = "Couldn't load parent: \(error)" }
        }
    }

    // MARK: gallery

    private let columns = [GridItem(.adaptive(minimum: 180), spacing: 12)]

    private var gallery: some View {
        HStack(spacing: 0) {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(model.currentBatch) { node in childCard(node) }
                }.padding(12)
            }
            Divider()
            RemixLineageTreeView(model: model, openInEditor: openInEditor).frame(width: 260)
        }
    }

    private func childCard(_ node: RemixNode) -> some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(.black.opacity(0.05))
                switch node.status {
                case .generating:
                    ProgressView().controlSize(.small)
                case .interrupted:
                    VStack {
                        Image(systemName: "pause.circle")
                        Text("Interrupted").font(.caption2)
                    }
                    .foregroundStyle(.secondary)
                case .failed(let msg):
                    VStack { Image(systemName: "exclamationmark.triangle"); Text(msg).font(.caption2).lineLimit(2) }
                        .foregroundStyle(.orange).padding(4)
                case .compiled:
                    RemixThumbnailView(isf: node.isfSource, animating: model.shouldAnimate(node.id),
                                       onSnapshot: { img in model.storeSnapshot(id: node.id, image: img) }) { valid, err in
                        model.markCompileResult(id: node.id, valid: valid, error: err)
                    }.clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
            .frame(height: 130)
            HStack(spacing: 10) {
                Button { model.toggleFavorite(node.id) } label: {
                    Image(systemName: model.lineage.isFavorite(node.id) ? "star.fill" : "star")
                }.help("Favorite")
                Button { model.promoteToParent(.a, nodeID: node.id) } label: {
                    Image(systemName: "arrow.up.circle")
                }.help("Promote to Parent A")
                Button { openInEditor(node.isfSource) } label: {
                    Image(systemName: "square.and.pencil")
                }.help("Open in editor")
            }
            .buttonStyle(.borderless)
            Text(node.directive).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 10).fill(.background).shadow(radius: 1))
    }
}
