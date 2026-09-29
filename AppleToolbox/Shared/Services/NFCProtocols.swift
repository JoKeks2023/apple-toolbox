import Foundation

/// Hex rendering and parsing for NFC identifiers, AIDs and APDUs.
nonisolated enum NFCHex {
    static func string(_ data: Data, separator: String = " ") -> String {
        data.map { String(format: "%02X", $0) }.joined(separator: separator)
    }

    /// Parses hex digits, ignoring spaces and colons. Returns nil for odd lengths, empty input or non-hex characters.
    static func data(_ hex: String) -> Data? {
        let digits = Array(hex.filter { !$0.isWhitespace && $0 != ":" })
        guard !digits.isEmpty, digits.count.isMultiple(of: 2) else { return nil }
        var data = Data(capacity: digits.count / 2)
        for index in stride(from: 0, to: digits.count, by: 2) {
            guard let byte = UInt8(String(digits[index...index + 1]), radix: 16) else { return nil }
            data.append(byte)
        }
        return data
    }
}

/// ISO/IEC 7816-4 status word returned after every response APDU.
nonisolated struct ISO7816StatusWord: Equatable, Sendable {
    let sw1: UInt8
    let sw2: UInt8

    var hex: String { String(format: "%02X%02X", sw1, sw2) }
    /// 9000, or 61XX (success with more response bytes waiting).
    var isSuccess: Bool { (sw1 == 0x90 && sw2 == 0x00) || sw1 == 0x61 }

    var meaning: String {
        switch (sw1, sw2) {
        case (0x90, 0x00): "Success"
        case (0x61, _): "Success, \(sw2 == 0 ? 256 : Int(sw2)) more response bytes available (GET RESPONSE)"
        case (0x62, 0x00): "Warning: no information given, memory unchanged"
        case (0x62, 0x81): "Warning: part of the returned data may be corrupted"
        case (0x62, 0x82): "Warning: end of file reached before Le bytes were read"
        case (0x62, 0x83): "Warning: selected file or application is deactivated"
        case (0x62, 0x84): "Warning: file control information is not formatted per ISO 7816-4"
        case (0x63, 0x00): "Warning: verification failed"
        case (0x63, let low) where low & 0xF0 == 0xC0: "Warning: verification failed, \(low & 0x0F) retries left"
        case (0x64, 0x00): "Error: execution error, memory unchanged"
        case (0x65, 0x81): "Error: memory failure"
        case (0x67, 0x00): "Error: wrong length"
        case (0x68, 0x81): "Error: logical channel not supported"
        case (0x68, 0x82): "Error: secure messaging not supported"
        case (0x69, 0x82): "Error: security status not satisfied"
        case (0x69, 0x83): "Error: authentication method blocked"
        case (0x69, 0x85): "Error: conditions of use not satisfied"
        case (0x69, 0x86): "Error: command not allowed (no current file)"
        case (0x6A, 0x80): "Error: incorrect parameters in the data field"
        case (0x6A, 0x81): "Error: function not supported"
        case (0x6A, 0x82): "Error: file or application not found"
        case (0x6A, 0x86): "Error: incorrect parameters P1-P2"
        case (0x6A, 0x88): "Error: referenced data not found"
        case (0x6B, 0x00): "Error: wrong parameters P1-P2"
        case (0x6C, _): "Error: wrong Le field, \(sw2 == 0 ? 256 : Int(sw2)) bytes available"
        case (0x6D, 0x00): "Error: instruction code not supported"
        case (0x6E, 0x00): "Error: class not supported"
        case (0x6F, 0x00): "Error: no precise diagnosis"
        case (0x62, _), (0x63, _): "Warning (\(hex))"
        case (0x64...0x66, _): "Execution error (\(hex))"
        case (0x67...0x6F, _): "Checking error (\(hex))"
        default: "Unknown status word (\(hex))"
        }
    }
}

/// Command APDUs the toolbox sends. Only interindustry commands from ISO/IEC 7816-4.
nonisolated enum ISO7816Command {
    /// SELECT by DF name (AID): CLA 00, INS A4, P1 04 (select by name), P2 00 (first occurrence, return FCI), Lc, AID, Le 00 (up to 256 bytes).
    static func selectByName(_ aid: Data) -> Data {
        Data([0x00, 0xA4, 0x04, 0x00, UInt8(aid.count)]) + aid + Data([0x00])
    }
}

