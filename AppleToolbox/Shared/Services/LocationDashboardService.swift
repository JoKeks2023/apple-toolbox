import Foundation
import Combine
#if canImport(CoreLocation)
import CoreLocation
#endif

/// One recorded Core Location fix. Negative accuracies, speeds and courses mean "invalid", as in `CLLocation`.
nonisolated struct LocationTrackSample: Identifiable, Equatable, Sendable {
    let id: Int
    let timestamp: Date
    let latitude: Double
    let longitude: Double
    /// Meters above mean sea level; only meaningful when `verticalAccuracy > 0`.
    let altitude: Double
    let ellipsoidalAltitude: Double
    let horizontalAccuracy: Double
    let verticalAccuracy: Double
    let speed: Double
    let speedAccuracy: Double
    let course: Double
    let courseAccuracy: Double
    let floor: Int?
    let isSimulated: Bool
    let isFromAccessory: Bool

    init(id: Int, timestamp: Date, latitude: Double, longitude: Double, altitude: Double = 0, ellipsoidalAltitude: Double = 0,
         horizontalAccuracy: Double, verticalAccuracy: Double = -1, speed: Double = -1, speedAccuracy: Double = -1,
         course: Double = -1, courseAccuracy: Double = -1, floor: Int? = nil, isSimulated: Bool = false, isFromAccessory: Bool = false) {
        self.id = id
        self.timestamp = timestamp
        self.latitude = latitude
        self.longitude = longitude
        self.altitude = altitude
        self.ellipsoidalAltitude = ellipsoidalAltitude
        self.horizontalAccuracy = horizontalAccuracy
        self.verticalAccuracy = verticalAccuracy
        self.speed = speed
        self.speedAccuracy = speedAccuracy
        self.course = course
        self.courseAccuracy = courseAccuracy
        self.floor = floor
        self.isSimulated = isSimulated
        self.isFromAccessory = isFromAccessory
    }

    var hasValidAltitude: Bool { verticalAccuracy > 0 }
    var hasValidSpeed: Bool { speed >= 0 }
    var hasValidHorizontalAccuracy: Bool { horizontalAccuracy >= 0 }

    /// Evenly thins a track for charts, always keeping the first and last sample.
    static func downsampled(_ samples: [LocationTrackSample], maxCount: Int) -> [LocationTrackSample] {
        guard maxCount > 1, samples.count > maxCount else { return samples }
        let step = Double(samples.count - 1) / Double(maxCount - 1)
        return (0..<maxCount).map { samples[Int((Double($0) * step).rounded())] }
    }
}

nonisolated enum Geodesy {
    /// Mean Earth radius (IUGG) in meters.
    static let earthRadius = 6_371_008.8

    /// Great-circle distance in meters (haversine).
    static func distance(fromLatitude lat1: Double, longitude lon1: Double, toLatitude lat2: Double, longitude lon2: Double) -> Double {
        let phi1 = lat1 * .pi / 180, phi2 = lat2 * .pi / 180
        let deltaPhi = (lat2 - lat1) * .pi / 180, deltaLambda = (lon2 - lon1) * .pi / 180
        let h = sin(deltaPhi / 2) * sin(deltaPhi / 2) + cos(phi1) * cos(phi2) * sin(deltaLambda / 2) * sin(deltaLambda / 2)
        return 2 * earthRadius * asin(min(1, h.squareRoot()))
    }
}

