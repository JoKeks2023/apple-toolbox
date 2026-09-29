import Foundation
#if canImport(CoreBluetooth) && !os(tvOS)
import CoreBluetooth
#endif

/// How a GATT value is entered in the explorer.
enum GATTValueFormat: String, CaseIterable, Identifiable, Sendable {
    case hex = "Hex bytes"
    case utf8 = "UTF-8 text"
    var id: String { rawValue }
}

/// ATT write request (confirmed by the peripheral) or write command (no confirmation).
enum GATTWriteKind: String, CaseIterable, Identifiable, Sendable {
    case withResponse = "With response"
    case withoutResponse = "Without response"
    var id: String { rawValue }
}

enum GATTValueError: Error, Equatable, LocalizedError {
    case invalidHexCharacter(String)
    case oddHexDigitCount

    var errorDescription: String? {
        switch self {
        case .invalidHexCharacter(let token): "“\(token)” is not a hex byte. Use pairs like 0A FF 10 or 0x0AFF10."
        case .oddHexDigitCount: "Hex input needs an even number of digits (two per byte)."
        }
    }
}

/// Pure helpers that render and parse GATT values; shared by the central and peripheral experiments.
enum GATTFormatting {
    /// Space-separated uppercase hex bytes, e.g. `0A FF 10`.
    static func hex(_ data: Data) -> String {
        data.map { String(format: "%02X", $0) }.joined(separator: " ")
    }

    /// The value as text when it is valid UTF-8 without control characters (tabs and line breaks allowed).
    static func utf8(_ data: Data) -> String? {
        guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return nil }
        let allowed: Set<Unicode.Scalar> = ["\t", "\n", "\r"]
        let printable = text.unicodeScalars.allSatisfy { !($0.properties.generalCategory == .control) || allowed.contains($0) }
        return printable ? text : nil
    }

    /// One-line summary: byte count, hex and, when printable, the UTF-8 text.
    static func summary(_ data: Data?) -> String {
        guard let data else { return "No value read yet" }
        guard !data.isEmpty else { return "0 B (empty)" }
        let text = utf8(data).map { " · “\($0)”" } ?? ""
        return "\(data.count) B · \(hex(data))\(text)"
    }

    /// Parses hex bytes separated by spaces, colons, dashes or commas; `0x` prefixes are allowed.
    static func parseHex(_ text: String) throws -> Data {
        let separators = CharacterSet(charactersIn: " :-,\n\t\r")
        var digits = ""
        for token in text.components(separatedBy: separators) where !token.isEmpty {
            let body = token.lowercased().hasPrefix("0x") ? String(token.dropFirst(2)) : token
            guard !body.isEmpty, body.allSatisfy(\.isHexDigit) else { throw GATTValueError.invalidHexCharacter(token) }
            digits += body
        }
        guard digits.count.isMultiple(of: 2) else { throw GATTValueError.oddHexDigitCount }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(digits.count / 2)
        var index = digits.startIndex
        while index < digits.endIndex {
            let next = digits.index(index, offsetBy: 2)
            guard let byte = UInt8(digits[index..<next], radix: 16) else { throw GATTValueError.invalidHexCharacter(String(digits[index..<next])) }
            bytes.append(byte)
            index = next
        }
        return Data(bytes)
    }

    static func encode(_ text: String, as format: GATTValueFormat) throws -> Data {
        switch format {
        case .hex: try parseHex(text)
        case .utf8: Data(text.utf8)
        }
    }

    /// Readable form of a descriptor value. Core Bluetooth returns NSNumber, String or Data depending on the descriptor type.
    static func descriptorValue(_ value: Any?, uuid: String) -> String {
        guard let value else { return "Not read yet" }
        switch value {
        case let number as NSNumber:
            let raw = number.uint16Value
            switch GATTNames.shortForm(uuid) {
            case "2902":
                var flags: [String] = []
                if raw & 0x1 != 0 { flags.append("notifications") }
                if raw & 0x2 != 0 { flags.append("indications") }
                return String(format: "0x%04X · ", raw) + (flags.isEmpty ? "disabled" : flags.joined(separator: " + ") + " enabled")
            case "2900":
                var flags: [String] = []
                if raw & 0x1 != 0 { flags.append("reliable write") }
                if raw & 0x2 != 0 { flags.append("writable auxiliaries") }
                return String(format: "0x%04X · ", raw) + (flags.isEmpty ? "none" : flags.joined(separator: ", "))
            default:
                return number.stringValue
            }
        case let text as String:
            return "“\(text)”"
        case let data as Data:
            return summary(data)
        default:
            return String(describing: value)
        }
    }
}

