/// Decides how to fetch a shader based on whether the user configured an API key.
enum FetchStrategy: Equatable {
    case api          // keyed official API (Silver+ members)
    case webView      // default: drive WKWebView past Cloudflare, no key needed

    static func select(hasKey: Bool) -> FetchStrategy {
        hasKey ? .api : .webView
    }
}
