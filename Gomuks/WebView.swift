import SwiftUI
import WebKit

struct WebView: UIViewRepresentable {
    let browser: Browser

    func makeUIView(context: Context) -> WKWebView {
        browser.start()
        return browser.webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}
}
