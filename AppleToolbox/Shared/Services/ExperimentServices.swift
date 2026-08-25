import Foundation
#if canImport(CryptoKit)
import CryptoKit
#endif
#if canImport(LocalAuthentication)
import LocalAuthentication
#endif
#if canImport(Security)
import Security
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
        #if canImport(LocalAuthentication) && !os(watchOS)
        let context = LAContext()
        var error: NSError?
        let available = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
        return "Biometry: \(context.biometryType.displayName)\nAvailable: \(available)\(error.map { "\nReason: \($0.localizedDescription)" } ?? "")"
        #else
        return "LocalAuthentication is not available on this platform."
        #endif
    }

    static func authenticate() async throws -> String {
        #if canImport(LocalAuthentication) && !os(watchOS)
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

#if canImport(LocalAuthentication)
private extension LABiometryType {
    var displayName: String {
        switch self { case .faceID: "Face ID"; case .touchID: "Touch ID"; default: "passcode / device authentication" }
    }
}
#endif

struct CryptoService {
    private static let message = Data("Joris Apple Toolbox · CryptoKit".utf8)

    static func hash() -> String {
        #if canImport(CryptoKit)
        let digest = SHA256.hash(data: message).map { String(format: "%02x", $0) }.joined()
        return "Message: \(String(data: message, encoding: .utf8)!)\nSHA-256: \(digest)"
        #else
        return "CryptoKit is not available on this platform."
        #endif
    }

    static func signAndVerify() -> String {
        #if canImport(CryptoKit)
        let key = P256.Signing.PrivateKey()
        let signature = try? key.signature(for: message)
        let verified = signature.map { (try? key.publicKey.isValidSignature($0, for: message)) == true } ?? false
        return "P256 public key: \(key.publicKey.rawRepresentation.base64EncodedString())\nSignature bytes: \(signature?.rawRepresentation.count ?? 0)\nSignature verified: \(verified)"
        #else
        return "CryptoKit is not available on this platform."
        #endif
    }

    static func run() -> String { "\(hash())\n\n\(signAndVerify())" }
}

struct KeychainService {
    private static let account = "com.jorisconrad.appletoolbox.demo"
    static func save() -> String {
        #if canImport(Security)
        let value = Data("Keychain test · \(ISO8601DateFormatter().string(from: Date()))".utf8)
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrAccount as String: account]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = value
        let saveStatus = SecItemAdd(add as CFDictionary, nil)
        return "Save: \(statusMessage(saveStatus))\nAccount: \(account)\nValue: \(String(data: value, encoding: .utf8) ?? "<binary>")"
        #else
        return "Keychain is not available on this platform."
        #endif
    }

    static func read() -> String {
        #if canImport(Security)
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrAccount as String: account, kSecReturnData as String: true]
        var result: CFTypeRef?
        let readStatus = SecItemCopyMatching(query as CFDictionary, &result)
        let readValue = (result as? Data).flatMap { String(data: $0, encoding: .utf8) } ?? "<no value>"
        return "Read: \(statusMessage(readStatus))\nValue: \(readValue)"
        #else
        return "Keychain is not available on this platform."
        #endif
    }

    static func delete() -> String {
        #if canImport(Security)
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrAccount as String: account]
        return "Delete: \(statusMessage(SecItemDelete(query as CFDictionary)))"
        #else
        return "Keychain is not available on this platform."
        #endif
    }

    #if canImport(Security)
    private static func statusMessage(_ status: OSStatus) -> String {
        status == errSecSuccess ? "Success" : "OSStatus \(status)"
    }
    #endif

    static func run() -> String { "\(save())\n\(read())\n\(delete())" }
}

struct SecureEnclaveService {
    static func run() throws -> String {
        #if canImport(CryptoKit)
        guard SecureEnclave.isAvailable else { throw ExperimentServiceError.unavailable("This device or simulator does not provide a Secure Enclave.") }
        let key = try SecureEnclave.P256.Signing.PrivateKey()
        let message = Data("Secure Enclave test".utf8)
        let signature = try key.signature(for: message)
        let verified = key.publicKey.isValidSignature(signature, for: message)
        return "Non-exportable key created\nPublic key: \(key.publicKey.rawRepresentation.base64EncodedString())\nSignature verified: \(verified)"
        #else
        throw ExperimentServiceError.unavailable("CryptoKit is not available on this platform.")
        #endif
    }
}
