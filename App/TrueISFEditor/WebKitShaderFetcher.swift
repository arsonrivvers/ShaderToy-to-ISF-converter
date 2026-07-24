import Foundation
import WebKit
import ShadertoyISFKit

enum WebFetchError: Error, Equatable {
    case badID
    case challengeTimeout
    case noData
    case httpError(Int)   // the in-page /shadertoy POST returned a non-200 status
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
    enum State: Equatable {
        case loading
        case verificationRequired
        case cleared
        case failed(String)
    }

    private let webView: WKWebView
    private let window: NSWindow
    private static weak var activeVerificationFetcher: WebKitShaderFetcher?

    /// Diagnostics for the last poll (used by the debug-fetch affordance).
    private(set) var lastTitle: String = "(none)"
    private(set) var lastURL: String = "(none)"
    private(set) var lastBody: String = "(none)"
    /// Raw text returned by the in-page `/shadertoy` POST on the last fetch (the actual payload
    /// the parser sees). Distinct from `lastBody`, which is the page chrome's innerText.
    private(set) var lastResponseBody: String = "(none)"
    /// HTTP status of the last in-page `/shadertoy` POST.
    private(set) var lastResponseStatus: Int = -1

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

    static func foregroundActiveVerification() -> Bool {
        guard let fetcher = activeVerificationFetcher else { return false }
        fetcher.window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        return true
    }

    /// Harvests real public shader IDs from Shadertoy's results page (for the conversion-conformance
    /// corpus). Scrapes `/view/<id>` links from the rendered page — no ID-guessing. Best-effort.
    // (No sort parameter: the browse SPA renders its default popular grid — a sort option was
    // never honored, and the parameter only made the signature lie.)
    func harvestShaderIDs(count: Int = 60) async -> [String] {
        guard let url = URL(string: "https://www.shadertoy.com/browse") else { return [] }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        defer { window.orderOut(nil) }
        webView.load(URLRequest(url: url))
        try? await waitUntilReady(timeout: 20)
        // SPA: the grid loads via AJAX and lazy-loads more on scroll. Scroll to the bottom each poll
        // to accumulate `/view/<id>` links (clean shader IDs — the `id="…"` pattern matched page
        // chrome like header/navTop/footer, so only /view/ is used).
        var ids = Set<String>()
        for _ in 0..<30 {
            _ = try? await webView.evaluateJavaScript("window.scrollTo(0, document.body.scrollHeight); document.querySelectorAll('.NextPage,.morePagesButton').forEach(function(b){b.click&&b.click();});")
            try? await Task.sleep(nanoseconds: 800_000_000)
            let js = "JSON.stringify(Array.from(new Set((document.body.innerHTML.match(/\\/view\\/[A-Za-z0-9]{6}/g)||[]).map(function(s){return s.slice(6);}))))"
            if let raw = (try? await webView.evaluateJavaScript(js)) as? String,
               let data = raw.data(using: .utf8),
               let got = try? JSONDecoder().decode([String].self, from: data) {
                ids.formUnion(got)
            }
            #if DEBUG
            print("HARVEST poll: ids=\(ids.count)")   // corpus-harness diagnostics only
            #endif
            if ids.count >= count { break }
        }
        return Array(ids.prefix(count))
    }

    func fetchShader(id: String) async throws -> Shader {
        try await fetchShader(id: id, onState: { _ in })
    }

    func fetchShader(
        id: String,
        onState: @MainActor (State) -> Void
    ) async throws -> Shader {
        var completed = false
        defer {
            if !completed {
                onState(.failed("fetch failed"))
            }
        }
        // Reset per fetch: a stale value would attribute the PREVIOUS fetch's HTTP status to this
        // one in the import log (e.g. a challenge-timeout logging the prior fetch's 200).
        lastResponseStatus = -1
        guard let url = URL(string: "https://www.shadertoy.com/view/\(id)") else {
            throw WebFetchError.badID
        }
        window.title = "Fetching from Shadertoy… (if a checkbox appears, click it)"
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        Self.activeVerificationFetcher = self
        defer {
            if Self.activeVerificationFetcher === self {
                Self.activeVerificationFetcher = nil
            }
            window.orderOut(nil)
        }
        onState(.loading)

        // Retry transient failures once (Cloudflare challenges and 429/5xx are often transient):
        // reload and try again. Definitive outcomes (parse = not-found/private, badID, other HTTP)
        // surface immediately.
        var lastError: Error = WebFetchError.challengeTimeout
        for attempt in 0..<2 {
            do {
                if attempt == 0 { webView.load(URLRequest(url: url)) } else { webView.reload() }
                try await waitUntilReady(timeout: 20, onState: onState)
                let json = try await runInPageFetch(id: id)
                let shader = try ShadertoyInternalParser.parse(Data(json.utf8))
                completed = true
                return shader
            } catch let e as WebFetchError {
                lastError = e
                switch e {
                case .challengeTimeout: continue
                case .httpError(let s) where s == 429 || s >= 500: continue
                default: throw e
                }
            }
            // ShadertoyInternalParserError (not found / not public) isn't a WebFetchError, so it
            // propagates out here without retry — that's the intended definitive path.
        }
        throw lastError
    }

