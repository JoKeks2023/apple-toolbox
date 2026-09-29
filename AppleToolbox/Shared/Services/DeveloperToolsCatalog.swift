import Foundation

/// Apple developer tools (spec §33) and Apple diagnostic/business utilities (spec §34), with what the
/// Toolbox can reproduce through public APIs. Reference data only; it does not imply private API access.
struct DeveloperToolEntry: Identifiable {
    enum Kind: String, CaseIterable, Identifiable {
        case developerTool = "Developer tools"
        case appleUtility = "Apple utilities"
        var id: String { rawValue }
    }

    let id: String
    let name: String
    let kind: Kind
    let summary: String
    /// What the Toolbox offers instead, or why a third-party app cannot do the same.
    let inToolbox: String
    let relatedExperiments: [String]
    let documentation: URL?

    init(_ id: String, _ name: String, _ kind: Kind, summary: String, inToolbox: String, related: [String] = [], documentation: String? = nil) {
        self.id = id
        self.name = name
        self.kind = kind
        self.summary = summary
        self.inToolbox = inToolbox
        self.relatedExperiments = related
        self.documentation = documentation.flatMap(URL.init(string:))
    }
}

enum DeveloperToolsCatalog {
    static let all: [DeveloperToolEntry] = [
        DeveloperToolEntry("xcode", "Xcode", .developerTool,
            summary: "IDE, compilers, signing and capabilities, SDKs for every Apple platform.",
            inToolbox: "Capabilities an experiment needs are listed under Requirements and checked against the app's own provisioning profile in the Entitlement Explorer.",
            documentation: "https://developer.apple.com/xcode/"),
        DeveloperToolEntry("simulator", "Simulator", .developerTool,
            summary: "Runs apps for iPhone, iPad, Apple Watch, Apple TV and Vision Pro on the Mac, with simulated location, Face ID and push notifications.",
            inToolbox: "Experiments whose hardware the Simulator lacks report Device Only instead of pretending to work.",
            related: ["capability-explorer"],
            documentation: "https://developer.apple.com/documentation/xcode/running-your-app-in-simulator-or-on-a-device"),
        DeveloperToolEntry("devices", "Devices and Simulators", .developerTool,
            summary: "Pairs devices, installs builds, shows device logs, screenshots and provisioning profiles.",
            inToolbox: "The Device Scanner lists what the current device exposes through public APIs.",
            related: ["capability-explorer"],
            documentation: "https://developer.apple.com/documentation/xcode/devices-and-simulator"),
        DeveloperToolEntry("instruments", "Instruments", .developerTool,
            summary: "Profiles time, allocations, leaks, energy, network and custom signposts.",
            inToolbox: "The Diagnostics experiment emits os_signpost intervals that appear in Instruments' Points of Interest track.",
            related: ["diagnostics"],
            documentation: "https://help.apple.com/instruments/mac/current/"),
        DeveloperToolEntry("organizer", "Xcode Organizer", .developerTool,
            summary: "Crash, hang, energy and disk-write reports and metrics from TestFlight and App Store users.",
            inToolbox: "The Diagnostics experiment subscribes to MetricKit, the source of the same on-device metrics and diagnostics.",
            related: ["diagnostics"],
            documentation: "https://developer.apple.com/documentation/xcode/acquiring-crash-reports-and-diagnostic-logs"),
        DeveloperToolEntry("accessibility-inspector", "Accessibility Inspector", .developerTool,
            summary: "Inspects accessibility labels, traits and audits a running app.",
            inToolbox: "Not reproducible in-app; the Toolbox's rows carry accessibility identifiers used by its UI tests.",
            documentation: "https://developer.apple.com/documentation/accessibility/accessibility-inspector"),
        DeveloperToolEntry("create-ml", "Create ML", .developerTool,
            summary: "Trains image, sound, text, tabular and motion models on the Mac.",
            inToolbox: "The Core ML experiment imports, compiles and inspects models on the device.",
            related: ["core-ml"],
            documentation: "https://developer.apple.com/machine-learning/create-ml/"),
        DeveloperToolEntry("reality-composer-pro", "Reality Composer Pro", .developerTool,
            summary: "Builds RealityKit scenes, materials and particle effects.",
            inToolbox: "The ARKit experiment runs world tracking on the device.",
            related: ["arkit"],
            documentation: "https://developer.apple.com/augmented-reality/tools/"),
        DeveloperToolEntry("homekit-accessory-simulator", "HomeKit Accessory Simulator", .developerTool,
            summary: "Simulates HomeKit accessories, services and characteristics on the Mac (Additional Tools for Xcode).",
            inToolbox: "Add simulated accessories to a home, then inspect them with the HomeKit experiment.",
            related: ["homekit-discovery"],
            documentation: "https://developer.apple.com/documentation/homekit/testing-your-app-with-the-homekit-accessory-simulator"),
        DeveloperToolEntry("packetlogger", "PacketLogger", .developerTool,
            summary: "Captures Bluetooth HCI traffic from a Mac or a device with the Bluetooth logging profile.",
            inToolbox: "Third-party apps cannot capture Bluetooth packets; the Core Bluetooth experiment shows what an app sees at the GATT level.",
            related: ["core-bluetooth"],
            documentation: "https://developer.apple.com/bluetooth/"),
        DeveloperToolEntry("bluetooth-tools", "Bluetooth tools", .developerTool,
            summary: "Bluetooth Explorer and related tools from Additional Tools for Xcode for inspecting radios and devices.",
            inToolbox: "Core Bluetooth scanning covers advertising data and RSSI that apps may read.",
            related: ["core-bluetooth"],
            documentation: "https://developer.apple.com/bluetooth/"),
        DeveloperToolEntry("filemerge", "FileMerge", .developerTool,
            summary: "Visual diff and merge of files and folders, shipped with Xcode.",
            inToolbox: "No in-app counterpart.",
            documentation: "https://developer.apple.com/xcode/"),
        DeveloperToolEntry("console", "Console", .developerTool,
            summary: "Streams unified logs from the Mac and connected devices.",
            inToolbox: "The Diagnostics experiment reads this app's own unified log entries through OSLogStore; other processes' logs are not accessible.",
            related: ["diagnostics"],
            documentation: "https://support.apple.com/guide/console/welcome/mac"),
        DeveloperToolEntry("xcode-cloud", "Xcode Cloud", .developerTool,
            summary: "Continuous integration and delivery built into Xcode.",
            inToolbox: "Not used by this project; verification is local.",
            documentation: "https://developer.apple.com/xcode-cloud/"),
        DeveloperToolEntry("debugging", "Profiling & debugging workflows", .developerTool,
            summary: "Breakpoints, memory graph, view debugger, sanitizers and performance checks.",
            inToolbox: "The Diagnostics experiment measures a workload with signposts and shows thermal and memory state.",
            related: ["diagnostics"],
            documentation: "https://developer.apple.com/documentation/xcode/debugging"),
        DeveloperToolEntry("indoor-survey", "Indoor Survey", .appleUtility,
            summary: "Apple's app for surveying venues in the Indoor Maps Program, recording positions and radio fingerprints.",
            inToolbox: "The Indoor Maps experiment imports IMDF archives; Wi-Fi fingerprints are not available to third-party apps.",
            related: ["indoor-imdf"],
            documentation: "https://register.apple.com/indoor"),
        DeveloperToolEntry("airport-utility", "AirPort Utility", .appleUtility,
            summary: "Configures AirPort base stations; on iOS it can scan Wi-Fi networks when the Wi-Fi scanner is enabled.",
            inToolbox: "Apps cannot scan for Wi-Fi networks; the network experiments show the current path and interfaces.",
            related: ["network-path"],
            documentation: "https://support.apple.com/guide/aputility/welcome/mac"),
        DeveloperToolEntry("field-test-mode", "Field Test Mode", .appleUtility,
            summary: "Hidden iPhone menu with cellular radio details (signal, bands, cells).",
            inToolbox: "The Diagnostics experiment shows the public radio access technology per cellular service; signal and cell details are private."),
        DeveloperToolEntry("apple-configurator", "Apple Configurator", .appleUtility,
            summary: "Prepares, supervises and configures devices with profiles.",
            inToolbox: "The Entitlement Explorer reads the app's own embedded provisioning profile; device configuration profiles are not readable by apps.",
            documentation: "https://support.apple.com/guide/apple-configurator-mac/welcome/mac"),
        DeveloperToolEntry("apple-business-manager", "Apple Business Manager", .appleUtility,
            summary: "Device enrollment, MDM assignment and app distribution for organizations.",
            inToolbox: "The Diagnostics experiment shows a managed app configuration if an MDM delivered one.",
            related: ["diagnostics"],
            documentation: "https://support.apple.com/guide/apple-business-manager/welcome/web"),
        DeveloperToolEntry("apple-business-register", "Apple Business Register", .appleUtility,
            summary: "Registers organizations for Apple programs such as Indoor Maps.",
            inToolbox: "Indoor venue data it produces can be explored with the Indoor Maps experiment.",
            related: ["indoor-imdf"],
            documentation: "https://register.apple.com/"),
        DeveloperToolEntry("apple-business-connect", "Apple Business Connect", .appleUtility,
            summary: "Manages place cards, logos and actions shown in Maps and Wallet.",
            inToolbox: "The MapKit experiment searches the same public place data.",
            related: ["mapkit-search"],
            documentation: "https://businessconnect.apple.com/"),
    ]
}
