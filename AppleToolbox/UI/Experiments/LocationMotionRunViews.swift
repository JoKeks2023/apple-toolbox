import SwiftUI
#if canImport(MapKit) && !os(watchOS) && !os(tvOS)
import MapKit
#endif

struct CoreLocationRunView: View {
    @StateObject private var location = LocationExperimentService()
    @State private var radius = LocationExperimentService.regionRadii[1]

    var body: some View {
        HStack { Label("Authorization", systemImage: "location"); Spacer(); Text(location.authorization).foregroundStyle(.secondary) }
        HStack { Label("Accuracy", systemImage: "scope"); Spacer(); Text(location.accuracyAuthorization).foregroundStyle(.secondary) }
        Button("Request Location Permission", action: location.requestPermission)
        if location.isReducedAccuracy {
            Button("Request Temporary Precise Location", action: location.requestTemporaryPreciseLocation)
        }
        Button(location.isUpdating ? "Stop Live Updates" : "Start Live Updates") { location.isUpdating ? location.stopUpdates() : location.startUpdates() }.buttonStyle(.borderedProminent)
            .experimentSession(location)
        OutputView(text: location.output, isError: location.output.localizedCaseInsensitiveContains("error") || location.output.localizedCaseInsensitiveContains("denied"))
        LocationReadingView(location: location)
        HeadingDetailsView(location: location)
        RegionMonitoringView(location: location, radius: $radius)
        AlwaysServicesView(location: location)
        LocationEventsView(events: location.events)
    }
}

struct CoreMotionRunView: View {
    @StateObject private var motion = MotionExperimentService()

    var body: some View {
        Button(motion.isRunning ? "Stop Motion Updates" : "Start Motion Updates") { motion.isRunning ? motion.stopMotion() : motion.startMotion() }.buttonStyle(.borderedProminent)
            .experimentSession(motion)
        OutputView(text: motion.output, isError: motion.output.localizedCaseInsensitiveContains("not available") || motion.output.localizedCaseInsensitiveContains("error") || motion.output.localizedCaseInsensitiveContains("denied"))
        MotionReadingView(motion: motion)
        AttitudeMagnetView(motion: motion)
        PedometerView(motion: motion)
        AltimeterView(motion: motion)
        MotionAvailabilityView(features: motion.features)
    }
}

private struct LocationReadingView: View {
    @ObservedObject var location: LocationExperimentService

    var body: some View {
        Section("Live reading") {
            #if canImport(MapKit) && !os(watchOS) && !os(tvOS)
            LocationMapView(coordinate: location.coordinateValue, region: location.monitoredRegion)
                .frame(height: 220)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            #endif
            LabeledContent("Coordinate", value: location.coordinate)
            LabeledContent("Accuracy", value: location.accuracy)
            LabeledContent("Altitude", value: location.altitude)
            LabeledContent("Speed", value: location.speed)
            LabeledContent("Course", value: location.course)
            LabeledContent("Heading", value: location.heading)
            LabeledContent("Floor", value: location.floorLevel)
        }
    }
}

private struct HeadingDetailsView: View {
    @ObservedObject var location: LocationExperimentService

    var body: some View {
        Section("Heading · CLHeading") {
            LabeledContent("Heading service", value: location.headingService.detail)
            LabeledContent("True heading", value: location.trueHeading)
            LabeledContent("Magnetic heading", value: location.magneticHeading)
            LabeledContent("Heading accuracy", value: location.headingAccuracy)
        }
    }
}

private struct RegionMonitoringView: View {
    @ObservedObject var location: LocationExperimentService
    @Binding var radius: Double

