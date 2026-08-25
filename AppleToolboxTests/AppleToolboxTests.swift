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
        #expect(ExperimentRegistry.all.map(\.id) == ["localauthentication", "cryptokit", "keychain", "secure-enclave", "core-location", "core-motion", "core-nfc", "core-bluetooth", "network-path", "camera-vision", "audio-input", "mapkit-search", "homekit-discovery", "matter-status", "continuity", "app-intents", "natural-language", "foundation-models", "healthkit-status", "wallet-status", "wallet-creator", "widgetkit", "nearby-interaction", "indoor-imdf", "arkit", "roomplan", "speech", "core-ml", "translation", "sound-analysis", "musickit", "shazamkit", "notifications", "app-attest", "passkeys", "sign-in-with-apple", "capability-explorer"])
        #expect(ExperimentRegistry.all.count == 37)
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
