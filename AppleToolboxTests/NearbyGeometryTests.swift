import Testing
import Foundation
@testable import AppleToolbox

struct NearbyGeometryTests {

    @Test func convertsDirectionVectorsToAngles() {
        #expect(abs(NearbyGeometry.azimuth(SIMD3(0, 0, -1))) < 0.0001)
        #expect(abs(NearbyGeometry.azimuth(SIMD3(1, 0, 0)) - .pi / 2) < 0.0001)
        #expect(abs(NearbyGeometry.elevation(SIMD3(0, 0, -1))) < 0.0001)
        #expect(abs(NearbyGeometry.elevation(SIMD3(0, 1, 0)) - .pi / 2) < 0.0001)
        #expect(NearbyGeometry.degrees(.pi / 4) == "+45°")
        #expect(NearbyGeometry.degrees(-.pi / 6) == "-30°")
        #expect(NearbyGeometry.degrees(0) == "0°")
    }

    @Test func placesRadarBlips() {
        let ahead = NearbyGeometry.radarPoint(distance: 1, azimuth: 0, range: 2)
        #expect(abs(ahead.x) < 0.0001 && abs(ahead.y + 0.5) < 0.0001)
        let right = NearbyGeometry.radarPoint(distance: 4, azimuth: .pi / 2, range: 2)
        #expect(abs(right.x - 1) < 0.0001 && abs(right.y) < 0.0001)
    }

    @Test func picksAReadableRadarRange() {
        #expect(NearbyGeometry.radarRange(for: []) == 1)
        #expect(NearbyGeometry.radarRange(for: [0.4]) == 1)
        #expect(NearbyGeometry.radarRange(for: [1.5, 3.2]) == 5)
        #expect(NearbyGeometry.radarRange(for: [60]) == 100)
    }

    @Test func formatsDistancesAndErrors() {
        #expect(NearbyGeometry.meters(1.234) == "1.23 m")
        #expect(NearbyGeometry.meters(12.34) == "12.3 m")
        #expect(NearbyGeometry.errorDescription(code: -5884).contains("did not allow"))
        #expect(NearbyGeometry.errorDescription(code: -5881).contains("peer"))
    }
}
