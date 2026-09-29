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
    @State private var protection = KeychainProtection.userPresence
    @State private var output: String
    @State private var isAuthenticating = false

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
        Picker("Protected item", selection: $protection) {
            ForEach(KeychainProtection.allCases) { Text($0.title).tag($0) }
        }
        Button("Save Protected Item") { output = KeychainService.saveProtected(value: value, protection: protection) }
        Button("Read with Face ID / Touch ID / Passcode", action: readProtected)
            .disabled(isAuthenticating)
        Button("Delete Protected Item") { output = KeychainService.deleteProtected() }
        OutputView(text: output, isError: Self.isFailure(output))
    }

    private func readProtected() {
        isAuthenticating = true
        output = "Waiting for authentication…"
        Task {
            output = await KeychainService.readProtected()
            isAuthenticating = false
        }
    }

    private static func isFailure(_ text: String) -> Bool {
        ["failed", "not available", "errSec", "OSStatus"].contains { text.contains($0) } && !text.contains("errSecSuccess")
    }
}

struct SecureEnclaveRunView: View {
    @State private var message = "Hello from Joris Apple Toolbox"
    @State private var requireUserPresence = false
    @State private var storedKey = "—"
    @State private var output: String
    @State private var isSigning = false

    init(experiment: ExperimentDescriptor) {
        _output = State(initialValue: ExperimentOutput.initialMessage(for: experiment.currentStatus))
    }

    var body: some View {
        TextField("Message to sign", text: $message)
        Button("Sign with a One-Time Key") {
            do { output = try SecureEnclaveService.run(message: message) }
            catch { output = "Error: \(error.localizedDescription)" }
        }
        .buttonStyle(.borderedProminent)
        LabeledContent("Persistent key") { Text(storedKey).multilineTextAlignment(.trailing) }
            .onAppear { storedKey = SecureEnclaveService.storedKeySummary() }
        Toggle("Require user presence for a new key", isOn: $requireUserPresence)
        Button("Sign with Persistent Key", action: signWithPersistentKey)
            .disabled(isSigning)
        Button("Delete Persistent Key", role: .destructive) {
            output = SecureEnclaveService.deletePersistentKey()
            storedKey = SecureEnclaveService.storedKeySummary()
        }
        OutputView(text: output, isError: output.localizedCaseInsensitiveContains("error") || output.localizedCaseInsensitiveContains("not available") || output.localizedCaseInsensitiveContains("failed"))
    }

    private func signWithPersistentKey() {
        isSigning = true
        output = "Loading or creating the Secure Enclave key…"
        Task {
            output = await SecureEnclaveService.signWithPersistentKey(message: message, requireUserPresence: requireUserPresence)
            storedKey = SecureEnclaveService.storedKeySummary()
            isSigning = false
        }
    }
}
