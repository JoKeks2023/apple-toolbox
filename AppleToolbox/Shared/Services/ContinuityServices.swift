import Foundation
import Combine

#if canImport(WatchConnectivity) && !os(tvOS)
import WatchConnectivity
#endif
#if canImport(UIKit)
import UIKit
#endif
#if os(watchOS)
import WatchKit
#endif

/// One transfer or received payload as plain values for the UI.
nonisolated struct WatchTransferRow: Identifiable, Equatable, Sendable {
    let id = UUID()
    let title: String
    let detail: String
}

/// A file the counterpart sent with `transferFile(_:metadata:)`, copied out of the WatchConnectivity inbox.
nonisolated struct WatchReceivedFile: Equatable, Sendable {
    let name: String
    let byteCount: Int
    let metadata: String
    let preview: String
    let receivedAt: Date
}

/// Pure formatting of WatchConnectivity payloads (property-list dictionaries and small files).
nonisolated enum WatchTransferFormat {
    /// `key=value` pairs sorted by key, so both ends and the tests show payloads the same way.
    static func summary(_ payload: [String: Any]?) -> String {
        guard let payload, !payload.isEmpty else { return "empty" }
        return payload.keys.sorted().map { "\($0)=\(value(payload[$0] as Any))" }.joined(separator: " · ")
    }

    static func value(_ value: Any) -> String {
        switch value {
        case let date as Date: date.formatted(.iso8601)
        case let data as Data: "\(data.count) bytes"
        case let text as String: text
        case let number as NSNumber: number.stringValue
        case let list as [Any]: "[\(list.count) items]"
        case let dictionary as [String: Any]: "{\(summary(dictionary))}"
        default: String(describing: value)
        }
    }

    /// A file name that says who created it and when, e.g. `toolbox-iPhone-20260929-101500.txt`.
    static func fileName(from device: String, date: Date) -> String {
        let slug = device.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? String($0) : "-" }.joined()
        let stamp = date.formatted(Date.VerbatimFormatStyle(format: "\(year: .defaultDigits)\(month: .twoDigits)\(day: .twoDigits)-\(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased))\(minute: .twoDigits)\(second: .twoDigits)",
                                                            timeZone: .gmt, calendar: Calendar(identifier: .gregorian)))
        return "toolbox-\(slug)-\(stamp).txt"
    }

    static func fileContents(from device: String, date: Date, counter: Int) -> String {
        """
        Apple Toolbox WatchConnectivity file #\(counter)
        From: \(device)
        Created: \(date.formatted(.iso8601))
        Sent with WCSession.transferFile(_:metadata:); the receiver copies it before the delegate call returns.
        """
    }

    /// UTF-8 text of a small file, or its size when it is not text.
    static func preview(_ data: Data, limit: Int = 200) -> String {
        guard let text = String(data: data, encoding: .utf8) else { return "\(data.count) bytes of binary data" }
        return text.count > limit ? String(text.prefix(limit)) + "…" : text
    }

    static func progress(_ fraction: Double) -> String {
        fraction.formatted(.percent.precision(.fractionLength(0)))
    }
}

/// Keys and kinds of the messages Apple Toolbox sends over WatchConnectivity.
nonisolated enum WatchLinkMessage {
    static let kindKey = "kind"
    static let fromKey = "from"
    static let tokenKey = "token"
    static let errorKey = "error"

    static let ping = "ping"
    static let pong = "pong"
    /// The watch sends its archived `NIDiscoveryToken`; the iPhone answers with its own under `tokenKey`.
    static let nearbyToken = "nearby-token"
    /// The watch ended its Nearby Interaction session, so the iPhone ends its side too.
    static let nearbyStop = "nearby-stop"
    static let context = "application-context"
    static let userInfo = "user-info"
    static let complication = "complication"
    static let file = "file"
}

