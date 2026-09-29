import Foundation
import Combine
import SwiftUI
#if canImport(UserNotifications)
import UserNotifications
#endif
#if canImport(ImageIO)
import ImageIO
#endif
#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif
#if canImport(Intents) && os(iOS)
import Intents
#endif
#if os(iOS) || os(tvOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

// MARK: - Choices

/// `UNNotificationInterruptionLevel` with what each level needs to take effect.
enum NotificationInterruptionChoice: String, CaseIterable, Identifiable {
    case passive, active, timeSensitive, critical

    var id: String { rawValue }

    var title: String {
        switch self {
        case .passive: "Passive"
        case .active: "Active"
        case .timeSensitive: "Time Sensitive"
        case .critical: "Critical"
        }
    }

    var summary: String {
        switch self {
        case .passive: "Added to Notification Center without sound, banner or screen wake."
        case .active: "The default: banner, sound and screen wake; held back by Focus and the scheduled summary."
        case .timeSensitive: "Breaks through Focus and the scheduled summary, but only with the time-sensitive entitlement and while the person keeps Time Sensitive Notifications on for the app."
        case .critical: "Plays even when muted and in Focus. Needs Apple's critical-alerts entitlement and the person's separate consent; without them iOS delivers it like an active notification."
        }
    }

    /// Capability in `CapabilityRegistry` the level depends on.
    var capabilityID: String? {
        switch self {
        case .timeSensitive: "time-sensitive-notifications"
        case .critical: "critical-alerts"
        default: nil
        }
    }

    var entitlementKey: String? {
        switch self {
        case .timeSensitive: "com.apple.developer.usernotifications.time-sensitive"
        case .critical: "com.apple.developer.usernotifications.critical-alerts"
        default: nil
        }
    }

    #if canImport(UserNotifications)
    var level: UNNotificationInterruptionLevel {
        switch self {
        case .passive: .passive
        case .active: .active
        case .timeSensitive: .timeSensitive
        case .critical: .critical
        }
    }
    #endif
}

enum NotificationAuthorizationChoice: String, CaseIterable, Identifiable {
    case standard, provisional, criticalAlert

    var id: String { rawValue }

    var title: String {
        switch self {
        case .standard: "Alert, sound, badge"
        case .provisional: "Provisional (no prompt, quiet)"
        case .criticalAlert: "Alert, sound, badge + critical alert"
        }
    }

    #if canImport(UserNotifications)
    var options: UNAuthorizationOptions {
        switch self {
        case .standard: [.alert, .sound, .badge, .providesAppNotificationSettings]
        case .provisional: [.alert, .sound, .badge, .provisional]
        case .criticalAlert: [.alert, .sound, .badge, .criticalAlert]
        }
    }
    #endif
}

enum NotificationThreadChoice: String, CaseIterable, Identifiable {
    case none = ""
    case measurements = "toolbox.thread.measurements"
    case reports = "toolbox.thread.reports"

    var id: String { rawValue.isEmpty ? "none" : rawValue }

    var title: String {
        switch self {
        case .none: "No thread (grouped by app)"
        case .measurements: "Measurements"
        case .reports: "Reports"
        }
    }
}

enum NotificationDelayChoice: Int, CaseIterable, Identifiable {
    case one = 1, five = 5, fifteen = 15, minute = 60

    var id: Int { rawValue }
    var title: String { rawValue < 60 ? "\(rawValue) s" : "1 min" }
}

// MARK: - Formatting

nonisolated enum NotificationFormatting {
    /// APNs device tokens are shown the way a provider server sends them: lowercase hex without separators.
    static func hex(_ token: Data) -> String {
        token.map { String(format: "%02x", $0) }.joined()
    }

    #if canImport(UserNotifications)
    static func authorization(_ status: UNAuthorizationStatus) -> String {
        switch status {
        case .notDetermined: "Not determined"
        case .denied: "Denied"
        case .authorized: "Authorized"
        case .provisional: "Provisional"
        #if os(iOS)
        case .ephemeral: "Ephemeral (App Clip)"
        #endif
        @unknown default: "Unknown (\(status.rawValue))"
        }
    }

    static func setting(_ setting: UNNotificationSetting) -> String {
        switch setting {
        case .notSupported: "Not supported"
        case .disabled: "Disabled"
        case .enabled: "Enabled"
        @unknown default: "Unknown (\(setting.rawValue))"
        }
    }

    static func level(_ level: UNNotificationInterruptionLevel) -> String {
        switch level {
        case .passive: "passive"
        case .active: "active"
        case .timeSensitive: "timeSensitive"
        case .critical: "critical"
        @unknown default: "level \(level.rawValue)"
        }
    }
    #endif
}

