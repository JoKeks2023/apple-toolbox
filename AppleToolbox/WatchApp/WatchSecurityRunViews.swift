import SwiftUI
import AuthenticationServices

// Compact watch run views for the Security experiments. Each one calls the same shared service as the iPhone view.

struct WatchCryptoKitView: View {
    @State private var request = CryptoLabRequest()
    @State private var report: CryptoLabReport?

    var body: some View {
        List {
            Picker("Operation", selection: $request.operation) {
                ForEach(CryptoLabOperation.allCases) { Text($0.title).tag($0) }
            }
            algorithmPicker
            if request.operation != .keys {
                TextField("Message", text: $request.message)
            }
            if request.operation == .hmac {
                TextField("HMAC key", text: $request.hmacKey)
            }
            Button(request.operation == .keys ? "Generate & Export" : "Run", systemImage: "play.fill") { report = CryptoLab.run(request) }
            if let report {
                Text(report.text)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(report.isError ? .red : .primary)
            } else {
                WatchOutput(text: "Every run checks the round trip on this watch and shows that tampered data is rejected.")
            }
        }
        .navigationTitle("CryptoKit")
    }

    @ViewBuilder private var algorithmPicker: some View {
        switch request.operation {
        case .hash, .hmac:
            Picker("Hash", selection: $request.hash) { ForEach(CryptoLabHash.allCases) { Text($0.title).tag($0) } }
        case .encrypt:
            Picker("Cipher", selection: $request.cipher) { ForEach(CryptoLabCipher.allCases) { Text($0.title).tag($0) } }
        case .keyAgreement:
            Picker("Curve", selection: $request.curve) { ForEach(CryptoLabCurve.allCases) { Text($0.title).tag($0) } }
        case .signature:
            Picker("Algorithm", selection: $request.signature) { ForEach(CryptoLabSignatureAlgorithm.allCases) { Text($0.title).tag($0) } }
        case .hpke:
            Picker("Suite", selection: $request.hpkeSuite) { ForEach(CryptoLabHPKESuite.allCases) { Text($0.title).tag($0) } }
        case .keys:
            Picker("Key type", selection: $request.keyKind) { ForEach(CryptoLabKeyKind.allCases) { Text($0.title).tag($0) } }
        }
    }
}

struct WatchKeychainView: View {
    @State private var value = "Watch secret"
    @State private var output = "Save, read and delete a generic password in this watch's keychain."

    var body: some View {
        List {
            TextField("Value", text: $value)
            Button("Save", systemImage: "square.and.arrow.down") { output = KeychainService.save(value: value) }
            Button("Read", systemImage: "eye") { output = KeychainService.read() }
            Button("Delete", systemImage: "trash", role: .destructive) { output = KeychainService.delete() }
            Section {
                WatchOutput(text: output, isError: !output.contains("errSecSuccess") && (output.contains("errSec") || output.contains("OSStatus")))
            } footer: {
                Text("The watch has its own keychain; items are not shared with the iPhone app. The Face ID / Touch ID protected item runs on iPhone, iPad and Mac.")
            }
        }
        .navigationTitle("Keychain")
    }
}

struct WatchSecureEnclaveView: View {
    @State private var message = "Signed on Apple Watch"
    @State private var storedKey = SecureEnclaveService.storedKeySummary()
    @State private var output = "Sign with a persistent, non-exportable Secure Enclave key."
    @State private var isSigning = false

    var body: some View {
        List {
            TextField("Message", text: $message)
            Button(isSigning ? "Signing…" : "Sign", systemImage: "signature") {
                isSigning = true
                Task {
                    output = await SecureEnclaveService.signWithPersistentKey(message: message, requireUserPresence: false)
                    storedKey = SecureEnclaveService.storedKeySummary()
                    isSigning = false
                }
            }
            .disabled(isSigning)
            Button("Delete Key", systemImage: "trash", role: .destructive) {
                output = SecureEnclaveService.deletePersistentKey()
                storedKey = SecureEnclaveService.storedKeySummary()
            }
            Section {
                WatchFactRow(title: "Stored key", text: storedKey)
                WatchOutput(text: output, isError: output.contains("Error") || output.contains("failed") || output.contains("does not provide"))
            } footer: {
                Text("The key blob stays in this watch's keychain; the private key never leaves the Secure Enclave. The watch lab creates keys without a user-presence requirement.")
            }
        }
        .navigationTitle("Secure Enclave")
    }
}

struct WatchAppAttestView: View {
    @StateObject private var attest: AppAttestExperimentService

    init(experiment: ExperimentDescriptor) {
        _attest = StateObject(wrappedValue: AppAttestExperimentService(initialOutput: WatchRunText.initialMessage(for: experiment.currentStatus)))
    }

    var body: some View {
        List {
            Button("Generate & Attest Key", systemImage: "key") { Task { await attest.generateAndAttestKey() } }
                .disabled(attest.isRunning)
            Button("Generate Assertion", systemImage: "checkmark.seal") { Task { await attest.generateAssertion() } }
                .disabled(attest.isRunning || attest.attestedKeyID == nil)
            Button("DeviceCheck Token", systemImage: "iphone.gen3.radiowaves.left.and.right") { Task { await attest.requestDeviceCheckToken() } }
                .disabled(attest.isRunning)
            if attest.isRunning { ProgressView() }
            WatchOutput(text: attest.output, isError: attest.isError)
            Section("Support") {
                WatchOutput(text: AppAttestExperimentService.supportSummary)
            }
        }
        .navigationTitle("App Attest")
    }
}

struct WatchSignInWithAppleView: View {
    @StateObject private var signIn: SignInWithAppleExperimentService

    init(experiment: ExperimentDescriptor) {
        _signIn = StateObject(wrappedValue: SignInWithAppleExperimentService(initialOutput: WatchRunText.initialMessage(for: experiment.currentStatus)))
    }

    var body: some View {
        List {
            SignInWithAppleButton(.signIn) { signIn.configure($0) } onCompletion: { signIn.handle($0) }
                .frame(minHeight: 44)
            Button("Credential State", systemImage: "person.badge.shield.checkmark") { Task { await signIn.checkCredentialState() } }
                .disabled(signIn.userID == nil || signIn.isCheckingState)
            WatchOutput(text: signIn.output, isError: signIn.isError)
            Section("Entitlement") {
                WatchOutput(text: SignInWithAppleExperimentService.entitlementSummary)
            }
        }
        .navigationTitle("Sign in with Apple")
    }
}

/// First output line before anything ran, like `ExperimentOutput.initialMessage(for:)` on the iPhone.
enum WatchRunText {
    static func initialMessage(for status: ExperimentStatus) -> String {
        switch status {
        case .available: "Ready. Results from the real system API appear here."
        case .permissionRequired: "Permission has not been granted yet. The system asks when the experiment starts."
        default: "Not available right now (\(status.title)). See “Why doesn't this work?”; the real API result still appears here."
        }
    }
}
