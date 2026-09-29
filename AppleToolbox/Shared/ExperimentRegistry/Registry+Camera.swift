import Foundation

extension ExperimentRegistry {
    static let camera: [ExperimentDescriptor] = [
        ExperimentDescriptor(id: "camera-lab", name: "Camera Lab", category: .camera,
            description: "Live AVCaptureVideoPreviewLayer preview of any discovered camera, photo capture (HEIC/JPEG, flash) with EXIF metadata and depth data, focus, exposure bias, zoom, torch and video HDR controls, and short video recording with AVCaptureMovieFileOutput.", frameworks: ["AVFoundation", "ImageIO"], supportedPlatforms: [.iOS, .iPadOS, .macOS], hardwareRequirements: ["Camera", "TrueDepth, dual or LiDAR camera for depth data"], osRequirements: ["iOS 17+ · iPadOS 17+ · macOS 14+"], permissions: ["Camera Usage Description", "Microphone Usage Description (optional, video audio)"], capabilities: ["Photo capture", "Depth data", "Movie recording"], entitlements: [], documentationURL: URL(string: "https://developer.apple.com/documentation/avfoundation/capture-setup")!, evaluate: ExperimentAvailability.camera,
            useCase: ExperimentUseCase(id: "camera-lab-capture", title: "Take a photo and read what the camera did", summary: "Pick any camera the system discovers (wide, ultra wide, telephoto, TrueDepth, LiDAR depth, virtual or external), tune focus, exposure, zoom, torch and HDR, then capture a photo or a short clip.", interaction: "Start the camera, tap the preview to focus, adjust the controls, then take a photo to inspect its EXIF metadata and depth map, or switch to Video and record up to a minute. Share the files from the result."),
            explanations: [
                .hardwareUnsupported: ExperimentExplanation(reason: "AVCaptureDevice.DiscoverySession reports no video capture device.", required: "A built-in or connected camera",
                    nextStep: "Run the lab on an iPhone or iPad, or connect a camera to the Mac."),
                .permissionDenied: ExperimentExplanation(reason: "Camera access was denied or is restricted, so AVCaptureDeviceInput cannot open a camera.", required: "Camera Usage Description",
                    nextStep: "Allow camera access in Settings › Privacy & Security › Camera, then return to the app."),
                .platformUnsupported: ExperimentExplanation(reason: "Apple TV has no built-in camera (tvOS only offers an iPhone as Continuity Camera, which this lab does not cover), and watchOS has no camera API.", required: "iPhone, iPad or Mac",
                    nextStep: "Open the Camera Lab on an iPhone, iPad or Mac."),
            ]),
        ExperimentDescriptor(id: "camera-vision", name: "Camera & Vision", category: .camera,
            description: "Capture live camera frames and run Vision text recognition on the real image stream.", frameworks: ["AVFoundation", "Vision"], supportedPlatforms: [.iOS, .iPadOS, .macOS], hardwareRequirements: ["Camera"], osRequirements: ["iOS 11+ · macOS 10.15+"], permissions: ["Camera Usage Description"], capabilities: [], entitlements: [], documentationURL: URL(string: "https://developer.apple.com/documentation/vision")!, evaluate: ExperimentAvailability.camera),
    ]
}
