import Testing
import Foundation
@testable import AppleToolbox

struct BeaconIdentityTests {

    private let uuid = "E2C56DB5-DFFB-48D2-B060-D0F5A71096E0"

    @Test func parsesUUIDOnly() throws {
        let identity = try BeaconIdentity.parse(uuid: " \(uuid.lowercased()) ", major: "", minor: "").get()
        #expect(identity.uuid.uuidString == uuid)
        #expect(identity.major == nil)
        #expect(identity.minor == nil)
    }

    @Test func parsesMajorAndMinor() throws {
        let identity = try BeaconIdentity.parse(uuid: uuid, major: "7", minor: "65535").get()
        #expect(identity.major == 7)
        #expect(identity.minor == 65535)
        #expect(identity.summary.hasSuffix("major 7 · minor 65535"))
    }

    @Test func rejectsInvalidInput() {
        #expect(BeaconIdentity.parse(uuid: "not-a-uuid", major: "", minor: "") == .failure(.invalidUUID))
        #expect(BeaconIdentity.parse(uuid: uuid, major: "65536", minor: "") == .failure(.invalidMajor))
        #expect(BeaconIdentity.parse(uuid: uuid, major: "-1", minor: "") == .failure(.invalidMajor))
        #expect(BeaconIdentity.parse(uuid: uuid, major: "1", minor: "x") == .failure(.invalidMinor))
        #expect(BeaconIdentity.parse(uuid: uuid, major: "", minor: "3") == .failure(.minorWithoutMajor))
    }

    @Test func presetsCarryValidUUIDs() {
        for preset in BeaconUUIDPreset.allCases {
            if let value = preset.uuid { #expect(UUID(uuidString: value) != nil, "\(preset.rawValue)") }
        }
        #expect(BeaconUUIDPreset.custom.uuid == nil)
    }

    @Test func sortsNearestFirstAndUnknownLast() {
        func reading(_ minor: Int, accuracy: Double, rssi: Int) -> BeaconReading {
            BeaconReading(uuid: UUID(), major: 1, minor: minor, proximity: .near, accuracy: accuracy, rssi: rssi, timestamp: Date())
        }
        let sorted = BeaconReading.sortedByDistance([reading(1, accuracy: -1, rssi: -90), reading(2, accuracy: 3.2, rssi: -70), reading(3, accuracy: 0.4, rssi: -50), reading(4, accuracy: -1, rssi: -60)])
        #expect(sorted.map(\.minor) == [3, 2, 4, 1])
    }
}

struct LocationTrackTests {

    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func sample(_ index: Int, latitude: Double, longitude: Double = 8, accuracy: Double = 5, altitude: Double = 100, verticalAccuracy: Double = 3, speed: Double = 1.5, floor: Int? = nil) -> LocationTrackSample {
        LocationTrackSample(id: index, timestamp: start.addingTimeInterval(Double(index) * 10), latitude: latitude, longitude: longitude,
                            altitude: altitude, horizontalAccuracy: accuracy, verticalAccuracy: verticalAccuracy, speed: speed, floor: floor)
    }

    @Test func haversineMatchesOneThousandthOfADegree() {
        let meters = Geodesy.distance(fromLatitude: 0, longitude: 0, toLatitude: 0.001, longitude: 0)
        #expect(abs(meters - 111.195) < 0.01)
    }

    @Test func statisticsSkipInaccurateFixesForDistance() {
        let samples = [
            sample(0, latitude: 50.000),
            sample(1, latitude: 50.001),
            sample(2, latitude: 50.050, accuracy: 500), // a GPS jump with poor accuracy
            sample(3, latitude: 50.002),
        ]
        let statistics = LocationTrackStatistics(samples: samples)
        #expect(statistics.sampleCount == 4)
        #expect(statistics.distanceSampleCount == 3)
        #expect(abs(statistics.distance - 2 * 111.195) < 0.1)
        #expect(statistics.duration == 30)
        #expect(abs((statistics.averageSpeed ?? 0) - statistics.distance / 30) < 0.0001)
        #expect(statistics.bestAccuracy == 5)
        #expect(statistics.worstAccuracy == 500)
        #expect(statistics.medianAccuracy == 5)
    }