// MARK: - Delegate log

/// One thing the notification delegate or the APNs registration reported.
nonisolated struct NotificationEvent: Codable, Identifiable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable { case presented, response, settings, token, tokenError }

    let id: UUID
    let date: Date
    let kind: Kind
    let title: String
    let detail: String

    init(kind: Kind, title: String, detail: String, date: Date = Date()) {
        self.id = UUID()
        self.date = date
        self.kind = kind
        self.title = title
        self.detail = detail
    }

    var symbolName: String {
        switch kind {
        case .presented: "bell.badge"
        case .response: "hand.tap"
        case .settings: "gear"
        case .token: "key"
        case .tokenError: "exclamationmark.triangle"
        }
    }
}

/// Persists the delegate log so responses to actions tapped while the app was not running still show up.
/// The delegate writes from its callback queue; UserDefaults is thread-safe and the lock keeps appends atomic.
nonisolated enum NotificationEventStore {
    private static let key = "notifications.delegateLog"
    private static let limit = 40
    private static let lock = NSLock()

    static func load() -> [NotificationEvent] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([NotificationEvent].self, from: data)) ?? []
    }

    static func append(_ event: NotificationEvent) {
        lock.withLock {
            let events = Array(([event] + load()).prefix(limit))
            if let data = try? JSONEncoder().encode(events) { UserDefaults.standard.set(data, forKey: key) }
        }
    }

    static func clear() {
        lock.withLock { UserDefaults.standard.removeObject(forKey: key) }
    }
}

/// What the app-wide notification delegate and the APNs callbacks saw, for the run view.
@MainActor
final class NotificationEventLog: ObservableObject {
    static let shared = NotificationEventLog()

    @Published private(set) var events = NotificationEventStore.load()
    @Published private(set) var deviceToken: String?
    @Published private(set) var registrationError: String?

    func reload() { events = NotificationEventStore.load() }

    func clear() {
        NotificationEventStore.clear()
        reload()
    }

    func didRegister(deviceToken token: Data) {
        let hex = NotificationFormatting.hex(token)
        deviceToken = hex
        registrationError = nil
        NotificationEventStore.append(NotificationEvent(kind: .token, title: "APNs device token", detail: "\(token.count) bytes: \(hex)"))
        reload()
    }

    func didFailToRegister(_ error: any Error) {
        let nsError = error as NSError
        registrationError = "\(nsError.domain) \(nsError.code): \(nsError.localizedDescription)"
        NotificationEventStore.append(NotificationEvent(kind: .tokenError, title: "APNs registration failed", detail: registrationError ?? ""))
        reload()
    }
}

#if canImport(UserNotifications)
extension NotificationEvent {
    nonisolated static func presented(_ notification: UNNotification) -> NotificationEvent {
        let request = notification.request
        #if os(tvOS)
        let lines = ["request \(request.identifier)", "badge \(request.content.badge.map { "\($0)" } ?? "unchanged")"]
        #else
        var lines = ["request \(request.identifier)", "level \(NotificationFormatting.level(request.content.interruptionLevel))"]
        if !request.content.categoryIdentifier.isEmpty { lines.append("category \(request.content.categoryIdentifier)") }
        if !request.content.threadIdentifier.isEmpty { lines.append("thread \(request.content.threadIdentifier)") }
        #endif
        return NotificationEvent(kind: .presented, title: "willPresent: shown while the app was in the foreground",
                                 detail: (lines + ["presentation options: banner, list, sound, badge"]).joined(separator: "\n"))
    }

    #if !os(tvOS)
    nonisolated static func response(_ response: UNNotificationResponse) -> NotificationEvent {
        let request = response.notification.request
        var lines = ["request \(request.identifier)"]
        if !request.content.categoryIdentifier.isEmpty { lines.append("category \(request.content.categoryIdentifier)") }
        if let text = (response as? UNTextInputNotificationResponse)?.userText { lines.append("typed text “\(text)”") }
        if !request.content.threadIdentifier.isEmpty { lines.append("thread \(request.content.threadIdentifier)") }
        lines.append("delivered \(response.notification.date.formatted(date: .omitted, time: .standard))")
        let title = ToolboxNotificationAction.title(for: response.actionIdentifier, defaultIdentifier: UNNotificationDefaultActionIdentifier,
                                                    dismissIdentifier: UNNotificationDismissActionIdentifier)
        return NotificationEvent(kind: .response, title: "didReceive: \(title)", detail: lines.joined(separator: "\n"))
    }
    #endif
}

