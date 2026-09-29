import Foundation
import Combine
#if canImport(MapKit)
import MapKit
#endif

nonisolated struct IMDFRow: Identifiable, Hashable {
    let title: String
    let value: String
    var id: String { title }
}

nonisolated struct IMDFCount: Identifiable, Hashable {
    let type: String
    let count: Int
    var id: String { type }
}

nonisolated struct IMDFLevel: Identifiable, Hashable {
    let id: String
    let ordinal: Int
    let name: String
    let building: String?
    let isOutdoor: Bool
    /// Features on this level per IMDF type, including amenities, anchors and occupants resolved through their units.
    let counts: [IMDFCount]

    var title: String {
        var title = "\(ordinal) · \(name)"
        if let building { title += " (\(building))" }
        if isOutdoor { title += " · outdoor" }
        return title
    }
}

nonisolated struct IMDFSummary {
    let source: String
    let isArchive: Bool
    let manifest: [IMDFRow]
    let typeCounts: [IMDFCount]
    let levels: [IMDFLevel]
    let notes: [String]

    var totalFeatures: Int { typeCounts.reduce(0) { $0 + $1.count } }
    var defaultLevelID: String? { (levels.first { $0.ordinal == 0 } ?? levels.first)?.id }
}

#if canImport(MapKit)
nonisolated struct IMDFLevelShapes {
    var outline: [MKPolygon] = []
    var units: [MKPolygon] = []
    var openings: [MKPolyline] = []

    var isEmpty: Bool { outline.isEmpty && units.isEmpty && openings.isEmpty }
}

nonisolated struct IMDFMapGeometry {
    var venue: [MKPolygon] = []
    var levels: [String: IMDFLevelShapes] = [:]

    /// The map rectangle that frames the venue outline and the level's shapes.
    func boundingRect(for levelID: String) -> MKMapRect? {
        let shapes = levels[levelID] ?? IMDFLevelShapes()
        let overlays: [MKOverlay] = venue + shapes.outline + shapes.units + shapes.openings
        guard let first = overlays.first else { return nil }
        return overlays.dropFirst().reduce(first.boundingMapRect) { $0.union($1.boundingMapRect) }
    }
}
#endif

/// Decoded archive handed from the background reader to the main actor. The MapKit shapes are
/// created by the reader and never mutated afterwards.
nonisolated struct IMDFDecodedArchive: @unchecked Sendable {
    let summary: IMDFSummary
    #if canImport(MapKit)
    let geometry: IMDFMapGeometry
    #endif
}

@MainActor
final class IndoorIMDFExperimentService: ObservableObject {
    @Published private(set) var output = "Import an unzipped IMDF archive folder, or one or more IMDF GeoJSON files."
    @Published private(set) var status: ExperimentStatus = .available
    @Published private(set) var isLoading = false
    @Published private(set) var summary: IMDFSummary?
    @Published var selectedLevelID: String?
    #if canImport(MapKit)
    @Published private(set) var geometry: IMDFMapGeometry?
    #endif

    func load(urls: [URL]) {
        guard !urls.isEmpty, !isLoading else { return }
        isLoading = true
        output = "Decoding \(urls.map(\.lastPathComponent).joined(separator: ", "))…"
        Task {
            let result = await Task.detached(priority: .userInitiated) { IMDFArchiveReader.read(urls) }.value
            isLoading = false
            switch result {
            case .success(let archive):
                summary = archive.summary
                #if canImport(MapKit)
                geometry = archive.geometry
                #endif
                selectedLevelID = archive.summary.defaultLevelID
                status = .available
                let kind = archive.summary.isArchive ? "IMDF archive" : "IMDF files"
                var lines = ["\(kind) decoded with MKGeoJSONDecoder: \(archive.summary.source)",
                             "Features: \(archive.summary.totalFeatures) in \(archive.summary.typeCounts.count) type(s) · Levels: \(archive.summary.levels.count)"]
                lines += archive.summary.notes
                output = lines.joined(separator: "\n")
            case .failure(let failure):
                summary = nil
                #if canImport(MapKit)
                geometry = nil
                #endif
                selectedLevelID = nil
                status = .unavailable
                output = "IMDF import error: \(failure.message)"
            }
        }
    }

