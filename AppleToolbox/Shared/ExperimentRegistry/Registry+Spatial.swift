import Foundation

extension ExperimentRegistry {
    static let spatial: [ExperimentDescriptor] = [
        ExperimentDescriptor(id: "arkit", name: "ARKit", category: .spatial,
            description: "Start real world tracking and inspect whether the device supports scene-depth frames.", frameworks: ["ARKit"], supportedPlatforms: [.iOS, .iPadOS], hardwareRequirements: ["ARKit-capable camera and motion hardware"], osRequirements: ["iOS 11+ · iPadOS 11+"], permissions: ["Camera Usage Description"], capabilities: ["ARKit", "Scene Depth where supported"], entitlements: [], documentationURL: URL(string: "https://developer.apple.com/documentation/arkit")!, evaluate: ExperimentAvailability.arKit,
            explanations: [
                .hardwareUnsupported: ExperimentExplanation(reason: "World tracking is not supported on this device.", required: "A device with an A9 chip or later and a rear camera",
                    nextStep: "Run the experiment on a recent iPhone or iPad."),
            ]),
        ExperimentDescriptor(id: "roomplan", name: "RoomPlan", category: .spatial,
            description: "Scan a room with RoomCaptureView on a LiDAR device, summarize walls, doors, windows, openings, objects and overall dimensions, and share the result as a USDZ model.", frameworks: ["RoomPlan", "ARKit"], supportedPlatforms: [.iOS, .iPadOS], hardwareRequirements: ["LiDAR Scanner (iPhone Pro or iPad Pro)"], osRequirements: ["iOS 17+ · iPadOS 17+"], permissions: ["Camera Usage Description"], capabilities: ["RoomPlan", "LiDAR", "USDZ export"], entitlements: [], documentationURL: URL(string: "https://developer.apple.com/documentation/roomplan")!, evaluate: ExperimentAvailability.roomPlan,
            useCase: ExperimentUseCase(id: "roomplan-scan", title: "Measure a room", summary: "Walk around a room with a LiDAR iPhone or iPad and let RoomPlan build a parametric 3D model of it.", interaction: "Start the capture, scan every wall slowly, tap Done, then inspect walls, doors, windows, objects and dimensions and share the USDZ file."),
            explanations: [
                .hardwareUnsupported: ExperimentExplanation(reason: "RoomCaptureSession.isSupported is false: this device (or the Simulator) has no LiDAR Scanner.", required: "A LiDAR-capable iPhone Pro or iPad Pro",
                    nextStep: "Run the experiment on a LiDAR device."),
                .permissionDenied: ExperimentExplanation(reason: "Camera access was denied, and RoomPlan scans the room through the camera.", required: "Camera Usage Description",
                    nextStep: "Allow camera access in Settings › Privacy & Security › Camera, then return to the app."),
            ]),
    ]
}
