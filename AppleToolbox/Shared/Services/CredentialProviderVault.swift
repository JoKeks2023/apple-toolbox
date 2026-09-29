import Foundation
import CryptoKit
import Security

// Shared by the iOS app and the `AppleToolbox Credential Provider` extension: the demo credentials the provider offers
// in AutoFill, the log of what the extension did, and the WebAuthn pieces it needs to create and use demo passkeys.

/// A demo password the provider can fill. The values are generated demo data, not real secrets.
nonisolated struct DemoPasswordCredential: Codable, Equatable, Identifiable, Sendable {
    /// Also the record identifier of the password identity in ASCredentialIdentityStore.
    let id: String
    let domain: String
    let user: String
    let password: String
}

/// A passkey the provider created for a relying party. The private key lives in the keychain (App Group access group).
nonisolated struct DemoPasskeyCredential: Codable, Equatable, Identifiable, Sendable {
    let relyingParty: String
    let userName: String
    let userHandle: Data
    let credentialID: Data
    var signCount: UInt32
    let createdAt: Date

    /// Record identifier of the passkey identity: the credential ID in base64url.
    var id: String { Base64URL.encode(credentialID) }
}

/// One thing the extension did, shown in the app.
nonisolated struct CredentialVaultEvent: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let date: Date
    let text: String

    init(_ text: String, date: Date = Date()) {
        id = UUID()
        self.date = date
        self.text = text
    }
}

nonisolated struct CredentialVault: Codable, Equatable, Sendable {
    var passwords: [DemoPasswordCredential] = []
    var passkeys: [DemoPasskeyCredential] = []
    var events: [CredentialVaultEvent] = []

    static let eventLimit = 30

    mutating func log(_ text: String) {
        events = Array(([CredentialVaultEvent(text)] + events).prefix(Self.eventLimit))
    }

    /// Two demo accounts with freshly generated passwords. example.com and its subdomains are reserved for examples.
    static func demoPasswords(using generator: inout some RandomNumberGenerator) -> [DemoPasswordCredential] {
        [("example.com", "toolbox-user"), ("login.example.com", "second-account")].map { domain, user in
            DemoPasswordCredential(id: "demo-password-\(user)", domain: domain, user: user, password: demoPassword(using: &generator))
        }
    }

    /// "Demo-" plus three groups of four characters from an alphabet without look-alikes.
    static func demoPassword(using generator: inout some RandomNumberGenerator) -> String {
        let alphabet = Array("abcdefghjkmnpqrstuvwxyzABCDEFGHJKMNPQRSTUVWXYZ23456789")
        let groups = (0..<3).map { _ in String((0..<4).map { _ in alphabet.randomElement(using: &generator)! }) }
        return "Demo-" + groups.joined(separator: "-")
    }

    /// Passwords for the requested services, most specific first. A service identifier can be a domain or a URL; an entry
    /// for `example.com` also matches `www.example.com`. Without service identifiers every password is offered.
    func passwords(matching serviceIdentifiers: [String]) -> [DemoPasswordCredential] {
        let hosts = serviceIdentifiers.compactMap(Self.host(of:))
        guard !hosts.isEmpty else { return passwords }
        return passwords.filter { credential in hosts.contains { Self.host($0, belongsTo: credential.domain) } }
    }

    /// Passkeys for a relying party, limited to the allowed credential IDs when the relying party lists any.
    func passkeys(forRelyingParty relyingParty: String, allowedCredentialIDs: [Data] = []) -> [DemoPasskeyCredential] {
        passkeys.filter { passkey in
            passkey.relyingParty.caseInsensitiveCompare(relyingParty) == .orderedSame
                && (allowedCredentialIDs.isEmpty || allowedCredentialIDs.contains(passkey.credentialID))
        }
    }

    static func host(of serviceIdentifier: String) -> String? {
        let trimmed = serviceIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return nil }
        if trimmed.contains("://") { return URL(string: trimmed)?.host() }
        return trimmed.split(separator: "/").first.map(String.init)
    }

    static func host(_ host: String, belongsTo domain: String) -> Bool {
        let domain = domain.lowercased()
        return host == domain || host.hasSuffix("." + domain)
    }
}