    /// Polls the page until Cloudflare's interstitial is gone AND we're positively on shadertoy.com
    /// (so a redirect/error page isn't mistaken for a loaded shader). Throws `challengeTimeout`.
    private func waitUntilReady(
        timeout: TimeInterval,
        onState: @MainActor (State) -> Void = { _ in }
    ) async throws {
        try await Self.waitForReadiness(
            timeout: timeout,
            now: { Date().timeIntervalSinceReferenceDate },
            sleep: { try await Task.sleep(nanoseconds: 600_000_000) },
            pageInfo: {
                let info = (try? await webView.evaluateJavaScript(
                    "JSON.stringify({t: document.title, h: location.hostname})")) as? String ?? ""
                let (title, host) = Self.parseReadyInfo(info)
                lastTitle = title
                lastURL = webView.url?.absoluteString ?? "(nil)"
                lastBody = ((try? await webView.evaluateJavaScript(
                    "(document.body ? document.body.innerText : '').slice(0,400)")) as? String ?? "")
                    .replacingOccurrences(of: "\n", with: " | ")
                return (title, host)
            },
            onState: onState
        )
        try await Task.sleep(nanoseconds: 400_000_000)   // let scripts settle
    }

    /// Ordinary network loads retain a bounded deadline. Once an interactive verification page is
    /// positively identified on Shadertoy, that deadline no longer owns the handoff: the visible
    /// page remains available until legitimate clearance or task/user cancellation.
    static func waitForReadiness(
        timeout: TimeInterval,
        now: () -> TimeInterval,
        sleep: () async throws -> Void,
        pageInfo: () async -> (title: String, host: String),
        onState: @MainActor (State) -> Void
    ) async throws {
        let start = now()
        let challengeTitles: Set<String> = ["Just a moment...", "Just a moment…", ""]
        var waitingForHuman = false
        var reportedVerification = false

        while waitingForHuman || now() - start < timeout {
            try Task.checkCancellation()
            try await sleep()
            let (title, host) = await pageInfo()
            if host.hasSuffix("shadertoy.com"), !challengeTitles.contains(title) {
                onState(.cleared)
                return
            }
            if host.hasSuffix("shadertoy.com"),
               challengeTitles.contains(title),
               !reportedVerification {
                reportedVerification = true
                waitingForHuman = true
                onState(.verificationRequired)
            }
        }
        throw WebFetchError.challengeTimeout
    }

    private static func parseReadyInfo(_ json: String) -> (title: String, host: String) {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return ("", "") }
        return (obj["t"] as? String ?? "", obj["h"] as? String ?? "")
    }

    private func runInPageFetch(id: String) async throws -> String {
        // Capture the HTTP status alongside the body so a Cloudflare 403/429/5xx (which returns an
        // HTML body, not shader JSON) surfaces as a real error instead of a misleading parse failure.
        let js = """
        const body = 's=' + encodeURIComponent(JSON.stringify({shaders:[id]})) + '&nt=1&nl=1&np=1';
        const r = await fetch('/shadertoy', { method:'POST', headers:{'Content-Type':'application/x-www-form-urlencoded'}, body });
        const text = await r.text();
        return JSON.stringify({ status: r.status, body: text });
        """
        let result = try await webView.callAsyncJavaScript(js, arguments: ["id": id], contentWorld: .page)
        guard let raw = result as? String,
              let data = raw.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let status = obj["status"] as? Int,
              let text = obj["body"] as? String else { throw WebFetchError.noData }
        lastResponseStatus = status
        lastResponseBody = text
        guard status == 200 else { throw WebFetchError.httpError(status) }
        guard !text.isEmpty else { throw WebFetchError.noData }
        return text
    }
}
