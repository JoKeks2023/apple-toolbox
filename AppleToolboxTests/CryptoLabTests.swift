import Testing
import Foundation
@testable import AppleToolbox

/// Known-answer vectors from the RFCs and NIST, plus round trips and tamper checks for every algorithm the lab offers.
struct CryptoLabKnownVectorTests {
    private func hex(_ text: String) throws -> Data { try #require(CryptoLab.bytes(fromHexOrBase64: text)) }

    @Test func sha2MatchesFIPS180Vectors() {
        let abc = Data("abc".utf8)
        #expect(CryptoLab.hex(CryptoLab.digest(abc, .sha256)) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        #expect(CryptoLab.hex(CryptoLab.digest(abc, .sha384)) == "cb00753f45a35e8bb5a03d699ac65007272c32ab0eded1631a8b605a43ff5bed8086072ba1e7cc2358baeca134c825a7")
        #expect(CryptoLab.hex(CryptoLab.digest(abc, .sha512)) == "ddaf35a193617abacc417349ae20413112e6fa4e89a97ea20a9eeee64b55d39a2192992a274fc1a836ba3c23a3feebbd454d4423643ce80e2a9ac94fa54ca49f")
    }

    /// RFC 4231 test case 2.
    @Test func hmacMatchesRFC4231() {
        let key = Data("Jefe".utf8), message = Data("what do ya want for nothing?".utf8)
        #expect(CryptoLab.hex(CryptoLab.hmac(message, key: key, .sha256)) == "5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843")
        #expect(CryptoLab.hex(CryptoLab.hmac(message, key: key, .sha384)) == "af45d2e376484031617f78d2b58a6b1b9c7ef464f5a01b47e42ec3736322445e8e2240ca5e69e2c78b3239ecfab21649")
        #expect(CryptoLab.hex(CryptoLab.hmac(message, key: key, .sha512)) == "164b7a7bfcf819e2e395fbe73b56e0a387bd64222e831fd610270cd7ea2505549758bf75c05a994a6d034f65f8f0e6fdcaeab1a34d4a6b4b636e070a38bce737")
        let mac = CryptoLab.hmac(message, key: key, .sha256)
        #expect(CryptoLab.isValidHMAC(mac, for: message, key: key, .sha256))
        #expect(!CryptoLab.isValidHMAC(mac, for: CryptoLab.tampered(message), key: key, .sha256))
    }

    /// RFC 5869 test case 1.
    @Test func hkdfMatchesRFC5869() throws {
        let okm = CryptoLab.hkdf(inputKeyMaterial: Data(repeating: 0x0b, count: 22), salt: try hex("000102030405060708090a0b0c"),
                                 info: try hex("f0f1f2f3f4f5f6f7f8f9"), outputByteCount: 42, .sha256)
        #expect(CryptoLab.hex(okm) == "3cb25f25faacd57a90434f64d0362f2a2d2d0a90cf1a5a4c5db02d56ecc4c5bf34007208d5b887185865")
    }

    /// GCM specification test cases 2 (AES-128) and 14 (AES-256): zero key, zero nonce, one zero block.
    @Test func aesGCMMatchesTheGCMSpecification() throws {
        let block = Data(count: 16), nonce = Data(count: 12)
        let aes128 = try CryptoLab.seal(block, key: Data(count: 16), nonce: nonce, associatedData: Data(), .aesGCM128)
        #expect(CryptoLab.hex(aes128.ciphertext) == "0388dace60b6a392f328c2b971b2fe78")
        #expect(CryptoLab.hex(aes128.tag) == "ab6e47d42cec13bdf53a67b21257bddf")
        let aes256 = try CryptoLab.seal(block, key: Data(count: 32), nonce: nonce, associatedData: Data(), .aesGCM256)
        #expect(CryptoLab.hex(aes256.ciphertext) == "cea7403d4d606b6e074ec5d3baf39d18")
        #expect(CryptoLab.hex(aes256.tag) == "d0d1c8a799996bf0265b98b5d48ab919")
    }

    /// RFC 8439 section 2.8.2.
    @Test func chaChaPolyMatchesRFC8439() throws {
        let plaintext = Data("Ladies and Gentlemen of the class of '99: If I could offer you only one tip for the future, sunscreen would be it.".utf8)
        let key = Data(0x80...0x9f), aad = try hex("50515253c0c1c2c3c4c5c6c7")
        let sealed = try CryptoLab.seal(plaintext, key: key, nonce: try hex("070000004041424344454647"), associatedData: aad, .chaChaPoly)
        #expect(CryptoLab.hex(sealed.ciphertext.prefix(16)) == "d31a8d34648e60db7b86afbc53ef7ec2")
        #expect(CryptoLab.hex(sealed.tag) == "1ae10b594f09e26a7e902ecbd0600691")
        #expect(try CryptoLab.open(sealed, key: key, associatedData: aad, .chaChaPoly) == plaintext)
    }

    /// RFC 7748 section 6.1.
    @Test func x25519MatchesRFC7748() throws {
        let secret = try CryptoLab.x25519SharedSecret(privateKey: try hex("77076d0a7318a57d3c16c17251b26645df4c2f87ebc0992ab177fba51db92c2a"),
                                                      peerPublicKey: try hex("de9edb7d7b7dc1b4d35b61c2ece435373f8343c85b78674dadfc7e146f882b4f"))
        #expect(CryptoLab.hex(secret) == "4a5d9d5ba4ce2de1728e3bf480350f25e07e21c947d19e3376f09b3c1e161742")
    }

    /// RFC 8032 section 7.1, tests 1 and 2. CryptoKit signs with randomness, so the vectors are checked by verification.
    @Test func ed25519MatchesRFC8032() throws {
        let publicKey = try hex("d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a")
        #expect(try CryptoLab.ed25519PublicKey(forPrivateKey: try hex("9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60")) == publicKey)
        let signature = try hex("e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e065224901555fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b")
        #expect(try CryptoLab.isValidEd25519Signature(signature, for: Data(), publicKey: publicKey))
        #expect(try CryptoLab.isValidEd25519Signature(
            try hex("92a009a9f0d4cab8720e820b5f642540a2b27b5416503f8fb3762223ebdb69da085ac1e43e15996e458f3613d0f11d8c387b2eaeb4302aeeb00d291612bb0c00"),
            for: Data([0x72]), publicKey: try hex("3d4017c3e843895a92b70aa74d1b7ebc9c982ccf2ec4968cc0cd55f12af4660c")))
        #expect(try !CryptoLab.isValidEd25519Signature(CryptoLab.tampered(signature), for: Data(), publicKey: publicKey))
    }
}