    var body: some View {
        Section("Region monitoring") {
            LabeledContent("Availability", value: location.regionMonitoring.detail)
            Picker("Radius", selection: $radius) {
                ForEach(LocationExperimentService.regionRadii, id: \.self) { Text(LocationExperimentService.radiusLabel($0)).tag($0) }
            }
            .disabled(location.monitoredRegion != nil)
            Button(location.monitoredRegion == nil ? "Monitor Region Around Me" : "Stop Region Monitoring") {
                location.monitoredRegion == nil ? location.startRegionMonitoring(radius: radius) : location.stopRegionMonitoring()
            }
            .disabled(!location.regionMonitoring.isAvailable || (location.monitoredRegion == nil && location.coordinateValue == nil))
            LabeledContent("Current state", value: location.regionState)
            if location.coordinateValue == nil && location.regionMonitoring.isAvailable {
                Text("Start live updates first; the circle is centered on your current location.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct AlwaysServicesView: View {
    @ObservedObject var location: LocationExperimentService

    var body: some View {
        Section("Visits & significant changes") {
            Text("Both services are designed for Always authorization. With When In Use the system may deliver nothing.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if location.canRequestAlways {
                Button("Upgrade to Always Authorization", action: location.requestAlwaysAuthorization)
            }
            LabeledContent("Visits", value: location.visits.detail)
            Button(location.isMonitoringVisits ? "Stop Visit Monitoring" : "Start Visit Monitoring") {
                location.isMonitoringVisits ? location.stopVisitMonitoring() : location.startVisitMonitoring()
            }
            .disabled(!location.visits.isAvailable)
            LabeledContent("Significant changes", value: location.significantChanges.detail)
            Button(location.isMonitoringSignificantChanges ? "Stop Significant-Change Monitoring" : "Start Significant-Change Monitoring") {
                location.isMonitoringSignificantChanges ? location.stopSignificantChanges() : location.startSignificantChanges()
            }
            .disabled(!location.significantChanges.isAvailable)
        }
    }
}

private struct LocationEventsView: View {
    let events: [LocationMonitorEvent]

    var body: some View {
        Section("Monitoring events") {
            if events.isEmpty {
                Text("Region entries and exits, visits and significant changes appear here as they arrive.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(events) { event in
                VStack(alignment: .leading, spacing: 3) {
                    Label(event.title, systemImage: event.symbol)
                        .font(.headline)
                    Text(event.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(event.date.formatted(date: .omitted, time: .standard))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            }
        }
    }
}

#if canImport(MapKit) && !os(watchOS) && !os(tvOS)
private struct LocationMapView: View {
    let coordinate: LocationCoordinate?
    let region: LocationRegion?
    @State private var position = MapCameraPosition.region(MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 51.1657, longitude: 10.4515),
        span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)
    ))

    var body: some View {
        Map(position: $position) {
            if let region {
                MapCircle(center: Self.point(region.center), radius: region.radius)
                    .foregroundStyle(.tint.opacity(0.18))
                    .stroke(.tint, lineWidth: 2)
            }
            if let coordinate {
                Marker("Live position", coordinate: Self.point(coordinate))
                    .tint(.red)
            }
        }
        .overlay(alignment: .topLeading) {
            Label(coordinate == nil ? "Waiting for location" : "Live position", systemImage: coordinate == nil ? "location.slash" : "location.fill")
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(.regularMaterial, in: Capsule())
                .padding(10)
        }
        .onChange(of: coordinate) { _, newValue in
            guard let newValue, region == nil else { return }
            withAnimation(.easeInOut(duration: 0.35)) {
                position = .region(MKCoordinateRegion(center: Self.point(newValue), span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)))
            }
        }
        .onChange(of: region) { _, newValue in
            guard let newValue else { return }
            withAnimation(.easeInOut(duration: 0.35)) {
                position = .region(MKCoordinateRegion(center: Self.point(newValue.center), latitudinalMeters: newValue.radius * 3, longitudinalMeters: newValue.radius * 3))
            }
        }
    }

    private static func point(_ coordinate: LocationCoordinate) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }
}
#endif

private struct MotionReadingView: View {
    @ObservedObject var motion: MotionExperimentService

    var body: some View {
        Section("Live vectors · x  ·  y  ·  z") {
            VectorRow(title: "User acceleration", symbol: "figure.run", vector: motion.userAcceleration, unit: "g")
            VectorRow(title: "Rotation rate", symbol: "rotate.3d", vector: motion.rotationRate, unit: "rad/s")
            VectorRow(title: "Gravity", symbol: "arrow.down", vector: motion.gravity, unit: "g")
            if let lastUpdated = motion.lastUpdated {
                Text("Updated \(lastUpdated.formatted(date: .omitted, time: .standard))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Start updates and move the device to see live values.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct AttitudeMagnetView: View {
    @ObservedObject var motion: MotionExperimentService

    var body: some View {
        Section("Attitude & magnetic field") {
            LabeledContent("Roll", value: Self.degrees(motion.attitude.x))
            LabeledContent("Pitch", value: Self.degrees(motion.attitude.y))
            LabeledContent("Yaw", value: Self.degrees(motion.attitude.z))
            VectorRow(title: "Magnetic field", symbol: "location.north.line", vector: motion.magneticField, unit: "µT")
            LabeledContent("Source", value: motion.magneticSource)
            LabeledContent("Calibration", value: motion.magneticAccuracy)
        }
    }

    private static func degrees(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1))) + "°"
    }
}

private struct PedometerView: View {
    @ObservedObject var motion: MotionExperimentService

    var body: some View {
        Section("Pedometer · CMPedometer") {
            Button(motion.isPedometerRunning ? "Stop Pedometer" : "Start Pedometer") { motion.isPedometerRunning ? motion.stopPedometer() : motion.startPedometer() }
            LabeledContent("Steps since start", value: motion.pedometerReading.steps)
            LabeledContent("Distance", value: motion.pedometerReading.distance)
            LabeledContent("Floors", value: motion.pedometerReading.floors)
            LabeledContent("Cadence", value: motion.pedometerReading.cadence)
            LabeledContent("Pace", value: motion.pedometerReading.pace)
            LabeledContent("Today so far", value: motion.pedometerReading.today)
        }
    }
}

private struct AltimeterView: View {
    @ObservedObject var motion: MotionExperimentService

    var body: some View {
        Section("Altimeter · CMAltimeter") {
            Button(motion.isAltimeterRunning ? "Stop Altimeter" : "Start Altimeter") { motion.isAltimeterRunning ? motion.stopAltimeter() : motion.startAltimeter() }
            LabeledContent("Relative altitude", value: motion.altitudeReading.relative)
            LabeledContent("Pressure", value: motion.altitudeReading.pressure)
            LabeledContent("Absolute altitude", value: motion.altitudeReading.absolute)
            LabeledContent("Absolute accuracy", value: motion.altitudeReading.absoluteAccuracy)
        }
    }
}

private struct MotionAvailabilityView: View {
    let features: [MotionFeature]

    var body: some View {
        Section("Availability on this device") {
            ForEach(features) { feature in
                LabeledContent {
                    Text(feature.detail).multilineTextAlignment(.trailing)
                } label: {
                    Label(feature.title, systemImage: feature.isAvailable ? "checkmark.circle.fill" : "xmark.circle")
                }
            }
        }
    }
}

private struct VectorRow: View {
    let title: String
    let symbol: String
    let vector: MotionVector
    let unit: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: symbol)
                .font(.headline)
            Text("\(vector.formattedValues) \(unit)")
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 3)
    }
}
