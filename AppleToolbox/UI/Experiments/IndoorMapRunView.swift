import SwiftUI
#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif
#if canImport(MapKit)
import MapKit
#endif

struct IndoorIMDFRunView: View {
    @StateObject private var indoor = IndoorIMDFExperimentService()
    /// true: pick an archive folder, false: pick GeoJSON files, nil: importer closed.
    @State private var importsFolder: Bool?

    var body: some View {
        Text("IMDF archives are usually shared as .zip files. iOS has no public API to extract zip archives, so unzip the archive first (for example by tapping it in the Files app) and import the resulting folder. Individual .geojson files can be imported too.")
            .font(.caption)
            .foregroundStyle(.secondary)
        HStack {
            Button("Import IMDF Folder", systemImage: "folder") { importsFolder = true }.buttonStyle(.borderedProminent)
            Button("Import GeoJSON Files", systemImage: "doc.on.doc") { importsFolder = false }.buttonStyle(.bordered)
        }
        .disabled(indoor.isLoading)
        #if canImport(UniformTypeIdentifiers) && !os(tvOS)
        .fileImporter(isPresented: Binding(get: { importsFolder != nil }, set: { if !$0 { importsFolder = nil } }),
                      allowedContentTypes: importsFolder == true ? [.folder] : Self.geoJSONTypes,
                      allowsMultipleSelection: importsFolder != true) { result in
            switch result {
            case .success(let urls): indoor.load(urls: urls)
            case .failure(let error): indoor.reportImportFailure(error)
            }
        }
        #endif
        if indoor.isLoading {
            ProgressView("Decoding GeoJSON…")
        }
        if let summary = indoor.summary {
            IMDFSummaryView(summary: summary)
            if !summary.levels.isEmpty {
                Section("Levels (\(summary.levels.count))") {
                    Picker("Level", selection: $indoor.selectedLevelID) {
                        ForEach(summary.levels) { Text($0.title).tag(Optional($0.id)) }
                    }
                    if let level = summary.levels.first(where: { $0.id == indoor.selectedLevelID }) {
                        if level.counts.isEmpty {
                            Text("No features reference this level.").font(.caption).foregroundStyle(.secondary)
                        }
                        ForEach(level.counts) { LabeledContent($0.type.capitalized, value: "\($0.count)") }
                        #if canImport(MapKit)
                        if let geometry = indoor.geometry, geometry.boundingRect(for: level.id) != nil {
                            IMDFLevelMap(geometry: geometry, levelID: level.id)
                        } else {
                            Text("This level has no unit, opening or outline geometry to draw.").font(.caption).foregroundStyle(.secondary)
                        }
                        #else
                        Text("Map overlays are not available on this platform.").font(.caption).foregroundStyle(.secondary)
                        #endif
                    }
                }
            }
        }
        OutputView(text: indoor.output, isError: indoor.status == .unavailable)
    }

    #if canImport(UniformTypeIdentifiers)
    private static let geoJSONTypes: [UTType] = [.json, UTType(filenameExtension: "geojson", conformingTo: .json)].compactMap { $0 }
    #endif
}

private struct IMDFSummaryView: View {
    let summary: IMDFSummary

    var body: some View {
        if !summary.manifest.isEmpty {
            Section("Manifest") {
                ForEach(summary.manifest) { LabeledContent($0.title, value: $0.value) }
            }
        }
        Section("Feature types (\(summary.totalFeatures) features)") {
            ForEach(summary.typeCounts) { LabeledContent($0.type.capitalized, value: "\($0.count)") }
        }
    }
}

#if canImport(MapKit)
private struct IMDFLevelMap: View {
    let geometry: IMDFMapGeometry
    let levelID: String

    var body: some View {
        let shapes = geometry.levels[levelID] ?? IMDFLevelShapes()
        VStack(alignment: .leading, spacing: 6) {
            Map(initialPosition: cameraPosition) {
                ForEach(Array(geometry.venue.enumerated()), id: \.offset) { MapPolygon($0.element).foregroundStyle(.gray.opacity(0.06)).stroke(.gray, lineWidth: 2) }
                ForEach(Array(shapes.outline.enumerated()), id: \.offset) { MapPolygon($0.element).foregroundStyle(.gray.opacity(0.12)).stroke(.secondary, lineWidth: 1) }
                ForEach(Array(shapes.units.enumerated()), id: \.offset) { MapPolygon($0.element).foregroundStyle(.blue.opacity(0.18)).stroke(.blue, lineWidth: 1) }
                ForEach(Array(shapes.openings.enumerated()), id: \.offset) { MapPolyline($0.element).stroke(.orange, lineWidth: 3) }
            }
            .mapStyle(.standard(pointsOfInterest: .excludingAll))
            .frame(height: 320)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .id(levelID)
            Text("Gray: venue and level outline · Blue: \(shapes.units.count) units · Orange: \(shapes.openings.count) openings")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var cameraPosition: MapCameraPosition {
        guard let rect = geometry.boundingRect(for: levelID) else { return .automatic }
        return .rect(rect.insetBy(dx: -rect.width * 0.1, dy: -rect.height * 0.1))
    }
}
#endif
