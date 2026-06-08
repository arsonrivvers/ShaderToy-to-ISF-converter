import Foundation
import WebKit
import ShadertoyISFKit

enum WebFetchError: Error, Equatable {
    case badID
    case challengeTimeout
    case noData
}

/// Fetches a Shadertoy shader by driving a real WKWebView: load the shader's view page
/// (WebKit clears Cloudflare's managed challenge like Safari does), then run an in-origin
/// `fetch('/shadertoy', …)` to retrieve the shader JSON.
///
/// Two deliberate design choices, both learned the hard way:
///  1. **Poll-only.** We never await a navigation-completion continuation. Cloudflare does
///     several redirects/reloads; tying completion to a single `didFinish` leaks the
///     continuation. We fire `load()` and poll page state via `evaluateJavaScript`.
///  2. **Visible window.** WebKit throttles JavaScript/rendering for web views that aren't in
///     an on-screen window, so Cloudflare's challenge never runs offscreen. We attach the web
///     view to a small real window during the fetch (also lets the user solve a rare
///     interactive challenge), then hide it.
@MainActor
final class WebKitShaderFetcher: NSObject {
    private let webView: WKWebView
    private let window: NSWindow

    /// Diagnostics for the last poll (used by the debug-fetch affordance).
    private(set) var lastTitle: String = "(none)"
    private(set) var lastURL: String = "(none)"
    private(set) var lastBody: String = "(none)"

    override init() {
        let frame = NSRect(x: 0, y: 0, width: 480, height: 360)
        webView = WKWebView(frame: frame, configuration: WKWebViewConfiguration())
        window = NSWindow(contentRect: frame,
                          styleMask: [.titled, .closable, .miniaturizable],
                          backing: .buffered, defer: false)
        window.title = "Fetching from Shadertoy…"
        window.contentView = webView
        window.isReleasedWhenClosed = false
        super.init()
        // Present as Safari so Cloudflare's managed challenge treats us like a normal browser.
        webView.customUserAgent =
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
        // Persistent (default) data store → Cloudflare clearance cookie persists across fetches.
    }

    func fetchShader(id: String) async throws -> Shader {
        guard let url = URL(string: "https://www.shadertoy.com/view/\(id)") else { throw WebFetchError.badID }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        defer { window.orderOut(nil) }

        webView.load(URLRequest(url: url))
        try await waitUntilReady(timeout: 20)
        let json = try await runInPageFetch(id: id)
        return try ShadertoyInternalParser.parse(Data(json.utf8))
    }

    /// Polls `document.title` until Cloudflare's "Just a moment…" interstitial is gone and a
    /// real page title is present. Returns when ready; throws `challengeTimeout` on timeout.
    private func waitUntilReady(timeout: TimeInterval) async throws {
        let start = Date()
        let challengeTitles: Set<String> = ["Just a moment...", "Just a moment…", ""]
        while Date().timeIntervalSince(start) < timeout {
            try await Task.sleep(nanoseconds: 600_000_000)
            let title = (try? await webView.evaluateJavaScript("document.title")) as? String ?? ""
            lastTitle = title
            lastURL = webView.url?.absoluteString ?? "(nil)"
            lastBody = ((try? await webView.evaluateJavaScript(
                "(document.body ? document.body.innerText : '').slice(0,400)")) as? String ?? "")
                .replacingOccurrences(of: "\n", with: " | ")
            if !challengeTitles.contains(title) {
                // Give the page's scripts a beat to settle after the challenge clears.
                try await Task.sleep(nanoseconds: 400_000_000)
                return
            }
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
