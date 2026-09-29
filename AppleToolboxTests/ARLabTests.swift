import Testing
import Foundation
import CoreGraphics
#if canImport(ARKit)
import ARKit
#endif
@testable import AppleToolbox

@MainActor
struct ARLabTests {

    @Test func referencePatternIsDeterministicAndInsideTheImage() {
        let first = ARLabFormat.patternShapes()
        let second = ARLabFormat.patternShapes()
        #expect(first == second)
        #expect(first.count == 90)
        #expect(ARLabFormat.patternShapes(seed: 1) != first)
        for shape in first {
            #expect(shape.rect.minX >= 0 && shape.rect.minY >= 0)
            #expect(shape.rect.maxX <= 1 + 1e-9 && shape.rect.maxY <= 1 + 1e-9)
            #expect(shape.rect.width >= 0.04 && shape.rect.width <= 0.2)
            #expect((0...1).contains(shape.hue))
        }
        // Several shape kinds keep the pattern non-repetitive for ARKit.
        #expect(Set(first.map { "\($0.kind)" }).count == 3)
    }

    @Test func framesPerSecondAndMeters() {
        #expect(ARLabFormat.fps(frames: 30, seconds: 0.5) == 60)
        #expect(ARLabFormat.fps(frames: 10, seconds: 0) == 0)
        #expect(ARLabFormat.meters(1.234) == "1.23 m")
    }

    #if canImport(ARKit)
    @Test func trackingStatesAndPlaneClassificationsReadNaturally() {
        #expect(ARLabFormat.trackingState(.normal) == "Normal")
        #expect(ARLabFormat.trackingState(.notAvailable) == "Not available")
        #expect(ARLabFormat.trackingState(.limited(.excessiveMotion)) == "Limited — excessive motion")
        #expect(ARLabFormat.trackingState(.limited(.relocalizing)) == "Limited — relocalizing")
        #expect(ARLabFormat.classification(.wall) == "Wall")
        #expect(ARLabFormat.classification(.none(.undetermined)) == "Unclassified (undetermined yet)")
        #expect(ARLabFormat.worldMapping(.mapped) == "Mapped")
    }
    #endif

    @Test func arkitExperimentIsTheLab() throws {
        let experiment = try #require(ExperimentRegistry.descriptor(for: "arkit"))
        #expect(experiment.name == "ARKit & RealityKit Lab")
        #expect(experiment.frameworks == ["ARKit", "RealityKit"])
        #expect(experiment.supportedPlatforms == [.iOS, .iPadOS])
        #expect(experiment.explanation(for: .platformUnsupported) != nil)
        #expect(ARLabMode.allCases.map(\.configurationName).allSatisfy { $0.hasPrefix("AR") && $0.hasSuffix("Configuration") })
    }
}
