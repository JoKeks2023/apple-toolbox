import Testing
import Foundation
@testable import AppleToolbox

struct NFCProtocolTests {

    @Test func hexRoundTrip() {
        let data = Data([0xD2, 0x76, 0x00, 0x00, 0x85, 0x01, 0x01])
        #expect(NFCHex.string(data) == "D2 76 00 00 85 01 01")
        #expect(NFCHex.string(data, separator: "") == "D2760000850101")
        #expect(NFCHex.data("d2 76:00 00 85 01 01") == data)
        #expect(NFCHex.data("ABC") == nil)
        #expect(NFCHex.data("") == nil)
        #expect(NFCHex.data("ZZ") == nil)
    }

    @Test func selectByNameEncodesTheAID() {
        let aid = Data([0xA0, 0x00, 0x00, 0x02, 0x47, 0x10, 0x01])
        #expect(ISO7816Command.selectByName(aid) == Data([0x00, 0xA4, 0x04, 0x00, 0x07]) + aid + Data([0x00]))
    }

    @Test func statusWordsAreDescribed() {
        #expect(ISO7816StatusWord(sw1: 0x90, sw2: 0x00).meaning == "Success")
        #expect(ISO7816StatusWord(sw1: 0x90, sw2: 0x00).isSuccess)
        #expect(ISO7816StatusWord(sw1: 0x61, sw2: 0x10).isSuccess)
        #expect(ISO7816StatusWord(sw1: 0x61, sw2: 0x10).meaning.contains("16 more"))
        #expect(ISO7816StatusWord(sw1: 0x6A, sw2: 0x82).meaning.contains("not found"))
        #expect(!ISO7816StatusWord(sw1: 0x6A, sw2: 0x82).isSuccess)
        #expect(ISO7816StatusWord(sw1: 0x63, sw2: 0xC2).meaning.contains("2 retries"))
        #expect(ISO7816StatusWord(sw1: 0x6D, sw2: 0x00).hex == "6D00")
        #expect(ISO7816StatusWord(sw1: 0x6A, sw2: 0x99).meaning == "Checking error (6A99)")
        #expect(ISO7816StatusWord(sw1: 0x12, sw2: 0x34).meaning.hasPrefix("Unknown"))
    }

    @Test func declaredIdentifiersAreReadFromTheInfoDictionary() {
        let info: [String: Any] = [NFCInfoPlist.iso7816SelectIdentifiersKey: ["d2760000850101", "XYZ", "A0000002471001"]]
        #expect(NFCInfoPlist.declaredHexValues(for: NFCInfoPlist.iso7816SelectIdentifiersKey, in: info) == ["D2760000850101", "A0000002471001"])
        #expect(NFCInfoPlist.declaredHexValues(for: NFCInfoPlist.feliCaSystemCodesKey, in: info).isEmpty)
        #expect(NFCInfoPlist.declaredHexValues(for: NFCInfoPlist.feliCaSystemCodesKey, in: nil).isEmpty)
    }

    @Test func appInfoPlistDeclaresOnlyNamedNonPaymentIdentifiers() throws {
        // Unit tests run inside the app host, so the main bundle carries the app's Info.plist.
        let info = try #require(Bundle.main.infoDictionary)
        let aids = NFCInfoPlist.declaredHexValues(for: NFCInfoPlist.iso7816SelectIdentifiersKey, in: info)
        let codes = NFCInfoPlist.declaredHexValues(for: NFCInfoPlist.feliCaSystemCodesKey, in: info)
        #expect(!aids.isEmpty)
        #expect(!codes.isEmpty)
        for aid in aids {
            #expect(NFCKnownIdentifiers.applicationName(forAID: aid) != "Custom application", "\(aid)")
            // Payment system environment AIDs ("1PAY.SYS.DDF01", "2PAY.SYS.DDF01") are not selectable with NFCTagReaderSession.
            #expect(!aid.hasPrefix("315041592E") && !aid.hasPrefix("325041592E"), "\(aid)")
        }
        for code in codes {
            #expect(!code.contains("FF"), "FeliCa wildcard \(code)")
            #expect(NFCKnownIdentifiers.systemCodeName(code) != "Custom system code", "\(code)")
        }
    }

