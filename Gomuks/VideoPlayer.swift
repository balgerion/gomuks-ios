import Foundation
import UIKit
import WebKit

@MainActor
enum VideoPlayer {
    enum LinkKind {
        case video
        case other
        case failed
    }

    private struct CheckResult: Decodable {
        let video: Bool
        let reason: String?
        let pattern: String?
        let url: String?
    }

    private static let key = "player_url"
    private static let patternsKey = "video_patterns"
    private static let noMediaKey = "no_media_links"
    private static let noMediaLifetime: TimeInterval = 7 * 24 * 60 * 60
    private static let patternLifetime: TimeInterval = 30 * 24 * 60 * 60
    private static let maxPatterns = 200
    private static let maxConcurrentChecks = 2
    private static let videoHosts = [
        "youtube.com", "youtu.be", "youtube-nocookie.com", "vimeo.com", "tiktok.com",
        "twitch.tv", "dailymotion.com", "dai.ly", "streamable.com",
    ]
    private static let mixedHosts = [
        "x.com", "twitter.com", "instagram.com", "reddit.com", "redd.it",
        "facebook.com", "fb.watch", "tumblr.com", "bsky.app", "imgur.com", "pinterest.com", "pin.it",
    ]
    private static var results: [URL: LinkKind] = [:]
    private static var resolved: [URL: URL] = [:]
    private static var checks: [URL: Task<LinkKind?, Never>] = [:]
    private static var queued: [URL] = []
    private static var noMedia: [String: Date] = loadNoMedia()
    private static var learned: [String: Date] = loadPatterns()
    private static var patterns: [NSRegularExpression] = learned.keys.compactMap { try? NSRegularExpression(pattern: $0) }

    static var server: URL? {
        get {
            UserDefaults.standard.string(forKey: key).flatMap { URL(serverAddress: $0) }
        }
        set {
            UserDefaults.standard.set(newValue?.absoluteString, forKey: key)
        }
    }

    static func watchURL(for link: URL) -> URL? {
        playerURL(for: resolved[link] ?? link, endpoint: "watch")
    }

    static func iframeURL(for link: URL) -> URL? {
        playerURL(for: resolved[link] ?? link, endpoint: "iframe")
    }

    static func kind(of url: URL) async -> LinkKind {
        guard isCheckable(url) else { return .other }
        if let kind = known(url) {
            return kind
        }
        if isMixed(url) {
            return checks[url] != nil || isKnownVideoHost(url) ? .video : .other
        }
        if isKnownVideoHost(url) || matchesPattern(url) {
            return .video
        }
        guard let result = await check(url, deep: false, timeout: 1.5) else { return .other }
        remember(result, for: url)
        if result.video, let pattern = result.pattern {
            learn(pattern, from: url)
        }
        let kind: LinkKind = result.video ? .video : .other
        results[url] = kind
        return kind
    }

    static func prefetch(_ links: [URL]) {
        var wanted: [URL] = []
        for link in links where isCheckable(link) && isMixed(link) && checks[link] == nil && !wanted.contains(link) {
            if let kind = known(link), kind != .failed {
                continue
            }
            results[link] = nil
            wanted.append(link)
        }
        queued = wanted
        startQueued()
    }

    static func markNoVideo(_ link: URL, reason: String?) {
        results[link] = reason == "error" ? .failed : .other
        if reason == "no-media" {
            rememberNoMedia(link)
            forgetPatterns(matching: link)
        }
    }

    private static func playerURL(for link: URL, endpoint: String, query: String = "") -> URL? {
        guard let server,
              var components = URLComponents(url: server, resolvingAgainstBaseURL: false)
        else { return nil }
        var path = components.path
        while path.hasSuffix("/") {
            path.removeLast()
        }
        components.path = path + "/" + endpoint
        guard let encoded = link.absoluteString.uriComponentEncoded else { return nil }
        components.percentEncodedQuery = "url=" + encoded + query
        return components.url
    }

