import SwiftUI

@main
struct AppleToolboxApp: App {
    init() {
        #if os(iOS)
        // Activate early so pings from the watch app can be answered, even when the app was woken in the background.
        ContinuityExperimentService.shared.activate()
        #endif
    }

    var body: some Scene { WindowGroup { ContentView() } }
}
