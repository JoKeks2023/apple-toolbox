import Foundation
#if canImport(CryptoKit)
import CryptoKit
#endif
#if canImport(LocalAuthentication)
import LocalAuthentication
#endif

enum ExperimentServiceError: LocalizedError {
    case unavailable(String)
    var errorDescription: String? {
        if case .unavailable(let message) = self { return message }
        return nil
    }
}

struct AuthenticationService {
    static func availability() -> String {
        #if canImport(LocalAuthentication) && !os(watchOS) && !os(tvOS)
        let context = LAContext()
        var error: NSError?
        let available = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
        return "Biometry: \(context.biometryType.displayName)\nAvailable: \(available)\(error.map { "\nReason: \($0.localizedDescription)" } ?? "")"
        #else
        return "LocalAuthentication is not available on this platform."
        #endif
    }

    static func authenticate() async throws -> String {
        #if canImport(LocalAuthentication) && !os(watchOS) && !os(tvOS)
        let context = LAContext()
        var biometricError: NSError?
        let biometricAvailable = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &biometricError)
        let policy: LAPolicy
        if biometricAvailable {
            policy = .deviceOwnerAuthenticationWithBiometrics
        } else {
            var authenticationError: NSError?
            guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &authenticationError) else {
                throw ExperimentServiceError.unavailable(authenticationError?.localizedDescription ?? biometricError?.localizedDescription ?? "Authentication is not available on this device.")
            }
            policy = .deviceOwnerAuthentication
        }
        let reason = "Verify your identity to test LocalAuthentication."
        let method = policy == .deviceOwnerAuthenticationWithBiometrics ? context.biometryType.displayName : "device passcode / authentication"
        return try await withCheckedThrowingContinuation { continuation in
            context.evaluatePolicy(policy, localizedReason: reason) { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if success {
                    continuation.resume(returning: "Authentication succeeded using \(method).")
                } else {
                    continuation.resume(throwing: ExperimentServiceError.unavailable("Authentication did not succeed."))
                }
            }
        }
        #else
        throw ExperimentServiceError.unavailable("LocalAuthentication is not available on this platform.")
        #endif
    }
}

#if canImport(LocalAuthentication) && !os(tvOS)
private extension LABiometryType {
    var displayName: String {
        switch self { case .faceID: "Face ID"; case .touchID: "Touch ID"; default: "passcode / device authentication" }
    }
}
#endif

struct CryptoService {
    private static let defaultMessage = "Joris Apple Toolbox · CryptoKit"

    static func hash(message: String = defaultMessage) -> String {
        guard let digest = sha256Hex(message) else { return "CryptoKit is not available on this platform." }
        return "Message: \(message)\nSHA-256: \(digest)"
    }

    /// Lowercase hex SHA-256 digest of the UTF-8 bytes, or nil where CryptoKit is missing.
    static func sha256Hex(_ message: String) -> String? {
        #if canImport(CryptoKit)
        SHA256.hash(data: Data(message.utf8)).map { String(format: "%02x", $0) }.joined()
        #else
        nil
        #endif
    }

    static func signAndVerify(message: String = defaultMessage) -> String {
        #if canImport(CryptoKit)
        let data = Data(message.utf8)
        let key = P256.Signing.PrivateKey()
        let signature = try? key.signature(for: data)
        let verified = signature.map { (try? key.publicKey.isValidSignature($0, for: data)) == true } ?? false
        return "Message: \(message)\nP256 public key: \(key.publicKey.rawRepresentation.base64EncodedString())\nSignature bytes: \(signature?.rawRepresentation.count ?? 0)\nSignature verified: \(verified)"
        #else
        return "CryptoKit is not available on this platform."
        #endif
    }

    static func run(message: String = defaultMessage) -> String { "\(hash(message: message))\n\n\(signAndVerify(message: message))" }
}
