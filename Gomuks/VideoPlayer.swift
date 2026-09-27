import Foundation
import UIKit
import WebKit

@MainActor
enum VideoPlayer {
    private struct CheckResult: Decodable {
        let video: Bool
    }

    private static let key = "player_url"
    private static let videoHosts = [
        "youtube.com", "youtu.be", "youtube-nocookie.com", "vimeo.com", "tiktok.com",
        "twitch.tv", "dailymotion.com", "dai.ly", "streamable.com",
    ]
    private static var checked: [URL: Bool] = [:]

    static var server: URL? {
        get {
            UserDefaults.standard.string(forKey: key).flatMap { URL(serverAddress: $0) }
        }
        set {
            UserDefaults.standard.set(newValue?.absoluteString, forKey: key)
        }
    }

    static func watchURL(for link: URL) async -> URL? {
        await isVideoLink(link) ? playerURL(for: link, endpoint: "watch") : nil
    }

    static func iframeURL(for link: URL) async -> URL? {
        await isVideoLink(link) ? playerURL(for: link, endpoint: "iframe") : nil
    }

    private static func playerURL(for link: URL, endpoint: String) -> URL? {
        guard let server,
              var components = URLComponents(url: server, resolvingAgainstBaseURL: false)
        else { return nil }
        var path = components.path
        while path.hasSuffix("/") {
            path.removeLast()
        }
        components.path = path + "/" + endpoint
        guard let encoded = link.absoluteString.uriComponentEncoded else { return nil }
        components.percentEncodedQuery = "url=" + encoded
        return components.url
    }

    private static func isVideoLink(_ url: URL) async -> Bool {
        guard server != nil, let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http" else { return false }
        if let result = checked[url] {
            return result
        }
        if isKnownVideoHost(url) {
            return true
        }
        guard let result = await check(url) else { return false }
        checked[url] = result
        return result
    }

    static func markNoVideo(_ link: URL) {
        checked[link] = false
    }

    private static func check(_ link: URL) async -> Bool? {
        guard let url = playerURL(for: link, endpoint: "check") else { return nil }
        let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 1.5)
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let result = try? JSONDecoder().decode(CheckResult.self, from: data)
        else { return nil }
        return result.video
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
    private var webView: WKWebView?
    private var touchingControls = false
    private var swipeToDismiss: SwipeToDismiss?

    init(url: URL) {
        self.url = url
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
