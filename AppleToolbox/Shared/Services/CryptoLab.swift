import Foundation
#if canImport(CryptoKit)
import CryptoKit
#endif

// MARK: Choices

/// What the Crypto Lab runs (spec §40: "Generate key" promoted to a Credential / Crypto Lab).
nonisolated enum CryptoLabOperation: String, CaseIterable, Identifiable, Sendable {
    case hash, hmac, encrypt, keyAgreement, signature, hpke, keys

    var id: String { rawValue }
    var title: String {
        switch self {
        case .hash: "Hash"
        case .hmac: "HMAC"
        case .encrypt: "Encrypt / decrypt"
        case .keyAgreement: "Key agreement"
        case .signature: "Sign / verify"
        case .hpke: "HPKE seal / open"
        case .keys: "Key export / import"
        }
    }
}

nonisolated enum CryptoLabHash: String, CaseIterable, Identifiable, Sendable {
    case sha256, sha384, sha512

    var id: String { rawValue }
    var title: String {
        switch self {
        case .sha256: "SHA-256"
        case .sha384: "SHA-384"
        case .sha512: "SHA-512"
        }
    }
}

nonisolated enum CryptoLabCipher: String, CaseIterable, Identifiable, Sendable {
    case aesGCM128, aesGCM256, chaChaPoly

    var id: String { rawValue }
    var title: String {
        switch self {
        case .aesGCM128: "AES-GCM-128"
        case .aesGCM256: "AES-GCM-256"
        case .chaChaPoly: "ChaCha20-Poly1305"
        }
    }
    var keyByteCount: Int { self == .aesGCM128 ? 16 : 32 }
}

nonisolated enum CryptoLabCurve: String, CaseIterable, Identifiable, Sendable {
    case p256, p384, p521, x25519

    var id: String { rawValue }
    var title: String {
        switch self {
        case .p256: "P-256 ECDH"
        case .p384: "P-384 ECDH"
        case .p521: "P-521 ECDH"
        case .x25519: "X25519 (Curve25519)"
        }
    }
}

nonisolated enum CryptoLabSignatureAlgorithm: String, CaseIterable, Identifiable, Sendable {
    case p256, p384, p521, ed25519

    var id: String { rawValue }
    var title: String {
        switch self {
        case .p256: "P-256 ECDSA · SHA-256"
        case .p384: "P-384 ECDSA · SHA-384"
        case .p521: "P-521 ECDSA · SHA-512"
        case .ed25519: "Ed25519 (Curve25519)"
        }
    }
}

nonisolated enum CryptoLabHPKESuite: String, CaseIterable, Identifiable, Sendable {
    case p256, p384, p521, x25519, xWing

    var id: String { rawValue }
    var title: String {
        switch self {
        case .p256: "P-256 · HKDF-SHA256 · AES-GCM-256"
        case .p384: "P-384 · HKDF-SHA384 · AES-GCM-256"
        case .p521: "P-521 · HKDF-SHA512 · AES-GCM-256"
        case .x25519: "X25519 · HKDF-SHA256 · ChaCha20-Poly1305"
        case .xWing: "X-Wing (ML-KEM-768 + X25519) · AES-GCM-256"
        }
    }
}

nonisolated enum CryptoLabKeyKind: String, CaseIterable, Identifiable, Sendable {
    case p256, p384, p521, ed25519, x25519, symmetric

    var id: String { rawValue }
    var title: String {
        switch self {
        case .p256: "P-256"
        case .p384: "P-384"
        case .p521: "P-521"
        case .ed25519: "Ed25519 (Curve25519 signing)"
        case .x25519: "X25519 (Curve25519 key agreement)"
        case .symmetric: "Symmetric (256-bit)"
        }
    }
}

nonisolated enum CryptoLabKeyFormat: String, CaseIterable, Identifiable, Sendable {
    case pem, der, x963, raw

    var id: String { rawValue }
    var shortName: String { self == .pem ? "PEM" : self == .der ? "DER" : self == .x963 ? "X9.63" : "raw" }
    var title: String {
        switch self {
        case .pem: "PEM"
        case .der: "DER (hex or Base64)"
        case .x963: "X9.63 (hex or Base64)"
        case .raw: "Raw (hex or Base64)"
        }
    }
}

nonisolated enum CryptoLabKeyPart: String, CaseIterable, Identifiable, Sendable {
    case publicKey, privateKey

    var id: String { rawValue }
    var title: String { self == .publicKey ? "Public key" : "Private key" }
}

/// Everything the lab's controls produce; one value keeps the run view and the tests in step.
nonisolated struct CryptoLabRequest: Sendable {
    var operation = CryptoLabOperation.hash
    var hash = CryptoLabHash.sha256
    var cipher = CryptoLabCipher.aesGCM256
    var curve = CryptoLabCurve.p256
    var signature = CryptoLabSignatureAlgorithm.p256
    var hpkeSuite = CryptoLabHPKESuite.x25519
    var keyKind = CryptoLabKeyKind.p256
    var keyFormat = CryptoLabKeyFormat.pem
    var keyPart = CryptoLabKeyPart.publicKey
    var message = "Hello from Joris Apple Toolbox"
    var associatedData = ""
    var hmacKey = "toolbox-secret"
    var importText = ""
}

nonisolated struct CryptoLabReport: Sendable {
    let text: String
    let isError: Bool
    /// Text the lab suggests for the import field after an export (the public key in a format the importer reads).
    var importCandidate: String? = nil
    var importFormat: CryptoLabKeyFormat? = nil
    var importPart: CryptoLabKeyPart? = nil
}

// MARK: Results of the pure operations

nonisolated struct CryptoLabSealedMessage: Sendable, Equatable {
    let nonce: Data
    let ciphertext: Data
    let tag: Data
    var combined: Data { nonce + ciphertext + tag }
}

