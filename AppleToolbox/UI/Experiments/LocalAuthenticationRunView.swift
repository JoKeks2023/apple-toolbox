import SwiftUI

struct LocalAuthenticationRunView: View {
    @StateObject private var auth: LocalAuthenticationExperimentService
    @State private var message = "Sign me with the persisted right"

    init(experiment: ExperimentDescriptor) {
        _auth = StateObject(wrappedValue: LocalAuthenticationExperimentService(initialOutput: ExperimentOutput.initialMessage(for: experiment.currentStatus)))
    }

    var body: some View {
        OutputView(text: auth.overview, isError: false)
            .onAppear(perform: auth.inspect)
        Button("Check Policies & Domain State Again", action: auth.inspect)
        Text("Checking never prompts. The domain state hashes are stored on this device and compared on the next check, so a changed hash means the biometric enrolment changed in between.")
            .font(.caption).foregroundStyle(.secondary)

        Section("Evaluate a policy · system prompt") {
            Picker("Policy", selection: $auth.policy) {
                ForEach(LocalAuthenticationPolicyOption.allCases) { Text($0.title).tag($0) }
            }
            Picker("Reuse window", selection: $auth.reuseDuration) {
                ForEach(LocalAuthenticationReuseDuration.allCases) { Text($0.title).tag($0) }
            }
            Button("Evaluate Policy", action: auth.evaluate)
                .buttonStyle(.borderedProminent)
                .experimentSession(auth)
        }
        .disabled(auth.isRunning)

        Section("LARight") {
            Picker("Requirement", selection: $auth.requirement) {
                ForEach(LocalAuthenticationRightRequirement.allCases) { Text($0.title).tag($0) }
            }
            LabeledContent("State", value: auth.rightState)
            Button("Check Requirement (no prompt)", action: auth.checkRight)
            Button("Authorize Right", action: auth.authorizeRight)
            Button("Deauthorize Right", action: auth.deauthorizeRight)
        }
        .disabled(auth.isRunning)

        Section("LAPersistedRight · LARightStore") {
            TextField("Secret to store with the right", text: $auth.secret)
            TextField("Message to sign with the right's key", text: $message)
            Button("Save Persisted Right", action: auth.savePersistedRight)
            Button("Authorize, Sign & Read Secret") { auth.usePersistedRight(message: message) }
            Button("Remove Persisted Right", role: .destructive, action: auth.removePersistedRight)
            Text("The right uses the requirement chosen above. The system creates the key pair and keeps the secret; the app only receives them after authorization.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .disabled(auth.isRunning)

        Section("Result") {
            OutputView(text: auth.output, isError: auth.isError)
        }
    }
}
