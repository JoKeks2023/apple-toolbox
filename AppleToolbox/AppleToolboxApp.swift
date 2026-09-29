import SwiftUI

@main
struct AppleToolboxApp: App {
    // Installs the notification delegate while the app launches and receives the APNs device token.
    #if os(iOS) || os(tvOS)
    @UIApplicationDelegateAdaptor(ToolboxAppDelegate.self) private var appDelegate
    #elseif os(macOS)
    @NSApplicationDelegateAdaptor(ToolboxAppDelegate.self) private var appDelegate
    #endif

    init() {
        #if os(iOS)
        // Activate early so pings from the watch app can be answered, even when the app was woken in the background.
        ContinuityExperimentService.shared.activate()
        #endif
    }

    var body: some Scene { WindowGroup { ContentView() } }
}
