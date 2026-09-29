import Foundation

/// How to build an experiment's core feature in your own app: the minimal code, the Info.plist keys,
/// the entitlements and what to enable for the App ID. Shown in the experiment's "How to implement" section.
nonisolated struct ImplementationGuide: Sendable {
    /// The SDK a snippet is typechecked against by `scripts/check-guide-snippets.py`.
    enum Platform: String, Sendable { case iOS, macOS, tvOS, watchOS }

    struct PlistEntry: Sendable, Hashable {
        let key: String
        /// An example value, written as it would appear in the Info.plist (a string, `<true/>`, an array …).
        let value: String
    }

    let platform: Platform
    /// A self-contained Swift file (imports and declarations) that typechecks in Swift 6 against the SDK.
    let snippet: String
    let infoPlist: [PlistEntry]
    /// Entitlement keys with their value, e.g. "com.apple.developer.nfc.readersession.formats = [TAG]".
    let entitlements: [String]
    /// What to add under Signing & Capabilities or enable for the App ID in the developer portal.
    let capabilities: [String]
    /// Things worth knowing before you ship it: threading, availability, App Review, Apple approval.
    let notes: [String]

    init(platform: Platform = .iOS, snippet: String, infoPlist: [PlistEntry] = [], entitlements: [String] = [],
         capabilities: [String] = [], notes: [String] = []) {
        self.platform = platform
        self.snippet = snippet
        self.infoPlist = infoPlist
        self.entitlements = entitlements
        self.capabilities = capabilities
        self.notes = notes
    }

    /// The Info.plist entries as XML, ready to paste into the source view of an Info.plist.
    var infoPlistXML: String {
        infoPlist.map { entry in
            let value = entry.value.hasPrefix("<") ? entry.value : "<string>\(entry.value)</string>"
            return "<key>\(entry.key)</key>\n\(value)"
        }.joined(separator: "\n")
    }
}

/// One dictionary per category (`Guides+<Category>.swift`), keyed by experiment id.
nonisolated enum ImplementationGuides {
    static func guide(for experimentID: String) -> ImplementationGuide? { all[experimentID] }

    static let all: [String: ImplementationGuide] = [
        ai, audio, camera, connectivity, developer, health, home, input, location, maps,
        networking, nfc, platform, security, sensors, spatial, system, wallet,
    ].reduce(into: [:]) { result, category in result.merge(category) { first, _ in first } }
}
