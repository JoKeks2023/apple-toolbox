import Foundation

/// An app extension embedded in this app's PlugIns folder, read from the extension's own Info.plist. Only the iOS app
/// embeds extensions; on other platforms the list is empty.
nonisolated struct EmbeddedAppExtension: Equatable, Sendable {
    let fileName: String
    let bundleIdentifier: String
    let extensionPoint: String
    let principalClass: String?

    init?(fileName: String, infoDictionary: [String: Any]) {
        guard let nsExtension = infoDictionary["NSExtension"] as? [String: Any],
              let point = nsExtension["NSExtensionPointIdentifier"] as? String else { return nil }
        self.fileName = fileName
        bundleIdentifier = infoDictionary["CFBundleIdentifier"] as? String ?? "unknown bundle"
        extensionPoint = point
        principalClass = nsExtension["NSExtensionPrincipalClass"] as? String
    }

    /// Every extension in the given PlugIns folder (the app's own by default).
    static func all(in plugIns: URL? = Bundle.main.builtInPlugInsURL) -> [EmbeddedAppExtension] {
        guard let plugIns, let urls = try? FileManager.default.contentsOfDirectory(at: plugIns, includingPropertiesForKeys: nil) else { return [] }
        return urls.filter { $0.pathExtension == "appex" }.sorted { $0.lastPathComponent < $1.lastPathComponent }.compactMap { url in
            Bundle(url: url)?.infoDictionary.flatMap { EmbeddedAppExtension(fileName: url.lastPathComponent, infoDictionary: $0) }
        }
    }

    /// The app's own PlugIns folder, read once: the bundle cannot change while the app runs.
    static let bundled = all()

    static func embedded(extensionPoint: String) -> [EmbeddedAppExtension] {
        bundled.filter { $0.extensionPoint == extensionPoint }
    }

    var summary: String { "\(fileName) · \(bundleIdentifier)" }
}
