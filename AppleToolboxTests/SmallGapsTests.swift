import Testing
import Foundation
import simd
@testable import AppleToolbox

@MainActor
struct SmallGapsTests {

    private func ap(_ ssid: String?, _ bssid: String?, _ rssi: Int) -> WiFiAccessPointSample {
        WiFiAccessPointSample(ssid: ssid, bssid: bssid, rssi: rssi, noise: -92, channel: 36, band: "5 GHz")
    }

    @Test func wifiFingerprintSortsStrongestFirst() {
        let samples = [ap("B", "02", -70), ap("A", "01", -48), ap("C", "00", -70)]
        #expect(WiFiFingerprint.sorted(samples).map(\.bssid) == ["01", "00", "02"])
        #expect(WiFiFingerprint.summary(samples) == "3 AP(s) · strongest -48 dBm (A)")
        #expect(WiFiFingerprint.summary([]) == "No access points")
        #expect(samples[1].snr == 44)
    }

    @Test func wifiIdentifiersHiddenWithoutLocation() {
        #expect(WiFiFingerprint.identifiersHidden([ap(nil, nil, -50), ap(nil, nil, -60)]))
        #expect(!WiFiFingerprint.identifiersHidden([ap(nil, nil, -50), ap("Office", nil, -60)]))
        #expect(!WiFiFingerprint.identifiersHidden([]))
        #expect(WiFiFingerprint.summary([ap(nil, nil, -50)]).hasSuffix("(hidden)"))
    }

    @Test func surveyPointWithoutWiFiStillDecodes() throws {
        let point = SurveyPoint(timestamp: Date(timeIntervalSince1970: 0), reference: nil, measurement: nil, level: nil, confidence: .high, note: "")
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(point)) as! [String: Any]
        json["wifi"] = nil
        let decoded = try JSONDecoder().decode(SurveyPoint.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(decoded.wifi == nil)
        var withWiFi = point
        withWiFi.wifi = [ap("A", "01", -40)]
        #expect(try JSONDecoder().decode(SurveyPoint.self, from: JSONEncoder().encode(withWiFi)).wifi?.first?.rssi == -40)
    }

    @Test func rawAccelerationMagnitude() {
        #expect(MotionVector(x: 0, y: 0, z: -1).magnitude == 1)
        #expect(abs(MotionVector(x: 3, y: 4, z: 0).magnitude - 5) < 1e-9)
    }

    @Test func worldTransformTranslation() {
        var transform = matrix_identity_float4x4
        transform.columns.3 = SIMD4(0.5, -1, 2, 1)
        #expect(NearbyGeometry.position(from: transform) == SIMD3(0.5, -1, 2))
        #expect(NearbyGeometry.worldPositionText(SIMD3(0.5, -1, 2)).hasSuffix(" m"))
    }

    @Test func experimentSearchMatchesNameFrameworkAndCategory() {
        let all = ExperimentRegistry.all
        #expect(ExperimentSearch.matches("  ", in: all).isEmpty)
        #expect(ExperimentSearch.matches("multipeer", in: all).contains { $0.id == "multipeer-connectivity" })
        #expect(ExperimentSearch.matches("CoreMotion", in: all).contains { $0.frameworks.contains("CoreMotion") })
        #expect(ExperimentSearch.matches("zzz-no-match", in: all).isEmpty)
    }
}
