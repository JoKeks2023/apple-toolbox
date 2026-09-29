import Testing
import Foundation
import CryptoKit
@testable import AppleToolbox

struct KeychainSharingTests {
    private let defaultGroup = "ABCDE12345.\(ToolboxIdentifiers.base).ios"

    @Test func readsTheTeamPrefixOfAnAccessGroup() {
        #expect(KeychainSharingStore.teamPrefix(defaultGroup) == "ABCDE12345")
        #expect(KeychainSharingStore.teamPrefix("group.com.example.AppleToolbox") == nil)
        #expect(KeychainSharingStore.teamPrefix("com.apple.token") == nil)
        #expect(KeychainSharingStore.teamPrefix("") == nil)
    }

    @Test func namesEveryAccessGroupOption() {
        #expect(KeychainAccessGroupOption.appDefault.accessGroup(defaultGroup: defaultGroup) == defaultGroup)
        #expect(KeychainAccessGroupOption.shared.accessGroup(defaultGroup: defaultGroup) == "ABCDE12345.\(ToolboxIdentifiers.base).shared")
        #expect(KeychainAccessGroupOption.appGroup.accessGroup(defaultGroup: nil) == ToolboxIdentifiers.appGroup)
        #expect(KeychainAccessGroupOption.shared.accessGroup(defaultGroup: nil) == nil)
    }

    @Test func summarizesItemAttributes() {
        let password = KeychainSharingStore.summary(of: ["agrp": defaultGroup, "svce": "com.example", "acct": "demo", "sync": true], itemClass: "generic password")
        #expect(password == KeychainItemSummary(itemClass: "generic password", accessGroup: defaultGroup, label: "com.example · demo", synchronizable: true))
        let key = KeychainSharingStore.summary(of: ["agrp": defaultGroup, "atag": Data("tag".utf8)], itemClass: "key")
        #expect(key.label == "tag" && !key.synchronizable)
        #expect(KeychainSharingStore.summary(of: [:], itemClass: "certificate").accessGroup == "unknown group")
    }

    @Test func groupsItemsAndKeepsEmptyKnownGroups() {
        let items = [
            KeychainItemSummary(itemClass: "key", accessGroup: "B", label: "z", synchronizable: false),
            KeychainItemSummary(itemClass: "generic password", accessGroup: "B", label: "a", synchronizable: false),
            KeychainItemSummary(itemClass: "generic password", accessGroup: "A", label: "x", synchronizable: true),
        ]
        let groups = KeychainSharingStore.grouped(items, knownGroups: ["C", "A"])
        #expect(groups.map(\.accessGroup) == ["A", "B", "C"])
        #expect(groups[1].items.map(\.label) == ["a", "z"])
        #expect(groups[2].items.isEmpty)
        let report = KeychainSharingStore.listing(groups, failures: [])
        #expect(report.text.contains("C — no items") && report.text.contains("B — 2 items") && report.text.contains("· iCloud"))
        #expect(!report.isError)
        #expect(KeychainSharingStore.listing(groups, failures: ["key: errSecParam"]).isError)
    }
}

@MainActor
struct CredentialProviderScanTests {

    @Test func findsOnlyCredentialProviderExtensions() {
        let provider: [String: Any] = [
            "CFBundleIdentifier": "com.example.app.provider",
            "NSExtension": ["NSExtensionPointIdentifier": CredentialProviderExtensionScan.extensionPoint,
                            "NSExtensionAttributes": ["ASCredentialProviderExtensionCapabilities": ["ProvidesPasskeys": true, "ProvidesOneTimeCodes": false]]],
        ]
        let widget: [String: Any] = ["CFBundleIdentifier": "com.example.app.widget", "NSExtension": ["NSExtensionPointIdentifier": "com.apple.widgetkit-extension"]]
        let providers = CredentialProviderExtensionScan.providers(in: [provider, widget, [:]])
        #expect(providers == [CredentialProviderExtensionScan.Provider(bundleIdentifier: "com.example.app.provider", capabilities: ["ProvidesPasskeys"])])
    }

