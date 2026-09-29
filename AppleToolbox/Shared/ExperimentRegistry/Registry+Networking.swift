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
        ExperimentDescriptor(id: "wifi-capabilities", name: "Wi-Fi & Network Capabilities", category: .networking,
            description: "Read the current Wi-Fi network, add a hotspot configuration, probe the local network permission, check the Multicast, Multipath and 5G slicing boundaries, and on iOS run a local packet tunnel (NEPacketTunnelProvider, test range only) and configure a Personal VPN (IKEv2) with real API calls.",
            frameworks: ["NetworkExtension", "Network", "CoreLocation", "CoreWLAN (macOS)"], supportedPlatforms: [.iOS, .iPadOS, .macOS],
            hardwareRequirements: ["A Wi-Fi connection for the current network"],
            osRequirements: ["NEHotspotNetwork.fetchCurrent: iOS 14+", "NEHotspotConfigurationManager: iOS 11+", "NETunnelProviderManager: iOS 9+ · NEVPNManager IKEv2: iOS 9+", "fetchLastDisconnectError: iOS 16+", "CoreWLAN: macOS 10.10+"],
            permissions: ["Location with Precise Location (SSID and BSSID)", "Local Network"],
            capabilities: ["Access Wi-Fi Information", "Hotspot", "Multicast Networking (managed)", "Personal VPN", "Network Extensions", "Multipath", "5G Network Slicing"],
            entitlements: ["com.apple.developer.networking.wifi-info", "com.apple.developer.networking.HotspotConfiguration", "com.apple.developer.networking.networkextension (packet-tunnel-provider, app and extension)", "com.apple.developer.networking.vpn.api (allow-vpn)"],
            documentationURL: URL(string: "https://developer.apple.com/documentation/networkextension/nehotspotnetwork")!, evaluate: ExperimentAvailability.wifiInformation,
            useCase: ExperimentUseCase(id: "wifi-boundaries", title: "See what an app may know about Wi-Fi",
                summary: "Compare what the system reveals to a third-party app with what needs an entitlement, location access or Apple's approval.",
                interaction: "Read the current network, allow precise location if asked, join a network you enter, then probe local network access and try each capability."),
            explanations: [
                .entitlementRequired: ExperimentExplanation(reason: "This build is not provisioned with Access Wi-Fi Information, so NEHotspotNetwork.fetchCurrent always returns nil.",
                    required: "com.apple.developer.networking.wifi-info on the App ID of a paid developer team, plus precise location",
                    nextStep: "Enable Access Wi-Fi Information in Signing & Capabilities and install a new build. The hotspot, local network and capability checks below still run."),
                .permissionRequired: ExperimentExplanation(reason: "The system reveals SSID and BSSID only to apps with precise location access (or for a network the app configured, or with an active VPN or DNS settings configuration).",
                    required: "Location While Using the App with Precise Location on",
                    nextStep: "Tap Request Location Access in the run section; if Precise Location is off, request it once."),
                .permissionDenied: ExperimentExplanation(reason: "Location access is denied or restricted, so SSID and BSSID stay hidden.",
                    required: "Location While Using the App with Precise Location on",
                    nextStep: "Allow location for Apple Toolbox in Settings › Privacy & Security › Location Services."),
                .platformUnsupported: ExperimentExplanation(reason: "tvOS has no public API for Wi-Fi details or hotspot configuration, and the watch app does not include this experiment.",
                    required: "iPhone, iPad or Mac", nextStep: "Open the experiment on iPhone, iPad or Mac."),
            ],
            applePrograms: ["Apple Developer Program: Access Wi-Fi Information and Hotspot are not available to free Personal Teams",
                            "Multicast Networking: granted by Apple on request (Multicast Networking Entitlement Request)"]),
    ]
}
