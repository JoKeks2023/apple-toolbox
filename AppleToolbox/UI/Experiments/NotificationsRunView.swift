import SwiftUI

/// UserNotifications (spec §26): authorization and settings, categories with actions, interruption levels,
/// runtime-rendered attachments, threads, badge, pending/delivered lists, the delegate log, the content
/// extension, APNs registration and the communication/critical boundaries.
struct NotificationsRunView: View {
    @StateObject private var service = NotificationExperimentService()
    @ObservedObject private var log = NotificationEventLog.shared

    var body: some View {
        NotificationAuthorizationSection(service: service)
        #if !os(tvOS)
        NotificationComposeSection(service: service)
        #endif
        NotificationBadgeSection(service: service)
        NotificationDelegateLogSection(log: log)
        NotificationListsSection(service: service)
        #if !os(tvOS)
        NotificationCategoriesSection(service: service)
        #endif
        NotificationAPNsSection(service: service, log: log)
        #if !os(tvOS)
        NotificationBoundariesSection(service: service)
        #endif
    }
}

private struct NotificationAuthorizationSection: View {
    @ObservedObject var service: NotificationExperimentService

    var body: some View {
        Section("Authorization & settings") {
            Picker("Request", selection: $service.authorizationChoice) {
                ForEach(NotificationAuthorizationChoice.allCases) { Text($0.title).tag($0) }
            }
            Button("Request Authorization", action: service.requestAuthorization)
                .buttonStyle(.borderedProminent)
            ForEach(service.settings.rows) { row in
                LabeledContent(row.title, value: row.value)
            }
            Button("Re-read Settings", systemImage: "arrow.clockwise", action: service.refresh)
        }
        .onAppear(perform: service.refresh)
    }
}

#if !os(tvOS)
private struct NotificationComposeSection: View {
    @ObservedObject var service: NotificationExperimentService