/// Native MIFARE commands sent with sendMiFareCommand / sendMiFareISO7816Command.
nonisolated enum MiFareCommand {
    /// Ultralight / NTAG GET_VERSION (0x60): returns 8 bytes (vendor, type, subtype, version, storage size, protocol).
    static let ultralightGetVersion = Data([0x60])

    /// Ultralight / NTAG READ (0x30, page): returns 16 bytes, i.e. four 4-byte pages starting at `page` (wrapping at the end).
    static func ultralightRead(page: UInt8) -> Data { Data([0x30, page]) }

    /// A DESFire native command wrapped in ISO 7816-4: CLA 90, INS = native command, P1 P2 00, [Lc data], Le 00.
    static func desfireWrapped(_ command: UInt8, data: Data = Data()) -> Data {
        var apdu = Data([0x90, command, 0x00, 0x00])
        if !data.isEmpty { apdu.append(UInt8(data.count)); apdu.append(data) }
        apdu.append(0x00)
        return apdu
    }

    /// DESFire GetVersion (native 0x60); the card answers in three frames, each but the last ending in 91 AF.
    static var desfireGetVersion: Data { desfireWrapped(0x60) }
    /// DESFire ADDITIONAL_FRAME (native 0xAF) fetches the next frame.
    static var desfireAdditionalFrame: Data { desfireWrapped(0xAF) }

    /// Status word 91 AF: more data follows.
    static func desfireHasMoreFrames(sw1: UInt8, sw2: UInt8) -> Bool { sw1 == 0x91 && sw2 == 0xAF }

    /// Meaning of a DESFire status word (SW1 91 carries the native status in SW2).
    static func desfireStatus(sw1: UInt8, sw2: UInt8) -> String {
        guard sw1 == 0x91 else { return ISO7816StatusWord(sw1: sw1, sw2: sw2).meaning }
        switch sw2 {
        case 0x00: return "Operation OK"
        case 0xAF: return "Additional frame expected"
        case 0x1C: return "Illegal command code"
        case 0x7E: return "Length error"
        case 0x9D: return "Permission denied"
        case 0xAE: return "Authentication error"
        case 0xBE: return "Boundary error"
        case 0xCA: return "Command aborted"
        default: return "DESFire status \(String(format: "%02X", sw2))"
        }
    }
}

/// Decoded answer to the Ultralight / NTAG GET_VERSION command.
nonisolated struct UltralightVersion: Equatable, Sendable {
    let vendor: UInt8
    let productType: UInt8
    let productSubtype: UInt8
    let majorVersion: UInt8
    let minorVersion: UInt8
    let storageSize: UInt8

    init?(_ data: Data) {
        guard data.count >= 8 else { return nil }
        let bytes = [UInt8](data)
        vendor = bytes[1]; productType = bytes[2]; productSubtype = bytes[3]
        majorVersion = bytes[4]; minorVersion = bytes[5]; storageSize = bytes[6]
    }

    var vendorName: String { vendor == 0x04 ? "NXP" : String(format: "0x%02X", vendor) }

    /// Product name from the NXP data sheets (NTAG21x, Ultralight EV1).
    var productName: String {
        switch (productType, storageSize) {
        case (0x04, 0x0F): "NTAG213"
        case (0x04, 0x11): "NTAG215"
        case (0x04, 0x13): "NTAG216"
        case (0x03, 0x0B): "MIFARE Ultralight EV1 (MF0UL11)"
        case (0x03, 0x0E): "MIFARE Ultralight EV1 (MF0UL21)"
        case (0x04, _): "NTAG (unknown size)"
        case (0x03, _): "MIFARE Ultralight (unknown size)"
        default: String(format: "Product type 0x%02X", productType)
        }
    }

    /// Bit 0 set means the size lies between 2^n and 2^(n+1) bytes; otherwise it is exactly 2^n bytes.
    var storageDescription: String {
        let exponent = Int(storageSize >> 1)
        guard exponent < 32 else { return String(format: "0x%02X", storageSize) }
        let base = 1 << exponent
        return storageSize & 1 == 0 ? "\(base) bytes" : "\(base)–\(base * 2) bytes"
    }
}

/// Extra read commands the inspector runs after connecting, chosen in the run view.
nonisolated struct NFCReadOptions: Equatable, Sendable {
    static let blockStartChoices = Array(0..<64)
    static let blockCountChoices = [1, 2, 4, 8, 16, 32]
    static let ultralightPageChoices: [UInt8] = stride(from: 0, through: 44, by: 4).map { UInt8($0) }

    var blockStart = 0
    var blockCount = 4
    var ultralightPage: UInt8 = 4
}

