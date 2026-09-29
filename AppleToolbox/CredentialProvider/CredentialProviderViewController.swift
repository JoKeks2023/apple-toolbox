import UIKit
import SwiftUI
import Combine
import AuthenticationServices
import LocalAuthentication
import CryptoKit

/// The AutoFill credential provider: offers the demo passwords and passkeys from the App Group vault, creates demo
/// passkeys when a website registers one, and signs passkey assertions with keys kept in this device's keychain.
/// The system calls these methods on the main thread; it shows the view only for the `prepare…` calls.
final class CredentialProviderViewController: ASCredentialProviderViewController {
    private let model = CredentialPickerModel()

    override func viewDidLoad() {
        super.viewDidLoad()
        let actions = CredentialPickerActions(
            usePassword: { [weak self] in self?.complete(with: $0) },
            usePasskey: { [weak self] passkey, request in self?.assert(passkey, for: request) },
            register: { [weak self] in self?.register($0) },
            saveIdentities: { [weak self] in self?.saveIdentities() },
            finishConfiguration: { [weak self] in self?.extensionContext.completeExtensionConfigurationRequest() },
            cancel: { [weak self] in self?.cancel(.userCanceled) })
        let host = UIHostingController(rootView: CredentialPickerView(model: model, actions: actions))
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        host.didMove(toParent: self)
    }

    // MARK: Lists

    override func prepareCredentialList(for serviceIdentifiers: [ASCredentialServiceIdentifier]) {
        model.show(.list(services: serviceIdentifiers.map(\.identifier), passkeyRequest: nil))
    }

    override func prepareCredentialList(for serviceIdentifiers: [ASCredentialServiceIdentifier], requestParameters: ASPasskeyCredentialRequestParameters) {
        let request = PasskeyAssertionContext(relyingParty: requestParameters.relyingPartyIdentifier, clientDataHash: requestParameters.clientDataHash,
                                              userVerification: requestParameters.userVerificationPreference, allowedCredentials: requestParameters.allowedCredentials)
        model.show(.list(services: serviceIdentifiers.map(\.identifier), passkeyRequest: request))
    }

    // MARK: A credential picked in the QuickType bar

    /// Demo passwords are filled directly. Passkeys always need the person to confirm (and verify) in the extension's UI.
    override func provideCredentialWithoutUserInteraction(for credentialRequest: any ASCredentialRequest) {
        guard credentialRequest.type == .password else {
            cancel(.userInteractionRequired)
            return
        }
        guard let credential = password(for: credentialRequest) else {
            cancel(.credentialIdentityNotFound)
            return
        }
        complete(with: credential)
    }

    override func prepareInterfaceToProvideCredential(for credentialRequest: any ASCredentialRequest) {
        switch credentialRequest.type {
        case .password:
            let service = AutoFillObject.identity(of: credentialRequest)
                .flatMap { AutoFillObject.object("serviceIdentifier", of: $0) }
                .flatMap { AutoFillObject.string("identifier", of: $0) }
            model.show(.list(services: service.map { [$0] } ?? [], passkeyRequest: nil))
        case .passkeyAssertion:
            guard let request = credentialRequest as? ASPasskeyCredentialRequest,
                  let identity = AutoFillObject.identity(of: request),
                  let credentialID = AutoFillObject.data("credentialID", of: identity),
                  let relyingParty = AutoFillObject.string("relyingPartyIdentifier", of: identity),
                  let passkey = CredentialVaultStore.load().passkeys.first(where: { $0.credentialID == credentialID }) else {
                cancel(.credentialIdentityNotFound)
                return
            }
            let context = PasskeyAssertionContext(relyingParty: relyingParty, clientDataHash: request.clientDataHash,
                                                  userVerification: request.userVerificationPreference, allowedCredentials: [credentialID])
            model.show(.confirm(passkey, context))
        default:
            cancel(.failed)
        }
    }

    // MARK: Passkey registration

    override func prepareInterface(forPasskeyRegistration registrationRequest: any ASCredentialRequest) {
        guard let request = registrationRequest as? ASPasskeyCredentialRequest,
              let identity = AutoFillObject.identity(of: request),
              let relyingParty = AutoFillObject.string("relyingPartyIdentifier", of: identity),
              let userName = AutoFillObject.string("userName", of: identity),
              let userHandle = AutoFillObject.data("userHandle", of: identity) else {
            cancel(.failed)
            return
        }
        guard request.supportedAlgorithms.contains(.ES256) else {
            model.message = "The relying party does not accept ES256 (P-256), the only algorithm this demo provider supports."
            model.show(.unsupported)
            return
        }
        let excluded = AutoFillObject.excludedCredentialIDs(of: request)
        if CredentialVaultStore.load().passkeys.contains(where: { excluded.contains($0.credentialID) }) {
            cancel(.matchedExcludedCredential)
            return
        }
        model.show(.register(PasskeyRegistrationContext(relyingParty: relyingParty, userName: userName,
                                                        userHandle: userHandle, clientDataHash: request.clientDataHash,
                                                        userVerification: request.userVerificationPreference)))
    }

