import Testing
import Foundation
@testable import AppleToolbox

struct IndoorSurveyTests {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func fix(_ latitude: Double, accuracy: Double, floor: Int? = nil, offset: TimeInterval = 0) -> SurveyFix {
        SurveyFix(latitude: latitude, longitude: 8, horizontalAccuracy: accuracy, altitude: 120, verticalAccuracy: 4, floor: floor, timestamp: now.addingTimeInterval(offset))
    }

    @Test func averagesWithInverseVarianceWeights() throws {
        let measurement = try #require(SurveyMeasurement.average(of: [fix(50.0, accuracy: 5, floor: 1), fix(50.0001, accuracy: 10, floor: 1, offset: 4), fix(51, accuracy: -1)]))
        #expect(abs(measurement.latitude - 50.00002) < 1e-9)
        #expect(measurement.fixCount == 2)
        #expect(measurement.horizontalAccuracy == 7.5)
        #expect(measurement.bestAccuracy == 5)
        #expect(abs(measurement.spread - 6.484) < 0.01)
        #expect(measurement.floor == 1)
        #expect(measurement.duration == 4)
        #expect(measurement.altitude == 120)
        #expect(SurveyMeasurement.average(of: [fix(50, accuracy: -1)]) == nil)
        #expect(SurveyMeasurement.average(of: []) == nil)
    }

    @Test func positionErrorAndFloorMismatch() throws {
        let measurement = try #require(SurveyMeasurement.average(of: [fix(50.0001, accuracy: 4, floor: 2)]))
        let point = SurveyPoint(timestamp: now, reference: SurveyCoordinate(latitude: 50, longitude: 8), measurement: measurement,
                                level: SurveyLevel(id: "L0", ordinal: 0, name: "Ground"), confidence: .high, note: "")
        #expect(abs((point.positionError ?? 0) - 11.1195) < 0.01)
        #expect(point.floorMismatch)
        #expect(point.coordinate == SurveyCoordinate(latitude: 50, longitude: 8))
        let referenceOnly = SurveyPoint(timestamp: now, reference: SurveyCoordinate(latitude: 50, longitude: 8), measurement: nil, level: nil, confidence: .low, note: "")
        #expect(referenceOnly.positionError == nil)
        #expect(!referenceOnly.floorMismatch)
    }

    @Test func heatmapAveragesSamplesPerCell() {
        let origin = SurveyCoordinate(latitude: 50, longitude: 8)
        let metersPerDegree = SurveyHeatmap.metersPerDegree
        let samples = [
            SurveyHeatmap.Sample(coordinate: origin, value: 4),
            SurveyHeatmap.Sample(coordinate: SurveyCoordinate(latitude: 50 + 1 / metersPerDegree, longitude: 8), value: 8), // 1 m north, same 3 m cell
            SurveyHeatmap.Sample(coordinate: SurveyCoordinate(latitude: 50 + 4 / metersPerDegree, longitude: 8), value: 20), // 4 m north, next cell
        ]
        let cells = SurveyHeatmap.cells(for: samples, cellSize: 3)
        #expect(cells.count == 2)
        #expect(cells[0].row == 0 && cells[0].count == 2 && cells[0].meanValue == 6)
        #expect(cells[0].accuracyClass == .good)
        #expect(cells[1].row == 1 && cells[1].meanValue == 20)
        #expect(cells[1].accuracyClass == .poor)
        #expect(cells[0].corners.count == 4)
        #expect(cells[0].corners[0] == origin)
        #expect(abs((cells[0].corners[2].latitude - 50) * metersPerDegree - 3) < 1e-6)
        #expect(SurveyHeatmap.cells(for: [], cellSize: 3).isEmpty)
    }

