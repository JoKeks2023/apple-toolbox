import Foundation

nonisolated extension ImplementationGuides {
    static let camera: [String: ImplementationGuide] = [
        "camera-lab": ImplementationGuide(
            snippet: #"""
            import AVFoundation

            /// Runs a photo capture session on its own queue. Show `session` with AVCaptureVideoPreviewLayer(session:).
            final class CameraController: NSObject, AVCapturePhotoCaptureDelegate, @unchecked Sendable {
                let session = AVCaptureSession()
                private let output = AVCapturePhotoOutput()
                private let queue = DispatchQueue(label: "camera.session") // guards all state below
                private var completion: (@Sendable (Data?) -> Void)?

                func start() async {
                    guard await AVCaptureDevice.requestAccess(for: .video) else { return }
                    queue.async { [self] in
                        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                              let input = try? AVCaptureDeviceInput(device: camera) else { return }
                        session.beginConfiguration()
                        session.sessionPreset = .photo
                        if session.canAddInput(input) { session.addInput(input) }
                        if session.canAddOutput(output) { session.addOutput(output) }
                        session.commitConfiguration()
                        session.startRunning() // blocks: never call it on the main thread
                    }
                }

                func capturePhoto(completion: @escaping @Sendable (Data?) -> Void) {
                    queue.async { [self] in
                        self.completion = completion
                        let settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.hevc])
                        output.capturePhoto(with: settings, delegate: self)
                    }
                }

                func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
                    let data = photo.fileDataRepresentation() // HEIC with EXIF metadata
                    queue.async { [self] in
                        completion?(data)
                        completion = nil
                    }
                }
            }
            """#,
            infoPlist: [
                .init(key: "NSCameraUsageDescription", value: "Takes photos and videos."),
                .init(key: "NSMicrophoneUsageDescription", value: "Records sound with your videos."),
            ],
            notes: [
                "Session configuration and startRunning() block; keep them on a dedicated serial queue.",
                "Change focus, exposure, zoom and torch between device.lockForConfiguration() and unlockForConfiguration().",
                "The microphone key is only needed when you record video with audio; saving to Photos needs NSPhotoLibraryAddUsageDescription.",
            ]
        ),
        "camera-vision": ImplementationGuide(
            snippet: #"""
            import CoreGraphics
            import Vision

            /// Reads barcodes and text from an image with the Swift Vision API (iOS 18+).
            func analyze(_ image: CGImage) async throws -> (codes: [String], lines: [String]) {
                let barcodes = try await DetectBarcodesRequest().perform(on: image)

                var textRequest = RecognizeTextRequest()
                textRequest.recognitionLevel = .accurate
                textRequest.usesLanguageCorrection = true
                let text = try await textRequest.perform(on: image)

                return (barcodes.compactMap(\.payloadString),
                        text.compactMap { $0.topCandidates(1).first?.string })
            }

            /// Face bounding boxes, normalized to 0…1 with the origin at the lower left.
            func faces(in image: CGImage) async throws -> [NormalizedRect] {
                try await DetectFaceRectanglesRequest().perform(on: image).map(\.boundingBox)
            }
            """#,
            infoPlist: [
                .init(key: "NSCameraUsageDescription", value: "Analyzes the live camera image."),
            ],
            notes: [
                "Requests also accept CMSampleBuffer and CVPixelBuffer, so live frames from AVCaptureVideoDataOutput work the same way.",
                "Pass the image orientation for camera frames, or observations come back rotated.",
                "Skip frames while a request is still running instead of queuing them; keep the work off the main actor.",
            ]
        ),
    ]
}
