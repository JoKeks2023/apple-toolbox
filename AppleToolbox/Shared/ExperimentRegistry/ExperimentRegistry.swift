import Foundation

enum ExperimentRegistry {
    static let all: [ExperimentDescriptor] = [
        ExperimentDescriptor(id: "localauthentication", name: "LocalAuthentication", category: .security,
            description: "Test Face ID, Touch ID, or device-owner authentication and inspect real failure states.",
            frameworks: ["LocalAuthentication"], supportedPlatforms: SupportedPlatform.allCases,
            hardwareRequirements: ["Face ID or Touch ID when biometrics are tested"], osRequirements: ["iOS 11+ · macOS 10.13+ · watchOS 4+ · tvOS 11+"],
            permissions: ["Biometric/device authentication prompt"], capabilities: [], entitlements: [],
            documentationURL: URL(string: "https://developer.apple.com/documentation/localauthentication")!, evaluate: { .available }),
        ExperimentDescriptor(id: "cryptokit", name: "CryptoKit", category: .security,
            description: "Hash data, create a P-256 key, sign a message, and verify the signature in one live run.",
            frameworks: ["CryptoKit"], supportedPlatforms: SupportedPlatform.allCases,
            hardwareRequirements: [], osRequirements: ["iOS 13+ · macOS 10.15+ · watchOS 6+ · tvOS 13+"], permissions: [], capabilities: [], entitlements: [],
            documentationURL: URL(string: "https://developer.apple.com/documentation/cryptokit")!, evaluate: { .available }),
        ExperimentDescriptor(id: "keychain", name: "Keychain", category: .security,
            description: "Write, read, and delete a generic password item using the public Keychain API.",
            frameworks: ["Security"], supportedPlatforms: SupportedPlatform.allCases, hardwareRequirements: [], osRequirements: ["iOS 2+ · macOS 10.6+"], permissions: [], capabilities: ["Data Protection"], entitlements: [],
            documentationURL: URL(string: "https://developer.apple.com/documentation/security/keychain_services")!, evaluate: { .available }),
        ExperimentDescriptor(id: "secure-enclave", name: "Secure Enclave", category: .security,
            description: "Create a non-exportable signing key, expose its public key, and verify a signature.",
            frameworks: ["CryptoKit"], supportedPlatforms: [.iOS, .iPadOS, .macOS, .watchOS], hardwareRequirements: ["Secure Enclave"], osRequirements: ["iOS 11+ · macOS 10.14+ · watchOS 4+"], permissions: [], capabilities: [], entitlements: [],
            documentationURL: URL(string: "https://developer.apple.com/documentation/cryptokit/storing-keys-in-the-secure-enclave")!, evaluate: { DeviceCapabilities.current.secureEnclave ? .available : .hardwareUnsupported }),
        ExperimentDescriptor(id: "core-location", name: "Core Location", category: .location,
            description: "Request permission and inspect live coordinates, accuracy, altitude, speed, and course.",
            frameworks: ["CoreLocation"], supportedPlatforms: [.iOS, .iPadOS, .macOS, .watchOS], hardwareRequirements: ["Location hardware or a simulated location"], osRequirements: ["iOS 6+ · macOS 10.9+ · watchOS 2+"], permissions: ["Location When In Use"], capabilities: [], entitlements: [],
            documentationURL: URL(string: "https://developer.apple.com/documentation/corelocation")!, evaluate: { .permissionRequired }),
        ExperimentDescriptor(id: "core-motion", name: "Core Motion", category: .sensors,
            description: "Stream device motion with user acceleration, rotation rate, and gravity values.",
            frameworks: ["CoreMotion"], supportedPlatforms: [.iOS, .iPadOS, .watchOS], hardwareRequirements: ["Motion sensors"], osRequirements: ["iOS 7+ · watchOS 2+"], permissions: [], capabilities: [], entitlements: [],
            documentationURL: URL(string: "https://developer.apple.com/documentation/coremotion")!, evaluate: { DeviceCapabilities.current.motion ? .available : .hardwareUnsupported })
    ]

    static func descriptor(for id: String) -> ExperimentDescriptor? { all.first { $0.id == id } }
}
