import Testing
import Foundation
@testable import AppleToolbox

@MainActor
struct RegionAvailabilityTests {

    @Test func hostCardEmulationIsLimitedToTheEEA() {
        let hce = RegionRestrictedFeature.hostCardEmulation
        for region in ["DE", "FR", "NO", "IS", "LI", "de"] { #expect(hce.isSupported(inRegion: region), "\(region)") }
        for region in ["US", "GB", "CH", "JP", "CN"] { #expect(!hce.isSupported(inRegion: region), "\(region)") }
        #expect(RegionRestrictedFeature.europeanEconomicArea.count == 30)
    }

    @Test func tapToPayFollowsTheCountryList() {
        let tapToPay = RegionRestrictedFeature.tapToPay
        for region in ["US", "GB", "DE", "AU", "JP"] { #expect(tapToPay.isSupported(inRegion: region), "\(region)") }
        for region in ["CN", "RU", "IN"] { #expect(!tapToPay.isSupported(inRegion: region), "\(region)") }
    }

    @Test func missingRegionIsNotRestricted() {
        for feature in RegionRestrictedFeature.allCases {
            #expect(feature.isSupported(inRegion: nil))
            #expect(feature.isSupported(inRegion: ""))
        }
    }

    @Test func statusMapsOnlyUnsupportedRegions() {
        #expect(RegionRestrictedFeature.hostCardEmulation.status(region: "US", otherwise: .available) == .regionRestricted)
        #expect(RegionRestrictedFeature.hostCardEmulation.status(region: "AT", otherwise: .approvalRequired) == .approvalRequired)
        #expect(RegionRestrictedFeature.tapToPay.status(region: nil, otherwise: .appleProgramRequired) == .appleProgramRequired)
    }

    @Test func appleIntelligenceLocaleMapping() {
        #expect(AppleIntelligenceRegionMapping.status(modelStatus: .available, supportsCurrentLocale: true) == .available)
        #expect(AppleIntelligenceRegionMapping.status(modelStatus: .available, supportsCurrentLocale: false) == .regionRestricted)
        #expect(AppleIntelligenceRegionMapping.status(modelStatus: .hardwareUnsupported, supportsCurrentLocale: false) == .hardwareUnsupported)
        #expect(AppleIntelligenceRegionMapping.status(modelStatus: .unavailable, supportsCurrentLocale: true) == .unavailable)
    }

    @Test func regionRestrictedExperimentsExplainTheRegion() {
        for id in ["nfc-card-emulation", "tap-to-pay", "foundation-models", "foundation-models-tools", "foundation-models-image"] {
            guard let descriptor = ExperimentRegistry.all.first(where: { $0.id == id }) else { Issue.record("missing \(id)"); continue }
            #expect(descriptor.explanations[.regionRestricted] != nil, "\(id)")
        }
    }
}
