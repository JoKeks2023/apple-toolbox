import Testing
import Foundation
@testable import AppleToolbox

@MainActor
struct AdvancedWalletTests {

    @Test func everyAdvancedCredentialIsRepresentedSeparately() throws {
        let ids = ["corporate-badge", "access-keys", "home-key", "car-key", "student-id", "hotel-key", "tap-to-pay"]
        #expect(Set(AdvancedCredentialCatalog.all.map(\.id)) == Set(ids))
        for id in ids {
            let credential = try #require(AdvancedCredentialCatalog.credential(for: id))
            let experiment = try #require(ExperimentRegistry.descriptor(for: id))
            #expect(experiment.category == .wallet, "\(id)")
            #expect(experiment.applePrograms == [credential.program], "\(id)")
            #expect(!experiment.entitlements.isEmpty, "\(id)")
            #expect(experiment.explanation(for: .appleProgramRequired)?.reason == credential.reason, "\(id)")
            #expect(credential.documentationURL.host == "developer.apple.com", "\(id)")
            for capabilityID in credential.capabilityIDs {
                let capability = try #require(CapabilityRegistry.descriptor(for: capabilityID), "\(id) → \(capabilityID)")
                #expect(capability.access == .appleApproval, "\(capabilityID)")
            }
        }
        #expect(ExperimentRegistry.descriptor(for: "secure-element-passes") != nil)
    }

    @Test func issuerEntitlementsAreInTheCapabilityRegistry() {
        for id in AdvancedCredentialCatalog.issuerCapabilityIDs {
            #expect(CapabilityRegistry.descriptor(for: id)?.kind == .appleProgram, "\(id)")
        }
        #expect(CapabilityRegistry.descriptor(for: "tap-to-pay")?.experimentID == "tap-to-pay")
        #expect(CapabilityRegistry.descriptor(for: "secure-element-credential")?.experimentID == "secure-element-passes")
    }

    @Test func withoutProgramEntitlementsTheStatusNamesTheProgram() {
        // The test host is signed without any Apple issuer entitlement.
        for credential in AdvancedCredentialCatalog.all where !credential.checksPaymentCardReader {
            #expect(ExperimentAvailability.advancedCredential(credential.id) == .appleProgramRequired, "\(credential.id)")
        }
        #expect(ExperimentAvailability.advancedCredential("not-a-credential") == .unavailable)
    }
}
