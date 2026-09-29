import Foundation
import Combine
#if canImport(CoreLocation)
import CoreLocation
#endif

// MARK: - Survey model

nonisolated struct SurveyCoordinate: Codable, Equatable, Sendable {
    var latitude: Double
    var longitude: Double
}

/// The IMDF level a point or path was recorded on.
nonisolated struct SurveyLevel: Codable, Equatable, Sendable {
    var id: String
    var ordinal: Int
    var name: String
}

/// How sure the surveyor is that the tapped reference position is where they really stood.
nonisolated enum SurveyConfidence: String, Codable, CaseIterable, Identifiable, Sendable {
    case high, medium, low

    var id: String { rawValue }
    var title: String {
        switch self {
        case .high: "High · exact spot (door, anchor, corner)"
        case .medium: "Medium · within about a meter"
        case .low: "Low · rough estimate"
        }
    }
}

/// One Core Location fix used for a survey measurement.
nonisolated struct SurveyFix: Equatable, Sendable {
    var latitude: Double
    var longitude: Double
    var horizontalAccuracy: Double
    var altitude: Double?
    var verticalAccuracy: Double?
    var floor: Int?
    var timestamp: Date
}

/// Position reported by Core Location for a survey point, averaged over the capture window.
nonisolated struct SurveyMeasurement: Codable, Equatable, Sendable {
    var latitude: Double
    var longitude: Double
    /// Median horizontal accuracy Core Location reported for the fixes, in meters.
    var horizontalAccuracy: Double
    var bestAccuracy: Double
    /// Root-mean-square distance of the fixes from their averaged position, in meters.
    var spread: Double
    var altitude: Double?
    var verticalAccuracy: Double?
    /// `CLFloor.level`, only reported in venues with Apple indoor positioning.
    var floor: Int?
    var fixCount: Int
    var duration: TimeInterval

    /// Inverse-variance weighted mean of the fixes with a valid accuracy.
    static func average(of fixes: [SurveyFix]) -> SurveyMeasurement? {
        let valid = fixes.filter { $0.horizontalAccuracy > 0 }
        guard let first = valid.first else { return nil }
        let weights = valid.map { 1 / ($0.horizontalAccuracy * $0.horizontalAccuracy) }
        let total = weights.reduce(0, +)
        let latitude = zip(valid, weights).reduce(0) { $0 + $1.0.latitude * $1.1 } / total
        let longitude = zip(valid, weights).reduce(0) { $0 + $1.0.longitude * $1.1 } / total
        let squared = valid.map { pow(Geodesy.distance(fromLatitude: latitude, longitude: longitude, toLatitude: $0.latitude, longitude: $0.longitude), 2) }
        let accuracies = valid.map(\.horizontalAccuracy).sorted()
        let middle = accuracies.count / 2
        let median = accuracies.count.isMultiple(of: 2) ? (accuracies[middle - 1] + accuracies[middle]) / 2 : accuracies[middle]
        let altitudes = valid.compactMap { fix in fix.verticalAccuracy.flatMap { $0 > 0 ? fix.altitude : nil } }
        let verticals = valid.compactMap { $0.verticalAccuracy }.filter { $0 > 0 }
        let floors = valid.compactMap(\.floor)
        let mostCommonFloor = Dictionary(grouping: floors, by: { $0 }).max { $0.value.count < $1.value.count }?.key
        let timestamps = valid.map(\.timestamp)
        return SurveyMeasurement(
            latitude: latitude, longitude: longitude,
            horizontalAccuracy: median, bestAccuracy: accuracies[0],
            spread: (squared.reduce(0, +) / Double(squared.count)).squareRoot(),
            altitude: altitudes.isEmpty ? nil : altitudes.reduce(0, +) / Double(altitudes.count),
            verticalAccuracy: verticals.isEmpty ? nil : verticals.reduce(0, +) / Double(verticals.count),
            floor: mostCommonFloor ?? first.floor, fixCount: valid.count,
            duration: (timestamps.max() ?? first.timestamp).timeIntervalSince(timestamps.min() ?? first.timestamp))
    }
}

