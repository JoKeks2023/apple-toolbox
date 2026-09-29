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
        ExperimentDescriptor(id: "camera-vision", name: "Vision Lab", category: .camera,
            description: "Run Vision's Swift requests on live camera frames or a picked photo: barcodes, face rectangles and landmarks, human body and hand pose, image classification, document segmentation, text recognition, object tracking, animal recognition, human rectangles and objectness-based saliency, with boxes, confidences and the observations drawn over the analyzed image.", frameworks: ["Vision", "AVFoundation", "PhotosUI"], supportedPlatforms: [.iOS, .iPadOS, .macOS], hardwareRequirements: ["Camera for live frames and tracking (photos work without one)"], osRequirements: ["iOS 18+ · iPadOS 18+ · macOS 15+ (Vision Swift API)"], permissions: ["Camera Usage Description (live frames only)"], capabilities: ["On-device Vision requests"], entitlements: [], documentationURL: URL(string: "https://developer.apple.com/documentation/vision")!, evaluate: { .available },
            useCase: ExperimentUseCase(id: "vision-lab-analyze", title: "See what Vision finds in a frame", summary: "Point the camera at a QR code, a face, a hand, a document or any scene, or pick a photo, and inspect every observation Vision returns.", interaction: "Choose a request, then start the live camera or pick a photo. For object tracking, start the camera and drag a rectangle around an object."),
            explanations: [
                .platformUnsupported: ExperimentExplanation(reason: "Vision itself exists on tvOS, but Apple TV has no camera and no PhotosPicker, so this lab has no image to analyze; watchOS lacks most of these requests.", required: "iPhone, iPad or Mac",
                    nextStep: "Open the Vision Lab on an iPhone, iPad or Mac."),
            ]),
    ]
}
