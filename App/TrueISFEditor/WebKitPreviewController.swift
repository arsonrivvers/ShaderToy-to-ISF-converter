import Foundation
import AppKit
import WebKit
import Combine
import VVMetalKit

@MainActor
final class WebKitPreviewController: NSObject, ObservableObject, WKScriptMessageHandler, PreviewEngine {
    @Published var compileValid = false
    @Published var compileError: String?
    @Published var compileErrorLine: Int?
    @Published var inputs: [ISFPreviewInput] = []

    var nsView: NSView { webView }
    var compileStateWillChange: ObservableObjectPublisher { objectWillChange }

    /// Inert here — WebKit cannot bind image textures. Present only to satisfy PreviewEngine; never
    /// receives `updateInputs`/`setSelection`, so it stays empty.
    let imageSources: SourceRouter = {
        let p = RenderProperties.global()
        return SourceRouter(device: p.device, queue: p.renderQueue)
    }()

    let webView: WKWebView
    private var ready = false
    private var pendingISF: String?
    private var pendingRenderSize: String?

    override init() {
        let config = WKWebViewConfiguration()
        webView = WKWebView(frame: .zero, configuration: config)
        super.init()
        webView.configuration.userContentController.add(self, name: "isf")
        if let url = Bundle.main.url(forResource: "isf-preview", withExtension: "html") {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        }
    }

    /// Render an ISF source string. Queues until the harness reports ready.
    func load(isf: String) {
        guard ready else { pendingISF = isf; return }
        guard let lit = jsStringLiteral(isf) else { return }
        webView.evaluateJavaScript("loadISF(\(lit));", completionHandler: nil)
    }

    func setInput(_ name: String, _ jsonValue: String) {
        guard let nameLit = jsStringLiteral(name) else { return }
        webView.evaluateJavaScript("setInput(\(nameLit), \(jsonValue));", completionHandler: nil)
    }

    /// Set output dimensions (drives RENDERSIZE + the canvas buffer). `fitToWindow` ⇒ the WebGL
    /// harness fits to the canvas (0,0 sentinel); otherwise render at exactly width×height.
    func setRenderSize(width: Int, height: Int, fitToWindow: Bool) {
        let js: String
        if fitToWindow { js = "setRenderSize(0, 0);" }
        else { js = "setRenderSize(\(max(width, 1)), \(max(height, 1)));" }
        guard ready else { pendingRenderSize = js; return }
        webView.evaluateJavaScript(js, completionHandler: nil)
    }

    private func jsStringLiteral(_ s: String) -> String? {
        // JSONEncoder turns a String into a valid, fully-escaped JS string literal.
        guard let data = try? JSONEncoder().encode(s) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // MARK: WKScriptMessageHandler
    func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage) {
        handleScriptMessage(message.body)
    }

    /// Split from the delegate method so tests can drive it (WKScriptMessage isn't constructible).
    func handleScriptMessage(_ body: Any) {
        guard let dict = body as? [String: Any], let type = dict["type"] as? String else { return }
        switch type {
        case "ready":
            ready = true
            if let s = pendingRenderSize { pendingRenderSize = nil; webView.evaluateJavaScript(s, completionHandler: nil) }
            if let p = pendingISF { pendingISF = nil; load(isf: p) }
        case "compile":
            compileValid = (dict["valid"] as? Bool) ?? false
            compileError = dict["error"] as? String
            compileErrorLine = dict["errorLine"] as? Int
            inputs = (dict["inputs"] as? [[String: Any]])?.map {
                ISFPreviewInput(name: $0["NAME"] as? String ?? "",
                                type: $0["TYPE"] as? String ?? "",
                                defaultValue: $0["DEFAULT"], min: $0["MIN"], max: $0["MAX"],
                                labels: $0["LABELS"] as? [String],
                                values: ($0["VALUES"] as? [Any])?.compactMap { ($0 as? NSNumber)?.doubleValue })
            } ?? []
        case "runtime":
            // Route through the same path the diagnostics pipeline reads: EditorViewModel maps
            // compileError to the gutter only when compileValid is false — leaving it true showed
            // a broken render with "No diagnostics".
            compileError = dict["error"] as? String
            compileValid = false
        default: break
        }
    }
}
