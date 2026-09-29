import Foundation

nonisolated extension ImplementationGuides {
    static let system: [String: ImplementationGuide] = [
        "app-intents": ImplementationGuide(
            snippet: #"""
            import AppIntents
            import CryptoKit

            /// An action Siri, Spotlight and the Shortcuts app can run without opening the app.
            struct HashTextIntent: AppIntent {
                static let title: LocalizedStringResource = "Hash Text"
                static let description = IntentDescription("Returns the SHA-256 hash of a text.")

                @Parameter(title: "Text")
                var text: String

                func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
                    let hash = SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
                    return .result(value: hash, dialog: "The hash is \(hash.prefix(12))…")
                }
            }

            /// Registers the intent as an App Shortcut: available right after install, no setup by the user.
            struct AppShortcuts: AppShortcutsProvider {
                static var appShortcuts: [AppShortcut] {
                    AppShortcut(intent: HashTextIntent(),
                                phrases: ["Hash text with \(.applicationName)"],
                                shortTitle: "Hash Text",
                                systemImageName: "number")
                }
            }
            """#,
            notes: [
                "Every App Shortcut phrase must contain \\(.applicationName); phrases are extracted at build time, not at runtime.",
                "No Siri entitlement is needed for App Intents; that's only for the old SiriKit intents.",
                "Set static openAppWhenRun = true (or use OpenIntent) if the action must bring the app to the foreground.",
            ]
        ),
        "spotlight-siri": ImplementationGuide(
            snippet: #"""
            import AppIntents
            import CoreSpotlight

            /// An app entity that Spotlight can index and that intents can take as a parameter.
            struct RecipeEntity: IndexedEntity {
                static let typeDisplayRepresentation: TypeDisplayRepresentation = "Recipe"
                static let defaultQuery = RecipeQuery()
                let id: String
                let name: String

                var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
            }

            struct RecipeQuery: EntityQuery {
                func entities(for identifiers: [String]) async throws -> [RecipeEntity] {
                    identifiers.map { RecipeEntity(id: $0, name: $0.capitalized) } // Look them up in your store.
                }
            }

            /// Runs when the user taps the entity in Spotlight.
            struct OpenRecipeIntent: OpenIntent {
                static let title: LocalizedStringResource = "Open Recipe"
                @Parameter(title: "Recipe") var target: RecipeEntity

                @MainActor
                func perform() async throws -> some IntentResult {
                    print("Navigate to \(target.id)")
                    return .result()
                }
            }

            func index(_ recipes: [RecipeEntity]) async throws {
                try await CSSearchableIndex.default().indexAppEntities(recipes)
            }

            /// Tell the system the user did this, so Siri Suggestions can learn it.
            func donateOpen(of recipe: RecipeEntity) async throws {
                let intent = OpenRecipeIntent()
                intent.target = recipe
                _ = try await IntentDonationManager.shared.donate(intent: intent)
            }
            """#,
            notes: [
                "IndexedEntity and indexAppEntities need iOS 18; before that, index CSSearchableItems and handle CSSearchableItemActionType.",
                "Re-index when data changes and delete removed items, or Spotlight shows stale results.",
                "Donate only actions the user actually performed; donations drive Siri Suggestions ranking.",
            ]
        ),
        "widgetkit": ImplementationGuide(
            snippet: #"""
            import AppIntents
            import SwiftUI
            import WidgetKit

            let appGroup = "group.com.example.app" // Shared by the app and the widget extension.

            struct CountEntry: TimelineEntry {
                let date: Date
                let count: Int
            }

            struct CountProvider: TimelineProvider {
                func placeholder(in context: Context) -> CountEntry { CountEntry(date: .now, count: 0) }
                func getSnapshot(in context: Context, completion: @escaping (CountEntry) -> Void) { completion(current()) }
                func getTimeline(in context: Context, completion: @escaping (Timeline<CountEntry>) -> Void) {
                    completion(Timeline(entries: [current()], policy: .never))
                }
                private func current() -> CountEntry {
                    CountEntry(date: .now, count: UserDefaults(suiteName: appGroup)?.integer(forKey: "count") ?? 0)
                }
            }

            /// Runs in the widget's process when the button is tapped; the widget reloads afterwards.
            struct IncrementIntent: AppIntent {
                static let title: LocalizedStringResource = "Increment"
                func perform() async throws -> some IntentResult {
                    let defaults = UserDefaults(suiteName: appGroup)
                    defaults?.set((defaults?.integer(forKey: "count") ?? 0) + 1, forKey: "count")
                    return .result()
                }
            }

            struct CountWidget: Widget {
                var body: some WidgetConfiguration {
                    StaticConfiguration(kind: "Count", provider: CountProvider()) { entry in
                        VStack {
                            Text("\(entry.count)").font(.largeTitle)
                            Button("Add", intent: IncrementIntent())
                        }
                        .containerBackground(.fill.tertiary, for: .widget)
                    }
                    .configurationDisplayName("Counter")
                    .supportedFamilies([.systemSmall, .accessoryRectangular])
                }
            }
            """#,
            entitlements: ["com.apple.security.application-groups = [group.com.example.app] (app and widget extension)"],
            capabilities: ["App Groups (on both targets)", "Widget Extension target"],
            notes: [
                "After the app changes shared data, call WidgetCenter.shared.reloadTimelines(ofKind:); the budget for reloads is limited.",
                "Widgets are rendered views, not live apps: only Button and Toggle with an AppIntent are interactive (iOS 17+).",
                "Control Center controls use ControlWidget with ControlWidgetButton or ControlWidgetToggle (iOS 18+).",
            ]
        ),
        "live-activities": ImplementationGuide(
            snippet: #"""
            import ActivityKit
            import SwiftUI
            import WidgetKit

            /// Shared by the app and the widget extension.
            struct RunAttributes: ActivityAttributes {
                struct ContentState: Codable, Hashable { var progress: Double }
                var name: String
            }

            // In the app:
            func startRun() throws -> Activity<RunAttributes> {
                guard ActivityAuthorizationInfo().areActivitiesEnabled else { throw CancellationError() }
                return try Activity.request(attributes: RunAttributes(name: "Measurement"),
                                            content: ActivityContent(state: .init(progress: 0), staleDate: nil))
            }

            func update(_ activity: Activity<RunAttributes>, progress: Double) async {
                await activity.update(ActivityContent(state: .init(progress: progress), staleDate: nil))
            }

            func end(_ activity: Activity<RunAttributes>) async {
                await activity.end(nil, dismissalPolicy: .default)
            }

            // In the widget extension:
            struct RunLiveActivity: Widget {
                var body: some WidgetConfiguration {
                    ActivityConfiguration(for: RunAttributes.self) { context in
                        ProgressView(context.attributes.name, value: context.state.progress).padding() // Lock Screen
                    } dynamicIsland: { context in
                        DynamicIsland {
                            DynamicIslandExpandedRegion(.center) { ProgressView(value: context.state.progress) }
                        } compactLeading: {
                            Image(systemName: "gauge")
                        } compactTrailing: {
                            Text(context.state.progress, format: .percent)
                        } minimal: {
                            Image(systemName: "gauge")
                        }
                    }
                }
            }
            """#,
            infoPlist: [
                .init(key: "NSSupportsLiveActivities", value: "<true/>"),
            ],
            capabilities: ["Widget Extension target", "Push Notifications (only for remote updates via ActivityKit push tokens)"],
            notes: [
                "The user can disable Live Activities per app; check ActivityAuthorizationInfo and observe its updates.",
                "The ContentState payload is limited to 4 KB and a Live Activity lasts at most 8 hours (12 on the Lock Screen).",
                "Updates from a suspended app need ActivityKit push notifications; local timers stop in the background.",
            ]
        ),
        "notifications": ImplementationGuide(
            snippet: #"""
            import UserNotifications

            /// Asks for permission, schedules a notification with actions and handles the user's answer.
            final class NotificationController: NSObject, UNUserNotificationCenterDelegate {
                func scheduleReminder() async throws {
                    let center = UNUserNotificationCenter.current()
                    center.delegate = self // Set before the app finishes launching to receive action taps.

                    let reply = UNTextInputNotificationAction(identifier: "reply", title: "Reply")
                    let delete = UNNotificationAction(identifier: "delete", title: "Delete", options: [.destructive, .authenticationRequired])
                    center.setNotificationCategories([
                        UNNotificationCategory(identifier: "message", actions: [reply, delete], intentIdentifiers: []),
                    ])

                    guard try await center.requestAuthorization(options: [.alert, .sound, .badge]) else { return }
                    let content = UNMutableNotificationContent()
                    content.title = "Build finished"
                    content.body = "Tap to see the results."
                    content.categoryIdentifier = "message"
                    content.threadIdentifier = "builds"
                    content.interruptionLevel = .timeSensitive
                    let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
                    try await center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger))
                }

                func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
                    [.banner, .sound, .list] // Also show it while the app is in the foreground.
                }

                func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
                    if let text = (response as? UNTextInputNotificationResponse)?.userText {
                        print("Reply: \(text)")
                    } else {
                        print("Action: \(response.actionIdentifier)")
                    }
                }
            }
            """#,
            entitlements: [
                "com.apple.developer.usernotifications.time-sensitive = true",
                "aps-environment = development (only for remote notifications)",
            ],
            capabilities: ["Time Sensitive Notifications", "Push Notifications (only for remote notifications)"],
            notes: [
                "Local notifications need no entitlement; .timeSensitive without the entitlement is delivered as .active.",
                "The delegate is held weakly: keep a strong reference to it for the app's lifetime.",
                "Custom notification UI and mutating push payloads need a Notification Content or Service extension.",
            ]
        ),
    ]
}