    @Test func elevationGainIgnoresNoise() {
        let altitudes: [Double] = [100, 101, 99, 104, 110, 108, 103]
        let samples = altitudes.enumerated().map { sample($0.offset, latitude: 50, altitude: $0.element) }
        let statistics = LocationTrackStatistics(samples: samples)
        #expect(statistics.elevationGain == 10) // 100 → 104 → 110
        #expect(statistics.elevationLoss == 7) // 110 → 103
        #expect(statistics.minAltitude == 99)
        #expect(statistics.maxAltitude == 110)
    }

    @Test func invalidValuesAreExcluded() {
        let samples = [sample(0, latitude: 50, verticalAccuracy: -1, speed: -1, floor: 2), sample(1, latitude: 50, speed: 4, floor: 0)]
        let statistics = LocationTrackStatistics(samples: samples)
        #expect(statistics.maxSpeed == 4)
        #expect(statistics.minAltitude == 100)
        #expect(statistics.floors == [0, 2])
        #expect(LocationTrackStatistics(samples: []).sampleCount == 0)
    }

    @Test func downsamplingKeepsEndpoints() {
        let samples = (0..<1_000).map { sample($0, latitude: 50 + Double($0) * 0.0001) }
        let thinned = LocationTrackSample.downsampled(samples, maxCount: 100)
        #expect(thinned.count == 100)
        #expect(thinned.first?.id == 0)
        #expect(thinned.last?.id == 999)
        #expect(LocationTrackSample.downsampled(Array(samples.prefix(10)), maxCount: 100).count == 10)
    }

    @Test func gpxContainsEveryPointAndEscapesTheName() {
        let gpx = LocationTrackExporter.gpx([sample(0, latitude: 50.1234567), sample(1, latitude: 50.2, verticalAccuracy: -1)], name: "Walk <A&B>")
        #expect(gpx.contains(#"<gpx version="1.1""#))
        #expect(gpx.contains("<name>Walk &lt;A&amp;B&gt;</name>"))
        #expect(gpx.components(separatedBy: "<trkpt ").count - 1 == 2)
        #expect(gpx.contains(#"lat="50.1234567" lon="8.0000000""#))
        #expect(gpx.components(separatedBy: "<ele>").count - 1 == 1)
        #expect(gpx.contains("<atb:hacc>5.0</atb:hacc>"))
    }

    @Test func geoJSONUsesLongitudeLatitudeOrder() throws {
        let data = try LocationTrackExporter.geoJSON([sample(0, latitude: 50, longitude: 8), sample(1, latitude: 51, longitude: 9, verticalAccuracy: -1)], name: "Track")
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["type"] as? String == "FeatureCollection")
        let feature = try #require((object["features"] as? [[String: Any]])?.first)
        let geometry = try #require(feature["geometry"] as? [String: Any])
        #expect(geometry["type"] as? String == "LineString")
        let coordinates = try #require(geometry["coordinates"] as? [[Double]])
        #expect(coordinates == [[8, 50, 100], [9, 51]])
        let properties = try #require(feature["properties"] as? [String: Any])
        #expect(properties["sampleCount"] as? Int == 2)
        let perPoint = try #require(properties["coordinateProperties"] as? [String: Any])
        #expect((perPoint["times"] as? [String])?.count == 2)
        #expect((perPoint["verticalAccuracy"] as? [Any])?.last is NSNull)
    }

    @Test func singleFixExportsAsPoint() throws {
        let data = try LocationTrackExporter.geoJSON([sample(0, latitude: 50)], name: "One")
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let geometry = try #require(((object["features"] as? [[String: Any]])?.first)?["geometry"] as? [String: Any])
        #expect(geometry["type"] as? String == "Point")
    }
}
