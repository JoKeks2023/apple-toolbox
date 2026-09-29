import SwiftUI

struct HealthKitReaderRunView: View {
    @StateObject private var health: HealthKitReaderService

    init(experiment: ExperimentDescriptor) {
        _health = StateObject(wrappedValue: HealthKitReaderService(initialOutput: ExperimentOutput.initialMessage(for: experiment.currentStatus)))
    }

    var body: some View {
        Picker("Data set", selection: $health.preset) {
            ForEach(HealthReaderPreset.allCases) { Text($0.title).tag($0) }
        }
        .disabled(health.isReading || health.isRequesting)
        Text(health.typeOptions.map(\.title).joined(separator: " · "))
            .font(.caption)
            .foregroundStyle(.secondary)
        LabeledContent("Request status") { Text(health.requestStatus).multilineTextAlignment(.trailing) }
            .onAppear(perform: health.checkRequestStatus)
        HStack {
            Button(health.isRequesting ? "Requesting…" : "Request Read Access", action: health.requestAuthorization)
                .buttonStyle(.borderedProminent)
                .disabled(health.isRequesting)
            Button(health.isReading ? "Reading…" : "Read Recent Samples", action: health.readRecent)
                .buttonStyle(.bordered)
                .disabled(health.isReading)
        }
        Text("HealthKit keeps read decisions private: after the request the app only knows that it asked. Types you declined return no samples, exactly like types without data.")
            .font(.caption)
            .foregroundStyle(.secondary)

        ForEach(health.groups) { group in
            Section(group.title) {
                ForEach(group.rows) { row in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(row.title).font(.subheadline)
                            Spacer(minLength: 8)
                            Text(row.value).font(.callout.monospacedDigit()).multilineTextAlignment(.trailing)
                        }
                        if !row.detail.isEmpty {
                            Text(row.detail).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                if let note = group.note {
                    Text(note).font(.caption).foregroundStyle(.secondary)
                }
            }
        }

        Section("Background delivery") {
            LabeledContent("Entitlement") { Text(health.backgroundDeliveryEntitlement).multilineTextAlignment(.trailing) }
            Picker("Type", selection: $health.observedTypeID) {
                ForEach(health.typeOptions) { Text($0.title).tag($0.id) }
            }
            .disabled(health.isObserving)
            Picker("Frequency", selection: $health.frequency) {
                ForEach(HealthDeliveryFrequency.allCases) { Text($0.title).tag($0) }
            }
            .disabled(health.isObserving)
            Button(health.isObserving ? "Stop Observer & Disable Delivery" : "Start Observer & Enable Delivery") {
                if health.isObserving { health.stopObserving() } else { health.startObserving() }
            }
            .buttonStyle(.bordered)
            .experimentSession(health)
            LabeledContent("Observer query") { Text(health.observerState).multilineTextAlignment(.trailing) }
            LabeledContent("Background delivery") { Text(health.deliveryState).multilineTextAlignment(.trailing) }
            if let newest = health.newestObservedSample {
                LabeledContent("Newest sample") { Text(newest).multilineTextAlignment(.trailing) }
            }
            Text("The observer query runs only while this experiment is open, and leaving it disables background delivery again. An app that wants to be woken in the background must register its observer queries at every launch.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        Section("Health Records · why clinical data is not read") {
            ForEach(health.healthRecordsRows) { row in
                LabeledContent(row.title) { Text(row.value).multilineTextAlignment(.trailing) }
            }
            Text("Clinical records (HKClinicalType: allergies, conditions, immunizations, lab results, medications, procedures, vital signs) need the health-records value in com.apple.developer.healthkit.access and the NSHealthClinicalHealthRecordsShareUsageDescription key. This build declares neither, and HealthKit refuses a clinical request without them, so Apple Toolbox does not send one. Health Records also exists only where the Health app supports it (supportsHealthRecords()).")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        OutputView(text: health.output, isError: health.isError)
    }
}