// MARK: - Categories and delegate

#if !os(tvOS)
/// The categories registered at launch. The `report` category is drawn by the notification content extension on iOS.
enum ToolboxNotificationCategories {
    static var all: Set<UNNotificationCategory> { [actions, report] }

    static var actions: UNNotificationCategory {
        let reply = UNTextInputNotificationAction(identifier: ToolboxNotificationAction.reply, title: "Reply", options: [],
                                                  icon: UNNotificationActionIcon(systemImageName: "arrowshape.turn.up.left"),
                                                  textInputButtonTitle: "Send", textInputPlaceholder: "Message for Apple Toolbox")
        let verify = UNNotificationAction(identifier: ToolboxNotificationAction.verify, title: "Mark Verified", options: [.authenticationRequired],
                                          icon: UNNotificationActionIcon(systemImageName: "lock"))
        let open = UNNotificationAction(identifier: ToolboxNotificationAction.open, title: "Open Experiment", options: [.foreground],
                                        icon: UNNotificationActionIcon(systemImageName: "arrow.up.forward.app"))
        let delete = UNNotificationAction(identifier: ToolboxNotificationAction.delete, title: "Delete", options: [.destructive],
                                          icon: UNNotificationActionIcon(systemImageName: "trash"))
        return category(.actions, actions: [reply, verify, open, delete])
    }

    static var report: UNNotificationCategory {
        let acknowledge = UNNotificationAction(identifier: ToolboxNotificationAction.acknowledge, title: "Acknowledge", options: [],
                                               icon: UNNotificationActionIcon(systemImageName: "checkmark.circle"))
        let open = UNNotificationAction(identifier: ToolboxNotificationAction.open, title: "Open Experiment", options: [.foreground],
                                        icon: UNNotificationActionIcon(systemImageName: "arrow.up.forward.app"))
        return category(.report, actions: [acknowledge, open])
    }

    private static func category(_ category: ToolboxNotificationCategory, actions: [UNNotificationAction]) -> UNNotificationCategory {
        #if os(watchOS)
        // watchOS has no hidden-preview placeholder or summary format; the watch shows the actions below the notification.
        UNNotificationCategory(identifier: category.rawValue, actions: actions, intentIdentifiers: [], options: [.customDismissAction])
        #else
        UNNotificationCategory(identifier: category.rawValue, actions: actions, intentIdentifiers: [],
                               hiddenPreviewsBodyPlaceholder: "Apple Toolbox notification",
                               categorySummaryFormat: "%u more Apple Toolbox notifications",
                               options: [.customDismissAction, .hiddenPreviewsShowTitle])
        #endif
    }
}
#endif

/// App-wide `UNUserNotificationCenterDelegate`. Installed while the app launches, so a response to an action
/// tapped while the app was not running is delivered as soon as the system launches the app for it.
final class ToolboxNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = ToolboxNotificationDelegate()

    static func install() {
        let center = UNUserNotificationCenter.current()
        center.delegate = shared
        #if !os(tvOS)
        center.setNotificationCategories(ToolboxNotificationCategories.all)
        #endif
    }

    // UserNotifications calls the delegate on a private queue, so these stay nonisolated and hop to the main actor.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        NotificationEventStore.append(.presented(notification))
        Task { @MainActor in NotificationEventLog.shared.reload() }
        completionHandler([.banner, .list, .sound, .badge])
    }

    #if !os(tvOS)
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        NotificationEventStore.append(.response(response))
        #if os(watchOS)
        Task { @MainActor in NotificationEventLog.shared.reload() }
        #else
        let opensApp = [UNNotificationDefaultActionIdentifier, ToolboxNotificationAction.open].contains(response.actionIdentifier)
        Task { @MainActor in
            NotificationEventLog.shared.reload()
            // The default and the foreground action bring the app forward; show the experiment that sent the notification.
            if opensApp { ToolboxNavigator.shared.request = .experiment("notifications") }
        }
        #endif
        completionHandler()
    }
    #endif

    #if os(iOS) || os(macOS)
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, openSettingsFor notification: UNNotification?) {
        let source = notification.map { "from notification \($0.request.identifier)" } ?? "from the app's notification settings"
        NotificationEventStore.append(NotificationEvent(kind: .settings, title: "openSettingsFor: in-app notification settings requested", detail: source))
        Task { @MainActor in NotificationEventLog.shared.reload() }
    }
    #endif
}
#endif

