import Foundation
import Combine
#if canImport(LocalAuthentication) && (os(iOS) || os(macOS))
import LocalAuthentication
import Security
#endif

// MARK: Choices

/// The LAPolicy values iOS and macOS offer. Wrist detection is watchOS-only and the …WithWatch names are deprecated
/// macOS aliases of the companion policies, so neither gets its own entry.
nonisolated enum LocalAuthenticationPolicyOption: String, CaseIterable, Identifiable, Sendable {
    case deviceOwner, biometrics, companion, biometricsOrCompanion

    var id: String { rawValue }
    var title: String {
        switch self {
        case .deviceOwner: "Device owner (biometrics or passcode)"
        case .biometrics: "Biometrics only"
        case .companion: "Companion device"
        case .biometricsOrCompanion: "Biometrics or companion"
        }
    }
    var apiName: String {
        switch self {
        case .deviceOwner: "deviceOwnerAuthentication"
        case .biometrics: "deviceOwnerAuthenticationWithBiometrics"
        case .companion: "deviceOwnerAuthenticationWithCompanion"
        case .biometricsOrCompanion: "deviceOwnerAuthenticationWithBiometricsOrCompanion"
        }
    }

    #if canImport(LocalAuthentication) && (os(iOS) || os(macOS))
    var policy: LAPolicy {
        switch self {
        case .deviceOwner: .deviceOwnerAuthentication
        case .biometrics: .deviceOwnerAuthenticationWithBiometrics
        case .companion: .deviceOwnerAuthenticationWithCompanion
        case .biometricsOrCompanion: .deviceOwnerAuthenticationWithBiometricsOrCompanion
        }
    }
    #endif
}

/// Values for `touchIDAuthenticationAllowableReuseDuration`; 300 s is `LATouchIDAuthenticationMaximumAllowableReuseDuration`.
nonisolated enum LocalAuthenticationReuseDuration: Double, CaseIterable, Identifiable, Sendable {
    case off = 0, tenSeconds = 10, oneMinute = 60, maximum = 300

    var id: Double { rawValue }
    var title: String {
        switch self {
        case .off: "Off (always prompt)"
        case .tenSeconds: "10 seconds"
        case .oneMinute: "60 seconds"
        case .maximum: "5 minutes (maximum)"
        }
    }
}

nonisolated enum LocalAuthenticationRightRequirement: String, CaseIterable, Identifiable, Sendable {
    case standard, biometry, biometryCurrentSet, biometryWithPasscodeFallback

    var id: String { rawValue }
    var title: String {
        switch self {
        case .standard: "Default (biometrics or passcode)"
        case .biometry: "Biometrics"
        case .biometryCurrentSet: "Current biometric enrolment"
        case .biometryWithPasscodeFallback: "Biometrics, passcode fallback"
        }
    }

    #if canImport(LocalAuthentication) && (os(iOS) || os(macOS))
    var requirement: LAAuthenticationRequirement {
        switch self {
        case .standard: .default
        case .biometry: .biometry
        case .biometryCurrentSet: .biometryCurrentSet
        case .biometryWithPasscodeFallback: .biometry(fallback: .devicePasscode)
        }
    }
    #endif
}

// MARK: Pure helpers

/// Names LocalAuthentication error codes (LAError.Code raw values from LAPublicDefines.h).
nonisolated enum LocalAuthenticationErrorName {
    static func name(for code: Int) -> String {
        switch code {
        case -1: "authenticationFailed"
        case -2: "userCancel"
        case -3: "userFallback"
        case -4: "systemCancel"
        case -5: "passcodeNotSet"
        case -6: "biometryNotAvailable"
        case -7: "biometryNotEnrolled"
        case -8: "biometryLockout"
        case -9: "appCancel"
        case -10: "invalidContext"
        case -11: "companionNotAvailable"
        case -12: "biometryNotPaired"
        case -13: "biometryDisconnected"
        case -14: "invalidDimensions"
        case -1004: "notInteractive"
        default: "unrecognized code"
        }
    }

    static func describe(_ error: Error) -> String {
        let error = error as NSError
        if error.domain == "com.apple.LocalAuthentication" {
            return "LAError \(error.code) (\(name(for: error.code))): \(error.localizedDescription)"
        }
        if error.domain == NSOSStatusErrorDomain { return KeychainStatus.describe(OSStatus(error.code)) }
        return "\(error.domain) \(error.code): \(error.localizedDescription)"
    }
}

