import Foundation

extension ExperimentRegistry {
    static let system: [ExperimentDescriptor] = [
        ExperimentDescriptor(id: "app-intents", name: "App Intents", category: .system,
            description: "Run the app's App Intents in-process (status, SHA-256 hash, capability summary, open a category or experiment) and list the App Shortcuts registered for Siri, Spotlight, and Shortcuts.", frameworks: ["AppIntents", "CryptoKit"], supportedPlatforms: SupportedPlatform.allCases, hardwareRequirements: [], osRequirements: ["iOS 16+ · macOS 13+ · watchOS 9+ · tvOS 16+"], permissions: [], capabilities: ["App Shortcuts (no Siri entitlement needed)", "App entities and queries"], entitlements: [], documentationURL: URL(string: "https://developer.apple.com/documentation/appintents")!, evaluate: { .available }),
        ExperimentDescriptor(id: "spotlight-siri", name: "Spotlight & Siri", category: .system,
            description: "Index every experiment in Spotlight as an App Intents IndexedEntity, open a tapped result straight into its experiment, and donate the Open Experiment intent whenever an experiment opens so Siri Suggestions can learn from it.", frameworks: ["CoreSpotlight", "AppIntents"], supportedPlatforms: [.iOS, .iPadOS, .macOS], hardwareRequirements: [], osRequirements: ["iOS 18+ · iPadOS 18+ · macOS 15+ (IndexedEntity)"], permissions: [], capabilities: ["Core Spotlight index", "App Intents donations"], entitlements: [], documentationURL: URL(string: "https://developer.apple.com/documentation/appintents/making-app-entities-available-in-spotlight")!, evaluate: ExperimentAvailability.spotlightIndexing,
            useCase: ExperimentUseCase(id: "spotlight-open", title: "Find an experiment from anywhere", summary: "Search Spotlight for an experiment or a framework and land directly on it; Siri Suggestions pick up the experiments you open often.", interaction: "Search for “CryptoKit” or “Bluetooth” in Spotlight and tap the Apple Toolbox result, then come back here to see the handled result, the live index contents and the recorded donations."),
            explanations: [
                .platformUnsupported: ExperimentExplanation(reason: "Core Spotlight keeps no searchable app index on \(CurrentPlatform.value.rawValue), and IndexedEntity exists only on iOS, iPadOS, macOS and visionOS.", required: "iPhone, iPad or Mac",
                    nextStep: "Open Apple Toolbox on an iPhone, iPad or Mac; the App Intents experiment still runs the intents here."),
                .unavailable: ExperimentExplanation(reason: "CSSearchableIndex.isIndexingAvailable() returns false, so this device does not accept Spotlight index updates right now.", required: "A device on which Core Spotlight indexing is available",
                    nextStep: "Check that Spotlight is not disabled or restricted on this device, then relaunch Apple Toolbox to index again."),
            ]),
        ExperimentDescriptor(id: "widgetkit", name: "WidgetKit", category: .system,
            description: "Share the last opened experiment with the Home Screen and Lock Screen widget through an App Group, run App Intents from an interactive widget and from Control Center controls in the widget's process, list what is placed and reload each kind. The interactive widget adapts to StandBy.", frameworks: ["WidgetKit", "AppIntents", "SwiftUI"], supportedPlatforms: [.iOS, .iPadOS], hardwareRequirements: [], osRequirements: ["iOS 18+ · iPadOS 18+ (controls)"], permissions: [], capabilities: ["Home Screen widgets", "Lock Screen widgets", "Interactive widgets", "Control Center controls", "StandBy", "App Groups"], entitlements: ["com.apple.security.application-groups"], documentationURL: URL(string: "https://developer.apple.com/documentation/widgetkit")!, evaluate: ExperimentAvailability.widgetKit,
            useCase: ExperimentUseCase(id: "widgetkit-interactive", title: "Drive the app from a widget and a control",
                summary: "Pin the last opened experiment from the Toolbox Controls widget or the Pin control and watch the shared state change here.",
                interaction: "Add the widget and the controls, tap refresh or the pin, then list and reload them here. Each intent run names the process it ran in."),
            explanations: [
                .entitlementRequired: ExperimentExplanation(reason: "The App Group container is not provisioned, so the app cannot share data with its widget.", required: "com.apple.security.application-groups with \(ToolboxIdentifiers.appGroup) for the app and the widget extension",
                    nextStep: "Register the App Group for both App IDs in Signing & Capabilities and reinstall the app."),
            ]),
        ExperimentDescriptor(id: "live-activities", name: "Live Activities", category: .system,
            description: "Start, update and end a real Live Activity with ActivityKit: a measurement run that the widget extension draws on the Lock Screen and in the Dynamic Island (compact, minimal, expanded), updated by the app with real battery, thermal and Low Power readings.", frameworks: ["ActivityKit", "WidgetKit", "SwiftUI"], supportedPlatforms: [.iOS, .iPadOS], hardwareRequirements: ["Dynamic Island presentations need an iPhone with Dynamic Island"], osRequirements: ["iOS 16.2+"], permissions: ["Live Activities switch in Settings"], capabilities: ["NSSupportsLiveActivities", "Lock Screen", "Dynamic Island"], entitlements: [], documentationURL: URL(string: "https://developer.apple.com/documentation/activitykit")!, evaluate: ExperimentAvailability.liveActivities,
            useCase: ExperimentUseCase(id: "live-activity-run", title: "Watch a measurement on the Lock Screen",
                summary: "Start a timed measurement run and follow it in the Dynamic Island and on the Lock Screen while the app keeps it updated.",
                interaction: "Start the run, lock the device or go Home, then long-press the Dynamic Island. End it from here or let it finish."),
            explanations: [
                .permissionDenied: ExperimentExplanation(reason: "ActivityAuthorizationInfo().areActivitiesEnabled is false: Live Activities are turned off for Apple Toolbox, or this device cannot show them.", required: "Live Activities allowed for Apple Toolbox on a device that supports them",
                    nextStep: "Turn on Settings › Apple Toolbox › Live Activities, or run the experiment on an iPhone."),
            ]),
        ExperimentDescriptor(id: "notifications", name: "UserNotifications", category: .system,
            description: "Schedule real local notifications with categories and actions (text input, authentication-required, destructive), interruption levels, a runtime-rendered image attachment, threads and badges; log every delegate callback, draw one category with a notification content extension, register for APNs, rewrite remote pushes with a notification service extension (title marker, downloaded attachment) and probe the time-sensitive, critical-alert and communication boundaries.", frameworks: ["UserNotifications", "UserNotificationsUI", "Intents", "UIKit"], supportedPlatforms: [.iOS, .iPadOS, .macOS, .watchOS, .tvOS], hardwareRequirements: [], osRequirements: ["iOS 15+ · macOS 12+ · watchOS 8+ · tvOS 15+ (tvOS: badge only)"], permissions: ["Notification authorization"], capabilities: ["Alerts, sounds, badges", "Notification categories and actions", "Notification content extension (iOS)", "Notification service extension for mutable-content pushes (iOS)", "Push Notifications", "Time Sensitive Notifications"], entitlements: ["aps-environment", "com.apple.developer.usernotifications.time-sensitive", "com.apple.security.application-groups (service extension → app)"], documentationURL: URL(string: "https://developer.apple.com/documentation/usernotifications")!, evaluate: ExperimentAvailability.notifications,
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
