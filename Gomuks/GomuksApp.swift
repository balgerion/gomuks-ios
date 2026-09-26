import SwiftUI

@main
struct GomuksApp: App {
    @StateObject private var browser = Browser()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            WebView(browser: browser)
                .ignoresSafeArea()
                .onOpenURL { browser.open($0) }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                browser.reloadIfServerChanged()
            }
        }
    }
}
