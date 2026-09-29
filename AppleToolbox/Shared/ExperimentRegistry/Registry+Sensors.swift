import Foundation

extension ExperimentRegistry {
    static let sensors: [ExperimentDescriptor] = [
        ExperimentDescriptor(id: "core-motion", name: "Core Motion", category: .sensors,
            description: "Stream device motion with attitude and the calibrated magnetic field, count steps with the pedometer, and read barometric altitude.",
            frameworks: ["CoreMotion"], supportedPlatforms: [.iOS, .iPadOS, .watchOS], hardwareRequirements: ["Motion sensors", "Magnetometer for the magnetic field", "Barometer for altitude"], osRequirements: ["iOS 7+ · watchOS 2+", "Absolute altitude: iOS 15+ · watchOS 8+"], permissions: ["Motion & Fitness (pedometer and altimeter)"], capabilities: [], entitlements: [],
            documentationURL: URL(string: "https://developer.apple.com/documentation/coremotion")!, evaluate: ExperimentAvailability.coreMotion,
            useCase: ExperimentUseCase(id: "motion-meter", title: "Move the device", summary: "Turn your iPhone or Apple Watch into a live motion meter, compass, step counter, and barometer.", interaction: "Start motion updates and tilt the device to watch attitude and the magnetic field, then start the pedometer or altimeter and walk or take the stairs."),
            explanations: [
                .hardwareUnsupported: ExperimentExplanation(reason: "Device motion data is not available (for example in the Simulator).", required: "Accelerometer and gyroscope",
                    nextStep: "Run on an iPhone, iPad or Apple Watch."),
                .permissionDenied: ExperimentExplanation(reason: "Motion & Fitness access is denied or restricted, so the pedometer and altimeter return no data. Device motion still works.", required: "Motion & Fitness access for Apple Toolbox and Fitness Tracking turned on",
                    nextStep: "Allow it in Settings › Privacy & Security › Motion & Fitness."),
            ]),
    ]
}
