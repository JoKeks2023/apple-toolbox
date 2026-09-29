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
}
