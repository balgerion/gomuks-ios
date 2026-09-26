import UIKit
import WebKit

final class VideoPlayerController: UIViewController, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler,
    UIGestureRecognizerDelegate {
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

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
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

        let pan = UIPanGestureRecognizer(target: self, action: #selector(dismissPan(_:)))
        pan.delegate = self
        view.addGestureRecognizer(pan)

        webView.load(URLRequest(url: url))
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        touchingControls = message.body as? Bool ?? false
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return true }
        let velocity = pan.velocity(in: view)
        return !touchingControls && abs(velocity.x) > abs(velocity.y)
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        true
    }

    @objc private func dismissPan(_ pan: UIPanGestureRecognizer) {
        let translation = pan.translation(in: view)
        switch pan.state {
        case .changed:
            view.transform = CGAffineTransform(translationX: translation.x, y: 0)
        case .ended, .cancelled:
            if abs(translation.x) > 100 || abs(pan.velocity(in: view).x) > 800 {
                close()
            } else {
                UIView.animate(withDuration: 0.2) {
                    self.view.transform = .identity
                }
            }
        default:
            break
        }
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
