import Foundation

/// Identifiers derived from the bundle ID instead of being hard-coded. Every target's bundle ID is
/// `$(BUNDLE_ID_PREFIX).AppleToolbox…` (set in Config/Signing.xcconfig), and the entitlements and Info.plist build
/// the App Group, the shared keychain group and the Handoff activity type from the same prefix.
nonisolated enum ToolboxIdentifiers {
    static let placeholderBase = "com.example.AppleToolbox"

    /// "<prefix>.AppleToolbox", e.g. "com.example.AppleToolbox".
    static let base = baseIdentifier(for: Bundle.main.bundleIdentifier)
    /// Matches `application-groups` in the entitlements.
    static let appGroup = "group.\(base)"

    /// The bundle ID up to and including its "AppleToolbox" component; the placeholder when it has none.
    static func baseIdentifier(for bundleIdentifier: String?) -> String {
        let components = (bundleIdentifier ?? "").split(separator: ".")
        guard let index = components.firstIndex(of: "AppleToolbox"), index > 0 else { return placeholderBase }
        return components[...index].joined(separator: ".")
    }
}