// MARK: - App delegate

#if os(iOS) || os(tvOS)
/// Installs the notification delegate before launch completes and receives the APNs device token.
final class ToolboxAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, willFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        ToolboxNotificationDelegate.install()
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        NotificationEventLog.shared.didRegister(deviceToken: deviceToken)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: any Error) {
        NotificationEventLog.shared.didFailToRegister(error)
    }
}
#elseif os(macOS)
/// Installs the notification delegate before launch completes and receives the APNs device token.
final class ToolboxAppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        ToolboxNotificationDelegate.install()
    }

    func application(_ application: NSApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        NotificationEventLog.shared.didRegister(deviceToken: deviceToken)
    }

    func application(_ application: NSApplication, didFailToRegisterForRemoteNotificationsWithError error: any Error) {
        NotificationEventLog.shared.didFailToRegister(error)
    }
}
#endif

// MARK: - Experiment service

nonisolated struct NotificationSettingRow: Identifiable, Equatable, Sendable {
    var id: String { title }
    let title: String
    let value: String
}

/// Settings read in the completion handler and carried to the main actor as plain values.
nonisolated struct NotificationSettingsSnapshot: Equatable, Sendable {
    var authorization = "Not read yet"
    var isAuthorized = false
    var timeSensitive: String?
    var criticalAlert: String?
    var rows: [NotificationSettingRow] = []

    #if canImport(UserNotifications)
    init() {}

    init(_ settings: UNNotificationSettings) {
        authorization = NotificationFormatting.authorization(settings.authorizationStatus)
        isAuthorized = [.authorized, .provisional].contains(settings.authorizationStatus)
        var rows = [NotificationSettingRow(title: "Authorization", value: authorization)]
        #if !os(watchOS)
        rows.append(NotificationSettingRow(title: "Badge", value: NotificationFormatting.setting(settings.badgeSetting)))
        #endif
        #if !os(tvOS)
        timeSensitive = NotificationFormatting.setting(settings.timeSensitiveSetting)
        criticalAlert = NotificationFormatting.setting(settings.criticalAlertSetting)
        rows += [NotificationSettingRow(title: "Alert", value: NotificationFormatting.setting(settings.alertSetting)),
                 NotificationSettingRow(title: "Sound", value: NotificationFormatting.setting(settings.soundSetting)),
                 NotificationSettingRow(title: "Notification Center", value: NotificationFormatting.setting(settings.notificationCenterSetting)),
                 NotificationSettingRow(title: "Time Sensitive", value: timeSensitive ?? ""),
                 NotificationSettingRow(title: "Critical alerts", value: criticalAlert ?? ""),
                 NotificationSettingRow(title: "Scheduled summary", value: NotificationFormatting.setting(settings.scheduledDeliverySetting)),
                 NotificationSettingRow(title: "Direct messages", value: NotificationFormatting.setting(settings.directMessagesSetting)),
                 NotificationSettingRow(title: "In-app settings link", value: settings.providesAppNotificationSettings ? "Provided" : "Not provided")]
        #endif
        #if os(iOS) || os(macOS)
        rows.append(NotificationSettingRow(title: "Lock Screen", value: NotificationFormatting.setting(settings.lockScreenSetting)))
        let style = switch settings.alertStyle { case .none: "None"; case .banner: "Banner"; case .alert: "Alert"; @unknown default: "Unknown" }
        rows.append(NotificationSettingRow(title: "Alert style", value: style))
        let previews = switch settings.showPreviewsSetting { case .always: "Always"; case .whenAuthenticated: "When unlocked"; case .never: "Never"; @unknown default: "Unknown" }
        rows.append(NotificationSettingRow(title: "Show previews", value: previews))
        #endif
        self.rows = rows
    }
    #endif
}