/// iPhone ↔ Apple Watch link. The same service runs in the iOS app and in the watch app,
/// so each side can ping its counterpart and answer incoming pings.
@MainActor
final class ContinuityExperimentService: NSObject, ObservableObject {
    static let shared = ContinuityExperimentService()

    @Published private(set) var output = "WatchConnectivity is ready."
    @Published private(set) var activation = "Not activated"
    @Published private(set) var isPaired: Bool?
    @Published private(set) var isCounterpartInstalled: Bool?
    @Published private(set) var isReachable = false
    @Published private(set) var lastMessage: String?
    /// Round trip of the last answered ping, in milliseconds.
    @Published private(set) var lastRoundTripMilliseconds: Int?
    /// iPhone only: whether the watch face shows this app's complication, and the complication transfers left today.
    @Published private(set) var isComplicationEnabled: Bool?
    @Published private(set) var remainingComplicationTransfers: Int?
    /// Watch only: the iPhone must be unlocked once after a restart before the watch can reach it.
    @Published private(set) var iPhoneNeedsUnlock: Bool?
    @Published private(set) var sentContext = "Nothing sent yet"
    @Published private(set) var receivedContext = "Nothing received yet"
    @Published private(set) var outstandingUserInfo: [WatchTransferRow] = []
    @Published private(set) var outstandingFiles: [WatchTransferRow] = []
    @Published private(set) var receivedUserInfo: [WatchTransferRow] = []
    @Published private(set) var receivedFile: WatchReceivedFile?
    /// Delivery results and arrivals, newest first.
    @Published private(set) var transferLog: [WatchTransferRow] = []
    private var sendCounter = 0

    static var deviceName: String {
        #if os(watchOS)
        WKInterfaceDevice.current().name
        #elseif canImport(UIKit)
        UIDevice.current.name
        #else
        Host.current().localizedName ?? "Mac"
        #endif
    }

    func activate() {
        #if canImport(WatchConnectivity) && !os(tvOS)
        guard WCSession.isSupported() else {
            activation = "Unsupported"
            output = "WatchConnectivity is not supported on this device (for example on iPad)."
            return
        }
        let session = WCSession.default
        session.delegate = self
        if session.activationState == .activated {
            refresh(from: session)
            output = "Session already active."
        } else {
            session.activate()
            output = "Activation requested…"
        }
        #else
        output = "WatchConnectivity is not available on this platform."
        #endif
    }

    func ping() {
        #if canImport(WatchConnectivity) && !os(tvOS)
        guard WCSession.isSupported() else { output = "WatchConnectivity is not supported on this device."; return }
        let session = WCSession.default
        guard session.activationState == .activated else { activate(); output = "Activate the session first, then ping again."; return }
        guard session.isReachable else {
            output = "Counterpart is not reachable. Open Apple Toolbox on the \(counterpartName) and keep it in the foreground."
            return
        }
        let sent = Date()
        output = "Ping sent to the \(counterpartName)…"
        session.sendMessage([WatchLinkMessage.kindKey: WatchLinkMessage.ping, WatchLinkMessage.fromKey: Self.deviceName], replyHandler: { @Sendable [weak self] reply in
            let from = reply[WatchLinkMessage.fromKey] as? String ?? "counterpart"
            let milliseconds = Int(Date().timeIntervalSince(sent) * 1000)
            Task { @MainActor in
                self?.lastMessage = "Pong from \(from)"
                self?.lastRoundTripMilliseconds = milliseconds
                self?.output = "Round trip to \(from): \(milliseconds) ms"
            }
        }, errorHandler: { @Sendable [weak self] error in
            let message = error.localizedDescription
            Task { @MainActor in self?.output = "Ping error: \(message)" }
        })
        #else
        output = "WatchConnectivity is not available on this platform."
        #endif
    }

    private var counterpartName: String {
        #if os(watchOS)
        "iPhone"
        #else
        "Apple Watch"
        #endif
    }

    #if os(watchOS)
    // MARK: Nearby Interaction token exchange (watch side)

