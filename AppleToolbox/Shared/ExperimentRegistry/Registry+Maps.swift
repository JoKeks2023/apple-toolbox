import Foundation

extension ExperimentRegistry {
    static let maps: [ExperimentDescriptor] = [
        ExperimentDescriptor(id: "mapkit-search", name: "MapKit Search", category: .maps,
            description: "Search real map data for places and inspect returned names and coordinates.", frameworks: ["MapKit"], supportedPlatforms: [.iOS, .iPadOS, .macOS, .tvOS], hardwareRequirements: [], osRequirements: ["iOS 6+ · macOS 10.9+ · tvOS 9+"], permissions: [], capabilities: ["Maps"], entitlements: [], documentationURL: URL(string: "https://developer.apple.com/documentation/mapkit")!, evaluate: { [.iOS, .iPadOS, .macOS, .tvOS].contains(CurrentPlatform.value) ? .available : .platformUnsupported }),
        ExperimentDescriptor(id: "indoor-imdf", name: "Indoor Maps / IMDF", category: .maps,
            description: "Import an unzipped IMDF archive folder or individual GeoJSON files, decode every feature type with MKGeoJSONDecoder, count features per type and level, and draw the selected level's units and openings on a map.", frameworks: ["MapKit", "Foundation"], supportedPlatforms: [.iOS, .iPadOS, .macOS], hardwareRequirements: [], osRequirements: ["iOS 17+ · macOS 14+"], permissions: ["User-selected file access"], capabilities: ["Indoor Mapping Data Format", "Security-scoped file access"], entitlements: [], documentationURL: URL(string: "https://developer.apple.com/documentation/mapkit/displaying-an-indoor-map")!, evaluate: { [.iOS, .iPadOS, .macOS].contains(CurrentPlatform.value) ? .available : .platformUnsupported },
            useCase: ExperimentUseCase(id: "imdf-explorer", title: "Explore an indoor map", summary: "Load a venue's IMDF archive and inspect its floors, rooms, doors and points of interest on a real map.", interaction: "Unzip the archive in Files, import the folder, pick a level, and compare the feature counts with the drawn units and openings."),
            explanations: [
                .platformUnsupported: ExperimentExplanation(reason: "IMDF archives are imported through the document picker, which Apple TV and Apple Watch do not offer to this app.", required: "iOS, iPadOS or macOS",
                    nextStep: "Open Apple Toolbox on iPhone, iPad or Mac and import the unzipped IMDF folder."),
            ]),
        ExperimentDescriptor(id: "indoor-survey", name: "Indoor Survey", category: .maps,
            description: "Survey an imported IMDF level: record reference points and walking paths with Core Location accuracy, floor, confidence and notes, compare reference and measured positions, view an accuracy heatmap, save surveys as JSON in the app's Documents folder (Application Support on Mac) and export them as GeoJSON.",
            frameworks: ["CoreLocation", "MapKit", "Foundation"], supportedPlatforms: [.iOS, .iPadOS, .macOS], hardwareRequirements: ["GPS, Wi-Fi and Bluetooth positioning", "Floors only in venues with Apple indoor positioning"], osRequirements: ["iOS 17+ · macOS 14+"], permissions: ["Location When In Use", "Temporary precise location (purpose key)", "User-selected file access (IMDF import)"], capabilities: ["Indoor Mapping Data Format", "Local JSON storage"], entitlements: [],
            documentationURL: URL(string: "https://developer.apple.com/documentation/corelocation/clfloor")!, evaluate: ExperimentAvailability.location,
            useCase: ExperimentUseCase(id: "indoor-survey-utility", title: "Survey positioning quality in a building", summary: "Measure how well Core Location performs on each floor of a venue and hand the results to GIS tools.", interaction: "Import the venue's IMDF folder and pick a level, start location, tap a spot you can identify and stand on it while recording, walk the corridors as a path, then read the error vectors and heatmap and export the survey as GeoJSON."),
            explanations: [
                .platformUnsupported: ExperimentExplanation(reason: "Surveys need continuous location updates and the document picker for IMDF, which Apple TV and Apple Watch do not offer to this app.", required: "iOS, iPadOS or macOS",
                    nextStep: "Open Apple Toolbox on iPhone, iPad or Mac."),
                .permissionRequired: ExperimentExplanation(reason: "The app has not asked for location access yet; without it points can only be placed by tapping the map.", required: "Location When In Use",
                    nextStep: "Tap Start Location; the system asks for location access first."),
                .permissionDenied: ExperimentExplanation(reason: "Location access is denied or restricted, so no measured positions or accuracies can be recorded.", required: "Location Services on and Apple Toolbox allowed While Using the App",
                    nextStep: "Allow Apple Toolbox in Settings › Privacy & Security › Location Services."),
            ]),
    ]
}
