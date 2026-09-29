import SwiftUI

extension BeaconRangingService: StoppableExperiment {
    var isActive: Bool { isRanging || isWaitingForPermission }
}

struct BeaconRangingRunView: View {
    @StateObject private var beacon = BeaconRangingService()

    var body: some View {
        LabeledContent("Authorization", value: beacon.authorization)
        LabeledContent("Ranging") { Text(beacon.rangingAvailability).multilineTextAlignment(.trailing) }
        Picker("UUID preset", selection: $beacon.preset) {
            ForEach(BeaconUUIDPreset.allCases) { Text($0.title).tag($0) }
        }
        .onChange(of: beacon.preset) { _, preset in beacon.applyPreset(preset) }
        .disabled(beacon.isActive)
        BeaconIdentityFields(beacon: beacon)
            .disabled(beacon.isActive)
        Button(beacon.isActive ? "Stop Ranging" : "Start Ranging", systemImage: beacon.isActive ? "stop.circle" : "dot.radiowaves.left.and.right") {
            beacon.isActive ? beacon.stop() : beacon.start()
        }
        .buttonStyle(.borderedProminent)
        .experimentSession(beacon)
        OutputView(text: beacon.output, isError: beacon.isError)
        BeaconListView(beacon: beacon)
        Section("Why can't the app see every beacon?") {
            Text("Core Location only ranges beacons whose proximity UUID you name here; there is no public API to list every iBeacon nearby, and Core Bluetooth hides iBeacon advertisements from third-party apps. Distance is an estimate from the received signal strength (RSSI) and the beacon's calibrated transmit power, so walls, bodies and the device's orientation change it. Proximity buckets are Immediate (a few centimeters), Near (about a meter) and Far.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct BeaconIdentityFields: View {
    @ObservedObject var beacon: BeaconRangingService

    var body: some View {
        TextField("Proximity UUID", text: $beacon.uuidText)
            .font(.body.monospaced())
            .autocorrectionDisabled()
            #if os(iOS)
            .textInputAutocapitalization(.characters)
            #endif
            .onChange(of: beacon.uuidText) { _, text in
                if beacon.preset.uuid.map({ $0 != text }) ?? false { beacon.preset = .custom }
            }
        TextField("Major (empty = any)", text: $beacon.majorText)
            #if os(iOS)
            .keyboardType(.numberPad)
            #endif
        TextField("Minor (empty = any, needs a major)", text: $beacon.minorText)
            #if os(iOS)
            .keyboardType(.numberPad)
            #endif
    }
}

private struct BeaconListView: View {
    @ObservedObject var beacon: BeaconRangingService

    var body: some View {
        Section("Beacons in range (\(beacon.beacons.count))") {
            if let identity = beacon.activeIdentity, beacon.isRanging {
                Text(identity.summary)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            LabeledContent("Ranging callbacks", value: "\(beacon.callbackCount)")
            LabeledContent("Distinct beacons this session", value: "\(beacon.distinctBeacons)")
            if let last = beacon.lastCallback {
                LabeledContent("Last callback", value: last.formatted(date: .omitted, time: .standard))
            }
            if beacon.beacons.isEmpty {
                Text(beacon.isRanging ? "No matching beacon in range right now." : "Start ranging to list matching beacons with proximity, estimated distance and RSSI.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(beacon.beacons) { reading in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Label("Major \(reading.major) · Minor \(reading.minor)", systemImage: reading.proximity.symbol)
                            .font(.headline)
                        Spacer()
                        Text(reading.proximity.rawValue)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Self.color(for: reading.proximity))
                    }
                    HStack(spacing: 12) {
                        Text("Distance \(reading.accuracyText)")
                        Text("RSSI \(reading.rssiText)")
                    }
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    Text(reading.uuid.uuidString)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            }
        }
    }

    private static func color(for proximity: BeaconProximity) -> Color {
        switch proximity {
        case .immediate: .green
        case .near: .blue
        case .far: .orange
        case .unknown: .secondary
        }
    }
}
