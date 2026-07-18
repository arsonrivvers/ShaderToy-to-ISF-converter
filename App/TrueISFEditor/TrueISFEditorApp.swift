import SwiftUI
import ShadertoyISFKit
import UniformTypeIdentifiers

@main
struct TrueISFEditorApp: App {
    @NSApplicationDelegateAdaptor(AppQuitGuard.self) private var quitGuard
    @StateObject private var library = LibraryModel()
    @StateObject private var vm = EditorViewModel()
    @StateObject private var settings = SettingsStore()
    @StateObject private var remixModel = RemixStudioModel(
        generator: RemixGenerator(
            makeProvider: { AssistProviderFactory.make(kind: AssistProviderSelection.current().kind) },
            modelProvider: { AssistProviderSelection.current().model }
        )
    )

    init() {
        // Best-effort crash capture; accessing CrashLog.shared also ingests any crash from last session.
        let pendingURL = MainActor.assumeIsolated { CrashLog.shared.pendingURL }
        CrashReporter.install(pendingURL: pendingURL)

        // Debug-only headless harnesses (fetch / preview / ISFMSL / corpus). Compiled out of
        // release builds: a shipped app that silently fetches-and-exits on an env var is surprise
        // behavior, and the raw ids here bypass the ShadertoyURL validator (CSO N9/N11). The
        // corpus scripts build Debug, so `scripts/corpus-run.sh` keeps working.
        #if DEBUG
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
                    out = "ERROR (\(id)): \(error)\nlastTitle=\(fetcher.lastTitle)\nlastURL=\(fetcher.lastURL)\nstatus=\(fetcher.lastResponseStatus)\nresp=\(fetcher.lastResponseBody)"
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

                // Give the harness a generous startup window (loads are queued until "ready").
                try? await Task.sleep(nanoseconds: 3_000_000_000)

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

        // Headless debug affordance: `SHADERTOY_DEBUG_ISFMSL=<path-to-.fs>` compiles that ISF
        // file through the real Metal/ISFMSLKit preview path and prints the compile result —
        // used to verify GLSL→MSL transpile fixes (e.g. extension/polyfill handling) without UI.
        if let isfPath = ProcessInfo.processInfo.environment["SHADERTOY_DEBUG_ISFMSL"], !isfPath.isEmpty {
            Task { @MainActor in
                let src = (try? String(contentsOfFile: isfPath, encoding: .utf8)) ?? ""
                let controller = MetalPreviewController()
                controller.load(isf: src)
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                print("=== DEBUG ISFMSL ===")
                print("path=\(isfPath)")
                print("compileValid=\(controller.compileValid)")
                print("compileError=\(controller.compileError ?? "nil")")
                print("=== END ===")
                exit(0)
            }
        }

        // Headless conversion-conformance harness: `SHADERTOY_DEBUG_CORPUS=<ids-file>` reads one
        // Shadertoy ID per line, fetches+converts+transpiles each through the real ISFMSLKit path,
        // and prints a pass/fail report bucketed by error. With `SHADERTOY_DEBUG_CORPUS_OUT=<dir>`
        // it also writes each raw /shadertoy JSON to <dir>/<id>.json (to seed regression fixtures).
        // This is the proactive net that replaces one-shader-at-a-time bug reports.
        if let idsPath = ProcessInfo.processInfo.environment["SHADERTOY_DEBUG_CORPUS"], !idsPath.isEmpty {
            let outDir = ProcessInfo.processInfo.environment["SHADERTOY_DEBUG_CORPUS_OUT"]
            Task { @MainActor in
                let fetcher = WebKitShaderFetcher()
                // `SHADERTOY_DEBUG_CORPUS=browse:<sort>:<count>` harvests real popular IDs from the
                // Shadertoy results page instead of reading a file (no ID-guessing).
                var ids: [String]
                if idsPath.hasPrefix("browse:") {
                    // `browse:<anything>:<count>` — the middle segment is legacy (the browse SPA
                    // renders its default popular grid; a sort param was never honored).
                    let parts = idsPath.split(separator: ":").map(String.init)
                    let count = parts.count > 2 ? (Int(parts[2]) ?? 60) : 60
                    ids = await fetcher.harvestShaderIDs(count: count)
                    print("HARVESTED \(ids.count) ids: \(ids.joined(separator: ","))")
                } else {
                    ids = ((try? String(contentsOfFile: idsPath, encoding: .utf8)) ?? "")
                        .split(whereSeparator: \.isNewline)
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty && !$0.hasPrefix("#") }
                }
                let preview = MetalPreviewController()
                var lines: [String] = []
                for id in ids {
                    // Bind the fetched shader via `if let` (its type is inferred — naming the type
                    // is ambiguous because a second linked module also exports `Shader`).
                    var line: String? = nil
                    for _ in 0..<3 {
                        guard let s = try? await fetcher.fetchShader(id: id) else { continue }
                        if let outDir { try? fetcher.lastResponseBody.write(toFile: outDir + "/\(id).json", atomically: true, encoding: .utf8) }
                        let (doc, warnings) = ISFConverter.convert(s)
                        preview.load(isf: doc.fileText)
                        var valid = false; var err: String? = nil
                        for _ in 0..<400 {
                            if preview.compileValid { valid = true; break }
                            if let e = preview.compileError { err = e; break }
                            try? await Task.sleep(nanoseconds: 50_000_000)
                        }
                        if valid {
                            // Pixel-truth gate: a compile-clean conversion can still render
                            // black/NaN (the C5/M1/M2 class) — render 3 frames and look.
                            let gateTimes = PixelGate.parseTimes(
                                ProcessInfo.processInfo.environment["SHADERTOY_DEBUG_GATE_TIMES"])
                            let pixel = gateTimes.map { preview.runPixelGate(times: $0) }
                                ?? preview.runPixelGate()
                            line = pixel.isFail
                                ? "\(id)\tFAIL\tpixel=\(pixel.rawValue)"
                                : "\(id)\tOK\tpixel=\(pixel.rawValue)\twarnings=\(warnings.count)"
                        } else {
                            line = "\(id)\tFAIL\t\((err ?? "timeout").split(separator: "\n").first.map(String.init) ?? "")"
                        }
                        break
                    }
                    let resolved = line ?? "\(id)\tFETCH-FAIL"
                    lines.append(resolved); print(resolved)
                }
                let compileOK = lines.filter { $0.contains("\tOK\t") || $0.contains("\tFAIL\tpixel=") }.count
                let pixelOK = lines.filter { $0.contains("\tOK\t") }.count
                let report = "=== CORPUS compile \(compileOK)/\(ids.count) · pixel \(pixelOK)/\(ids.count) OK ===\n"
                    + lines.joined(separator: "\n")
                let outPath = NSTemporaryDirectory() + "conversion-corpus-report.txt"
                try? report.write(toFile: outPath, atomically: true, encoding: .utf8)
                print(report)
                print("report: \(outPath)")
                exit(0)
            }
        }
        #endif

