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
        // Lets the Open Apple Toolbox control navigate when the system runs its intent in the app.
        ToolboxWidgetIntentHost.openExperiment = { ToolboxNavigator.shared.request = .experiment($0) }
        #endif
    }

    var body: some Scene {
        WindowGroup { ContentView() }
        #if os(iOS)
        // Second scene for the Windows & Displays experiment's openWindow(id:) test.
        WindowGroup("Window Probe", id: WindowProbe.sceneID) { WindowProbeView() }
            .commandsRemoved()
        #endif
    }
}
