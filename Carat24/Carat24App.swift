import SwiftUI

@main
struct Carat24App: App {
    @StateObject private var browser = BrowserModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(browser)
                .preferredColorScheme(.light)
        }
    }
}