    @Test func icManufacturerNames() {
        #expect(NFCKnownIdentifiers.icManufacturer(0x04) == "NXP Semiconductors (0x04)")
        #expect(NFCKnownIdentifiers.icManufacturer(0x07) == "Texas Instruments (0x07)")
        #expect(NFCKnownIdentifiers.icManufacturer(0x7E) == "Unknown manufacturer (0x7E)")
    }

    @Test func ndefRecordValidation() {
        #expect(NDEFRecordKind.uri.validationError(for: "https://developer.apple.com") == nil)
        #expect(NDEFRecordKind.uri.validationError(for: "tel:+491234") == nil)
        #expect(NDEFRecordKind.uri.validationError(for: "developer apple com") != nil)
        #expect(NDEFRecordKind.uri.validationError(for: "   ") != nil)
        #expect(NDEFRecordKind.text.validationError(for: "Hello tag") == nil)
        #expect(NDEFRecordKind.text.validationError(for: String(repeating: "a", count: 5000)) != nil)
    }

    @Test func historyKeepsTheNewestTagsFirst() {
        func tag(_ n: Int) -> NFCInspectedTag {
            NFCInspectedTag(id: UUID(), date: Date(timeIntervalSince1970: TimeInterval(n)), technology: "ISO 15693", identifier: "\(n)", fields: [], exchanges: [], ndefRecords: [])
        }
        var history: [NFCInspectedTag] = []
        for n in 0..<5 { history = NFCInspectorHistory.appending(tag(n), to: history, limit: 3) }
        #expect(history.map(\.identifier) == ["4", "3", "2"])
        let again = NFCInspectorHistory.appending(history[1], to: history, limit: 3)
        #expect(again.map(\.identifier) == ["3", "4", "2"])
    }

    @Test func historyPersistsAsJSON() throws {
        let defaults = try #require(UserDefaults(suiteName: "nfc-inspector-tests"))
        defer { defaults.removePersistentDomain(forName: "nfc-inspector-tests") }
        let exchange = NFCAPDUExchange(title: "SELECT", command: "00 A4 04 00", response: "No data", statusWord: "6A82", meaning: "Error: file or application not found", error: nil)
        let tag = NFCInspectedTag(id: UUID(), date: Date(timeIntervalSince1970: 1_000), technology: "ISO 7816", identifier: "04 A1", fields: [NFCTagField(label: "PACE support", value: "No")], exchanges: [exchange], ndefRecords: ["URI · https://apple.com"])
        NFCInspectorHistory.save([tag], to: defaults)
        #expect(NFCInspectorHistory.load(from: defaults) == [tag])
        NFCInspectorHistory.save([], to: defaults)
        #expect(NFCInspectorHistory.load(from: defaults).isEmpty)
    }

    @Test func commandAPDUCases() throws {
        let case1 = try #require(ISO7816CommandAPDU(Data([0x00, 0xB0, 0x00, 0x00])))
        #expect(case1.data.isEmpty && case1.expectedLength == nil)
        let case2 = try #require(ISO7816CommandAPDU(Data([0x00, 0xB0, 0x00, 0x00, 0x00])))
        #expect(case2.expectedLength == 256)
        let aid = Data([0xF0, 0x41, 0x54, 0x42, 0x44, 0x45, 0x4D, 0x4F])
        let case3 = try #require(ISO7816CommandAPDU(Data([0x00, 0xA4, 0x04, 0x00, 0x08]) + aid))
        #expect(case3.data == aid && case3.expectedLength == nil && case3.isSelectByName)
        let case4 = try #require(ISO7816CommandAPDU(ISO7816Command.selectByName(aid)))
        #expect(case4.data == aid && case4.expectedLength == 256)
        let extendedLe = try #require(ISO7816CommandAPDU(Data([0x00, 0xB0, 0x00, 0x00, 0x00, 0x01, 0x00])))
        #expect(extendedLe.expectedLength == 256)
        let extended = try #require(ISO7816CommandAPDU(Data([0x00, 0xD6, 0x00, 0x00, 0x00, 0x00, 0x02, 0xAA, 0xBB, 0x00, 0x00])))
        #expect(extended.data == Data([0xAA, 0xBB]) && extended.expectedLength == 65536)
        #expect(ISO7816CommandAPDU(Data([0x00, 0xA4, 0x04])) == nil)
        #expect(ISO7816CommandAPDU(Data([0x00, 0xA4, 0x04, 0x00, 0x05, 0x01])) == nil)
    }

