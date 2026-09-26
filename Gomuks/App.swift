import SwiftUI
import UIKit
import WebKit

@main
struct GomuksApp: App {
    @StateObject private var browser = Browser.shared

    var body: some Scene {
        WindowGroup {
            WebView(browser: browser)
                .ignoresSafeArea()
                .onOpenURL { browser.open($0) }
                .fullScreenCover(isPresented: $browser.needsSetup) {
                    SetupView(browser: browser)
                }
        }
    }
}

struct WebView: UIViewControllerRepresentable {
    let browser: Browser

    func makeUIViewController(context: Context) -> WebViewController {
        browser.start()
        return WebViewController(webView: browser.webView)
    }

    func updateUIViewController(_ controller: WebViewController, context: Context) {}
}

final class WebViewController: UIViewController {
    private let webView: WKWebView

    init(webView: WKWebView) {
        self.webView = webView
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        webView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(webView)
        view.keyboardLayoutGuide.usesBottomSafeArea = false
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor),
        ])
    }
}

final class GomuksWebView: WKWebView {
    override var inputAccessoryView: UIView? {
        nil
    }
}
