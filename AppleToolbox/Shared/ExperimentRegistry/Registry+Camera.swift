import Foundation

extension ExperimentRegistry {
    static let camera: [ExperimentDescriptor] = [
        ExperimentDescriptor(id: "camera-vision", name: "Camera & Vision", category: .camera,
            description: "Capture live camera frames and run Vision text recognition on the real image stream.", frameworks: ["AVFoundation", "Vision"], supportedPlatforms: [.iOS, .iPadOS, .macOS], hardwareRequirements: ["Camera"], osRequirements: ["iOS 11+ · macOS 10.15+"], permissions: ["Camera Usage Description"], capabilities: [], entitlements: [], documentationURL: URL(string: "https://developer.apple.com/documentation/vision")!, evaluate: ExperimentAvailability.camera),
    ]
}
