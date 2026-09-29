import SwiftUI

/// Run views for the Security category.
struct SecurityRunRoutes: View {
    let experiment: ExperimentDescriptor

    var body: some View {
        switch experiment.id {
        case "localauthentication": LocalAuthenticationRunView(experiment: experiment)
        case "cryptokit": CryptoKitRunView(experiment: experiment)
        case "keychain": KeychainRunView(experiment: experiment)
        case "secure-enclave": SecureEnclaveRunView(experiment: experiment)
        case "app-attest": AppAttestRunView(experiment: experiment)
        case "passkeys": PasskeysRunView(experiment: experiment)
        case "sign-in-with-apple": SignInWithAppleRunView(experiment: experiment)
        case "keychain-sharing": KeychainSharingRunView(experiment: experiment)
        case "security-keys": SecurityKeysRunView(experiment: experiment)
        case "credential-provider": CredentialProviderRunView(experiment: experiment)
        default: UnroutedExperimentView()
        }
    }
}
