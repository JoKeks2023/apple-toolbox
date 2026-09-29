import Testing
import Foundation
@testable import AppleToolbox

private let unavailableStatuses: [ExperimentStatus] = [
    .permissionRequired, .permissionDenied, .entitlementRequired, .approvalRequired, .hardwareUnsupported, .osUnsupported,
    .platformUnsupported, .regionRestricted, .appleProgramRequired, .developmentOnly, .deviceOnly, .simulatorOnly, .unavailable,
]

@MainActor
struct ExperimentRegistryTests {

    @Test func identifiersAreUniqueAndURLSafe() {
        let ids = ExperimentRegistry.all.map(\.id)
        #expect(Set(ids).count == ids.count)
        for id in ids { #expect(id == id.lowercased() && !id.contains(" "), "\(id)") }
    }

    @Test func containsThePhaseOneExperiments() {
        for id in ["localauthentication", "cryptokit", "keychain", "secure-enclave", "core-location", "core-motion"] {
            #expect(ExperimentRegistry.descriptor(for: id) != nil, "\(id)")
        }
    }

    @Test func everyExperimentHasDocumentationAndMetadata() {
        for experiment in ExperimentRegistry.all {
            #expect(!experiment.name.isEmpty)
            #expect(!experiment.description.isEmpty, "\(experiment.id)")
            #expect(!experiment.frameworks.isEmpty, "\(experiment.id)")
            #expect(!experiment.supportedPlatforms.isEmpty, "\(experiment.id)")
            #expect(!experiment.osRequirements.isEmpty, "\(experiment.id)")
            #expect(experiment.documentationURL.host == "developer.apple.com", "\(experiment.id)")
        }
    }

    @Test func everyCategoryHasAnExperiment() {
        for category in ExperimentCategory.allCases {
            #expect(ExperimentRegistry.all.contains { $0.category == category }, "\(category.rawValue)")
        }
    }

    @Test func unsupportedPlatformOverridesTheLiveCheck() {
        for experiment in ExperimentRegistry.all where !experiment.supportedPlatforms.contains(CurrentPlatform.value) {
            #expect(experiment.currentStatus == .platformUnsupported, "\(experiment.id)")
        }
    }
}

@MainActor
struct ExperimentExplanationTests {

    @Test func availableExperimentsNeedNoExplanation() {
        for experiment in ExperimentRegistry.all { #expect(experiment.explanation(for: .available) == nil) }
    }

    @Test func everyUnavailableStatusIsExplained() {
        for experiment in ExperimentRegistry.all {
            for status in unavailableStatuses {
                let explanation = experiment.explanation(for: status)
                #expect(explanation?.reason.isEmpty == false, "\(experiment.id) · \(status.title)")
                #expect(explanation?.required.isEmpty == false, "\(experiment.id) · \(status.title)")
                #expect(explanation?.nextStep.isEmpty == false, "\(experiment.id) · \(status.title)")
            }
        }
    }

    @Test func specificExplanationsNameTheBoundary() throws {
        let roomPlan = try #require(ExperimentRegistry.descriptor(for: "roomplan"))
        #expect(roomPlan.explanation(for: .hardwareUnsupported)?.reason.contains("LiDAR") == true)
        let passkeys = try #require(ExperimentRegistry.descriptor(for: "passkeys"))
        #expect(passkeys.explanation(for: .entitlementRequired)?.required.contains("webcredentials") == true)
    }

    @Test func initialOutputPointsToTheExplanation() {
        #expect(ExperimentOutput.initialMessage(for: .available).hasPrefix("Ready"))
        #expect(ExperimentOutput.initialMessage(for: .hardwareUnsupported).contains("Why doesn't this work?"))
    }
}

@MainActor
struct ExperimentCheckTests {

    private func outcome(_ id: String, of experimentID: String, for status: ExperimentStatus) throws -> ExperimentCheck.Outcome? {
        let experiment = try #require(ExperimentRegistry.descriptor(for: experimentID))
        return experiment.checks(for: status).first { $0.id == id }?.outcome
    }