/// One pending or delivered request as plain values.
nonisolated struct NotificationRequestSummary: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let detail: String

    #if canImport(UserNotifications)
    init(_ request: UNNotificationRequest, deliveredAt: Date? = nil) {
        id = request.identifier
        #if os(tvOS)
        title = request.identifier
        detail = "badge \(request.content.badge.map { "\($0)" } ?? "unchanged")"
        #else
        title = request.content.title.isEmpty ? request.identifier : request.content.title
        var parts = [request.identifier, NotificationFormatting.level(request.content.interruptionLevel)]
        if !request.content.categoryIdentifier.isEmpty { parts.append(request.content.categoryIdentifier) }
        if !request.content.threadIdentifier.isEmpty { parts.append(request.content.threadIdentifier) }
        if !request.content.attachments.isEmpty { parts.append("\(request.content.attachments.count) attachment(s)") }
        if let deliveredAt { parts.append("delivered \(deliveredAt.formatted(date: .omitted, time: .standard))") }
        else if let next = (request.trigger as? UNTimeIntervalNotificationTrigger)?.nextTriggerDate() {
            parts.append("fires \(next.formatted(date: .omitted, time: .standard))")
        }
        detail = parts.joined(separator: " · ")
        #endif
    }
    #endif
}

/// Registered categories as plain values.
nonisolated struct NotificationCategorySummary: Identifiable, Equatable, Sendable {
    let id: String
    let actions: String
}

@MainActor
final class NotificationExperimentService: ObservableObject {
    @Published var authorizationChoice = NotificationAuthorizationChoice.standard
    @Published var category = ToolboxNotificationCategory.actions
    @Published var interruption = NotificationInterruptionChoice.active
    @Published var thread = NotificationThreadChoice.measurements
    @Published var delay = NotificationDelayChoice.five
    @Published var includeAttachment = true
    @Published var badgeCount = 1
    static let badgePresets = [1, 2, 5, 12, 99]

    @Published private(set) var settings = NotificationSettingsSnapshot()
    @Published private(set) var categories: [NotificationCategorySummary] = []
    @Published private(set) var pending: [NotificationRequestSummary] = []
    @Published private(set) var delivered: [NotificationRequestSummary] = []
    @Published private(set) var output = "Request authorization, then schedule a notification. Lock the device or leave the app to see it as a banner; the delegate log below shows what the app received."
    @Published private(set) var isError = false
    @Published private(set) var badgeOutput = "The badge is set with UNUserNotificationCenter.setBadgeCount(_:)."
    @Published private(set) var apnsOutput = "Not registered in this session."
    @Published private(set) var communicationOutput = "Not tried yet."

    /// Reads settings, registered categories and the pending and delivered lists.
    func refresh() {
        #if canImport(UserNotifications)
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { @Sendable [weak self] settings in
            let snapshot = NotificationSettingsSnapshot(settings)
            Task { @MainActor in self?.settings = snapshot }
        }
        #if !os(tvOS)
        center.getNotificationCategories { @Sendable [weak self] categories in
            let summaries = categories.map { category in
                NotificationCategorySummary(id: category.identifier, actions: category.actions.map { action in
                    var flags: [String] = []
                    if action is UNTextInputNotificationAction { flags.append("text input") }
                    if action.options.contains(.authenticationRequired) { flags.append("auth") }
                    if action.options.contains(.destructive) { flags.append("destructive") }
                    if action.options.contains(.foreground) { flags.append("foreground") }
                    return flags.isEmpty ? action.title : "\(action.title) (\(flags.joined(separator: ", ")))"
                }.joined(separator: " · "))
            }.sorted { $0.id < $1.id }
            Task { @MainActor in self?.categories = summaries }
        }
        #endif
        refreshLists()
        #endif
        reloadServiceRecord()
    }

    func refreshLists() {
        #if canImport(UserNotifications)
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { @Sendable [weak self] requests in
            let summaries = requests.map { NotificationRequestSummary($0) }
            Task { @MainActor in self?.pending = summaries }
        }
        #if !os(tvOS)
        center.getDeliveredNotifications { @Sendable [weak self] notifications in
            let summaries = notifications.map { NotificationRequestSummary($0.request, deliveredAt: $0.date) }
            Task { @MainActor in self?.delivered = summaries }
        }
        #endif
        #endif
    }

