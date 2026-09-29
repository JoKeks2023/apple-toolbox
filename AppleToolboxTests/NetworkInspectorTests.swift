import Testing
import Foundation
import Network
@testable import AppleToolbox

struct NetworkInspectorTests {

    @Test func parsesHostInput() {
        #expect(NetworkTargetParser.host("  example.com ") == "example.com")
        #expect(NetworkTargetParser.host("https://example.com/path?q=1") == "example.com")
        #expect(NetworkTargetParser.host("[::1]") == "::1")
        #expect(NetworkTargetParser.host("   ") == nil)
    }

    @Test func parsesPortInput() {
        #expect(NetworkTargetParser.port("443") == 443)
        #expect(NetworkTargetParser.port(" 8080 ") == 8080)
        #expect(NetworkTargetParser.port("0") == nil)
        #expect(NetworkTargetParser.port("65536") == nil)
        #expect(NetworkTargetParser.port("http") == nil)
    }

    @Test func formatsPayloads() {
        #expect(NetworkPayloadFormatter.describe(Data("HTTP/1.1 200 OK\r\n".utf8)) == "HTTP/1.1 200 OK")
        #expect(NetworkPayloadFormatter.describe(Data()) == "(empty)")
        #expect(NetworkPayloadFormatter.describe(Data([0x00, 0xff, 0x10])) == "00 ff 10 (binary)")
        let long = NetworkPayloadFormatter.describe(Data(String(repeating: "a", count: 700).utf8), limit: 600)
        #expect(long.hasSuffix("… (100 more characters)"))
    }

    @Test func namesTLSParameters() {
        #expect(TLSDescription.version(0x0304) == "TLS 1.3")
        #expect(TLSDescription.version(0x0303) == "TLS 1.2")
        #expect(TLSDescription.version(0x1234) == "Unknown (0x1234)")
        #expect(TLSDescription.cipherSuite(0x1301) == "TLS_AES_128_GCM_SHA256")
        #expect(TLSDescription.cipherSuite(0xC02F) == "TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256")
        #expect(TLSDescription.cipherSuite(0xABCD) == "0xABCD")
    }

    @Test func lineEndingsAppendTheRightBytes() {
        #expect(LineEnding.none.suffix.isEmpty)
        #expect(Array(LineEnding.crlf.suffix.utf8) == [13, 10])
        #expect(Array(LineEnding.lf.suffix.utf8) == [10])
    }

    @Test func explainsLocalNetworkAndBonjourErrors() {
        let denied = NWError.dns(NetworkErrorExplainer.policyDenied)
        #expect(NetworkErrorExplainer.isLocalNetworkDenial(denied))
        #expect(NetworkErrorExplainer.explain(denied).contains("Local Network"))
        #expect(NetworkErrorExplainer.explain(.dns(NetworkErrorExplainer.noAuth)).contains("NSBonjourServices"))
        #expect(!NetworkErrorExplainer.isLocalNetworkDenial(.posix(.ECONNREFUSED)))
        #expect(NetworkErrorExplainer.explain(.posix(.ECONNREFUSED)).contains("nothing is listening"))
    }

    @Test func validatesBonjourServiceTypes() {
        #expect(BonjourServiceType.isValid("_http._tcp"))
        #expect(BonjourServiceType.isValid("_toolbox-echo._tcp"))
        #expect(BonjourServiceType.isValid("_matterc._udp"))
        #expect(!BonjourServiceType.isValid("http._tcp"))
        #expect(!BonjourServiceType.isValid("_http._sctp"))
        #expect(!BonjourServiceType.isValid("_this-name-is-too-long._tcp"))
        #expect(!BonjourServiceType.isValid("_-bad._tcp"))
    }

    @Test func presetServiceTypesAreValidAndDeclared() {
        let declared = Set(BonjourServiceType.declaredTypes())
        for preset in BonjourServiceType.presets {
            #expect(BonjourServiceType.isValid(preset.type), "\(preset.type)")
            #expect(declared.contains(preset.type), "\(preset.type) missing from NSBonjourServices")
        }
    }

    @Test func logKeepsTheNewestEntries() {
        var log: [NetworkLogEntry] = []
        for index in 0..<(NetworkLogFormatter.capacity + 5) { log = NetworkLogFormatter.appending(NetworkLogEntry(.info, "\(index)"), to: log) }
        #expect(log.count == NetworkLogFormatter.capacity)
        #expect(log.last?.text == "\(NetworkLogFormatter.capacity + 4)")
        #expect(NetworkLogFormatter.text([], placeholder: "empty") == "empty")
    }
}
