import SwiftUI
import ShadertoyISFKit
import UniformTypeIdentifiers

@main
struct TrueISFEditorApp: App {
    @StateObject private var library = LibraryModel()
    @StateObject private var vm = EditorViewModel()
    @StateObject private var settingsModel = AppModel()
    @StateObject private var remixModel = RemixStudioModel(
        generator: RemixGenerator(
            makeProvider: {
                switch AssistProviderSelection.current().kind {
                case .claude:
                    return ClaudeCodeRunner(binary: ClaudeCodeRunner.locateBinary(
                        override: UserDefaults.standard.string(forKey: "claudeBinaryPath")))
                case .codex:
                    return CodexRunner(binary: CodexRunner.locateBinary(
                        override: UserDefaults.standard.string(forKey: "codexBinaryPath")))
                }
            },
            modelProvider: { AssistProviderSelection.current().model }
        )
    )

    init() {
        // Best-effort crash capture; accessing CrashLog.shared also ingests any crash from last session.
        let pendingURL = MainActor.assumeIsolated { CrashLog.shared.pendingURL }
        CrashReporter.install(pendingURL: pendingURL)

        // Headless debug affordance: `SHADERTOY_DEBUG_FETCH=<id>` fetches + converts that
        // shader, prints the .fs to stdout, and exits — no UI. Used to verify the WKWebView
        // fetch path in the real (entitled, sandboxed) app context. No effect in normal use.
        let args = ProcessInfo.processInfo.arguments
        let argID = args.firstIndex(of: "--debug-fetch").flatMap { i in i + 1 < args.count ? args[i + 1] : nil }
        let debugID = ProcessInfo.processInfo.environment["SHADERTOY_DEBUG_FETCH"] ?? argID
        if let id = debugID, !id.isEmpty {
            let outPath = NSTemporaryDirectory() + "shadertoy_debug.txt"
            Task { @MainActor in
                let fetcher = WebKitShaderFetcher()
                var out: String
                do {
                    let shader = try await fetcher.fetchShader(id: id)
                    let (doc, warnings) = ISFConverter.convert(shader)
                    out = "OK: \(id) — \(shader.info.name) — \(shader.renderpass.count) pass(es), \(warnings.count) warning(s)\n\n" + doc.fileText
                } catch {
                    out = "ERROR (\(id)): \(error)\nlastTitle=\(fetcher.lastTitle)\nlastURL=\(fetcher.lastURL)\nbody=\(fetcher.lastBody)"
                }
                try? out.write(toFile: outPath, atomically: true, encoding: .utf8)
                print("=== DEBUG FETCH ===\n\(out)\n=== END ===")
                exit(0)
            }
        }

        // Headless debug affordance: `SHADERTOY_DEBUG_PREVIEW=1` instantiates an
        // WebKitPreviewController, loads a known-good ISF and a known-bad ISF (tanh without
        // polyfill), prints the compile results from the WKWebView harness, and exits.
        // Used to verify the preview pipeline in the real entitled app — WebGL only works
        // in the real binary, not in bare xctest.
        if ProcessInfo.processInfo.environment["SHADERTOY_DEBUG_PREVIEW"] == "1" {
            Task { @MainActor in
                // Build a known-good ISF using the converter
                let goodShader = ShaderFactory.singlePass(
                    imageCode: "void mainImage(out vec4 O, vec2 I){ O = vec4(I/iResolution.xy, 0.0, 1.0); }",
                    name: "DebugGood"
                )
                let (goodDoc, _) = ISFConverter.convert(goodShader)
                let goodISF = goodDoc.fileText

                // Known-bad ISF: raw ISF with tanh and NO polyfill so GLSL ES will reject it
                let badISF = """
/*{
  "ISFVSN": "2",
  "DESCRIPTION": "debug bad shader",
  "INPUTS": []
}*/
void main() {
    vec4 v = tanh(vec4(0.5));
    gl_FragColor = v;
}
"""

                let controller = WebKitPreviewController()

                // Wait for harness to become ready (poll up to 5s)
                var waited = 0
                while waited < 50 {
                    try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
                    waited += 1
                    // Once ready, the controller will have processed the "ready" message
                    // We detect readiness via a brief extra sleep after first check
                    if waited == 5 { break }
                }
                // Give the harness a generous startup window
                try? await Task.sleep(nanoseconds: 2_500_000_000) // 2.5s

                print("=== DEBUG PREVIEW: loading good ISF ===")
                controller.load(isf: goodISF)
                try? await Task.sleep(nanoseconds: 2_000_000_000) // 2s to compile + report
                print("GOOD ISF — compileValid=\(controller.compileValid) compileError=\(controller.compileError ?? "nil") inputs=\(controller.inputs.count)")

                print("=== DEBUG PREVIEW: loading bad ISF (tanh, no polyfill) ===")
                controller.load(isf: badISF)
                try? await Task.sleep(nanoseconds: 2_000_000_000) // 2s to compile + report
                print("BAD ISF  — compileValid=\(controller.compileValid) compileError=\(controller.compileError ?? "nil")")

                print("=== DEBUG PREVIEW END ===")
                exit(0)
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            EditorScreen(library: library, vm: vm)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New") { vm.newUntitled() }
                    .keyboardShortcut("n")
                Button("New from Shadertoy…") { vm.requestImport = true }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
                Divider()
                RemixMenuButton()
                Divider()
                Button("Add Folder to Library…") { addFolderToLibrary() }
                    .keyboardShortcut("o")
            }
            CommandGroup(replacing: .saveItem) {
                Button("Save") { saveCurrent() }
                    .keyboardShortcut("s")
                Button("Save As…") { saveAs() }
                    .keyboardShortcut("s", modifiers: [.command, .shift])
            }
            CommandGroup(after: .windowArrangement) {
                CrashLogMenuButton()
            }
            CommandGroup(after: .sidebar) {
                EditorCollapseMenuButton()
            }
        }
        Window("Crash Log", id: "crash-log") {
            CrashLogView()
        }
        Window("ISF Remix Studio", id: "remix-studio") {
            RemixStudioView(
                model: remixModel,
                resolver: RemixParentResolver(
                    currentEditorSource: { vm.file.source },
                    fetchShadertoy: RemixParentResolver.liveFetch(
                        apiKey: { KeychainStore.load() ?? "" })   // same source the importer uses
                ),
                openInEditor: { isf in
                    vm.loadImported(isf: isf, warnings: [], suggestedName: "Remixed shader")
                },
                libraryEntries: library.filtered(query: "")
            )
        }
        Settings { SettingsView(model: settingsModel) }
    }

    @MainActor private func saveCurrent() {
        if vm.needsSaveAs { saveAs() } else { vm.saveInPlace() }
    }

    @MainActor private func saveAs() {
        let panel = NSSavePanel()
        panel.title = "Save ISF Shader"
        panel.nameFieldStringValue = vm.file.displayName
        panel.canCreateDirectories = true
        if let fsType = UTType(filenameExtension: "fs") { panel.allowedContentTypes = [fsType] }
        if panel.runModal() == .OK, let url = panel.url { vm.saveAs(url) }
    }

    @MainActor private func addFolderToLibrary() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Add Folder"
        if panel.runModal() == .OK, let url = panel.url { library.addFolder(url) }
    }
}
