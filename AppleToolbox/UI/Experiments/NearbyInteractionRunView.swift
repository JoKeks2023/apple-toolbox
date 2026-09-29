import SwiftUI

/// Nearby Interaction (spec §13): live distance and direction to a peer, camera assistance, extended distance,
/// convergence coaching, device capabilities and the accessory session boundary.
struct NearbyInteractionRunView: View {
    @StateObject private var nearby = NearbyExperimentService()

    var body: some View {
        Group {
            if nearby.isRunning {
                Button("Stop Nearby Interaction", action: nearby.stop).buttonStyle(.borderedProminent)
            } else {
                Button("Start Peer Ranging", action: nearby.start).buttonStyle(.borderedProminent)
            }
        }
        .experimentSession(nearby)
        Toggle("Camera assistance (ARKit)", isOn: Binding(get: { nearby.useCameraAssistance }, set: nearby.setCameraAssistance))
            .disabled(!nearby.capabilities.cameraAssistance)
        Toggle("Extended distance", isOn: Binding(get: { nearby.useExtendedDistance }, set: nearby.setExtendedDistance))
            .disabled(!nearby.capabilities.extendedDistance)
        NearbyLiveSection(nearby: nearby)
        NearbyCapabilitiesSection(nearby: nearby)
        NearbyAccessorySection(nearby: nearby)
        OutputView(text: nearby.output, isError: nearby.output.localizedCaseInsensitiveContains("error") || nearby.output.localizedCaseInsensitiveContains("not supported"))
    }
}

private struct NearbyLiveSection: View {
    @ObservedObject var nearby: NearbyExperimentService