/// Names for common Bluetooth SIG-assigned numbers and Apple-documented services.
enum GATTNames {
    /// SIG UUIDs built on the Bluetooth base UUID reduce to their 16-bit form; everything else is uppercased.
    static func shortForm(_ uuid: String) -> String {
        let upper = uuid.uppercased()
        let baseSuffix = "-0000-1000-8000-00805F9B34FB"
        if upper.count == 36, upper.hasSuffix(baseSuffix), upper.hasPrefix("0000") {
            return String(upper.dropFirst(4).prefix(4))
        }
        return upper
    }

    static func name(for uuid: String) -> String? { known[shortForm(uuid)] }

    private static let known: [String: String] = [
        // Services
        "1800": "Generic Access", "1801": "Generic Attribute", "1802": "Immediate Alert", "1803": "Link Loss",
        "1804": "Tx Power", "1805": "Current Time", "1808": "Glucose", "1809": "Health Thermometer",
        "180A": "Device Information", "180D": "Heart Rate", "180F": "Battery", "1810": "Blood Pressure",
        "1811": "Alert Notification", "1812": "Human Interface Device", "1814": "Running Speed and Cadence",
        "1816": "Cycling Speed and Cadence", "1818": "Cycling Power", "1819": "Location and Navigation",
        "181A": "Environmental Sensing", "181C": "User Data", "181D": "Weight Scale", "1822": "Pulse Oximeter",
        "1826": "Fitness Machine",
        "7905F431-B5CE-4E99-A40F-4B1E122D00D0": "Apple Notification Center Service",
        "89D3502B-0F36-433A-8EF4-C502AD55F8DC": "Apple Media Service",
        // Characteristics
        "2A00": "Device Name", "2A01": "Appearance", "2A04": "Peripheral Preferred Connection Parameters",
        "2A05": "Service Changed", "2A06": "Alert Level", "2A07": "Tx Power Level", "2A19": "Battery Level",
        "2A1C": "Temperature Measurement", "2A23": "System ID", "2A24": "Model Number String", "2A25": "Serial Number String",
        "2A26": "Firmware Revision String", "2A27": "Hardware Revision String", "2A28": "Software Revision String",
        "2A29": "Manufacturer Name String", "2A2B": "Current Time", "2A37": "Heart Rate Measurement",
        "2A38": "Body Sensor Location", "2A39": "Heart Rate Control Point", "2A4A": "HID Information",
        "2A4B": "Report Map", "2A4D": "Report", "2A50": "PnP ID", "2A5B": "CSC Measurement",
        "2A63": "Cycling Power Measurement", "2A6D": "Pressure", "2A6E": "Temperature", "2A6F": "Humidity",
        "2AA6": "Central Address Resolution",
        // Descriptors
        "2900": "Characteristic Extended Properties", "2901": "Characteristic User Description",
        "2902": "Client Characteristic Configuration", "2903": "Server Characteristic Configuration",
        "2904": "Characteristic Presentation Format", "2905": "Characteristic Aggregate Format", "2908": "Report Reference",
    ]
}

#if canImport(CoreBluetooth) && !os(tvOS)
extension GATTFormatting {
    /// Names of the GATT properties a characteristic declares, in Core Bluetooth's bit order.
    static func propertyNames(_ properties: CBCharacteristicProperties) -> [String] {
        let names: [(CBCharacteristicProperties, String)] = [
            (.broadcast, "Broadcast"), (.read, "Read"), (.writeWithoutResponse, "Write without response"), (.write, "Write"),
            (.notify, "Notify"), (.indicate, "Indicate"), (.authenticatedSignedWrites, "Signed write"),
            (.extendedProperties, "Extended properties"), (.notifyEncryptionRequired, "Notify (encrypted)"),
            (.indicateEncryptionRequired, "Indicate (encrypted)"),
        ]
        return names.filter { properties.contains($0.0) }.map(\.1)
    }
}
#endif