nonisolated struct SurveyPoint: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var timestamp: Date
    /// Where the surveyor says they stood (tapped on the map).
    var reference: SurveyCoordinate?
    /// What Core Location reported at that moment.
    var measurement: SurveyMeasurement?
    var level: SurveyLevel?
    var confidence: SurveyConfidence
    var note: String

    /// Reference position if known, otherwise the measured one.
    var coordinate: SurveyCoordinate? {
        reference ?? measurement.map { SurveyCoordinate(latitude: $0.latitude, longitude: $0.longitude) }
    }

    /// Distance from the reference to the measured position: the positioning error at this spot.
    var positionError: Double? {
        guard let reference, let measurement else { return nil }
        return Geodesy.distance(fromLatitude: reference.latitude, longitude: reference.longitude, toLatitude: measurement.latitude, longitude: measurement.longitude)
    }

    /// Core Location reported a floor that differs from the IMDF level's ordinal.
    var floorMismatch: Bool {
        guard let floor = measurement?.floor, let level else { return false }
        return floor != level.ordinal
    }
}

nonisolated struct SurveyPathSample: Codable, Equatable, Sendable {
    var latitude: Double
    var longitude: Double
    /// nil for vertices drawn on the map.
    var horizontalAccuracy: Double?
    var floor: Int?
    var timestamp: Date
}

nonisolated struct SurveyPath: Identifiable, Codable, Equatable, Sendable {
    nonisolated enum Source: String, Codable, Sendable { case walked, drawn }

    var id = UUID()
    var name: String
    var source: Source
    var started: Date
    var level: SurveyLevel?
    var samples: [SurveyPathSample] = []

    var length: Double {
        zip(samples, samples.dropFirst()).reduce(0) { total, pair in
            total + Geodesy.distance(fromLatitude: pair.0.latitude, longitude: pair.0.longitude, toLatitude: pair.1.latitude, longitude: pair.1.longitude)
        }
    }
}

nonisolated struct IndoorSurvey: Identifiable, Codable, Equatable, Sendable {
    static let currentVersion = 1

    var version = IndoorSurvey.currentVersion
    var id = UUID()
    var name: String
    var created: Date
    var modified: Date
    /// Source of the IMDF archive the survey was recorded on, if any.
    var venue: String?
    var points: [SurveyPoint] = []
    var paths: [SurveyPath] = []

    static func named(_ date: Date) -> IndoorSurvey {
        IndoorSurvey(name: "Survey " + date.formatted(date: .abbreviated, time: .shortened), created: date, modified: date)
    }
}

// MARK: - Heatmap

nonisolated enum SurveyHeatmapMetric: String, CaseIterable, Identifiable, Sendable {
    case accuracy, error

    var id: String { rawValue }
    var title: String { self == .accuracy ? "Reported accuracy" : "Measured error (reference vs. fix)" }
}

/// Accuracy classes used for colors and the legend.
nonisolated enum SurveyAccuracyClass: Int, CaseIterable, Identifiable, Sendable {
    case excellent, good, fair, poor, bad

    var id: Int { rawValue }

    init(meters: Double) {
        self = switch meters {
        case ..<3: .excellent
        case ..<8: .good
        case ..<15: .fair
        case ..<30: .poor
        default: .bad
        }
    }

    var title: String {
        switch self {
        case .excellent: "< 3 m"
        case .good: "3–8 m"
        case .fair: "8–15 m"
        case .poor: "15–30 m"
        case .bad: "≥ 30 m"
        }
    }
}

nonisolated struct SurveyHeatmapCell: Identifiable, Equatable, Sendable {
    let column: Int
    let row: Int
    /// Corners in drawing order (south-west, south-east, north-east, north-west).
    let corners: [SurveyCoordinate]
    let meanValue: Double
    let count: Int

    var id: String { "\(column):\(row)" }
    var accuracyClass: SurveyAccuracyClass { SurveyAccuracyClass(meters: meanValue) }
}

