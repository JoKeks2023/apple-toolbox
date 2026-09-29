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

struct NotificationServicePayloadTests {

    @Test func readsAnHTTPSAttachmentURL() {
        let payload = NotificationServicePayload(userInfo: ["attachment-url": " https://example.com/a/b.png "])
        #expect(payload.attachmentURL == URL(string: "https://example.com/a/b.png"))
        #expect(payload.attachmentProblem == nil)
    }

    @Test func explainsUnusableAttachmentValues() {
        #expect(NotificationServicePayload(userInfo: [:]).attachmentURL == nil)
        #expect(NotificationServicePayload(userInfo: [:]).attachmentProblem == nil)
        let http = NotificationServicePayload(userInfo: ["attachment-url": "http://example.com/a.png"])
        #expect(http.attachmentURL == nil)
        #expect(http.attachmentProblem?.contains("https") == true)
        #expect(NotificationServicePayload(userInfo: ["attachment-url": "not a url"]).attachmentProblem != nil)
        #expect(NotificationServicePayload(userInfo: ["attachment-url": 42]).attachmentProblem != nil)
    }

    @Test func marksTheTitleOnce() {
        let marked = NotificationServicePayload.mutatedTitle("Apple Toolbox")
        #expect(marked == "Apple Toolbox \(NotificationServicePayload.titleMarker)")
        #expect(NotificationServicePayload.mutatedTitle(marked) == marked)
        #expect(NotificationServicePayload.mutatedTitle("") == NotificationServicePayload.titleMarker)
    }

    @Test func picksTheAttachmentFileExtension() {
        let url = URL(string: "https://example.com/download?id=1")!
        #expect(NotificationServicePayload.attachmentFileExtension(mimeType: "image/png", url: url) == "png")
        #expect(NotificationServicePayload.attachmentFileExtension(mimeType: "image/JPEG; charset=binary", url: url) == "jpg")
        #expect(NotificationServicePayload.attachmentFileExtension(mimeType: "application/octet-stream", url: URL(string: "https://example.com/clip.MP4")!) == "mp4")
        #expect(NotificationServicePayload.attachmentFileExtension(mimeType: nil, url: URL(string: "https://example.com/photo.jpeg")!) == "jpg")
        #expect(NotificationServicePayload.attachmentFileExtension(mimeType: "text/html", url: url) == nil)
    }

    @Test func samplePayloadReachesTheServiceExtension() throws {
        let json = NotificationServicePayload.samplePayload()
        let object = try #require(try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        let aps = try #require(object["aps"] as? [String: Any])
        #expect(NotificationServicePayload.reachesServiceExtension(aps: aps))
        #expect(object["attachment-url"] as? String == NotificationServicePayload.sampleAttachmentURL.absoluteString)
        #expect(!NotificationServicePayload.reachesServiceExtension(aps: ["alert": "Hi"]))
        #expect(!NotificationServicePayload.reachesServiceExtension(aps: ["mutable-content": 1, "content-available": 1]))
    }

    @Test func recordSummaryNamesTheOutcome() {
        let record = NotificationServiceRecord(date: Date(timeIntervalSinceReferenceDate: 0), requestIdentifier: "req", originalTitle: "A",
                                               deliveredTitle: "A ✦", outcome: .timedOut, attachment: "the download did not finish before the time limit")
        #expect(record.summary.contains("time limit reached"))
        #expect(record.summary.contains("“A” → “A ✦”"))
    }
}
