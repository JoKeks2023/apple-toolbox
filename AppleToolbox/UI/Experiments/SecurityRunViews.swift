import SwiftUI

struct CryptoKitRunView: View {
    @State private var request = CryptoLabRequest()
    @State private var output: String
    @State private var isError = false

    init(experiment: ExperimentDescriptor) {
        _output = State(initialValue: ExperimentOutput.initialMessage(for: experiment.currentStatus))
    }

    var body: some View {
        Picker("Operation", selection: $request.operation) {
            ForEach(CryptoLabOperation.allCases) { Text($0.title).tag($0) }
        }
        algorithmPickers
        if request.operation != .keys {
            TextField("Message", text: $request.message, axis: .vertical)
                .lineLimit(1...4)
        }
        if request.operation == .hmac {
            TextField("HMAC key (UTF-8 text)", text: $request.hmacKey)
                .autocorrectionDisabled()
        }
        if request.operation == .encrypt || request.operation == .hpke {
            TextField("Associated data (optional, authenticated but not encrypted)", text: $request.associatedData)
                .autocorrectionDisabled()
        }
        Button(request.operation == .keys ? "Generate & Export Key" : "Run \(request.operation.title)") { show(CryptoLab.run(request)) }
            .buttonStyle(.borderedProminent)
        if request.operation == .keys {
            Picker("Import format", selection: $request.keyFormat) {
                ForEach(CryptoLabKeyFormat.allCases) { Text($0.title).tag($0) }
            }
            Picker("Key part", selection: $request.keyPart) {
                ForEach(CryptoLabKeyPart.allCases) { Text($0.title).tag($0) }
            }
            TextField("Key to import: PEM, hex or Base64", text: $request.importText, axis: .vertical)
                .lineLimit(2...8)
                .font(.system(.footnote, design: .monospaced))
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
            Button("Import Key") { show(CryptoLab.importReport(request)) }
        }
        OutputView(text: output, isError: isError)
        Text("Keys generated here live only in memory for this run and are shown in full so you can inspect them; never paste production private keys into a lab.")
            .font(.caption).foregroundStyle(.secondary)
    }

    @ViewBuilder private var algorithmPickers: some View {
        switch request.operation {
        case .hash, .hmac:
            Picker("Hash function", selection: $request.hash) {
                ForEach(CryptoLabHash.allCases) { Text($0.title).tag($0) }
            }
        case .encrypt:
            Picker("Cipher", selection: $request.cipher) {
                ForEach(CryptoLabCipher.allCases) { Text($0.title).tag($0) }
            }
        case .keyAgreement:
            Picker("Curve", selection: $request.curve) {
                ForEach(CryptoLabCurve.allCases) { Text($0.title).tag($0) }
            }
            Picker("HKDF hash", selection: $request.hash) {
                ForEach(CryptoLabHash.allCases) { Text($0.title).tag($0) }
            }
        case .signature:
            Picker("Algorithm", selection: $request.signature) {
                ForEach(CryptoLabSignatureAlgorithm.allCases) { Text($0.title).tag($0) }
            }
        case .hpke:
            Picker("Ciphersuite", selection: $request.hpkeSuite) {
                ForEach(CryptoLabHPKESuite.allCases) { Text($0.title).tag($0) }
            }
        case .keys:
            Picker("Key type", selection: $request.keyKind) {
                ForEach(CryptoLabKeyKind.allCases) { Text($0.title).tag($0) }
            }
        }
    }

    private func show(_ report: CryptoLabReport) {
        output = report.text
        isError = report.isError
        if let candidate = report.importCandidate {
            request.importText = candidate
            request.keyFormat = report.importFormat ?? request.keyFormat
            request.keyPart = report.importPart ?? request.keyPart
        }
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
    @State private var message = "Hello from Apple Toolbox"
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