/// Block range choices for ISO 15693 reads.
nonisolated enum ISO15693BlockRange {
    /// Clamps a requested range to what the tag reports; `totalBlocks` < 0 means the tag did not report its size.
    static func clamp(start: Int, count: Int, totalBlocks: Int) -> ClosedRange<Int>? {
        guard start >= 0, count > 0 else { return nil }
        let upper = start + count - 1
        guard totalBlocks > 0 else { return start...min(upper, 255) }
        guard start < totalBlocks else { return nil }
        return start...min(upper, totalBlocks - 1, 255)
    }
}

/// A parsed ISO/IEC 7816-4 command APDU in short or extended length encoding.
nonisolated struct ISO7816CommandAPDU: Equatable, Sendable {
    let cla: UInt8
    let ins: UInt8
    let p1: UInt8
    let p2: UInt8
    let data: Data
    /// Ne, the maximum response length the reader expects; nil when the command has no Le field.
    let expectedLength: Int?

    /// Parses the four APDU cases (no data/no Le, Le only, data only, data and Le); nil when the lengths do not add up.
    init?(_ bytes: Data) {
        let bytes = [UInt8](bytes)
        guard bytes.count >= 4 else { return nil }
        cla = bytes[0]
        ins = bytes[1]
        p1 = bytes[2]
        p2 = bytes[3]
        let body = Array(bytes.dropFirst(4))
        if body.isEmpty {
            data = Data()
            expectedLength = nil
        } else if body.count == 1 {
            data = Data()
            expectedLength = body[0] == 0 ? 256 : Int(body[0])
        } else if body[0] != 0 {
            let lc = Int(body[0])
            guard body.count == 1 + lc || body.count == 2 + lc else { return nil }
            data = Data(body[1...lc])
            expectedLength = body.count == 2 + lc ? (body[1 + lc] == 0 ? 256 : Int(body[1 + lc])) : nil
        } else {
            guard body.count >= 3 else { return nil }
            let length = Int(body[1]) << 8 | Int(body[2])
            if body.count == 3 {
                data = Data()
                expectedLength = length == 0 ? 65536 : length
            } else {
                guard length > 0, body.count == 3 + length || body.count == 5 + length else { return nil }
                data = Data(body[3..<3 + length])
                if body.count == 5 + length {
                    let le = Int(body[3 + length]) << 8 | Int(body[4 + length])
                    expectedLength = le == 0 ? 65536 : le
                } else {
                    expectedLength = nil
                }
            }
        }
    }

    /// SELECT by DF name, the command a reader uses to pick an application by AID.
    var isSelectByName: Bool { ins == 0xA4 && p1 == 0x04 }
}

/// The stateless demo card behind the card emulation experiment. It is not a credential: it only answers SELECT for its
/// own proprietary AID with a fixed greeting.
nonisolated enum CardEmulationDemo {
    /// Proprietary AID (category F, not registered with ISO): F0 followed by ASCII "ATBDEMO".
    static let aidHex = "F041544244454D4F"
    static let greeting = Data("APPLE TOOLBOX DEMO".utf8)

    static func response(to command: Data) -> (response: Data, note: String) {
        guard let apdu = ISO7816CommandAPDU(command) else { return reply(Data(), 0x67, 0x00, "Malformed command APDU") }
        guard apdu.isSelectByName else { return reply(Data(), 0x6D, 0x00, "INS \(String(format: "%02X", apdu.ins)) is not implemented by the demo card") }
        guard apdu.data == NFCHex.data(aidHex) else {
            return reply(Data(), 0x6A, 0x82, "SELECT \(NFCHex.string(apdu.data, separator: "")) is not the demo AID")
        }
        return reply(greeting, 0x90, 0x00, "SELECT demo AID, answered with “APPLE TOOLBOX DEMO”")
    }

    private static func reply(_ payload: Data, _ sw1: UInt8, _ sw2: UInt8, _ context: String) -> (response: Data, note: String) {
        let status = ISO7816StatusWord(sw1: sw1, sw2: sw2)
        return (payload + Data([sw1, sw2]), "\(context) → \(status.hex) \(status.meaning)")
    }
}

/// Info.plist keys that Core NFC reads before it selects applications or polls FeliCa system codes.
nonisolated enum NFCInfoPlist {
    static let iso7816SelectIdentifiersKey = "com.apple.developer.nfc.readersession.iso7816.select-identifiers"
    static let feliCaSystemCodesKey = "com.apple.developer.nfc.readersession.felica.systemcodes"

    /// Uppercased hex strings declared under `key`; malformed entries are dropped, as Core NFC ignores them too.
    static func declaredHexValues(for key: String, in info: [String: Any]?) -> [String] {
        (info?[key] as? [String] ?? []).map { $0.uppercased() }.filter { NFCHex.data($0) != nil }
    }
}

