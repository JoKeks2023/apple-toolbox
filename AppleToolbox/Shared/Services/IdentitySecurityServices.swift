import Foundation

#if canImport(DeviceCheck)
import DeviceCheck
#endif

#if canImport(AuthenticationServices)
import AuthenticationServices
#endif

enum IdentitySecurityExperimentService {
    static func appAttestStatus() -> String {
        #if canImport(DeviceCheck)
        let supported = DCAppAttestService.shared.isSupported
        return supported
            ? "App Attest is supported on this device. A server challenge and App Attest entitlement are required before generating an attestation."
            : "App Attest is not supported on this device or platform."
        #else
        return "DeviceCheck/App Attest is not available in this platform SDK."
        #endif
    }

    static func passkeyStatus() -> String {
        #if canImport(AuthenticationServices)
        return "AuthenticationServices is available. Passkeys require a configured associated domain and relying-party server; this experiment does not fake a credential."
        #else
        return "AuthenticationServices is not available on this platform."
        #endif
    }

    static func signInWithAppleStatus() -> String {
        #if canImport(AuthenticationServices)
        return "Sign in with Apple APIs are available. A real authorization request requires the app capability and a user-driven authorization flow."
        #else
        return "Sign in with Apple is not available on this platform."
        #endif
    }
}
