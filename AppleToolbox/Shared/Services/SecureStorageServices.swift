import Foundation
#if canImport(CryptoKit)
import CryptoKit
#endif
#if canImport(LocalAuthentication) && (os(iOS) || os(macOS))
import LocalAuthentication
#endif
#if canImport(Security)
import Security
#endif

/// Turns an OSStatus into its symbolic name, number and the system's own description.
nonisolated enum KeychainStatus {
    static func describe(_ status: OSStatus) -> String {
        #if canImport(Security)
        let name = switch status {
        case errSecSuccess: "errSecSuccess"
        case errSecItemNotFound: "errSecItemNotFound"
        case errSecDuplicateItem: "errSecDuplicateItem"
        case errSecUserCanceled: "errSecUserCanceled"
        case errSecAuthFailed: "errSecAuthFailed"
        case errSecInteractionNotAllowed: "errSecInteractionNotAllowed"
        case errSecMissingEntitlement: "errSecMissingEntitlement"
        case errSecNotAvailable: "errSecNotAvailable"
        case errSecParam: "errSecParam"
        case errSecDecode: "errSecDecode"
        default: "OSStatus"
        }
        let message = SecCopyErrorMessageString(status, nil) as String? ?? "No system description"
        return "\(name) (\(status)) · \(message)"
        #else
        return "OSStatus \(status)"
        #endif
    }
}

nonisolated enum KeychainProtection: String, CaseIterable, Identifiable {
    case userPresence, biometryCurrentSet

    var id: String { rawValue }
    var title: String {
        switch self {
        case .userPresence: "User presence (biometry or passcode)"
        case .biometryCurrentSet: "Current biometry set only"
        }
    }
}

nonisolated struct KeychainService {
    private static let account = "com.jorisconrad.appletoolbox.demo"
    private static let protectedAccount = "com.jorisconrad.appletoolbox.protected"
    private static let service = "com.jorisconrad.appletoolbox"

    static func save(value: String = "Keychain test · \(ISO8601DateFormatter().string(from: Date()))") -> String {
        #if canImport(Security)
        let value = Data(value.utf8)
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrAccount as String: account]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = value
        let saveStatus = SecItemAdd(add as CFDictionary, nil)
        return "Save: \(KeychainStatus.describe(saveStatus))\nAccount: \(account)\nValue: \(String(data: value, encoding: .utf8) ?? "<binary>")"
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
        return "Read: \(KeychainStatus.describe(readStatus))\nValue: \(readValue)"
        #else
        return "Keychain is not available on this platform."
        #endif
    }

    static func delete() -> String {
        #if canImport(Security)
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrAccount as String: account]
        return "Delete: \(KeychainStatus.describe(SecItemDelete(query as CFDictionary)))"
        #else
        return "Keychain is not available on this platform."
        #endif
    }

    static func run(value: String = "Keychain test") -> String { "\(save(value: value))\n\(read())\n\(delete())" }

    // MARK: Access-controlled item

    /// Stores an item that the system only releases after Face ID, Touch ID or the passcode.
    static func saveProtected(value: String, protection: KeychainProtection) -> String {
        #if canImport(LocalAuthentication) && (os(iOS) || os(macOS))
        let flags: SecAccessControlCreateFlags = protection == .userPresence ? .userPresence : .biometryCurrentSet
        var error: Unmanaged<CFError>?
        guard let access = SecAccessControlCreateWithFlags(nil, kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly, flags, &error) else {
            return "SecAccessControlCreateWithFlags failed: \(error?.takeRetainedValue().localizedDescription ?? "unknown error")"
        }
        let query = protectedQuery()
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = Data(value.utf8)
        add[kSecAttrAccessControl as String] = access
        let status = SecItemAdd(add as CFDictionary, nil)
        let biometry = DeviceProbes.biometry()
        var lines = [
            "Save protected item: \(KeychainStatus.describe(status))",
            "Protection: \(protection.title)",
            "Accessible: only while a passcode is set, this device only",
            "Biometry: \(biometry.name ?? "none") · \(biometry.isReady ? "ready" : biometry.reason ?? "not ready")",
        ]
        if status == errSecMissingEntitlement {
            lines.append("Access-controlled items live in the data protection keychain, which needs a signed app with an application identifier.")
        } else if status != errSecSuccess && protection == .biometryCurrentSet && !biometry.isReady {
            lines.append("Current-biometry items need enrolled Face ID or Touch ID.")
        }
        return lines.joined(separator: "\n")
        #else
        return "Access-controlled Keychain items need LocalAuthentication, which is not available on this platform."
        #endif
    }

    /// Reads the protected item off the main thread; the system shows Face ID, Touch ID or the passcode sheet.
    static func readProtected() async -> String {
        #if canImport(LocalAuthentication) && (os(iOS) || os(macOS))
        await Task.detached(priority: .userInitiated) {
            let context = LAContext()
            context.localizedReason = "Read the protected Apple Toolbox Keychain item"
            var query = protectedQuery()
            query[kSecReturnData as String] = true
            query[kSecMatchLimit as String] = kSecMatchLimitOne
            query[kSecUseAuthenticationContext as String] = context
            var result: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &result)
            let value = (result as? Data).flatMap { String(data: $0, encoding: .utf8) }
            return "Read protected item: \(KeychainStatus.describe(status))" + (value.map { "\nValue: \($0)" } ?? "")
        }.value
        #else
        "Access-controlled Keychain items need LocalAuthentication, which is not available on this platform."
        #endif
    }

    static func deleteProtected() -> String {
        #if canImport(Security)
        "Delete protected item: \(KeychainStatus.describe(SecItemDelete(protectedQuery() as CFDictionary)))"
        #else
        "Keychain is not available on this platform."
        #endif
    }

    #if canImport(Security)
    private static func protectedQuery() -> [String: Any] {
        var query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: protectedAccount]
        #if os(macOS)
        // Access control is only enforced by the data protection keychain on macOS.
        query[kSecUseDataProtectionKeychain as String] = true
        #endif
        return query
    }
    #endif
}

