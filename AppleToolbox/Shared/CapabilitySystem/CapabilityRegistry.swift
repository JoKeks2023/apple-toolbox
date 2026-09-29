import Foundation

/// The kind of gate Apple puts in front of a capability (spec §35).
enum CapabilityKind: String, CaseIterable, Identifiable {
    case developerCapability = "Developer Capability"
    case managedCapability = "Managed Capability"
    case specialEntitlement = "Special Entitlement"
    case appleProgram = "Apple Program"
    case hardwareDependent = "Hardware Dependent"

    var id: String { rawValue }
    var symbolName: String {
        switch self {
        case .developerCapability: "hammer"
        case .managedCapability: "person.badge.key"
        case .specialEntitlement: "seal"
        case .appleProgram: "building.columns"
        case .hardwareDependent: "cpu"
        }
    }
    var summary: String {
        switch self {
        case .developerCapability: "Added directly in Xcode under Signing & Capabilities."
        case .managedCapability: "Apple must approve a request first; the approved capability is then enabled on the App ID."
        case .specialEntitlement: "Granted by Apple only for specific use cases, agreements or regions."
        case .appleProgram: "Requires participation in a separate Apple program or partner agreement."
        case .hardwareDependent: "Can be enabled in Xcode, but only works on devices or accessories with the required hardware."
        }
    }
}

enum CapabilityAccess: Equatable {
    /// Can be added in Xcode (Signing & Capabilities) without asking Apple.
    case xcode
    /// Needs a request to Apple and its approval before it can be provisioned.
    case appleApproval

    var title: String {
        switch self {
        case .xcode: "Enable in Xcode"
        case .appleApproval: "Apple approval"
        }
    }
}

/// Where the capability's key lives, which decides how its state can be inspected.
enum CapabilityKeySource: Equatable {
    /// Entitlement that appears in the provisioning profile once enabled on the App ID.
    case provisioningProfile
    /// Entitlement that provisioning profiles do not list; only the code signature carries it.
    case codeSignature
    /// Info.plist key, not an entitlement.
    case infoPlist
    /// App ID setting without any entitlement key.
    case appIDOnly
}

struct CapabilityDescriptor: Identifiable {
    let id: String
    let name: String
    /// Entitlement (or Info.plist) keys; the capability is present when any of them is.
    let keys: [String]
    let keySource: CapabilityKeySource
    let kind: CapabilityKind
    let access: CapabilityAccess
    let platforms: [SupportedPlatform]
    let framework: String
    /// Whether a free Personal Team can use it (per Xcode's capability catalog); otherwise Apple Developer Program membership is required.
    let personalTeam: Bool
    let region: String?
    let hardware: String?
    let experimentID: String?
    /// What it takes to get the capability working; shown as the next step when it is missing.
    let requirement: String
    let documentationURL: URL

    init(id: String, name: String, keys: [String], source: CapabilityKeySource = .provisioningProfile, kind: CapabilityKind,
         access: CapabilityAccess = .xcode, platforms: [SupportedPlatform], framework: String, personalTeam: Bool = false,
         region: String? = nil, hardware: String? = nil, experiment: String? = nil, requirement: String, documentation: String) {
        self.id = id
        self.name = name
        self.keys = keys
        self.keySource = source
        self.kind = kind
        self.access = access
        self.platforms = platforms
        self.framework = framework
        self.personalTeam = personalTeam
        self.region = region
        self.hardware = hardware
        self.experimentID = experiment
        self.requirement = requirement
        self.documentationURL = URL(string: "https://developer.apple.com/documentation/" + documentation)!
    }

    var isSupportedOnCurrentPlatform: Bool { platforms.contains(CurrentPlatform.value) }
    var relatedExperiment: ExperimentDescriptor? { experimentID.flatMap(ExperimentRegistry.descriptor(for:)) }
}

/// Central catalog of Apple capabilities. Keys and platforms follow Apple's entitlement documentation and
/// Xcode's capability catalog; this is reference data, the runtime state comes from the app's own signature.
enum CapabilityRegistry {
    private static let phone: [SupportedPlatform] = [.iOS]
    private static let mobile: [SupportedPlatform] = [.iOS, .iPadOS]
    private static let every = SupportedPlatform.allCases
    private static func entitlement(_ key: String) -> String { "bundleresources/entitlements/" + key.lowercased() }

