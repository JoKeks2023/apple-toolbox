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

/// Passkey registration and assertion through ASAuthorizationController (spec §8). The system only allows relying parties
/// listed as `webcredentials:` associated domains; without one it rejects the request, and that error is the honest result.
@MainActor
final class PasskeyExperimentService: NSObject, ObservableObject {
    @Published var relyingPartyID: String
    @Published var userName = "toolbox-user"
    @Published private(set) var output: String
    @Published private(set) var isError = false
    @Published private(set) var isRunning = false
    #if canImport(AuthenticationServices) && !os(watchOS)
    private var controller: ASAuthorizationController?
    private var anchor: ASPresentationAnchor?
    private var pendingRequest = ""
    private var pendingRelyingParty = ""
    #endif

    init(initialOutput: String) {
        output = initialOutput
        relyingPartyID = WebCredentialsConfiguration.current.domains.first ?? "example.com"
        super.init()
    }

    static var configurationSummary: String { WebCredentialsConfiguration.current.summary }

    func register() {
        #if canImport(AuthenticationServices) && !os(watchOS)
        guard let relyingParty = trimmedRelyingParty() else { return }
        let name = userName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return finish("Enter a user name for the new passkey.", isError: true) }
        let challenge = LocalChallenge.randomBytes(32)
        let userHandle = LocalChallenge.randomBytes(16)
        let request = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: relyingParty)
            .createCredentialRegistrationRequest(challenge: challenge, name: name, userID: userHandle)
        perform(request, kind: "Registration", relyingParty: relyingParty, details: """
        Registration request for “\(name)” at \(relyingParty)
        Challenge: \(challenge.count) random bytes generated on this device (\(LocalChallenge.hexPrefix(challenge)))
        User ID: \(userHandle.count) random bytes generated on this device (a real server uses a stable, non-personal account handle)
        """)
        #else
        finish("Passkeys are not available on this platform.", isError: true)
        #endif
    }

    func signIn() {
        #if canImport(AuthenticationServices) && !os(watchOS)
        guard let relyingParty = trimmedRelyingParty() else { return }
        let challenge = LocalChallenge.randomBytes(32)
        let request = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: relyingParty)
            .createCredentialAssertionRequest(challenge: challenge)
        perform(request, kind: "Assertion", relyingParty: relyingParty, details: """
        Assertion request at \(relyingParty)
        Challenge: \(challenge.count) random bytes generated on this device (\(LocalChallenge.hexPrefix(challenge)))
        """)
        #else
        finish("Passkeys are not available on this platform.", isError: true)
        #endif
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
    private func perform(_ request: ASAuthorizationRequest, kind: String, relyingParty: String, details: String) {
        guard let window = Self.currentWindow() else { return finish("No window is available to present the passkey sheet.", isError: true) }
        anchor = window
        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        self.controller = controller
        pendingRequest = details
        pendingRelyingParty = relyingParty
        isRunning = true
        finish(details + "\n  LOCAL ONLY: a relying-party server issues the challenge and verifies the response.\n\(kind) sent to the system; waiting for the passkey sheet…")
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
            complete("The system returned an unexpected credential type: \(type(of: authorization.credential)).", isError: true)
        }
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        var text = AuthorizationErrorReport.describe(error, context: "Passkey request")
        let configuration = WebCredentialsConfiguration.current
        if !configuration.isWildcardOnly && !configuration.domains.contains(pendingRelyingParty) {
            text += "\nThis app lists no webcredentials:\(pendingRelyingParty) associated domain, so the system rejects passkey requests for it."
        } else if (error as NSError).code == ASAuthorizationError.Code.canceled.rawValue {
            text += "\nThe sheet was dismissed, which is also the result when no passkey exists and the person cancels."
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
