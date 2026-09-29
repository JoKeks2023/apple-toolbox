import Foundation

extension ExperimentRegistry {
    static let security: [ExperimentDescriptor] = [
        ExperimentDescriptor(id: "localauthentication", name: "LocalAuthentication", category: .security,
            description: "Test Face ID, Touch ID, or device-owner authentication and inspect real failure states.",
            frameworks: ["LocalAuthentication"], supportedPlatforms: [.iOS, .iPadOS, .macOS],
            hardwareRequirements: ["Face ID or Touch ID when biometrics are tested"], osRequirements: ["iOS 11+ · macOS 10.13+"],
            permissions: ["Biometric/device authentication prompt"], capabilities: [], entitlements: [],
            documentationURL: URL(string: "https://developer.apple.com/documentation/localauthentication")!, evaluate: ExperimentAvailability.localAuthentication,
            useCase: ExperimentUseCase(id: "biometric-gate", title: "Protect an action", summary: "Use the device owner authentication policy before releasing a result.", interaction: "Run authentication and inspect the real biometric or passcode outcome."),
            explanations: [
                .unavailable: ExperimentExplanation(reason: "No device passcode is set, so owner authentication cannot run.", required: "A device passcode (and optionally Face ID or Touch ID)",
                    nextStep: "Set a passcode in Settings › Face ID & Passcode."),
                .hardwareUnsupported: ExperimentExplanation(reason: "Neither biometrics nor passcode authentication can be evaluated here.", required: "Face ID, Touch ID or a device passcode",
                    nextStep: "Run on a device with a passcode; in the Simulator enroll Face ID via Features › Face ID."),
            ]),
        ExperimentDescriptor(id: "cryptokit", name: "CryptoKit", category: .security,
            description: "Hash data, create a P-256 key, sign a message, and verify the signature in one live run.",
            frameworks: ["CryptoKit"], supportedPlatforms: SupportedPlatform.allCases,
            hardwareRequirements: [], osRequirements: ["iOS 13+ · macOS 10.15+ · watchOS 6+ · tvOS 13+"], permissions: [], capabilities: [], entitlements: [],
            documentationURL: URL(string: "https://developer.apple.com/documentation/cryptokit")!, evaluate: { .available },
            useCase: ExperimentUseCase(id: "crypto-message", title: "Sign a message", summary: "Use CryptoKit to hash and sign text that you choose.", interaction: "Enter a message, then run hashing or signing and inspect the live output.")),
        ExperimentDescriptor(id: "keychain", name: "Keychain", category: .security,
            description: "Write, read, and delete a generic password, and store one behind SecAccessControl so reading it needs Face ID, Touch ID, or the passcode.",
            frameworks: ["Security", "LocalAuthentication"], supportedPlatforms: SupportedPlatform.allCases, hardwareRequirements: [], osRequirements: ["iOS 2+ · macOS 10.6+", "Access control: iOS 11.3+ · macOS 10.13.4+"], permissions: ["Face ID, Touch ID or passcode prompt (protected item)"], capabilities: ["Data Protection"], entitlements: [],
            documentationURL: URL(string: "https://developer.apple.com/documentation/security/keychain_services")!, evaluate: { .available },
            useCase: ExperimentUseCase(id: "keychain-value", title: "Store a secret", summary: "Use the Keychain as a small persistent credential store and lock one item behind Face ID, Touch ID, or the passcode.", interaction: "Save, read, and delete a plain value; then pick a protection, save a protected item, and read it back through the real authentication prompt.")),
        ExperimentDescriptor(id: "secure-enclave", name: "Secure Enclave", category: .security,
            description: "Create a non-exportable signing key, keep it across runs through its Keychain blob, sign and verify, and delete it again.",
            frameworks: ["CryptoKit", "Security", "LocalAuthentication"], supportedPlatforms: [.iOS, .iPadOS, .macOS, .watchOS], hardwareRequirements: ["Secure Enclave"], osRequirements: ["iOS 11+ · macOS 10.14+ · watchOS 4+"], permissions: ["Face ID, Touch ID or passcode prompt (keys that require user presence)"], capabilities: [], entitlements: [],
            documentationURL: URL(string: "https://developer.apple.com/documentation/cryptokit/storing-keys-in-the-secure-enclave")!, evaluate: { DeviceCapabilities.current.secureEnclave ? .available : .hardwareUnsupported },
            useCase: ExperimentUseCase(id: "secure-enclave-signature", title: "Sign with hardware-backed storage", summary: "Keep a non-exportable Secure Enclave key across launches and sign your own message with it.", interaction: "Sign with the persistent key to see whether it was created or reused and compare its fingerprint; delete it to start over. The private key never leaves the enclave."),
            explanations: [
                .hardwareUnsupported: ExperimentExplanation(reason: "This device or simulator does not provide a Secure Enclave, so keys can be neither created nor restored.", required: "A device with a Secure Enclave (iPhone 5s or later, Apple silicon or T2 Mac, Apple Watch)",
                    nextStep: "Run the experiment on a physical device."),
            ]),
        ExperimentDescriptor(id: "app-attest", name: "App Attest & DeviceCheck", category: .security,
            description: "Generate and attest a Secure Enclave key, sign a sample payload with an assertion, and request a DeviceCheck token. The challenge is local; server-side verification is out of scope.", frameworks: ["DeviceCheck", "CryptoKit"], supportedPlatforms: SupportedPlatform.allCases, hardwareRequirements: ["A physical device that supports App Attest (not the Simulator)"], osRequirements: ["App Attest: iOS 14+ · macOS 11+ · tvOS 15+ · watchOS 9+", "DeviceCheck: iOS 11+ · macOS 10.15+ · tvOS 11+ · watchOS 9+"], permissions: [], capabilities: ["App ID registered with Apple", "App Attest capability optional (development builds use the sandbox without it)"], entitlements: [], documentationURL: URL(string: "https://developer.apple.com/documentation/devicecheck/establishing-your-app-s-integrity")!, evaluate: ExperimentAvailability.appAttest,
            explanations: [
                .hardwareUnsupported: ExperimentExplanation(reason: "DCAppAttestService reports that App Attest is not supported here (for example in the Simulator).", required: "A physical device with a Secure Enclave and an App ID registered with Apple",
                    nextStep: "Run the experiment on a real device; the DeviceCheck token can still be tried below."),
            ]),
        ExperimentDescriptor(id: "passkeys", name: "Passkeys", category: .security,
            description: "Send a real passkey registration or assertion request for a relying party you enter and inspect the credential or the system's error. Challenges are local random bytes.", frameworks: ["AuthenticationServices"], supportedPlatforms: [.iOS, .iPadOS, .macOS, .tvOS], hardwareRequirements: [], osRequirements: ["iOS 15+ · macOS 12+ · tvOS 16+"], permissions: [], capabilities: ["Associated Domains with a webcredentials: entry", "apple-app-site-association file on the relying-party domain"], entitlements: ["com.apple.developer.associated-domains (webcredentials:)"], documentationURL: URL(string: "https://developer.apple.com/documentation/authenticationservices/supporting-passkeys")!, evaluate: ExperimentAvailability.passkeys,
            explanations: [
                .entitlementRequired: ExperimentExplanation(reason: "Passkeys are bound to a relying-party domain, and no webcredentials: associated domain is provisioned for this app.", required: "Associated Domains entitlement with webcredentials:<domain> and an apple-app-site-association file on that domain listing this app",
                    nextStep: "Add the Associated Domains capability for your relying party and host the association file. The requests below still run and show the system's rejection."),
            ]),
        ExperimentDescriptor(id: "sign-in-with-apple", name: "Sign in with Apple", category: .security,
            description: "Run the real Sign in with Apple flow, inspect the returned credential (shortened identifier, real-user status, token and code sizes) and query its credential state.", frameworks: ["AuthenticationServices"], supportedPlatforms: SupportedPlatform.allCases, hardwareRequirements: [], osRequirements: ["iOS 13+ · macOS 10.15+ · tvOS 13+ · watchOS 6+"], permissions: [], capabilities: ["Sign in with Apple", "Apple Account signed in on the device"], entitlements: ["com.apple.developer.applesignin"], documentationURL: URL(string: "https://developer.apple.com/documentation/authenticationservices/implementing-user-authentication-with-sign-in-with-apple")!, evaluate: ExperimentAvailability.signInWithApple,
            explanations: [
                .entitlementRequired: ExperimentExplanation(reason: "Neither the embedded provisioning profile nor this build's readable signed entitlements include Sign in with Apple.", required: "com.apple.developer.applesignin = [Default], enabled on the App ID of a paid developer team",
                    nextStep: "Add the Sign in with Apple capability to this target in Xcode › Signing & Capabilities; the button below still shows the system's real error."),
            ]),
    ]
}