    @Test func statusFollowsTheBundledProviders() {
        #expect(ExperimentAvailability.credentialProvider() == CredentialProviderExtensionScan.status(for: CredentialProviderExtensionScan.bundled))
        #expect(CredentialProviderExtensionScan.status(for: []) == .entitlementRequired)
        let unprovisioned = CredentialProviderExtensionScan.Provider(bundleIdentifier: "p", capabilities: [], entitlement: .notProvisioned)
        #expect(CredentialProviderExtensionScan.status(for: [unprovisioned]) == .entitlementRequired)
        let provisioned = CredentialProviderExtensionScan.Provider(bundleIdentifier: "p", capabilities: [], entitlement: .provisioned("true"))
        #expect(CredentialProviderExtensionScan.status(for: [provisioned]) == .available)
        // Simulator and local builds embed no profile: the extension is trusted until AutoFill says otherwise.
        #expect(CredentialProviderExtensionScan.status(for: [CredentialProviderExtensionScan.Provider(bundleIdentifier: "p", capabilities: [])]) == .available)
    }

    @Test func namesIdentityStoreErrors() {
        #expect(CredentialProviderReport.name(forStoreErrorCode: 0) == "internalError")
        #expect(CredentialProviderReport.name(forStoreErrorCode: 1) == "storeDisabled")
        #expect(CredentialProviderReport.name(forStoreErrorCode: 2) == "storeBusy")
        #expect(CredentialProviderReport.describe(nil) == "no error was reported")
    }
}

struct WebAuthnOptionTests {

    /// The raw values are the WebAuthn Level 3 strings that the requests carry.
    @Test func optionsUseWebAuthnValues() {
        #expect(WebAuthnUserVerification.allCases.map(\.rawValue) == ["preferred", "required", "discouraged"])
        #expect(WebAuthnAttestation.allCases.map(\.rawValue) == ["none", "indirect", "direct", "enterprise"])
        #expect(WebAuthnResidentKey.allCases.map(\.rawValue) == ["discouraged", "preferred", "required"])
    }
}

@MainActor
struct CredentialExperimentRegistryTests {

    @Test func newSecurityExperimentsAreRegisteredAndLinked() throws {
        for id in ["keychain-sharing", "security-keys", "credential-provider"] {
            let experiment = try #require(ExperimentRegistry.descriptor(for: id))
            #expect(experiment.category == .security)
        }
        #expect(CapabilityRegistry.descriptor(for: "keychain-sharing")?.experimentID == "keychain-sharing")
        #expect(CapabilityRegistry.descriptor(for: "autofill-credential-provider")?.experimentID == "credential-provider")
    }
}

struct CredentialVaultTests {

    @Test func matchesPasswordsByDomainAndSubdomain() {
        let vault = CredentialVault(passwords: [
            DemoPasswordCredential(id: "a", domain: "example.com", user: "one", password: "x"),
            DemoPasswordCredential(id: "b", domain: "login.example.com", user: "two", password: "y"),
        ])
        #expect(vault.passwords(matching: ["https://www.example.com/sign-in"]).map(\.id) == ["a"])
        #expect(vault.passwords(matching: ["login.example.com"]).map(\.id) == ["a", "b"])
        #expect(vault.passwords(matching: ["example.org"]).isEmpty)
        #expect(vault.passwords(matching: []).count == 2)
        #expect(!CredentialVault.host("badexample.com", belongsTo: "example.com"))
    }

    @Test func filtersPasskeysByRelyingPartyAndAllowList() {
        let passkey = DemoPasskeyCredential(relyingParty: "webauthn.io", userName: "u", userHandle: Data([1]), credentialID: Data([9, 9]), signCount: 0, createdAt: .now)
        let vault = CredentialVault(passkeys: [passkey])
        #expect(vault.passkeys(forRelyingParty: "WebAuthn.io").count == 1)
        #expect(vault.passkeys(forRelyingParty: "webauthn.io", allowedCredentialIDs: [Data([1])]).isEmpty)
        #expect(vault.passkeys(forRelyingParty: "webauthn.io", allowedCredentialIDs: [Data([9, 9])]).count == 1)
        #expect(passkey.id == "CQk")
    }