    private static func isCheckable(_ url: URL) -> Bool {
        guard server != nil, let scheme = url.scheme?.lowercased() else { return false }
        return scheme == "https" || scheme == "http"
    }

    private static func isMixed(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return mixedHosts.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    static func playerRedirected(to target: URL, from link: URL) {
        guard target == link || target == resolved[link] else { return }
        markNoVideo(link, reason: "no-media")
    }

    private static func forgetPatterns(matching link: URL) {
        let text = link.absoluteString
        let range = NSRange(text.startIndex..., in: text)
        let stale = patterns.filter { $0.firstMatch(in: text, options: .anchored, range: range) != nil }.map(\.pattern)
        guard !stale.isEmpty else { return }
        for pattern in stale {
            learned[pattern] = nil
        }
        patterns.removeAll { stale.contains($0.pattern) }
        UserDefaults.standard.set(learned, forKey: patternsKey)
    }

    private static func matchesPattern(_ url: URL) -> Bool {
        let text = url.absoluteString
        let range = NSRange(text.startIndex..., in: text)
        return patterns.contains { $0.firstMatch(in: text, options: .anchored, range: range) != nil }
    }

    private static func learn(_ pattern: String, from url: URL) {
        guard learned[pattern] == nil, !isMixed(url),
              let expression = try? NSRegularExpression(pattern: pattern)
        else { return }
        let text = url.absoluteString
        guard expression.firstMatch(in: text, options: .anchored, range: NSRange(text.startIndex..., in: text)) != nil else { return }
        if learned.count >= maxPatterns, let oldest = learned.min(by: { $0.value < $1.value })?.key {
            learned[oldest] = nil
            patterns.removeAll { $0.pattern == oldest }
        }
        learned[pattern] = Date()
        patterns.append(expression)
        UserDefaults.standard.set(learned, forKey: patternsKey)
    }

    private static func loadPatterns() -> [String: Date] {
        let stored = UserDefaults.standard.dictionary(forKey: patternsKey) as? [String: Date] ?? [:]
        return stored.filter { $0.value.timeIntervalSinceNow > -patternLifetime }
    }

    private static func known(_ url: URL) -> LinkKind? {
        if let kind = results[url] {
            return kind
        }
        if let date = noMedia[url.absoluteString], date.timeIntervalSinceNow > -noMediaLifetime {
            return .other
        }
        return nil
    }

    private static func startQueued() {
        while checks.count < maxConcurrentChecks, !queued.isEmpty {
            let link = queued.removeFirst()
            let task = Task { () -> LinkKind? in
                let result = await check(link, deep: true, timeout: 10)
                checks[link] = nil
                startQueued()
                guard let result else { return nil }
                remember(result, for: link)
                let kind: LinkKind = result.video ? .video : result.reason == "error" ? .failed : .other
                results[link] = kind
                if !result.video && result.reason == "no-media" {
                    rememberNoMedia(link)
                }
                return kind
            }
            checks[link] = task
        }
    }

    private static func check(_ link: URL, deep: Bool, timeout: TimeInterval) async -> CheckResult? {
        guard let url = playerURL(for: link, endpoint: "check", query: deep ? "&deep=1" : "") else { return nil }
        let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200
        else { return nil }
        return try? JSONDecoder().decode(CheckResult.self, from: data)
    }

    private static func remember(_ result: CheckResult, for link: URL) {
        if let canonical = result.url.flatMap(URL.init(string:)), canonical != link {
            resolved[link] = canonical
        }
    }

    private static func loadNoMedia() -> [String: Date] {
        let stored = UserDefaults.standard.dictionary(forKey: noMediaKey) as? [String: Date] ?? [:]
        return stored.filter { $0.value.timeIntervalSinceNow > -noMediaLifetime }
    }

    private static func rememberNoMedia(_ link: URL) {
        noMedia = noMedia.filter { $0.value.timeIntervalSinceNow > -noMediaLifetime }
        noMedia[link.absoluteString] = Date()
        UserDefaults.standard.set(noMedia, forKey: noMediaKey)
    }

    private static func isKnownVideoHost(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        if host == "instagram.com" || host.hasSuffix(".instagram.com") {
            return url.path.hasPrefix("/reel")
        }
        if host == "fb.watch" {
            return true
        }
        if host == "facebook.com" || host.hasSuffix(".facebook.com") {
            let path = url.path
            return ["/reel", "/share/r/", "/share/v/", "/watch"].contains { path.hasPrefix($0) } || path.contains("/videos/")
        }
        return videoHosts.contains { host == $0 || host.hasSuffix("." + $0) }
    }
}

final class VideoPlayerController: UIViewController, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
    private static let controlsMessage = "gomuksPlayerControls"
    private static let controlsScript = """
    (() => {
        const report = (touching) => window.webkit.messageHandlers.\(controlsMessage).postMessage(touching);
        document.addEventListener("touchstart", (event) => {
            report(Boolean(event.target.closest && event.target.closest(".vjs-control-bar")));
        }, { capture: true, passive: true });
        document.addEventListener("touchend", () => report(false), { capture: true, passive: true });
        document.addEventListener("touchcancel", () => report(false), { capture: true, passive: true });
    })();
    """