        // A2: quit guard closures capture the StateObject's wrapped instance; safe — both
        // outlive the app run. canReplaceDocument() runs the standard discard-confirm alert.
        let vmRef = _vm.wrappedValue
        quitGuard.hasUnsavedChanges = { MainActor.assumeIsolated { vmRef.file.isDirty } }
        quitGuard.confirmDiscard = { MainActor.assumeIsolated { vmRef.canReplaceDocument() } }
    }

    var body: some Scene {
        // `Window`, not `WindowGroup`: the editor binds app-singleton NSViews (editor webView,
        // preview nsView) that can only live in one hierarchy — WindowGroup's default ⌘N "New
        // Window" made two windows steal them back and forth.
        Window("TrueISFEditor", id: "main") {
            EditorScreen(library: library, vm: vm)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New") { vm.newUntitled() }
                    .keyboardShortcut("n")
                Button("New from Shadertoy…") { vm.requestImport = true }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
                Menu("Open Example") {
                    ForEach(TestPatternCatalog.all) { pattern in
                        Button(pattern.name) {
                            vm.loadExample(name: pattern.name, source: pattern.sourceText)
                        }
                    }
                }
                Menu("New from Template") {
                    ForEach(TemplateCatalog.all) { t in
                        Button(t.name) { vm.loadExample(name: t.name, source: t.sourceText) }
                    }
                }
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
                Button("Versions…") { vm.requestVersions = true }
                    .keyboardShortcut("v", modifiers: [.command, .option])
            }
            CommandGroup(after: .windowArrangement) {
                CrashLogMenuButton()
                ImportLogMenuButton()
            }
            CommandGroup(after: .sidebar) {
                EditorCollapseMenuButton()
            }
        }
        Window("Crash Log", id: "crash-log") {
            CrashLogView()
        }
        Window("Import Log", id: "import-log") {
            ImportLogView()
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
        Settings { SettingsView(store: settings) }
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

/// A2: ⌘Q guard. SwiftUI Window scenes have no native terminate hook; this delegate asks the
/// EditorViewModel (via closures, set in the App init) whether edits would be lost.
final class AppQuitGuard: NSObject, NSApplicationDelegate {
    var hasUnsavedChanges: () -> Bool = { false }
    var confirmDiscard: () -> Bool = { true }

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Headless test mode: the host must not present as a foreground app — no dock icon,
        // no activation, no stealing focus from whatever the user is doing during suite runs.
        if TestHarness.isActive { NSApp.setActivationPolicy(.accessory) }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard TestHarness.isActive else { return }
        // SwiftUI orders the main Window in after launch completes; hide it one runloop later.
        DispatchQueue.main.async {
            NSApp.windows.forEach { $0.orderOut(nil) }
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // Headless test mode: XCTest terminates the host after every suite run — a discard
        // modal here blocks the harness until it kills the host (and pops on the user's screen).
        if TestHarness.isActive { return .terminateNow }
        guard hasUnsavedChanges() else { return .terminateNow }
        return confirmDiscard() ? .terminateNow : .terminateCancel
    }
}
