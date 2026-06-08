import Foundation
import WebKit
import ShadertoyISFKit

enum WebFetchError: Error, Equatable {
    case badID
    case challengeTimeout
    case noData
}

@MainActor
final class WebKitShaderFetcher: NSObject {
    private let webView: WKWebView
    private var loadContinuation: CheckedContinuation<Void, Error>?

    override init() {
        let config = WKWebViewConfiguration()
        webView = WKWebView(frame: .init(x: 0, y: 0, width: 800, height: 600), configuration: config)
        super.init()
        webView.navigationDelegate = self
        // Keep a persistent (default) data store so Cloudflare clearance cookies persist.
    }

    func fetchShader(id: String) async throws -> Shader {
        guard let url = URL(string: "https://www.shadertoy.com/view/\(id)") else { throw WebFetchError.badID }
        try await load(url)
        try await waitForChallengeToClear(timeout: 20)
        let json = try await runInPageFetch(id: id)
        return try ShadertoyInternalParser.parse(Data(json.utf8))
    }

    private func load(_ url: URL) async throws {
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            loadContinuation = c
            webView.load(URLRequest(url: url))
        }
    }

    private func waitForChallengeToClear(timeout: TimeInterval) async throws {
        let start = Date()
        while Date().timeIntervalSince(start) < timeout {
            let title = (try? await webView.evaluateJavaScript("document.title")) as? String ?? ""
            if !title.isEmpty && title != "Just a moment..." && title != "Just a moment…" {
                return
            }
            try await Task.sleep(nanoseconds: 700_000_000)
        }
        throw WebFetchError.challengeTimeout
    }

    private func runInPageFetch(id: String) async throws -> String {
        let js = """
        const body = 's=' + encodeURIComponent(JSON.stringify({shaders:[id]})) + '&nt=1&nl=1&np=1';
        const r = await fetch('/shadertoy', { method:'POST', headers:{'Content-Type':'application/x-www-form-urlencoded'}, body });
        return await r.text();
        """
        let result = try await webView.callAsyncJavaScript(js, arguments: ["id": id], contentWorld: .page)
        guard let text = result as? String, !text.isEmpty else { throw WebFetchError.noData }
        return text
    }
}

extension WebKitShaderFetcher: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loadContinuation?.resume(); loadContinuation = nil
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        loadContinuation?.resume(throwing: error); loadContinuation = nil
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        loadContinuation?.resume(throwing: error); loadContinuation = nil
    }
}