    func requestAuthorization() {
        #if canImport(UserNotifications)
        let choice = authorizationChoice
        UNUserNotificationCenter.current().requestAuthorization(options: choice.options) { @Sendable [weak self] granted, error in
            Task { @MainActor in
                await PermissionCenter.shared.refresh()
                guard let self else { return }
                if let error {
                    self.show("requestAuthorization(\(choice.title)) failed: \(error.localizedDescription)", isError: true)
                } else {
                    var text = "requestAuthorization(\(choice.title)) returned granted = \(granted)."
                    if choice == .criticalAlert {
                        text += "\nThe .criticalAlert option is only honored with Apple's critical-alerts entitlement; see “Critical alerts” in the settings below for the real result."
                    }
                    if choice == .provisional { text += "\nProvisional authorization never prompts; notifications arrive quietly in Notification Center with Keep/Turn Off buttons." }
                    self.show(text, isError: !granted)
                }
                self.refresh()
            }
        }
        #else
        show("UserNotifications is not available on this platform.", isError: true)
        #endif
    }

    func schedule() {
        #if canImport(UserNotifications) && !os(tvOS)
        let content = UNMutableNotificationContent()
        content.title = "Apple Toolbox · \(interruption.title)"
        content.subtitle = category.title
        content.body = category == .report
            ? "Long-press to open the custom report drawn by the notification content extension."
            : "Scheduled \(Date().formatted(date: .omitted, time: .standard)) by the UserNotifications experiment. Long-press for the actions."
        content.categoryIdentifier = category.rawValue
        content.threadIdentifier = thread.rawValue
        content.interruptionLevel = interruption.level
        content.relevanceScore = interruption == .passive ? 0.1 : 0.8
        #if os(iOS)
        content.sound = interruption == .passive ? nil : interruption == .critical ? .defaultCritical : .default
        #else
        content.sound = interruption == .passive ? nil : .default
        #endif
        if category == .report {
            let statuses = ExperimentRegistry.all.map(\.currentStatus)
            let report = ToolboxNotificationReport(platform: CurrentPlatform.value.rawValue, statusTitles: statuses.map(\.title),
                                                   availableTitle: ExperimentStatus.available.title, measuredAt: Date())
            content.userInfo = report.userInfo
        }
        var notes: [String] = []
        if includeAttachment {
            do {
                let url = try NotificationArtwork.renderPNG(title: interruption.title, subtitle: category.title)
                let attachment = try UNNotificationAttachment(identifier: "artwork", url: url, options: [UNNotificationAttachmentOptionsTypeHintKey: UTType.png.identifier])
                content.attachments = [attachment]
                notes.append("Attachment: \(url.lastPathComponent) rendered with ImageRenderer; UserNotifications moved it into its own store.")
            } catch {
                notes.append("Attachment failed: \(error.localizedDescription)")
            }
        }
        notes += boundaryNotes()
        let identifier = "toolbox.\(UUID().uuidString.prefix(8).lowercased())"
        let seconds = delay.rawValue
        let request = UNNotificationRequest(identifier: identifier, content: content,
                                            trigger: UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(seconds), repeats: false))
        let details = notes
        let summary = "\(identifier) fires in \(seconds) s · level .\(NotificationFormatting.level(content.interruptionLevel)) · category \(category.rawValue.isEmpty ? "none" : category.rawValue) · thread \(thread.rawValue.isEmpty ? "none" : thread.rawValue)"
        UNUserNotificationCenter.current().add(request) { @Sendable [weak self] error in
            Task { @MainActor in
                guard let self else { return }
                if let error {
                    self.show("add(_:) failed: \(error.localizedDescription)", isError: true)
                } else {
                    self.show((["Scheduled \(summary)."] + details).joined(separator: "\n"), isError: false)
                }
                self.refreshLists()
            }
        }
        #else
        show("On tvOS notifications can only change the app icon badge; alerts, sounds, actions and attachments are unavailable.", isError: true)
        #endif
    }

    /// What decides whether the chosen interruption level takes effect.
    private func boundaryNotes() -> [String] {
        guard let capability = interruption.capabilityID, let key = interruption.entitlementKey else { return [] }
        let entitlement = IdentityEntitlements.summary(of: IdentityEntitlements.state(ofCapability: capability), key: key)
        let setting = interruption == .timeSensitive ? settings.timeSensitive : settings.criticalAlert
        return [entitlement, "\(interruption.title) setting for this app: \(setting ?? "not read yet")."]
    }

    func setBadge() { applyBadge(badgeCount) }
    func clearBadge() { applyBadge(0) }

    private func applyBadge(_ count: Int) {
        #if canImport(UserNotifications) && !os(watchOS)
        UNUserNotificationCenter.current().setBadgeCount(count) { @Sendable [weak self] error in
            Task { @MainActor in
                self?.badgeOutput = error.map { "setBadgeCount(\(count)) failed: \($0.localizedDescription)" }
                    ?? "setBadgeCount(\(count)) succeeded. The badge only shows when badges are allowed for the app (Badge: \(self?.settings.rows.first { $0.title == "Badge" }?.value ?? "unknown"))."
            }
        }
        #endif
    }

    func removePending(_ identifier: String) {
        #if canImport(UserNotifications)
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
        refreshLists()
        #endif
    }

    func removeAllPending() {
        #if canImport(UserNotifications)
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        refreshLists()
        #endif
    }

    func removeDelivered(_ identifier: String) {
        #if canImport(UserNotifications) && !os(tvOS)
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [identifier])
        refreshLists()
        #endif
    }

    func removeAllDelivered() {
        #if canImport(UserNotifications) && !os(tvOS)
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        refreshLists()
        #endif
    }

    // MARK: APNs

    var apnsEntitlement: String {
        IdentityEntitlements.summary(of: IdentityEntitlements.state(ofCapability: "push-notifications"), key: "aps-environment")
    }

    var isRegisteredForRemoteNotifications: Bool? {
        #if os(iOS) || os(tvOS)
        UIApplication.shared.isRegisteredForRemoteNotifications
        #elseif os(macOS)
        NSApplication.shared.isRegisteredForRemoteNotifications
        #else
        nil
        #endif
    }

    func registerForRemoteNotifications() {
        #if os(iOS) || os(tvOS)
        UIApplication.shared.registerForRemoteNotifications()
        #elseif os(macOS)
        NSApplication.shared.registerForRemoteNotifications()
        #endif
        apnsOutput = "registerForRemoteNotifications() called at \(Date().formatted(date: .omitted, time: .standard)). The token or the error arrives in the app delegate and appears above and in the delegate log."
    }

    // MARK: Communication notifications

    var communicationEntitlement: String {
        IdentityEntitlements.summary(of: IdentityEntitlements.state(ofCapability: "communication-notifications"), key: "com.apple.developer.usernotifications.communication")
    }

    /// Donates an incoming INSendMessageIntent and asks UserNotifications to turn a notification into a communication
    /// notification with it. Without the capability the system rejects or ignores the update; the real result is shown.
    func tryCommunicationNotification() {
        #if canImport(Intents) && os(iOS)
        let sender = INPerson(personHandle: INPersonHandle(value: "toolbox-sender", type: .unknown), nameComponents: nil, displayName: "Apple Toolbox",
                              image: nil, contactIdentifier: nil, customIdentifier: "toolbox.sender",
                              isMe: false, suggestionType: .none)
        let intent = INSendMessageIntent(recipients: nil, outgoingMessageType: .outgoingMessageText, content: "Communication notification test",
                                         speakableGroupName: nil, conversationIdentifier: "toolbox.conversation", serviceName: nil,
                                         sender: sender, attachments: nil)
        let interaction = INInteraction(intent: intent, response: nil)
        interaction.direction = .incoming
        interaction.donate { @Sendable [weak self] error in
            Task { @MainActor in
                self?.communicationOutput += "\nINInteraction.donate: " + (error.map { "failed: \($0.localizedDescription)" } ?? "succeeded")
            }
        }
        let content = UNMutableNotificationContent()
        content.title = "Apple Toolbox"
        content.body = "Communication notification test"
        content.threadIdentifier = "toolbox.conversation"
        do {
            let updated = try content.updating(from: intent)
            let request = UNNotificationRequest(identifier: "toolbox.communication", content: updated,
                                                trigger: UNTimeIntervalNotificationTrigger(timeInterval: 3, repeats: false))
            communicationOutput = "content.updating(from: INSendMessageIntent) returned content (title “\(updated.title)”). Scheduled for 3 s; it only shows the sender avatar if the system accepted it as a communication notification."
            UNUserNotificationCenter.current().add(request) { @Sendable [weak self] error in
                Task { @MainActor in
                    if let error { self?.communicationOutput += "\nadd(_:) failed: \(error.localizedDescription)" }
                    self?.refreshLists()
                }
            }
        } catch {
            let nsError = error as NSError
            communicationOutput = "content.updating(from: INSendMessageIntent) threw \(nsError.domain) \(nsError.code): \(nsError.localizedDescription)"
        }
        #else
        communicationOutput = "This experiment builds the INSendMessageIntent on iOS only. Communication notifications need the Communication Notifications capability, an Intents donation and NSUserActivityTypes containing INSendMessageIntent."
        #endif
    }

    // MARK: Content extension

    /// The notification content extensions embedded in this app bundle, read from their Info.plists.
    var embeddedContentExtensions: [String] { Self.bundledContentExtensions }

    private static let bundledContentExtensions: [String] = {
        guard let plugIns = Bundle.main.builtInPlugInsURL,
              let urls = try? FileManager.default.contentsOfDirectory(at: plugIns, includingPropertiesForKeys: nil) else { return [] }
        return urls.filter { $0.pathExtension == "appex" }.compactMap { url in
            guard let info = Bundle(url: url)?.infoDictionary, let ext = info["NSExtension"] as? [String: Any],
                  ext["NSExtensionPointIdentifier"] as? String == "com.apple.usernotifications.content-extension" else { return nil }
            let attributes = ext["NSExtensionAttributes"] as? [String: Any]
            let categories = (attributes?["UNNotificationExtensionCategory"] as? String).map { [$0] } ?? attributes?["UNNotificationExtensionCategory"] as? [String] ?? []
            return "\(url.lastPathComponent) · categories: \(categories.joined(separator: ", "))"
        }
    }()

    var supportsContentExtensions: Bool {
        #if canImport(UserNotifications)
        UNUserNotificationCenter.current().supportsContentExtensions
        #else
        false
        #endif
    }

    // MARK: Service extension

    static let serviceExtensionPoint = "com.apple.usernotifications.service"

    /// The notification service extensions embedded in this app bundle.
    var embeddedServiceExtensions: [EmbeddedAppExtension] {
        EmbeddedAppExtension.embedded(extensionPoint: Self.serviceExtensionPoint)
    }

    /// What the service extension wrote to the App Group after the last push it rewrote.
    @Published private(set) var lastServiceRecord = NotificationServiceRecordStore.load()

    func reloadServiceRecord() {
        lastServiceRecord = NotificationServiceRecordStore.load()
    }

    func clearServiceRecord() {
        NotificationServiceRecordStore.clear()
        reloadServiceRecord()
    }

    /// The HTTP/2 headers a provider sends with the sample payload.
    var sampleHeaders: String {
        "apns-push-type: alert\napns-topic: \(Bundle.main.bundleIdentifier ?? "<bundle identifier>")\napns-priority: 10"
    }

    private func show(_ text: String, isError: Bool) {
        output = text
        self.isError = isError
    }
}

