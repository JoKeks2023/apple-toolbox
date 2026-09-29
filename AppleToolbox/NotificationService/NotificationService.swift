import Foundation
import UserNotifications

/// Rewrites remote notifications that arrive with `mutable-content: 1` before iOS shows them: the title gets a marker,
/// and the media named by the payload's `attachment-url` is downloaded and attached. Local notifications that the app
/// schedules never pass through a service extension.
///
/// UserNotifications calls both overrides on the extension's own queue, and the download finishes on URLSession's
/// queue. The state they share is only touched under `lock`, which is why the class is `@unchecked Sendable`.
nonisolated final class NotificationService: UNNotificationServiceExtension, @unchecked Sendable {
    private let lock = NSLock()
    private var contentHandler: ((UNNotificationContent) -> Void)?
    private var bestAttempt: UNMutableNotificationContent?
    private var originalTitle = ""
    private var requestIdentifier = ""
    private var attachmentNote = "none requested"
    private var download: URLSessionDownloadTask?

    override func didReceive(_ request: UNNotificationRequest, withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        guard let content = request.content.mutableCopy() as? UNMutableNotificationContent else {
            contentHandler(request.content)
            return
        }
        let payload = NotificationServicePayload(userInfo: content.userInfo)
        content.title = NotificationServicePayload.mutatedTitle(content.title)
        lock.withLock {
            self.contentHandler = contentHandler
            bestAttempt = content
            originalTitle = request.content.title
            requestIdentifier = request.identifier
            attachmentNote = payload.attachmentProblem ?? (payload.attachmentURL == nil ? "none requested" : "download started")
        }
        guard let url = payload.attachmentURL else {
            finish(.rewritten)
            return
        }
        let task = URLSession.shared.downloadTask(with: url) { [weak self] location, response, error in
            // The downloaded file is deleted when this closure returns, so it is moved synchronously here.
            self?.attach(location: location, response: response, error: error, url: url)
        }
        lock.withLock { download = task }
        task.resume()
    }

    /// Called shortly before the system's time limit (about 30 seconds). Delivers the best attempt so far.
    override func serviceExtensionTimeWillExpire() {
        finish(.timedOut)
        lock.withLock { download }?.cancel()
    }

    private func attach(location: URL?, response: URLResponse?, error: (any Error)?, url: URL) {
        var attachment: UNNotificationAttachment?
        let note: String
        if let error {
            note = "download failed: \(error.localizedDescription)"
        } else if let status = (response as? HTTPURLResponse)?.statusCode, !(200..<300).contains(status) {
            note = "the server answered HTTP \(status)"
        } else if let location {
            if let fileExtension = NotificationServicePayload.attachmentFileExtension(mimeType: response?.mimeType, url: url) {
                do {
                    let file = FileManager.default.temporaryDirectory
                        .appendingPathComponent("toolbox-attachment-\(UUID().uuidString)").appendingPathExtension(fileExtension)
                    try FileManager.default.moveItem(at: location, to: file)
                    let bytes = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                    attachment = try UNNotificationAttachment(identifier: NotificationServicePayload.attachmentKey, url: file)
                    note = "attached \(url.lastPathComponent) (\(response?.mimeType ?? fileExtension), \(ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)))"
                } catch {
                    note = "UNNotificationAttachment rejected the file: \(error.localizedDescription)"
                }
            } else {
                note = "unsupported media type \(response?.mimeType ?? "unknown"); UserNotifications accepts images, audio and video"
            }
        } else {
            note = "the download returned no file"
        }
        lock.withLock {
            attachmentNote = note
            if let attachment { bestAttempt?.attachments = [attachment] }
        }
        finish(.rewritten)
    }

    /// Hands the content to the system exactly once and records what happened for the app.
    private func finish(_ outcome: NotificationServiceRecord.Outcome) {
        let delivery: (handler: (UNNotificationContent) -> Void, content: UNNotificationContent, record: NotificationServiceRecord)? = lock.withLock {
            guard let handler = contentHandler, let content = bestAttempt else { return nil }
            contentHandler = nil
            if outcome == .timedOut, attachmentNote == "download started" { attachmentNote = "the download did not finish before the time limit" }
            let attached = attachmentNote.hasPrefix("attached") || attachmentNote == "none requested"
            if !attached { content.body += "\n(Attachment: \(attachmentNote))" }
            let record = NotificationServiceRecord(date: Date(), requestIdentifier: requestIdentifier, originalTitle: originalTitle,
                                                   deliveredTitle: content.title, outcome: outcome, attachment: attachmentNote)
            return (handler, content, record)
        }
        guard let delivery else { return }
        NotificationServiceRecordStore.save(delivery.record)
        delivery.handler(delivery.content)
    }
}
