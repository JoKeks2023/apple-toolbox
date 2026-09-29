import Testing
import Foundation
import CoreBluetooth
@testable import AppleToolbox

struct GATTFormattingTests {

    @Test func hexIsUppercaseAndSpaceSeparated() {
        #expect(GATTFormatting.hex(Data([0x0A, 0xFF, 0x10])) == "0A FF 10")
        #expect(GATTFormatting.hex(Data()) == "")
    }

    @Test func parsesCommonHexNotations() throws {
        let expected = Data([0x01, 0xA0, 0xFF])
        #expect(try GATTFormatting.parseHex("01 A0 FF") == expected)
        #expect(try GATTFormatting.parseHex("01a0ff") == expected)
        #expect(try GATTFormatting.parseHex("0x01 0xA0 0xff") == expected)
        #expect(try GATTFormatting.parseHex("01:a0:FF") == expected)
        #expect(try GATTFormatting.parseHex("0x01A0FF") == expected)
        #expect(try GATTFormatting.parseHex("") == Data())
    }

    @Test func rejectsInvalidHex() {
        #expect(throws: GATTValueError.oddHexDigitCount) { try GATTFormatting.parseHex("ABC") }
        #expect(throws: GATTValueError.invalidHexCharacter("zz")) { try GATTFormatting.parseHex("01 zz") }
        #expect(throws: GATTValueError.invalidHexCharacter("0x")) { try GATTFormatting.parseHex("0x") }
    }

    @Test func encodesTextAsUTF8() throws {
        #expect(try GATTFormatting.encode("Hi ✓", as: .utf8) == Data("Hi ✓".utf8))
        #expect(try GATTFormatting.encode("48 69", as: .hex) == Data("Hi".utf8))
    }

    @Test func showsTextOnlyForPrintableUTF8() {
        #expect(GATTFormatting.utf8(Data("Toolbox\n".utf8)) == "Toolbox\n")
        #expect(GATTFormatting.utf8(Data([0x00, 0x41])) == nil)
        #expect(GATTFormatting.utf8(Data([0xFF, 0xFE])) == nil)
        #expect(GATTFormatting.utf8(Data()) == nil)
    }

    @Test func summarisesValues() {
        #expect(GATTFormatting.summary(nil) == "No value read yet")
        #expect(GATTFormatting.summary(Data()) == "0 B (empty)")
        #expect(GATTFormatting.summary(Data([0x64])) == "1 B · 64 · “d”")
        #expect(GATTFormatting.summary(Data([0x00, 0x01])) == "2 B · 00 01")
    }

    @Test func describesDescriptorValues() {
        #expect(GATTFormatting.descriptorValue(nil, uuid: "2902") == "Not read yet")
        #expect(GATTFormatting.descriptorValue(NSNumber(value: 1), uuid: "2902") == "0x0001 · notifications enabled")
        #expect(GATTFormatting.descriptorValue(NSNumber(value: 0), uuid: "2902") == "0x0000 · disabled")
        #expect(GATTFormatting.descriptorValue(NSNumber(value: 3), uuid: "00002902-0000-1000-8000-00805f9b34fb") == "0x0003 · notifications + indications enabled")
        #expect(GATTFormatting.descriptorValue("Battery", uuid: "2901") == "“Battery”")
        #expect(GATTFormatting.descriptorValue(Data([0x04, 0x00]), uuid: "2904") == "2 B · 04 00")
    }

    @Test func namesPropertiesInBitOrder() {
        let properties: CBCharacteristicProperties = [.notify, .read, .write]
        #expect(GATTFormatting.propertyNames(properties) == ["Read", "Write", "Notify"])
        #expect(GATTFormatting.propertyNames([]) == [])
    }
}

struct GATTNamesTests {

    @Test func reducesBaseUUIDsToTheirShortForm() {
        #expect(GATTNames.shortForm("0000180f-0000-1000-8000-00805f9b34fb") == "180F")
        #expect(GATTNames.shortForm("2a19") == "2A19")
        #expect(GATTNames.shortForm("7905f431-b5ce-4e99-a40f-4b1e122d00d0") == "7905F431-B5CE-4E99-A40F-4B1E122D00D0")
    }

    @Test func knowsCommonSIGAndAppleUUIDs() {
        #expect(GATTNames.name(for: "180F") == "Battery")
        #expect(GATTNames.name(for: "00002A19-0000-1000-8000-00805F9B34FB") == "Battery Level")
        #expect(GATTNames.name(for: "2902") == "Client Characteristic Configuration")
        #expect(GATTNames.name(for: "7905F431-B5CE-4E99-A40F-4B1E122D00D0") == "Apple Notification Center Service")
        #expect(GATTNames.name(for: "FFFF") == nil)
    }
}