/// Bins samples into square cells of a local metric grid and averages their value per cell.
nonisolated enum SurveyHeatmap {
    nonisolated struct Sample: Equatable, Sendable {
        let coordinate: SurveyCoordinate
        let value: Double
    }

    static let metersPerDegree = Geodesy.earthRadius * .pi / 180

    static func samples(for survey: IndoorSurvey, levelID: String?, metric: SurveyHeatmapMetric) -> [Sample] {
        let points = survey.points.filter { levelID == nil || $0.level?.id == levelID }
        switch metric {
        case .error:
            return points.compactMap { point in
                guard let error = point.positionError, let reference = point.reference else { return nil }
                return Sample(coordinate: reference, value: error)
            }
        case .accuracy:
            let pointSamples = points.compactMap { point -> Sample? in
                guard let measurement = point.measurement, let coordinate = point.coordinate else { return nil }
                return Sample(coordinate: coordinate, value: measurement.horizontalAccuracy)
            }
            let pathSamples = survey.paths.filter { levelID == nil || $0.level?.id == levelID }.flatMap(\.samples).compactMap { sample -> Sample? in
                guard let accuracy = sample.horizontalAccuracy, accuracy >= 0 else { return nil }
                return Sample(coordinate: SurveyCoordinate(latitude: sample.latitude, longitude: sample.longitude), value: accuracy)
            }
            return pointSamples + pathSamples
        }
    }

    static func cells(for samples: [Sample], cellSize: Double) -> [SurveyHeatmapCell] {
        guard let origin = samples.first?.coordinate, cellSize > 0 else { return [] }
        let metersPerLongitudeDegree = metersPerDegree * cos(origin.latitude * .pi / 180)
        guard metersPerLongitudeDegree > 0 else { return [] }
        var bins: [[Int]: (sum: Double, count: Int)] = [:]
        for sample in samples {
            let x = (sample.coordinate.longitude - origin.longitude) * metersPerLongitudeDegree
            let y = (sample.coordinate.latitude - origin.latitude) * metersPerDegree
            let key = [Int((x / cellSize).rounded(.down)), Int((y / cellSize).rounded(.down))]
            bins[key, default: (0, 0)].sum += sample.value
            bins[key, default: (0, 0)].count += 1
        }
        func coordinate(_ column: Int, _ row: Int) -> SurveyCoordinate {
            SurveyCoordinate(latitude: origin.latitude + Double(row) * cellSize / metersPerDegree,
                             longitude: origin.longitude + Double(column) * cellSize / metersPerLongitudeDegree)
        }
        return bins.map { key, bin in
            let column = key[0], row = key[1]
            return SurveyHeatmapCell(column: column, row: row,
                                     corners: [coordinate(column, row), coordinate(column + 1, row), coordinate(column + 1, row + 1), coordinate(column, row + 1)],
                                     meanValue: bin.sum / Double(bin.count), count: bin.count)
        }
        .sorted { ($0.row, $0.column) < ($1.row, $1.column) }
    }
}

// MARK: - Persistence and export