    static let all: [CapabilityDescriptor] = [
        CapabilityDescriptor(id: "access-wifi-information", name: "Access Wi-Fi Information", keys: ["com.apple.developer.networking.wifi-info"], kind: .developerCapability, platforms: mobile + [.watchOS], framework: "NetworkExtension",
            requirement: "Enable Access Wi-Fi Information. Reading the current network also needs precise location authorization, a network the app configured itself, or an active VPN or DNS settings configuration.", documentation: entitlement("com.apple.developer.networking.wifi-info")),
        CapabilityDescriptor(id: "app-attest", name: "App Attest", keys: ["com.apple.developer.devicecheck.appattest-environment"], kind: .developerCapability, platforms: every, framework: "DeviceCheck", experiment: "app-attest",
            requirement: "Optional entitlement: without it development builds use the App Attest sandbox and TestFlight/App Store builds use production; set it to override the environment. Your server must issue challenges and verify attestations.", documentation: "devicecheck/establishing-your-app-s-integrity"),
        CapabilityDescriptor(id: "app-groups", name: "App Groups", keys: ["com.apple.security.application-groups"], kind: .developerCapability, platforms: every, framework: "Foundation", personalTeam: true, experiment: "widgetkit",
            requirement: "Enable App Groups and register a group identifier to share containers and defaults between the app and its extensions.", documentation: "xcode/configuring-app-groups"),
        CapabilityDescriptor(id: "apple-pay", name: "Apple Pay", keys: ["com.apple.developer.in-app-payments"], kind: .developerCapability, platforms: mobile + [.macOS, .watchOS], framework: "PassKit", experiment: "apple-pay",
            requirement: "Register a Merchant ID, create its payment processing certificate, and enable Apple Pay with that Merchant ID.", documentation: "xcode/configuring-apple-pay-support"),
        CapabilityDescriptor(id: "associated-domains", name: "Associated Domains", keys: ["com.apple.developer.associated-domains"], kind: .developerCapability, platforms: every, framework: "Universal Links · AuthenticationServices", experiment: "passkeys",
            requirement: "Enable Associated Domains, list the domains, and host an apple-app-site-association file on each of them.", documentation: "xcode/supporting-associated-domains"),
        CapabilityDescriptor(id: "autofill-credential-provider", name: "AutoFill Credential Provider", keys: ["com.apple.developer.authentication-services.autofill-credential-provider"], kind: .developerCapability, platforms: mobile + [.macOS], framework: "AuthenticationServices", personalTeam: true, experiment: "credential-provider",
            requirement: "Add a credential provider extension with this capability. People then turn the provider on in Settings.", documentation: entitlement("com.apple.developer.authentication-services.autofill-credential-provider")),
        CapabilityDescriptor(id: "background-modes", name: "Background Modes", keys: ["UIBackgroundModes"], source: .infoPlist, kind: .developerCapability, platforms: mobile + [.watchOS], framework: "UIKit · BackgroundTasks", personalTeam: true,
            requirement: "Enable Background Modes and select only the modes the app really uses; App Review checks each declared mode.", documentation: "bundleresources/information-property-list/uibackgroundmodes"),
        CapabilityDescriptor(id: "classkit", name: "ClassKit", keys: ["com.apple.developer.ClassKit-environment"], kind: .developerCapability, platforms: mobile + [.macOS], framework: "ClassKit",
            requirement: "Enable ClassKit and choose the environment. Progress data only reaches teachers through the Schoolwork app.", documentation: "classkit"),
        CapabilityDescriptor(id: "communication-notifications", name: "Communication Notifications", keys: ["com.apple.developer.usernotifications.communication"], kind: .developerCapability, platforms: mobile + [.macOS, .watchOS], framework: "UserNotifications · Intents", experiment: "notifications",
            requirement: "Enable Communication Notifications, donate message or call intents, and update the notification content with them.", documentation: "usernotifications/implementing-communication-notifications"),
        CapabilityDescriptor(id: "data-protection", name: "Data Protection", keys: ["com.apple.developer.default-data-protection"], source: .codeSignature, kind: .developerCapability, platforms: mobile + [.tvOS, .watchOS], framework: "Foundation", personalTeam: true, experiment: "keychain",
            requirement: "Enable Data Protection to set the default file protection class; individual files can still choose their own class.", documentation: entitlement("com.apple.developer.default-data-protection")),
        CapabilityDescriptor(id: "healthkit", name: "HealthKit", keys: ["com.apple.developer.healthkit"], kind: .developerCapability, platforms: mobile + [.watchOS], framework: "HealthKit", personalTeam: true, experiment: "healthkit-status",
            requirement: "Enable HealthKit, add the Health usage descriptions, and request read/write authorization per data type at runtime.", documentation: "healthkit"),
        CapabilityDescriptor(id: "homekit", name: "HomeKit", keys: ["com.apple.developer.homekit"], kind: .developerCapability, platforms: mobile + [.tvOS, .watchOS], framework: "HomeKit", personalTeam: true, experiment: "homekit-discovery",
            requirement: "Enable HomeKit and add NSHomeKitUsageDescription. People grant access to their home data on first use.", documentation: "homekit/enabling-homekit-in-your-app"),
        CapabilityDescriptor(id: "hotspot", name: "Hotspot", keys: ["com.apple.developer.networking.HotspotConfiguration"], kind: .developerCapability, platforms: mobile + [.watchOS], framework: "NetworkExtension",
            requirement: "Enable Hotspot to join or configure Wi-Fi networks with NEHotspotConfigurationManager. People confirm each network the app adds.", documentation: entitlement("com.apple.developer.networking.HotspotConfiguration")),
        CapabilityDescriptor(id: "icloud", name: "iCloud", keys: ["com.apple.developer.icloud-services", "com.apple.developer.icloud-container-identifiers", "com.apple.developer.ubiquity-kvstore-identifier"], kind: .developerCapability, platforms: every, framework: "CloudKit · Foundation",
            requirement: "Enable iCloud, pick CloudKit, iCloud Documents or key-value storage, and assign containers. People must be signed in to iCloud.", documentation: "xcode/configuring-icloud-services"),
        CapabilityDescriptor(id: "keychain-sharing", name: "Keychain Sharing", keys: ["keychain-access-groups"], kind: .developerCapability, platforms: every, framework: "Security", personalTeam: true, experiment: "keychain-sharing",
            requirement: "Enable Keychain Sharing and list the access groups to share keychain items between apps of the same team. Profiles always allow the team wildcard (TEAMID.*); the app's entitlements name the concrete groups.", documentation: entitlement("keychain-access-groups")),
        CapabilityDescriptor(id: "maps", name: "Maps (Routing App)", keys: ["MKDirectionsApplicationSupportedModes"], source: .infoPlist, kind: .developerCapability, platforms: mobile, framework: "MapKit", personalTeam: true, experiment: "mapkit-search",
            requirement: "Only routing apps need this: enable Maps and choose the transport modes. Showing maps or searching places with MapKit needs no capability.", documentation: "xcode/configuring-maps-support"),
        CapabilityDescriptor(id: "matter-allow-setup-payload", name: "Matter Allow Setup Payload", keys: ["com.apple.developer.matter.allow-setup-payload"], kind: .developerCapability, platforms: every, framework: "MatterSupport", experiment: "matter-status",
            requirement: "Enable Matter Allow Setup Payload to hand an onboarding payload to the Matter setup flow. Commissioning still needs a real Matter accessory.", documentation: entitlement("com.apple.developer.matter.allow-setup-payload")),
        CapabilityDescriptor(id: "multicast-networking", name: "Multicast Networking", keys: ["com.apple.developer.networking.multicast"], kind: .managedCapability, access: .appleApproval, platforms: mobile, framework: "Network",
            requirement: "Request the entitlement on the Multicast Networking Entitlement Request page, then enable it on the App ID. Local Network permission is still required.", documentation: entitlement("com.apple.developer.networking.multicast")),
        CapabilityDescriptor(id: "multipath", name: "Multipath", keys: ["com.apple.developer.networking.multipath"], kind: .developerCapability, platforms: mobile, framework: "Network · Foundation",
            requirement: "Enable Multipath and opt in per connection with a multipath service type. The server must support Multipath TCP.", documentation: entitlement("com.apple.developer.networking.multipath")),
        CapabilityDescriptor(id: "nfc-tag-reading", name: "Near Field Communication Tag Reading", keys: ["com.apple.developer.nfc.readersession.formats"], kind: .hardwareDependent, platforms: mobile, framework: "CoreNFC",
            hardware: "iPhone 7 or later; iPad models cannot read NFC tags.", experiment: "core-nfc",
            requirement: "Enable NFC Tag Reading, add NFCReaderUsageDescription, and check NFCReaderSession.readingAvailable before starting a session.", documentation: entitlement("com.apple.developer.nfc.readersession.formats")),
        CapabilityDescriptor(id: "network-extensions", name: "Network Extensions", keys: ["com.apple.developer.networking.networkextension"], kind: .developerCapability, platforms: mobile + [.macOS, .tvOS], framework: "NetworkExtension",
            requirement: "Enable Network Extensions, choose the provider types, and add the matching extension targets.", documentation: "networkextension"),
        CapabilityDescriptor(id: "personal-vpn", name: "Personal VPN", keys: ["com.apple.developer.networking.vpn.api"], kind: .developerCapability, platforms: mobile + [.macOS], framework: "NetworkExtension",
            requirement: "Enable Personal VPN to configure the built-in IKEv2/IPsec client with NEVPNManager. People approve the configuration.", documentation: entitlement("com.apple.developer.networking.vpn.api")),
        CapabilityDescriptor(id: "push-notifications", name: "Push Notifications", keys: ["aps-environment", "com.apple.developer.aps-environment"], kind: .developerCapability, platforms: every, framework: "UserNotifications", experiment: "notifications",
            requirement: "Enable Push Notifications, register for remote notifications, and send through APNs from a server using the matching environment.", documentation: "usernotifications/registering-your-app-with-apns"),
        CapabilityDescriptor(id: "sign-in-with-apple", name: "Sign in with Apple", keys: ["com.apple.developer.applesignin"], kind: .developerCapability, platforms: every, framework: "AuthenticationServices", experiment: "sign-in-with-apple",
            requirement: "Enable Sign in with Apple and verify the identity token on your server.", documentation: "xcode/configuring-sign-in-with-apple"),
        CapabilityDescriptor(id: "siri", name: "Siri", keys: ["com.apple.developer.siri"], kind: .developerCapability, platforms: mobile + [.tvOS, .watchOS], framework: "Intents (SiriKit)", experiment: "app-intents",
            requirement: "Only needed for SiriKit intents: enable Siri and add NSSiriUsageDescription. App Intents and App Shortcuts work without it.", documentation: "sirikit"),
        CapabilityDescriptor(id: "time-sensitive-notifications", name: "Time Sensitive Notifications", keys: ["com.apple.developer.usernotifications.time-sensitive"], kind: .developerCapability, platforms: mobile + [.macOS, .watchOS], framework: "UserNotifications", experiment: "notifications",
            requirement: "Enable Time Sensitive Notifications and use the time-sensitive interruption level only for urgent content. People can turn it off per app.", documentation: "usernotifications/unnotificationinterruptionlevel/timesensitive"),
        CapabilityDescriptor(id: "wallet", name: "Wallet", keys: ["com.apple.developer.pass-type-identifiers"], kind: .developerCapability, platforms: mobile + [.watchOS], framework: "PassKit", experiment: "wallet-status",
            requirement: "Register Pass Type IDs and enable Wallet to access your own passes. Issuing signed passes needs a Pass Type ID certificate.", documentation: "xcode/configuring-wallet-support"),
        CapabilityDescriptor(id: "weatherkit", name: "WeatherKit", keys: ["com.apple.developer.weatherkit"], kind: .developerCapability, platforms: every, framework: "WeatherKit",
            requirement: "Enable WeatherKit both as capability and as app service on the App ID, and show Apple Weather attribution.", documentation: "weatherkit"),
        CapabilityDescriptor(id: "wireless-accessory-configuration", name: "Wireless Accessory Configuration", keys: ["com.apple.external-accessory.wireless-configuration"], kind: .hardwareDependent, platforms: mobile, framework: "ExternalAccessory", personalTeam: true,
            hardware: "An MFi-certified Wi-Fi accessory that supports Wireless Accessory Configuration.",
            requirement: "Enable Wireless Accessory Configuration and present the accessory setup flow for a nearby unconfigured accessory.", documentation: entitlement("com.apple.external-accessory.wireless-configuration")),

        CapabilityDescriptor(id: "game-center", name: "Game Center", keys: ["com.apple.developer.game-center"], kind: .developerCapability, platforms: every, framework: "GameKit", personalTeam: true,
            requirement: "Enable Game Center and configure leaderboards or achievements in App Store Connect. The player must be signed in to Game Center.", documentation: "gamekit"),
        CapabilityDescriptor(id: "in-app-purchase", name: "In-App Purchase", keys: [], source: .appIDOnly, kind: .developerCapability, platforms: every, framework: "StoreKit",
            requirement: "No entitlement key: In-App Purchase is an App ID setting. Configure products in App Store Connect and accept the Paid Apps agreement.", documentation: "storekit/in-app-purchase"),
        CapabilityDescriptor(id: "group-activities", name: "Group Activities (SharePlay)", keys: ["com.apple.developer.group-session"], kind: .developerCapability, platforms: mobile + [.macOS, .tvOS], framework: "GroupActivities",
            requirement: "Enable Group Activities to start shared SharePlay sessions over FaceTime or Messages.", documentation: "xcode/configuring-group-activities"),
        CapabilityDescriptor(id: "push-to-talk", name: "Push to Talk", keys: ["com.apple.developer.push-to-talk"], kind: .developerCapability, platforms: mobile, framework: "PushToTalk",
            requirement: "Enable Push to Talk plus the push-to-talk background mode; audio transport is provided by your own service.", documentation: "pushtotalk"),
        CapabilityDescriptor(id: "location-push", name: "Location Push Service Extension", keys: ["com.apple.developer.location.push"], kind: .developerCapability, platforms: mobile, framework: "CoreLocation", experiment: "core-location",
            requirement: "Enable the capability on a location push service extension. The app needs Always location authorization before the extension receives location pushes.", documentation: entitlement("com.apple.developer.location.push")),
        CapabilityDescriptor(id: "extended-virtual-addressing", name: "Extended Virtual Addressing", keys: ["com.apple.developer.kernel.extended-virtual-addressing"], kind: .developerCapability, platforms: mobile + [.tvOS], framework: "Kernel memory",
            requirement: "Enable Extended Virtual Addressing when the app needs a larger address space; physical memory limits still apply.", documentation: entitlement("com.apple.developer.kernel.extended-virtual-addressing")),
        CapabilityDescriptor(id: "declared-age-range", name: "Declared Age Range", keys: ["com.apple.developer.declared-age-range"], kind: .developerCapability, platforms: mobile + [.macOS], framework: "DeclaredAgeRange",
            requirement: "Enable Declared Age Range and request the age range at runtime; the person or a parent decides whether to share it.", documentation: entitlement("com.apple.developer.declared-age-range")),
        CapabilityDescriptor(id: "sensitive-content-analysis", name: "Sensitive Content Analysis", keys: ["com.apple.developer.sensitivecontentanalysis.client"], kind: .developerCapability, platforms: mobile + [.macOS], framework: "SensitiveContentAnalysis",
            requirement: "Enable the capability. Analysis only runs when Sensitive Content Warning or Communication Safety is turned on for the person.", documentation: "sensitivecontentanalysis"),
        CapabilityDescriptor(id: "journaling-suggestions", name: "Journaling Suggestions", keys: ["com.apple.developer.journal.allow"], kind: .developerCapability, platforms: phone, framework: "JournalingSuggestions",
            requirement: "Enable Journaling Suggestions to present the system picker; the app only receives suggestions the person selects.", documentation: "journalingsuggestions"),

        CapabilityDescriptor(id: "increased-memory-limit", name: "Increased Memory Limit", keys: ["com.apple.developer.kernel.increased-memory-limit"], kind: .hardwareDependent, platforms: mobile, framework: "Kernel memory", personalTeam: true,
            hardware: "Only some device models grant a higher limit.",
            requirement: "Enable Increased Memory Limit, check os_proc_available_memory() at runtime, and keep working when no extra memory is granted.", documentation: entitlement("com.apple.developer.kernel.increased-memory-limit")),
        CapabilityDescriptor(id: "5g-network-slicing", name: "5G Network Slicing", keys: ["com.apple.developer.networking.slicing.appcategory", "com.apple.developer.networking.slicing.trafficcategory"], kind: .hardwareDependent, platforms: mobile, framework: "Network",
            hardware: "5G cellular connection on a carrier that offers network slicing.",
            requirement: "Set both the app category and traffic category entitlements. Slicing only takes effect on supported carriers.", documentation: entitlement("com.apple.developer.networking.slicing.appcategory")),
        CapabilityDescriptor(id: "wifi-aware", name: "Wi-Fi Aware", keys: ["com.apple.developer.wifi-aware"], kind: .hardwareDependent, platforms: mobile, framework: "WiFiAware",
            hardware: "A device whose Wi-Fi hardware supports Wi-Fi Aware.",
            requirement: "Enable Wi-Fi Aware with the Publish and/or Subscribe role and check device support at runtime before pairing.", documentation: entitlement("com.apple.developer.wifi-aware")),

        CapabilityDescriptor(id: "family-controls", name: "Family Controls", keys: ["com.apple.developer.family-controls"], kind: .managedCapability, access: .appleApproval, platforms: mobile, framework: "FamilyControls",
            requirement: "Development builds can enable Family Controls directly; TestFlight and App Store distribution need Apple's approval of the distribution request.", documentation: "familycontrols"),
        CapabilityDescriptor(id: "critical-alerts", name: "Critical Alerts", keys: ["com.apple.developer.usernotifications.critical-alerts"], kind: .managedCapability, access: .appleApproval, platforms: every, framework: "UserNotifications", experiment: "notifications",
            requirement: "Request the entitlement from Apple with a justified use case. People must still allow critical alerts separately.", documentation: entitlement("com.apple.developer.usernotifications.critical-alerts")),
        CapabilityDescriptor(id: "hotspot-helper", name: "Hotspot Helper", keys: ["com.apple.developer.networking.HotspotHelper"], kind: .managedCapability, access: .appleApproval, platforms: mobile, framework: "NetworkExtension",
            requirement: "Request the Hotspot Helper entitlement from Apple; after approval enable it as an additional capability on the App ID.", documentation: entitlement("com.apple.developer.networking.HotspotHelper")),
        CapabilityDescriptor(id: "fall-detection", name: "Fall Detection Notifications", keys: ["com.apple.developer.health.fall-detection"], kind: .managedCapability, access: .appleApproval, platforms: mobile + [.watchOS], framework: "CoreMotion",
            hardware: "Apple Watch with fall detection turned on.",
            requirement: "Request the entitlement from Apple, then receive events through CMFallDetectionManager after the person authorizes it.", documentation: entitlement("com.apple.developer.health.fall-detection")),
        CapabilityDescriptor(id: "default-web-browser", name: "Default Web Browser", keys: ["com.apple.developer.web-browser"], kind: .managedCapability, access: .appleApproval, platforms: mobile, framework: "WebKit",
            requirement: "Request the entitlement from Apple; the browser must meet Apple's requirements for default browser apps.", documentation: entitlement("com.apple.developer.web-browser")),
        CapabilityDescriptor(id: "financekit", name: "FinanceKit", keys: ["com.apple.developer.financekit"], kind: .managedCapability, access: .appleApproval, platforms: phone, framework: "FinanceKit",
            requirement: "Request the entitlement with Apple's request form; the person must consent before the app can read financial data.", documentation: entitlement("com.apple.developer.financekit")),

        CapabilityDescriptor(id: "nfc-hce", name: "NFC Host Card Emulation", keys: ["com.apple.developer.nfc.hce"], kind: .specialEntitlement, access: .appleApproval, platforms: phone, framework: "CoreNFC",
            region: "European Economic Area", hardware: "NFC-capable iPhone.", experiment: "nfc-card-emulation",
            requirement: "Apply to Apple for the HCE entitlement and list the supported application identifier prefixes. Check CardSession.isSupported and isEligible at runtime.", documentation: entitlement("com.apple.developer.nfc.hce")),
        CapabilityDescriptor(id: "sensorkit", name: "SensorKit", keys: ["com.apple.developer.sensorkit.reader.allow"], kind: .specialEntitlement, access: .appleApproval, platforms: mobile + [.watchOS], framework: "SensorKit",
            requirement: "Only for research: Apple must approve the research study before it grants reader access to sensor data.", documentation: entitlement("com.apple.developer.sensorkit.reader.allow")),
        CapabilityDescriptor(id: "alternative-app-marketplace", name: "Alternative App Marketplace", keys: ["com.apple.developer.marketplace.app-installation"], kind: .specialEntitlement, access: .appleApproval, platforms: mobile, framework: "MarketplaceKit",
            region: "Only where Apple offers alternative app distribution, such as the European Union",
            requirement: "Apple approves the entitlement against its marketplace criteria. Not available for Enterprise or Developer ID distribution.", documentation: entitlement("com.apple.developer.marketplace.app-installation")),
        CapabilityDescriptor(id: "web-browser-engine", name: "Web Browser Engine", keys: ["com.apple.developer.web-browser-engine.host"], kind: .specialEntitlement, access: .appleApproval, platforms: mobile, framework: "BrowserEngineKit",
            region: "Supported regions only; the request process differs per region",
            requirement: "Request the entitlement from Apple and split the engine into rendering, networking and web content extensions.", documentation: entitlement("com.apple.developer.web-browser-engine.host")),

        CapabilityDescriptor(id: "secure-element-credential", name: "Secure Element Credential", keys: ["com.apple.developer.secure-element-credential"], kind: .appleProgram, access: .appleApproval, platforms: phone, framework: "SecureElementCredential",
            region: "Countries and regions supported by the NFC & SE Platform", hardware: "iPhone with Secure Element and NFC.",
            requirement: "Request access to the NFC & SE Platform and register the applet with Apple Business Register. Covers corporate badges, student IDs, car, home and hotel keys, transit and payments.", documentation: "secureelementcredential"),
        CapabilityDescriptor(id: "tap-to-pay", name: "Tap to Pay on iPhone", keys: ["com.apple.developer.proximity-reader.payment.acceptance"], kind: .appleProgram, access: .appleApproval, platforms: phone, framework: "ProximityReader",
            region: "Supported countries and regions only", hardware: "Supported iPhone model.",
            requirement: "The Account Holder of an organization account requests the entitlement and integrates a supported payment service provider. Distribution needs a separate distribution entitlement.", documentation: "proximityreader/setting-up-the-entitlement-for-tap-to-pay-on-iphone"),
        CapabilityDescriptor(id: "carplay", name: "CarPlay", keys: ["com.apple.developer.carplay-audio", "com.apple.developer.carplay-communication", "com.apple.developer.carplay-charging", "com.apple.developer.carplay-fueling", "com.apple.developer.carplay-maps", "com.apple.developer.carplay-messaging", "com.apple.developer.carplay-parking", "com.apple.developer.carplay-quick-ordering", "com.apple.developer.carplay-driving-task", "com.apple.developer.carplay-voice-based-conversation"], kind: .appleProgram, access: .appleApproval, platforms: phone, framework: "CarPlay",
            requirement: "Request the CarPlay entitlement for one supported app category and accept the CarPlay Entitlement Addendum.", documentation: "carplay")
    ]

    static func descriptor(for id: String) -> CapabilityDescriptor? { all.first { $0.id == id } }
    static func capabilities(of kind: CapabilityKind) -> [CapabilityDescriptor] { all.filter { $0.kind == kind } }
}