    /// Sends this watch's archived Nearby Interaction discovery token to the iPhone and returns the iPhone's token.
    /// watchOS has no MultipeerConnectivity, so WatchConnectivity carries the tokens, as in Apple's watchOS sample.
    func exchangeNearbyToken(_ token: Data) async throws -> Data {
        guard WCSession.isSupported() else { throw ExperimentServiceError.unavailable("WatchConnectivity is not supported on this device.") }
        let session = WCSession.default
        guard session.activationState == .activated else {
            activate()
            throw ExperimentServiceError.unavailable("The WatchConnectivity session is not active yet. Try again in a moment.")
        }
        guard session.isReachable else {
            throw ExperimentServiceError.unavailable("The iPhone is not reachable. Open Apple Toolbox on the paired iPhone, keep it in the foreground, then try again.")
        }
        let message: [String: Any] = [WatchLinkMessage.kindKey: WatchLinkMessage.nearbyToken, WatchLinkMessage.tokenKey: token,
                                      WatchLinkMessage.fromKey: Self.deviceName]
        return try await withCheckedThrowingContinuation { continuation in
            session.sendMessage(message, replyHandler: { @Sendable reply in
                if let token = reply[WatchLinkMessage.tokenKey] as? Data {
                    continuation.resume(returning: token)
                } else {
                    let reason = reply[WatchLinkMessage.errorKey] as? String ?? "The iPhone answered without a discovery token."
                    continuation.resume(throwing: ExperimentServiceError.unavailable(reason))
                }
            }, errorHandler: { @Sendable error in
                continuation.resume(throwing: error)
            })
        }
    }

    /// Tells the iPhone to end its side of the ranging session; best effort, only while it is reachable.
    func endNearbyRanging() {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated, WCSession.default.isReachable else { return }
        WCSession.default.sendMessage([WatchLinkMessage.kindKey: WatchLinkMessage.nearbyStop], replyHandler: nil, errorHandler: nil)
    }
    #endif

    #if canImport(WatchConnectivity) && !os(tvOS)
    private func refresh(from session: WCSession) {
        activation = session.activationState.title
        isReachable = session.isReachable
        #if os(iOS)
        isPaired = session.isPaired
        isCounterpartInstalled = session.isWatchAppInstalled
        isComplicationEnabled = session.isComplicationEnabled
        remainingComplicationTransfers = session.isPaired ? session.remainingComplicationUserInfoTransfers : nil
        #elseif os(watchOS)
        isPaired = true
        isCounterpartInstalled = session.isCompanionAppInstalled
        iPhoneNeedsUnlock = session.iOSDeviceNeedsUnlockAfterRebootForReachability
        #endif
        if session.activationState == .activated {
            receivedContext = WatchTransferFormat.summary(session.receivedApplicationContext)
            refreshTransfers()
        }
    }

    /// The session when it can transfer; otherwise reports why not.
    private func transferSession() -> WCSession? {
        guard WCSession.isSupported() else { output = "WatchConnectivity is not supported on this device."; return nil }
        let session = WCSession.default
        guard session.activationState == .activated else { activate(); output = "Activate the session first, then try again."; return nil }
        #if os(iOS)
        guard session.isPaired else { output = "No Apple Watch is paired with this iPhone (WCSession.isPaired is false)."; return nil }
        guard session.isWatchAppInstalled else { output = "Apple Toolbox is not installed on the paired Apple Watch (isWatchAppInstalled is false)."; return nil }
        #endif
        return session
    }

    private func basePayload(_ kind: String) -> [String: Any] {
        sendCounter += 1
        return [WatchLinkMessage.kindKey: kind, WatchLinkMessage.fromKey: Self.deviceName, "counter": sendCounter, "sentAt": Date()]
    }

    private func log(_ title: String, _ detail: String) {
        transferLog.insert(WatchTransferRow(title: title, detail: detail), at: 0)
        if transferLog.count > 20 { transferLog.removeLast(transferLog.count - 20) }
    }
    #endif

