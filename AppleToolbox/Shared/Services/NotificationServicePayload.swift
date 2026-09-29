import Foundation

/// What the notification service extension reads from a remote notification and how it rewrites it. Shared by the
/// iOS app (sample payload, last run) and the `AppleToolbox Notification Service` extension.
nonisolated struct NotificationServicePayload: Equatable, Sendable {
    /// Custom top-level payload key with the image, audio or video the extension downloads as an attachment.
    static let attachmentKey = "attachment-url"
    /// Appended to the title so the change the extension made is visible on the banner.
    static let titleMarker = "✦ rewritten by the service extension"
    /// A small PNG on apple.com used in the sample payload.
    static let sampleAttachmentURL = URL(string: "https://www.apple.com/ac/structured-data/images/open_graph_logo.png")!

    /// The URL to download, when the payload carries a usable one.
    let attachmentURL: URL?
    /// Why a present `attachment-url` value is not used.
    let attachmentProblem: String?

    init(userInfo: [AnyHashable: Any]) {
        guard let raw = userInfo[Self.attachmentKey] else {
            attachmentURL = nil
            attachmentProblem = nil
            return
        }
        guard let string = raw as? String, let url = URL(string: string.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme?.lowercased(), url.host?.isEmpty == false else {
            attachmentURL = nil
            attachmentProblem = "\(Self.attachmentKey) is not an absolute URL."
            return
        }
        guard scheme == "https" else {
            attachmentURL = nil
            attachmentProblem = "\(Self.attachmentKey) uses \(scheme):; App Transport Security only allows https downloads."
            return
        }
        attachmentURL = url
        attachmentProblem = nil
    }

    /// The title the extension delivers. An empty title gets the marker alone; an already marked title stays as it is.
    static func mutatedTitle(_ title: String) -> String {
        if title.hasSuffix(titleMarker) { return title }
        return title.isEmpty ? titleMarker : "\(title) \(titleMarker)"
    }

    /// File extensions UserNotifications accepts for attachments, keyed by MIME type.
    static let supportedTypes: [String: String] = [
        "image/png": "png", "image/jpeg": "jpg", "image/jpg": "jpg", "image/gif": "gif", "image/heic": "heic",
        "audio/mpeg": "mp3", "audio/mp4": "m4a", "audio/x-m4a": "m4a", "audio/aiff": "aiff", "audio/x-aiff": "aiff",
        "audio/wav": "wav", "audio/x-wav": "wav", "video/mp4": "mp4", "video/mpeg": "mpg", "video/quicktime": "mov",
    ]

    /// The file extension the downloaded file needs so UserNotifications recognizes its type, or nil when neither the
    /// server's MIME type nor the URL names a supported one.
    static func attachmentFileExtension(mimeType: String?, url: URL) -> String? {
        // "image/png; charset=binary" → "image/png"
        let essence = mimeType?.split(separator: ";").first?.trimmingCharacters(in: .whitespaces).lowercased() ?? ""
        if let known = supportedTypes[essence] { return known }
        let pathExtension = url.pathExtension.lowercased()
        let normalized = pathExtension == "jpeg" ? "jpg" : pathExtension
        return Set(supportedTypes.values).contains(normalized) ? normalized : nil
    }

    /// A payload that reaches the extension: an alert plus `mutable-content: 1`. Pretty-printed with sorted keys.
    static func samplePayload(title: String = "Apple Toolbox", body: String = "Sent through APNs and rewritten on the device.",
                              attachmentURL: URL? = sampleAttachmentURL) -> String {
        var payload: [String: Any] = [
            "aps": [
                "alert": ["title": title, "body": body],
                "mutable-content": 1,
                "sound": "default",
            ] as [String: Any],
        ]
        if let attachmentURL { payload[attachmentKey] = attachmentURL.absoluteString }
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]),
              let json = String(data: data, encoding: .utf8) else { return "{}" }
        return json
    }

    /// Whether a push payload reaches a service extension: it needs `mutable-content: 1` and an alert to show.
    static func reachesServiceExtension(aps: [String: Any]) -> Bool {
        let mutable = (aps["mutable-content"] as? Int) == 1 || (aps["mutable-content"] as? Bool) == true
        return mutable && aps["alert"] != nil
    }
}

/// What the extension did with the last notification, written to the App Group so the app can show it.
nonisolated struct NotificationServiceRecord: Codable, Equatable, Sendable {
    enum Outcome: String, Codable, Sendable {
        /// Delivered with the rewritten title (and the attachment, if one was requested and downloaded).
        case rewritten
        /// serviceExtensionTimeWillExpire fired first; the best attempt so far was delivered.
        case timedOut
    }

    let date: Date
    let requestIdentifier: String
    let originalTitle: String
    let deliveredTitle: String
    let outcome: Outcome
    /// "none requested", "attached image.png (11 KB)" or the reason the attachment failed.
    let attachment: String

    var summary: String {
        let when = date.formatted(date: .abbreviated, time: .standard)
        let result = outcome == .timedOut ? "time limit reached, best attempt delivered" : "rewritten"
        return "\(when) · \(result)\nrequest \(requestIdentifier)\ntitle “\(originalTitle)” → “\(deliveredTitle)”\nattachment: \(attachment)"
    }
}

/// App Group storage for the extension's last run.
nonisolated enum NotificationServiceRecordStore {
    private static let key = "notificationService.lastRecord"

    private static var defaults: UserDefaults? { UserDefaults(suiteName: ToolboxIdentifiers.appGroup) }

    static func load() -> NotificationServiceRecord? {
        guard let data = defaults?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(NotificationServiceRecord.self, from: data)
    }

    static func save(_ record: NotificationServiceRecord) {
        guard let data = try? JSONEncoder().encode(record) else { return }
        defaults?.set(data, forKey: key)
    }

    static func clear() {
        defaults?.removeObject(forKey: key)
    }
}