nonisolated struct CryptoLabAgreement: Sendable {
    let alicePublicKey: Data
    let bobPublicKey: Data
    let aliceSecret: Data
    let bobSecret: Data
    let aliceKey: Data
    let bobKey: Data
}

nonisolated struct CryptoLabSignatureRun: Sendable {
    let publicKey: Data
    let signature: Data
    let derSignature: Data?
    let verifies: Bool
    let tamperedMessageVerifies: Bool
    let tamperedSignatureVerifies: Bool
}

nonisolated struct CryptoLabHPKERun: Sendable {
    let recipientPublicKey: Data
    let encapsulatedKey: Data
    let ciphertext: Data
    let opened: Data
    /// What happened when a different recipient key tried to open the message (nil if it wrongly succeeded).
    let wrongRecipientError: String?
    /// What happened when one ciphertext bit was flipped (nil if it wrongly succeeded).
    let tamperedError: String?
}

nonisolated struct CryptoLabKeyRepresentation: Sendable, Equatable {
    let label: String
    let value: String
    let byteCount: Int?
    /// Importing `value` again restored the same key.
    let roundTrips: Bool
}

nonisolated struct CryptoLabKeyExport: Sendable {
    let privateRepresentations: [CryptoLabKeyRepresentation]
    let publicRepresentations: [CryptoLabKeyRepresentation]
    let note: String?
    let importCandidate: String
    let importFormat: CryptoLabKeyFormat
}

nonisolated enum CryptoLabError: LocalizedError, Equatable {
    case invalidEncoding(String)
    case unsupported(String)
    case emptyInput(String)

    var errorDescription: String? {
        switch self {
        case .invalidEncoding(let text), .unsupported(let text), .emptyInput(let text): text
        }
    }
}

// MARK: Lab

