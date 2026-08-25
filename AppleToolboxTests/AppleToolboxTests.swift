//
//  AppleToolboxTests.swift
//  AppleToolboxTests
//
//  Created by Joris Conrad on 25.08.26.
//

import Testing
import Foundation
@testable import AppleToolbox

struct AppleToolboxTests {

    @Test func registryContainsOnlyFoundationExperiments() async throws {
        #expect(ExperimentRegistry.all.map(\.id) == ["localauthentication", "cryptokit", "keychain", "secure-enclave", "core-location", "core-motion", "core-nfc", "core-bluetooth", "network-path"])
        #expect(ExperimentRegistry.all.count == 9)
    }

    @Test func everyExperimentHasDocumentationAndMetadata() async throws {
        for experiment in ExperimentRegistry.all {
            #expect(!experiment.name.isEmpty)
            #expect(!experiment.frameworks.isEmpty)
            #expect(!experiment.supportedPlatforms.isEmpty)
            #expect(experiment.documentationURL.host == "developer.apple.com")
        }
    }

}