nonisolated struct SecureEnclaveService {
    private static let service = "com.jorisconrad.appletoolbox"
    private static let keyAccount = "com.jorisconrad.appletoolbox.secure-enclave-key"
    private static let userPresence = "requires user presence"
    private static let noProtection = "no user presence required"

    /// One-off key that is discarded after signing.
    static func run(message: String = "Secure Enclave test") throws -> String {
        #if canImport(CryptoKit)
        guard SecureEnclave.isAvailable else { throw ExperimentServiceError.unavailable("This device or simulator does not provide a Secure Enclave.") }
        let key = try SecureEnclave.P256.Signing.PrivateKey()
        let data = Data(message.utf8)
        let signature = try key.signature(for: data)
        let verified = key.publicKey.isValidSignature(signature, for: data)
        return "Message: \(message)\nOne-time non-exportable key created (not stored)\nPublic key: \(key.publicKey.rawRepresentation.base64EncodedString())\nSignature verified: \(verified)"
        #else
        throw ExperimentServiceError.unavailable("CryptoKit is not available on this platform.")
        #endif
    }

    // MARK: Persistent key

    /// Describes the stored key from its Keychain attributes only, so it never triggers authentication.
    static func storedKeySummary() -> String {
        #if canImport(Security)
        var query = keyQuery()
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let attributes = result as? [String: Any] else {
            return status == errSecItemNotFound ? "None stored yet" : KeychainStatus.describe(status)
        }
        let created = (attributes[kSecAttrCreationDate as String] as? Date).map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "unknown date"
        let protection = attributes[kSecAttrDescription as String] as? String ?? "unknown protection"
        let fingerprint = attributes[kSecAttrComment as String] as? String ?? "unknown fingerprint"
        return "Stored \(created) · \(protection) · \(fingerprint)"
        #else
        return "Keychain is not available on this platform."
        #endif
    }

    /// Restores the key from its Keychain blob ("reused") or creates and stores a new one ("created"), then signs and verifies.
    static func signWithPersistentKey(message: String, requireUserPresence: Bool) async -> String {
        #if canImport(CryptoKit) && canImport(LocalAuthentication) && (os(iOS) || os(macOS))
        await Task.detached(priority: .userInitiated) { persistentSign(message: message, requireUserPresence: requireUserPresence) }.value
        #else
        "Persistent Secure Enclave keys are not available on this platform."
        #endif
    }

    static func deletePersistentKey() -> String {
        #if canImport(Security)
        let status = SecItemDelete(keyQuery() as CFDictionary)
        guard status == errSecSuccess else { return "Delete stored key: \(KeychainStatus.describe(status))" }
        return "Delete stored key: \(KeychainStatus.describe(status))\nThe key blob is gone, so this Secure Enclave key can never be used again. The next persistent run creates a new key."
        #else
        return "Keychain is not available on this platform."
        #endif
    }

    #if canImport(CryptoKit) && canImport(LocalAuthentication) && (os(iOS) || os(macOS))
    private static func persistentSign(message: String, requireUserPresence: Bool) -> String {
        guard SecureEnclave.isAvailable else { return "This device or simulator does not provide a Secure Enclave." }
        let context = LAContext()
        context.localizedReason = "Sign your message with the Apple Toolbox Secure Enclave key"
        var lines: [String] = []
        do {
            let key: SecureEnclave.P256.Signing.PrivateKey
            var query = keyQuery()
            query[kSecReturnData as String] = true
            query[kSecReturnAttributes as String] = true
            query[kSecMatchLimit as String] = kSecMatchLimitOne
            var result: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &result)
            if status == errSecSuccess, let item = result as? [String: Any], let blob = item[kSecValueData as String] as? Data {
                key = try SecureEnclave.P256.Signing.PrivateKey(dataRepresentation: blob, authenticationContext: context)
                let protection = item[kSecAttrDescription as String] as? String ?? "unknown protection"
                lines += ["Key: reused (restored from its Keychain blob)", "Protection: \(protection)"]
                if (protection == userPresence) != requireUserPresence {
                    lines.append("Note: a stored key keeps the protection it was created with. Delete it to create one with the other setting.")
                }
            } else if status == errSecItemNotFound {
                var error: Unmanaged<CFError>?
                let flags: SecAccessControlCreateFlags = requireUserPresence ? [.privateKeyUsage, .userPresence] : .privateKeyUsage
                guard let access = SecAccessControlCreateWithFlags(nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly, flags, &error) else {
                    return "SecAccessControlCreateWithFlags failed: \(error?.takeRetainedValue().localizedDescription ?? "unknown error")"
                }
                key = try SecureEnclave.P256.Signing.PrivateKey(accessControl: access, authenticationContext: context)
                let protection = requireUserPresence ? userPresence : noProtection
                let storeStatus = store(key, protection: protection)
                lines += ["Key: created in the Secure Enclave", "Protection: \(protection)", "Blob stored in Keychain: \(KeychainStatus.describe(storeStatus))"]
            } else {
                return "Reading the stored key failed: \(KeychainStatus.describe(status))"
            }
            let data = Data(message.utf8)
            let signature = try key.signature(for: data)
            let verified = key.publicKey.isValidSignature(signature, for: data)
            lines += [
                "Public key fingerprint: \(fingerprint(key.publicKey))",
                "Message: \(message)",
                "Signature: \(signature.derRepresentation.count) bytes (DER)",
                "Signature verified: \(verified)",
            ]
        } catch {
            lines.append("Error: \(describe(error))")
        }
        return lines.joined(separator: "\n")
    }

    private static func store(_ key: SecureEnclave.P256.Signing.PrivateKey, protection: String) -> OSStatus {
        var item = keyQuery()
        SecItemDelete(item as CFDictionary)
        item[kSecValueData as String] = key.dataRepresentation
        item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        item[kSecAttrLabel as String] = "Apple Toolbox Secure Enclave signing key"
        item[kSecAttrDescription as String] = protection
        item[kSecAttrComment as String] = fingerprint(key.publicKey)
        return SecItemAdd(item as CFDictionary, nil)
    }

    /// First 16 bytes of the SHA-256 digest of the X9.63 public key.
    private static func fingerprint(_ publicKey: P256.Signing.PublicKey) -> String {
        let hex = SHA256.hash(data: publicKey.x963Representation).map { String(format: "%02x", $0) }.joined()
        return "SHA-256 " + stride(from: 0, to: 32, by: 8).map { String(hex.dropFirst($0).prefix(8)) }.joined(separator: " ") + " …"
    }

    private static func describe(_ error: Error) -> String {
        let error = error as NSError
        if error.domain == NSOSStatusErrorDomain { return KeychainStatus.describe(OSStatus(error.code)) }
        if error.domain == LAErrorDomain { return "LocalAuthentication \(error.code) · \(error.localizedDescription)" }
        return "\(error.localizedDescription) (\(error.domain) \(error.code))"
    }
    #endif

    #if canImport(Security)
    private static func keyQuery() -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: keyAccount]
    }
    #endif
}
