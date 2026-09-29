import UIKit
import WebKit

@MainActor
final class Browser: NSObject, ObservableObject {
    static let shared = Browser()

    @Published var needsSetup = false
    @Published private(set) var setupError: String?
    private(set) var credentials = Credentials.load()
    let webView: WKWebView
    private var started = false
    private var pendingURL: URL?
    private var showingImage = false

    override init() {
        webView = GomuksWebView(frame: .zero, configuration: .media())
        super.init()
        webView.isInspectable = true
        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.navigationDelegate = self
        webView.uiDelegate = self
        let contentController = webView.configuration.userContentController
        contentController.add(self, name: SettingsButton.messageName)
        contentController.add(self, name: MediaScript.messageName)
        contentController.addUserScript(
            WKUserScript(source: SettingsButton.script, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        )
        contentController.addUserScript(
            WKUserScript(source: TimelineScroll.script, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        )
        contentController.addUserScript(
            WKUserScript(source: MediaScript.script, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        )
        contentController.addUserScript(
            WKUserScript(source: InlineVideoScript.script(subframesOnly: true), injectionTime: .atDocumentStart, forMainFrameOnly: false)
        )
    }

    func start() {
        guard !started else { return }
        started = true
        VideoPlayer.refreshPatterns()
        guard let credentials else {
            needsSetup = true
            return
        }
        let target = loadServer()
        Task {
            guard await !hasAuthCookie(for: credentials.server) else { return }
            if let error = await authenticate(credentials) {
                showSetup(error: error)
            } else if let target {
                webView.load(URLRequest(url: target))
            }
        }
    }

    func open(_ url: URL) {
        guard url.scheme?.lowercased() == "matrix" else { return }
        pendingURL = url
        guard credentials != nil, !needsSetup else { return }
        if webView.url == nil || webView.isLoading {
            loadServer()
        } else if let encoded = url.absoluteString.uriComponentEncoded {
            pendingURL = nil
            webView.evaluateJavaScript("location.hash = \"/uri/\(encoded)\"")
        }
    }

    func showSetup(error: String?) {
        setupError = error
        needsSetup = true
    }

    func dismissSetup() {
        setupError = nil
        needsSetup = false
        if webView.url == nil {
            loadServer()
        }
    }

    func connect(server raw: String, username: String, password: String) async {
        setupError = nil
        guard let server = URL(serverAddress: raw) else {
            setupError = "Invalid server address"
            return
        }
        let credentials = Credentials(server: server, username: username, password: password)
        if let error = await authenticate(credentials) {
            setupError = error
            return
        }
        credentials.save()
        self.credentials = credentials
        needsSetup = false
        loadServer()
    }

    @discardableResult
    private func loadServer() -> URL? {
        guard let server = credentials?.server else { return nil }
        var target = server
        if let pendingURL, let encoded = pendingURL.absoluteString.uriComponentEncoded {
            var base = server.absoluteString
            while base.hasSuffix("/") {
                base.removeLast()
            }
            target = URL(string: base + "/#/uri/" + encoded) ?? server
        }
        pendingURL = nil
        webView.load(URLRequest(url: target))
        return target
    }

    private func authenticate(_ credentials: Credentials) async -> String? {
        guard let authURL = URL(string: "_gomuks/auth", relativeTo: Self.withTrailingSlash(credentials.server)) else {
            return "Invalid server address"
        }
        var request = URLRequest(url: authURL)
        request.httpMethod = "POST"
        request.setValue(
            "Basic " + Data("\(credentials.username):\(credentials.password)".utf8).base64EncodedString(),
            forHTTPHeaderField: "Authorization"
        )
        let session = URLSession(configuration: .ephemeral)
        defer { session.finishTasksAndInvalidate() }
        do {
            let (_, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return "Invalid server response"
            }
            switch http.statusCode {
            case 200, 201, 204:
                break
            case 401:
                return "Incorrect username or password"
            default:
                return "Server returned HTTP \(http.statusCode)"
            }
            var headers: [String: String] = [:]
            for (key, value) in http.allHeaderFields {
                if let key = key as? String, let value = value as? String {
                    headers[key] = value
                }
            }
            let cookieStore = webView.configuration.websiteDataStore.httpCookieStore
            for cookie in HTTPCookie.cookies(withResponseHeaderFields: headers, for: authURL) {
                await cookieStore.setCookie(cookie)
            }
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    private func hasAuthCookie(for server: URL) async -> Bool {
        guard let host = server.host?.lowercased() else { return false }
        let cookies = await webView.configuration.websiteDataStore.httpCookieStore.allCookies()
        return cookies.contains {
            $0.name == "gomuks_auth"
                && $0.domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".")) == host
                && ($0.expiresDate ?? .distantFuture) > Date()
        }
    }

    private static func withTrailingSlash(_ url: URL) -> URL {
        let text = url.absoluteString
        return text.hasSuffix("/") ? url : URL(string: text + "/") ?? url
    }

    private var topPresenter: UIViewController? {
        guard var presenter = webView.window?.rootViewController else { return nil }
        while let presented = presenter.presentedViewController {
            presenter = presented
        }
        return presenter
    }

    @discardableResult
    private func present(_ controller: UIViewController) -> Bool {
        guard let presenter = topPresenter else { return false }
        presenter.present(controller, animated: true)
        return true
    }
}

extension Browser {
    private func isServer(_ url: URL) -> Bool {
        guard let server = credentials?.server else { return false }
        return Self.sameOrigin(url, server)
    }

    private func openExternally(_ url: URL) {
        if url.scheme?.lowercased() == "matrix" {
            open(url)
            return
        }
        Task {
            if await VideoPlayer.kind(of: url) == .video, let watch = VideoPlayer.watchURL(for: url) {
                present(VideoPlayerController(url: watch))
            } else {
                UIApplication.shared.open(url, options: [:], completionHandler: nil)
            }
        }
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

    func webView(
        _ webView: WKWebView,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping @MainActor (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        let space = challenge.protectionSpace
        guard space.authenticationMethod == NSURLAuthenticationMethodHTTPBasic,
              let credentials,
              space.host.lowercased() == credentials.server.host?.lowercased()
        else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        if challenge.previousFailureCount == 0 {
            completionHandler(
                .useCredential,
                URLCredential(user: credentials.username, password: credentials.password, persistence: .forSession)
            )
        } else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            showSetup(error: "Incorrect username or password")
        }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
            return
        }
        if nsError.domain == "WebKitErrorDomain" && nsError.code == 102 {
            return
        }
        showSetup(error: error.localizedDescription)
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

extension Browser: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        switch message.name {
        case MediaScript.messageName:
            showImage(message.body)
        case SettingsButton.messageName:
            showSetup(error: nil)
        default:
            break
        }
    }

    private func showImage(_ body: Any) {
        guard let fields = body as? [String: Any] else { return }
        if let prefetch = fields["prefetch"] as? [String] {
            VideoPlayer.prefetch(prefetch.compactMap(URL.init(string:)).filter { !isServer($0) })
            return
        }
        guard let entries = fields["images"] as? [[String: Any]],
              let index = fields["index"] as? Int
        else { return }
        let images = entries.compactMap { entry -> ViewerImage? in
            guard let src = entry["src"] as? String, let url = URL(string: src) else { return nil }
            return ViewerImage(url: url, name: entry["alt"] as? String ?? "")
        }
        if let noVideo = (fields["noVideo"] as? String).flatMap(URL.init(string:)) {
            let reason = fields["reason"] as? String
            VideoPlayer.markNoVideo(noVideo, reason: reason)
            if reason == "error" {
                UIApplication.shared.open(noVideo, options: [:], completionHandler: nil)
                return
            }
        }
        guard images.indices.contains(index), !showingImage else { return }
        showingImage = true
        let link = (fields["link"] as? String).flatMap(URL.init(string:))
        Task {
            defer { showingImage = false }
            if let link {
                switch await VideoPlayer.kind(of: link) {
                case .video:
                    if let player = VideoPlayer.iframeURL(for: link),
                       let argument = try? JSONSerialization.data(withJSONObject: [player.absoluteString]),
                       let json = String(data: argument, encoding: .utf8) {
                        webView.evaluateJavaScript("window.__gomuksEmbedVideo(...\(json))", completionHandler: nil)
                        return
                    }
                case .failed:
                    UIApplication.shared.open(link, options: [:], completionHandler: nil)
                    return
                case .other:
                    break
                }
            }
            let cookies = await webView.configuration.websiteDataStore.httpCookieStore.allCookies()
            let configuration = URLSessionConfiguration.ephemeral
            for cookie in cookies {
                configuration.httpCookieStorage?.setCookie(cookie)
            }
            guard let presenter = topPresenter, !(presenter is ImageViewerController) else { return }
            let viewer = ImageViewerController(images: images, startIndex: index, session: URLSession(configuration: configuration))
            presenter.present(viewer, animated: true)
        }
    }
}

extension String {
    private static let uriComponentAllowed = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.!~*'()"
    )

    var uriComponentEncoded: String? {
        addingPercentEncoding(withAllowedCharacters: Self.uriComponentAllowed)
    }
}

extension WKWebViewConfiguration {
    static func media() -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        return configuration
    }
}
