import Foundation

extension ExperimentRegistry {
    static let system: [ExperimentDescriptor] = [
        ExperimentDescriptor(id: "app-intents", name: "App Intents", category: .system,
            description: "Run the app's App Intents in-process (status, SHA-256 hash, capability summary, open a category or experiment) and list the App Shortcuts registered for Siri, Spotlight, and Shortcuts.", frameworks: ["AppIntents", "CryptoKit"], supportedPlatforms: SupportedPlatform.allCases, hardwareRequirements: [], osRequirements: ["iOS 16+ · macOS 13+ · watchOS 9+ · tvOS 16+"], permissions: [], capabilities: ["App Shortcuts (no Siri entitlement needed)", "App entities and queries"], entitlements: [], documentationURL: URL(string: "https://developer.apple.com/documentation/appintents")!, evaluate: { .available }),
        ExperimentDescriptor(id: "widgetkit", name: "WidgetKit", category: .system,
            description: "Share the last opened experiment with the Home Screen and Lock Screen widget through an App Group, list the installed widget configurations, and reload their timelines.", frameworks: ["WidgetKit", "SwiftUI", "Foundation"], supportedPlatforms: [.iOS, .iPadOS], hardwareRequirements: [], osRequirements: ["iOS 18+ · iPadOS 18+"], permissions: [], capabilities: ["Home Screen widgets", "Lock Screen widgets", "App Groups"], entitlements: ["com.apple.security.application-groups"], documentationURL: URL(string: "https://developer.apple.com/documentation/widgetkit")!, evaluate: ExperimentAvailability.widgetKit,
            explanations: [
                .entitlementRequired: ExperimentExplanation(reason: "The App Group container is not provisioned, so the app cannot share data with its widget.", required: "com.apple.security.application-groups with group.com.jorisconrad.AppleToolbox for the app and the widget extension",
                    nextStep: "Register the App Group for both App IDs in Signing & Capabilities and reinstall the app."),
            ]),
        ExperimentDescriptor(id: "notifications", name: "UserNotifications", category: .system,
            description: "Request notification authorization and schedule one real local test notification.", frameworks: ["UserNotifications"], supportedPlatforms: [.iOS, .iPadOS, .macOS, .watchOS, .tvOS], hardwareRequirements: [], osRequirements: ["iOS 10+ · macOS 10.14+ · watchOS 3+ · tvOS 10+"], permissions: ["Notification authorization"], capabilities: ["Alerts, sounds, badges"], entitlements: [], documentationURL: URL(string: "https://developer.apple.com/documentation/usernotifications")!, evaluate: ExperimentAvailability.notifications),
    ]
}
