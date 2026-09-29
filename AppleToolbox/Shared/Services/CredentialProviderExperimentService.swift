import Foundation
import Combine
#if canImport(AuthenticationServices)
import AuthenticationServices
#endif

/// The AutoFill credential provider boundary (spec §8). A provider is an app extension the person enables in Settings;
/// the containing app can only query the identity store's state and feed it identities, which is exactly what runs here.
@MainActor
final class CredentialProviderExperimentService: ObservableObject {
    @Published private(set) var output: String
    @Published private(set) var isError = false
    @Published private(set) var isRunning = false

    static let demoService = "example.com"
    static let demoUser = "toolbox-user"

    init(initialOutput: String) {
        output = initialOutput
    }

    /// What this build contains: bundled provider extensions and the entitlement state.
    static var boundarySummary: String {
        let providers = CredentialProviderExtensionScan.bundled
        let entitlement = IdentityEntitlements.summary(of: IdentityEntitlements.state(ofCapability: "autofill-credential-provider"),
                                                       key: "com.apple.developer.authentication-services.autofill-credential-provider")
        let providerLines = providers.isEmpty
            ? ["Bundled provider extensions: none (no .appex with \(CredentialProviderExtensionScan.extensionPoint))"]
            : providers.map { "Bundled provider: \($0.bundleIdentifier) · \($0.capabilities.isEmpty ? "passwords" : $0.capabilities.joined(separator: ", "))" }
        return (providerLines + ["App target: \(entitlement)"]).joined(separator: "\n")
    }

    // MARK: Identity store

    func checkStoreState() {
        #if canImport(AuthenticationServices) && (os(iOS) || os(macOS))
        start("Asking ASCredentialIdentityStore for its state…")
        ASCredentialIdentityStore.shared.getState { @Sendable [weak self] state in
            // The state object is not Sendable; only its two flags cross to the main actor.
            let enabled = state.isEnabled, incremental = state.supportsIncrementalUpdates
            Task { @MainActor in
                self?.finish("""
                ASCredentialIdentityStore state
                isEnabled: \(enabled)
                supportsIncrementalUpdates: \(incremental)
                \(enabled ? "This app's provider extension is turned on for AutoFill, so the store accepts identities." : "The store is disabled for this app: no provider extension of this app is turned on in Settings, so identity writes are rejected.")
                """, isError: false)
            }
        }
        #else
        finish(Self.unsupported, isError: true)
        #endif
    }

    /// Writes one password identity; without an enabled provider the store answers with its real error.
    func saveDemoIdentity() {
        #if canImport(AuthenticationServices) && (os(iOS) || os(macOS))
        start("Saving a demo password identity…")
        let identity = ASPasswordCredentialIdentity(serviceIdentifier: ASCredentialServiceIdentifier(identifier: Self.demoService, type: .domain),
                                                    user: Self.demoUser, recordIdentifier: "apple-toolbox-demo")
        let identities: [any ASCredentialIdentity] = [identity]
        ASCredentialIdentityStore.shared.saveCredentialIdentities(identities) { @Sendable [weak self] success, error in
            Task { @MainActor in
                self?.finish(success
                    ? "Saved “\(Self.demoUser)” for \(Self.demoService). AutoFill now offers it from this app's provider; remove it again below."
                    : "Saving the identity failed: \(CredentialProviderReport.describe(error))", isError: !success)
            }
        }
        #else
        finish(Self.unsupported, isError: true)
        #endif
    }

    func removeAllIdentities() {
        #if canImport(AuthenticationServices) && (os(iOS) || os(macOS))
        start("Removing all identities this app saved…")
        ASCredentialIdentityStore.shared.removeAllCredentialIdentities { @Sendable [weak self] success, error in
            Task { @MainActor in
                self?.finish(success ? "Removed every identity this app had saved." : "Removing identities failed: \(CredentialProviderReport.describe(error))", isError: !success)
            }
        }
        #else
        finish(Self.unsupported, isError: true)
        #endif
    }

    // MARK: Settings

    /// Shows the system request to turn this app on for AutoFill; it only succeeds when a provider extension exists.
    func requestTurnOn() {
        #if canImport(AuthenticationServices) && (os(iOS) || os(macOS))
        start("Asking the system to turn on this app's credential provider…")
        ASSettingsHelper.requestToTurnOnCredentialProviderExtension { @Sendable [weak self] enabled in
            Task { @MainActor in
                self?.finish(enabled
                    ? "appWasEnabledForAutoFill: true. The person turned the provider on."
                    : "appWasEnabledForAutoFill: false. Either the person declined, or (as in this build) there is no provider extension the system could turn on.",
                    isError: !enabled)
            }
        }
        #else
        finish(Self.unsupported, isError: true)
        #endif
    }

    func openProviderSettings() {
        #if canImport(AuthenticationServices) && (os(iOS) || os(macOS))
        start("Opening the AutoFill provider settings…")
        ASSettingsHelper.openCredentialProviderAppSettings { @Sendable [weak self] error in
            Task { @MainActor in
                self?.finish(error.map { "Opening the settings failed: \(CredentialProviderReport.describe($0))" } ?? "The system opened the AutoFill provider settings.", isError: error != nil)
            }
        }
        #else
        finish(Self.unsupported, isError: true)
        #endif
    }

    private static let unsupported = "AutoFill credential providers exist only on iOS, iPadOS and macOS."

    private func start(_ text: String) {
        isRunning = true
        output = text
        isError = false
    }

    private func finish(_ text: String, isError: Bool) {
        isRunning = false
        output = text
        self.isError = isError
    }
}

/// Names ASCredentialIdentityStore errors (ASCredentialIdentityStoreErrorCode) and falls back to the NSError fields.
nonisolated enum CredentialProviderReport {
    static func name(forStoreErrorCode code: Int) -> String {
        switch code {
        case 0: "internalError"
        case 1: "storeDisabled"
        case 2: "storeBusy"
        default: "unrecognized code"
        }
    }

    static func describe(_ error: Error?) -> String {
        guard let error = error as NSError? else { return "no error was reported" }
        #if canImport(AuthenticationServices) && (os(iOS) || os(macOS))
        if error.domain == ASCredentialIdentityStoreErrorDomain {
            return "ASCredentialIdentityStoreError \(error.code) (\(name(forStoreErrorCode: error.code))): \(error.localizedDescription)"
        }
        #endif
        return "\(error.domain) \(error.code): \(error.localizedDescription)"
    }
}
