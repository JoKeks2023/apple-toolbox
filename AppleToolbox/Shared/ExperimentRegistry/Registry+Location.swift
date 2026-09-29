import Foundation

extension ExperimentRegistry {
    static let location: [ExperimentDescriptor] = [
        ExperimentDescriptor(id: "core-location", name: "Core Location", category: .location,
            description: "Inspect live coordinates, precise vs. approximate accuracy, heading and floor, and monitor a region, visits, and significant changes around you.",
            frameworks: ["CoreLocation"], supportedPlatforms: [.iOS, .iPadOS, .macOS, .watchOS], hardwareRequirements: ["Location hardware or a simulated location", "Magnetometer for heading"], osRequirements: ["iOS 6+ · macOS 10.9+ · watchOS 2+", "CLMonitor: iOS 17+ · macOS 14+"], permissions: ["Location When In Use", "Temporary precise location (purpose key)", "Location Always (optional upgrade for visits and significant changes)"], capabilities: [], entitlements: [],
            documentationURL: URL(string: "https://developer.apple.com/documentation/corelocation")!, evaluate: ExperimentAvailability.location,
            useCase: ExperimentUseCase(id: "location-dashboard", title: "Build a live location dashboard", summary: "Use the device's real location stream, heading, and a geofence around you.", interaction: "Grant permission and start updates, then monitor a region around you and walk in or out to see entry and exit events. Upgrade to Always only if you want visits and significant changes."),
            explanations: [
                .permissionRequired: ExperimentExplanation(reason: "The app has not asked for location access yet.", required: "Location When In Use (Always only for visits and significant changes)",
                    nextStep: "Tap Request Location Permission; the Always upgrade is offered separately."),
                .permissionDenied: ExperimentExplanation(reason: "Location access is denied, restricted by Screen Time or MDM, or Location Services are off.", required: "Location Services on and Apple Toolbox allowed While Using the App",
                    nextStep: "Turn on Settings › Privacy & Security › Location Services and allow Apple Toolbox."),
            ]),
        ExperimentDescriptor(id: "ibeacon-ranging", name: "iBeacon Ranging", category: .location,
            description: "Range iBeacons for a proximity UUID you enter, optionally narrowed by major and minor, with CLBeaconIdentityConstraint, and watch proximity, estimated distance and RSSI update live.",
            frameworks: ["CoreLocation"], supportedPlatforms: [.iOS, .iPadOS, .macOS], hardwareRequirements: ["Bluetooth LE", "An iBeacon transmitter nearby (hardware beacon or another device advertising)"], osRequirements: ["iOS 13+ · macOS 10.15+"], permissions: ["Location When In Use (Always on macOS)"], capabilities: [], entitlements: [],
            documentationURL: URL(string: "https://developer.apple.com/documentation/corelocation/ranging-for-beacons")!, evaluate: ExperimentAvailability.beaconRanging,
            useCase: ExperimentUseCase(id: "beacon-finder", title: "Find the beacons around you", summary: "Check which beacons of a known UUID are in range and how close each one is.", interaction: "Pick a vendor preset or type the UUID your beacons advertise, optionally add a major and minor, start ranging and walk toward a beacon to see its proximity change from Far to Immediate."),
            explanations: [
                .hardwareUnsupported: ExperimentExplanation(reason: "CLLocationManager.isRangingAvailable() returns false: this device cannot range iBeacons.", required: "A device with Bluetooth LE that supports beacon ranging",
                    nextStep: "Run the experiment on an iPhone or iPad; most Macs do not range beacons."),
                .permissionRequired: ExperimentExplanation(reason: "Beacon ranging is a location service and the app has not asked for location access yet.", required: "Location When In Use",
                    nextStep: "Tap Start Ranging; the system asks for location access first."),
                .permissionDenied: ExperimentExplanation(reason: "Location access is denied or restricted, so Core Location reports no beacons.", required: "Location Services on and Apple Toolbox allowed",
                    nextStep: "Allow Apple Toolbox in Settings › Privacy & Security › Location Services."),
            ]),
        ExperimentDescriptor(id: "location-dashboard", name: "Location Dashboard", category: .location,
            description: "Record a track from CLLocationUpdate.liveUpdates, draw it on a map, chart speed, altitude and accuracy over time, summarize the session and export the track as GPX or GeoJSON.",
            frameworks: ["CoreLocation", "MapKit", "Charts"], supportedPlatforms: [.iOS, .iPadOS, .macOS], hardwareRequirements: ["GPS/GNSS for outdoor tracks (Wi-Fi positioning otherwise)"], osRequirements: ["iOS 17+ · macOS 14+ (CLLocationUpdate)"], permissions: ["Location When In Use", "Temporary precise location (purpose key)"], capabilities: [], entitlements: [],
            documentationURL: URL(string: "https://developer.apple.com/documentation/corelocation/cllocationupdate")!, evaluate: ExperimentAvailability.location,
            useCase: ExperimentUseCase(id: "track-recorder", title: "Record and analyze a walk", summary: "Turn live location updates into a track with charts, statistics and a GPX file for other apps.", interaction: "Choose an update profile, start recording and walk outside for a few minutes, then compare the speed, altitude and accuracy charts, check the statistics and share the track as GPX or GeoJSON."),
            explanations: [
                .permissionRequired: ExperimentExplanation(reason: "The app has not asked for location access yet.", required: "Location When In Use",
                    nextStep: "Tap Start Recording; the system asks for location access first."),
                .permissionDenied: ExperimentExplanation(reason: "Location access is denied or restricted, so no fixes arrive.", required: "Location Services on and Apple Toolbox allowed While Using the App",
                    nextStep: "Allow Apple Toolbox in Settings › Privacy & Security › Location Services."),
            ]),
    ]
}