    /// Shown once after the person turns the provider on (ASCredentialProviderExtensionShowsConfigurationUI).
    override func prepareInterfaceForExtensionConfiguration() {
        model.show(.configuration)
    }

    // MARK: Completing requests

    private func password(for request: any ASCredentialRequest) -> DemoPasswordCredential? {
        guard let recordIdentifier = AutoFillObject.identity(of: request).flatMap({ AutoFillObject.string("recordIdentifier", of: $0) }) else { return nil }
        return CredentialVaultStore.load().passwords.first { $0.id == recordIdentifier }
    }

    private func complete(with credential: DemoPasswordCredential) {
        CredentialVaultStore.update { $0.log("Filled the demo password of \(credential.user) for \(credential.domain).") }
        extensionContext.completeRequest(withSelectedCredential: ASPasswordCredential(user: credential.user, password: credential.password), completionHandler: nil)
    }

    private func assert(_ passkey: DemoPasskeyCredential, for request: PasskeyAssertionContext) {
        Task {
            model.isWorking = true
            defer { model.isWorking = false }
            var flags: SoftwarePasskeyAuthenticator.Flags = [.userPresent]
            if request.userVerification != .discouraged {
                if let failure = await verifyUser(reason: "Sign in to \(request.relyingParty) with a demo passkey") {
                    model.message = "User verification failed: \(failure)"
                    return
                }
                flags.insert(.userVerified)
            }
            do {
                let key = try PasskeyKeyStore.load(credentialID: passkey.credentialID)
                let signCount = passkey.signCount + 1
                let authenticatorData = SoftwarePasskeyAuthenticator.authenticatorData(relyingParty: passkey.relyingParty, flags: flags, signCount: signCount)
                let signature = try SoftwarePasskeyAuthenticator.signature(privateKey: key, authenticatorData: authenticatorData, clientDataHash: request.clientDataHash)
                CredentialVaultStore.update { vault in
                    if let index = vault.passkeys.firstIndex(where: { $0.credentialID == passkey.credentialID }) { vault.passkeys[index].signCount = signCount }
                    vault.log("Signed in \(passkey.userName) at \(passkey.relyingParty) with a demo passkey (sign count \(signCount), user verified: \(flags.contains(.userVerified))).")
                }
                let credential = ASPasskeyAssertionCredential(userHandle: passkey.userHandle, relyingParty: passkey.relyingParty, signature: signature,
                                                              clientDataHash: request.clientDataHash, authenticatorData: authenticatorData,
                                                              credentialID: passkey.credentialID)
                extensionContext.completeAssertionRequest(using: credential, completionHandler: nil)
            } catch {
                model.message = "Signing failed: \(error.localizedDescription)"
            }
        }
    }

    private func register(_ request: PasskeyRegistrationContext) {
        Task {
            model.isWorking = true
            defer { model.isWorking = false }
            var flags: SoftwarePasskeyAuthenticator.Flags = [.userPresent]
            if request.userVerification != .discouraged {
                if let failure = await verifyUser(reason: "Create a demo passkey for \(request.relyingParty)") {
                    model.message = "User verification failed: \(failure)"
                    return
                }
                flags.insert(.userVerified)
            }
            do {
                let key = P256.Signing.PrivateKey()
                let credentialID = SoftwarePasskeyAuthenticator.randomCredentialID()
                try PasskeyKeyStore.save(key, credentialID: credentialID)
                let attested = SoftwarePasskeyAuthenticator.attestedCredentialData(credentialID: credentialID, publicKey: key.publicKey)
                let authenticatorData = SoftwarePasskeyAuthenticator.authenticatorData(relyingParty: request.relyingParty, flags: flags, signCount: 0, attestedCredential: attested)
                let passkey = DemoPasskeyCredential(relyingParty: request.relyingParty, userName: request.userName, userHandle: request.userHandle,
                                                    credentialID: credentialID, signCount: 0, createdAt: Date())
                CredentialVaultStore.update { vault in
                    vault.passkeys.append(passkey)
                    vault.log("Created a demo passkey for \(request.userName) at \(request.relyingParty) (attestation none, user verified: \(flags.contains(.userVerified))).")
                }
                // Offer the new passkey in the QuickType bar too; the store only accepts it while the provider is turned on.
                let identity = ASPasskeyCredentialIdentity(relyingPartyIdentifier: passkey.relyingParty, userName: passkey.userName,
                                                           credentialID: passkey.credentialID, userHandle: passkey.userHandle, recordIdentifier: passkey.id)
                ASCredentialIdentityStore.shared.saveCredentialIdentities([identity]) { @Sendable _, error in
                    if let error { CredentialVaultStore.update { $0.log("Saving the passkey identity failed: \(error.localizedDescription)") } }
                }
                let credential = ASPasskeyRegistrationCredential(relyingParty: request.relyingParty, clientDataHash: request.clientDataHash, credentialID: credentialID,
                                                                 attestationObject: SoftwarePasskeyAuthenticator.attestationObject(authenticatorData: authenticatorData))
                extensionContext.completeRegistrationRequest(using: credential, completionHandler: nil)
            } catch {
                model.message = "Creating the passkey failed: \(error.localizedDescription)"
            }
        }
    }