    var body: some View {
        Section("Live distance and direction") {
            let reading = nearby.reading
            let blips = reading.flatMap { reading in
                reading.distance.map { [RadarBlip(id: "peer", label: nearby.peerName ?? "Peer", distance: $0, azimuth: reading.azimuth)] }
            } ?? []
            NearbyRadarView(blips: blips, range: NearbyGeometry.radarRange(for: blips.compactMap(\.distance)))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            LabeledContent("Session", value: nearby.phase)
            LabeledContent("Peer", value: nearby.peerName ?? "—")
            LabeledContent("Distance", value: reading?.distance.map(NearbyGeometry.meters) ?? "—")
            LabeledContent("Azimuth (direction)", value: reading?.direction.map { NearbyGeometry.degrees(NearbyGeometry.azimuth($0)) } ?? "Not available")
            LabeledContent("Elevation (direction)", value: reading?.direction.map { NearbyGeometry.degrees(NearbyGeometry.elevation($0)) } ?? "Not available")
            LabeledContent("Horizontal angle", value: reading?.horizontalAngle.map(NearbyGeometry.degrees) ?? "Not available")
            LabeledContent("Vertical estimate", value: reading?.verticalEstimate ?? "—")
            LabeledContent("Convergence", value: nearby.convergence)
            Text("Start ranging on two UWB devices (iPhone 11 or later) near each other; they exchange discovery tokens over MultipeerConnectivity. Direction needs the devices in portrait, facing each other within the UWB field of view. With camera assistance, ARKit adds a horizontal angle and a vertical estimate after you sweep the phone; convergence tells you which motion is still missing.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct NearbyCapabilitiesSection: View {
    @ObservedObject var nearby: NearbyExperimentService

    var body: some View {
        Section("Capabilities · NIDeviceCapability") {
            row("Precise distance", nearby.capabilities.preciseDistance, nearby.peerCapabilities?.preciseDistance)
            row("Direction", nearby.capabilities.direction, nearby.peerCapabilities?.direction)
            row("Camera assistance", nearby.capabilities.cameraAssistance, nearby.peerCapabilities?.cameraAssistance)
            row("Extended distance", nearby.capabilities.extendedDistance, nearby.peerCapabilities?.extendedDistance)
            row("DL-TDOA (UWB anchors)", nearby.capabilities.dlTDOA, nearby.peerCapabilities?.dlTDOA)
            row("Bluetooth Channel Sounding", nearby.capabilities.bluetoothChannelSounding, nearby.peerCapabilities?.bluetoothChannelSounding)
            Text("“This” is NISession.deviceCapabilities; the peer column comes from the capabilities inside its discovery token. DL-TDOA positions a device against installed UWB anchors and needs that infrastructure; Bluetooth Channel Sounding ranging needs a supporting accessory.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func row(_ title: String, _ local: Bool?, _ peer: Bool?) -> some View {
        LabeledContent(title, value: "This: \(Self.text(local)) · Peer: \(peer == nil && nearby.peerCapabilities == nil ? "—" : Self.text(peer))")
    }

    private static func text(_ value: Bool?) -> String {
        switch value {
        case true: "Yes"
        case false: "No"
        case nil: "n/a"
        }
    }
}

private struct NearbyAccessorySection: View {
    @ObservedObject var nearby: NearbyExperimentService

    var body: some View {
        Section("Accessory sessions") {
            Text("Third-party UWB accessories (built on Apple's Nearby Interaction Accessory Protocol with certified UWB chipsets) send their own configuration data over Bluetooth LE after a vendor-specific handshake. The app passes that data to NINearbyAccessoryConfiguration; without the vendor's accessory and firmware there is nothing to range with, and Apple Toolbox cannot generate it.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Try an accessory configuration without vendor data", action: nearby.tryAccessoryConfiguration)
            if let report = nearby.accessoryReport {
                Text(report).font(.caption.monospaced())
            }
        }
    }
}

/// A peer on the radar; azimuth in radians, positive to the right of the device's top edge.
struct RadarBlip: Identifiable, Equatable {
    let id: String
    let label: String
    let distance: Float?
    let azimuth: Float?
}

/// Top-down radar: this device in the center facing up, rings for distance, a dot and arrow per peer with direction,
/// and a dashed ring for peers with distance only.
struct NearbyRadarView: View {
    let blips: [RadarBlip]
    let range: Float
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)
            let radius = size / 2 - 18
            let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
            ZStack {
                ForEach(1...4, id: \.self) { ring in
                    Circle()
                        .stroke(Color.secondary.opacity(ring == 4 ? 0.35 : 0.18), lineWidth: 1)
                        .frame(width: radius * 2 * CGFloat(ring) / 4, height: radius * 2 * CGFloat(ring) / 4)
                        .position(center)
                }
                Path { path in
                    path.move(to: center)
                    path.addLine(to: CGPoint(x: center.x, y: center.y - radius))
                }
                .stroke(Color.secondary.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                Text(NearbyGeometry.meters(range))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .position(x: center.x + 28, y: center.y - radius - 8)
                Image(systemName: "iphone")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .position(center)
                if let azimuth = blips.lazy.compactMap(\.azimuth).first {
                    // Arrow towards the first peer with a direction, orbiting the device.
                    Image(systemName: "location.north.fill")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(.tint)
                        .offset(y: -34)
                        .rotationEffect(.radians(Double(azimuth)))
                        .position(center)
                }
                ForEach(blips) { blip in
                    if let distance = blip.distance {
                        if let azimuth = blip.azimuth {
                            let point = NearbyGeometry.radarPoint(distance: distance, azimuth: azimuth, range: range)
                            let position = CGPoint(x: center.x + CGFloat(point.x) * radius, y: center.y + CGFloat(point.y) * radius)
                            Circle()
                                .fill(.tint)
                                .frame(width: 14, height: 14)
                                .shadow(color: .accentColor.opacity(0.5), radius: 6)
                                .position(position)
                            Text(blip.label)
                                .font(.caption2.weight(.semibold))
                                .lineLimit(1)
                                .position(x: position.x, y: position.y + 16)
                        } else {
                            let ringRadius = CGFloat(min(distance / max(range, 0.01), 1)) * radius
                            Circle()
                                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [6, 5]))
                                .frame(width: ringRadius * 2, height: ringRadius * 2)
                                .position(center)
                            Text("\(blip.label) · no direction")
                                .font(.caption2.weight(.semibold))
                                .lineLimit(1)
                                .position(x: center.x, y: center.y - ringRadius - 10)
                        }
                    }
                }
            }
            .animation(reduceMotion ? nil : .spring(duration: 0.35), value: blips)
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: 320, maxHeight: 320)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        guard !blips.isEmpty else { return "Radar: no peer measured yet" }
        return blips.map { blip in
            let distance = blip.distance.map(NearbyGeometry.meters) ?? "unknown distance"
            let direction = blip.azimuth.map { "direction \(NearbyGeometry.degrees($0))" } ?? "no direction"
            return "\(blip.label): \(distance), \(direction)"
        }.joined(separator: "; ")
    }
}
