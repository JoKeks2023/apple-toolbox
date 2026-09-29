import Foundation

/// The experiments the watch app can run on Apple Watch (spec §29). Every descriptor that lists `.watchOS` in
/// `supportedPlatforms` must appear here and have a case in the watch app's `WatchRunRoutes`; a unit test keeps
/// the registry and this list in step.
nonisolated enum WatchRunCatalog {
    static let experimentIDs: Set<String> = [
        "app-attest", "app-intents", "capability-explorer", "continuity", "core-bluetooth", "core-location", "core-motion",
        "cryptokit", "healthkit-status", "homekit-discovery", "keychain", "musickit", "natural-language", "nearby-interaction",
        "notifications", "secure-enclave", "sign-in-with-apple",
    ]

    static func hasWatchRun(_ experimentID: String) -> Bool { experimentIDs.contains(experimentID) }
}
