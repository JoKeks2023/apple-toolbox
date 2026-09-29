import Foundation
import Combine
import CryptoKit

#if canImport(DeviceCheck)
import DeviceCheck
#endif

/// App Attest and DeviceCheck against Apple's servers (spec §8). This lab has no server, so the challenge is generated on
/// the device; in production the server issues it, verifies the attestation and checks every assertion.
@MainActor
final class AppAttestExperimentService: ObservableObject {
    @Published private(set) var output: String
    @Published private(set) var isError = false
    @Published private(set) var isRunning = false
    /// Kept in memory for this session only; a production app persists it, because the key is unusable without it.
    @Published private(set) var attestedKeyID: String?

    init(initialOutput: String) {
        output = initialOutput
    }

    static var supportSummary: String {
        #if canImport(DeviceCheck)
        let appAttest = DCAppAttestService.shared.isSupported ? "supported" : "not supported"
        let deviceCheck = DCDevice.current.isSupported ? "supported" : "not supported"
        return """
        App Attest: \(appAttest) on this device (DCAppAttestService.isSupported)
        DeviceCheck: \(deviceCheck) on this device (DCDevice.isSupported)
        Environment: the app declares no appattest-environment entitlement, so development-signed builds use the App Attest sandbox; TestFlight and App Store builds always use production.
        """
        #else
        return "DeviceCheck is not available in this platform SDK."
        #endif
    }

    func generateAndAttestKey() async {
        #if canImport(DeviceCheck)
        let service = DCAppAttestService.shared
        guard service.isSupported else { return finish("App Attest is not supported on this device, so no key can be generated. Apps skip the check here and fall back to other server-side risk signals.", isError: true) }
        isRunning = true
        defer { isRunning = false }
        attestedKeyID = nil
        do {
            let keyID = try await service.generateKey()
            let challenge = LocalChallenge.randomBytes(32)
            let clientDataHash = Data(SHA256.hash(data: challenge))
            let attestation = try await service.attestKey(keyID, clientDataHash: clientDataHash)
            attestedKeyID = keyID
            finish("""
            Key generated in the Secure Enclave and attested by Apple.
            Key ID: \(keyID)
            Challenge: \(challenge.count) random bytes generated on this device (\(LocalChallenge.hexPrefix(challenge)))
              LOCAL ONLY: in production your server issues a one-time challenge and verifies the attestation.
            Client data hash: SHA-256 of the challenge (\(LocalChallenge.hexPrefix(clientDataHash)))
            Attestation object: \(attestation.count) bytes (CBOR with certificate chain, receipt and authenticator data)
            Next: a server would validate the certificate chain against Apple's App Attest root, check the nonce and App ID, and store the public key.
            """)
        } catch {
            finish(Self.describe(error, step: "App Attest key generation or attestation"), isError: true)
        }
        #else
        finish("DeviceCheck is not available in this platform SDK.", isError: true)
        #endif
    }

    func generateAssertion() async {
        #if canImport(DeviceCheck)
        guard let keyID = attestedKeyID else { return finish("Generate and attest a key first; assertions are signed with the attested key.", isError: true) }
        isRunning = true
        defer { isRunning = false }
        let payload = #"{"action":"sample-request","issuedAt":"\#(Date().formatted(.iso8601))","nonce":"\#(LocalChallenge.randomBytes(8).map { String(format: "%02x", $0) }.joined())"}"#
        let clientDataHash = Data(SHA256.hash(data: Data(payload.utf8)))
        do {
            let assertion = try await DCAppAttestService.shared.generateAssertion(keyID, clientDataHash: clientDataHash)
            finish("""
            Assertion generated with key \(keyID.prefix(12))…
            Sample payload: \(payload)
            Client data hash: SHA-256 of the payload (\(LocalChallenge.hexPrefix(clientDataHash)))
            Assertion object: \(assertion.count) bytes (CBOR with signature and authenticator data including a counter)
            Next: a server would verify the signature with the stored public key and check that the counter increased.
            """)
        } catch {
            finish(Self.describe(error, step: "App Attest assertion"), isError: true)
        }
        #else
        finish("DeviceCheck is not available in this platform SDK.", isError: true)
        #endif
    }

    func requestDeviceCheckToken() async {
        #if canImport(DeviceCheck)
        guard DCDevice.current.isSupported else { return finish("DeviceCheck is not supported on this device, so no token can be generated.", isError: true) }
        isRunning = true
        defer { isRunning = false }
        do {
            let token = try await DCDevice.current.generateToken()
            finish("""
            DeviceCheck token received: \(token.count) bytes (not shown; treat it like a credential).
            The token is ephemeral. Your server sends it to Apple's DeviceCheck API to query or set two bits per device and developer team.
            """)
        } catch {
            finish(Self.describe(error, step: "DeviceCheck token"), isError: true)
        }
        #else
        finish("DeviceCheck is not available in this platform SDK.", isError: true)
        #endif
    }

    private func finish(_ text: String, isError: Bool = false) {
        output = text
        self.isError = isError
    }

    private static func describe(_ error: Error, step: String) -> String {
        #if canImport(DeviceCheck)
        if let error = error as? DCError {
            let (name, hint) = switch error.code {
            case .featureUnsupported: ("featureUnsupported", "The service is not available for this device, build or process.")
            case .invalidInput: ("invalidInput", "The system rejected the key identifier or client data hash.")
            case .invalidKey: ("invalidKey", "The key cannot be used for this call (for example it was already attested). Generate a new key.")
            case .serverUnavailable: ("serverUnavailable", "Apple's server could not be reached. Production apps retry attestation later with the same key.")
            case .unknownSystemFailure: ("unknownSystemFailure", "The system could not complete the request.")
            @unknown default: ("code \(error.code.rawValue)", "")
            }
            return "\(step) failed with DCError \(error.code.rawValue) (\(name)): \(error.localizedDescription)\n\(hint)"
        }
        #endif
        let nsError = error as NSError
        return "\(step) failed (\(nsError.domain) \(nsError.code)): \(nsError.localizedDescription)"
    }
}
