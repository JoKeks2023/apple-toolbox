import Testing
import Foundation
import CoreGraphics
@testable import AppleToolbox

@MainActor
struct VisionLabTests {

    @Test func aspectFitCentersTheImage() {
        // A 4:3 landscape image in a square container is letterboxed vertically.
        let rect = VisionGeometry.aspectFitRect(imageSize: CGSize(width: 400, height: 300), in: CGSize(width: 200, height: 200))
        #expect(rect == CGRect(x: 0, y: 25, width: 200, height: 150))
        #expect(VisionGeometry.aspectFitRect(imageSize: .zero, in: CGSize(width: 10, height: 10)) == .zero)
    }

    @Test func normalizedPointsFlipIntoViewCoordinates() {
        let imageRect = CGRect(x: 0, y: 25, width: 200, height: 150)
        // Vision's origin is bottom-left, SwiftUI's is top-left.
        #expect(VisionGeometry.viewPoint(CGPoint(x: 0, y: 0), in: imageRect) == CGPoint(x: 0, y: 175))
        #expect(VisionGeometry.viewPoint(CGPoint(x: 1, y: 1), in: imageRect) == CGPoint(x: 200, y: 25))
        let round = VisionGeometry.normalizedPoint(VisionGeometry.viewPoint(CGPoint(x: 0.25, y: 0.75), in: imageRect), in: imageRect)
        #expect(abs(round.x - 0.25) < 1e-9 && abs(round.y - 0.75) < 1e-9)
        // Points outside the image clamp to its edge.
        #expect(VisionGeometry.normalizedPoint(CGPoint(x: -20, y: 0), in: imageRect) == CGPoint(x: 0, y: 1))
    }

    @Test func selectionRectFromDragAndTap() {
        let drag = VisionGeometry.selectionRect(from: CGPoint(x: 0.6, y: 0.2), to: CGPoint(x: 0.2, y: 0.7))
        #expect(abs(drag.minX - 0.2) < 1e-9 && abs(drag.minY - 0.2) < 1e-9)
        #expect(abs(drag.width - 0.4) < 1e-9 && abs(drag.height - 0.5) < 1e-9)
        // A tap becomes a square around the point, kept inside the image.
        let tap = VisionGeometry.selectionRect(from: CGPoint(x: 0.99, y: 0.01), to: CGPoint(x: 0.99, y: 0.01), minimumSide: 0.2)
        #expect(abs(tap.width - 0.2) < 1e-9 && abs(tap.height - 0.2) < 1e-9)
        #expect(tap.maxX <= 1 + 1e-9 && tap.minY >= 0)
    }

    @Test func labelsReadNaturally() {
        #expect(VisionLabFormat.symbologyName("qr") == "QR")
        #expect(VisionLabFormat.symbologyName("ean13") == "EAN-13")
        #expect(VisionLabFormat.symbologyName("code39FullASCII") == "Code 39")
        #expect(VisionLabFormat.symbologyName("unknownSymbology") == "unknownSymbology")
        #expect(VisionLabFormat.classificationLabel("coffee_mug") == "coffee mug")
        #expect(VisionLabFormat.percent(0.876) == "88 %")
    }

    @Test func everyRequestNamesItsVisionAPI() {
        for request in VisionLabRequest.allCases {
            #expect(request.apiName.hasSuffix("Request"), "\(request)")
        }
        #expect(Set(VisionLabRequest.allCases.map(\.apiName)).count == VisionLabRequest.allCases.count)
    }

    @Test func visionLabReplacesTheTextOnlyExperiment() throws {
        let experiment = try #require(ExperimentRegistry.descriptor(for: "camera-vision"))
        #expect(experiment.name == "Vision Lab")
        #expect(experiment.frameworks.contains("Vision"))
        #expect(!experiment.supportedPlatforms.contains(.tvOS))
    }
}
