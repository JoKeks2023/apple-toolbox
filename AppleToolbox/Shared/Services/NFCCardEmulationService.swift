import Foundation
import Combine

#if canImport(CoreNFC) && os(iOS)
import CoreNFC
#endif

extension ExperimentAvailability {
    /// Host card emulation needs an NFC iPhone, a device model that supports CardSession and Apple's HCE entitlement.
    /// The device region outside the EEA reports Region Restricted; the authoritative regional eligibility
    /// (`CardSession.isEligible`, by Apple Account region) is asynchronous and shown by the run view.
    static func nfcCardEmulation() -> ExperimentStatus {
        #if canImport(CoreNFC) && os(iOS)
        guard NFCReaderSession.readingAvailable else { return .hardwareUnsupported }
        guard RegionRestrictedFeature.hostCardEmulation.isSupported(inRegion: RegionRestrictedFeature.currentRegion) else { return .regionRestricted }
        guard NFCCardEmulationService.hceEntitlement.isPresent else { return .approvalRequired }
        return CardSession.isSupported ? .available : .hardwareUnsupported
        #else
        return .platformUnsupported
        #endif
    }
}

/// What the card session reports back to the main actor.
nonisolated enum CardEmulationEvent: Sendable {
    case log(String)
    case exchange(command: String, response: String, note: String)
    case ended(String?)
}

/// ISO 7816 card emulation with CoreNFC's CardSession (spec §9): eligibility checks, presentment intent, the session
/// lifecycle and a demo APDU responder. CardSession() terminates apps without the HCE entitlement, so a session is only
/// created when the embedded profile grants it and the device reports support and eligibility.
@MainActor
final class NFCCardEmulationService: ObservableObject {
    enum StartMode: String, CaseIterable, Identifiable {
        case onReaderDetected = "When a reader is detected"
        case immediately = "Right after the session starts"
        var id: String { rawValue }
    }

    struct Check: Identifiable {
        let id: String
        let title: String
        let value: String
        let passed: Bool?
    }

    static let entitlementKey = "com.apple.developer.nfc.hce"
    static let prefixesKey = "com.apple.developer.nfc.hce.iso7816.select-identifier-prefixes"
    static var hceEntitlement: ProvisioningState { IdentityEntitlements.state(ofCapability: "nfc-hce") }

    @Published var startMode: StartMode = .onReaderDetected
    @Published private(set) var checks: [Check] = []
    @Published private(set) var canStart = false
    @Published private(set) var isRunning = false
    @Published private(set) var events: [String] = []
    @Published private(set) var presentment: String = "Not acquired"
    @Published private(set) var output = "Checking card emulation eligibility…"
    @Published private(set) var isError = false

    private var sessionTask: Task<Void, Never>?
    #if canImport(CoreNFC) && os(iOS)
    private var assertion: NFCPresentmentIntentAssertion?
    #endif

    var isActive: Bool { isRunning }