struct CryptoLabRoundTripTests {
    private let message = Data("Apple Toolbox".utf8)

    @Test(arguments: CryptoLabCipher.allCases)
    func aeadRoundTripsAndRejectsTampering(_ cipher: CryptoLabCipher) throws {
        let key = CryptoLab.randomKey(byteCount: cipher.keyByteCount)
        let aad = Data("header".utf8)
        let sealed = try CryptoLab.seal(message, key: key, associatedData: aad, cipher)
        #expect(sealed.nonce.count == 12 && sealed.tag.count == 16)
        #expect(try CryptoLab.open(sealed, key: key, associatedData: aad, cipher) == message)
        let tampered = CryptoLabSealedMessage(nonce: sealed.nonce, ciphertext: CryptoLab.tampered(sealed.ciphertext), tag: sealed.tag)
        #expect(throws: (any Error).self) { try CryptoLab.open(tampered, key: key, associatedData: aad, cipher) }
        #expect(throws: (any Error).self) { try CryptoLab.open(sealed, key: key, associatedData: Data(), cipher) }
    }

    @Test(arguments: CryptoLabCurve.allCases, CryptoLabHash.allCases)
    func bothSidesDeriveTheSameKey(_ curve: CryptoLabCurve, _ hash: CryptoLabHash) throws {
        let agreement = try CryptoLab.agree(curve, hash: hash, salt: Data("salt".utf8))
        #expect(agreement.aliceSecret == agreement.bobSecret)
        #expect(agreement.aliceKey == agreement.bobKey && agreement.aliceKey.count == 32)
        #expect(agreement.alicePublicKey != agreement.bobPublicKey)
    }

    @Test(arguments: CryptoLabSignatureAlgorithm.allCases)
    func signaturesVerifyAndDetectTampering(_ algorithm: CryptoLabSignatureAlgorithm) throws {
        let run = try CryptoLab.signatureRun(algorithm, message: message)
        #expect(run.verifies)
        #expect(!run.tamperedMessageVerifies)
        #expect(!run.tamperedSignatureVerifies)
        #expect((run.derSignature == nil) == (algorithm == .ed25519))
    }