/// A domain state hash the app saw earlier, with the time it was stored.
nonisolated struct StoredDomainState: Codable, Equatable, Sendable {
    let stateHash: Data
    let date: Date
}

/// What changed between the stored and the current domain state hash.
nonisolated enum DomainStateChange: Equatable, Sendable {
    /// The system reports no state (for example, nothing enrolled) and nothing was stored.
    case noState
    /// First check: nothing was stored before.
    case firstCheck
    case unchanged(since: Date)
    case changed(since: Date)
    /// A state was stored before, but the system reports none now (enrolment removed or biometrics disabled).
    case removed(since: Date)

    static func compare(stored: StoredDomainState?, current: Data?) -> DomainStateChange {
        switch (stored, current) {
        case (nil, nil): .noState
        case (nil, .some): .firstCheck
        case (.some(let stored), nil): .removed(since: stored.date)
        case (.some(let stored), .some(let current)): stored.stateHash == current ? .unchanged(since: stored.date) : .changed(since: stored.date)
        }
    }

    var isChange: Bool {
        switch self {
        case .changed, .removed: true
        default: false
        }
    }

    var summary: String {
        switch self {
        case .noState: "no state reported"
        case .firstCheck: "first check, stored for next time"
        case .unchanged(let date): "unchanged since last check (\(Self.format(date)))"
        case .changed(let date): "CHANGED since last check (\(Self.format(date)))"
        case .removed(let date): "no longer reported; a state existed at the last check (\(Self.format(date)))"
        }
    }

    private static func format(_ date: Date) -> String { date.formatted(date: .abbreviated, time: .standard) }
}

/// Persists the last seen domain state hashes in the app's own defaults, one entry per domain.
nonisolated struct DomainStateStore: Sendable {
    let suiteName: String?
    let prefix: String

    init(suiteName: String? = nil, prefix: String = "localauthentication.domainState.") {
        self.suiteName = suiteName
        self.prefix = prefix
    }

    private var defaults: UserDefaults { suiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard }

    func load(_ domain: String) -> StoredDomainState? {
        defaults.data(forKey: prefix + domain).flatMap { try? PropertyListDecoder().decode(StoredDomainState.self, from: $0) }
    }

    func save(_ state: StoredDomainState?, for domain: String) {
        guard let state, let data = try? PropertyListEncoder().encode(state) else { return defaults.removeObject(forKey: prefix + domain) }
        defaults.set(data, forKey: prefix + domain)
    }

    /// Compares the current hash with the stored one and stores the current one for the next check.
    func check(_ domain: String, current: Data?, now: Date = Date()) -> DomainStateChange {
        let change = DomainStateChange.compare(stored: load(domain), current: current)
        if case .unchanged = change { return change }
        save(current.map { StoredDomainState(stateHash: $0, date: now) }, for: domain)
        return change
    }
}

// MARK: Service

/// LocalAuthentication details (spec §8): biometry type, every policy, domain state tracking, the reuse window and
/// LARight / LAPersistedRight. `canEvaluatePolicy` and the domain state never prompt; only the explicit buttons do.
@MainActor
final class LocalAuthenticationExperimentService: ObservableObject {
    @Published var policy = LocalAuthenticationPolicyOption.deviceOwner
    @Published var reuseDuration = LocalAuthenticationReuseDuration.off
    @Published var requirement = LocalAuthenticationRightRequirement.standard
    @Published var secret = "A secret released only after authentication"
    @Published private(set) var overview = "Not checked yet."
    @Published private(set) var output: String
    @Published private(set) var isError = false
    @Published private(set) var isRunning = false
    @Published private(set) var rightState = "No LARight created yet"

    static let persistedRightIdentifier = "com.jorisconrad.appletoolbox.la-right"
    private let domainStates = DomainStateStore()
    #if canImport(LocalAuthentication) && (os(iOS) || os(macOS))
    private var evaluationContext: LAContext?
    private var right: LARight?
    #endif

    init(initialOutput: String) {
        output = initialOutput
    }

    // MARK: Inspection (no prompt)