    /// Re-reads the outstanding user info and file transfers from the session.
    func refreshTransfers() {
        #if canImport(WatchConnectivity) && !os(tvOS)
        guard WCSession.isSupported(), WCSession.default.activationState == .activated else { return }
        let session = WCSession.default
        outstandingUserInfo = session.outstandingUserInfoTransfers.map { transfer in
            var title = transfer.isTransferring ? "Transferring" : "Queued"
            #if os(iOS)
            if transfer.isCurrentComplicationInfo { title += " · complication" }
            #endif
            return WatchTransferRow(title: title, detail: WatchTransferFormat.summary(transfer.userInfo))
        }
        outstandingFiles = session.outstandingFileTransfers.map { transfer in
            WatchTransferRow(title: "\(transfer.isTransferring ? "Transferring" : "Queued") · \(WatchTransferFormat.progress(transfer.progress.fractionCompleted))",
                             detail: transfer.file.fileURL.lastPathComponent)
        }
        #if os(iOS)
        if session.isPaired {
            isComplicationEnabled = session.isComplicationEnabled
            remainingComplicationTransfers = session.remainingComplicationUserInfoTransfers
        }
        #endif
        #endif
    }

    /// `updateApplicationContext(_:)`: only the latest context is kept and delivered, replacing any earlier one.
    func updateContext() {
        #if canImport(WatchConnectivity) && !os(tvOS)
        guard let session = transferSession() else { return }
        var context = basePayload(WatchLinkMessage.context)
        context["note"] = "Latest state; replaces the previous context"
        do {
            try session.updateApplicationContext(context)
            sentContext = WatchTransferFormat.summary(session.applicationContext)
            output = "updateApplicationContext succeeded. The \(counterpartName) receives it now or on its next launch; only the newest context is delivered."
        } catch {
            output = "updateApplicationContext failed: \(error.localizedDescription)"
        }
        #else
        output = "WatchConnectivity is not available on this platform."
        #endif
    }

    /// `transferUserInfo(_:)`: every dictionary is queued and delivered in order, even while the counterpart is not running.
    func sendUserInfo() {
        #if canImport(WatchConnectivity) && !os(tvOS)
        guard let session = transferSession() else { return }
        let transfer = session.transferUserInfo(basePayload(WatchLinkMessage.userInfo))
        output = "transferUserInfo queued (\(WatchTransferFormat.summary(transfer.userInfo))). It stays in the outstanding list until didFinish reports delivery."
        refreshTransfers()
        #else
        output = "WatchConnectivity is not available on this platform."
        #endif
    }

