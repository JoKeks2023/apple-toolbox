import SwiftUI
#if canImport(MapKit)
import MapKit
#endif

extension IndoorSurveyService: StoppableExperiment {}

struct IndoorSurveyRunView: View {
    @StateObject private var indoor = IndoorIMDFExperimentService()
    @StateObject private var survey = IndoorSurveyService()
    @State private var map = SurveyMapOptions()

    var body: some View {
        IMDFImportControls(indoor: indoor)
        if let summary = indoor.summary, !summary.levels.isEmpty {
            Picker("Level", selection: $indoor.selectedLevelID) {
                ForEach(summary.levels) { Text($0.title).tag(Optional($0.id)) }
            }
        } else if !indoor.isLoading {
            Text("No IMDF level imported: points are recorded on the plain map without a level.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        SurveyLocationControls(survey: survey)
        OutputView(text: survey.output, isError: survey.isError)
            .onChange(of: indoor.selectedLevelID, initial: true) { _, _ in survey.level = currentLevel }
            .onChange(of: indoor.summary?.source, initial: true) { _, source in survey.venue = source }
        #if canImport(MapKit)
        SurveyMapSection(survey: survey, indoor: indoor, options: $map)
        #endif
        SurveyRecordingControls(survey: survey)
        SurveyContentsView(survey: survey)
        SurveyHeatmapSettings(options: $map)
        SurveyCalibrationView(survey: survey)
        Section("Why are there no Wi-Fi fingerprints?") {
            Text("A fingerprint is the list of nearby access points with their signal strength (RSSI) at a spot. iOS and macOS give third-party apps no API to scan for access points or read their RSSI: NEHotspotNetwork.fetchCurrent returns only the joined network's SSID and BSSID (with an entitlement and location access), and per-network signal strength is reserved for approved Hotspot Helper apps. Apple collects fingerprints for indoor positioning with its own Indoor Survey app in the Indoor Maps Program. This utility therefore records what Core Location exposes: the resulting position, its reported accuracy and floor.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        SavedSurveysView(survey: survey)
        SurveyExportView(survey: survey)
    }

    private var currentLevel: SurveyLevel? {
        guard let level = indoor.summary?.levels.first(where: { $0.id == indoor.selectedLevelID }) else { return nil }
        return SurveyLevel(id: level.id, ordinal: level.ordinal, name: level.name)
    }
}

struct SurveyMapOptions {
    var showsHeatmap = true
    var metric = SurveyHeatmapMetric.accuracy
    var cellSize = 3.0
    var showsAllLevels = false

    static let cellSizes: [Double] = [1, 2, 3, 5, 10]
}

enum SurveyColors {
    static func color(for accuracyClass: SurveyAccuracyClass) -> Color {
        switch accuracyClass {
        case .excellent: .green
        case .good: .mint
        case .fair: .yellow
        case .poor: .orange
        case .bad: .red
        }
    }
}

private struct SurveyLocationControls: View {
    @ObservedObject var survey: IndoorSurveyService

    var body: some View {
        TextField("Survey name", text: $survey.surveyName)
            .onSubmit(survey.renameSurvey)
        HStack {
            Button(survey.isLocating ? "Stop Location" : "Start Location", systemImage: survey.isLocating ? "location.slash" : "location") {
                survey.isLocating ? survey.stop() : survey.startLocation()
            }
            .buttonStyle(.borderedProminent)
            .experimentSession(survey)
            Button("New Survey", systemImage: "plus", action: survey.newSurvey)
                .buttonStyle(.bordered)
        }
        if let fix = survey.liveFix {
            LabeledContent("Live fix") {
                Text("±\(TrackText.number(fix.horizontalAccuracy)) m · \(SurveyAccuracyClass(meters: fix.horizontalAccuracy).title)")
                    .foregroundStyle(SurveyColors.color(for: SurveyAccuracyClass(meters: fix.horizontalAccuracy)))
            }
        }
    }
}

#if canImport(MapKit)
private struct SurveyMapSection: View {
    @ObservedObject var survey: IndoorSurveyService
    @ObservedObject var indoor: IndoorIMDFExperimentService
    @Binding var options: SurveyMapOptions

    var body: some View {
        let levelID = indoor.selectedLevelID
        let visibleLevel = options.showsAllLevels ? nil : levelID
        let points = survey.survey.points.filter { visibleLevel == nil || $0.level?.id == visibleLevel }
        let paths = survey.survey.paths.filter { visibleLevel == nil || $0.level?.id == visibleLevel }
        let numbers = Dictionary(uniqueKeysWithValues: survey.survey.points.enumerated().map { ($0.element.id, $0.offset + 1) })
        let cells = options.showsHeatmap ? SurveyHeatmap.cells(for: SurveyHeatmap.samples(for: survey.survey, levelID: visibleLevel, metric: options.metric), cellSize: options.cellSize) : []
        Section("Survey map") {
            MapReader { proxy in
                Map(initialPosition: initialPosition(levelID: levelID)) {
                    if let geometry = indoor.geometry, let levelID {
                        IMDFLevelOverlays(geometry: geometry, levelID: levelID)
                    }
                    ForEach(cells) { cell in
                        MapPolygon(coordinates: cell.corners.map { Self.point($0) })
                            .foregroundStyle(SurveyColors.color(for: cell.accuracyClass).opacity(0.45))
                    }
                    ForEach(paths) { path in
                        MapPolyline(coordinates: path.samples.map { Self.point(latitude: $0.latitude, longitude: $0.longitude) })
                            .stroke(path.source == .walked ? Color.purple : Color.gray, style: StrokeStyle(lineWidth: 3, dash: path.source == .drawn ? [6, 4] : []))
                    }
                    if let walked = survey.walkedPath, walked.samples.count >= 2 {
                        MapPolyline(coordinates: walked.samples.map { Self.point(latitude: $0.latitude, longitude: $0.longitude) }).stroke(.purple, lineWidth: 4)
                    }
                    if let drawn = survey.drawnPath, drawn.samples.count >= 1 {
                        MapPolyline(coordinates: drawn.samples.map { Self.point(latitude: $0.latitude, longitude: $0.longitude) })
                            .stroke(.gray, style: StrokeStyle(lineWidth: 3, dash: [6, 4]))
                    }
                    ForEach(points) { point in
                        if let reference = point.reference, let measurement = point.measurement {
                            MapPolyline(coordinates: [Self.point(reference), Self.point(latitude: measurement.latitude, longitude: measurement.longitude)])
                                .stroke(.red, style: StrokeStyle(lineWidth: 2, dash: [4, 3]))
                            Annotation("", coordinate: Self.point(latitude: measurement.latitude, longitude: measurement.longitude)) {
                                Circle().stroke(.red, lineWidth: 2).frame(width: 10, height: 10)
                            }
                        }
                        if let coordinate = point.coordinate {
                            Annotation("P\(numbers[point.id] ?? 0)", coordinate: Self.point(coordinate)) {
                                Circle()
                                    .fill(point.measurement.map { SurveyColors.color(for: SurveyAccuracyClass(meters: $0.horizontalAccuracy)) } ?? .gray)
                                    .frame(width: 14, height: 14)
                                    .overlay(Circle().stroke(.white, lineWidth: 2))
                            }
                        }
                    }
                    if let reference = survey.pendingReference {
                        Marker("Reference", systemImage: "scope", coordinate: Self.point(reference)).tint(.red)
                    }
                    if let fix = survey.liveFix {
                        MapCircle(center: Self.point(latitude: fix.latitude, longitude: fix.longitude), radius: max(fix.horizontalAccuracy, 1))
                            .foregroundStyle(.blue.opacity(0.12))
                            .stroke(.blue.opacity(0.5), lineWidth: 1)
                        Annotation("You", coordinate: Self.point(latitude: fix.latitude, longitude: fix.longitude)) {
                            Circle().fill(.blue).frame(width: 12, height: 12).overlay(Circle().stroke(.white, lineWidth: 2))
                        }
                    }
                }
                .mapStyle(.standard(pointsOfInterest: .excludingAll))
                #if !os(tvOS)
                .onTapGesture { screenPoint in
                    guard let coordinate = proxy.convert(screenPoint, from: .local) else { return }
                    survey.handleTap(at: SurveyCoordinate(latitude: coordinate.latitude, longitude: coordinate.longitude))
                }
                #endif
            }
            .frame(height: 380)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .id("\(survey.survey.id)-\(levelID ?? "plain")")
            Text("Dots: survey points colored by reported accuracy (gray = reference only) · red dashes: error from reference to measured fix · purple: walked paths · gray dashes: drawn paths · squares: heatmap cells")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func initialPosition(levelID: String?) -> MapCameraPosition {
        if let geometry = indoor.geometry, let levelID, let rect = geometry.boundingRect(for: levelID) {
            return .rect(rect.insetBy(dx: -rect.width * 0.1, dy: -rect.height * 0.1))
        }
        let coordinates = survey.survey.points.compactMap(\.coordinate)
        if let first = coordinates.first {
            let points = coordinates.map { MKMapPoint(Self.point($0)) }
            let rect = points.reduce(MKMapRect(origin: MKMapPoint(Self.point(first)), size: MKMapSize(width: 0, height: 0))) { $0.union(MKMapRect(origin: $1, size: MKMapSize(width: 0, height: 0))) }
            let padding = max(rect.width, rect.height, 200) * 0.25
            return .rect(rect.insetBy(dx: -padding, dy: -padding))
        }
        return .userLocation(fallback: .automatic)
    }

    private static func point(_ coordinate: SurveyCoordinate) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }

    private static func point(latitude: Double, longitude: Double) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}
#endif

private struct SurveyRecordingControls: View {
    @ObservedObject var survey: IndoorSurveyService

    var body: some View {
        Section("Record") {
            Picker("Tap on map", selection: $survey.tapMode) {
                ForEach(IndoorSurveyService.TapMode.allCases) { Text($0.rawValue).tag($0) }
            }
            #if os(tvOS)
            Text("Apple TV cannot tap map positions; record at the current location instead.").font(.caption).foregroundStyle(.secondary)
            #endif
            Picker("Confidence", selection: $survey.confidence) {
                ForEach(SurveyConfidence.allCases) { Text($0.title).tag($0) }
            }
            Picker("Capture", selection: $survey.averaging) {
                ForEach(IndoorSurveyService.Averaging.allCases) { Text($0.title).tag($0) }
            }
            TextField("Note for the next point", text: $survey.note)
            if let reference = survey.pendingReference {
                LabeledContent("Pending reference") { Text(IndoorSurveyService.format(reference)).font(.caption.monospaced()) }
            }
            HStack {
                Button(survey.isCapturing ? "Capturing… \(survey.captureFixCount) fix(es)" : "Record at Current Location", systemImage: "location.viewfinder", action: survey.recordAtCurrentLocation)
                    .buttonStyle(.borderedProminent)
                    .disabled(survey.isCapturing)
                if survey.pendingReference != nil {
                    Button("Save Reference Only", action: survey.saveReferenceOnly).buttonStyle(.bordered)
                    Button("Discard", role: .destructive, action: survey.discardReference).buttonStyle(.bordered)
                }
            }
            HStack {
                Button(survey.walkedPath == nil ? "Start Walking Path" : "Finish Walking Path (\(survey.walkedPath?.samples.count ?? 0))", systemImage: "figure.walk") {
                    survey.walkedPath == nil ? survey.startWalkedPath() : survey.finishWalkedPath()
                }
                .buttonStyle(.bordered)
                if let drawn = survey.drawnPath {
                    Button("Finish Drawn Path (\(drawn.samples.count))", action: survey.finishDrawnPath).buttonStyle(.bordered)
                    Button("Undo Vertex", action: survey.undoVertex).buttonStyle(.bordered)
                }
            }
        }
    }
}

private struct SurveyContentsView: View {
    @ObservedObject var survey: IndoorSurveyService

    var body: some View {
        Section("Survey points (\(survey.survey.points.count))") {
            if survey.survey.points.isEmpty {
                Text("Tap a spot you can identify on the map, stand on it and record, or record at your current location without a reference.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(Array(survey.survey.points.enumerated()), id: \.element.id) { index, point in
                SurveyPointRow(index: index, point: point)
            }
            .onDelete(perform: survey.deletePoints)
        }
        Section("Paths (\(survey.survey.paths.count))") {
            if survey.survey.paths.isEmpty {
                Text("Start a walking path to record every fix while you walk, or pick “Draw path vertex” and tap the route on the map.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(survey.survey.paths) { path in
                VStack(alignment: .leading, spacing: 3) {
                    Label(path.name, systemImage: path.source == .walked ? "figure.walk" : "scribble")
                        .font(.headline)
                    Text("\(path.samples.count) \(path.source == .walked ? "fixes" : "vertices") · \(TrackText.meters(path.length))" + (path.level.map { " · \($0.name)" } ?? ""))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .onDelete(perform: survey.deletePaths)
        }
    }
}

private struct SurveyPointRow: View {
    let index: Int
    let point: SurveyPoint

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text("P\(index + 1)").font(.headline.monospaced())
                if let measurement = point.measurement {
                    Text("±\(TrackText.number(measurement.horizontalAccuracy)) m")
                        .foregroundStyle(SurveyColors.color(for: SurveyAccuracyClass(meters: measurement.horizontalAccuracy)))
                } else {
                    Text("Reference only").foregroundStyle(.secondary)
                }
                if let error = point.positionError {
                    Text("error \(TrackText.number(error)) m").foregroundStyle(.red)
                }
                Spacer()
                Text(point.confidence.rawValue.capitalized).font(.caption).foregroundStyle(.secondary)
            }
            if let measurement = point.measurement {
                Text("\(measurement.fixCount) fix(es) over \(TrackText.number(measurement.duration)) s · spread \(TrackText.number(measurement.spread)) m · best ±\(TrackText.number(measurement.bestAccuracy)) m")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text([point.level.map { "Level \($0.ordinal) · \($0.name)" } ?? "No IMDF level",
                  point.measurement?.floor.map { "CLFloor \($0)" } ?? "no CLFloor",
                  point.timestamp.formatted(date: .omitted, time: .standard)].joined(separator: " · "))
                .font(.caption)
                .foregroundStyle(.secondary)
            if point.floorMismatch {
                Label("Core Location floor differs from the IMDF level ordinal", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            if !point.note.isEmpty {
                Text(point.note).font(.caption)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct SurveyHeatmapSettings: View {
    @Binding var options: SurveyMapOptions

    var body: some View {
        Section("Heatmap") {
            Toggle("Show heatmap", isOn: $options.showsHeatmap)
            Picker("Metric", selection: $options.metric) {
                ForEach(SurveyHeatmapMetric.allCases) { Text($0.title).tag($0) }
            }
            Picker("Cell size", selection: $options.cellSize) {
                ForEach(SurveyMapOptions.cellSizes, id: \.self) { Text("\(Int($0)) m").tag($0) }
            }
            Toggle("Include all levels", isOn: $options.showsAllLevels)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(SurveyAccuracyClass.allCases) { accuracyClass in
                        HStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: 3).fill(SurveyColors.color(for: accuracyClass).opacity(0.6)).frame(width: 14, height: 14)
                            Text(accuracyClass.title).font(.caption2)
                        }
                    }
                }
            }
            Text("Each cell averages the reported horizontal accuracy (or the measured error against your reference points) of every point and walked-path fix inside it.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct SurveyCalibrationView: View {
    @ObservedObject var survey: IndoorSurveyService

    var body: some View {
        Section("Calibration guidance") {
            LabeledContent("Authorization", value: survey.authorization)
            LabeledContent("Location accuracy", value: survey.accuracyAuthorization)
            if survey.isReducedAccuracy {
                Button("Request Temporary Precise Location", action: survey.requestTemporaryPreciseLocation)
            }
            LabeledContent("Floor from Core Location", value: survey.liveFix.map { $0.floor.map { "Level \($0) · Apple indoor positioning active" } ?? "Not reported · no Apple indoor positioning here" } ?? "—")
            #if os(iOS)
            LabeledContent("Compass accuracy", value: survey.headingAccuracy.map { $0 < 0 ? "Invalid · calibrate" : "±\(TrackText.number($0))°" + ($0 > 20 ? " · move in a figure eight" : "") } ?? "—")
            #endif
            Text("""
            1. Start at a reference you can find on the map (door, anchor, corner), tap it, stand on it and record with 5–10 s averaging.
            2. Wait until the live accuracy stops improving before you record; the first fixes indoors are often coarse.
            3. Hold the device the same way at every point, at chest height, and do not cover the top edge.
            4. Keep Wi-Fi and Bluetooth on: Core Location uses them indoors even though apps cannot read them.
            5. Revisit a point later; a repeatable error vector means a positioning bias, a random one means noise.
            There is no public API to calibrate Apple's indoor positioning; these steps only make your measurements comparable.
            """)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}

private struct SavedSurveysView: View {
    @ObservedObject var survey: IndoorSurveyService

    var body: some View {
        Section("Saved surveys (\(survey.savedSurveys.count))") {
            Text(survey.storageDescription)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
            ForEach(survey.savedSurveys) { saved in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(saved.name).font(.headline)
                        Text("\(saved.points.count) point(s) · \(saved.paths.count) path(s) · \(saved.modified.formatted(date: .abbreviated, time: .shortened))" + (saved.venue.map { " · \($0)" } ?? ""))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if saved.id == survey.survey.id {
                        Text("Open").font(.caption).foregroundStyle(.secondary)
                    } else {
                        Button("Open") { survey.open(saved) }.buttonStyle(.borderless)
                    }
                    Button("Delete", role: .destructive) { survey.deleteSaved(saved) }.buttonStyle(.borderless)
                }
            }
        }
    }
}

private struct SurveyExportView: View {
    @ObservedObject var survey: IndoorSurveyService

    var body: some View {
        Section("Export") {
            Button("Export GeoJSON", systemImage: "doc.badge.arrow.up", action: survey.exportGeoJSON)
                .disabled(survey.survey.points.isEmpty && survey.survey.paths.isEmpty)
            #if !os(tvOS)
            if let url = survey.exportURL {
                ShareLink(item: url, preview: SharePreview(url.lastPathComponent)) {
                    Label("Share \(url.lastPathComponent)", systemImage: "square.and.arrow.up")
                }
            }
            #endif
        }
    }
}