/// CryptoKit operations on user data. Every value shown comes from the real CryptoKit call; nothing is simulated.
nonisolated enum CryptoLab {
    static let keyAgreementInfo = Data("Apple Toolbox key agreement".utf8)
    static let hpkeInfo = Data("Apple Toolbox HPKE".utf8)

    // MARK: Encoding helpers

    static func hex<Bytes: Sequence>(_ bytes: Bytes) -> String where Bytes.Element == UInt8 {
        bytes.map { String(format: "%02x", $0) }.joined()
    }

    /// Accepts hex (spaces and colons allowed) or standard Base64, which is how keys are usually pasted.
    static func bytes(fromHexOrBase64 text: String) -> Data? {
        let compact = text.filter { !$0.isWhitespace && $0 != ":" }
        guard !compact.isEmpty else { return nil }
        if compact.count.isMultiple(of: 2), compact.allSatisfy(\.isHexDigit) {
            var data = Data(capacity: compact.count / 2)
            var index = compact.startIndex
            while index < compact.endIndex {
                let next = compact.index(index, offsetBy: 2)
                guard let byte = UInt8(compact[index..<next], radix: 16) else { return nil }
                data.append(byte)
                index = next
            }
            return data
        }
        return Data(base64Encoded: compact)
    }

    /// Flips the lowest bit of the first byte; an empty value gets one byte so the tamper test still changes it.
    static func tampered(_ data: Data) -> Data {
        guard let first = data.first else { return Data([0x01]) }
        var copy = data
        copy[copy.startIndex] = first ^ 0x01
        return copy
    }

    static func preview(_ data: Data, limit: Int = 48) -> String {
        data.count > limit ? hex(data.prefix(limit)) + "… (\(data.count) bytes)" : hex(data)
    }

    static func fingerprint(_ data: Data) -> String {
        #if canImport(CryptoKit)
        let digest = hex(SHA256.hash(data: data))
        return stride(from: 0, to: 32, by: 8).map { String(digest.dropFirst($0).prefix(8)) }.joined(separator: " ") + " …"
        #else
        return "unavailable"
        #endif
    }

    static func describe(_ error: Error) -> String {
        if let error = error as? CryptoLabError { return error.errorDescription ?? "\(error)" }
        let nsError = error as NSError
        if nsError.domain == NSOSStatusErrorDomain { return "OSStatus \(nsError.code): \(nsError.localizedDescription)" }
        return "\(String(describing: type(of: error))).\(error)"
    }

    #if canImport(CryptoKit)

    // MARK: Hashing and MACs

    static func digest(_ data: Data, _ hash: CryptoLabHash) -> Data {
        switch hash {
        case .sha256: Data(SHA256.hash(data: data))
        case .sha384: Data(SHA384.hash(data: data))
        case .sha512: Data(SHA512.hash(data: data))
        }
    }

    static func hmac(_ data: Data, key: Data, _ hash: CryptoLabHash) -> Data {
        let key = SymmetricKey(data: key)
        return switch hash {
        case .sha256: Data(HMAC<SHA256>.authenticationCode(for: data, using: key))
        case .sha384: Data(HMAC<SHA384>.authenticationCode(for: data, using: key))
        case .sha512: Data(HMAC<SHA512>.authenticationCode(for: data, using: key))
        }
    }

    /// Constant-time check through CryptoKit's own validation API.
    static func isValidHMAC(_ mac: Data, for data: Data, key: Data, _ hash: CryptoLabHash) -> Bool {
        let key = SymmetricKey(data: key)
        return switch hash {
        case .sha256: HMAC<SHA256>.isValidAuthenticationCode(mac, authenticating: data, using: key)
        case .sha384: HMAC<SHA384>.isValidAuthenticationCode(mac, authenticating: data, using: key)
        case .sha512: HMAC<SHA512>.isValidAuthenticationCode(mac, authenticating: data, using: key)
        }
    }

    static func hkdf(inputKeyMaterial: Data, salt: Data, info: Data, outputByteCount: Int, _ hash: CryptoLabHash) -> Data {
        let ikm = SymmetricKey(data: inputKeyMaterial)
        let key = switch hash {
        case .sha256: HKDF<SHA256>.deriveKey(inputKeyMaterial: ikm, salt: salt, info: info, outputByteCount: outputByteCount)
        case .sha384: HKDF<SHA384>.deriveKey(inputKeyMaterial: ikm, salt: salt, info: info, outputByteCount: outputByteCount)
        case .sha512: HKDF<SHA512>.deriveKey(inputKeyMaterial: ikm, salt: salt, info: info, outputByteCount: outputByteCount)
        }
        return data(of: key)
    }

    // MARK: Symmetric encryption

    static func randomKey(byteCount: Int) -> Data {
        data(of: SymmetricKey(size: SymmetricKeySize(bitCount: byteCount * 8)))
    }

    /// Seals with a random nonce unless one is given (fixed nonces are only for known-answer tests).
    static func seal(_ plaintext: Data, key: Data, nonce: Data? = nil, associatedData: Data, _ cipher: CryptoLabCipher) throws -> CryptoLabSealedMessage {
        let key = SymmetricKey(data: key)
        switch cipher {
        case .aesGCM128, .aesGCM256:
            let box = try AES.GCM.seal(plaintext, using: key, nonce: try nonce.map { try AES.GCM.Nonce(data: $0) }, authenticating: associatedData)
            return CryptoLabSealedMessage(nonce: Data(box.nonce), ciphertext: box.ciphertext, tag: box.tag)
        case .chaChaPoly:
            let box = try ChaChaPoly.seal(plaintext, using: key, nonce: try nonce.map { try ChaChaPoly.Nonce(data: $0) }, authenticating: associatedData)
            return CryptoLabSealedMessage(nonce: Data(box.nonce), ciphertext: box.ciphertext, tag: box.tag)
        }
    }

    static func open(_ sealed: CryptoLabSealedMessage, key: Data, associatedData: Data, _ cipher: CryptoLabCipher) throws -> Data {
        let key = SymmetricKey(data: key)
        switch cipher {
        case .aesGCM128, .aesGCM256:
            let box = try AES.GCM.SealedBox(nonce: AES.GCM.Nonce(data: sealed.nonce), ciphertext: sealed.ciphertext, tag: sealed.tag)
            return try AES.GCM.open(box, using: key, authenticating: associatedData)
        case .chaChaPoly:
            let box = try ChaChaPoly.SealedBox(nonce: ChaChaPoly.Nonce(data: sealed.nonce), ciphertext: sealed.ciphertext, tag: sealed.tag)
            return try ChaChaPoly.open(box, using: key, authenticating: associatedData)
        }
    }

    // MARK: Key agreement

    /// Two fresh key pairs agree on a secret from both sides, and HKDF turns each side's secret into a symmetric key.
    static func agree(_ curve: CryptoLabCurve, hash: CryptoLabHash, salt: Data, info: Data = keyAgreementInfo, outputByteCount: Int = 32) throws -> CryptoLabAgreement {
        func run<Key: DiffieHellmanKeyAgreement>(_ alice: Key, _ bob: Key, publicBytes: (Key.PublicKey) -> Data) throws -> CryptoLabAgreement {
            let aliceSecret = try alice.sharedSecretFromKeyAgreement(with: bob.publicKey)
            let bobSecret = try bob.sharedSecretFromKeyAgreement(with: alice.publicKey)
            return CryptoLabAgreement(
                alicePublicKey: publicBytes(alice.publicKey), bobPublicKey: publicBytes(bob.publicKey),
                aliceSecret: aliceSecret.withUnsafeBytes { Data($0) }, bobSecret: bobSecret.withUnsafeBytes { Data($0) },
                aliceKey: derive(aliceSecret, hash, salt: salt, info: info, outputByteCount: outputByteCount),
                bobKey: derive(bobSecret, hash, salt: salt, info: info, outputByteCount: outputByteCount))
        }
        return switch curve {
        case .p256: try run(P256.KeyAgreement.PrivateKey(), P256.KeyAgreement.PrivateKey()) { $0.x963Representation }
        case .p384: try run(P384.KeyAgreement.PrivateKey(), P384.KeyAgreement.PrivateKey()) { $0.x963Representation }
        case .p521: try run(P521.KeyAgreement.PrivateKey(), P521.KeyAgreement.PrivateKey()) { $0.x963Representation }
        case .x25519: try run(Curve25519.KeyAgreement.PrivateKey(), Curve25519.KeyAgreement.PrivateKey()) { $0.rawRepresentation }
        }
    }

    static func x25519SharedSecret(privateKey: Data, peerPublicKey: Data) throws -> Data {
        let key = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: privateKey)
        let peer = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: peerPublicKey)
        return try key.sharedSecretFromKeyAgreement(with: peer).withUnsafeBytes { Data($0) }
    }

    private static func derive(_ secret: SharedSecret, _ hash: CryptoLabHash, salt: Data, info: Data, outputByteCount: Int) -> Data {
        let key = switch hash {
        case .sha256: secret.hkdfDerivedSymmetricKey(using: SHA256.self, salt: salt, sharedInfo: info, outputByteCount: outputByteCount)
        case .sha384: secret.hkdfDerivedSymmetricKey(using: SHA384.self, salt: salt, sharedInfo: info, outputByteCount: outputByteCount)
        case .sha512: secret.hkdfDerivedSymmetricKey(using: SHA512.self, salt: salt, sharedInfo: info, outputByteCount: outputByteCount)
        }
        return data(of: key)
    }

    // MARK: Signatures

    /// Signs with a new key, then verifies the original, a message with one flipped bit and a signature with one flipped bit.
    static func signatureRun(_ algorithm: CryptoLabSignatureAlgorithm, message: Data) throws -> CryptoLabSignatureRun {
        func run(publicKey: Data, signature: Data, der: Data?, verify: (Data, Data) -> Bool) -> CryptoLabSignatureRun {
            CryptoLabSignatureRun(publicKey: publicKey, signature: signature, derSignature: der,
                verifies: verify(signature, message),
                tamperedMessageVerifies: verify(signature, tampered(message)),
                tamperedSignatureVerifies: verify(tampered(signature), message))
        }
        switch algorithm {
        case .p256:
            let key = P256.Signing.PrivateKey()
            let signature = try key.signature(for: message)
            return run(publicKey: key.publicKey.x963Representation, signature: signature.rawRepresentation, der: signature.derRepresentation) { raw, data in
                (try? P256.Signing.ECDSASignature(rawRepresentation: raw)).map { key.publicKey.isValidSignature($0, for: data) } ?? false
            }
        case .p384:
            let key = P384.Signing.PrivateKey()
            let signature = try key.signature(for: message)
            return run(publicKey: key.publicKey.x963Representation, signature: signature.rawRepresentation, der: signature.derRepresentation) { raw, data in
                (try? P384.Signing.ECDSASignature(rawRepresentation: raw)).map { key.publicKey.isValidSignature($0, for: data) } ?? false
            }
        case .p521:
            let key = P521.Signing.PrivateKey()
            let signature = try key.signature(for: message)
            return run(publicKey: key.publicKey.x963Representation, signature: signature.rawRepresentation, der: signature.derRepresentation) { raw, data in
                (try? P521.Signing.ECDSASignature(rawRepresentation: raw)).map { key.publicKey.isValidSignature($0, for: data) } ?? false
            }
        case .ed25519:
            let key = Curve25519.Signing.PrivateKey()
            let signature = try key.signature(for: message)
            return run(publicKey: key.publicKey.rawRepresentation, signature: signature, der: nil) { raw, data in
                key.publicKey.isValidSignature(raw, for: data)
            }
        }
    }

    static func isValidEd25519Signature(_ signature: Data, for message: Data, publicKey: Data) throws -> Bool {
        try Curve25519.Signing.PublicKey(rawRepresentation: publicKey).isValidSignature(signature, for: message)
    }

    static func ed25519PublicKey(forPrivateKey privateKey: Data) throws -> Data {
        try Curve25519.Signing.PrivateKey(rawRepresentation: privateKey).publicKey.rawRepresentation
    }

    // MARK: HPKE (RFC 9180, base mode)

    static func hpkeRun(_ suite: CryptoLabHPKESuite, message: Data, info: Data = hpkeInfo, associatedData: Data) throws -> CryptoLabHPKERun {
        switch suite {
        case .p256: try hpke(P256.KeyAgreement.PrivateKey.self, .P256_SHA256_AES_GCM_256, kem: .P256_HKDF_SHA256, message, info, associatedData)
        case .p384: try hpke(P384.KeyAgreement.PrivateKey.self, .P384_SHA384_AES_GCM_256, kem: .P384_HKDF_SHA384, message, info, associatedData)
        case .p521: try hpke(P521.KeyAgreement.PrivateKey.self, .P521_SHA512_AES_GCM_256, kem: .P521_HKDF_SHA512, message, info, associatedData)
        case .x25519: try hpke(Curve25519.KeyAgreement.PrivateKey.self, .Curve25519_SHA256_ChachaPoly, kem: .Curve25519_HKDF_SHA256, message, info, associatedData)
        case .xWing: try hpkeKEM(XWingMLKEM768X25519.PrivateKey.self, .XWingMLKEM768X25519_SHA256_AES_GCM_256, kem: .XWingMLKEM768X25519, message, info, associatedData)
        }
    }

    private static func hpke<Key: HPKEDiffieHellmanPrivateKeyGeneration>(_ type: Key.Type, _ suite: HPKE.Ciphersuite, kem: HPKE.KEM, _ message: Data, _ info: Data, _ aad: Data) throws -> CryptoLabHPKERun {
        let recipientKey = Key()
        var sender = try HPKE.Sender(recipientKey: recipientKey.publicKey, ciphersuite: suite, info: info)
        let ciphertext = try sender.seal(message, authenticating: aad)
        var recipient = try HPKE.Recipient(privateKey: recipientKey, ciphersuite: suite, info: info, encapsulatedKey: sender.encapsulatedKey)
        let opened = try recipient.open(ciphertext, authenticating: aad)
        let wrongRecipientError = rejection {
            var other = try HPKE.Recipient(privateKey: Key(), ciphersuite: suite, info: info, encapsulatedKey: sender.encapsulatedKey)
            _ = try other.open(ciphertext, authenticating: aad)
        }
        let tamperedError = rejection {
            var fresh = try HPKE.Recipient(privateKey: recipientKey, ciphersuite: suite, info: info, encapsulatedKey: sender.encapsulatedKey)
            _ = try fresh.open(tampered(ciphertext), authenticating: aad)
        }
        return CryptoLabHPKERun(recipientPublicKey: try recipientKey.publicKey.hpkeRepresentation(kem: kem), encapsulatedKey: sender.encapsulatedKey,
                                ciphertext: ciphertext, opened: opened, wrongRecipientError: wrongRecipientError, tamperedError: tamperedError)
    }

    private static func hpkeKEM<Key: HPKEKEMPrivateKeyGeneration>(_ type: Key.Type, _ suite: HPKE.Ciphersuite, kem: HPKE.KEM, _ message: Data, _ info: Data, _ aad: Data) throws -> CryptoLabHPKERun {
        let recipientKey = try Key()
        var sender = try HPKE.Sender(recipientKey: recipientKey.publicKey, ciphersuite: suite, info: info)
        let ciphertext = try sender.seal(message, authenticating: aad)
        var recipient = try HPKE.Recipient(privateKey: recipientKey, ciphersuite: suite, info: info, encapsulatedKey: sender.encapsulatedKey)
        let opened = try recipient.open(ciphertext, authenticating: aad)
        let wrongRecipientError = rejection {
            var other = try HPKE.Recipient(privateKey: try Key(), ciphersuite: suite, info: info, encapsulatedKey: sender.encapsulatedKey)
            _ = try other.open(ciphertext, authenticating: aad)
        }
        let tamperedError = rejection {
            var fresh = try HPKE.Recipient(privateKey: recipientKey, ciphersuite: suite, info: info, encapsulatedKey: sender.encapsulatedKey)
            _ = try fresh.open(tampered(ciphertext), authenticating: aad)
        }
        return CryptoLabHPKERun(recipientPublicKey: try recipientKey.publicKey.hpkeRepresentation(kem: kem), encapsulatedKey: sender.encapsulatedKey,
                                ciphertext: ciphertext, opened: opened, wrongRecipientError: wrongRecipientError, tamperedError: tamperedError)
    }

    /// Runs an operation that must fail and returns the error it failed with, or nil when it unexpectedly succeeded.
    private static func rejection(_ operation: () throws -> Void) -> String? {
        do {
            try operation()
            return nil
        } catch {
            return describe(error)
        }
    }

    // MARK: Key generation, export and import

    /// Generates a key of the chosen kind and exports every representation CryptoKit offers, re-importing each one.
    static func exportKey(_ kind: CryptoLabKeyKind) -> CryptoLabKeyExport {
        switch kind {
        case .p256: return nistExport(P256.Signing.PrivateKey.self)
        case .p384: return nistExport(P384.Signing.PrivateKey.self)
        case .p521: return nistExport(P521.Signing.PrivateKey.self)
        case .ed25519:
            let key = Curve25519.Signing.PrivateKey()
            let publicRaw = key.publicKey.rawRepresentation
            return CryptoLabKeyExport(
                privateRepresentations: [representation("raw", key.rawRepresentation, expected: publicRaw) { try Curve25519.Signing.PrivateKey(rawRepresentation: $0).publicKey.rawRepresentation }],
                publicRepresentations: [representation("raw", publicRaw, expected: publicRaw) { try Curve25519.Signing.PublicKey(rawRepresentation: $0).rawRepresentation }],
                note: curve25519Note, importCandidate: hex(publicRaw), importFormat: .raw)
        case .x25519:
            let key = Curve25519.KeyAgreement.PrivateKey()
            let publicRaw = key.publicKey.rawRepresentation
            return CryptoLabKeyExport(
                privateRepresentations: [representation("raw", key.rawRepresentation, expected: publicRaw) { try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: $0).publicKey.rawRepresentation }],
                publicRepresentations: [representation("raw", publicRaw, expected: publicRaw) { try Curve25519.KeyAgreement.PublicKey(rawRepresentation: $0).rawRepresentation }],
                note: curve25519Note, importCandidate: hex(publicRaw), importFormat: .raw)
        case .symmetric:
            let raw = randomKey(byteCount: 32)
            return CryptoLabKeyExport(
                privateRepresentations: [representation("raw", raw, expected: raw) { data(of: SymmetricKey(data: $0)) }],
                publicRepresentations: [],
                note: "A symmetric key is just its bytes: no public part, and CryptoKit defines no PEM or DER wrapping for it.",
                importCandidate: hex(raw), importFormat: .raw)
        }
    }

    private static let curve25519Note = "CryptoKit represents Curve25519 keys only as 32 raw bytes; it offers no X9.63, DER or PEM form for them."

    private static func nistExport<Key: CryptoLabNISTPrivateKey>(_ type: Key.Type) -> CryptoLabKeyExport {
        let key = Key(compactRepresentable: true)
        let expected = key.publicKey.x963Representation
        func privateKey(_ label: String, _ bytes: Data, base64: Bool = false, _ reimport: (Data) throws -> Key) -> CryptoLabKeyRepresentation {
            representation(label, bytes, base64: base64, expected: expected) { try reimport($0).publicKey.x963Representation }
        }
        func publicKey(_ label: String, _ bytes: Data, base64: Bool = false, _ reimport: (Data) throws -> Key.PublicKey) -> CryptoLabKeyRepresentation {
            representation(label, bytes, base64: base64, expected: expected) { try reimport($0).x963Representation }
        }
        let publicPEM = key.publicKey.pemRepresentation
        return CryptoLabKeyExport(
            privateRepresentations: [
                privateKey("raw", key.rawRepresentation) { try Key(rawRepresentation: $0) },
                privateKey("X9.63", key.x963Representation) { try Key(x963Representation: $0) },
                privateKey("DER (PKCS #8)", key.derRepresentation, base64: true) { try Key(derRepresentation: $0) },
                CryptoLabKeyRepresentation(label: "PEM", value: key.pemRepresentation, byteCount: nil,
                                           roundTrips: (try? Key(pemRepresentation: key.pemRepresentation).publicKey.x963Representation) == expected),
            ],
            publicRepresentations: [
                publicKey("raw", key.publicKey.rawRepresentation) { try Key.PublicKey(rawRepresentation: $0) },
                publicKey("X9.63", key.publicKey.x963Representation) { try Key.PublicKey(x963Representation: $0) },
                publicKey("compressed", key.publicKey.compressedRepresentation) { try Key.PublicKey(compressedRepresentation: $0) },
                publicKey("DER (SubjectPublicKeyInfo)", key.publicKey.derRepresentation, base64: true) { try Key.PublicKey(derRepresentation: $0) },
                CryptoLabKeyRepresentation(label: "PEM", value: publicPEM, byteCount: nil,
                                           roundTrips: (try? Key.PublicKey(pemRepresentation: publicPEM).x963Representation) == expected),
            ],
            note: nil, importCandidate: publicPEM, importFormat: .pem)
    }

    /// One exported representation; the round trip imports `bytes` again and compares the restored public key with `expected`.
    private static func representation(_ label: String, _ bytes: Data, base64: Bool = false, expected: Data, reimport: (Data) throws -> Data) -> CryptoLabKeyRepresentation {
        CryptoLabKeyRepresentation(label: label, value: base64 ? bytes.base64EncodedString() : hex(bytes), byteCount: bytes.count,
                                   roundTrips: (try? reimport(bytes)) == expected)
    }

    /// Parses a pasted key and returns what CryptoKit restored: the public key bytes (X9.63 for P curves, raw otherwise).
    static func importKey(_ text: String, kind: CryptoLabKeyKind, format: CryptoLabKeyFormat, part: CryptoLabKeyPart) throws -> Data {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw CryptoLabError.emptyInput("Paste a key first (PEM text, or hex/Base64 bytes).") }
        switch kind {
        case .p256: return try nistImport(P256.Signing.PrivateKey.self, trimmed, format: format, part: part)
        case .p384: return try nistImport(P384.Signing.PrivateKey.self, trimmed, format: format, part: part)
        case .p521: return try nistImport(P521.Signing.PrivateKey.self, trimmed, format: format, part: part)
        case .ed25519, .x25519, .symmetric:
            guard format == .raw else { throw CryptoLabError.unsupported("CryptoKit offers no \(format.shortName) representation for \(kind.title) keys. Use “Raw”.") }
            let bytes = try decode(trimmed)
            switch (kind, part) {
            case (.ed25519, .publicKey): return try Curve25519.Signing.PublicKey(rawRepresentation: bytes).rawRepresentation
            case (.ed25519, .privateKey): return try Curve25519.Signing.PrivateKey(rawRepresentation: bytes).publicKey.rawRepresentation
            case (.x25519, .publicKey): return try Curve25519.KeyAgreement.PublicKey(rawRepresentation: bytes).rawRepresentation
            case (.x25519, .privateKey): return try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: bytes).publicKey.rawRepresentation
            case (_, .publicKey): throw CryptoLabError.unsupported("A symmetric key has no public part. Choose “Private key”.")
            case (_, .privateKey):
                guard [16, 24, 32].contains(bytes.count) else { throw CryptoLabError.invalidEncoding("\(bytes.count) bytes is not an AES key size (16, 24 or 32 bytes).") }
                return data(of: SymmetricKey(data: bytes))
            }
        }
    }

    private static func nistImport<Key: CryptoLabNISTPrivateKey>(_ type: Key.Type, _ text: String, format: CryptoLabKeyFormat, part: CryptoLabKeyPart) throws -> Data {
        if format == .pem {
            return part == .publicKey ? try Key.PublicKey(pemRepresentation: text).x963Representation : try Key(pemRepresentation: text).publicKey.x963Representation
        }
        let bytes = try decode(text)
        switch (format, part) {
        case (.der, .publicKey): return try Key.PublicKey(derRepresentation: bytes).x963Representation
        case (.der, .privateKey): return try Key(derRepresentation: bytes).publicKey.x963Representation
        case (.x963, .publicKey): return try Key.PublicKey(x963Representation: bytes).x963Representation
        case (.x963, .privateKey): return try Key(x963Representation: bytes).publicKey.x963Representation
        case (_, .publicKey): return try Key.PublicKey(rawRepresentation: bytes).x963Representation
        case (_, .privateKey): return try Key(rawRepresentation: bytes).publicKey.x963Representation
        }
    }

    private static func decode(_ text: String) throws -> Data {
        guard let bytes = bytes(fromHexOrBase64: text) else { throw CryptoLabError.invalidEncoding("The text is neither hex nor Base64.") }
        return bytes
    }

    private static func data(of key: SymmetricKey) -> Data {
        key.withUnsafeBytes { Data($0) }
    }
    #endif
}

