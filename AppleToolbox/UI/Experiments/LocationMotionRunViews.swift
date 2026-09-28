import SwiftUI
#if canImport(MapKit) && !os(watchOS) && !os(tvOS)
import MapKit
#endif

struct CoreLocationRunView: View {
    @StateObject private var location = LocationExperimentService()
    @Binding var liveStatus: ExperimentStatus?

    var body: some View {
        Group {
            HStack { Label("Authorization", systemImage: "location"); Spacer(); Text(location.authorization).foregroundStyle(.secondary) }
            Button("Request Location Permission", action: location.requestPermission)
            Button(location.isUpdating ? "Stop Live Updates" : "Start Live Updates") { location.isUpdating ? location.stop() : location.start() }.buttonStyle(.borderedProminent)
            LocationReadingView(location: location)
            OutputView(text: location.output, isError: location.output.localizedCaseInsensitiveContains("error") || location.output.localizedCaseInsensitiveContains("denied"))
        }
        .onChange(of: location.status, initial: true) { liveStatus = location.status }
    }
}

struct CoreMotionRunView: View {
    @StateObject private var motion = MotionExperimentService()
    @Binding var liveStatus: ExperimentStatus?

    var body: some View {
        Group {
            Button(motion.isRunning ? "Stop Motion Updates" : "Start Motion Updates") { motion.isRunning ? motion.stop() : motion.start() }.buttonStyle(.borderedProminent)
            MotionReadingView(motion: motion)
            OutputView(text: motion.output, isError: motion.output.localizedCaseInsensitiveContains("not available") || motion.output.localizedCaseInsensitiveContains("error"))
        }
        .onChange(of: motion.status, initial: true) { liveStatus = motion.status }
    }
}

private struct LocationReadingView: View {
    @ObservedObject var location: LocationExperimentService

    var body: some View {
        Section("Live reading") {
            #if canImport(MapKit) && !os(watchOS) && !os(tvOS)
            LocationMapView(coordinate: location.coordinateValue)
                .frame(height: 220)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            #endif
            LabeledContent("Coordinate", value: location.coordinate)
            LabeledContent("Accuracy", value: location.accuracy)
            LabeledContent("Altitude", value: location.altitude)
            LabeledContent("Speed", value: location.speed)
            LabeledContent("Course", value: location.course)
            LabeledContent("Heading", value: location.heading)
        }
    }
}

#if canImport(MapKit) && !os(watchOS) && !os(tvOS)
private struct LocationMapView: View {
    let coordinate: LocationCoordinate?
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 51.1657, longitude: 10.4515),
        span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)
    )

    var body: some View {
        Map(coordinateRegion: $region, annotationItems: markerItems) { marker in
            MapMarker(coordinate: marker.coordinate, tint: .red)
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
            guard let newValue else { return }
            withAnimation(.easeInOut(duration: 0.35)) {
                region = MKCoordinateRegion(
                    center: CLLocationCoordinate2D(latitude: newValue.latitude, longitude: newValue.longitude),
                    span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
                )
            }
        }
    }

    private var markerItems: [LocationMapMarker] {
        guard let coordinate else { return [] }
        return [LocationMapMarker(coordinate: CLLocationCoordinate2D(latitude: coordinate.latitude, longitude: coordinate.longitude))]
    }
}

private struct LocationMapMarker: Identifiable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
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
