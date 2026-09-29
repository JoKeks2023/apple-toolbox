import Testing
import Foundation
import CoreVideo
import ImageIO
@testable import AppleToolbox

@MainActor
struct CameraLabTests {

    @Test func exposureAndApertureReadLikeACamera() {
        #expect(CameraLabFormat.exposure(1.0 / 120) == "1/120 s")
        #expect(CameraLabFormat.exposure(0.0333) == "1/30 s")
        #expect(CameraLabFormat.exposure(2) == "2.0 s")
        #expect(CameraLabFormat.exposure(0) == "—")
        #expect(CameraLabFormat.aperture(1.78) == "ƒ/1.8")
        #expect(CameraLabFormat.aperture(2.2) == "ƒ/2.2")
    }

    @Test func zoomUsesTheDisplayMultiplier() {
        #expect(CameraLabFormat.zoom(1) == "1×")
        #expect(CameraLabFormat.zoom(2, multiplier: 0.5) == "1×")
        #expect(CameraLabFormat.zoom(1, multiplier: 0.5) == "0.5×")
        #expect(CameraLabFormat.zoom(2.5) == "2.5×")
    }

    @Test func dimensionsAndDurations() {
        #expect(CameraLabFormat.dimensions(width: 4032, height: 3024) == "4032 × 3024 (12.2 MP)")
        #expect(CameraLabFormat.dimensions(width: 0, height: 0) == "—")
        #expect(CameraLabFormat.duration(7.4) == "0:07")
        #expect(CameraLabFormat.duration(75) == "1:15")
        #expect(CameraLabFormat.duration(.nan) == "—")
    }

    @Test func fourCharacterCodesAndDepthTypes() {
        #expect(CameraLabFormat.fourCC(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange) == "420f")
        #expect(CameraLabFormat.fourCC(1) == "0x00000001")
        #expect(CameraLabFormat.depthTypeName(kCVPixelFormatType_DisparityFloat16) == "Disparity, Float16")
        #expect(CameraLabFormat.depthTypeName(kCVPixelFormatType_DepthFloat32) == "Depth (m), Float32")
    }

    @Test func metadataRowsReadExifAndTiff() {
        let metadata: [String: Any] = [
            kCGImagePropertyOrientation as String: 6,
            kCGImagePropertyTIFFDictionary as String: [
                kCGImagePropertyTIFFMake as String: "Apple",
                kCGImagePropertyTIFFModel as String: "iPhone",
            ],
            kCGImagePropertyExifDictionary as String: [
                kCGImagePropertyExifExposureTime as String: 0.008333,
                kCGImagePropertyExifFNumber as String: 1.78,
                kCGImagePropertyExifISOSpeedRatings as String: [64],
                kCGImagePropertyExifFocalLength as String: 6.86,
                kCGImagePropertyExifFocalLenIn35mmFilm as String: 24,
                kCGImagePropertyExifFlash as String: 16,
                kCGImagePropertyExifLensModel as String: "iPhone back camera 6.86mm f/1.78",
            ],
        ]
        let rows = Dictionary(uniqueKeysWithValues: CameraLabFormat.metadataRows(metadata).map { ($0.title, $0.value) })
        #expect(rows["Camera"] == "Apple iPhone")
        #expect(rows["Exposure"] == "1/120 s")
        #expect(rows["Aperture"] == "ƒ/1.8")
        #expect(rows["ISO"] == "ISO 64")
        #expect(rows["Focal length"] == "6.86 mm (24 mm equiv.)")
        #expect(rows["Flash"] == "Did not fire")
        #expect(rows["Orientation"] == "Right (6)")
        #expect(rows["Lens"] == "iPhone back camera 6.86mm f/1.78")
        #expect(CameraLabFormat.metadataRows([:]).isEmpty)
    }

    @Test func cameraLabIsRegisteredAndRouted() throws {
        let experiment = try #require(ExperimentRegistry.descriptor(for: "camera-lab"))
        #expect(experiment.category == .camera)
        #expect(experiment.supportedPlatforms.contains(.iOS) && experiment.supportedPlatforms.contains(.macOS))
        #expect(!experiment.supportedPlatforms.contains(.tvOS))
        #expect(experiment.explanation(for: .platformUnsupported)?.reason.contains("Continuity Camera") == true)
    }
}
