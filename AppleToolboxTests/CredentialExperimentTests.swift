import Testing
import Foundation
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

    @Test func thisBuildBundlesNoProvider() {
        #expect(CredentialProviderExtensionScan.bundled.isEmpty)
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