#if canImport(CryptoKit)
/// The key API CryptoKit repeats for P-256, P-384 and P-521, so export and import are written once for all three curves.
nonisolated protocol CryptoLabNISTPublicKey {
    init<Bytes: ContiguousBytes>(rawRepresentation: Bytes) throws
    init<Bytes: ContiguousBytes>(x963Representation: Bytes) throws
    init<Bytes: ContiguousBytes>(compressedRepresentation: Bytes) throws
    init<Bytes: RandomAccessCollection>(derRepresentation: Bytes) throws where Bytes.Element == UInt8
    init(pemRepresentation: String) throws
    var rawRepresentation: Data { get }
    var x963Representation: Data { get }
    var compressedRepresentation: Data { get }
    var derRepresentation: Data { get }
    var pemRepresentation: String { get }
}

nonisolated protocol CryptoLabNISTPrivateKey {
    associatedtype PublicKey: CryptoLabNISTPublicKey
    init(compactRepresentable: Bool)
    init<Bytes: ContiguousBytes>(rawRepresentation: Bytes) throws
    init<Bytes: ContiguousBytes>(x963Representation: Bytes) throws
    init<Bytes: RandomAccessCollection>(derRepresentation: Bytes) throws where Bytes.Element == UInt8
    init(pemRepresentation: String) throws
    var publicKey: PublicKey { get }
    var rawRepresentation: Data { get }
    var x963Representation: Data { get }
    var derRepresentation: Data { get }
    var pemRepresentation: String { get }
}

