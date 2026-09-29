import Testing
import Foundation
@testable import AppleToolbox

struct SpatialLinkTests {

    @Test func messagesSurviveTheWireFormat() throws {
        let device = SpatialLinkDeviceInfo(name: "Test iPhone", platform: "iPhone", supportsUWB: true, system: "Version 26.5")
        var hello = SpatialLinkMessage(kind: .hello, sentAt: 12.5, device: device, path: "Satisfied via Wi-Fi (en0)")
        hello.token = Data([1, 2, 3])
        #expect(try SpatialLinkCodec.decode(SpatialLinkCodec.encode(hello)) == hello)
        let pong = SpatialLinkMessage(kind: .pong, sentAt: 99)
        #expect(try SpatialLinkCodec.decode(SpatialLinkCodec.encode(pong)) == pong)
        #expect(throws: (any Error).self) { try SpatialLinkCodec.decode(Data("not json".utf8)) }
    }

    @Test func measuresRoundTripsOnTheSendersClock() {
        #expect(SpatialLinkCodec.roundTripMilliseconds(sentAt: 10, receivedAt: 10.043) == 43)
        #expect(SpatialLinkCodec.roundTripMilliseconds(sentAt: 10, receivedAt: 9) == 0)
    }

    @Test func advertisesPlatformAndUWBBeforeConnecting() {
        let info = SpatialLinkCodec.discoveryInfo(identifier: "abc", platform: "iPad", supportsUWB: false)
        #expect(info[PeerInvitationPolicy.identifierKey] == "abc")
        #expect(SpatialLinkCodec.platform(in: info) == "iPad")
        #expect(SpatialLinkCodec.supportsUWB(in: info) == false)
        #expect(SpatialLinkCodec.supportsUWB(in: nil) == nil)
    }

    @Test func linkServiceTypeIsDeclared() {
        let declared = Set(BonjourServiceType.declaredTypes())
        #expect(declared.contains("_\(SpatialLinkCodec.serviceType)._tcp"))
        #expect(declared.contains("_\(SpatialLinkCodec.serviceType)._udp"))
    }
}
