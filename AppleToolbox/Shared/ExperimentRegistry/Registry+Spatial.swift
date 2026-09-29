import Foundation

extension ExperimentRegistry {
    static let spatial: [ExperimentDescriptor] = [
        ExperimentDescriptor(id: "arkit", name: "ARKit & RealityKit Lab", category: .spatial,
            description: "Run world, face, body or image tracking in a RealityKit ARView: plane detection, raycast placement of box and sphere entities with materials, physics and animation, the live anchor list, scene reconstruction mesh and occlusion on LiDAR devices, tracking state, frame statistics and a configuration support matrix.", frameworks: ["ARKit", "RealityKit"], supportedPlatforms: [.iOS, .iPadOS], hardwareRequirements: ["ARKit-capable camera and motion hardware", "TrueDepth camera for face tracking", "A12 or later for body tracking", "LiDAR Scanner for scene reconstruction"], osRequirements: ["iOS 16+ · iPadOS 16+"], permissions: ["Camera Usage Description"], capabilities: ["ARKit", "RealityKit", "Scene reconstruction where supported", "Face, body and image tracking where supported"], entitlements: [], documentationURL: URL(string: "https://developer.apple.com/documentation/arkit")!, evaluate: ExperimentAvailability.arKit,
            useCase: ExperimentUseCase(id: "arkit-lab-place", title: "Place RealityKit objects on real surfaces", summary: "Start world tracking, let ARKit find planes, then tap to drop physics objects or spinning shapes onto them; switch to face, body or image tracking to watch the matching anchors.", interaction: "Pick a configuration and entity options, start the session, move the device until planes appear and tap a surface. The anchor list, tracking state and frame statistics update live."),
            explanations: [
                .hardwareUnsupported: ExperimentExplanation(reason: "World tracking is not supported on this device.", required: "A device with an A9 chip or later and a rear camera",
                    nextStep: "Run the experiment on a recent iPhone or iPad."),
                .permissionDenied: ExperimentExplanation(reason: "Camera access was denied, and ARKit tracks the world through the camera.", required: "Camera Usage Description",
                    nextStep: "Allow camera access in Settings › Privacy & Security › Camera, then return to the app."),
                .platformUnsupported: ExperimentExplanation(reason: "ARKit's ARSession and RealityKit's AR camera mode run only on iPhone and iPad; the Mac and Apple TV have no ARKit tracking, and visionOS uses ARKitSession data providers instead.", required: "iPhone or iPad",
                    nextStep: "Open the lab on an iPhone or iPad."),
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
