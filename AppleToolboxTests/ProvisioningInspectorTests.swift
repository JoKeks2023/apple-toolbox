import Testing
import Foundation
@testable import AppleToolbox

@MainActor
struct ProvisioningInspectorTests {

    private func signedProfile(entitlements: String) -> Data {
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Name</key><string>Toolbox Development</string>
            <key>TeamName</key><string>Example Team</string>
            <key>TeamIdentifier</key><array><string>ABCDE12345</string></array>
            <key>ExpirationDate</key><date>2030-01-01T00:00:00Z</date>
            <key>ProvisionedDevices</key><array><string>device-1</string><string>device-2</string></array>
            <key>Entitlements</key><dict>\(entitlements)</dict>
        </dict>
        </plist>
        """
        // Profiles are CMS messages: binary bytes surround the XML payload.
        var data = Data([0x30, 0x80, 0x06, 0x09, 0x2A, 0x86])
        data.append(Data(plist.utf8))
        data.append(Data([0x00, 0x00, 0xA0, 0x82]))
        return data
    }

    @Test func parsesProfileSummaryAndEntitlements() throws {
        let data = signedProfile(entitlements: "<key>com.apple.developer.homekit</key><true/><key>com.apple.developer.nfc.readersession.formats</key><array><string>NDEF</string><string>TAG</string></array><key>get-task-allow</key><true/>")
        let profile = try #require(ProvisioningInspector.parse(data))
        #expect(profile.name == "Toolbox Development")
        #expect(profile.teamName == "Example Team")
        #expect(profile.teamIdentifier == "ABCDE12345")
        #expect(profile.provisionedDeviceCount == 2)
        #expect(profile.isExpired == false)
        #expect(profile.entitlements["com.apple.developer.homekit"] == "true")
        #expect(profile.entitlements["com.apple.developer.nfc.readersession.formats"] == "NDEF, TAG")
    }

    @Test func mapsProfileContentToCapabilityState() throws {
        let data = signedProfile(entitlements: "<key>com.apple.developer.homekit</key><true/><key>aps-environment</key><string>development</string>")
        let lookup = ProvisioningLookup.found(try #require(ProvisioningInspector.parse(data)))
        let homeKit = try #require(CapabilityRegistry.descriptor(for: "homekit"))
        let weatherKit = try #require(CapabilityRegistry.descriptor(for: "weatherkit"))
        let push = try #require(CapabilityRegistry.descriptor(for: "push-notifications"))
        let dataProtection = try #require(CapabilityRegistry.descriptor(for: "data-protection"))
        #expect(ProvisioningInspector.state(of: homeKit, in: lookup) == .provisioned("true"))
        #expect(ProvisioningInspector.state(of: weatherKit, in: lookup) == .notProvisioned)
        #expect(ProvisioningInspector.state(of: push, in: lookup) == .provisioned("aps-environment: development"))
        if case .unknown = ProvisioningInspector.state(of: dataProtection, in: lookup) {} else { Issue.record("code-signature-only keys must stay unknown") }
    }

    @Test func missingProfileNeverClaimsAState() throws {
        let lookup = ProvisioningLookup.missing("No profile")
        let homeKit = try #require(CapabilityRegistry.descriptor(for: "homekit"))
        #expect(ProvisioningInspector.state(of: homeKit, in: lookup) == .unknown("No profile"))
        #expect(ProvisioningInspector.parse(Data("not a profile".utf8))?.name == nil)
    }
}
