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
    ]
}
