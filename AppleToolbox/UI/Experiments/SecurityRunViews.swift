import SwiftUI

struct LocalAuthenticationRunView: View {
    let experiment: ExperimentDescriptor
    @State private var output: String
    @State private var isRunning = false

    init(experiment: ExperimentDescriptor) {
        self.experiment = experiment
        _output = State(initialValue: ExperimentOutput.initialMessage(for: experiment.currentStatus))
    }

    var body: some View {
        OutputView(text: AuthenticationService.availability(), isError: false)
        Button("Authenticate with Face ID / Touch ID", action: authenticate)
            .buttonStyle(.borderedProminent).disabled(isRunning || experiment.currentStatus != .available)
        OutputView(text: output, isError: output.localizedCaseInsensitiveContains("error"))
    }

    private func authenticate() {
        isRunning = true
        Task {
            do { output = try await AuthenticationService.authenticate() }
            catch { output = "Error: \(error.localizedDescription)" }
            isRunning = false
        }
    }
}

struct CryptoKitRunView: View {
    @State private var message = "Hello from Joris Apple Toolbox"
    @State private var output: String

    init(experiment: ExperimentDescriptor) {
        _output = State(initialValue: ExperimentOutput.initialMessage(for: experiment.currentStatus))
    }

    var body: some View {
        TextField("Message to hash or sign", text: $message)
        Button("Hash with SHA-256") { output = CryptoService.hash(message: message) }
        Button("Sign and Verify with P-256") { output = CryptoService.signAndVerify(message: message) }
            .buttonStyle(.borderedProminent)
        Button("Run Complete Crypto Experiment") { output = CryptoService.run(message: message) }
        OutputView(text: output, isError: output.localizedCaseInsensitiveContains("not available"))
    }
}

struct KeychainRunView: View {
    @State private var value = "A secret I chose to store"
    @State private var output: String

    init(experiment: ExperimentDescriptor) {
        _output = State(initialValue: ExperimentOutput.initialMessage(for: experiment.currentStatus))
    }

    var body: some View {
        TextField("Value to store", text: $value)
        HStack {
            Button("Save", action: { output = KeychainService.save(value: value) })
            Button("Read", action: { output = KeychainService.read() })
            Button("Delete", action: { output = KeychainService.delete() })
        }
        .buttonStyle(.borderedProminent)
        OutputView(text: output, isError: output.localizedCaseInsensitiveContains("failed") || output.localizedCaseInsensitiveContains("not available"))
    }
}

struct SecureEnclaveRunView: View {
    @State private var message = "Hello from Joris Apple Toolbox"
    @State private var output: String

    init(experiment: ExperimentDescriptor) {
        _output = State(initialValue: ExperimentOutput.initialMessage(for: experiment.currentStatus))
    }

    var body: some View {
        TextField("Message to sign", text: $message)
        Button("Create key and sign message") {
            do { output = try SecureEnclaveService.run(message: message) }
            catch { output = "Error: \(error.localizedDescription)" }
        }
        .buttonStyle(.borderedProminent)
        OutputView(text: output, isError: output.localizedCaseInsensitiveContains("error") || output.localizedCaseInsensitiveContains("not available"))
    }
}
