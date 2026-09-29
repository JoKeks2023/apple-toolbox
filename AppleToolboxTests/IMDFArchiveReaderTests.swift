import Testing
import Foundation
@testable import AppleToolbox

#if canImport(MapKit)
struct IMDFArchiveReaderTests {

    private static let levelID = "11111111-1111-4111-8111-111111111111"

    /// A minimal IMDF archive: manifest, one level and two units on it, plus one opening.
    private func makeArchive() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("imdf-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let square = "[[[8.0,50.0],[8.001,50.0],[8.001,50.001],[8.0,50.001],[8.0,50.0]]]"
        let files = [
            "manifest.json": #"{"version":"1.0.0","language":"en","created":"2026-09-29T00:00:00Z"}"#,
            "level.geojson": #"{"type":"FeatureCollection","features":[{"id":"\#(Self.levelID)","type":"Feature","feature_type":"level","geometry":{"type":"Polygon","coordinates":\#(square)},"properties":{"ordinal":0,"name":{"en":"Ground"},"outdoor":false,"building_ids":[]}}]}"#,
            "unit.geojson": #"{"type":"FeatureCollection","features":[{"id":"22222222-2222-4222-8222-222222222222","type":"Feature","feature_type":"unit","geometry":{"type":"Polygon","coordinates":\#(square)},"properties":{"category":"room","level_id":"\#(Self.levelID)"}},{"id":"33333333-3333-4333-8333-333333333333","type":"Feature","feature_type":"unit","geometry":{"type":"Polygon","coordinates":\#(square)},"properties":{"category":"walkway","level_id":"\#(Self.levelID)"}}]}"#,
            "opening.geojson": #"{"type":"FeatureCollection","features":[{"id":"44444444-4444-4444-8444-444444444444","type":"Feature","feature_type":"opening","geometry":{"type":"LineString","coordinates":[[8.0,50.0],[8.0005,50.0]]},"properties":{"category":"pedestrian","level_id":"\#(Self.levelID)"}}]}"#,
        ]
        for (name, contents) in files {
            try Data(contents.utf8).write(to: folder.appendingPathComponent(name))
        }
        return folder
    }

    @Test func decodesFeaturesPerTypeAndLevel() throws {
        let archive = try makeArchive()
        defer { try? FileManager.default.removeItem(at: archive) }
        guard case .success(let decoded) = IMDFArchiveReader.read([archive]) else {
            Issue.record("The archive should decode")
            return
        }
        let summary = decoded.summary
        #expect(summary.isArchive)
        #expect(summary.typeCounts.first { $0.type == "level" }?.count == 1)
        #expect(summary.typeCounts.first { $0.type == "unit" }?.count == 2)
        #expect(summary.typeCounts.first { $0.type == "opening" }?.count == 1)
        let level = try #require(summary.levels.first)
        #expect(summary.levels.count == 1)
        #expect(level.ordinal == 0)
        #expect(level.name == "Ground")
        #expect(level.counts.first { $0.type == "unit" }?.count == 2)
        #expect(summary.manifest.contains { $0.title == "Version" && $0.value == "1.0.0" })
        #expect(decoded.geometry.levels[Self.levelID]?.units.count == 2)
    }

    @Test func rejectsFoldersWithoutGeoJSON() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("imdf-empty-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        guard case .failure(let failure) = IMDFArchiveReader.read([folder]) else {
            Issue.record("An empty folder must not decode")
            return
        }
        #expect(failure.message.contains("No .json or .geojson files"))
    }
}
#endif
