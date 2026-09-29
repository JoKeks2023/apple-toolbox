import Testing
import Foundation
@testable import AppleToolbox

struct AccessorySetupKitDeclarationTests {
    private let service = "D6417001-D406-4671-BE24-908130E6DD24"

    @Test func reportsEveryMissingEntryWithoutADeclaration() {
        let declaration = AccessorySetupKitDeclaration(infoDictionary: [:])
        #expect(declaration.missingEntries(serviceUUID: service, nameSubstring: "Toolbox").count == 3)
    }

    @Test func acceptsAMatchingDeclaration() {
        let declaration = AccessorySetupKitDeclaration(infoDictionary: [
            "NSAccessorySetupKitSupports": ["Bluetooth"],
            "NSAccessorySetupBluetoothServices": [service.lowercased()],
            "NSAccessorySetupBluetoothNames": ["Toolbox"],
        ])
        #expect(declaration.missingEntries(serviceUUID: service, nameSubstring: "Toolbox").isEmpty)
    }

    @Test func wiFiOnlyDoesNotCoverABluetoothItem() {
        let declaration = AccessorySetupKitDeclaration(infoDictionary: ["NSAccessorySetupKitSupports": ["WiFi"]])
        #expect(declaration.missingEntries(serviceUUID: service, nameSubstring: "Toolbox").first == "NSAccessorySetupKitSupports → Bluetooth")
    }

    @Test func thisBuildMatchesTheLiveStatus() {
        let missing = AccessorySetupKitDeclaration.current.missingEntries(serviceUUID: ToolboxGATTProfile.serviceUUID, nameSubstring: ToolboxGATTProfile.localName)
        #expect(ExperimentAvailability.accessorySetupKit() == (missing.isEmpty ? .available : .unavailable))
    }
}

struct MIDIMessageFormatterTests {

    @Test func namesNotesWithMiddleCAsC4() {
        #expect(MIDIMessageFormatter.noteName(60) == "C4")
        #expect(MIDIMessageFormatter.noteName(61) == "C#4")
        #expect(MIDIMessageFormatter.noteName(0) == "C-1")
        #expect(MIDIMessageFormatter.noteName(127) == "G9")
    }

    @Test func describesChannelVoiceMessages() {
        #expect(MIDIMessageFormatter.describe([0x2090_3C64]) == "Note On · ch 1 · C4 (60) · velocity 100")
        #expect(MIDIMessageFormatter.describe([0x2090_3C00]) == "Note Off · ch 1 · C4 (60) · Note On with velocity 0")
        #expect(MIDIMessageFormatter.describe([0x2083_4540]) == "Note Off · ch 4 · A4 (69) · velocity 64")
        #expect(MIDIMessageFormatter.describe([0x20B0_0764]) == "Control Change · ch 1 · CC 7 = 100")
        #expect(MIDIMessageFormatter.describe([0x20C9_0500]) == "Program Change · ch 10 · program 5")
        #expect(MIDIMessageFormatter.describe([0x20E0_0040]) == "Pitch Bend · ch 1 · 8192 (+0)")
        #expect(MIDIMessageFormatter.describe([0x20E0_0000]) == "Pitch Bend · ch 1 · 0 (-8192)")
    }

    @Test func describesSystemAndSysExMessages() {
        #expect(MIDIMessageFormatter.describe([0x10F8_0000]) == "Timing Clock")
        #expect(MIDIMessageFormatter.describe([0x10F2_0001]) == "Song Position · 128")
        #expect(MIDIMessageFormatter.describe([0x3006_7E7F, 0x0601_0000]) == "SysEx (complete) · 6 bytes")
    }

    @Test func splitsPacketsByMessageType() {
        let words: [UInt32] = [0x2090_3C64, 0x3006_7E7F, 0x0601_0000, 0x10F8_0000]
        #expect(MIDIMessageFormatter.split(words) == [[0x2090_3C64], [0x3006_7E7F, 0x0601_0000], [0x10F8_0000]])
        #expect(MIDIMessageFormatter.split([0x4090_3C00]) == [[0x4090_3C00]])
    }

    @Test func formatsRawWords() {
        #expect(MIDIMessageFormatter.hex([0x2090_3C64, 0x0000_0001]) == "20903C64 00000001")
    }
}

struct UnconfiguredAccessoryTests {

    @Test func decodesAccessoryProperties() {
        #expect(UnconfiguredAccessoryInfo.features(rawValue: 0) == [])
        #expect(UnconfiguredAccessoryInfo.features(rawValue: 0b101) == ["AirPlay", "HomeKit"])
        #expect(UnconfiguredAccessoryInfo.features(rawValue: 0b010) == ["AirPrint"])
    }
}