/// Stores surveys as JSON files: in the app container's Documents folder on iOS and iPadOS, and in Application Support
/// on macOS, where the unsandboxed app's Documents folder would be the user's own and trigger a privacy prompt.
nonisolated enum IndoorSurveyStore {
    static let folderName = "IndoorSurveys"

    static func defaultDirectory() throws -> URL {
        #if os(macOS)
        let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        return support.appendingPathComponent(Bundle.main.bundleIdentifier ?? "AppleToolbox", isDirectory: true).appendingPathComponent(folderName, isDirectory: true)
        #else
        let documents = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        return documents.appendingPathComponent(folderName, isDirectory: true)
        #endif
    }

    static func fileURL(for id: UUID, in directory: URL) -> URL {
        directory.appendingPathComponent("\(id.uuidString).json")
    }

    static func encode(_ survey: IndoorSurvey) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(survey)
    }

    static func decode(_ data: Data) throws -> IndoorSurvey {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(IndoorSurvey.self, from: data)
    }

    static func save(_ survey: IndoorSurvey, in directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try encode(survey).write(to: fileURL(for: survey.id, in: directory), options: .atomic)
    }

    /// Loads every readable survey, newest first; unreadable files are reported by name.
    static func loadAll(in directory: URL) -> (surveys: [IndoorSurvey], failures: [String]) {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        var surveys: [IndoorSurvey] = []
        var failures: [String] = []
        for file in files where file.pathExtension == "json" {
            do { surveys.append(try decode(Data(contentsOf: file))) } catch { failures.append(file.lastPathComponent) }
        }
        return (surveys.sorted { $0.modified > $1.modified }, failures)
    }

    static func delete(_ id: UUID, in directory: URL) throws {
        let url = fileURL(for: id, in: directory)
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }
}

