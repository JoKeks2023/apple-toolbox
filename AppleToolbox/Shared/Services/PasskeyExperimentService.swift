import Foundation
import Combine

#if canImport(AuthenticationServices)
import AuthenticationServices
#endif
#if os(iOS) || os(tvOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// Which WebAuthn authenticator a request targets: a synced passkey on this device, or an external FIDO2 security key.
nonisolated enum WebAuthnAuthenticator: String, Sendable {
    case platform, securityKey

    var credentialName: String { self == .platform ? "passkey" : "security key credential" }
}

/// WebAuthn `userVerification`; the enumerable options become Pickers in the security key lab.
nonisolated enum WebAuthnUserVerification: String, CaseIterable, Identifiable, Sendable {
    case preferred, required, discouraged
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

/// WebAuthn `attestation` conveyance preference.
nonisolated enum WebAuthnAttestation: String, CaseIterable, Identifiable, Sendable {
    case noAttestation = "none", indirect, direct, enterprise
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

/// WebAuthn `residentKey`: whether the key stores a discoverable credential (usable without a credential ID).
nonisolated enum WebAuthnResidentKey: String, CaseIterable, Identifiable, Sendable {
    case discouraged, preferred, required
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

/// Passkey and security key registration and assertion through ASAuthorizationController (spec §8). The system only allows
/// relying parties listed as `webcredentials:` associated domains; without one it rejects the request, and that error is the honest result.
@MainActor
final class PasskeyExperimentService: NSObject, ObservableObject {
    @Published var relyingPartyID: String
    @Published var userName = "toolbox-user"
    @Published var userVerification = WebAuthnUserVerification.preferred
    @Published var attestation = WebAuthnAttestation.noAttestation
    @Published var residentKey = WebAuthnResidentKey.discouraged
    @Published private(set) var output: String
    @Published private(set) var isError = false
    @Published private(set) var isRunning = false
    /// Credential ID of the security key registered in this session; the next assertion names it in allowCredentials.
    @Published private(set) var registeredCredentialID: Data?
    let authenticator: WebAuthnAuthenticator
    #if canImport(AuthenticationServices) && !os(watchOS)
    private var controller: ASAuthorizationController?
    private var anchor: ASPresentationAnchor?
    private var pendingRequest = ""
    private var pendingRelyingParty = ""
    #endif

    init(initialOutput: String, authenticator: WebAuthnAuthenticator = .platform) {
        output = initialOutput
        self.authenticator = authenticator
        relyingPartyID = WebCredentialsConfiguration.current.domains.first ?? "example.com"
        super.init()
    }

    static var configurationSummary: String { WebCredentialsConfiguration.current.summary }

    func register() {
        #if canImport(AuthenticationServices) && !os(watchOS)
        guard let relyingParty = trimmedRelyingParty() else { return }
        let name = userName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return finish("Enter a user name for the new \(authenticator.credentialName).", isError: true) }
        let challenge = LocalChallenge.randomBytes(32)
        let userHandle = LocalChallenge.randomBytes(16)
        guard let request = registrationRequest(relyingParty: relyingParty, challenge: challenge, name: name, userID: userHandle) else {
            return finish("Security keys are not available on this platform.", isError: true)
        }
        perform(request, kind: "Registration", relyingParty: relyingParty, details: """
        \(authenticator == .platform ? "Passkey" : "Security key") registration request for “\(name)” at \(relyingParty)
        Challenge: \(challenge.count) random bytes generated on this device (\(LocalChallenge.hexPrefix(challenge)))
        User ID: \(userHandle.count) random bytes generated on this device (a real server uses a stable, non-personal account handle)
        """ + optionSummary(registration: true))
        #else
        finish("Passkeys are not available on this platform.", isError: true)
        #endif
    }

    func signIn() {
        #if canImport(AuthenticationServices) && !os(watchOS)
        guard let relyingParty = trimmedRelyingParty() else { return }
        let challenge = LocalChallenge.randomBytes(32)
        guard let request = assertionRequest(relyingParty: relyingParty, challenge: challenge) else {
            return finish("Security keys are not available on this platform.", isError: true)
        }
        perform(request, kind: "Assertion", relyingParty: relyingParty, details: """
        \(authenticator == .platform ? "Passkey" : "Security key") assertion request at \(relyingParty)
        Challenge: \(challenge.count) random bytes generated on this device (\(LocalChallenge.hexPrefix(challenge)))
        """ + optionSummary(registration: false))
        #else
        finish("Passkeys are not available on this platform.", isError: true)
        #endif
    }

    /// The security key options that went into the request; passkey requests keep the system defaults.
    private func optionSummary(registration: Bool) -> String {
        guard authenticator == .securityKey else { return "" }
        var lines = ["User verification: \(userVerification.rawValue)"]
        if registration {
            lines += ["Attestation: \(attestation.rawValue)", "Resident key: \(residentKey.rawValue)", "Algorithm: ES256 (COSE -7)"]
        } else {
            lines.append(registeredCredentialID.map { "Allowed credential: \(LocalChallenge.hexPrefix($0)) (registered in this session), any transport" }
                         ?? "Allowed credentials: none (the key must hold a discoverable credential for this relying party)")
        }
        return "\n" + lines.joined(separator: "\n")
    }

    private func trimmedRelyingParty() -> String? {
        let relyingParty = relyingPartyID.trimmingCharacters(in: .whitespacesAndNewlines)
        if relyingParty.isEmpty { finish("Enter the relying-party identifier, usually the domain of the service (for example example.com).", isError: true) }
        return relyingParty.isEmpty ? nil : relyingParty
    }

    private func finish(_ text: String, isError: Bool = false) {
        output = text
        self.isError = isError
    }

    #if canImport(AuthenticationServices) && !os(watchOS)
    private func registrationRequest(relyingParty: String, challenge: Data, name: String, userID: Data) -> ASAuthorizationRequest? {
        switch authenticator {
        case .platform:
            return ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: relyingParty)
                .createCredentialRegistrationRequest(challenge: challenge, name: name, userID: userID)
        case .securityKey:
            #if os(iOS) || os(macOS)
            let request = ASAuthorizationSecurityKeyPublicKeyCredentialProvider(relyingPartyIdentifier: relyingParty)
                .createCredentialRegistrationRequest(challenge: challenge, displayName: name, name: name, userID: userID)
            request.credentialParameters = [ASAuthorizationPublicKeyCredentialParameters(algorithm: .ES256)]
            request.userVerificationPreference = userVerification.preference
            request.attestationPreference = attestation.kind
            request.residentKeyPreference = residentKey.preference
            return request
            #else
            return nil
            #endif
        }
    }

    private func assertionRequest(relyingParty: String, challenge: Data) -> ASAuthorizationRequest? {
        switch authenticator {
        case .platform:
            return ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: relyingParty)
                .createCredentialAssertionRequest(challenge: challenge)
        case .securityKey:
            #if os(iOS) || os(macOS)
            let request = ASAuthorizationSecurityKeyPublicKeyCredentialProvider(relyingPartyIdentifier: relyingParty)
                .createCredentialAssertionRequest(challenge: challenge)
            request.userVerificationPreference = userVerification.preference
            if let registeredCredentialID {
                request.allowedCredentials = [ASAuthorizationSecurityKeyPublicKeyCredentialDescriptor(
                    credentialID: registeredCredentialID, transports: ASAuthorizationSecurityKeyPublicKeyCredentialDescriptor.Transport.allSupported)]
            }
            return request
            #else
            return nil
            #endif
        }
    }

    private func perform(_ request: ASAuthorizationRequest, kind: String, relyingParty: String, details: String) {
        guard let window = Self.currentWindow() else { return finish("No window is available to present the \(authenticator.credentialName) sheet.", isError: true) }
        anchor = window
        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        self.controller = controller
        pendingRequest = details
        pendingRelyingParty = relyingParty
        isRunning = true
        finish(details + "\n  LOCAL ONLY: a relying-party server issues the challenge and verifies the response.\n\(kind) sent to the system; waiting for the \(authenticator.credentialName) sheet…")
        controller.performRequests()
    }

    private func complete(_ text: String, isError: Bool = false) {
        controller = nil
        isRunning = false
        finish(pendingRequest + "\n\n" + text, isError: isError)
    }

    private static func currentWindow() -> ASPresentationAnchor? {
        #if os(macOS)
        NSApplication.shared.keyWindow ?? NSApplication.shared.mainWindow ?? NSApplication.shared.windows.first
        #else
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let activeScene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        return activeScene?.windows.first(where: \.isKeyWindow) ?? activeScene?.windows.first
        #endif
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
    #endif
}

#if canImport(AuthenticationServices) && !os(watchOS)
extension PasskeyExperimentService: ASAuthorizationControllerDelegate {
    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        switch authorization.credential {
        case let registration as ASAuthorizationPlatformPublicKeyCredentialRegistration:
            complete("""
            Passkey created for \(pendingRelyingParty).
            Credential ID: \(Self.base64URL(registration.credentialID).prefix(16))… (\(registration.credentialID.count) bytes)
            Client data JSON: \(registration.rawClientDataJSON.count) bytes
            Attestation object: \(registration.rawAttestationObject.map { "\($0.count) bytes" } ?? "not returned")
            Next: the relying-party server checks challenge and origin in the client data and stores the public key from the attestation object.
            """)
        case let assertion as ASAuthorizationPlatformPublicKeyCredentialAssertion:
            complete("""
            Signed in with a passkey for \(pendingRelyingParty).
            Credential ID: \(Self.base64URL(assertion.credentialID).prefix(16))… (\(assertion.credentialID.count) bytes)
            User ID: \(assertion.userID.count) bytes · Signature: \(assertion.signature.count) bytes
            Authenticator data: \(assertion.rawAuthenticatorData.count) bytes · Client data JSON: \(assertion.rawClientDataJSON.count) bytes
            Next: the relying-party server verifies the signature with the stored public key and checks the challenge.
            """)
        default:
            #if os(iOS) || os(macOS)
            if let text = securityKeyResult(authorization.credential) { return complete(text) }
            #endif
            complete("The system returned an unexpected credential type: \(type(of: authorization.credential)).", isError: true)
        }
    }

    #if os(iOS) || os(macOS)
    private func securityKeyResult(_ credential: ASAuthorizationCredential) -> String? {
        switch credential {
        case let registration as ASAuthorizationSecurityKeyPublicKeyCredentialRegistration:
            registeredCredentialID = registration.credentialID
            return """
            Security key credential created for \(pendingRelyingParty).
            Credential ID: \(Self.base64URL(registration.credentialID).prefix(16))… (\(registration.credentialID.count) bytes)
            Transports reported by the key: \(registration.transports.isEmpty ? "none" : registration.transports.map(\.rawValue).joined(separator: ", "))
            Client data JSON: \(registration.rawClientDataJSON.count) bytes
            Attestation object: \(registration.rawAttestationObject.map { "\($0.count) bytes (format per the \(attestation.rawValue) preference)" } ?? "not returned")
            Next: the relying-party server checks challenge and origin, validates the attestation if it asked for one, and stores the public key.
            """
        case let assertion as ASAuthorizationSecurityKeyPublicKeyCredentialAssertion:
            return """
            Signed in with a security key for \(pendingRelyingParty).
            Credential ID: \(Self.base64URL(assertion.credentialID).prefix(16))… (\(assertion.credentialID.count) bytes)
            User ID: \(assertion.userID.count) bytes · Signature: \(assertion.signature.count) bytes · legacy AppID used: \(assertion.appID)
            Authenticator data: \(assertion.rawAuthenticatorData.count) bytes · Client data JSON: \(assertion.rawClientDataJSON.count) bytes
            Next: the relying-party server verifies the signature with the stored public key, checks the challenge and the signature counter.
            """
        default:
            return nil
        }
    }
    #endif

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        var text = AuthorizationErrorReport.describe(error, context: authenticator == .platform ? "Passkey request" : "Security key request")
        let configuration = WebCredentialsConfiguration.current
        if !configuration.isWildcardOnly && !configuration.domains.contains(pendingRelyingParty) {
            text += "\nThis app lists no webcredentials:\(pendingRelyingParty) associated domain, so the system rejects \(authenticator.credentialName) requests for it."
        } else if (error as NSError).code == ASAuthorizationError.Code.canceled.rawValue {
            text += "\nThe sheet was dismissed, which is also the result when no \(authenticator.credentialName) exists and the person cancels."
        }
        complete(text, isError: true)
    }
}

extension PasskeyExperimentService: ASAuthorizationControllerPresentationContextProviding {
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        guard let anchor else { preconditionFailure("perform(_:) only starts a request after it found a window") }
        return anchor
    }
}

extension PasskeyExperimentService: StoppableExperiment {
    var isActive: Bool { isRunning }

    func stop() {
        controller?.cancel()
    }
}
#endif

#if canImport(AuthenticationServices) && (os(iOS) || os(macOS))
extension WebAuthnUserVerification {
    var preference: ASAuthorizationPublicKeyCredentialUserVerificationPreference {
        switch self {
        case .preferred: .preferred
        case .required: .required
        case .discouraged: .discouraged
        }
    }
}

extension WebAuthnAttestation {
    var kind: ASAuthorizationPublicKeyCredentialAttestationKind {
        switch self {
        case .noAttestation: .none
        case .indirect: .indirect
        case .direct: .direct
        case .enterprise: .enterprise
        }
    }
}

extension WebAuthnResidentKey {
    var preference: ASAuthorizationPublicKeyCredentialResidentKeyPreference {
        switch self {
        case .discouraged: .discouraged
        case .preferred: .preferred
        case .required: .required
        }
    }
}
#endif