    /// Reads biometry type, every policy and the domain state; the domain state hashes are compared with the last check.
    func inspect() {
        #if canImport(LocalAuthentication) && (os(iOS) || os(macOS))
        let context = LAContext()
        let policyLines = LocalAuthenticationPolicyOption.allCases.map { option in
            var error: NSError?
            let result = context.canEvaluatePolicy(option.policy, error: &error)
            return "  \(option.apiName): " + (result ? "yes" : "no · \(error.map { LocalAuthenticationErrorName.describe($0) } ?? "no error reported")")
        }
        // The biometry type and the domain state are only populated after canEvaluatePolicy ran on this context.
        let domainState = context.domainState
        let biometryChange = domainStates.check("biometry", current: domainState.biometry.stateHash)
        let companionChange = domainStates.check("companion", current: domainState.companion.stateHash)
        let companions = domainState.companion.availableCompanionTypes.map { Self.name($0) }.sorted()
        var lines = ["Biometry type: \(Self.name(context.biometryType))", "Policies (canEvaluatePolicy, never prompts):"] + policyLines
        lines += [
            "  deviceOwnerAuthenticationWithWristDetection: watchOS only",
            "Domain state (LAContext.domainState):",
            "  Biometry hash: \(Self.hashSummary(domainState.biometry.stateHash)) · \(biometryChange.summary)",
            "  Companions available: \(companions.isEmpty ? "none" : companions.joined(separator: ", "))",
            "  Companion hash: \(Self.hashSummary(domainState.companion.stateHash)) · \(companionChange.summary)",
        ]
        if biometryChange.isChange {
            lines.append("The enrolled faces or fingerprints changed (added, removed or reset). Apps that bind secrets to the current enrolment must verify the person again.")
        }
        lines.append("Reuse window: touchIDAuthenticationAllowableReuseDuration up to \(Int(LATouchIDAuthenticationMaximumAllowableReuseDuration)) s")
        overview = lines.joined(separator: "\n")
        #else
        overview = "LocalAuthentication policies are not available on this platform."
        #endif
    }

    // MARK: Policy evaluation (prompts)

    func evaluate() {
        #if canImport(LocalAuthentication) && (os(iOS) || os(macOS))
        let option = policy
        let context = LAContext()
        context.touchIDAuthenticationAllowableReuseDuration = reuseDuration.rawValue
        context.localizedCancelTitle = "Cancel Test"
        var error: NSError?
        guard context.canEvaluatePolicy(option.policy, error: &error) else {
            return finish("\(option.apiName) cannot be evaluated here: \(error.map { LocalAuthenticationErrorName.describe($0) } ?? "no error reported")", isError: true)
        }
        evaluationContext = context
        isRunning = true
        let started = Date()
        finish("Waiting for \(option.title.lowercased())…\nReuse window: \(reuseDuration.title)")
        context.evaluatePolicy(option.policy, localizedReason: "Test \(option.title.lowercased()) in Apple Toolbox") { @Sendable [weak self] success, error in
            let elapsed = Date().timeIntervalSince(started)
            Task { @MainActor in self?.finishEvaluation(option, success: success, error: error, elapsed: elapsed) }
        }
        #else
        finish("LocalAuthentication policies are not available on this platform.", isError: true)
        #endif
    }

    #if canImport(LocalAuthentication) && (os(iOS) || os(macOS))
    private func finishEvaluation(_ option: LocalAuthenticationPolicyOption, success: Bool, error: Error?, elapsed: TimeInterval) {
        isRunning = false
        let biometryHash = evaluationContext?.domainState.biometry.stateHash
        evaluationContext = nil
        let elapsedText = elapsed.formatted(.number.precision(.fractionLength(2)))
        var lines = [success ? "\(option.apiName) succeeded after \(elapsedText) s." : "\(option.apiName) failed after \(elapsedText) s."]
        if let error { lines.append(LocalAuthenticationErrorName.describe(error)) }
        if success && reuseDuration != .off {
            lines.append("Reuse window \(reuseDuration.title): if the device was unlocked with biometrics within it, the system skips the prompt. It does not report whether that happened; a near-instant success is the only hint.")
        }
        lines.append("Biometry hash after evaluation: \(Self.hashSummary(biometryHash))")
        finish(lines.joined(separator: "\n"), isError: !success)
    }
    #endif

    // MARK: LARight

    /// Checks whether the requirement could be satisfied, without any prompt.
    func checkRight() {
        #if canImport(LocalAuthentication) && (os(iOS) || os(macOS))
        let right = LARight(requirement: requirement.requirement)
        let title = requirement.title
        runRight("Checking whether “\(title)” can be authorized…") { [weak self] in
            do {
                try await Self.call { right.checkCanAuthorize(completion: $0) }
                self?.rightState = "\(title) · \(Self.name(right.state))"
                return ("checkCanAuthorize: yes, “\(title)” can be authorized on this device.", false)
            } catch {
                return ("checkCanAuthorize: no · \(LocalAuthenticationErrorName.describe(error))", true)
            }
        }
        #else
        finish("LARight is not available on this platform.", isError: true)
        #endif
    }