    func refreshChecks() async {
        #if canImport(CoreNFC) && os(iOS)
        let reading = NFCReaderSession.readingAvailable
        let supported = CardSession.isSupported
        let entitlement = Self.hceEntitlement
        // isEligible is only meaningful (and documented as safe) once the device reports support.
        let eligible: Bool? = supported ? await CardSession.isEligible : nil
        let prefixes = ProvisioningInspector.load().profile?.entitlements[Self.prefixesKey]
        checks = [
            Check(id: "reader", title: "NFC hardware", value: reading ? "NFCReaderSession.readingAvailable = true" : "No NFC reader available to apps", passed: reading),
            Check(id: "supported", title: "CardSession.isSupported", value: supported ? "true" : "false", passed: supported),
            Check(id: "eligible", title: "CardSession.isEligible", value: eligible.map { $0 ? "true" : "false (region, Apple Account or settings)" } ?? "Not queried: device not supported", passed: eligible),
            Check(id: "region", title: "Device region", value: RegionRestrictedFeature.regionDescription(RegionRestrictedFeature.currentRegion) + (RegionRestrictedFeature.hostCardEmulation.isSupported(inRegion: RegionRestrictedFeature.currentRegion) ? " · in the EEA" : " · outside the EEA, where Apple offers HCE"), passed: RegionRestrictedFeature.hostCardEmulation.isSupported(inRegion: RegionRestrictedFeature.currentRegion)),
            Check(id: "entitlement", title: Self.entitlementKey, value: IdentityEntitlements.summary(of: entitlement, key: "HCE entitlement"), passed: entitlement.isPresent),
            Check(id: "prefixes", title: "Select identifier prefixes", value: prefixes ?? "Not provisioned; the system only forwards SELECTs for listed AIDs", passed: prefixes != nil),
        ]
        canStart = reading && supported && eligible == true && entitlement.isPresent
        if !isRunning {
            report(canStart
                ? "Eligible. Start a card session, then hold the iPhone to an ISO 7816 reader that selects \(CardEmulationDemo.aidHex)."
                : "Card emulation cannot start here: " + blocker(reading: reading, supported: supported, eligible: eligible, entitlement: entitlement.isPresent),
                isError: !canStart)
        }
        #else
        checks = [Check(id: "platform", title: "CardSession", value: "Only available on iPhone (iOS 17.4+)", passed: false)]
        report("CoreNFC card emulation is only available on iPhone.", isError: true)
        #endif
    }

    func start() {
        #if canImport(CoreNFC) && os(iOS)
        guard canStart, sessionTask == nil else { return }
        isRunning = true
        events = []
        let immediately = startMode == .immediately
        let report: @Sendable (CardEmulationEvent) -> Void = { @Sendable [weak self] event in
            Task { @MainActor in self?.handle(event) }
        }
        log("Creating CardSession…")
        sessionTask = Task { await CardEmulationRunner.run(startImmediately: immediately, report: report) }
        #endif
    }

    func stop() {
        sessionTask?.cancel()
    }

    func acquirePresentmentIntent() {
        #if canImport(CoreNFC) && os(iOS)
        guard canStart else { return }
        Task {
            do {
                let assertion = try await NFCPresentmentIntentAssertion.acquire()
                self.assertion = assertion
                presentment = "Held · valid: \(assertion.isValid)"
                log("Presentment intent acquired: the default contactless app will not launch while it is held (max. 15 s, foreground only).")
                try? await Task.sleep(for: .seconds(15.5))
                if self.assertion === assertion { presentment = "Held · valid: \(assertion.isValid) (15 s limit reached)" }
            } catch {
                presentment = "Not acquired"
                log("Presentment intent failed: \(CardEmulationRunner.describe(error))")
            }
        }
        #endif
    }

    func releasePresentmentIntent() {
        #if canImport(CoreNFC) && os(iOS)
        guard assertion != nil else { return }
        assertion = nil
        presentment = "Released"
        log("Presentment intent released; a new one can be acquired after a 15-second cool-down.")
        #endif
    }

    private func handle(_ event: CardEmulationEvent) {
        switch event {
        case .log(let message):
            log(message)
        case .exchange(let command, let response, let note):
            log("APDU ← \(command)\n     → \(response) · \(note)")
        case .ended(let failure):
            sessionTask = nil
            isRunning = false
            if let failure {
                log(failure)
                report(failure, isError: true)
            } else {
                log("Session ended.")
                report("Card session ended. \(events.count) lifecycle events recorded.")
            }
        }
    }

    private func log(_ message: String) {
        events.insert("\(Date().formatted(date: .omitted, time: .standard)) · \(message)", at: 0)
        if events.count > 60 { events.removeLast(events.count - 60) }
        if isRunning { report(message) }
    }

    private func report(_ message: String, isError: Bool = false) {
        output = message
        self.isError = isError
    }

    private func blocker(reading: Bool, supported: Bool, eligible: Bool?, entitlement: Bool) -> String {
        if !reading { return "this device has no NFC reader available to apps." }
        if !supported { return "CardSession.isSupported is false on this device." }
        if !entitlement { return "the HCE entitlement is not provisioned, and CardSession() would terminate the app without it." }
        if eligible != true { return "CardSession.isEligible is false (Apple Account region, device location or settings)." }
        return "unknown reason."
    }
}