    @Test func heatmapSamplesFollowTheMetric() throws {
        let measurement = try #require(SurveyMeasurement.average(of: [fix(50.0001, accuracy: 6)]))
        var survey = IndoorSurvey.named(now)
        survey.points = [
            SurveyPoint(timestamp: now, reference: SurveyCoordinate(latitude: 50, longitude: 8), measurement: measurement, level: SurveyLevel(id: "L0", ordinal: 0, name: "Ground"), confidence: .high, note: ""),
            SurveyPoint(timestamp: now, reference: nil, measurement: measurement, level: SurveyLevel(id: "L1", ordinal: 1, name: "First"), confidence: .high, note: ""),
        ]
        survey.paths = [SurveyPath(name: "Walk", source: .walked, started: now, level: SurveyLevel(id: "L0", ordinal: 0, name: "Ground"),
                                   samples: [SurveyPathSample(latitude: 50, longitude: 8, horizontalAccuracy: 9, floor: nil, timestamp: now)])]
        #expect(SurveyHeatmap.samples(for: survey, levelID: nil, metric: .accuracy).count == 3)
        #expect(SurveyHeatmap.samples(for: survey, levelID: "L0", metric: .accuracy).map(\.value) == [6, 9])
        let errors = SurveyHeatmap.samples(for: survey, levelID: nil, metric: .error)
        #expect(errors.count == 1)
        #expect(abs((errors.first?.value ?? 0) - 11.1195) < 0.01)
    }

    @Test func storeRoundTripsSurveys() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("surveys-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        var survey = IndoorSurvey.named(now)
        survey.venue = "Test venue"
        survey.points = [SurveyPoint(timestamp: now, reference: SurveyCoordinate(latitude: 50, longitude: 8), measurement: nil, level: nil, confidence: .medium, note: "Door ü")]
        try IndoorSurveyStore.save(survey, in: directory)
        try Data("not json".utf8).write(to: directory.appendingPathComponent("broken.json"))
        let loaded = IndoorSurveyStore.loadAll(in: directory)
        #expect(loaded.surveys == [survey])
        #expect(loaded.failures == ["broken.json"])
        try IndoorSurveyStore.delete(survey.id, in: directory)
        #expect(IndoorSurveyStore.loadAll(in: directory).surveys.isEmpty)
    }

    @Test func geoJSONExportContainsPointsAndPaths() throws {
        let measurement = try #require(SurveyMeasurement.average(of: [fix(50.0001, accuracy: 4, floor: 0)]))
        var survey = IndoorSurvey.named(now)
        survey.points = [SurveyPoint(timestamp: now, reference: SurveyCoordinate(latitude: 50, longitude: 8), measurement: measurement,
                                     level: SurveyLevel(id: "L0", ordinal: 0, name: "Ground"), confidence: .high, note: "Entrance")]
        survey.paths = [
            SurveyPath(name: "Corridor", source: .drawn, started: now, level: nil, samples: [
                SurveyPathSample(latitude: 50, longitude: 8, horizontalAccuracy: nil, floor: nil, timestamp: now),
                SurveyPathSample(latitude: 50.001, longitude: 8, horizontalAccuracy: nil, floor: nil, timestamp: now),
            ]),
            SurveyPath(name: "Too short", source: .walked, started: now, level: nil, samples: [
                SurveyPathSample(latitude: 50, longitude: 8, horizontalAccuracy: 5, floor: nil, timestamp: now),
            ]),
        ]
        let object = try #require(try JSONSerialization.jsonObject(with: IndoorSurveyExporter.geoJSON(survey)) as? [String: Any])
        #expect(object["type"] as? String == "FeatureCollection")
        let features = try #require(object["features"] as? [[String: Any]])
        #expect(features.count == 2)
        let point = features[0]
        #expect((point["geometry"] as? [String: Any])?["coordinates"] as? [Double] == [8, 50])
        let properties = try #require(point["properties"] as? [String: Any])
        #expect(properties["kind"] as? String == "survey_point")
        #expect(properties["note"] as? String == "Entrance")
        #expect(properties["level_ordinal"] as? Int == 0)
        let measured = try #require(properties["measured"] as? [Double])
        #expect(measured.count == 2 && measured[0] == 8 && abs(measured[1] - 50.0001) < 1e-9)
        #expect(abs((properties["position_error_m"] as? Double ?? 0) - 11.1195) < 0.01)
        let path = features[1]
        #expect((path["geometry"] as? [String: Any])?["type"] as? String == "LineString")
        #expect((path["properties"] as? [String: Any])?["kind"] as? String == "drawn_path")
        #expect(abs(((path["properties"] as? [String: Any])?["length_m"] as? Double ?? 0) - 111.195) < 0.01)
    }
}