/// Session statistics for a recorded track.
nonisolated struct LocationTrackStatistics: Equatable, Sendable {
    /// Fixes worse than this are ignored for the distance so GPS jumps do not inflate it.
    static let defaultAccuracyLimit: Double = 50
    /// Altitude changes smaller than this are treated as noise for gain and loss.
    static let defaultElevationThreshold: Double = 3

    var sampleCount = 0
    var distanceSampleCount = 0
    var duration: TimeInterval = 0
    var distance: Double = 0
    var maxSpeed: Double?
    var averageSpeed: Double?
    var minAltitude: Double?
    var maxAltitude: Double?
    var elevationGain: Double = 0
    var elevationLoss: Double = 0
    var bestAccuracy: Double?
    var worstAccuracy: Double?
    var medianAccuracy: Double?
    var floors: [Int] = []
    var simulatedSamples = 0

    init() {}

    init(samples: [LocationTrackSample], accuracyLimit: Double = defaultAccuracyLimit, elevationThreshold: Double = defaultElevationThreshold) {
        sampleCount = samples.count
        guard let first = samples.first, let last = samples.last else { return }
        duration = max(0, last.timestamp.timeIntervalSince(first.timestamp))

        var previous: LocationTrackSample?
        for sample in samples where sample.hasValidHorizontalAccuracy && sample.horizontalAccuracy <= accuracyLimit {
            distanceSampleCount += 1
            if let previous {
                distance += Geodesy.distance(fromLatitude: previous.latitude, longitude: previous.longitude, toLatitude: sample.latitude, longitude: sample.longitude)
            }
            previous = sample
        }
        averageSpeed = duration > 0 ? distance / duration : nil
        maxSpeed = samples.filter(\.hasValidSpeed).map(\.speed).max()

        let altitudes = samples.filter(\.hasValidAltitude).map(\.altitude)
        minAltitude = altitudes.min()
        maxAltitude = altitudes.max()
        if var reference = altitudes.first {
            for altitude in altitudes.dropFirst() {
                let change = altitude - reference
                if change >= elevationThreshold {
                    elevationGain += change
                    reference = altitude
                } else if change <= -elevationThreshold {
                    elevationLoss -= change
                    reference = altitude
                }
            }
        }

        let accuracies = samples.filter(\.hasValidHorizontalAccuracy).map(\.horizontalAccuracy).sorted()
        bestAccuracy = accuracies.first
        worstAccuracy = accuracies.last
        if !accuracies.isEmpty {
            let middle = accuracies.count / 2
            medianAccuracy = accuracies.count.isMultiple(of: 2) ? (accuracies[middle - 1] + accuracies[middle]) / 2 : accuracies[middle]
        }
        floors = Array(Set(samples.compactMap(\.floor))).sorted()
        simulatedSamples = samples.filter(\.isSimulated).count
    }
}

nonisolated enum LocationTrackFormat: String, CaseIterable, Identifiable, Sendable {
    case gpx, geoJSON

    var id: String { rawValue }
    var title: String { self == .gpx ? "GPX 1.1" : "GeoJSON" }
    var fileExtension: String { self == .gpx ? "gpx" : "geojson" }

    func data(for samples: [LocationTrackSample], name: String) throws -> Data {
        switch self {
        case .gpx: Data(LocationTrackExporter.gpx(samples, name: name).utf8)
        case .geoJSON: try LocationTrackExporter.geoJSON(samples, name: name)
        }
    }
}