/// Exports a survey as a GeoJSON FeatureCollection (RFC 7946): points as Point features, paths as LineStrings.
nonisolated enum IndoorSurveyExporter {
    static func geoJSON(_ survey: IndoorSurvey) throws -> Data {
        var features: [[String: Any]] = []
        for point in survey.points {
            guard let coordinate = point.coordinate else { continue }
            var properties: [String: Any] = [
                "kind": "survey_point",
                "id": point.id.uuidString,
                "timestamp": timestamp(point.timestamp),
                "confidence": point.confidence.rawValue,
                "note": point.note,
                "position_source": point.reference != nil ? "reference" : "measured",
            ]
            addLevel(point.level, to: &properties)
            if let reference = point.reference { properties["reference"] = [reference.longitude, reference.latitude] }
            if let measurement = point.measurement {
                properties["measured"] = [measurement.longitude, measurement.latitude]
                properties["horizontal_accuracy_m"] = measurement.horizontalAccuracy
                properties["best_accuracy_m"] = measurement.bestAccuracy
                properties["spread_m"] = measurement.spread
                properties["fix_count"] = measurement.fixCount
                properties["capture_seconds"] = measurement.duration
                if let floor = measurement.floor { properties["cl_floor"] = floor }
                if let altitude = measurement.altitude { properties["altitude_m"] = altitude }
                if let vertical = measurement.verticalAccuracy { properties["vertical_accuracy_m"] = vertical }
            }
            if let error = point.positionError { properties["position_error_m"] = error }
            features.append(["type": "Feature", "id": point.id.uuidString,
                             "geometry": ["type": "Point", "coordinates": [coordinate.longitude, coordinate.latitude]],
                             "properties": properties])
        }
        for path in survey.paths where path.samples.count >= 2 {
            var properties: [String: Any] = [
                "kind": path.source == .walked ? "walking_path" : "drawn_path",
                "id": path.id.uuidString,
                "name": path.name,
                "started": timestamp(path.started),
                "length_m": path.length,
                "coordinateProperties": [
                    "times": path.samples.map { timestamp($0.timestamp) },
                    "horizontal_accuracy_m": path.samples.map { orNull($0.horizontalAccuracy) },
                    "cl_floor": path.samples.map { orNull($0.floor) },
                ] as [String: Any],
            ]
            addLevel(path.level, to: &properties)
            features.append(["type": "Feature", "id": path.id.uuidString,
                             "geometry": ["type": "LineString", "coordinates": path.samples.map { [$0.longitude, $0.latitude] }],
                             "properties": properties])
        }
        var collection: [String: Any] = [
            "type": "FeatureCollection",
            "name": survey.name,
            "survey_id": survey.id.uuidString,
            "created": timestamp(survey.created),
            "modified": timestamp(survey.modified),
            "generator": "Apple Toolbox Indoor Survey",
            "features": features,
        ]
        if let venue = survey.venue { collection["venue"] = venue }
        return try JSONSerialization.data(withJSONObject: collection, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    }

    private static func addLevel(_ level: SurveyLevel?, to properties: inout [String: Any]) {
        guard let level else { return }
        properties["level_id"] = level.id
        properties["level_ordinal"] = level.ordinal
        properties["level_name"] = level.name
    }

    private static func timestamp(_ date: Date) -> String { date.formatted(.iso8601) }

    private static func orNull<Value>(_ value: Value?) -> Any { value.map { $0 as Any } ?? NSNull() }
}

// MARK: - Service

@MainActor
final class IndoorSurveyService: NSObject, ObservableObject {
    enum TapMode: String, CaseIterable, Identifiable {
        case point = "Place reference point", pathVertex = "Draw path vertex", none = "Pan only"
        var id: String { rawValue }
    }

    enum Averaging: Int, CaseIterable, Identifiable {
        case instant = 0, fiveSeconds = 5, tenSeconds = 10, thirtySeconds = 30
        var id: Int { rawValue }
        var title: String { self == .instant ? "Latest fix" : "Average over \(rawValue) s" }
    }

    @Published private(set) var survey: IndoorSurvey
    @Published private(set) var savedSurveys: [IndoorSurvey] = []
    @Published var surveyName: String
    @Published var tapMode = TapMode.point
    @Published var averaging = Averaging.fiveSeconds
    @Published var confidence = SurveyConfidence.high
    @Published var note = ""
    @Published private(set) var pendingReference: SurveyCoordinate?
    @Published private(set) var drawnPath: SurveyPath?
    @Published private(set) var walkedPath: SurveyPath?
    @Published private(set) var isLocating = false
    @Published private(set) var isCapturing = false
    @Published private(set) var captureFixCount = 0
    @Published private(set) var liveFix: SurveyFix?
    @Published private(set) var headingAccuracy: Double?
    @Published private(set) var authorization = "Not determined"
    @Published private(set) var accuracyAuthorization = "—"
    @Published private(set) var isReducedAccuracy = false
    @Published private(set) var exportURL: URL?
    @Published private(set) var isError = false
    @Published private(set) var output = "Import an IMDF level (optional), start location, then tap reference points or record at your position."

    /// The IMDF level new points and paths are recorded on; set by the run view.
    var level: SurveyLevel?
    /// Source of the imported IMDF archive, stored with the survey.
    var venue: String?

    private let directory: URL?
    private var captureFixes: [SurveyFix] = []
    private var captureTask: Task<Void, Never>?
    #if canImport(CoreLocation)
    private let manager = CLLocationManager()
    #endif

    override init() {
        let survey = IndoorSurvey.named(Date())
        self.survey = survey
        surveyName = survey.name
        directory = try? IndoorSurveyStore.defaultDirectory()
        super.init()
        #if canImport(CoreLocation)
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        updateAuthorization(manager.authorizationStatus, accuracy: manager.accuracyAuthorization)
        #endif
        reloadSavedSurveys()
    }

    var isActive: Bool { isLocating || isCapturing || walkedPath != nil }

    var storageDescription: String {
        directory.map { "Saved as JSON in \($0.path)" } ?? "Storage folder unavailable; surveys stay in memory"
    }

    // MARK: Location

    func startLocation() {
        #if canImport(CoreLocation) && !os(tvOS)
        guard !isLocating else { return }
        if manager.authorizationStatus == .notDetermined { manager.requestWhenInUseAuthorization() }
        manager.startUpdatingLocation()
        #if os(iOS)
        if CLLocationManager.headingAvailable() { manager.startUpdatingHeading() }
        #endif
        isLocating = true
        report("Location updates started. Wait until the accuracy settles before recording.")
        #else
        report("Continuous location updates are not available on this platform.", isError: true)
        #endif
    }

    func stopLocation() {
        #if canImport(CoreLocation) && !os(tvOS)
        manager.stopUpdatingLocation()
        #if os(iOS)
        manager.stopUpdatingHeading()
        #endif
        #endif
        isLocating = false
    }

    /// Stops location, a running capture and a walked path (the path is kept).
    func stop() {
        captureTask?.cancel()
        captureTask = nil
        isCapturing = false
        if walkedPath != nil { finishWalkedPath() }
        stopLocation()
    }

    func requestTemporaryPreciseLocation() {
        #if canImport(CoreLocation)
        Task {
            do {
                try await manager.requestTemporaryFullAccuracyAuthorization(withPurposeKey: LocationExperimentService.fullAccuracyPurposeKey)
                updateAuthorization(manager.authorizationStatus, accuracy: manager.accuracyAuthorization)
                report(isReducedAccuracy ? "Precise location was not granted; survey points stay approximate." : "Precise location granted temporarily.")
            } catch {
                report("Temporary precise location failed: \(error.localizedDescription)", isError: true)
            }
        }
        #endif
    }

    // MARK: Map interaction

    func handleTap(at coordinate: SurveyCoordinate) {
        switch tapMode {
        case .point:
            pendingReference = coordinate
            report("Reference set at \(Self.format(coordinate)). Record at your current location to measure the error there, or save the reference alone.")
        case .pathVertex:
            var path = drawnPath ?? SurveyPath(name: "Drawn path \(survey.paths.count + 1)", source: .drawn, started: Date(), level: level)
            path.samples.append(SurveyPathSample(latitude: coordinate.latitude, longitude: coordinate.longitude, horizontalAccuracy: nil, floor: nil, timestamp: Date()))
            drawnPath = path
            report("Vertex \(path.samples.count) added · \(Self.meters(path.length)) so far.")
        case .none:
            break
        }
    }

    func discardReference() { pendingReference = nil }

    // MARK: Points

    /// Saves the tapped reference without a Core Location measurement (for example a planned test point).
    func saveReferenceOnly() {
        guard let reference = pendingReference else { return }
        addPoint(SurveyPoint(timestamp: Date(), reference: reference, measurement: nil, level: level, confidence: confidence, note: note))
        pendingReference = nil
    }

    func recordAtCurrentLocation() {
        guard !isCapturing else { return }
        guard isLocating else {
            startLocation()
            report("Location updates were off; they are starting now. Record again once a fix is shown.")
            return
        }
        if averaging == .instant {
            guard let fix = liveFix, Date().timeIntervalSince(fix.timestamp) < 10 else {
                report("No fix from the last 10 seconds yet. Wait for the live accuracy to appear.", isError: true)
                return
            }
            finishCapture(with: [fix])
            return
        }
        captureFixes = []
        captureFixCount = 0
        isCapturing = true
        report("Hold still: averaging fixes for \(averaging.rawValue) s…")
        let seconds = averaging.rawValue
        captureTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard let self, !Task.isCancelled else { return }
            self.isCapturing = false
            self.finishCapture(with: self.captureFixes)
        }
    }

    private func finishCapture(with fixes: [SurveyFix]) {
        guard let measurement = SurveyMeasurement.average(of: fixes) else {
            report("No usable fix arrived during the capture window. Check the location permission and try again.", isError: true)
            return
        }
        let point = SurveyPoint(timestamp: Date(), reference: pendingReference, measurement: measurement, level: level, confidence: confidence, note: note)
        addPoint(point)
        pendingReference = nil
        var lines = ["Point \(survey.points.count) recorded from \(measurement.fixCount) fix(es): ±\(Self.number(measurement.horizontalAccuracy)) m reported, spread \(Self.number(measurement.spread)) m."]
        if let error = point.positionError { lines.append("Error against the reference: \(Self.number(error)) m.") }
        if point.floorMismatch, let floor = measurement.floor, let level = point.level {
            lines.append("Core Location reports floor \(floor), but the IMDF level ordinal is \(level.ordinal).")
        }
        report(lines.joined(separator: "\n"))
    }

    private func addPoint(_ point: SurveyPoint) {
        survey.points.append(point)
        note = ""
        persist()
    }

    func deletePoints(at offsets: IndexSet) {
        for index in offsets.sorted(by: >) where survey.points.indices.contains(index) { survey.points.remove(at: index) }
        persist()
    }

    // MARK: Paths

    func startWalkedPath() {
        guard walkedPath == nil else { return }
        if !isLocating { startLocation() }
        walkedPath = SurveyPath(name: "Walking path \(survey.paths.count + 1)", source: .walked, started: Date(), level: level)
        report("Walking path started. Every Core Location fix is added with its accuracy.")
    }

    func finishWalkedPath() {
        guard let path = walkedPath else { return }
        walkedPath = nil
        guard path.samples.count >= 2 else {
            report("The walking path had fewer than two fixes and was discarded.", isError: true)
            return
        }
        survey.paths.append(path)
        persist()
        report("\(path.name) saved: \(path.samples.count) fixes, \(Self.meters(path.length)).")
    }

    func finishDrawnPath() {
        guard let path = drawnPath else { return }
        drawnPath = nil
        guard path.samples.count >= 2 else {
            report("A drawn path needs at least two vertices.", isError: true)
            return
        }
        survey.paths.append(path)
        persist()
        report("\(path.name) saved: \(path.samples.count) vertices, \(Self.meters(path.length)).")
    }

    func undoVertex() {
        guard var path = drawnPath else { return }
        path.samples.removeLast()
        drawnPath = path.samples.isEmpty ? nil : path
    }

    func deletePaths(at offsets: IndexSet) {
        for index in offsets.sorted(by: >) where survey.paths.indices.contains(index) { survey.paths.remove(at: index) }
        persist()
    }

    // MARK: Surveys

    func renameSurvey() {
        let name = surveyName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name != survey.name else { surveyName = survey.name; return }
        survey.name = name
        // An empty survey is only written once it has content.
        if !survey.points.isEmpty || !survey.paths.isEmpty || savedSurveys.contains(where: { $0.id == survey.id }) { persist() }
    }

    func newSurvey() {
        stop()
        survey = IndoorSurvey.named(Date())
        surveyName = survey.name
        pendingReference = nil
        drawnPath = nil
        exportURL = nil
        report("Started \(survey.name). It is saved automatically after the first point or path.")
    }

    func open(_ saved: IndoorSurvey) {
        stop()
        survey = saved
        surveyName = saved.name
        pendingReference = nil
        drawnPath = nil
        exportURL = nil
        report("Opened \(saved.name): \(saved.points.count) point(s), \(saved.paths.count) path(s).")
    }

    func deleteSaved(_ saved: IndoorSurvey) {
        guard let directory else { return }
        do {
            try IndoorSurveyStore.delete(saved.id, in: directory)
            if saved.id == survey.id { newSurvey() }
            reloadSavedSurveys()
        } catch {
            report("Could not delete \(saved.name): \(error.localizedDescription)", isError: true)
        }
    }

    func exportGeoJSON() {
        renameSurvey()
        do {
            let data = try IndoorSurveyExporter.geoJSON(survey)
            let safeName = survey.name.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: "-")
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(safeName.isEmpty ? "Survey" : safeName).geojson")
            try data.write(to: url, options: .atomic)
            exportURL = url
            report("Exported \(survey.points.count) point(s) and \(survey.paths.count) path(s) to \(url.lastPathComponent) (\(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file))).")
        } catch {
            exportURL = nil
            report("GeoJSON export failed: \(error.localizedDescription)", isError: true)
        }
    }

    private func persist() {
        survey.modified = Date()
        if survey.venue == nil { survey.venue = venue }
        exportURL = nil
        guard let directory else {
            report("The storage folder is unavailable; the survey is kept in memory only.", isError: true)
            return
        }
        do {
            try IndoorSurveyStore.save(survey, in: directory)
            reloadSavedSurveys()
        } catch {
            report("Saving the survey failed: \(error.localizedDescription)", isError: true)
        }
    }

    private func reloadSavedSurveys() {
        guard let directory else { return }
        let result = IndoorSurveyStore.loadAll(in: directory)
        savedSurveys = result.surveys
        if !result.failures.isEmpty {
            report("Skipped unreadable survey file(s): \(result.failures.joined(separator: ", "))", isError: true)
        }
    }

    private func report(_ message: String, isError: Bool = false) {
        output = message
        self.isError = isError
    }

    static func format(_ coordinate: SurveyCoordinate) -> String {
        String(format: "%.6f, %.6f", coordinate.latitude, coordinate.longitude)
    }

    private static func number(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1)))
    }

    private static func meters(_ value: Double) -> String {
        value >= 1_000 ? (value / 1_000).formatted(.number.precision(.fractionLength(2))) + " km" : number(value) + " m"
    }

    // MARK: Core Location callbacks

    #if canImport(CoreLocation)
    fileprivate func updateAuthorization(_ status: CLAuthorizationStatus, accuracy: CLAccuracyAuthorization) {
        authorization = switch status {
        case .notDetermined: "Not determined"
        case .restricted: "Restricted"
        case .denied: "Denied"
        case .authorizedAlways: "Authorized · Always"
        case .authorizedWhenInUse: "Authorized · When In Use"
        @unknown default: "Unknown"
        }
        #if os(macOS)
        let isAuthorized = status == .authorizedAlways
        #else
        let isAuthorized = status == .authorizedAlways || status == .authorizedWhenInUse
        #endif
        isReducedAccuracy = isAuthorized && accuracy == .reducedAccuracy
        accuracyAuthorization = !isAuthorized ? "—" : accuracy == .fullAccuracy ? "Precise" : "Approximate"
        if status == .denied || status == .restricted, isLocating {
            report("Location access is \(authorization.lowercased()); survey points can only be placed by tapping the map.", isError: true)
        }
    }
    #endif

    fileprivate func apply(_ fix: SurveyFix) {
        liveFix = fix
        if isCapturing {
            captureFixes.append(fix)
            captureFixCount = captureFixes.count
        }
        if var path = walkedPath {
            path.samples.append(SurveyPathSample(latitude: fix.latitude, longitude: fix.longitude, horizontalAccuracy: fix.horizontalAccuracy, floor: fix.floor, timestamp: fix.timestamp))
            walkedPath = path
        }
    }

    fileprivate func applyHeadingAccuracy(_ accuracy: Double) {
        headingAccuracy = accuracy
    }

    fileprivate func fail(_ message: String) {
        report("Location error: \(message)", isError: true)
    }
}

#if canImport(CoreLocation)
// The manager is created on the main thread, so callbacks arrive there; values are copied into
// Sendable structs before hopping to the main actor so the conformance stays nonisolated.
extension IndoorSurveyService: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        let accuracy = manager.accuracyAuthorization
        Task { @MainActor [weak self] in
            self?.updateAuthorization(status, accuracy: accuracy)
            PermissionCenter.shared.invalidate()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let fixes = locations.map { location in
            SurveyFix(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude,
                      horizontalAccuracy: location.horizontalAccuracy,
                      altitude: location.verticalAccuracy > 0 ? location.altitude : nil,
                      verticalAccuracy: location.verticalAccuracy > 0 ? location.verticalAccuracy : nil,
                      floor: location.floor?.level, timestamp: location.timestamp)
        }
        Task { @MainActor [weak self] in fixes.forEach { self?.apply($0) } }
    }

    #if os(iOS)
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        let accuracy = newHeading.headingAccuracy
        Task { @MainActor [weak self] in self?.applyHeadingAccuracy(accuracy) }
    }
    #endif

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard (error as NSError).code != CLError.locationUnknown.rawValue else { return }
        let message = error.localizedDescription
        Task { @MainActor [weak self] in self?.fail(message) }
    }
}
#endif