    /// Writes every vault credential to the identity store so the QuickType bar can offer them.
    private func saveIdentities() {
        let vault = CredentialVaultStore.load()
        let identities: [any ASCredentialIdentity] = vault.passwords.map {
            ASPasswordCredentialIdentity(serviceIdentifier: ASCredentialServiceIdentifier(identifier: $0.domain, type: .domain), user: $0.user, recordIdentifier: $0.id)
        } + vault.passkeys.map {
            ASPasskeyCredentialIdentity(relyingPartyIdentifier: $0.relyingParty, userName: $0.userName, credentialID: $0.credentialID, userHandle: $0.userHandle, recordIdentifier: $0.id)
        }
        let count = identities.count
        ASCredentialIdentityStore.shared.saveCredentialIdentities(identities) { @Sendable [weak self] success, error in
            let text = success ? "Saved \(count) identities to the AutoFill identity store." : "Saving identities failed: \(error?.localizedDescription ?? "unknown error")"
            CredentialVaultStore.update { $0.log(text) }
            Task { @MainActor in self?.model.message = text }
        }
    }

    /// Runs device owner authentication (Face ID, Touch ID or passcode); returns nil on success or the failure text.
    private func verifyUser(reason: String) async -> String? {
        await withCheckedContinuation { continuation in
            let context = LAContext()
            var error: NSError?
            guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
                continuation.resume(returning: error?.localizedDescription ?? "no device passcode is set")
                return
            }
            context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { @Sendable success, error in
                continuation.resume(returning: success ? nil : (error?.localizedDescription ?? "not verified"))
            }
        }
    }

    private func cancel(_ code: ASExtensionError.Code) {
        extensionContext.cancelRequest(withError: NSError(domain: ASExtensionErrorDomain, code: code.rawValue))
    }
}

// MARK: - Model

struct PasskeyAssertionContext {
    let relyingParty: String
    let clientDataHash: Data
    let userVerification: ASAuthorizationPublicKeyCredentialUserVerificationPreference
    let allowedCredentials: [Data]
}

struct PasskeyRegistrationContext {
    let relyingParty: String
    let userName: String
    let userHandle: Data
    let clientDataHash: Data
    let userVerification: ASAuthorizationPublicKeyCredentialUserVerificationPreference
}

final class CredentialPickerModel: ObservableObject {
    enum Screen {
        case loading
        case list(services: [String], passkeyRequest: PasskeyAssertionContext?)
        case confirm(DemoPasskeyCredential, PasskeyAssertionContext)
        case register(PasskeyRegistrationContext)
        case configuration
        case unsupported
    }

    @Published var screen = Screen.loading
    @Published var vault = CredentialVault()
    @Published var message: String?
    @Published var isWorking = false

    func show(_ screen: Screen) {
        vault = CredentialVaultStore.load()
        self.screen = screen
    }
}

struct CredentialPickerActions {
    let usePassword: (DemoPasswordCredential) -> Void
    let usePasskey: (DemoPasskeyCredential, PasskeyAssertionContext) -> Void
    let register: (PasskeyRegistrationContext) -> Void
    let saveIdentities: () -> Void
    let finishConfiguration: () -> Void
    let cancel: () -> Void
}

// MARK: - Views

private struct CredentialPickerView: View {
    @ObservedObject var model: CredentialPickerModel
    let actions: CredentialPickerActions

