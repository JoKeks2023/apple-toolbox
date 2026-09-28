import Testing
import Foundation
@testable import AppleToolbox

@MainActor
struct CapabilityRegistryTests {

    @Test func coversSpecCapabilityList() {
        let ids = Set(CapabilityRegistry.all.map(\.id))
        let spec = ["access-wifi-information", "app-attest", "app-groups", "apple-pay", "associated-domains", "autofill-credential-provider", "background-modes", "classkit", "communication-notifications", "data-protection", "healthkit", "homekit", "hotspot", "icloud", "keychain-sharing", "maps", "matter-allow-setup-payload", "multicast-networking", "multipath", "nfc-tag-reading", "network-extensions", "personal-vpn", "push-notifications", "sign-in-with-apple", "siri", "time-sensitive-notifications", "wallet", "weatherkit", "wireless-accessory-configuration"]
        for id in spec { #expect(ids.contains(id), "missing \(id)") }
        #expect(Set(CapabilityRegistry.all.map(\.kind)) == Set(CapabilityKind.allCases))
    }

    @Test func identifiersAndKeysAreUnique() {
        let ids = CapabilityRegistry.all.map(\.id)
        #expect(Set(ids).count == ids.count)
        let keys = CapabilityRegistry.all.flatMap(\.keys)
        #expect(Set(keys).count == keys.count)
    }

    @Test func everyCapabilityHasMetadata() {
        for capability in CapabilityRegistry.all {
            #expect(!capability.name.isEmpty)
            #expect(!capability.framework.isEmpty)
            #expect(!capability.platforms.isEmpty)
            #expect(!capability.requirement.isEmpty)
            #expect(capability.documentationURL.host == "developer.apple.com")
            #expect(capability.keys.isEmpty == (capability.keySource == .appIDOnly), "\(capability.id)")
            if capability.access == .appleApproval { #expect(capability.kind != .developerCapability, "\(capability.id)") }
        }
    }

    @Test func relatedExperimentsExist() {
        for capability in CapabilityRegistry.all {
            guard let experimentID = capability.experimentID else { continue }
            #expect(ExperimentRegistry.descriptor(for: experimentID) != nil, "\(capability.id) → \(experimentID)")
        }
    }
}
