import Foundation

extension ExperimentRegistry {
    static let input: [ExperimentDescriptor] = [
        ExperimentDescriptor(id: "game-controller", name: "Game Controller", category: .input,
            description: "List connected game controllers and the Siri Remote with profile, battery, and haptics, discover wireless controllers, and watch live button, trigger, and stick input.", frameworks: ["GameController"], supportedPlatforms: [.iOS, .iPadOS, .macOS, .tvOS], hardwareRequirements: ["Connected game controller (Siri Remote on Apple TV)"], osRequirements: ["iOS 14+ · macOS 11+ · tvOS 14+"], permissions: [], capabilities: [], entitlements: [], documentationURL: URL(string: "https://developer.apple.com/documentation/gamecontroller")!, evaluate: ExperimentAvailability.gameController,
            useCase: ExperimentUseCase(id: "controller-input-monitor", title: "Test a game controller", summary: "See which controllers the system reports and watch every button, trigger, and stick as you use it.", interaction: "Start monitoring, turn on or pair a controller (or use the Siri Remote on Apple TV), then press buttons and move the sticks."),
            explanations: [
                .unavailable: ExperimentExplanation(reason: "No game controller is connected right now.", required: "A paired MFi, Xbox, PlayStation, or Switch controller (the Siri Remote counts on Apple TV)",
                    nextStep: "Pair the controller in Bluetooth settings, or put an MFi controller in pairing mode and start wireless discovery below."),
            ]),
    ]
}