/// Serializes a track as GPX 1.1 or as a GeoJSON LineString with per-point properties.
nonisolated enum LocationTrackExporter {
    static let gpxExtensionNamespace = "urn:apple-toolbox:gpx:1"

    static func gpx(_ samples: [LocationTrackSample], name: String) -> String {
        var lines = [
            #"<?xml version="1.0" encoding="UTF-8"?>"#,
            #"<gpx version="1.1" creator="Apple Toolbox" xmlns="http://www.topografix.com/GPX/1/1" xmlns:atb="\#(gpxExtensionNamespace)">"#,
            "  <metadata><name>\(escapeXML(name))</name>" + (samples.first.map { "<time>\(timestamp($0.timestamp))</time>" } ?? "") + "</metadata>",
            "  <trk>",
            "    <name>\(escapeXML(name))</name>",
            "    <trkseg>",
        ]
        for sample in samples {
            var point = #"      <trkpt lat="\#(coordinate(sample.latitude))" lon="\#(coordinate(sample.longitude))">"#
            if sample.hasValidAltitude { point += "<ele>\(decimal(sample.altitude, digits: 2))</ele>" }
            point += "<time>\(timestamp(sample.timestamp))</time>"
            var extensions = ""
            if sample.hasValidHorizontalAccuracy { extensions += "<atb:hacc>\(decimal(sample.horizontalAccuracy, digits: 1))</atb:hacc>" }
            if sample.hasValidAltitude { extensions += "<atb:vacc>\(decimal(sample.verticalAccuracy, digits: 1))</atb:vacc>" }
            if sample.hasValidSpeed { extensions += "<atb:speed>\(decimal(sample.speed, digits: 2))</atb:speed>" }
            if sample.course >= 0 { extensions += "<atb:course>\(decimal(sample.course, digits: 1))</atb:course>" }
            if let floor = sample.floor { extensions += "<atb:floor>\(floor)</atb:floor>" }
            if !extensions.isEmpty { point += "<extensions>\(extensions)</extensions>" }
            lines.append(point + "</trkpt>")
        }
        lines += ["    </trkseg>", "  </trk>", "</gpx>"]
        return lines.joined(separator: "\n") + "\n"
    }

    static func geoJSON(_ samples: [LocationTrackSample], name: String) throws -> Data {
        let statistics = LocationTrackStatistics(samples: samples)
        let coordinates: [[Double]] = samples.map { sample in
            sample.hasValidAltitude ? [sample.longitude, sample.latitude, sample.altitude] : [sample.longitude, sample.latitude]
        }
        func values(_ value: (LocationTrackSample) -> Any?) -> [Any] { samples.map { value($0) ?? NSNull() } }
        let perPoint: [String: Any] = [
            "times": samples.map { timestamp($0.timestamp) },
            "horizontalAccuracy": values { $0.hasValidHorizontalAccuracy ? $0.horizontalAccuracy : nil },
            "verticalAccuracy": values { $0.hasValidAltitude ? $0.verticalAccuracy : nil },
            "speed": values { $0.hasValidSpeed ? $0.speed : nil },
            "course": values { $0.course >= 0 ? $0.course : nil },
            "floor": values { $0.floor },
        ]
        var properties: [String: Any] = [
            "name": name,
            "sampleCount": samples.count,
            "distanceMeters": statistics.distance,
            "durationSeconds": statistics.duration,
            "coordinateProperties": perPoint,
        ]
        if let first = samples.first, let last = samples.last {
            properties["start"] = timestamp(first.timestamp)
            properties["end"] = timestamp(last.timestamp)
        }
        // A LineString needs two positions; a single fix is exported as a Point.
        let geometry: [String: Any] = coordinates.count >= 2
            ? ["type": "LineString", "coordinates": coordinates]
            : ["type": "Point", "coordinates": coordinates.first ?? []]
        let collection: [String: Any] = [
            "type": "FeatureCollection",
            "features": [["type": "Feature", "geometry": geometry, "properties": properties]],
        ]
        return try JSONSerialization.data(withJSONObject: collection, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    }

    static func escapeXML(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

    static func timestamp(_ date: Date) -> String { date.formatted(.iso8601) }

    private static func coordinate(_ value: Double) -> String { decimal(value, digits: 7) }

    private static func decimal(_ value: Double, digits: Int) -> String {
        String(format: "%.\(digits)f", locale: Locale(identifier: "en_US_POSIX"), value)
    }
}

nonisolated enum LocationUpdateProfile: String, CaseIterable, Identifiable, Sendable {
    case standard, fitness, otherNavigation, automotiveNavigation, airborne

    var id: String { rawValue }

    var title: String {
        switch self {
        case .standard: "Default"
        case .fitness: "Fitness (on foot, cycling)"
        case .otherNavigation: "Other navigation (boat, train)"
        case .automotiveNavigation: "Automotive navigation"
        case .airborne: "Airborne"
        }
    }
}

#if canImport(CoreLocation)
extension LocationUpdateProfile {
    nonisolated var liveConfiguration: CLLocationUpdate.LiveConfiguration {
        switch self {
        case .standard: .default
        case .fitness: .fitness
        case .otherNavigation: .otherNavigation
        case .automotiveNavigation: .automotiveNavigation
        case .airborne: .airborne
        }
    }
}
#endif

/// Records a track from `CLLocationUpdate.liveUpdates(_:)` and derives charts, statistics and exports from it.
@MainActor
final class LocationDashboardService: NSObject, ObservableObject {
    static let maximumSamples = 36_000

    @Published var profile: LocationUpdateProfile = .fitness
    @Published var exportFormat: LocationTrackFormat = .gpx
    @Published private(set) var authorization = "Not determined"
    @Published private(set) var accuracyAuthorization = "—"
    @Published private(set) var isReducedAccuracy = false
    @Published private(set) var isRecording = false
    @Published private(set) var samples: [LocationTrackSample] = []
    @Published private(set) var statistics = LocationTrackStatistics()
    @Published private(set) var diagnostics: [String] = []
    @Published private(set) var updateCount = 0
    @Published private(set) var exportURL: URL?
    @Published private(set) var exportSummary = ""
    @Published private(set) var isError = false
    @Published private(set) var output = "Start recording to build a track from live Core Location updates."

    private var updatesTask: Task<Void, Never>?
    private var nextSampleID = 0
    #if canImport(CoreLocation)
    private let manager = CLLocationManager()
    #endif
    #if os(iOS)
    private var serviceSession: CLServiceSession?
    #endif

    override init() {
        super.init()
        #if canImport(CoreLocation)
        manager.delegate = self
        updateAuthorization(manager.authorizationStatus, accuracy: manager.accuracyAuthorization)
        #endif
    }

    var latest: LocationTrackSample? { samples.last }

    func startRecording() {
        #if canImport(CoreLocation)
        guard !isRecording else { return }
        if manager.authorizationStatus == .notDetermined { manager.requestWhenInUseAuthorization() }
        #if os(iOS)
        // Keeps When In Use authorization alive for the session and shows the prompt if needed.
        serviceSession = CLServiceSession(authorization: .whenInUse)
        #endif
        isRecording = true
        isError = false
        diagnostics = []
        let profile = profile
        output = "Recording with the \(profile.title) profile. Updates pause in the background because the app has no background location mode."
        updatesTask = Task { [weak self] in
            do {
                for try await update in CLLocationUpdate.liveUpdates(profile.liveConfiguration) {
                    guard let self, !Task.isCancelled else { return }
                    self.handle(update)
                }
            } catch {
                // Cancelling the task (Stop Recording) can end the sequence with an error; that is not a failure.
                guard !Task.isCancelled else { return }
                self?.fail(error)
            }
        }
        #else
        isError = true
        output = "Core Location is not available on this platform."
        #endif
    }

    func stopRecording() {
        updatesTask?.cancel()
        updatesTask = nil
        #if os(iOS)
        serviceSession?.invalidate()
        serviceSession = nil
        #endif
        guard isRecording else { return }
        isRecording = false
        output = samples.isEmpty ? "Recording stopped. No fix was received." : "Recording stopped with \(samples.count) sample(s). Export the track below."
    }

    func stop() { stopRecording() }

    func clearTrack() {
        samples = []
        statistics = LocationTrackStatistics()
        updateCount = 0
        exportURL = nil
        exportSummary = ""
        output = isRecording ? "Track cleared; recording continues." : "Track cleared."
    }

    func requestTemporaryPreciseLocation() {
        #if canImport(CoreLocation)
        Task {
            do {
                try await manager.requestTemporaryFullAccuracyAuthorization(withPurposeKey: LocationExperimentService.fullAccuracyPurposeKey)
                updateAuthorization(manager.authorizationStatus, accuracy: manager.accuracyAuthorization)
                output = isReducedAccuracy ? "Precise location was not granted; the track stays approximate." : "Precise location granted temporarily."
            } catch {
                isError = true
                output = "Temporary precise location failed: \(error.localizedDescription)"
            }
        }
        #endif
    }

    func prepareExport() {
        guard !samples.isEmpty else {
            isError = true
            output = "Record at least one fix before exporting."
            return
        }
        let stamp = Self.fileStamp(samples.first?.timestamp ?? Date())
        let name = "Apple Toolbox track \(stamp)"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("AppleToolbox-Track-\(stamp).\(exportFormat.fileExtension)")
        do {
            let data = try exportFormat.data(for: samples, name: name)
            try data.write(to: url, options: .atomic)
            exportURL = url
            exportSummary = "\(exportFormat.title) · \(samples.count) point(s) · \(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file))"
            isError = false
            output = "Wrote \(url.lastPathComponent). Share it with the button below."
        } catch {
            exportURL = nil
            isError = true
            output = "Export failed: \(error.localizedDescription)"
        }
    }

    private static func fileStamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: date)
    }

    #if canImport(CoreLocation)
    private func handle(_ update: CLLocationUpdate) {
        updateCount += 1
        diagnostics = Self.diagnostics(of: update)
        guard let location = update.location else {
            if update.authorizationDenied || update.authorizationDeniedGlobally || update.authorizationRestricted {
                isError = true
                output = "Core Location delivers no fixes: location access is denied, restricted or Location Services are off."
            }
            return
        }
        if let last = samples.last, last.timestamp == location.timestamp { return }
        guard samples.count < Self.maximumSamples else {
            stopRecording()
            output = "Stopped at the limit of \(Self.maximumSamples) samples. Export or clear the track to record again."
            return
        }
        let source = location.sourceInformation
        samples.append(LocationTrackSample(
            id: nextSampleID, timestamp: location.timestamp,
            latitude: location.coordinate.latitude, longitude: location.coordinate.longitude,
            altitude: location.altitude, ellipsoidalAltitude: location.ellipsoidalAltitude,
            horizontalAccuracy: location.horizontalAccuracy, verticalAccuracy: location.verticalAccuracy,
            speed: location.speed, speedAccuracy: location.speedAccuracy,
            course: location.course, courseAccuracy: location.courseAccuracy,
            floor: location.floor?.level,
            isSimulated: source?.isSimulatedBySoftware ?? false, isFromAccessory: source?.isProducedByAccessory ?? false))
        nextSampleID += 1
        statistics = LocationTrackStatistics(samples: samples)
        if isError { isError = false }
    }

    private static func diagnostics(of update: CLLocationUpdate) -> [String] {
        var flags: [(Bool, String)] = [
            (update.stationary, "Stationary · updates paused"),
            (update.accuracyLimited, "Approximate location only"),
            (update.locationUnavailable, "Location unavailable"),
            (update.authorizationDenied, "Authorization denied"),
            (update.authorizationDeniedGlobally, "Location Services off"),
            (update.authorizationRestricted, "Restricted"),
            (update.insufficientlyInUse, "App not in use"),
        ]
        #if os(iOS) || os(macOS)
        flags += [
            (update.serviceSessionRequired, "Service session required"),
            (update.authorizationRequestInProgress, "Permission prompt open"),
        ]
        #endif
        return flags.filter(\.0).map(\.1)
    }

    private func fail(_ error: Error) {
        stopRecording()
        isError = true
        output = "Live updates ended: \(error.localizedDescription)"
    }

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
    }
    #endif
}

#if canImport(CoreLocation)
extension LocationDashboardService: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        let accuracy = manager.accuracyAuthorization
        Task { @MainActor [weak self] in
            self?.updateAuthorization(status, accuracy: accuracy)
            PermissionCenter.shared.invalidate()
        }
    }
}
#endif