    @Test func demoCardAnswersOnlyItsOwnSelect() throws {
        let aid = try #require(NFCHex.data(CardEmulationDemo.aidHex))
        #expect((5...16).contains(aid.count))
        #expect(CardEmulationDemo.aidHex.hasPrefix("F"), "proprietary, unregistered AID category")
        let selected = CardEmulationDemo.response(to: ISO7816Command.selectByName(aid))
        #expect(selected.response == CardEmulationDemo.greeting + Data([0x90, 0x00]))
        #expect(selected.note.contains("9000"))
        let otherAID = CardEmulationDemo.response(to: ISO7816Command.selectByName(Data([0xA0, 0x00, 0x00, 0x02, 0x47, 0x10, 0x01])))
        #expect(otherAID.response == Data([0x6A, 0x82]))
        #expect(CardEmulationDemo.response(to: Data([0x00, 0xB0, 0x00, 0x00, 0x00])).response == Data([0x6D, 0x00]))
        #expect(CardEmulationDemo.response(to: Data([0x00])).response == Data([0x67, 0x00]))
    }
}

struct MiFareCommandTests {

    @Test func ultralightCommands() {
        #expect(MiFareCommand.ultralightGetVersion == Data([0x60]))
        #expect(MiFareCommand.ultralightRead(page: 4) == Data([0x30, 0x04]))
    }

    @Test func desfireCommandsAreWrappedInISO7816() {
        #expect(MiFareCommand.desfireGetVersion == Data([0x90, 0x60, 0x00, 0x00, 0x00]))
        #expect(MiFareCommand.desfireAdditionalFrame == Data([0x90, 0xAF, 0x00, 0x00, 0x00]))
        #expect(MiFareCommand.desfireWrapped(0x5A, data: Data([0x01, 0x02, 0x03])) == Data([0x90, 0x5A, 0x00, 0x00, 0x03, 0x01, 0x02, 0x03, 0x00]))
    }

    @Test func desfireStatusWords() {
        #expect(MiFareCommand.desfireHasMoreFrames(sw1: 0x91, sw2: 0xAF))
        #expect(!MiFareCommand.desfireHasMoreFrames(sw1: 0x91, sw2: 0x00))
        #expect(MiFareCommand.desfireStatus(sw1: 0x91, sw2: 0x00) == "Operation OK")
        #expect(MiFareCommand.desfireStatus(sw1: 0x91, sw2: 0x9D) == "Permission denied")
    }

    @Test func decodesNTAG215Version() throws {
        let version = try #require(UltralightVersion(Data([0x00, 0x04, 0x04, 0x02, 0x01, 0x00, 0x11, 0x03])))
        #expect(version.vendorName == "NXP")
        #expect(version.productName == "NTAG215")
        #expect(version.storageDescription == "256–512 bytes")
        #expect(UltralightVersion(Data([0x00, 0x04])) == nil)
    }

    @Test func clampsISO15693BlockRanges() {
        #expect(ISO15693BlockRange.clamp(start: 0, count: 4, totalBlocks: 28) == 0...3)
        #expect(ISO15693BlockRange.clamp(start: 24, count: 8, totalBlocks: 28) == 24...27)
        #expect(ISO15693BlockRange.clamp(start: 30, count: 4, totalBlocks: 28) == nil)
        #expect(ISO15693BlockRange.clamp(start: 2, count: 4, totalBlocks: -1) == 2...5)
    }
}
