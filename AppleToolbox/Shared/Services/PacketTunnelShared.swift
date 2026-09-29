import Foundation

// Shared by the iOS app and the `AppleToolbox Packet Tunnel` extension: the test range the tunnel claims, the messages
// the app sends it, and the packet statistics it answers with.

/// The only addresses the demo tunnel routes: 198.18.0.0/15, the RFC 2544 benchmarking range, which is never used on the
/// internet. Every other packet keeps using the normal network, and nothing the tunnel reads is forwarded anywhere.
nonisolated enum TunnelTestRange {
    static let network = "198.18.0.0"
    static let subnetMask = "255.254.0.0"
    static let prefixLength = 15
    /// The tunnel interface's own address.
    static let interfaceAddress = "198.18.0.2"
    /// Where the app sends its test datagrams (UDP discard port).
    static let testTarget = "198.18.0.1"
    static let testPort: UInt16 = 9
    /// NETunnelProviderProtocol needs a server address; the provider never contacts it.
    static let serverAddress = "127.0.0.1"

    static var cidr: String { "\(network)/\(prefixLength)" }

    /// Dotted-quad IPv4 address as a big-endian integer.
    static func ipv4(_ address: String) -> UInt32? {
        let parts = address.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }
        var value: UInt32 = 0
        for part in parts {
            guard let octet = UInt8(part) else { return nil }
            value = value << 8 | UInt32(octet)
        }
        return value
    }

    static func contains(_ address: String) -> Bool {
        guard let value = ipv4(address), let base = ipv4(network), let mask = ipv4(subnetMask) else { return false }
        return value & mask == base & mask
    }
}

/// What the app asks the provider with `sendProviderMessage`.
nonisolated enum TunnelAppMessage: String, CaseIterable, Sendable {
    case stats
    case reset

    var data: Data { Data(rawValue.utf8) }

    /// Unknown messages are treated as a stats request.
    init(data: Data) {
        self = TunnelAppMessage(rawValue: String(decoding: data, as: UTF8.self)) ?? .stats
    }
}

/// The header fields of one IPv4 packet the tunnel read.
nonisolated struct IPv4PacketSummary: Equatable, Sendable {
    let source: String
    let destination: String
    let protocolNumber: UInt8
    let totalLength: Int
    /// Destination port for TCP and UDP.
    let destinationPort: UInt16?

    init?(_ packet: Data) {
        let bytes = [UInt8](packet)
        guard bytes.count >= 20, bytes[0] >> 4 == 4 else { return nil }
        let headerLength = Int(bytes[0] & 0x0f) * 4
        guard headerLength >= 20, bytes.count >= headerLength else { return nil }
        totalLength = Int(bytes[2]) << 8 | Int(bytes[3])
        protocolNumber = bytes[9]
        source = bytes[12..<16].map(String.init).joined(separator: ".")
        destination = bytes[16..<20].map(String.init).joined(separator: ".")
        let carriesPorts = protocolNumber == 6 || protocolNumber == 17
        destinationPort = carriesPorts && bytes.count >= headerLength + 4
            ? UInt16(bytes[headerLength + 2]) << 8 | UInt16(bytes[headerLength + 3]) : nil
    }

    var protocolName: String {
        switch protocolNumber {
        case 1: "ICMP"
        case 6: "TCP"
        case 17: "UDP"
        default: "IP protocol \(protocolNumber)"
        }
    }

    var description: String {
        "\(protocolName) \(source) → \(destination)\(destinationPort.map { ":\($0)" } ?? "") (\(totalLength) bytes)"
    }
}

/// Counters the provider keeps while the tunnel runs; sent to the app as JSON.
nonisolated struct TunnelStats: Codable, Equatable, Sendable {
    var startedAt: Date?
    var packets = 0
    var bytes = 0
    var byProtocol: [String: Int] = [:]
    var lastPacket: String?
    var lastPacketAt: Date?

    /// Counts one packet the tunnel read. The version nibble tells IPv4 from IPv6.
    mutating func record(_ packet: Data, at date: Date) {
        packets += 1
        bytes += packet.count
        lastPacketAt = date
        if let summary = IPv4PacketSummary(packet) {
            byProtocol[summary.protocolName, default: 0] += 1
            lastPacket = summary.description
        } else if packet.first.map({ $0 >> 4 == 6 }) == true {
            byProtocol["IPv6", default: 0] += 1
            lastPacket = "IPv6 packet (\(packet.count) bytes)"
        } else {
            byProtocol["Unparsed", default: 0] += 1
            lastPacket = "Unparsed packet (\(packet.count) bytes)"
        }
    }

    var encoded: Data? { try? JSONEncoder().encode(self) }

    static func decode(_ data: Data?) -> TunnelStats? {
        data.flatMap { try? JSONDecoder().decode(TunnelStats.self, from: $0) }
    }

    /// "UDP 3 · ICMP 1", largest count first.
    var protocolBreakdown: String {
        byProtocol.isEmpty ? "none" : byProtocol.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
            .map { "\($0.key) \($0.value)" }.joined(separator: " · ")
    }

    var summary: String {
        var lines = ["\(packets) packet\(packets == 1 ? "" : "s") · \(ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .memory))",
                     "by protocol: \(protocolBreakdown)"]
        if let lastPacket {
            lines.append("last: \(lastPacket)\(lastPacketAt.map { " at \($0.formatted(date: .omitted, time: .standard))" } ?? "")")
        }
        return lines.joined(separator: "\n")
    }
}
