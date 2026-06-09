import Foundation
import WebKit
import Combine

struct ISFPreviewInput: Identifiable, Equatable {
    let name: String
    let type: String          // "float","bool","color","point2D","long","image","event"
    let defaultValue: Any?
    let min: Any?
    let max: Any?
    let labels: [String]?     // long enum display names
    let values: [Double]?     // long enum underlying values
    var id: String { name }
    static func == (l: ISFPreviewInput, r: ISFPreviewInput) -> Bool { l.name == r.name && l.type == r.type }
}

@MainActor
final class ISFPreviewController: NSObject, ObservableObject, WKScriptMessageHandler, WKNavigationDelegate {
    @Published var compileValid = false
    @Published var compileError: String?
    @Published var compileErrorLine: Int?
    @Published var inputs: [ISFPreviewInput] = []

    let webView: WKWebView
    private var ready = false
    private var pendingISF: String?
    private var pendingRenderSize: String?

    override init() {
        let config = WKWebViewConfiguration()
        webView = WKWebView(frame: .zero, configuration: config)
        super.init()
        webView.configuration.userContentController.add(self, name: "isf")
        webView.navigationDelegate = self
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

    /// Set explicit output dimensions (drives RENDERSIZE + the canvas buffer). Pass nil/nil to fit.
    func setRenderSize(width: Int?, height: Int?) {
        let js: String
        if let w = width, let h = height, w > 0, h > 0 { js = "setRenderSize(\(w), \(h));" }
        else { js = "setRenderSize(0, 0);" }
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
        guard let dict = message.body as? [String: Any], let type = dict["type"] as? String else { return }
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
            compileError = dict["error"] as? String
        default: break
        }
    }
}