    @Test func generatesDemoPasswordsInTheExpectedShape() {
        var generator = SystemRandomNumberGenerator()
        let passwords = CredentialVault.demoPasswords(using: &generator)
        #expect(passwords.map(\.domain) == ["example.com", "login.example.com"])
        #expect(passwords.allSatisfy { $0.password.hasPrefix("Demo-") && $0.password.count == 19 })
    }

    @Test func keepsTheNewestEventsFirst() {
        var vault = CredentialVault()
        for index in 0..<(CredentialVault.eventLimit + 5) { vault.log("event \(index)") }
        #expect(vault.events.count == CredentialVault.eventLimit)
        #expect(vault.events.first?.text == "event \(CredentialVault.eventLimit + 4)")
    }
}

struct SoftwarePasskeyAuthenticatorTests {

    @Test func encodesCBORHeads() {
        #expect(CBOR.unsigned(10).encoded == Data([0x0a]))
        #expect(CBOR.unsigned(100).encoded == Data([0x18, 0x64]))
        #expect(CBOR.unsigned(1000).encoded == Data([0x19, 0x03, 0xe8]))
        #expect(CBOR.int(-7).encoded == Data([0x26]))
        #expect(CBOR.int(-1).encoded == Data([0x20]))
        #expect(CBOR.text("fmt").encoded == Data([0x63, 0x66, 0x6d, 0x74]))
        #expect(CBOR.bytes(Data([1, 2])).encoded == Data([0x42, 1, 2]))
        #expect(CBOR.map([]).encoded == Data([0xa0]))
        #expect(CBOR.array([.unsigned(1), .unsigned(2)]).encoded == Data([0x82, 1, 2]))
    }

    @Test func buildsAssertionAuthenticatorData() {
        let data = SoftwarePasskeyAuthenticator.authenticatorData(relyingParty: "example.com", flags: [.userPresent, .userVerified], signCount: 258)
        #expect(data.count == 37)
        #expect(data.prefix(32) == Data(SHA256.hash(data: Data("example.com".utf8))))
        #expect(data[32] == 0x05)
        #expect(Array(data.suffix(4)) == [0, 0, 1, 2])
    }

    @Test func buildsARegistrationThatVerifies() throws {
        let key = P256.Signing.PrivateKey()
        let credentialID = SoftwarePasskeyAuthenticator.randomCredentialID()
        let attested = SoftwarePasskeyAuthenticator.attestedCredentialData(credentialID: credentialID, publicKey: key.publicKey)
        // AAGUID (16) + length (2) + ID (16) + COSE key (77: map header, kty, alg, crv, x and y with their headers)
        #expect(attested.count == 16 + 2 + 16 + 77)
        #expect(Array(attested[16..<18]) == [0, 16])
        let authData = SoftwarePasskeyAuthenticator.authenticatorData(relyingParty: "example.com", flags: [.userPresent], signCount: 0, attestedCredential: attested)
        #expect(authData[32] == 0x41)
        let object = SoftwarePasskeyAuthenticator.attestationObject(authenticatorData: authData)
        #expect(object.prefix(5) == Data([0xa3, 0x63, 0x66, 0x6d, 0x74]))

        let clientDataHash = Data(SHA256.hash(data: Data("{}".utf8)))
        let signature = try SoftwarePasskeyAuthenticator.signature(privateKey: key, authenticatorData: authData, clientDataHash: clientDataHash)
        let parsed = try P256.Signing.ECDSASignature(derRepresentation: signature)
        #expect(key.publicKey.isValidSignature(parsed, for: authData + clientDataHash))
    }
}
