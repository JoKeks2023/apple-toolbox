import Foundation

#if canImport(AuthenticationServices)
import AuthenticationServices
#endif

enum IdentitySecurityExperimentService {
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

/// Random bytes generated on this device. The identity labs have no server, so they use them as challenges; in production
/// the server issues every challenge and verifies the result.
enum LocalChallenge {
    static func randomBytes(_ count: Int) -> Data {
        var generator = SystemRandomNumberGenerator()
        return Data((0..<count).map { _ in UInt8.random(in: .min ... .max, using: &generator) })
    }

    static func hexPrefix(_ data: Data, bytes: Int = 8) -> String {
        data.prefix(bytes).map { String(format: "%02x", $0) }.joined() + (data.count > bytes ? "…" : "")
    }
}