    /// `transferFile(_:metadata:)` with a small text file generated now.
    func sendFile() {
        #if canImport(WatchConnectivity) && !os(tvOS)
        guard let session = transferSession() else { return }
        sendCounter += 1
        let date = Date()
        let name = WatchTransferFormat.fileName(from: Self.deviceName, date: date)
        let data = Data(WatchTransferFormat.fileContents(from: Self.deviceName, date: date, counter: sendCounter).utf8)
        do {
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("WatchOutbox", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let url = folder.appendingPathComponent(name)
            try data.write(to: url, options: .atomic)
            let metadata: [String: Any] = [WatchLinkMessage.kindKey: WatchLinkMessage.file, WatchLinkMessage.fromKey: Self.deviceName,
                                           "counter": sendCounter, "createdAt": date, "bytes": data.count]
            let transfer = session.transferFile(url, metadata: metadata)
            output = "transferFile queued \(transfer.file.fileURL.lastPathComponent) (\(data.count) bytes) with metadata \(WatchTransferFormat.summary(transfer.file.metadata))."
        } catch {
            output = "Could not write the file to send: \(error.localizedDescription)"
        }
        refreshTransfers()
        #else
        output = "WatchConnectivity is not available on this platform."
        #endif
    }

    /// Cancels every outstanding user info and file transfer.
    func cancelOutstanding() {
        #if canImport(WatchConnectivity) && !os(tvOS)
        guard WCSession.isSupported(), WCSession.default.activationState == .activated else { return }
        let session = WCSession.default
        let count = session.outstandingUserInfoTransfers.count + session.outstandingFileTransfers.count
        session.outstandingUserInfoTransfers.forEach { $0.cancel() }
        session.outstandingFileTransfers.forEach { $0.cancel() }
        output = "Cancelled \(count) outstanding transfer(s)."
        refreshTransfers()
        #endif
    }

    #if os(iOS)
    /// `transferCurrentComplicationUserInfo(_:)`: jumps the queue and wakes the watch app, within a daily budget,
    /// but only while this app's complication is on the active watch face.
    func sendComplicationInfo() {
        guard let session = transferSession() else { return }
        guard session.isComplicationEnabled else {
            output = "The Apple Toolbox complication is not on the active watch face (isComplicationEnabled is false), so transferCurrentComplicationUserInfo is not available. Add the complication to a face and try again."
            return
        }
        var payload = basePayload(WatchLinkMessage.complication)
        payload["note"] = "Complication update from iPhone"
        let transfer = session.transferCurrentComplicationUserInfo(payload)
        output = "transferCurrentComplicationUserInfo queued (current complication info: \(transfer.isCurrentComplicationInfo ? "yes" : "no")). \(session.remainingComplicationUserInfoTransfers) high-priority transfer(s) left today; after that the transfer is sent like regular user info."
        refreshTransfers()
    }
    #endif
}

#if canImport(WatchConnectivity) && !os(tvOS)
extension ContinuityExperimentService: WCSessionDelegate {
    // WatchConnectivity calls the delegate on a background queue; UI state is updated on the main actor.
    nonisolated func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        let message = error.map { "Activation error: \($0.localizedDescription)" } ?? "Session activated."
        Task { @MainActor [weak self] in
            self?.refresh(from: WCSession.default)
            self?.output = message
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor [weak self] in self?.refresh(from: WCSession.default) }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        let from = message[WatchLinkMessage.fromKey] as? String ?? "counterpart"
        #if os(iOS) && canImport(NearbyInteraction)
        if message[WatchLinkMessage.kindKey] as? String == WatchLinkMessage.nearbyToken, let token = message[WatchLinkMessage.tokenKey] as? Data {
            // WatchConnectivity lets the reply come later; it is sent exactly once, after the main actor set up the session.
            nonisolated(unsafe) let replyHandler = replyHandler
            Task { @MainActor [weak self] in
                do {
                    let ownToken = try WatchNearbyResponder.shared.respond(toWatchToken: token, from: from)
                    replyHandler([WatchLinkMessage.tokenKey: ownToken])
                    self?.lastMessage = "Nearby token from \(from)"
                } catch {
                    replyHandler([WatchLinkMessage.errorKey: error.localizedDescription])
                    self?.lastMessage = "Nearby token from \(from) rejected"
                }
            }
            return
        }
        #endif
        replyHandler([WatchLinkMessage.kindKey: WatchLinkMessage.pong, WatchLinkMessage.fromKey: ContinuityExperimentService.replyName])
        Task { @MainActor [weak self] in
            self?.lastMessage = "Ping from \(from)"
            self?.output = "Answered a ping from \(from)."
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        let from = message[WatchLinkMessage.fromKey] as? String ?? "counterpart"
        let kind = message[WatchLinkMessage.kindKey] as? String
        Task { @MainActor [weak self] in
            #if os(iOS) && canImport(NearbyInteraction)
            if kind == WatchLinkMessage.nearbyStop {
                WatchNearbyResponder.shared.stop(reason: "The watch ended ranging.")
                self?.lastMessage = "Nearby ranging ended by the watch"
                return
            }
            #endif
            self?.lastMessage = kind.map { "Message “\($0)” from \(from)" } ?? "Message from \(from)"
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        let summary = WatchTransferFormat.summary(applicationContext)
        Task { @MainActor [weak self] in
            self?.receivedContext = summary
            self?.log("Application context received", summary)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        let summary = WatchTransferFormat.summary(userInfo)
        let isComplication = userInfo[WatchLinkMessage.kindKey] as? String == WatchLinkMessage.complication
        Task { @MainActor [weak self] in
            guard let self else { return }
            let title = isComplication ? "Complication user info" : "User info"
            receivedUserInfo.insert(WatchTransferRow(title: "\(title) · \(Date().formatted(date: .omitted, time: .standard))", detail: summary), at: 0)
            if receivedUserInfo.count > 10 { receivedUserInfo.removeLast(receivedUserInfo.count - 10) }
            log("\(title) received", summary)
            #if os(watchOS)
            // The complication shows the last thing the iPhone sent.
            if isComplication { WatchComplicationUpdater.recordPing("Complication info from iPhone") }
            #endif
        }
    }

    nonisolated func session(_ session: WCSession, didFinish userInfoTransfer: WCSessionUserInfoTransfer, error: Error?) {
        let summary = WatchTransferFormat.summary(userInfoTransfer.userInfo)
        let failure = error?.localizedDescription
        Task { @MainActor [weak self] in
            self?.log(failure == nil ? "User info delivered (didFinish)" : "User info failed", failure.map { "\($0) · \(summary)" } ?? summary)
            self?.refreshTransfers()
        }
    }

    nonisolated func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: Error?) {
        let name = fileTransfer.file.fileURL.lastPathComponent
        let failure = error?.localizedDescription
        Task { @MainActor [weak self] in
            self?.log(failure == nil ? "File delivered (didFinish)" : "File transfer failed", failure.map { "\($0) · \(name)" } ?? name)
            self?.refreshTransfers()
        }
    }

    /// The system deletes `file.fileURL` when this method returns, so the file is copied here, synchronously.
    nonisolated func session(_ session: WCSession, didReceive file: WCSessionFile) {
        let name = file.fileURL.lastPathComponent
        let metadata = WatchTransferFormat.summary(file.metadata)
        let received: WatchReceivedFile
        do {
            let folder = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                .appendingPathComponent("ReceivedWatchFiles", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let destination = folder.appendingPathComponent(name)
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.copyItem(at: file.fileURL, to: destination)
            let data = try Data(contentsOf: destination)
            received = WatchReceivedFile(name: name, byteCount: data.count, metadata: metadata, preview: WatchTransferFormat.preview(data), receivedAt: Date())
        } catch {
            received = WatchReceivedFile(name: name, byteCount: 0, metadata: metadata, preview: "Could not copy the file: \(error.localizedDescription)", receivedAt: Date())
        }
        Task { @MainActor [weak self] in
            self?.receivedFile = received
            self?.log("File received", "\(received.name) · \(received.byteCount) bytes")
        }
    }

    #if os(iOS)
    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor [weak self] in self?.refresh(from: WCSession.default) }
    }
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {
        Task { @MainActor [weak self] in self?.output = "Session became inactive." }
    }
    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        // Re-activate so a newly paired watch can connect.
        Task { @MainActor [weak self] in
            WCSession.default.activate()
            self?.output = "Session deactivated, re-activating for the current watch."
        }
    }
    #endif
}

extension ContinuityExperimentService {
    /// Read from the delegate queue when answering a ping, so it must not touch main-actor state.
    nonisolated static var replyName: String {
        #if os(watchOS)
        "Apple Watch"
        #else
        "iPhone"
        #endif
    }
}

private extension WCSessionActivationState {
    var title: String {
        switch self {
        case .activated: "Activated"
        case .inactive: "Inactive"
        case .notActivated: "Not activated"
        @unknown default: "Unknown"
        }
    }
}
#endif
