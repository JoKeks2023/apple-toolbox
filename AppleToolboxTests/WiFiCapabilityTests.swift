import Testing
import Foundation
import CoreLocation
@testable import AppleToolbox

@MainActor
struct WiFiCapabilityTests {

    @Test func validatesHotspotInput() {
        #expect(HotspotInputValidator.problem(ssid: "", passphrase: "", security: .open) != nil)
        #expect(HotspotInputValidator.problem(ssid: String(repeating: "x", count: 33), passphrase: "", security: .open) != nil)
        #expect(HotspotInputValidator.problem(ssid: "Café", passphrase: "", security: .open) == nil)
        #expect(HotspotInputValidator.problem(ssid: "Home", passphrase: "short", security: .personal) != nil)
        #expect(HotspotInputValidator.problem(ssid: "Home", passphrase: "long enough", security: .personal) == nil)
        #expect(HotspotInputValidator.problem(ssid: "Home", passphrase: String(repeating: "a", count: 64), security: .personal) == nil)
        #expect(HotspotInputValidator.problem(ssid: "Home", passphrase: String(repeating: "g", count: 64), security: .personal) != nil)
        #expect(HotspotInputValidator.problem(ssid: "Old", passphrase: "abcde", security: .wep) == nil)
        #expect(HotspotInputValidator.problem(ssid: "Old", passphrase: "0123456789", security: .wep) == nil)
        #expect(HotspotInputValidator.problem(ssid: "Old", passphrase: "abcdef", security: .wep) != nil)
    }

    @Test func namesHotspotErrorsAndSecurityTypes() {
        #expect(WiFiDescriptions.hotspotError(code: 7).contains("declined"))
        #expect(WiFiDescriptions.hotspotError(code: 13).contains("Already associated"))
        #expect(WiFiDescriptions.hotspotError(code: 99) == "Error 99")
        #expect(WiFiDescriptions.hotspotSecurity(rawValue: 2) == "WPA/WPA2/WPA3 Personal")
        #expect(WiFiDescriptions.coreWLANSecurity(rawValue: 11) == "WPA3 Personal")
        #expect(WiFiDescriptions.vpnStatus(rawValue: 3) == "Connected")
    }

    @Test func decidesTheLocalNetworkProbe() {
        #expect(LocalNetworkProbeOutcome.decide(sawOwnService: true, sawPolicyDenied: false, timedOut: false) == .granted)
        #expect(LocalNetworkProbeOutcome.decide(sawOwnService: false, sawPolicyDenied: true, timedOut: false) == .denied)
        #expect(LocalNetworkProbeOutcome.decide(sawOwnService: true, sawPolicyDenied: true, timedOut: false) == .denied)
        #expect(LocalNetworkProbeOutcome.decide(sawOwnService: false, sawPolicyDenied: false, timedOut: true) == .noAnswer)
        #expect(LocalNetworkProbeOutcome.decide(sawOwnService: false, sawPolicyDenied: false, timedOut: false) == .running)
    }

    @Test func mapsLocationStateToTheWiFiRequirement() {
        #expect(WiFiLocationRequirement.from(.notDetermined, .fullAccuracy) == .notDetermined)
        #expect(WiFiLocationRequirement.from(.denied, .fullAccuracy) == .denied)
        #expect(WiFiLocationRequirement.from(.authorizedWhenInUse, .reducedAccuracy) == .reducedAccuracy)
        #expect(WiFiLocationRequirement.from(.authorizedWhenInUse, .fullAccuracy) == .precise)
        #expect(WiFiLocationRequirement.reducedAccuracy.status == .permissionRequired)
        #expect(WiFiLocationRequirement.precise.status == .available)
    }

    @Test func linksNetworkCapabilitiesToTheExperiment() {
        for id in ["access-wifi-information", "hotspot", "multicast-networking", "multipath", "network-extensions", "personal-vpn", "5g-network-slicing"] {
            #expect(CapabilityRegistry.descriptor(for: id)?.experimentID == "wifi-capabilities", "\(id)")
        }
    }
}