#if canImport(CoreNFC) && os(iOS)
/// Runs one card session off the main actor. The session object stays inside this task; cancellation invalidates it.
nonisolated enum CardEmulationRunner {
    @concurrent static func run(startImmediately: Bool, report: @escaping @Sendable (CardEmulationEvent) -> Void) async {
        let session: CardSession
        do {
            session = try await CardSession()
        } catch {
            report(.ended("CardSession could not be created: \(describe(error))"))
            return
        }
        session.alertMessage = "Apple Toolbox demo card"
        let handle = NFCSessionObject(session)
        await withTaskCancellationHandler {
            do {
                for try await event in session.eventStream {
                    switch event {
                    case .sessionStarted:
                        report(.log("sessionStarted: the app holds the NFC card emulation resource."))
                        if startImmediately { try await startEmulation(session, report: report) }
                    case .readerDetected:
                        report(.log("readerDetected: an NFC reader's RF field is present."))
                        if await !session.isEmulationInProgress { try await startEmulation(session, report: report) }
                    case .received(let apdu):
                        let command = apdu.payload
                        let (response, note) = CardEmulationDemo.response(to: command)
                        do {
                            try await apdu.respond(response: response)
                            report(.exchange(command: NFCHex.string(command), response: NFCHex.string(response), note: note))
                        } catch {
                            report(.log("Responding to \(NFCHex.string(command)) failed: \(describe(error))"))
                        }
                    case .readerDeselected:
                        report(.log("readerDeselected: the reader moved away or ended the transaction."))
                        await session.stopEmulation(status: .success)
                        report(.log("Emulation stopped; the session waits for the next reader."))
                    case .sessionInvalidated(let reason):
                        report(.log("sessionInvalidated: \(describe(reason))"))
                    @unknown default:
                        report(.log("Unhandled card session event."))
                    }
                }
                report(.ended(nil))
            } catch {
                // Cancelling (Stop) invalidates the session, which may end the stream with an error; that is a normal end.
                report(.ended(Task.isCancelled ? nil : "The card session event stream failed: \(describe(error))"))
            }
        } onCancel: {
            handle.object.invalidate()
        }
    }

    @concurrent private static func startEmulation(_ session: CardSession, report: @Sendable (CardEmulationEvent) -> Void) async throws {
        try await session.startEmulation()
        report(.log("startEmulation(): the system card UI is shown and APDUs from the reader are forwarded (max. 60 s)."))
    }

    static func describe(_ error: any Error) -> String {
        if let error = error as? CardSession.Error {
            return switch error {
            case .accessNotAccepted: "The person has not accepted the app's card emulation request yet (accessNotAccepted)."
            case .systemEligibilityFailed: "The system or hardware configuration is not eligible (systemEligibilityFailed)."
            case .systemNotAvailable: "The card emulation service is temporarily unavailable (systemNotAvailable)."
            case .radioDisabled: "The NFC radio is disabled (radioDisabled)."
            case .maxSessionDurationReached: "Emulation reached the 60-second limit (maxSessionDurationReached)."
            case .userInvalidated: "The person ended the session (userInvalidated)."
            case .invalidated: "The session was invalidated (invalidated)."
            case .transmissionError: "Transmission with the reader failed (transmissionError)."
            case .emulationStopped: "Emulation was stopped (emulationStopped)."
            @unknown default: String(describing: error)
            }
        }
        if let error = error as? NFCPresentmentIntentAssertion.Error {
            return switch error {
            case .systemEligibilityFailed: "The system is not eligible for a presentment intent (systemEligibilityFailed)."
            case .systemNotAvailable: "The presentment service is unavailable, for example during the 15-second cool-down (systemNotAvailable)."
            @unknown default: String(describing: error)
            }
        }
        return error.localizedDescription
    }
}
#endif
