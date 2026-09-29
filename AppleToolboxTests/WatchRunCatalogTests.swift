import Testing
import Foundation
@testable import AppleToolbox

@MainActor
struct WatchRunCatalogTests {
    private var watchDescriptorIDs: Set<String> {
        Set(ExperimentRegistry.all.filter { $0.supportedPlatforms.contains(.watchOS) }.map(\.id))
    }

    @Test func everyWatchDescriptorHasAWatchRunView() {
        #expect(watchDescriptorIDs.subtracting(WatchRunCatalog.experimentIDs).isEmpty)
    }

    @Test func everyWatchRunBelongsToAWatchDescriptor() {
        #expect(WatchRunCatalog.experimentIDs.subtracting(watchDescriptorIDs).isEmpty)
    }

    @Test func experimentsWithoutWatchOSHaveNoWatchRun() {
        #expect(!WatchRunCatalog.hasWatchRun("foundation-models"))
        #expect(WatchRunCatalog.hasWatchRun("core-motion"))
    }

    @Test func sharedChecksPassThePlatformOfASupportedExperiment() throws {
        // The watch detail view shows the same checks; core-motion supports iPhone, iPad and Apple Watch.
        let motion = try #require(ExperimentRegistry.descriptor(for: "core-motion"))
        #expect(motion.checks(for: .available).first { $0.id == "platform" }?.outcome == .passed)
    }
}