    @Test func platformCheckMatchesSupportedPlatforms() {
        for experiment in ExperimentRegistry.all {
            let supported = experiment.supportedPlatforms.contains(CurrentPlatform.value)
            #expect(experiment.checks(for: .available).first { $0.id == "platform" }?.outcome == (supported ? .passed : .failed), "\(experiment.id)")
        }
    }

    @Test func hardwareCheckFollowsTheStatus() throws {
        #expect(try outcome("hardware", of: "roomplan", for: .hardwareUnsupported) == .failed)
        #expect(try outcome("hardware", of: "roomplan", for: .unavailable) == .pending)
        #expect(try outcome("hardware", of: "roomplan", for: .available) == .passed)
        #expect(try outcome("hardware", of: "cryptokit", for: .available) == nil)
    }

    @Test func permissionCheckFollowsTheStatus() throws {
        #expect(try outcome("permission", of: "core-location", for: .permissionRequired) == .pending)
        #expect(try outcome("permission", of: "core-location", for: .permissionDenied) == .failed)
        #expect(try outcome("permission", of: "core-location", for: .available) == .passed)
    }

    @Test func appleProgramsAreChecked() throws {
        #expect(try outcome("programs", of: "sign-in-with-apple", for: .entitlementRequired) == .passed)
        #expect(try outcome("programs", of: "sign-in-with-apple", for: .appleProgramRequired) == .failed)
        #expect(try outcome("programs", of: "cryptokit", for: .available) == nil)
    }

    @Test func entitlementCheckFollowsTheStatus() throws {
        #expect(try outcome("entitlement", of: "homekit-discovery", for: .entitlementRequired) == .failed)
        #expect(try outcome("entitlement", of: "homekit-discovery", for: .available) == .passed)
    }
}

struct PermissionStateTests {

    @Test func mapsToExperimentStatus() {
        #expect(PermissionState.granted.experimentStatus == nil)
        #expect(PermissionState.notDetermined.experimentStatus == .permissionRequired)
        #expect(PermissionState.unknown.experimentStatus == .permissionRequired)
        #expect(PermissionState.denied.experimentStatus == .permissionDenied)
        #expect(PermissionState.restricted.experimentStatus == .permissionDenied)
    }
}

@MainActor
struct CryptoServiceTests {

    @Test func sha256MatchesTheKnownVector() {
        #expect(CryptoService.sha256Hex("abc") == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }
}

@MainActor
struct WalletPassDraftTests {

    @Test func draftIsPassJSON() throws {
        let service = WalletPassCreatorService()
        service.passName = "Test Pass"
        service.serialNumber = "serial-42"
        service.createDraft()
        let url = try #require(service.draftURL)
        let pass = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        #expect(pass["formatVersion"] as? Int == 1)
        #expect(pass["description"] as? String == "Test Pass")
        #expect(pass["serialNumber"] as? String == "serial-42")
        #expect(pass["generic"] is [String: Any])
    }
}

#if canImport(MultipeerConnectivity) && !os(watchOS) && !os(tvOS)
struct PeerInvitationPolicyTests {

    @Test func exactlyOnePeerInvites() {
        let key = PeerInvitationPolicy.identifierKey
        let first = UUID().uuidString, second = UUID().uuidString
        let firstInvites = PeerInvitationPolicy.shouldInvite(localIdentifier: first, discoveryInfo: [key: second])
        let secondInvites = PeerInvitationPolicy.shouldInvite(localIdentifier: second, discoveryInfo: [key: first])
        #expect(firstInvites != secondInvites)
    }

    @Test func invitesPeersWithoutAnIdentifier() {
        #expect(PeerInvitationPolicy.shouldInvite(localIdentifier: "a", discoveryInfo: nil))
        #expect(PeerInvitationPolicy.shouldInvite(localIdentifier: "a", discoveryInfo: ["app": "apple-toolbox"]))
    }
}
#endif
