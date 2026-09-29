import Foundation
import Combine

#if canImport(UserNotifications)
import UserNotifications
#endif

@MainActor
final class NotificationExperimentService: ObservableObject {
    @Published private(set) var output = "Notification authorization has not been requested."

    func requestAuthorization() {
        #if canImport(UserNotifications)
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { @Sendable [weak self] granted, error in
            Task { @MainActor in
                await PermissionCenter.shared.refresh()
                if let error { self?.output = "Notification authorization error: \(error.localizedDescription)" }
                else { self?.output = granted ? "Notifications authorized." : "Notifications were denied or are restricted." }
            }
        }
        #else
        output = "UserNotifications is not available on this platform."
        #endif
    }

    func scheduleTestNotification() {
        #if canImport(UserNotifications) && !os(tvOS)
        let content = UNMutableNotificationContent()
        content.title = "Apple Toolbox"
        content.body = "This notification came from the real UserNotifications API."
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: "apple-toolbox-test", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request) { @Sendable [weak self] error in
            Task { @MainActor in self?.output = error.map { "Scheduling error: \($0.localizedDescription)" } ?? "Test notification scheduled for about one second from now." }
        }
        #else
        output = "UserNotifications is not available on this platform."
        #endif
    }
}
