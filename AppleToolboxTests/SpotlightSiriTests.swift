import Testing
import Foundation
import CoreSpotlight
@testable import AppleToolbox

@MainActor
struct SpotlightSiriTests {

    @Test func readsTheExperimentFromAnIndexedItemIdentifier() {
        #expect(SpotlightExperimentMetadata.experimentID(fromItemIdentifier: "ExperimentEntity/cryptokit") == "cryptokit")
        #expect(SpotlightExperimentMetadata.experimentID(fromItemIdentifier: "cryptokit") == "cryptokit")
        #expect(SpotlightExperimentMetadata.experimentID(fromItemIdentifier: "ExperimentEntity/") == nil)
        #expect(SpotlightExperimentMetadata.experimentID(fromItemIdentifier: "") == nil)
    }

    @Test func findsStaleIdentifiers() {
        #expect(SpotlightExperimentMetadata.staleIdentifiers(indexed: ["b", "a", "c", "a"], current: ["b", "c", "d"]) == ["a"])
        #expect(SpotlightExperimentMetadata.staleIdentifiers(indexed: [], current: ["a"]).isEmpty)
        #expect(SpotlightExperimentMetadata.staleIdentifiers(indexed: ["z", "y"], current: []) == ["y", "z"])
    }

    @Test func buildsKeywordsWithoutDuplicates() {
        let keywords = SpotlightExperimentMetadata.keywords(id: "secure-enclave", category: "Security", frameworks: ["CryptoKit", "Security"])
        #expect(keywords == ["CryptoKit", "Security", "Apple Toolbox", "secure", "enclave"])
    }

    @Test func indexedEntityCarriesSpotlightMetadata() throws {
        let experiment = try #require(ExperimentRegistry.descriptor(for: "cryptokit"))
        let entity = ExperimentEntity(experiment)
        let attributes = entity.attributeSet
        #expect(attributes.title == experiment.name)
        #expect(attributes.contentDescription == experiment.description)
        #expect(attributes.keywords?.contains("CryptoKit") == true)
        #expect(attributes.keywords?.contains(experiment.category.rawValue) == true)
        #expect(entity.symbolName == experiment.category.symbolName)
    }

    @Test func spotlightExperimentIsRegistered() throws {
        let experiment = try #require(ExperimentRegistry.descriptor(for: "spotlight-siri"))
        #expect(experiment.category == .system)
        #expect(experiment.frameworks.contains("CoreSpotlight"))
    }

    @Test func openExperimentIntentTargetsTheEntity() throws {
        let experiment = try #require(ExperimentRegistry.descriptor(for: "cryptokit"))
        let intent = OpenExperimentIntent(experiment: ExperimentEntity(experiment))
        #expect(intent.target.id == "cryptokit")
    }
}