    func authorizeRight() {
        #if canImport(LocalAuthentication) && (os(iOS) || os(macOS))
        let right = LARight(requirement: requirement.requirement)
        self.right = right
        let title = requirement.title
        runRight("Authorizing “\(title)”…") { [weak self] in
            do {
                try await Self.call { right.authorize(localizedReason: "Authorize an Apple Toolbox LARight", completion: $0) }
                self?.rightState = "\(title) · \(Self.name(right.state))"
                return ("LARight authorized (state: \(Self.name(right.state))). It stays authorized until it is deauthorized or released.", false)
            } catch {
                self?.rightState = "\(title) · \(Self.name(right.state))"
                return ("LARight authorization failed: \(LocalAuthenticationErrorName.describe(error))", true)
            }
        }
        #else
        finish("LARight is not available on this platform.", isError: true)
        #endif
    }

    func deauthorizeRight() {
        #if canImport(LocalAuthentication) && (os(iOS) || os(macOS))
        guard let right else { return finish("No LARight was authorized in this session.", isError: true) }
        runRight("Deauthorizing…") { [weak self] in
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                right.deauthorize { @Sendable in continuation.resume() }
            }
            self?.rightState = "\(self?.requirement.title ?? "LARight") · \(Self.name(right.state))"
            self?.right = nil
            return ("LARight deauthorized (state: \(Self.name(right.state))).", false)
        }
        #else
        finish("LARight is not available on this platform.", isError: true)
        #endif
    }

    // MARK: LAPersistedRight

    /// Stores a right with the entered secret in LARightStore; the system also creates a key pair bound to it.
    func savePersistedRight() {
        #if canImport(LocalAuthentication) && (os(iOS) || os(macOS))
        let right = LARight(requirement: requirement.requirement)
        let secret = Data(secret.utf8)
        let title = requirement.title
        runRight("Saving a persisted right…") {
            do {
                let persisted: LAPersistedRight = try await Self.call { LARightStore.shared.saveRight(right, identifier: Self.persistedRightIdentifier, secret: secret, completion: $0) }
                let publicKey = await Self.publicKeySummary(of: persisted)
                return ("""
                Saved LAPersistedRight “\(Self.persistedRightIdentifier)” (\(title))
                Secret stored: \(secret.count) bytes, readable only after authorization
                Bound key pair: \(publicKey)
                Saving again replaces the right and its key.
                """, false)
            } catch {
                return ("Saving the persisted right failed: \(LocalAuthenticationErrorName.describe(error))", true)
            }
        }
        #else
        finish("LAPersistedRight is not available on this platform.", isError: true)
        #endif
    }

    /// Loads the stored right, authorizes it (prompt), signs with its key, verifies, and reads the secret.
    func usePersistedRight(message: String) {
        #if canImport(LocalAuthentication) && (os(iOS) || os(macOS))
        let data = Data(message.utf8)
        runRight("Loading the persisted right…") {
            do {
                let persisted: LAPersistedRight = try await Self.call { LARightStore.shared.right(forIdentifier: Self.persistedRightIdentifier, completion: $0) }
                try await Self.call { persisted.authorize(localizedReason: "Use the Apple Toolbox persisted right", completion: $0) }
                var lines = ["Loaded and authorized “\(Self.persistedRightIdentifier)” (state: \(Self.name(persisted.state)))"]
                let algorithm = SecKeyAlgorithm.ecdsaSignatureMessageX962SHA256
                if persisted.key.canSign(using: algorithm) {
                    let signature: Data = try await Self.call { persisted.key.sign(data, algorithm: algorithm, completion: $0) }
                    lines.append("Signed \(data.count) bytes with the bound private key: \(signature.count)-byte ECDSA signature (X9.62, SHA-256)")
                    do {
                        try await Self.call { persisted.key.publicKey.verify(data, signature: signature, algorithm: algorithm, completion: $0) }
                        lines.append("Signature verified with the bound public key ✓")
                    } catch {
                        lines.append("Verification failed: \(LocalAuthenticationErrorName.describe(error))")
                    }
                } else {
                    lines.append("The bound key cannot sign with ecdsaSignatureMessageX962SHA256.")
                }
                let secret: Data = try await Self.call { persisted.secret.loadData(completion: $0) }
                lines.append("Secret released: “\(String(decoding: secret, as: UTF8.self))”")
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    persisted.deauthorize { @Sendable in continuation.resume() }
                }
                lines.append("Deauthorized again (state: \(Self.name(persisted.state))).")
                return (lines.joined(separator: "\n"), false)
            } catch {
                return ("Using the persisted right failed: \(LocalAuthenticationErrorName.describe(error))", true)
            }
        }
        #else
        finish("LAPersistedRight is not available on this platform.", isError: true)
        #endif
    }

    func removePersistedRight() {
        #if canImport(LocalAuthentication) && (os(iOS) || os(macOS))
        runRight("Removing the persisted right…") {
            do {
                try await Self.call { LARightStore.shared.removeRight(forIdentifier: Self.persistedRightIdentifier, completion: $0) }
                return ("Removed “\(Self.persistedRightIdentifier)”; its secret and key are gone.", false)
            } catch {
                return ("Removing the persisted right failed: \(LocalAuthenticationErrorName.describe(error))", true)
            }
        }
        #else
        finish("LAPersistedRight is not available on this platform.", isError: true)
        #endif
    }

    // MARK: Helpers

    private func finish(_ text: String, isError: Bool = false) {
        output = text
        self.isError = isError
    }

    private func runRight(_ waiting: String, _ operation: @escaping @MainActor () async -> (String, Bool)) {
        isRunning = true
        finish(waiting)
        Task {
            let (text, isError) = await operation()
            isRunning = false
            finish(text, isError: isError)
        }
    }

    #if canImport(LocalAuthentication) && (os(iOS) || os(macOS))
    /// Bridges a LocalAuthentication completion handler (declared Sendable in the SDK) to async/await.
    private static func call(_ start: (@escaping @Sendable (Error?) -> Void) -> Void) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            start { error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            }
        }
    }

    private static func call<Value>(_ start: (@escaping @Sendable (Value?, Error?) -> Void) -> Void) async throws -> Value {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<UncheckedResult<Value>, Error>) in
            start { value, error in
                if let value { continuation.resume(returning: UncheckedResult(value: value)) }
                else { continuation.resume(throwing: error ?? ExperimentServiceError.unavailable("The system returned neither a result nor an error.")) }
            }
        }.value
    }

    private static func publicKeySummary(of right: LAPersistedRight) async -> String {
        do {
            let bytes: Data = try await call { right.key.publicKey.exportBytes(completion: $0) }
            return "public key \(bytes.count) bytes · \(hashSummary(bytes))"
        } catch {
            return "public key export failed: \(LocalAuthenticationErrorName.describe(error))"
        }
    }

    static func name(_ type: LABiometryType) -> String {
        switch type {
        case .none: "none"
        case .touchID: "Touch ID"
        case .faceID: "Face ID"
        case .opticID: "Optic ID"
        @unknown default: "unknown (\(type.rawValue))"
        }
    }

    static func name(_ companion: LACompanionType) -> String {
        #if os(macOS)
        companion == .watch ? "Apple Watch" : "companion \(companion.rawValue)"
        #else
        switch companion {
        case .mac: "Mac"
        case .vision: "Apple Vision Pro"
        default: "companion \(companion.rawValue)"
        }
        #endif
    }

    static func name(_ state: LARight.State) -> String {
        switch state {
        case .unknown: "unknown"
        case .authorizing: "authorizing"
        case .authorized: "authorized"
        case .notAuthorized: "not authorized"
        @unknown default: "state \(state.rawValue)"
        }
    }
    #endif

    static func hashSummary(_ hash: Data?) -> String {
        guard let hash else { return "none" }
        return "\(hash.count) bytes · " + hash.prefix(6).map { String(format: "%02x", $0) }.joined() + "…"
    }
}

/// Carries a LocalAuthentication object out of its completion handler. LARight, LAPersistedRight and LAPublicKey are
/// immutable handles that the framework itself calls from arbitrary queues, so handing one to the main actor is safe.
nonisolated private struct UncheckedResult<Value>: @unchecked Sendable {
    let value: Value
}

extension LocalAuthenticationExperimentService: StoppableExperiment {
    var isActive: Bool { isRunning }

    /// Leaving the experiment cancels a pending policy prompt; LARight operations finish on their own.
    func stop() {
        #if canImport(LocalAuthentication) && (os(iOS) || os(macOS))
        evaluationContext?.invalidate()
        #endif
    }
}