    var body: some View {
        NavigationStack {
            List {
                content
                if let message = model.message {
                    Section { Text(message).font(.callout).foregroundStyle(.red) }
                }
                Section {
                    Text("Apple Toolbox demo provider: the credentials are generated demo data kept in the app's App Group, and passkey keys stay in this device's keychain.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .disabled(model.isWorking)
            .navigationTitle("Apple Toolbox")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: actions.cancel) }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.screen {
        case .loading:
            ProgressView()
        case .list(let services, let passkeyRequest):
            if let passkeyRequest {
                let passkeys = model.vault.passkeys(forRelyingParty: passkeyRequest.relyingParty, allowedCredentialIDs: passkeyRequest.allowedCredentials)
                Section("Passkeys for \(passkeyRequest.relyingParty)") {
                    if passkeys.isEmpty { Text("No demo passkey for this relying party. Create one by choosing Apple Toolbox when the site offers to save a passkey.").font(.callout) }
                    ForEach(passkeys) { passkey in
                        Button { actions.usePasskey(passkey, passkeyRequest) } label: { PasskeyRow(passkey: passkey) }
                    }
                }
            }
            let matching = model.vault.passwords(matching: services)
            Section(services.isEmpty ? "Demo passwords" : "Passwords for \(services.joined(separator: ", "))") {
                if matching.isEmpty {
                    Text(model.vault.passwords.isEmpty
                         ? "The vault is empty. Open Apple Toolbox › AutoFill Credential Provider and create the demo passwords."
                         : "No demo password for this site; the demo accounts are for example.com.")
                        .font(.callout)
                }
                ForEach(matching) { credential in
                    Button { actions.usePassword(credential) } label: { PasswordRow(credential: credential) }
                }
            }
            let others = model.vault.passwords.filter { !matching.contains($0) }
            if !others.isEmpty {
                Section("Other demo passwords") {
                    ForEach(others) { credential in
                        Button { actions.usePassword(credential) } label: { PasswordRow(credential: credential) }
                    }
                }
            }
        case .confirm(let passkey, let request):
            Section("Sign in with a demo passkey") {
                PasskeyRow(passkey: passkey)
                LabeledContent("User verification", value: request.userVerification.rawValue)
                Button("Sign In") { actions.usePasskey(passkey, request) }
                    .buttonStyle(.borderedProminent)
            }
        case .register(let request):
            Section("Create a demo passkey") {
                LabeledContent("Relying party", value: request.relyingParty)
                LabeledContent("User", value: request.userName)
                LabeledContent("User verification", value: request.userVerification.rawValue)
                Text("A new P-256 key is generated and stored in this device's keychain; the site receives the public key with attestation format none.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Create Passkey") { actions.register(request) }
                    .buttonStyle(.borderedProminent)
            }
        case .configuration:
            Section("Apple Toolbox is an AutoFill provider") {
                Text("\(model.vault.passwords.count) demo passwords and \(model.vault.passkeys.count) demo passkeys are in the vault. Save them to the identity store so the QuickType bar offers them.")
                Button("Save Identities", action: actions.saveIdentities)
                Button("Done", action: actions.finishConfiguration)
                    .buttonStyle(.borderedProminent)
            }
        case .unsupported:
            Section { Text("This request cannot be handled by the demo provider.") }
        }
    }
}

private struct PasswordRow: View {
    let credential: DemoPasswordCredential

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(credential.user, systemImage: "key.fill").font(.body.weight(.medium))
            Text("\(credential.domain) · \(String(repeating: "•", count: 8))").font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct PasskeyRow: View {
    let passkey: DemoPasskeyCredential

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(passkey.userName, systemImage: "person.badge.key.fill").font(.body.weight(.medium))
            Text("\(passkey.relyingParty) · created \(passkey.createdAt.formatted(date: .abbreviated, time: .shortened)) · sign count \(passkey.signCount)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// Reads the system's AutoFill request objects through KVC instead of the AuthenticationServices Swift types. On iOS 27
/// the system hands over private classes (such as SFPasskeyCredentialIdentity) that don't cast to
/// ASPasskeyCredentialIdentity, and arrays of them trap when the Swift overlay bridges them (#109). The app side reads
/// stored identities the same way (CredentialProviderExperimentService.describeIdentity).
private enum AutoFillObject {
    static func value(_ key: String, of object: NSObject) -> Any? {
        guard object.responds(to: NSSelectorFromString(key)) else { return nil }
        return object.value(forKey: key)
    }

    static func object(_ key: String, of object: NSObject) -> NSObject? { value(key, of: object) as? NSObject }
    static func string(_ key: String, of object: NSObject) -> String? { value(key, of: object) as? String }
    static func data(_ key: String, of object: NSObject) -> Data? { value(key, of: object) as? Data }

    /// The request's identity as a plain object, whatever class the system used.
    static func identity(of request: any ASCredentialRequest) -> NSObject? {
        guard let request = request as AnyObject as? NSObject else { return nil }
        return object("credentialIdentity", of: request)
    }

    /// `excludedCredentials` kept as an NSArray, so no element is bridged to a Swift type.
    static func excludedCredentialIDs(of request: ASPasskeyCredentialRequest) -> Set<Data> {
        guard let descriptors = value("excludedCredentials", of: request) as? NSArray else { return [] }
        return Set(descriptors.compactMap { ($0 as? NSObject).flatMap { data("credentialID", of: $0) } })
    }
}
