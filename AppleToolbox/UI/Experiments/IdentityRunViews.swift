import SwiftUI

struct AppAttestRunView: View {
    @StateObject private var appAttest: AppAttestExperimentService

    init(experiment: ExperimentDescriptor) {
        _appAttest = StateObject(wrappedValue: AppAttestExperimentService(initialOutput: ExperimentOutput.initialMessage(for: experiment.currentStatus)))
    }

    var body: some View {
        OutputView(text: AppAttestExperimentService.supportSummary, isError: false)
        Button("Generate & Attest Key") { Task { await appAttest.generateAndAttestKey() } }
            .buttonStyle(.borderedProminent).disabled(appAttest.isRunning)
        Button("Generate Assertion for Sample Payload") { Task { await appAttest.generateAssertion() } }
            .disabled(appAttest.isRunning || appAttest.attestedKeyID == nil)
        Button("Request DeviceCheck Token") { Task { await appAttest.requestDeviceCheckToken() } }
            .disabled(appAttest.isRunning)
        OutputView(text: appAttest.output, isError: appAttest.isError)
        Text("Server-side verification is out of scope: this lab only shows what the device produces. A real deployment verifies attestations, assertions and DeviceCheck tokens on its own server.")
            .font(.caption).foregroundStyle(.secondary)
    }
}