// MARK: - Attachment artwork

/// Renders the notification attachment at runtime with SwiftUI's ImageRenderer and writes it as PNG.
enum NotificationArtwork {
    static func renderPNG(title: String, subtitle: String) throws -> URL {
        let renderer = ImageRenderer(content: NotificationArtworkView(title: title, subtitle: subtitle, date: Date()))
        renderer.scale = 2
        guard let image = renderer.cgImage else { throw ExperimentServiceError.unavailable("ImageRenderer returned no image.") }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("toolbox-artwork-\(UUID().uuidString).png")
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw ExperimentServiceError.unavailable("ImageIO could not create a PNG destination.")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw ExperimentServiceError.unavailable("ImageIO could not write the PNG.") }
        return url
    }
}

private struct NotificationArtworkView: View {
    let title: String
    let subtitle: String
    let date: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "app.badge.fill").font(.system(size: 44, weight: .semibold))
            Spacer(minLength: 0)
            Text(title).font(.system(size: 30, weight: .bold, design: .rounded))
            Text(subtitle).font(.system(size: 16, weight: .medium))
            Text("Rendered \(date.formatted(date: .abbreviated, time: .standard))").font(.system(size: 13, design: .monospaced)).opacity(0.8)
        }
        .foregroundStyle(.white)
        .padding(24)
        .frame(width: 360, height: 220, alignment: .leading)
        .background(LinearGradient(colors: [.indigo, .teal], startPoint: .topLeading, endPoint: .bottomTrailing))
    }
}
