import SwiftUI
#if canImport(Charts)
import Charts
#endif
#if canImport(MapKit)
import MapKit
#endif

extension LocationDashboardService: StoppableExperiment {
    var isActive: Bool { isRecording }
}

struct LocationDashboardRunView: View {
    @StateObject private var dashboard = LocationDashboardService()

    var body: some View {
        LabeledContent("Authorization", value: dashboard.authorization)
        LabeledContent("Accuracy", value: dashboard.accuracyAuthorization)
        if dashboard.isReducedAccuracy {
            Button("Request Temporary Precise Location", action: dashboard.requestTemporaryPreciseLocation)
        }
        Picker("Update profile", selection: $dashboard.profile) {
            ForEach(LocationUpdateProfile.allCases) { Text($0.title).tag($0) }
        }
        .disabled(dashboard.isRecording)
        HStack {
            Button(dashboard.isRecording ? "Stop Recording" : "Start Recording", systemImage: dashboard.isRecording ? "stop.circle" : "record.circle") {
                dashboard.isRecording ? dashboard.stopRecording() : dashboard.startRecording()
            }
            .buttonStyle(.borderedProminent)
            .experimentSession(dashboard)
            Button("Clear Track", systemImage: "trash", role: .destructive, action: dashboard.clearTrack)
                .buttonStyle(.bordered)
                .disabled(dashboard.samples.isEmpty)
        }
        OutputView(text: dashboard.output, isError: dashboard.isError)
        LatestFixView(dashboard: dashboard)
        #if canImport(MapKit)
        TrackMapSection(samples: dashboard.samples)
        #endif
        #if canImport(Charts)
        TrackChartsView(samples: dashboard.samples)
        #endif
        TrackStatisticsView(statistics: dashboard.statistics)
        TrackExportView(dashboard: dashboard)
    }
}

enum TrackText {
    static func meters(_ value: Double) -> String {
        value >= 1_000 ? (value / 1_000).formatted(.number.precision(.fractionLength(2))) + " km" : value.formatted(.number.precision(.fractionLength(0))) + " m"
    }

    static func number(_ value: Double, digits: Int = 1) -> String {
        value.formatted(.number.precision(.fractionLength(digits)))
    }

    static func speed(_ metersPerSecond: Double) -> String {
        "\(number(metersPerSecond * 3.6)) km/h (\(number(metersPerSecond, digits: 2)) m/s)"
    }

    static func duration(_ seconds: TimeInterval) -> String {
        Duration.seconds(seconds).formatted(.time(pattern: .hourMinuteSecond))
    }
}

private struct LatestFixView: View {
    @ObservedObject var dashboard: LocationDashboardService