    @Test(arguments: CryptoLabHPKESuite.allCases)
    func hpkeOpensOnlyForTheRecipient(_ suite: CryptoLabHPKESuite) throws {
        let run = try CryptoLab.hpkeRun(suite, message: message, associatedData: Data("aad".utf8))
        #expect(run.opened == message)
        #expect(run.ciphertext.count == message.count + 16)
        #expect(run.wrongRecipientError != nil)
        #expect(run.tamperedError != nil)
    }

    @Test(arguments: CryptoLabKeyKind.allCases)
    func everyExportedRepresentationImportsAgain(_ kind: CryptoLabKeyKind) throws {
        let export = CryptoLab.exportKey(kind)
        #expect(!export.privateRepresentations.isEmpty)
        for representation in export.privateRepresentations + export.publicRepresentations {
            #expect(representation.roundTrips, "\(kind) \(representation.label)")
        }
        let part: CryptoLabKeyPart = kind == .symmetric ? .privateKey : .publicKey
        #expect(throws: Never.self) { try CryptoLab.importKey(export.importCandidate, kind: kind, format: export.importFormat, part: part) }
    }

    @Test func importRejectsWhatCryptoKitCannotRead() {
        #expect(throws: CryptoLabError.self) { try CryptoLab.importKey("   ", kind: .p256, format: .pem, part: .publicKey) }
        #expect(throws: CryptoLabError.self) { try CryptoLab.importKey("00", kind: .ed25519, format: .pem, part: .publicKey) }
        #expect(throws: CryptoLabError.self) { try CryptoLab.importKey("00", kind: .symmetric, format: .raw, part: .publicKey) }
        #expect(throws: CryptoLabError.self) { try CryptoLab.importKey("%%%", kind: .p256, format: .der, part: .publicKey) }
        #expect(throws: (any Error).self) { try CryptoLab.importKey("-----BEGIN PUBLIC KEY-----\nAAAA\n-----END PUBLIC KEY-----", kind: .p256, format: .pem, part: .publicKey) }
    }

    @Test func privateKeyImportDerivesThePublicKey() throws {
        let export = CryptoLab.exportKey(.p384)
        let pem = try #require(export.privateRepresentations.first { $0.label == "PEM" }?.value)
        let publicKey = try CryptoLab.importKey(pem, kind: .p384, format: .pem, part: .privateKey)
        #expect(try CryptoLab.importKey(export.importCandidate, kind: .p384, format: .pem, part: .publicKey) == publicKey)
    }
}

struct CryptoLabEncodingTests {

    @Test func decodesHexWithSeparatorsAndBase64() {
        #expect(CryptoLab.bytes(fromHexOrBase64: "de:ad be ef") == Data([0xde, 0xad, 0xbe, 0xef]))
        #expect(CryptoLab.bytes(fromHexOrBase64: "3q2+7w==") == Data([0xde, 0xad, 0xbe, 0xef]))
        #expect(CryptoLab.bytes(fromHexOrBase64: "") == nil)
        #expect(CryptoLab.bytes(fromHexOrBase64: "not base64!") == nil)
    }

    @Test func tamperingChangesExactlyOneBit() {
        #expect(CryptoLab.tampered(Data([0x10, 0x20])) == Data([0x11, 0x20]))
        #expect(CryptoLab.tampered(Data()) == Data([0x01]))
    }

    @Test func reportsCoverEveryOperation() {
        var request = CryptoLabRequest()
        for operation in CryptoLabOperation.allCases {
            request.operation = operation
            let report = CryptoLab.run(request)
            #expect(!report.isError, "\(operation): \(report.text)")
            #expect(!report.text.contains("✗"), "\(operation)")
        }
    }

    @Test func exportFillsTheImportField() {
        var request = CryptoLabRequest()
        request.operation = .keys
        request.keyKind = .ed25519
        let report = CryptoLab.run(request)
        #expect(report.importFormat == .raw && report.importPart == .publicKey)
        request.importText = report.importCandidate ?? ""
        request.keyFormat = .raw
        #expect(!CryptoLab.importReport(request).isError)
    }
}
