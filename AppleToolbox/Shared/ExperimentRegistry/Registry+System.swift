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
            description: "Schedule real local notifications with categories and actions (text input, authentication-required, destructive), interruption levels, a runtime-rendered image attachment, threads and badges; log every delegate callback, draw one category with a notification content extension, register for APNs and probe the time-sensitive, critical-alert and communication boundaries.", frameworks: ["UserNotifications", "UserNotificationsUI", "Intents", "UIKit"], supportedPlatforms: [.iOS, .iPadOS, .macOS, .watchOS, .tvOS], hardwareRequirements: [], osRequirements: ["iOS 15+ · macOS 12+ · watchOS 8+ · tvOS 15+ (tvOS: badge only)"], permissions: ["Notification authorization"], capabilities: ["Alerts, sounds, badges", "Notification categories and actions", "Notification content extension (iOS)", "Push Notifications", "Time Sensitive Notifications"], entitlements: ["aps-environment", "com.apple.developer.usernotifications.time-sensitive"], documentationURL: URL(string: "https://developer.apple.com/documentation/usernotifications")!, evaluate: ExperimentAvailability.notifications,
            useCase: ExperimentUseCase(id: "notifications-lab", title: "Build, deliver and answer a notification",
                summary: "Compose a notification with a category, interruption level, thread and a freshly rendered image, then act on it from the Lock Screen or Notification Center.",
                interaction: "Request authorization, schedule with a delay, leave the app and use Reply, Mark Verified, Open or Delete. The delegate log shows every response, even when the app was closed."),
            explanations: [
                .permissionRequired: ExperimentExplanation(reason: "Notification authorization has not been requested yet, or its state has not been read in this session.", required: "Notification authorization (alert, sound, badge) or provisional authorization",
                    nextStep: "Tap Request Authorization below; provisional authorization delivers quietly without a prompt."),
                .permissionDenied: ExperimentExplanation(reason: "Notifications are turned off for Apple Toolbox.", required: "Notification authorization for Apple Toolbox",
                    nextStep: "Allow notifications for Apple Toolbox in Settings › Notifications, then re-read the settings."),
            ]),
    ]
}