nonisolated extension P256.Signing.PublicKey: CryptoLabNISTPublicKey {}
nonisolated extension P384.Signing.PublicKey: CryptoLabNISTPublicKey {}
nonisolated extension P521.Signing.PublicKey: CryptoLabNISTPublicKey {}
nonisolated extension P256.Signing.PrivateKey: CryptoLabNISTPrivateKey {}
nonisolated extension P384.Signing.PrivateKey: CryptoLabNISTPrivateKey {}
nonisolated extension P521.Signing.PrivateKey: CryptoLabNISTPrivateKey {}
#endif

// MARK: Reports

nonisolated extension CryptoLab {
    /// Runs the selected operation on the request's data and renders the live CryptoKit output.
    static func run(_ request: CryptoLabRequest) -> CryptoLabReport {
        #if canImport(CryptoKit)
        let message = Data(request.message.utf8)
        let aad = Data(request.associatedData.utf8)
        do {
            switch request.operation {
            case .hash: return hashReport(message, request)
            case .hmac: return try hmacReport(message, request)
            case .encrypt: return try encryptReport(message, aad, request)
            case .keyAgreement: return try agreementReport(message, request)
            case .signature: return try signatureReport(message, request)
            case .hpke: return try hpkeReport(message, aad, request)
            case .keys: return exportReport(request.keyKind)
            }
        } catch {
            return CryptoLabReport(text: "\(request.operation.title) failed: \(describe(error))", isError: true)
        }
        #else
        return CryptoLabReport(text: "CryptoKit is not available on this platform.", isError: true)
        #endif
    }

    static func importReport(_ request: CryptoLabRequest) -> CryptoLabReport {
        #if canImport(CryptoKit)
        do {
            let publicKey = try importKey(request.importText, kind: request.keyKind, format: request.keyFormat, part: request.keyPart)
            let name = request.keyKind == .symmetric ? "Key bytes" : [CryptoLabKeyKind.p256, .p384, .p521].contains(request.keyKind) ? "Public key (X9.63)" : "Public key (raw)"
            return CryptoLabReport(text: [
                "Imported \(request.keyKind.title) \(request.keyPart.title.lowercased()) from \(request.keyFormat.title)",
                "\(name), \(publicKey.count) bytes: \(preview(publicKey, limit: 72))",
                "SHA-256 fingerprint: \(fingerprint(publicKey))",
                request.keyPart == .privateKey && request.keyKind != .symmetric ? "The public key was derived from the imported private key." : nil,
            ].compactMap { $0 }.joined(separator: "\n"), isError: false)
        } catch {
            return CryptoLabReport(text: "Import failed: \(describe(error))", isError: true)
        }
        #else
        return CryptoLabReport(text: "CryptoKit is not available on this platform.", isError: true)
        #endif
    }

    #if canImport(CryptoKit)
    private static func quoted(_ data: Data) -> String {
        data.isEmpty ? "none" : "“\(String(decoding: data, as: UTF8.self))” (\(data.count) bytes)"
    }

    private static func verdict(_ valid: Bool, expected: Bool) -> String {
        (valid ? "valid" : "invalid") + (valid == expected ? " ✓" : " ✗ unexpected")
    }

    private static func hashReport(_ message: Data, _ request: CryptoLabRequest) -> CryptoLabReport {
        let result = digest(message, request.hash)
        return CryptoLabReport(text: """
        \(request.hash.title) of \(message.count) UTF-8 bytes
        Digest (\(result.count) bytes): \(hex(result))
        Base64: \(result.base64EncodedString())
        Changing one input bit gives: \(preview(digest(tampered(message), request.hash), limit: 16))
        """, isError: false)
    }

    private static func hmacReport(_ message: Data, _ request: CryptoLabRequest) throws -> CryptoLabReport {
        let key = Data(request.hmacKey.utf8)
        guard !key.isEmpty else { throw CryptoLabError.emptyInput("Enter an HMAC key.") }
        let mac = hmac(message, key: key, request.hash)
        return CryptoLabReport(text: """
        HMAC-\(request.hash.title) · key: \(key.count) UTF-8 bytes · message: \(message.count) bytes
        MAC (\(mac.count) bytes): \(hex(mac))
        Verify with the same key: \(verdict(isValidHMAC(mac, for: message, key: key, request.hash), expected: true))
        Verify with one message bit flipped: \(verdict(isValidHMAC(mac, for: tampered(message), key: key, request.hash), expected: false))
        Verify with a different key: \(verdict(isValidHMAC(mac, for: message, key: tampered(key), request.hash), expected: false))
        """, isError: false)
    }

    private static func encryptReport(_ message: Data, _ aad: Data, _ request: CryptoLabRequest) throws -> CryptoLabReport {
        let cipher = request.cipher
        let key = randomKey(byteCount: cipher.keyByteCount)
        let sealed = try seal(message, key: key, associatedData: aad, cipher)
        let opened = try open(sealed, key: key, associatedData: aad, cipher)
        let tamperedCiphertext = CryptoLabSealedMessage(nonce: sealed.nonce, ciphertext: tampered(sealed.ciphertext), tag: sealed.tag)
        let tamperResult = rejectionText { _ = try open(tamperedCiphertext, key: key, associatedData: aad, cipher) }
        let aadResult = rejectionText { _ = try open(sealed, key: key, associatedData: tampered(aad), cipher) }
        return CryptoLabReport(text: """
        \(cipher.title) · new random \(key.count * 8)-bit key
        Key: \(hex(key))
        Nonce (\(sealed.nonce.count) bytes, random): \(hex(sealed.nonce))
        Ciphertext (\(sealed.ciphertext.count) bytes): \(preview(sealed.ciphertext))
        Tag (\(sealed.tag.count) bytes): \(hex(sealed.tag))
        Associated data (authenticated, not encrypted): \(quoted(aad))
        Combined nonce ‖ ciphertext ‖ tag (\(sealed.combined.count) bytes): \(sealed.combined.base64EncodedString())
        Decrypted: “\(String(decoding: opened, as: UTF8.self))” · round trip \(opened == message ? "matches ✓" : "differs ✗")
        One ciphertext bit flipped: \(tamperResult)
        Different associated data: \(aadResult)
        """, isError: opened != message)
    }

    private static func agreementReport(_ message: Data, _ request: CryptoLabRequest) throws -> CryptoLabReport {
        let salt = randomKey(byteCount: 32)
        let agreement = try agree(request.curve, hash: request.hash, salt: salt)
        let sealed = try seal(message, key: agreement.aliceKey, associatedData: Data(), .aesGCM256)
        let opened = try open(sealed, key: agreement.bobKey, associatedData: Data(), .aesGCM256)
        let publicName = request.curve == .x25519 ? "raw" : "X9.63"
        let keysMatch = agreement.aliceKey == agreement.bobKey
        return CryptoLabReport(text: """
        \(request.curve.title) between two new key pairs, Alice and Bob
        Alice public key (\(publicName), \(agreement.alicePublicKey.count) bytes): \(preview(agreement.alicePublicKey))
        Bob public key (\(publicName), \(agreement.bobPublicKey.count) bytes): \(preview(agreement.bobPublicKey))
        Shared secret, Alice's side (\(agreement.aliceSecret.count) bytes): \(fingerprint(agreement.aliceSecret))
        Shared secret, Bob's side (\(agreement.bobSecret.count) bytes): \(fingerprint(agreement.bobSecret))
        HKDF-\(request.hash.title) · salt: 32 random bytes (\(hex(salt.prefix(8)))…) · info: “\(String(decoding: keyAgreementInfo, as: UTF8.self))” · 32 bytes
        Alice's derived key: \(hex(agreement.aliceKey))
        Bob's derived key:   \(hex(agreement.bobKey))
        Derived keys match: \(keysMatch ? "yes ✓" : "no ✗")
        AES-GCM sealed with Alice's key, opened with Bob's: “\(String(decoding: opened, as: UTF8.self))” \(opened == message ? "✓" : "✗")
        Only the public keys, salt and info cross the wire; the raw shared secret is never used as a key directly.
        """, isError: !keysMatch || opened != message)
    }

    private static func signatureReport(_ message: Data, _ request: CryptoLabRequest) throws -> CryptoLabReport {
        let run = try signatureRun(request.signature, message: message)
        let publicName = request.signature == .ed25519 ? "raw" : "X9.63"
        let valid = run.verifies && !run.tamperedMessageVerifies && !run.tamperedSignatureVerifies
        return CryptoLabReport(text: [
            "\(request.signature.title) · new key pair · message: \(message.count) bytes",
            "Public key (\(publicName), \(run.publicKey.count) bytes): \(preview(run.publicKey))",
            "Signature (\(request.signature == .ed25519 ? "raw" : "raw r ‖ s"), \(run.signature.count) bytes): \(preview(run.signature, limit: 72))",
            run.derSignature.map { "Signature (DER, \($0.count) bytes): \($0.base64EncodedString())" },
            "Verify original message: \(verdict(run.verifies, expected: true))",
            "Verify with one message bit flipped: \(verdict(run.tamperedMessageVerifies, expected: false))",
            "Verify with one signature bit flipped: \(verdict(run.tamperedSignatureVerifies, expected: false))",
            "CryptoKit signs with fresh randomness, so signing the same message again gives different signature bytes.",
        ].compactMap { $0 }.joined(separator: "\n"), isError: !valid)
    }

    private static func hpkeReport(_ message: Data, _ aad: Data, _ request: CryptoLabRequest) throws -> CryptoLabReport {
        let run = try hpkeRun(request.hpkeSuite, message: message, associatedData: aad)
        return CryptoLabReport(text: """
        HPKE base mode (RFC 9180) · \(request.hpkeSuite.title)
        Recipient public key (\(run.recipientPublicKey.count) bytes): \(preview(run.recipientPublicKey))
        Encapsulated key sent with the message (\(run.encapsulatedKey.count) bytes): \(preview(run.encapsulatedKey))
        Info: “\(String(decoding: hpkeInfo, as: UTF8.self))” · associated data: \(quoted(aad))
        Ciphertext incl. 16-byte tag (\(run.ciphertext.count) bytes): \(preview(run.ciphertext))
        Recipient opened: “\(String(decoding: run.opened, as: UTF8.self))” \(run.opened == message ? "✓" : "✗")
        Another recipient key: \(run.wrongRecipientError.map { "rejected ✓ (\($0))" } ?? "opened ✗ unexpected")
        One ciphertext bit flipped: \(run.tamperedError.map { "rejected ✓ (\($0))" } ?? "opened ✗ unexpected")
        """, isError: run.opened != message || run.wrongRecipientError == nil || run.tamperedError == nil)
    }

    private static func exportReport(_ kind: CryptoLabKeyKind) -> CryptoLabReport {
        let export = exportKey(kind)
        func lines(_ title: String, _ reps: [CryptoLabKeyRepresentation]) -> [String] {
            guard !reps.isEmpty else { return [] }
            return [title] + reps.map { rep in
                let size = rep.byteCount.map { " (\($0) bytes)" } ?? ""
                let check = rep.roundTrips ? "re-import ✓" : "re-import ✗"
                return rep.label == "PEM" ? "  PEM · \(check)\n\(rep.value)" : "  \(rep.label)\(size) · \(check): \(rep.value)"
            }
        }
        let allRoundTrip = (export.privateRepresentations + export.publicRepresentations).allSatisfy(\.roundTrips)
        let text = (["New \(kind.title) key generated in software by CryptoKit"]
            + lines("Private key", export.privateRepresentations)
            + lines("Public key", export.publicRepresentations)
            + [export.note, "Every representation was imported again and restored the same key: \(allRoundTrip ? "yes ✓" : "no ✗")",
               "The \(export.importFormat == .pem ? "public-key PEM" : "raw key") is now in the import field; change it or paste your own key to try the importer."].compactMap { $0 })
            .joined(separator: "\n")
        return CryptoLabReport(text: text, isError: !allRoundTrip, importCandidate: export.importCandidate,
                               importFormat: export.importFormat, importPart: kind == .symmetric ? .privateKey : .publicKey)
    }

    private static func rejectionText(_ operation: () throws -> Void) -> String {
        rejection(operation).map { "rejected ✓ (\($0))" } ?? "accepted ✗ unexpected"
    }
    #endif
}
