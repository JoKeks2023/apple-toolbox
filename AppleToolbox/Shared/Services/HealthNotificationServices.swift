import Foundation
import Combine

#if canImport(HealthKit) && !os(macOS) && !os(tvOS)
import HealthKit
#endif

#if canImport(UserNotifications)
import UserNotifications
#endif

@MainActor
final class HealthAuthorizationExperimentService: ObservableObject {
    @Published private(set) var output = "HealthKit authorization has not been requested."

    func requestReadAuthorization() {
        #if canImport(HealthKit) && !os(macOS) && !os(tvOS)
        guard HKHealthStore.isHealthDataAvailable() else { output = "HealthKit is not available on this device."; return }
        let store = HKHealthStore()
        guard let stepCount = HKObjectType.quantityType(forIdentifier: .stepCount) else { output = "The step-count sample type is unavailable on this OS."; return }
        store.requestAuthorization(toShare: [], read: [stepCount]) { [weak self] success, error in
            Task { @MainActor in
                if let error { self?.output = "HealthKit authorization error: \(error.localizedDescription)" }
                else { self?.output = success ? "HealthKit read authorization completed for step count. The user may still have denied individual data types." : "HealthKit authorization was not granted." }
            }
        }
        #else
        output = "HealthKit authorization is not available on this platform."
        #endif
    }
}

@MainActor
final class NotificationExperimentService: ObservableObject {
    @Published private(set) var output = "Notification authorization has not been requested."

    func requestAuthorization() {
        #if canImport(UserNotifications)
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { [weak self] granted, error in
            Task { @MainActor in
                if let error { self?.output = "Notification authorization error: \(error.localizedDescription)" }
                else { self?.output = granted ? "Notifications authorized." : "Notifications were denied or are restricted." }
            }
        }
        #else
        output = "UserNotifications is not available on this platform."
        #endif
    }

    func scheduleTestNotification() {
        #if canImport(UserNotifications)
        let content = UNMutableNotificationContent()
        content.title = "Apple Toolbox"
        content.body = "This notification came from the real UserNotifications API."
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: "apple-toolbox-test", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request) { [weak self] error in
            Task { @MainActor in self?.output = error.map { "Scheduling error: \($0.localizedDescription)" } ?? "Test notification scheduled for about one second from now." }
        }
        #else
        output = "UserNotifications is not available on this platform."
        #endif
    }
}
