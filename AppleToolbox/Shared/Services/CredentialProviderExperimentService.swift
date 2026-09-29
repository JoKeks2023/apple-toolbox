import Foundation
import Combine
import Security
#if canImport(AuthenticationServices)
import AuthenticationServices
#endif

/// ASCredentialIdentityStore's state as plain values.
nonisolated struct CredentialStoreStateSnapshot: Equatable, Sendable {
    let isEnabled: Bool
    let supportsIncrementalUpdates: Bool
    let readAt: Date
}

/// The AutoFill credential provider (spec §8). The iOS app embeds the `AppleToolbox Credential Provider` extension; the
/// person turns it on in Settings. The app feeds the identity store with the demo credentials from the App Group vault
/// and shows the store's live state and what the extension did.
@MainActor
final class CredentialProviderExperimentService: ObservableObject {
    @Published private(set) var output: String
    @Published private(set) var isError = false
    @Published private(set) var isRunning = false
    @Published private(set) var storeState: CredentialStoreStateSnapshot?
    @Published private(set) var vault = CredentialVaultStore.load()
    /// What `credentialIdentities(forService:credentialIdentityTypes:)` returned, one line per identity.
    @Published private(set) var storedIdentities: [String]?

    init(initialOutput: String) {
        output = initialOutput
    }

    /// What this build contains: bundled provider extensions with their capabilities and entitlements.
    static var boundarySummary: String {
        let providers = CredentialProviderExtensionScan.bundled
        let key = CredentialProviderExtensionScan.entitlementKey
        let app = IdentityEntitlements.summary(of: IdentityEntitlements.state(ofCapability: "autofill-credential-provider"), key: key)
        let providerLines = providers.isEmpty
            ? ["Bundled provider extensions: none (no .appex with \(CredentialProviderExtensionScan.extensionPoint)). \(missingProviderReason)"]
            : providers.flatMap { provider in [
                "Bundled provider: \(provider.bundleIdentifier) · \(provider.capabilities.isEmpty ? "passwords" : provider.capabilities.joined(separator: ", "))",
                "Extension: \(IdentityEntitlements.summary(of: provider.entitlement, key: key))",
            ] }
        return (providerLines + ["App target: \(app)"]).joined(separator: "\n")
    }

    private static var missingProviderReason: String {
        #if os(iOS)
        "This build was made without the provider extension target."
        #else
        "The provider extension ships only in the iOS app."
        #endif
    }

    func reloadVault() {
        vault = CredentialVaultStore.load()
    }

    // MARK: Identity store

    func checkStoreState() {
        #if canImport(AuthenticationServices) && (os(iOS) || os(macOS))
        start("Asking ASCredentialIdentityStore for its state…")
        ASCredentialIdentityStore.shared.getState { @Sendable [weak self] state in
            // The state object is not Sendable; only its two flags cross to the main actor.
            let snapshot = CredentialStoreStateSnapshot(isEnabled: state.isEnabled, supportsIncrementalUpdates: state.supportsIncrementalUpdates, readAt: Date())
            Task { @MainActor in
                guard let self else { return }
                self.storeState = snapshot
                self.finish("""
                ASCredentialIdentityStore state
                isEnabled: \(snapshot.isEnabled)
                supportsIncrementalUpdates: \(snapshot.supportsIncrementalUpdates)
                \(snapshot.isEnabled ? "Apple Toolbox is turned on as an AutoFill provider, so the store accepts its identities." : "The store is disabled for this app: its provider is not turned on in \(Self.settingsPath), so identity writes are rejected with storeDisabled.")
                """, isError: false)
            }
        }
        #else
        finish(Self.unsupported, isError: true)
        #endif
    }

    /// Creates the demo passwords (fresh random values) in the App Group vault the extension reads.
    func createDemoPasswords() {
        var generator = SystemRandomNumberGenerator()
        let passwords = CredentialVault.demoPasswords(using: &generator)
        vault = CredentialVaultStore.update { vault in
            vault.passwords = passwords
            vault.log("The app created \(passwords.count) demo passwords.")
        }
        finish("Wrote \(passwords.count) demo passwords to the App Group vault: " + passwords.map { "\($0.user) @ \($0.domain)" }.joined(separator: ", ") + ". Save the identities next so the QuickType bar offers them.", isError: false)
    }

