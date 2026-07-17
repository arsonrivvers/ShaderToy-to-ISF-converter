import SwiftUI
import WebKit

/// One inline editor diagnostic (1-based line). Encoded straight to the harness's setDiagnostics.
struct EditorDiagnostic: Codable, Equatable {
    let line: Int
    let message: String
    let severity: String   // "error" | "warning" | "info"
}

/// Owns the WKWebView hosting CodeMirror 6 and bridges text + diagnostics to/from Swift.
/// Mirrors `WebKitPreviewController`'s ready-gating + message-handler pattern.
@MainActor
final class CodeEditorController: NSObject, ObservableObject, WKScriptMessageHandler {
    let webView: WKWebView
    /// Called when the user edits in the editor (not when text is pushed programmatically).
    var onChange: ((String) -> Void)?

    private var ready = false
    private var initialized = false
    private var lastText = ""                       // text currently believed to be in the editor
    private var pendingDiagnostics: [EditorDiagnostic]?
    private var inputNames: [String] = []           // declared input names for autocomplete

    override init() {
        let config = WKWebViewConfiguration()
        webView = WKWebView(frame: .zero, configuration: config)
        super.init()
        webView.configuration.userContentController.add(self, name: "editor")
        if let url = Bundle.main.url(forResource: "code-editor", withExtension: "html") {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        }
    }

    /// Replace the editor's document. No-op echo: the harness suppresses the resulting change post.
    func setText(_ text: String) {
        lastText = text
        guard ready, initialized, let lit = jsStringLiteral(text) else { return }
        webView.evaluateJavaScript("setText(\(lit));")
    }

    /// Replace the document AND drop undo history — for document switches, where ⌘Z must not
    /// restore the previous file's content into the new one (data-corruption class A1).
    private(set) var lastResetTextForTest: String?
    func resetText(_ text: String) {
        lastText = text
        lastResetTextForTest = text
        guard ready, initialized, let lit = jsStringLiteral(text) else { return }
        webView.evaluateJavaScript("resetDocument(\(lit));")
    }

    func setDiagnostics(_ diags: [EditorDiagnostic]) {
        guard ready, initialized else { pendingDiagnostics = diags; return }
        guard let data = try? JSONEncoder().encode(diags),
              let json = String(data: data, encoding: .utf8) else { return }
        webView.evaluateJavaScript("setDiagnostics(\(json));")
    }

    /// Move the editor cursor to a 1-based line and scroll it into view (click-to-jump).
    func revealLine(_ line: Int) {
        guard ready, initialized else { return }
        webView.evaluateJavaScript("revealLine(\(line));")
    }

    /// Replace 1-based lines [fromLine...toLine] with `replacement` (one-click fix apply).
    /// Goes through CodeMirror so undo works and onChange fires → recompile.
    func applyTextEdit(fromLine: Int, toLine: Int, _ replacement: String) {
        guard ready, initialized, let lit = jsStringLiteral(replacement) else { return }
        webView.evaluateJavaScript("applyTextEdit(\(fromLine), \(toLine), \(lit));")
    }

    /// Push the shader's declared input names so autocomplete offers the shader's own uniforms.
    /// Stored and re-pushed on (re)init since names change as the header is edited.
    func setInputNames(_ names: [String]) {
        inputNames = names
        pushInputNames()
    }

    private func pushInputNames() {
        guard ready, initialized,
              let data = try? JSONEncoder().encode(inputNames),
              let json = String(data: data, encoding: .utf8) else { return }
        webView.evaluateJavaScript("setInputNames(\(json));")
    }

    /// Load the bundled symbol DB into the editor for inline hover lookups.
    private func pushSymbols() {
        guard let url = Bundle.main.url(forResource: "symbols", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let json = String(data: data, encoding: .utf8) else { return }
        webView.evaluateJavaScript("setSymbols(\(json));")
    }

    private func jsStringLiteral(_ s: String) -> String? {
        guard let data = try? JSONEncoder().encode(s) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // MARK: WKScriptMessageHandler
    func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let dict = message.body as? [String: Any], let type = dict["type"] as? String else { return }
        switch type {
        case "ready":
            ready = true
            // Create the editor once, seeded with whatever text we have so far.
            if let lit = jsStringLiteral(lastText) {
                webView.evaluateJavaScript("initEditor(\(lit));") { [weak self] _, _ in
                    self?.initialized = true
                    self?.pushSymbols()
                    self?.pushInputNames()
                    if let p = self?.pendingDiagnostics { self?.pendingDiagnostics = nil; self?.setDiagnostics(p) }
                }
            }
        case "change":
            if let text = dict["text"] as? String {
                lastText = text
                onChange?(text)
            }
        default: break
        }
    }
}

/// Hosts the editor's WKWebView. Content is driven entirely through the controller.
struct CodeEditorView: NSViewRepresentable {
    let controller: CodeEditorController
    func makeNSView(context: Context) -> WKWebView { controller.webView }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
