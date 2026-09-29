import Foundation

/// The provisioning profile embedded in the running app's bundle.
struct ProvisioningProfile {
    let name: String
    let teamName: String?
    let teamIdentifier: String?
    let appIDName: String?
    let platforms: [String]
    let expirationDate: Date?
    let provisionedDeviceCount: Int?
    let provisionsAllDevices: Bool
    /// Entitlement values rendered as text, keyed by entitlement key.
    let entitlements: [String: String]

    var isExpired: Bool { expirationDate.map { $0 < Date() } ?? false }
}

enum ProvisioningLookup {
    case found(ProvisioningProfile)
    case missing(String)
    case unreadable(String)

    var profile: ProvisioningProfile? {
        if case .found(let profile) = self { return profile }
        return nil
    }
}

/// What the running app can prove about one capability (spec §36).
enum ProvisioningState: Equatable {
    /// The embedded profile lists the key; the associated value is the rendered entitlement value.
    case provisioned(String)
    case notProvisioned
    /// Info.plist-based capability that the bundle declares.
    case declared(String)
    case notDeclared
    case unknown(String)

    var title: String {
        switch self {
        case .provisioned: "Provisioned"
        case .notProvisioned: "Not provisioned"
        case .declared: "Declared"
        case .notDeclared: "Not declared"
        case .unknown: "Unknown"
        }
    }

    var isPresent: Bool {
        switch self {
        case .provisioned, .declared: true
        default: false
        }
    }
}

/// Reads the app's own embedded provisioning profile with public file and property list APIs.
/// It only reports what the profile says; it never grants, requests or simulates an entitlement.
enum ProvisioningInspector {
    static var profileURL: URL {
        #if os(macOS)
        Bundle.main.bundleURL.appendingPathComponent("Contents/embedded.provisionprofile")
        #else
        Bundle.main.bundleURL.appendingPathComponent("embedded.mobileprovision")
        #endif
    }

    /// The embedded profile can't change while the app runs; status checks ask for it many times per screen.
    static func load() -> ProvisioningLookup { cached }

    private static let cached = read()

    private static func read() -> ProvisioningLookup {
        let url = profileURL
        guard FileManager.default.fileExists(atPath: url.path) else { return .missing(missingProfileReason) }
        do {
            guard let profile = parse(try Data(contentsOf: url)) else {
                return .unreadable("\(url.lastPathComponent) exists, but it contains no readable property list.")
            }
            return .found(profile)
        } catch {
            return .unreadable("\(url.lastPathComponent) could not be read: \(error.localizedDescription)")
        }
    }

    /// A profile is a CMS-signed message whose payload is an XML property list; the plist is cut out between its
    /// markers. The signature is not verified here, the system already did that when it installed the app.
    static func parse(_ data: Data) -> ProvisioningProfile? {
        guard let start = data.range(of: Data("<?xml".utf8)),
              let end = data.range(of: Data("</plist>".utf8), in: start.upperBound..<data.endIndex),
              let plist = try? PropertyListSerialization.propertyList(from: data.subdata(in: start.lowerBound..<end.upperBound), format: nil) as? [String: Any]
        else { return nil }
        let entitlements = plist["Entitlements"] as? [String: Any] ?? [:]
        return ProvisioningProfile(
            name: plist["Name"] as? String ?? "Unnamed profile",
            teamName: plist["TeamName"] as? String,
            teamIdentifier: (plist["TeamIdentifier"] as? [String])?.first,
            appIDName: plist["AppIDName"] as? String,
            platforms: plist["Platform"] as? [String] ?? [],
            expirationDate: plist["ExpirationDate"] as? Date,
            provisionedDeviceCount: (plist["ProvisionedDevices"] as? [Any])?.count,
            provisionsAllDevices: plist["ProvisionsAllDevices"] as? Bool ?? false,
            entitlements: entitlements.mapValues(render))
    }

    static func state(of capability: CapabilityDescriptor, in lookup: ProvisioningLookup) -> ProvisioningState {
        switch capability.keySource {
        case .appIDOnly:
            return .unknown("This capability has no entitlement key, so neither the profile nor the bundle can show whether it is enabled.")
        case .infoPlist:
            let values = present(capability.keys, value: { Bundle.main.object(forInfoDictionaryKey: $0).map(render) })
            return values.map(ProvisioningState.declared) ?? .notDeclared
        case .provisioningProfile, .codeSignature:
            switch lookup {
            case .missing(let reason), .unreadable(let reason):
                return .unknown(reason)
            case .found(let profile):
                if let values = present(capability.keys, value: { profile.entitlements[$0] }) { return .provisioned(values) }
                return capability.keySource == .codeSignature
                    ? .unknown("Provisioning profiles do not list this entitlement; only the app's code signature carries it, and the explorer does not read the signature.")
                    : .notProvisioned
            }
        }
    }

    /// Renders the values of the keys that are present: the bare value for single-key capabilities, one `key: value` line per key otherwise.
    private static func present(_ keys: [String], value: (String) -> String?) -> String? {
        let found = keys.compactMap { key in value(key).map { (key, $0) } }
        guard !found.isEmpty else { return nil }
        return keys.count == 1 ? found[0].1 : found.map { "\($0.0): \($0.1)" }.joined(separator: "\n")
    }

    static func render(_ value: Any) -> String {
        switch value {
        case let number as NSNumber:
            CFGetTypeID(number) == CFBooleanGetTypeID() ? (number.boolValue ? "true" : "false") : number.stringValue
        case let string as String: string
        case let array as [Any]: array.isEmpty ? "(empty list)" : array.map(render).joined(separator: ", ")
        case let dictionary as [String: Any]: dictionary.sorted { $0.key < $1.key }.map { "\($0.key): \(render($0.value))" }.joined(separator: "; ")
        case let date as Date: date.formatted(date: .abbreviated, time: .shortened)
        case let data as Data: "\(data.count) bytes"
        default: String(describing: value)
        }
    }

    private static var missingProfileReason: String {
        #if targetEnvironment(simulator)
        "No embedded provisioning profile: Simulator builds are signed without one, so provisioned entitlements cannot be read here."
        #else
        "No embedded provisioning profile. Typical reasons: an App Store or TestFlight install, or a build signed without a profile (for example “Sign to Run Locally”)."
        #endif
    }
}
