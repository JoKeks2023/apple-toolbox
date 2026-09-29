import Testing
import Foundation
import UserNotifications
@testable import AppleToolbox

@MainActor
struct NotificationTests {

    @Test func buildsTheReportAndRoundTripsItThroughUserInfo() {
        let date = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let report = ToolboxNotificationReport(platform: "iOS", statusTitles: ["Available", "Available", "Permission Required", "Available", "Device Only"],
                                               availableTitle: "Available", measuredAt: date)
        #expect(report.available == 3)
        #expect(report.total == 5)
        #expect(report.buckets.first == .init(title: "Available", count: 3))
        #expect(report.buckets.map(\.title) == ["Available", "Device Only", "Permission Required"])

        let userInfo: [AnyHashable: Any] = report.userInfo
        #expect(ToolboxNotificationReport(userInfo: userInfo) == report)
        #expect(ToolboxNotificationReport(userInfo: [:]) == nil)
        #expect(ToolboxNotificationReport(userInfo: [ToolboxNotificationReport.userInfoKey: "not json"]) == nil)
    }

    @Test func formatsDeviceTokensAsProviderHex() {
        #expect(NotificationFormatting.hex(Data([0x00, 0x0f, 0xa0, 0xff])) == "000fa0ff")
        #expect(NotificationFormatting.hex(Data()) == "")
    }

    @Test func namesActionIdentifiers() {
        let name = { ToolboxNotificationAction.title(for: $0, defaultIdentifier: UNNotificationDefaultActionIdentifier, dismissIdentifier: UNNotificationDismissActionIdentifier) }
        #expect(name(UNNotificationDefaultActionIdentifier).hasPrefix("Opened"))
        #expect(name(UNNotificationDismissActionIdentifier).hasPrefix("Dismissed"))
        #expect(name(ToolboxNotificationAction.reply) == "Reply (text input)")
        #expect(name(ToolboxNotificationAction.verify).contains("authentication"))
        #expect(name("custom") == "Action custom")
    }

    @Test func mapsInterruptionLevelsToTheirCapabilities() {
        #expect(NotificationInterruptionChoice.passive.capabilityID == nil)
        #expect(NotificationInterruptionChoice.active.entitlementKey == nil)
        for choice in [NotificationInterruptionChoice.timeSensitive, .critical] {
            let capability = choice.capabilityID.flatMap(CapabilityRegistry.descriptor(for:))
            #expect(capability != nil)
            #expect(capability?.keys.contains(choice.entitlementKey ?? "") == true)
        }
        #expect(NotificationInterruptionChoice.timeSensitive.level == .timeSensitive)
        #expect(NotificationInterruptionChoice.critical.level == .critical)
    }

    @Test func registersCategoriesWithEveryActionKind() throws {
        let actions = ToolboxNotificationCategories.actions
        #expect(actions.identifier == ToolboxNotificationCategory.actions.rawValue)
        #expect(actions.options.contains(.customDismissAction))
        #expect(actions.actions.contains { $0 is UNTextInputNotificationAction })
        #expect(actions.actions.contains { $0.options.contains(.authenticationRequired) })
        #expect(actions.actions.contains { $0.options.contains(.destructive) })
        #expect(actions.actions.contains { $0.options.contains(.foreground) })
        #expect(ToolboxNotificationCategories.report.identifier == "toolbox.report")
        #expect(Set(ToolboxNotificationCategories.all.map(\.identifier)) == ["toolbox.actions", "toolbox.report"])
    }
}
