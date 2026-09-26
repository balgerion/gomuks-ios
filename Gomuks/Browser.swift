import UIKit
import WebKit

@MainActor
final class Browser: NSObject, ObservableObject {
    private static let defaultServer = URL(string: "https://gomuks.balgeriada.com")!
    private static let serverKey = "server_url"
    private static let uriComponentAllowed = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.!~*'()"
    )

    let webView: WKWebView
    private var loadedServer: URL?

    override init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        webView.isInspectable = true
        webView.allowsBackForwardNavigationGestures = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.navigationDelegate = self
        webView.uiDelegate = self
    }

    private var configuredServer: URL {
        let raw = UserDefaults.standard.string(forKey: Self.serverKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard let url = URL(string: raw),
              let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http",
              url.host != nil
        else {
            return Self.defaultServer
        }
        return url
    }

    func start() {
        guard loadedServer == nil else { return }
        let server = configuredServer
        load(server, server: server)
    }

    func open(_ url: URL) {
        guard url.scheme?.lowercased() == "matrix",
              let encoded = url.absoluteString.addingPercentEncoding(withAllowedCharacters: Self.uriComponentAllowed)
        else { return }
        let server = configuredServer
        var base = server.absoluteString
        while base.hasSuffix("/") {
            base.removeLast()
        }
        guard let target = URL(string: base + "/#/uri/" + encoded) else { return }
        load(target, server: server)
    }

    func reloadIfServerChanged() {
        guard let loadedServer else { return }
        let server = configuredServer
        if !Self.sameOrigin(loadedServer, server) {
            load(server, server: server)
        }
    }

    private func load(_ url: URL, server: URL) {
        loadedServer = server
        webView.load(URLRequest(url: url))
    }

    private func isServer(_ url: URL) -> Bool {
        Self.sameOrigin(url, loadedServer ?? configuredServer)
    }

    private func openExternally(_ url: URL) {
        if url.scheme?.lowercased() == "matrix" {
            open(url)
        } else {
            UIApplication.shared.open(url)
        }
    }

    private func present(_ alert: UIAlertController) -> Bool {
        guard var presenter = webView.window?.rootViewController else { return false }
        while let presented = presenter.presentedViewController {
            presenter = presented
        }
        presenter.present(alert, animated: true)
        return true
    }

    private static func sameOrigin(_ a: URL, _ b: URL) -> Bool {
        a.scheme?.lowercased() == b.scheme?.lowercased()
            && a.host?.lowercased() == b.host?.lowercased()
            && port(of: a) == port(of: b)
    }

    private static func port(of url: URL) -> Int? {
        if let port = url.port {
            return port
        }
        switch url.scheme?.lowercased() {
        case "https": return 443
        case "http": return 80
        default: return nil
        }
    }
}

extension Browser: WKNavigationDelegate {
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url, let scheme = url.scheme?.lowercased() else {
            decisionHandler(.allow)
            return
        }
        switch scheme {
        case "http", "https":
            if navigationAction.targetFrame?.isMainFrame == false || isServer(url) {
                decisionHandler(.allow)
            } else {
                decisionHandler(.cancel)
                openExternally(url)
            }
        case "about", "blob", "data", "javascript":
            decisionHandler(.allow)
        default:
            decisionHandler(.cancel)
            openExternally(url)
        }
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        webView.reload()
    }
}

extension Browser: WKUIDelegate {
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if let url = navigationAction.request.url {
            openExternally(url)
        }
        return nil
    }

    func webView(
        _ webView: WKWebView,
        requestMediaCapturePermissionFor origin: WKSecurityOrigin,
        initiatedByFrame frame: WKFrameInfo,
        type: WKMediaCaptureType,
        decisionHandler: @escaping @MainActor (WKPermissionDecision) -> Void
    ) {
        decisionHandler(.grant)
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptAlertPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping @MainActor () -> Void
    ) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler() })
        if !present(alert) {
            completionHandler()
        }
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptConfirmPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping @MainActor (Bool) -> Void
    ) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in completionHandler(false) })
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler(true) })
        if !present(alert) {
            completionHandler(false)
        }
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptTextInputPanelWithPrompt prompt: String,
        defaultText: String?,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping @MainActor (String?) -> Void
    ) {
        let alert = UIAlertController(title: nil, message: prompt, preferredStyle: .alert)
        alert.addTextField { $0.text = defaultText }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in completionHandler(nil) })
        alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak alert] _ in
            completionHandler(alert?.textFields?.first?.text ?? "")
        })
        if !present(alert) {
            completionHandler(nil)
        }
    }
}