/// Names for the public identifiers this app declares; anything else is shown as its raw hex value.
nonisolated enum NFCKnownIdentifiers {
    static func applicationName(forAID aid: String) -> String {
        switch aid.uppercased() {
        case "D2760000850101": "NFC Forum Type 4 NDEF application"
        case "A0000002471001": "ICAO eMRTD (ePassport, LDS1)"
        case "A0000006472F0001": "FIDO U2F / CTAP"
        case "A000000308000010000100": "PIV card application (NIST SP 800-73)"
        case "D27600012401": "OpenPGP card"
        default: "Custom application"
        }
    }

    static func systemCodeName(_ code: String) -> String {
        switch code.uppercased() {
        case "0003": "Transit IC (CJRC standard, e.g. Suica)"
        case "FE00": "FeliCa common area (e-money)"
        case "12FC": "NFC Forum Type 3 Tag (NDEF)"
        case "88B4": "FeliCa Lite-S"
        default: "Custom system code"
        }
    }

    /// IC manufacturer codes registered in ISO/IEC 7816-6, as reported by ISO 15693 tags.
    static func icManufacturer(_ code: Int) -> String {
        let names: [Int: String] = [
            0x01: "Motorola", 0x02: "STMicroelectronics", 0x03: "Hitachi", 0x04: "NXP Semiconductors", 0x05: "Infineon Technologies",
            0x06: "Cylink", 0x07: "Texas Instruments", 0x08: "Fujitsu", 0x09: "Matsushita", 0x0A: "NEC", 0x0B: "Oki Electric",
            0x0C: "Toshiba", 0x0D: "Mitsubishi Electric", 0x0E: "Samsung Electronics", 0x0F: "Hynix", 0x10: "LG Semiconductors",
            0x11: "Emosyn-EM Microelectronics", 0x12: "INSIDE Technology", 0x13: "ORGA Kartensysteme", 0x14: "Sharp", 0x15: "Atmel",
            0x16: "EM Microelectronic-Marin",
        ]
        return "\(names[code] ?? "Unknown manufacturer") (0x\(String(format: "%02X", code)))"
    }
}

/// One NDEF record the inspector can write.
nonisolated enum NDEFRecordKind: String, CaseIterable, Identifiable, Sendable {
    case uri = "URI"
    case text = "Text"

    var id: String { rawValue }

    /// Why `content` cannot be written as this record kind, or nil when it can.
    func validationError(for content: String) -> String? {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Enter the \(self == .uri ? "URI" : "text") to write." }
        switch self {
        case .uri:
            guard let url = URL(string: trimmed), let scheme = url.scheme, !scheme.isEmpty else {
                return "“\(trimmed)” is not a URI with a scheme, such as https://example.com."
            }
            return nil
        case .text:
            return trimmed.utf8.count > 4096 ? "Text records longer than 4 KB do not fit on common NFC tags." : nil
        }
    }
}

/// One labelled value in the inspector.
nonisolated struct NFCTagField: Codable, Equatable, Identifiable, Sendable {
    let label: String
    let value: String
    var id: String { label }
}

/// A command/response pair exchanged with an ISO 7816 tag.
nonisolated struct NFCAPDUExchange: Codable, Equatable, Identifiable, Sendable {
    var id: String { command + (statusWord ?? error ?? "") }
    let title: String
    let command: String
    let response: String?
    let statusWord: String?
    let meaning: String?
    let error: String?
}

/// Everything the inspector learned about one tag. Stored in the history, so it only holds Codable values.
nonisolated struct NFCInspectedTag: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let date: Date
    let technology: String
    let identifier: String
    let fields: [NFCTagField]
    let exchanges: [NFCAPDUExchange]
    let ndefRecords: [String]
}

/// The last inspected tags, newest first, kept in the app's own defaults.
nonisolated enum NFCInspectorHistory {
    static let key = "nfc-inspector.history"
    static let limit = 20

    static func appending(_ tag: NFCInspectedTag, to history: [NFCInspectedTag], limit: Int = limit) -> [NFCInspectedTag] {
        Array(([tag] + history.filter { $0.id != tag.id }).prefix(limit))
    }

    static func load(from defaults: UserDefaults = .standard) -> [NFCInspectedTag] {
        guard let data = defaults.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([NFCInspectedTag].self, from: data)) ?? []
    }

    static func save(_ history: [NFCInspectedTag], to defaults: UserDefaults = .standard) {
        if history.isEmpty {
            defaults.removeObject(forKey: key)
        } else if let data = try? JSONEncoder().encode(history) {
            defaults.set(data, forKey: key)
        }
    }
}
