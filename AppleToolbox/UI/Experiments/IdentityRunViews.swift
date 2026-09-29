import SwiftUI
#if canImport(AuthenticationServices)
import AuthenticationServices
#endif

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

struct SignInWithAppleRunView: View {
    @StateObject private var signIn: SignInWithAppleExperimentService
    @Environment(\.colorScheme) private var colorScheme

    init(experiment: ExperimentDescriptor) {
        _signIn = StateObject(wrappedValue: SignInWithAppleExperimentService(initialOutput: ExperimentOutput.initialMessage(for: experiment.currentStatus)))
    }

    var body: some View {
        OutputView(text: SignInWithAppleExperimentService.entitlementSummary, isError: false)
        #if canImport(AuthenticationServices)
        SignInWithAppleButton(.signIn) { signIn.configure($0) } onCompletion: { signIn.handle($0) }
            .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
            #if !os(tvOS)
            .frame(maxWidth: 320, minHeight: 44, maxHeight: 44)
            #endif
        Button("Check Credential State") { Task { await signIn.checkCredentialState() } }
            .disabled(signIn.userID == nil || signIn.isCheckingState)
        #endif
        OutputView(text: signIn.output, isError: signIn.isError)
        Text("The identity token and authorization code are never displayed. A real app sends them to its server, which verifies the token with Apple's public keys and redeems the code.")
            .font(.caption).foregroundStyle(.secondary)
    }
}

struct PasskeysRunView: View {
    @StateObject private var passkeys: PasskeyExperimentService

    init(experiment: ExperimentDescriptor) {
        _passkeys = StateObject(wrappedValue: PasskeyExperimentService(initialOutput: ExperimentOutput.initialMessage(for: experiment.currentStatus)))
    }

    var body: some View {
        OutputView(text: PasskeyExperimentService.configurationSummary, isError: false)
        TextField("Relying-party identifier (domain)", text: $passkeys.relyingPartyID)
            .autocorrectionDisabled()
            #if os(iOS)
            .textInputAutocapitalization(.never)
            .keyboardType(.URL)
            #endif
        TextField("User name", text: $passkeys.userName)
            .autocorrectionDisabled()
            #if os(iOS)
            .textInputAutocapitalization(.never)
            #endif
        HStack {
            Button("Create Passkey", action: passkeys.register).buttonStyle(.borderedProminent)
                .experimentSession(passkeys)
            Button("Sign In with Passkey", action: passkeys.signIn).buttonStyle(.bordered)
        }
        .disabled(passkeys.isRunning)
        OutputView(text: passkeys.output, isError: passkeys.isError)
        Text("Challenges and the user ID are random bytes generated on this device. A real relying party issues the challenge on its server and verifies the returned attestation or signature.")
            .font(.caption).foregroundStyle(.secondary)
    }
}
