import Testing
import Foundation
@testable import AppleToolbox

@MainActor
struct AIAvailabilityTests {

    @Test func platformThenSDKThenOSThenLiveStatus() {
        var evaluated = false
        let probe: () -> ExperimentStatus = { evaluated = true; return .available }
        #expect(AIAvailabilityMapping.status(platformSupported: false, frameworkInSDK: true, isSimulator: false, osSupported: true, liveStatus: probe) == .platformUnsupported)
        #expect(AIAvailabilityMapping.status(platformSupported: true, frameworkInSDK: false, isSimulator: true, osSupported: true, liveStatus: probe) == .deviceOnly)
        #expect(AIAvailabilityMapping.status(platformSupported: true, frameworkInSDK: false, isSimulator: false, osSupported: true, liveStatus: probe) == .platformUnsupported)
        #expect(AIAvailabilityMapping.status(platformSupported: true, frameworkInSDK: true, isSimulator: false, osSupported: false, liveStatus: probe) == .osUnsupported)
        #expect(!evaluated)
        #expect(AIAvailabilityMapping.status(platformSupported: true, frameworkInSDK: true, isSimulator: false, osSupported: true) { .unavailable } == .unavailable)
        #expect(AIAvailabilityMapping.status(platformSupported: true, frameworkInSDK: true, isSimulator: false, osSupported: true, liveStatus: probe) == .available)
        #expect(evaluated)
    }

    @Test func imageInputNeedsTheVisionCapability() {
        #expect(AIAvailabilityMapping.imageInputStatus(modelStatus: .available, supportsVision: true) == .available)
        #expect(AIAvailabilityMapping.imageInputStatus(modelStatus: .available, supportsVision: false) == .unavailable)
        #expect(AIAvailabilityMapping.imageInputStatus(modelStatus: .hardwareUnsupported, supportsVision: true) == .hardwareUnsupported)
    }

    @Test func executionFactsNeverClaimPrivateCloudCompute() {
        for imageInput in [nil, true, false] as [Bool?] {
            for tools in [true, false] {
                for pcc in [true, false] {
                    let facts = AIExecutionFacts.foundationModels(imageInput: imageInput, visionToolsInSDK: tools, pccProvisioned: pcc)
                    #expect(facts.count == 4)
                    #expect(facts.first?.place == .onDevice)
                    #expect(facts.last?.place == .notUsed)
                    #expect(facts.last?.detail.contains(AIExecutionFacts.pccEntitlement) == true)
                }
            }
        }
    }

    @Test func imageRowFollowsTheOSAndCapability() {
        let below27 = AIExecutionFacts.foundationModels(imageInput: nil, visionToolsInSDK: true, pccProvisioned: false)
        #expect(below27[1].place == .requiresOS && below27[2].place == .requiresOS)
        let vision = AIExecutionFacts.foundationModels(imageInput: true, visionToolsInSDK: true, pccProvisioned: false)
        #expect(vision[1].place == .onDevice && vision[2].place == .onDevice)
        let noVision = AIExecutionFacts.foundationModels(imageInput: false, visionToolsInSDK: false, pccProvisioned: false)
        #expect(noVision[1].place == .unsupported && noVision[2].place == .unsupported)
    }

    @Test func coreAIShapesResolveDynamicDimensions() {
        #expect(CoreAIShapes.concreteShape([1, -1, 0, 3]) == [1, 1, 1, 3])
        #expect(CoreAIShapes.concreteShape([]) == [1])
        #expect(CoreAIShapes.describe(shape: [1, -1, 8]) == "[1 × ? × 8]")
        let summary = CoreAIShapes.describe(scalarType: "Float32", shape: [1, 10], firstValues: [0.5], total: 10)
        #expect(summary.hasPrefix("Float32 [1 × 10] · 0") && summary.hasSuffix(", …"))
    }

    @Test func newAIExperimentsAreRegistered() throws {
        let image = try #require(ExperimentRegistry.descriptor(for: "foundation-models-image"))
        let coreAI = try #require(ExperimentRegistry.descriptor(for: "core-ai"))
        #expect(image.explanation(for: .osUnsupported)?.required.contains("27") == true)
        #expect(coreAI.explanation(for: .osUnsupported)?.required.contains("27") == true)
    }
}
