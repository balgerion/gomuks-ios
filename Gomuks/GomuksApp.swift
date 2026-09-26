import SwiftUI

@main
struct GomuksApp: App {
    @StateObject private var browser = Browser.shared

    var body: some Scene {
        WindowGroup {
            WebView(browser: browser)
                .ignoresSafeArea(.container)
                .onOpenURL { browser.open($0) }
                .fullScreenCover(isPresented: $browser.needsSetup) {
                    SetupView(browser: browser)
                }
        }
    }
}