    var body: some View {
        Section("Latest fix · CLLocationUpdate (\(dashboard.updateCount) updates)") {
            if !dashboard.diagnostics.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack { ForEach(dashboard.diagnostics, id: \.self) { InfoChip(title: $0, symbol: "info.circle") } }
                }
            }
            if let sample = dashboard.latest {
                LabeledContent("Coordinate") { Text(String(format: "%.6f, %.6f", sample.latitude, sample.longitude)).font(.body.monospaced()) }
                LabeledContent("Horizontal accuracy", value: sample.hasValidHorizontalAccuracy ? "±" + TrackText.number(sample.horizontalAccuracy) + " m" : "Invalid")
                LabeledContent("Altitude (sea level)", value: sample.hasValidAltitude ? TrackText.number(sample.altitude) + " m ±" + TrackText.number(sample.verticalAccuracy) + " m" : "Invalid")
                LabeledContent("Ellipsoidal altitude", value: sample.hasValidAltitude ? TrackText.number(sample.ellipsoidalAltitude) + " m" : "Invalid")
                LabeledContent("Speed", value: sample.hasValidSpeed ? TrackText.speed(sample.speed) : "Invalid")
                LabeledContent("Course", value: sample.course >= 0 ? TrackText.number(sample.course) + "°" + (sample.courseAccuracy >= 0 ? " ±" + TrackText.number(sample.courseAccuracy) + "°" : "") : "Invalid")
                LabeledContent("Floor", value: sample.floor.map { "Level \($0)" } ?? "Not reported")
                LabeledContent("Source", value: sample.isSimulated ? "Simulated by software" : sample.isFromAccessory ? "External accessory" : "This device")
                LabeledContent("Timestamp", value: sample.timestamp.formatted(date: .omitted, time: .standard))
            } else {
                Text("No fix yet. Start recording and move around; the first update can take a few seconds outdoors.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#if canImport(MapKit)
private enum TrackCamera: String, CaseIterable, Identifiable {
    case follow = "Follow position", whole = "Whole track", free = "Free"
    var id: String { rawValue }
}

private struct TrackMapSection: View {
    let samples: [LocationTrackSample]
    @State private var camera = TrackCamera.follow
    @State private var position = MapCameraPosition.automatic

    var body: some View {
        Section("Track map") {
            Picker("Camera", selection: $camera) {
                ForEach(TrackCamera.allCases) { Text($0.rawValue).tag($0) }
            }
            let track = LocationTrackSample.downsampled(samples, maxCount: 2_000).map(Self.coordinate)
            Map(position: $position) {
                if track.count >= 2 {
                    MapPolyline(coordinates: track).stroke(.blue, lineWidth: 4)
                }
                if let first = samples.first {
                    Marker("Start", systemImage: "flag.fill", coordinate: Self.coordinate(first)).tint(.green)
                }
                if let last = samples.last {
                    if last.hasValidHorizontalAccuracy {
                        MapCircle(center: Self.coordinate(last), radius: max(last.horizontalAccuracy, 1))
                            .foregroundStyle(.blue.opacity(0.15))
                            .stroke(.blue.opacity(0.5), lineWidth: 1)
                    }
                    Annotation("Now", coordinate: Self.coordinate(last)) {
                        Circle().fill(.blue).frame(width: 14, height: 14).overlay(Circle().stroke(.white, lineWidth: 2))
                    }
                }
            }
            .mapStyle(.standard(elevation: .flat))
            .frame(height: 280)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .onChange(of: samples.count) { _, _ in updateCamera() }
            .onChange(of: camera) { _, _ in updateCamera() }
            Text("Blue line: recorded track (\(samples.count) fixes) · circle: horizontal accuracy of the latest fix")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func updateCamera() {
        guard let last = samples.last else { return }
        switch camera {
        case .follow:
            position = .region(MKCoordinateRegion(center: Self.coordinate(last), latitudinalMeters: 400, longitudinalMeters: 400))
        case .whole:
            let points = samples.map { MKMapPoint(Self.coordinate($0)) }
            let rect = points.dropFirst().reduce(MKMapRect(origin: points[0], size: MKMapSize(width: 0, height: 0))) { $0.union(MKMapRect(origin: $1, size: MKMapSize(width: 0, height: 0))) }
            let padding = max(rect.width, rect.height, 400) * 0.2
            position = .rect(rect.insetBy(dx: -padding, dy: -padding))
        case .free:
            break
        }
    }

    private static func coordinate(_ sample: LocationTrackSample) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: sample.latitude, longitude: sample.longitude)
    }
}
#endif

#if canImport(Charts)
private struct TrackChartsView: View {
    let samples: [LocationTrackSample]

    var body: some View {
        let chartSamples = LocationTrackSample.downsampled(samples, maxCount: 400)
        Section("Speed over time") {
            chart(empty: chartSamples.filter(\.hasValidSpeed).count < 2) {
                Chart(chartSamples.filter(\.hasValidSpeed)) { sample in
                    LineMark(x: .value("Time", sample.timestamp), y: .value("Speed", sample.speed * 3.6))
                        .foregroundStyle(.green)
                }
                .chartYAxisLabel("km/h")
            }
        }
        Section("Altitude over time") {
            let altitudes = chartSamples.filter(\.hasValidAltitude)
            chart(empty: altitudes.count < 2) {
                Chart(altitudes) { sample in
                    AreaMark(x: .value("Time", sample.timestamp),
                             yStart: .value("Lower bound", sample.altitude - sample.verticalAccuracy),
                             yEnd: .value("Upper bound", sample.altitude + sample.verticalAccuracy))
                        .foregroundStyle(.orange.opacity(0.18))
                    LineMark(x: .value("Time", sample.timestamp), y: .value("Altitude", sample.altitude))
                        .foregroundStyle(.orange)
                }
                .chartYAxisLabel("m above sea level · band = vertical accuracy")
                .chartYScale(domain: .automatic(includesZero: false))
            }
        }
        Section("Accuracy over time") {
            chart(empty: chartSamples.filter(\.hasValidHorizontalAccuracy).count < 2) {
                Chart {
                    ForEach(chartSamples.filter(\.hasValidHorizontalAccuracy)) { sample in
                        LineMark(x: .value("Time", sample.timestamp), y: .value("Accuracy", sample.horizontalAccuracy), series: .value("Axis", "Horizontal"))
                            .foregroundStyle(by: .value("Axis", "Horizontal"))
                    }
                    ForEach(chartSamples.filter(\.hasValidAltitude)) { sample in
                        LineMark(x: .value("Time", sample.timestamp), y: .value("Accuracy", sample.verticalAccuracy), series: .value("Axis", "Vertical"))
                            .foregroundStyle(by: .value("Axis", "Vertical"))
                    }
                }
                .chartYAxisLabel("± m (lower is better)")
            }
        }
    }

    @ViewBuilder
    private func chart(empty: Bool, @ViewBuilder content: () -> some View) -> some View {
        if empty {
            Text("The chart appears after two valid fixes.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            content().frame(height: 170)
        }
    }
}
#endif

private struct TrackStatisticsView: View {
    let statistics: LocationTrackStatistics

    var body: some View {
        Section("Session statistics") {
            LabeledContent("Samples", value: "\(statistics.sampleCount) · \(statistics.distanceSampleCount) within ±\(Int(LocationTrackStatistics.defaultAccuracyLimit)) m used for distance")
            LabeledContent("Duration", value: TrackText.duration(statistics.duration))
            LabeledContent("Distance", value: TrackText.meters(statistics.distance))
            LabeledContent("Average speed", value: statistics.averageSpeed.map(TrackText.speed) ?? "—")
            LabeledContent("Maximum speed", value: statistics.maxSpeed.map(TrackText.speed) ?? "—")
            if let low = statistics.minAltitude, let high = statistics.maxAltitude {
                LabeledContent("Altitude range", value: "\(TrackText.number(low)) – \(TrackText.number(high)) m")
            } else {
                LabeledContent("Altitude range", value: "—")
            }
            LabeledContent("Elevation gain / loss", value: "+\(TrackText.number(statistics.elevationGain)) m / −\(TrackText.number(statistics.elevationLoss)) m")
            if let best = statistics.bestAccuracy, let median = statistics.medianAccuracy, let worst = statistics.worstAccuracy {
                LabeledContent("Horizontal accuracy", value: "best ±\(TrackText.number(best)) · median ±\(TrackText.number(median)) · worst ±\(TrackText.number(worst)) m")
            } else {
                LabeledContent("Horizontal accuracy", value: "—")
            }
            LabeledContent("Floors reported", value: statistics.floors.isEmpty ? "None (no indoor positioning here)" : statistics.floors.map(String.init).joined(separator: ", "))
            if statistics.simulatedSamples > 0 {
                LabeledContent("Simulated fixes", value: "\(statistics.simulatedSamples) (CLLocationSourceInformation)")
            }
        }
    }
}

private struct TrackExportView: View {
    @ObservedObject var dashboard: LocationDashboardService

    var body: some View {
        Section("Export track") {
            Picker("Format", selection: $dashboard.exportFormat) {
                ForEach(LocationTrackFormat.allCases) { Text($0.title).tag($0) }
            }
            Button("Create Export File", systemImage: "doc.badge.arrow.up", action: dashboard.prepareExport)
                .disabled(dashboard.samples.isEmpty)
            if let url = dashboard.exportURL {
                #if !os(tvOS)
                ShareLink(item: url, preview: SharePreview(url.lastPathComponent)) {
                    Label("Share \(url.lastPathComponent)", systemImage: "square.and.arrow.up")
                }
                #endif
                Text(dashboard.exportSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
