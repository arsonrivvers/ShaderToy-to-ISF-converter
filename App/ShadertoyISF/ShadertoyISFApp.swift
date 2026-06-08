import SwiftUI
import ShadertoyISFKit

@main
struct ShadertoyISFApp: App {
    init() {
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
    }

    var body: some Scene {
        WindowGroup { ContentView() }
    }
}
