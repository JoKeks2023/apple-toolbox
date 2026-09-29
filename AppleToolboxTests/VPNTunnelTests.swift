import Testing
import Foundation
@testable import AppleToolbox

struct PacketTunnelSharedTests {

    /// IPv4 header (20 bytes) + UDP header (8 bytes) + payload.
    private func udpPacket(to destination: [UInt8], port: UInt16, payload: Int = 4) -> Data {
        let total = 28 + payload
        var bytes: [UInt8] = [0x45, 0, UInt8(total >> 8), UInt8(total & 0xff), 0, 0, 0, 0, 64, 17, 0, 0, 198, 18, 0, 2] + destination
        bytes += [0xc3, 0x50, UInt8(port >> 8), UInt8(port & 0xff), 0, UInt8(8 + payload), 0, 0]
        bytes += [UInt8](repeating: 0x41, count: payload)
        return Data(bytes)
    }

    @Test func knowsTheTestRange() {
        #expect(TunnelTestRange.contains("198.18.0.1"))
        #expect(TunnelTestRange.contains("198.19.255.255"))
        #expect(!TunnelTestRange.contains("198.20.0.0"))
        #expect(!TunnelTestRange.contains("10.0.0.1"))
        #expect(!TunnelTestRange.contains("198.18.0"))
        #expect(TunnelTestRange.ipv4("256.0.0.1") == nil)
        #expect(TunnelTestRange.contains(TunnelTestRange.testTarget) && TunnelTestRange.contains(TunnelTestRange.interfaceAddress))
        #expect(TunnelTestRange.cidr == "198.18.0.0/15")
    }

    @Test func parsesAUDPHeader() throws {
        let summary = try #require(IPv4PacketSummary(udpPacket(to: [198, 18, 0, 1], port: 9)))
        #expect(summary.protocolName == "UDP")
        #expect(summary.source == "198.18.0.2")
        #expect(summary.destination == "198.18.0.1")
        #expect(summary.destinationPort == 9)
        #expect(summary.totalLength == 32)
        #expect(summary.description == "UDP 198.18.0.2 → 198.18.0.1:9 (32 bytes)")
        #expect(IPv4PacketSummary(Data([0x60] + [UInt8](repeating: 0, count: 39))) == nil)
        #expect(IPv4PacketSummary(Data([0x45, 0, 0])) == nil)
    }

    @Test func countsPacketsByProtocol() {
        var stats = TunnelStats(startedAt: Date(timeIntervalSinceReferenceDate: 0))
        let date = Date(timeIntervalSinceReferenceDate: 60)
        stats.record(udpPacket(to: [198, 18, 0, 1], port: 9), at: date)
        stats.record(udpPacket(to: [198, 18, 0, 1], port: 9, payload: 10), at: date)
        stats.record(Data([0x60] + [UInt8](repeating: 0, count: 39)), at: date)
        stats.record(Data([0x00, 0x01]), at: date)
        #expect(stats.packets == 4)
        #expect(stats.bytes == 32 + 38 + 40 + 2)
        #expect(stats.protocolBreakdown == "UDP 2 · IPv6 1 · Unparsed 1")
        #expect(stats.lastPacket == "Unparsed packet (2 bytes)")
        #expect(stats.summary.hasPrefix("4 packets"))
        #expect(TunnelStats.decode(stats.encoded) == stats)
        #expect(TunnelStats.decode(Data("nope".utf8)) == nil)
        #expect(TunnelStats().protocolBreakdown == "none")
    }

    @Test func roundTripsAppMessages() {
        for message in TunnelAppMessage.allCases { #expect(TunnelAppMessage(data: message.data) == message) }
        #expect(TunnelAppMessage(data: Data("hello".utf8)) == .stats)
    }
}

struct PersonalVPNTests {

    @Test func validatesTheForm() {
        var form = PersonalVPNForm()
        #expect(form.problem?.contains("server") == true)
        form.server = "vpn example.com"
        #expect(form.problem?.contains("without spaces") == true)
        form.server = "vpn.example.com"
        #expect(form.problem?.contains("remote ID") == true)
        form.remoteIdentifier = "vpn.example.com"
        #expect(form.problem?.contains("username") == true)
        form.username = "me"
        #expect(form.problem?.contains("password") == true)
        form.password = "secret"
        #expect(form.problem == nil)
        form.authentication = .sharedSecret
        #expect(form.problem?.contains("shared secret") == true)
        form.sharedSecret = "psk"
        #expect(form.problem == nil)
    }

    @Test func namesVPNErrors() {
        #expect(VPNDescriptions.connectionError(code: 6).hasPrefix("serverNotResponding"))
        #expect(VPNDescriptions.connectionError(code: 99) == "code 99")
        #expect(VPNDescriptions.managerError(code: 5).hasPrefix("configurationReadWriteFailed"))
        #expect(VPNDescriptions.status(rawValue: 3) == "Connected")
        let error = NSError(domain: "NEVPNConnectionErrorDomain", code: 5, userInfo: [NSLocalizedDescriptionKey: "x"])
        #expect(VPNDescriptions.describe(error) == "NEVPNConnectionErrorDomain 5 (serverAddressResolutionFailed: the server name could not be resolved): x")
    }

    @Test func offersOnlyCurrentAlgorithms() {
        #expect(PersonalVPNEncryption.allCases.map(\.title) == ["AES-256", "AES-256-GCM", "ChaCha20-Poly1305"])
        #expect(PersonalVPNDiffieHellman.allCases.allSatisfy { $0.rawValue >= 14 })
    }
}