    /// Writes every vault credential (passwords and the passkeys the extension created) to the identity store.
    func saveDemoIdentities() {
        #if canImport(AuthenticationServices) && (os(iOS) || os(macOS))
        if vault.passwords.isEmpty { createDemoPasswords() }
        let identities: [any ASCredentialIdentity] = vault.passwords.map {
            ASPasswordCredentialIdentity(serviceIdentifier: ASCredentialServiceIdentifier(identifier: $0.domain, type: .domain), user: $0.user, recordIdentifier: $0.id)
        } + vault.passkeys.map {
            ASPasskeyCredentialIdentity(relyingPartyIdentifier: $0.relyingParty, userName: $0.userName, credentialID: $0.credentialID, userHandle: $0.userHandle, recordIdentifier: $0.id)
        }
        let summary = "\(vault.passwords.count) password and \(vault.passkeys.count) passkey identities"
        start("Saving \(summary)…")
        ASCredentialIdentityStore.shared.saveCredentialIdentities(identities) { @Sendable [weak self] success, error in
            let report = CredentialProviderReport.describe(error)
            Task { @MainActor in
                self?.finish(success
                    ? "Saved \(summary). Tap a password field on example.com: the QuickType bar offers them from Apple Toolbox."
                    : "Saving the identities failed: \(report)", isError: !success)
                self?.listStoredIdentities()
            }
        }
        #else
        finish(Self.unsupported, isError: true)
        #endif
    }

    func removeAllIdentities() {
        removeAllIdentities(note: "The vault itself is unchanged.")
    }

    private func removeAllIdentities(note: String) {
        #if canImport(AuthenticationServices) && (os(iOS) || os(macOS))
        start("Removing all identities this app saved…")
        ASCredentialIdentityStore.shared.removeAllCredentialIdentities { @Sendable [weak self] success, error in
            let report = CredentialProviderReport.describe(error)
            Task { @MainActor in
                self?.finish(success ? "Removed every identity this app had saved. \(note)" : "Removing identities failed: \(report)\n\(note)", isError: !success)
                self?.listStoredIdentities()
            }
        }
        #else
        finish(Self.unsupported, isError: true)
        #endif
    }

    /// Lists the identities the store holds for this app's provider.
    func listStoredIdentities() {
        #if canImport(AuthenticationServices) && (os(iOS) || os(macOS))
        Task {
            let lines = await Self.identityLines()
            storedIdentities = lines
        }
        #endif
    }

    #if canImport(AuthenticationServices) && (os(iOS) || os(macOS))
    /// Runs off the main actor so the non-Sendable identities never cross it; only the rendered lines do.
    @concurrent private nonisolated static func identityLines() async -> [String] {
        let identities = await ASCredentialIdentityStore.shared.credentialIdentities()
        return identities.map { identity in
            let kind = identity is ASPasskeyCredentialIdentity ? "passkey" : identity is ASPasswordCredentialIdentity ? "password" : "identity"
            return "\(kind) · \(identity.user) @ \(identity.serviceIdentifier.identifier)"
        }.sorted()
    }
    #endif

    /// Removes the identities, the vault and the passkey keys.
    func resetDemoData() {
        let status = PasskeyKeyStore.deleteAll()
        vault = CredentialVaultStore.update { $0 = CredentialVault() }
        let keys = status == errSecSuccess ? "deleted" : status == errSecItemNotFound ? "none stored" : "SecItemDelete returned \(status)"
        removeAllIdentities(note: "Cleared the App Group vault; demo passkey keys: \(keys).")
    }

    // MARK: Settings

    static var settingsPath: String {
        #if os(macOS)
        "System Settings › General › AutoFill & Passwords"
        #else
        "Settings › General › AutoFill & Passwords"
        #endif
    }

    /// Shows the system request to turn this app on for AutoFill; it only succeeds when a provider extension exists.
    func requestTurnOn() {
        #if canImport(AuthenticationServices) && (os(iOS) || os(macOS))
        start("Asking the system to turn on this app's credential provider…")
        ASSettingsHelper.requestToTurnOnCredentialProviderExtension { @Sendable [weak self] enabled in
            Task { @MainActor in
                self?.finish(enabled
                    ? "appWasEnabledForAutoFill: true. The provider is on; the store now accepts identities."
                    : "appWasEnabledForAutoFill: false. Either the person declined, or there is no provider extension the system could turn on.",
                    isError: !enabled)
                self?.checkStoreState()
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
            let report = error.map { CredentialProviderReport.describe($0) }
            Task { @MainActor in
                self?.finish(report.map { "Opening the settings failed: \($0)" } ?? "The system opened the AutoFill provider settings.", isError: report != nil)
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
        reloadVault()
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
