import Foundation

extension ExperimentRegistry {
    static let networking: [ExperimentDescriptor] = [
        // The identifier stays "network-path" so saved shortcuts and widget links keep working.
        ExperimentDescriptor(id: "network-path", name: "Network Inspector", category: .networking,
            description: "Inspect the live network path, open TCP, UDP or TLS connections with NWConnection, run an echo server with NWListener, and browse Bonjour services with NWBrowser.",
            frameworks: ["Network", "Security"], supportedPlatforms: [.iOS, .iPadOS, .macOS, .tvOS], hardwareRequirements: [],
            osRequirements: ["iOS 12+ · macOS 10.14+ · tvOS 12+", "Link quality and ultra-constrained paths: iOS 26+ · macOS 26+ · tvOS 26+"],
            permissions: ["Local Network (listener, Bonjour browsing, connections to local addresses)"],
            capabilities: ["Bonjour service types declared in NSBonjourServices"], entitlements: [],
            documentationURL: URL(string: "https://developer.apple.com/documentation/network")!, evaluate: { .available },
            useCase: ExperimentUseCase(id: "network-inspector", title: "Debug a connection end to end",
                summary: "See which interface carries traffic, whether TLS negotiates, what a server answers, and which Bonjour services the local network offers.",
                interaction: "Start the path monitor, connect to a host over TCP, UDP or TLS and send text; start the echo listener on one device and connect to it from another device's browser."),
            explanations: [
                .platformUnsupported: ExperimentExplanation(reason: "watchOS restricts low-level networking (NWConnection, NWListener, NWBrowser) to audio streaming apps with an active audio session (TN3135), so the inspector cannot run there.",
                    required: "iPhone, iPad, Mac or Apple TV",
                    nextStep: "Open the Network Inspector on one of those devices."),
            ]),
    ]
}