    private let url: URL
    private let link: URL
    private var webView: WKWebView?
    private var touchingControls = false
    private var swipeToDismiss: SwipeToDismiss?

    init(url: URL, link: URL) {
        self.url = url
        self.link = link
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .pageSheet
        sheetPresentationController?.detents = [.large()]
        sheetPresentationController?.prefersGrabberVisible = true
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        view.accessibilityIdentifier = "gomuks-video-player"

        let configuration = WKWebViewConfiguration.media()
        configuration.userContentController.addUserScript(
            WKUserScript(source: InlineVideoScript.script(subframesOnly: false), injectionTime: .atDocumentStart, forMainFrameOnly: false)
        )
        configuration.userContentController.addUserScript(
            WKUserScript(source: Self.controlsScript, injectionTime: .atDocumentEnd, forMainFrameOnly: false)
        )
        configuration.userContentController.add(self, name: Self.controlsMessage)
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(webView)
        self.webView = webView

        let closeButton = UIButton(type: .system)
        closeButton.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
        closeButton.tintColor = .white
        closeButton.accessibilityLabel = "Close"
        closeButton.accessibilityIdentifier = "gomuks-video-player-close"
        closeButton.addTarget(self, action: #selector(close), for: .touchUpInside)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(closeButton)

        NSLayoutConstraint.activate([
            closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            closeButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -8),
            closeButton.widthAnchor.constraint(equalToConstant: 44),
            closeButton.heightAnchor.constraint(equalToConstant: 44),
            webView.topAnchor.constraint(equalTo: closeButton.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        swipeToDismiss = SwipeToDismiss(
            controller: self,
            movingView: view,
            fadesBackground: false,
            canBegin: { [weak self] in !(self?.touchingControls ?? false) },
            onDismiss: { [weak self] in self?.close() }
        )

        webView.load(URLRequest(url: url))
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        touchingControls = message.body as? Bool ?? false
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isBeingDismissed {
            webView?.configuration.userContentController.removeScriptMessageHandler(forName: Self.controlsMessage)
            webView?.loadHTMLString("", baseURL: nil)
        }
    }

    @objc private func close() {
        dismiss(animated: true)
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
    ) {
        guard let target = navigationAction.request.url,
              navigationAction.targetFrame?.isMainFrame == true,
              let host = target.host?.lowercased(),
              host != url.host?.lowercased()
        else {
            decisionHandler(.allow)
            return
        }
        decisionHandler(.cancel)
        VideoPlayer.playerRedirected(to: target, from: link)
        UIApplication.shared.open(target)
        dismiss(animated: true)
    }

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if let target = navigationAction.request.url {
            UIApplication.shared.open(target)
        }
        return nil
    }
}