    func reportImportFailure(_ error: Error) {
        status = .unavailable
        output = "File import error: \(error.localizedDescription)"
    }
}

/// Reads an IMDF archive folder (or loose GeoJSON files) and decodes it with MKGeoJSONDecoder.
nonisolated enum IMDFArchiveReader {
    struct Failure: Error { let message: String }

    static let featureTypes = ["venue", "address", "building", "footprint", "level", "unit", "opening", "amenity", "anchor", "occupant",
                               "section", "geofence", "kiosk", "detail", "fixture", "relationship"]
    /// Types counted per level; amenities, anchors and occupants are resolved through their units.
    private static let levelFeatureTypes = ["unit", "opening", "amenity", "anchor", "occupant", "section", "geofence", "kiosk", "detail", "fixture"]
    /// Types that reference their level directly through "level_id" or "level_ids".
    private static let directLevelTypes: Set<String> = ["unit", "opening", "section", "geofence", "kiosk", "detail", "fixture"]

    private struct File { let name: String; let data: Data }

    static func read(_ urls: [URL]) -> Result<IMDFDecodedArchive, Failure> {
        var files: [File] = []
        var notes: [String] = []
        var isArchive = false
        for url in urls {
            // Folder contents are only readable while the folder's security scope is open.
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                isArchive = true
                for file in jsonFiles(in: archiveRoot(in: url)) {
                    do { files.append(File(name: file.lastPathComponent, data: try Data(contentsOf: file))) }
                    catch { notes.append("Could not read \(file.lastPathComponent): \(error.localizedDescription)") }
                }
            } else {
                do { files.append(File(name: url.lastPathComponent, data: try Data(contentsOf: url))) }
                catch { notes.append("Could not read \(url.lastPathComponent): \(error.localizedDescription)") }
            }
        }
        let source = urls.map(\.lastPathComponent).joined(separator: ", ")
        guard !files.isEmpty else {
            return .failure(Failure(message: (["No .json or .geojson files were found in \(source). Select an unzipped IMDF archive folder (a .zip must be extracted first) or IMDF GeoJSON files."] + notes).joined(separator: "\n")))
        }
        #if canImport(MapKit)
        return decode(files, source: source, isArchive: isArchive, notes: notes)
        #else
        return .failure(Failure(message: "MKGeoJSONDecoder is not available on this platform."))
        #endif
    }

    private static func jsonFiles(in folder: URL) -> [URL] {
        let contents = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? []
        return contents.filter { ["json", "geojson"].contains($0.pathExtension.lowercased()) }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// Unzipping often produces a wrapper folder; descend one level when only a subfolder holds the IMDF files.
    private static func archiveRoot(in folder: URL) -> URL {
        func containsIMDF(_ candidate: URL) -> Bool {
            jsonFiles(in: candidate).contains { url in
                let stem = url.deletingPathExtension().lastPathComponent.lowercased()
                return stem == "manifest" || featureTypes.contains(stem)
            }
        }
        guard !containsIMDF(folder) else { return folder }
        let subfolders = ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? [])
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true && $0.lastPathComponent != "__MACOSX" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        return subfolders.first(where: containsIMDF) ?? folder
    }

    #if canImport(MapKit)
    private struct LevelInfo { let id: String; let ordinal: Int; let name: String; let buildingIDs: [String]; let isOutdoor: Bool }

    private static func decode(_ files: [File], source: String, isArchive: Bool, notes initialNotes: [String]) -> Result<IMDFDecodedArchive, Failure> {
        var notes = initialNotes
        var manifest: [IMDFRow]?
        var counts: [String: Int] = [:]
        var skipped: [String] = []
        var levels: [LevelInfo] = []
        var buildingNames: [String: String] = [:]
        var levelCounts: [String: [String: Int]] = [:]
        var unitLevels: [String: String] = [:]
        var anchorUnits: [String: String] = [:]
        var amenityUnits: [[String]] = []
        var occupantAnchors: [String] = []
        var geometry = IMDFMapGeometry()
        let decoder = MKGeoJSONDecoder()

        for file in files {
            let stem = (file.name as NSString).deletingPathExtension.lowercased()
            if stem == "manifest" {
                if let object = try? JSONSerialization.jsonObject(with: file.data) as? [String: Any] { manifest = manifestRows(object) }
                else { notes.append("manifest.json is not a valid JSON object.") }
                continue
            }
            let objects: [MKGeoJSONObject]
            do { objects = try decoder.decode(file.data) } catch {
                notes.append("\(file.name) is not valid GeoJSON: \(error.localizedDescription)")
                continue
            }
            guard let type = featureTypes.contains(stem) ? stem : declaredFeatureType(in: file.data) else { skipped.append(file.name); continue }
            let features = objects.compactMap { $0 as? MKGeoJSONFeature }
            counts[type, default: 0] += features.count
            for feature in features {
                let properties = feature.properties.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
                let id = feature.identifier ?? UUID().uuidString
                let levelIDs = (properties["level_id"] as? String).map { [$0] } ?? (properties["level_ids"] as? [String] ?? [])
                if directLevelTypes.contains(type) {
                    for levelID in levelIDs { levelCounts[levelID, default: [:]][type, default: 0] += 1 }
                }
                switch type {
                case "venue":
                    geometry.venue += polygons(feature.geometry)
                case "building":
                    if let name = label(properties["name"]) { buildingNames[id] = name }
                case "level":
                    let ordinal = properties["ordinal"] as? Int ?? 0
                    let name = label(properties["name"]) ?? label(properties["short_name"]) ?? "Level \(ordinal)"
                    levels.append(LevelInfo(id: id, ordinal: ordinal, name: name, buildingIDs: properties["building_ids"] as? [String] ?? [], isOutdoor: properties["outdoor"] as? Bool ?? false))
                    geometry.levels[id, default: IMDFLevelShapes()].outline += polygons(feature.geometry)
                case "unit":
                    if let levelID = levelIDs.first {
                        unitLevels[id] = levelID
                        geometry.levels[levelID, default: IMDFLevelShapes()].units += polygons(feature.geometry)
                    }
                case "opening":
                    if let levelID = levelIDs.first { geometry.levels[levelID, default: IMDFLevelShapes()].openings += polylines(feature.geometry) }
                case "anchor":
                    if let unitID = properties["unit_id"] as? String { anchorUnits[id] = unitID }
                case "amenity":
                    amenityUnits.append(properties["unit_ids"] as? [String] ?? [])
                case "occupant":
                    if let anchorID = properties["anchor_id"] as? String { occupantAnchors.append(anchorID) }
                default:
                    break
                }
            }
        }

        guard manifest != nil || !counts.isEmpty else {
            return .failure(Failure(message: (["\(source) is not IMDF: it contains no manifest.json and no IMDF feature files (venue.geojson, level.geojson, unit.geojson, …)."] + notes).joined(separator: "\n")))
        }

        // Amenities, anchors and occupants reference units, not levels.
        for unitIDs in amenityUnits {
            for levelID in Set(unitIDs.compactMap { unitLevels[$0] }) { levelCounts[levelID, default: [:]]["amenity", default: 0] += 1 }
        }
        for unitID in anchorUnits.values {
            if let levelID = unitLevels[unitID] { levelCounts[levelID, default: [:]]["anchor", default: 0] += 1 }
        }
        for anchorID in occupantAnchors {
            if let levelID = anchorUnits[anchorID].flatMap({ unitLevels[$0] }) { levelCounts[levelID, default: [:]]["occupant", default: 0] += 1 }
        }

        let showsBuilding = Set(levels.flatMap(\.buildingIDs)).count > 1
        var summaryLevels: [IMDFLevel] = []
        for level in levels {
            let typeCounts = levelCounts[level.id] ?? [:]
            let perType: [IMDFCount] = levelFeatureTypes.compactMap { type in typeCounts[type].map { IMDFCount(type: type, count: $0) } }
            let building: String? = showsBuilding ? level.buildingIDs.compactMap { buildingNames[$0] }.first : nil
            summaryLevels.append(IMDFLevel(id: level.id, ordinal: level.ordinal, name: level.name, building: building, isOutdoor: level.isOutdoor, counts: perType))
        }
        summaryLevels.sort { $0.ordinal != $1.ordinal ? $0.ordinal < $1.ordinal : $0.name < $1.name }

        if isArchive {
            if manifest == nil { notes.append("manifest.json is missing; an IMDF archive must include one.") }
            let missing = featureTypes.filter { counts[$0] == nil }
            if !missing.isEmpty { notes.append("Not in the archive: \(missing.map { "\($0).geojson" }.joined(separator: ", "))") }
        }
        if counts["level"] == nil { notes.append("No level features: floors cannot be listed or drawn.") }
        if !skipped.isEmpty { notes.append("Skipped (not IMDF features): \(skipped.joined(separator: ", "))") }

        let summary = IMDFSummary(source: source, isArchive: isArchive, manifest: manifest ?? [],
                                  typeCounts: featureTypes.compactMap { type in counts[type].map { IMDFCount(type: type, count: $0) } },
                                  levels: summaryLevels, notes: notes)
        return .success(IMDFDecodedArchive(summary: summary, geometry: geometry))
    }

    private static func manifestRows(_ manifest: [String: Any]) -> [IMDFRow] {
        var rows: [IMDFRow] = []
        if let version = manifest["version"] as? String { rows.append(IMDFRow(title: "Version", value: version)) }
        if let language = manifest["language"] as? String { rows.append(IMDFRow(title: "Language", value: language)) }
        if let created = manifest["created"] as? String { rows.append(IMDFRow(title: "Created", value: created)) }
        if let generator = manifest["generated_by"] as? String { rows.append(IMDFRow(title: "Generated by", value: generator)) }
        if let extensions = manifest["extensions"] as? [Any], !extensions.isEmpty { rows.append(IMDFRow(title: "Extensions", value: "\(extensions.count)")) }
        return rows
    }

    /// IMDF features carry a top-level "feature_type" member, which identifies files with non-standard names.
    private static func declaredFeatureType(in data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let type = object["feature_type"] as? String ?? (object["features"] as? [[String: Any]])?.first?["feature_type"] as? String
        return type.flatMap { featureTypes.contains($0) ? $0 : nil }
    }

    /// Picks the IMDF label matching the user's preferred languages, then English, then any.
    private static func label(_ value: Any?) -> String? {
        guard let labels = value as? [String: String], !labels.isEmpty else { return nil }
        for language in Locale.preferredLanguages {
            if let exact = labels[language] { return exact }
            let base = String(language.prefix { $0 != "-" })
            if let match = labels.first(where: { $0.key == base || $0.key.hasPrefix(base + "-") })?.value { return match }
        }
        return labels["en"] ?? labels.sorted { $0.key < $1.key }.first?.value
    }

    private static func polygons(_ geometry: [MKShape & MKGeoJSONObject]) -> [MKPolygon] {
        geometry.flatMap { shape -> [MKPolygon] in
            if let polygon = shape as? MKPolygon { return [polygon] }
            return (shape as? MKMultiPolygon)?.polygons ?? []
        }
    }

    private static func polylines(_ geometry: [MKShape & MKGeoJSONObject]) -> [MKPolyline] {
        geometry.flatMap { shape -> [MKPolyline] in
            if let polyline = shape as? MKPolyline { return [polyline] }
            return (shape as? MKMultiPolyline)?.polylines ?? []
        }
    }
    #endif
}