    var body: some View {
        Section("Compose") {
            Picker("Category", selection: $service.category) {
                ForEach(ToolboxNotificationCategory.allCases) { Text($0.title).tag($0) }
            }
            Picker("Interruption level", selection: $service.interruption) {
                ForEach(NotificationInterruptionChoice.allCases) { Text($0.title).tag($0) }
            }
            Text(service.interruption.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
            Picker("Thread", selection: $service.thread) {
                ForEach(NotificationThreadChoice.allCases) { Text($0.title).tag($0) }
            }
            Picker("Deliver after", selection: $service.delay) {
                ForEach(NotificationDelayChoice.allCases) { Text($0.title).tag($0) }
            }
            Toggle("Attach an image rendered now", isOn: $service.includeAttachment)
            Button("Schedule Notification", action: service.schedule)
                .buttonStyle(.borderedProminent)
            OutputView(text: service.output, isError: service.isError)
            Text("Actions: Reply opens a text field, Mark Verified asks to unlock first, Open Experiment launches the app, Delete is destructive; dismissing is reported too. Notifications in one thread are grouped and summarized with the category's summary format.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
#endif

private struct NotificationBadgeSection: View {
    @ObservedObject var service: NotificationExperimentService

    var body: some View {
        Section("Badge") {
            #if os(watchOS)
            Text("watchOS has no app icon badge.")
            #else
            Picker("Badge count", selection: $service.badgeCount) {
                ForEach(NotificationExperimentService.badgePresets, id: \.self) { Text("\($0)").tag($0) }
            }
            HStack {
                Button("Set Badge", action: service.setBadge).buttonStyle(.bordered)
                Button("Clear Badge", action: service.clearBadge).buttonStyle(.bordered)
            }
            Text(service.badgeOutput).font(.caption.monospaced())
            #endif
        }
    }
}

private struct NotificationDelegateLogSection: View {
    @ObservedObject var log: NotificationEventLog

    var body: some View {
        Section("Delegate log (\(log.events.count))") {
            Text("The UNUserNotificationCenterDelegate is installed at launch by the app delegate, so actions tapped while the app was closed are logged here too.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if log.events.isEmpty {
                Text("Nothing received yet. Schedule a notification and act on it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(log.events) { event in
                VStack(alignment: .leading, spacing: 3) {
                    Label(event.title, systemImage: event.symbolName).font(.subheadline.weight(.semibold))
                    Text(event.detail).font(.caption.monospaced()).foregroundStyle(.secondary)
                    Text(event.date.formatted(date: .abbreviated, time: .standard)).font(.caption2).foregroundStyle(.tertiary)
                }
            }
            if !log.events.isEmpty {
                Button("Clear Log", systemImage: "trash", role: .destructive, action: log.clear)
            }
        }
        .onAppear(perform: log.reload)
    }
}

private struct NotificationListsSection: View {
    @ObservedObject var service: NotificationExperimentService

    var body: some View {
        Section("Pending (\(service.pending.count))") {
            ForEach(service.pending) { request in
                RequestRow(request: request) { service.removePending(request.id) }
            }
            HStack {
                Button("Refresh", systemImage: "arrow.clockwise", action: service.refreshLists)
                if !service.pending.isEmpty {
                    Spacer()
                    Button("Remove All Pending", role: .destructive, action: service.removeAllPending)
                }
            }
            .buttonStyle(.borderless)
        }
        #if !os(tvOS)
        Section("Delivered (\(service.delivered.count))") {
            if service.delivered.isEmpty {
                Text("Delivered notifications still in Notification Center appear here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(service.delivered) { request in
                RequestRow(request: request) { service.removeDelivered(request.id) }
            }
            if !service.delivered.isEmpty {
                Button("Remove All Delivered", role: .destructive, action: service.removeAllDelivered)
            }
        }
        #endif
    }
}

private struct RequestRow: View {
    let request: NotificationRequestSummary
    let remove: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(request.title).font(.subheadline)
                Text(request.detail).font(.caption.monospaced()).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Remove", role: .destructive, action: remove)
                .buttonStyle(.borderless)
        }
    }
}

#if !os(tvOS)
private struct NotificationCategoriesSection: View {
    @ObservedObject var service: NotificationExperimentService

    var body: some View {
        Section("Registered categories · content extension") {
            ForEach(service.categories) { category in
                LabeledContent(category.id) { Text(category.actions).font(.caption).multilineTextAlignment(.trailing) }
            }
            LabeledContent("supportsContentExtensions", value: service.supportsContentExtensions ? "true" : "false")
            let extensions = service.embeddedContentExtensions
            if extensions.isEmpty {
                Text(contentExtensionBoundary).font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(extensions, id: \.self) { Text($0).font(.caption.monospaced()) }
                Text("Choose “Custom UI (content extension)” above and long-press the notification: the extension draws the device report from the notification's userInfo, and its Acknowledge action is handled inside the extension without opening the app.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var contentExtensionBoundary: String {
        #if os(iOS)
        "No notification content extension is embedded in this build, so the report category falls back to the system's default UI."
        #else
        "The notification content extension is only embedded in the iOS app; here the report category uses the system's default UI."
        #endif
    }
}
#endif

private struct NotificationAPNsSection: View {
    @ObservedObject var service: NotificationExperimentService
    @ObservedObject var log: NotificationEventLog

    var body: some View {
        Section("Remote notifications · APNs") {
            Text(service.apnsEntitlement).font(.caption)
            if let registered = service.isRegisteredForRemoteNotifications {
                LabeledContent("isRegisteredForRemoteNotifications", value: registered ? "true" : "false")
            }
            Button("Register for Remote Notifications", action: service.registerForRemoteNotifications)
                .buttonStyle(.borderedProminent)
            if let token = log.deviceToken {
                LabeledContent("Device token") { Text(token).font(.caption.monospaced()).multilineTextAlignment(.trailing) }
            }
            if let error = log.registrationError {
                OutputView(text: error, isError: true)
            } else {
                OutputView(text: service.apnsOutput, isError: false)
            }
            Text("The app can only obtain the token. Sending needs your own provider server: it authenticates to APNs with a token-signing key (.p8) or certificate and posts the JSON payload over HTTP/2 to api.sandbox.push.apple.com (development builds, aps-environment = development) or api.push.apple.com, with this token in the path and apns-topic set to the bundle identifier.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

#if !os(tvOS)
private struct NotificationBoundariesSection: View {
    @ObservedObject var service: NotificationExperimentService

    var body: some View {
        Section("Boundaries") {
            BoundaryRow(title: "Time Sensitive", gate: "Developer capability · Settings switch per app",
                        status: IdentityEntitlements.summary(of: IdentityEntitlements.state(ofCapability: "time-sensitive-notifications"), key: "com.apple.developer.usernotifications.time-sensitive"),
                        setting: service.settings.timeSensitive,
                        detail: "With the entitlement, .timeSensitive notifications break through Focus and the scheduled summary unless the person turns Time Sensitive Notifications off for the app.")
            BoundaryRow(title: "Critical Alerts", gate: "Managed capability · Apple approval",
                        status: IdentityEntitlements.summary(of: IdentityEntitlements.state(ofCapability: "critical-alerts"), key: "com.apple.developer.usernotifications.critical-alerts"),
                        setting: service.settings.criticalAlert,
                        detail: "Apple grants critical alerts only for health, safety and public-security use cases. Without the entitlement the .criticalAlert authorization option is ignored (Critical alerts stays “Not supported”) and .critical notifications arrive like active ones.")
            VStack(alignment: .leading, spacing: 6) {
                BoundaryRow(title: "Communication notifications", gate: "Developer capability · Intents donation",
                            status: service.communicationEntitlement, setting: nil,
                            detail: "Messages and calls show the sender's avatar and can break through Focus when the notification is updated with a donated INSendMessageIntent or INStartCallIntent. That needs the Communication Notifications capability and NSUserActivityTypes listing the intent in Info.plist; this build has neither, on purpose.")
                Button("Try content.updating(from: INSendMessageIntent)", action: service.tryCommunicationNotification)
                    .buttonStyle(.bordered)
                Text(service.communicationOutput).font(.caption.monospaced())
            }
        }
    }
}

private struct BoundaryRow: View {
    let title: String
    let gate: String
    let status: String
    let setting: String?
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.headline)
            Text(gate).font(.caption.weight(.medium)).foregroundStyle(.secondary)
            Text(status).font(.caption.monospaced())
            if let setting { Text("Setting for this app: \(setting)").font(.caption.monospaced()) }
            Text(detail).font(.caption)
        }
        .padding(.vertical, 2)
    }
}
#endif