/// The vault in the App Group's user defaults, readable by the app and the extension.
nonisolated enum CredentialVaultStore {
    private static let key = "credentialProvider.vault"
    private static let lock = NSLock()

    private static var defaults: UserDefaults? { UserDefaults(suiteName: ToolboxIdentifiers.appGroup) }

    static func load() -> CredentialVault {
        guard let data = defaults?.data(forKey: key), let vault = try? JSONDecoder().decode(CredentialVault.self, from: data) else { return CredentialVault() }
        return vault
    }

    /// Loads, changes and saves the vault in one step.
    @discardableResult
    static func update(_ change: (inout CredentialVault) -> Void) -> CredentialVault {
        lock.withLock {
            var vault = load()
            change(&vault)
            if let data = try? JSONEncoder().encode(vault) { defaults?.set(data, forKey: key) }
            return vault
        }
    }
}

// MARK: - WebAuthn

nonisolated enum Base64URL {
    static func encode(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}

/// The minimal CBOR encoder WebAuthn attestation objects and COSE keys need (RFC 8949, definite lengths only).
nonisolated enum CBOR: Equatable, Sendable {
    case unsigned(UInt64)
    case negative(Int64)
    case bytes(Data)
    case text(String)
    case array([CBOR])
    /// Entries are encoded in the given order; callers pass them in CTAP2 canonical order.
    case map([Pair])

    nonisolated struct Pair: Equatable, Sendable {
        let key: CBOR
        let value: CBOR
        init(_ key: CBOR, _ value: CBOR) {
            self.key = key
            self.value = value
        }
    }

    static func int(_ value: Int64) -> CBOR { value >= 0 ? .unsigned(UInt64(value)) : .negative(value) }

    var encoded: Data {
        switch self {
        case .unsigned(let value): Self.head(major: 0, value)
        case .negative(let value): Self.head(major: 1, UInt64(-1 - value))
        case .bytes(let data): Self.head(major: 2, UInt64(data.count)) + data
        case .text(let string): Self.head(major: 3, UInt64(string.utf8.count)) + Data(string.utf8)
        case .array(let items): items.reduce(Self.head(major: 4, UInt64(items.count))) { $0 + $1.encoded }
        case .map(let pairs): pairs.reduce(Self.head(major: 5, UInt64(pairs.count))) { $0 + $1.key.encoded + $1.value.encoded }
        }
    }

    private static func head(major: UInt8, _ value: UInt64) -> Data {
        let type = major << 5
        switch value {
        case 0..<24: return Data([type | UInt8(value)])
        case 24...0xff: return Data([type | 24, UInt8(value)])
        case 0x100...0xffff: return Data([type | 25]) + bigEndian(UInt16(value))
        case 0x10000...0xffff_ffff: return Data([type | 26]) + bigEndian(UInt32(value))
        default: return Data([type | 27]) + bigEndian(value)
        }
    }

    static func bigEndian<T: FixedWidthInteger>(_ value: T) -> Data {
        withUnsafeBytes(of: value.bigEndian) { Data($0) }
    }
}

/// Builds the authenticator data, attestation object and assertion signature of a software authenticator.
nonisolated enum SoftwarePasskeyAuthenticator {
    nonisolated struct Flags: OptionSet, Sendable {
        let rawValue: UInt8
        static let userPresent = Flags(rawValue: 0x01)
        static let userVerified = Flags(rawValue: 0x04)
        static let backupEligible = Flags(rawValue: 0x08)
        static let backedUp = Flags(rawValue: 0x10)
        static let attestedCredentialData = Flags(rawValue: 0x40)
    }

    /// COSE algorithm ES256 (ECDSA with P-256 and SHA-256), the only one this authenticator supports.
    static let es256: Int64 = -7
    /// The demo keys stay on this device, so the AAGUID is all zeros ("none" attestation).
    static let aaguid = Data(count: 16)

    /// rpIdHash (32) · flags (1) · signCount (4, big-endian) · attested credential data when registering.
    static func authenticatorData(relyingParty: String, flags: Flags, signCount: UInt32, attestedCredential: Data? = nil) -> Data {
        var data = Data(SHA256.hash(data: Data(relyingParty.utf8)))
        data.append(attestedCredential == nil ? flags.rawValue : flags.union(.attestedCredentialData).rawValue)
        data.append(CBOR.bigEndian(signCount))
        if let attestedCredential { data.append(attestedCredential) }
        return data
    }

    /// AAGUID · credential ID length (2, big-endian) · credential ID · COSE public key.
    static func attestedCredentialData(credentialID: Data, publicKey: P256.Signing.PublicKey) -> Data {
        aaguid + CBOR.bigEndian(UInt16(credentialID.count)) + credentialID + coseKey(publicKey).encoded
    }

    /// COSE_Key for an EC2 P-256 key: kty 2, alg -7, crv 1, x, y (CTAP2 canonical key order).
    static func coseKey(_ publicKey: P256.Signing.PublicKey) -> CBOR {
        let raw = publicKey.rawRepresentation
        return .map([
            .init(.int(1), .int(2)),
            .init(.int(3), .int(es256)),
            .init(.int(-1), .int(1)),
            .init(.int(-2), .bytes(raw.prefix(32))),
            .init(.int(-3), .bytes(raw.suffix(32))),
        ])
    }

    /// Attestation object with the "none" format: {"fmt": "none", "attStmt": {}, "authData": …}.
    static func attestationObject(authenticatorData: Data) -> Data {
        CBOR.map([
            .init(.text("fmt"), .text("none")),
            .init(.text("attStmt"), .map([])),
            .init(.text("authData"), .bytes(authenticatorData)),
        ]).encoded
    }

    /// DER-encoded ECDSA signature over authenticatorData ‖ clientDataHash.
    static func signature(privateKey: P256.Signing.PrivateKey, authenticatorData: Data, clientDataHash: Data) throws -> Data {
        try privateKey.signature(for: authenticatorData + clientDataHash).derRepresentation
    }

    static func randomCredentialID() -> Data {
        var generator = SystemRandomNumberGenerator()
        return Data((0..<16).map { _ in UInt8.random(in: .min ... .max, using: &generator) })
    }
}

/// Private keys of the demo passkeys, stored as generic passwords in the App Group keychain access group so both the
/// app (for deleting) and the extension (for signing) can reach them. They never leave this device.
nonisolated enum PasskeyKeyStore {
    static let service = "AppleToolbox.demo-passkey"

    nonisolated enum KeyError: Error, LocalizedError {
        case keychain(OSStatus)
        var errorDescription: String? {
            guard case .keychain(let status) = self else { return nil }
            return "Keychain error \(status): \(SecCopyErrorMessageString(status, nil) as String? ?? "unknown")"
        }
    }

    private static func query(_ credentialID: Data?) -> [String: Any] {
        var query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                    kSecAttrAccessGroup as String: ToolboxIdentifiers.appGroup]
        if let credentialID { query[kSecAttrAccount as String] = Base64URL.encode(credentialID) }
        #if os(macOS)
        query[kSecUseDataProtectionKeychain as String] = true
        #endif
        return query
    }

    static func save(_ key: P256.Signing.PrivateKey, credentialID: Data) throws {
        var attributes = query(credentialID)
        attributes[kSecValueData as String] = key.rawRepresentation
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeyError.keychain(status) }
    }

    static func load(credentialID: Data) throws -> P256.Signing.PrivateKey {
        var request = query(credentialID)
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { throw KeyError.keychain(status) }
        return try P256.Signing.PrivateKey(rawRepresentation: data)
    }

    /// Deletes every demo passkey key; returns the keychain status.
    @discardableResult
    static func deleteAll() -> OSStatus {
        SecItemDelete(query(nil) as CFDictionary)
    }
}
