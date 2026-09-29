import Foundation
import Combine
#if canImport(Security)
import Security
#endif

/// Keychain access groups the app can pick. The iOS target's `keychain-access-groups` entitlement lists the app's own
/// group first (so it stays the default) and the shared group; the App Group from `application-groups` also counts.
nonisolated enum KeychainAccessGroupOption: String, CaseIterable, Identifiable, Sendable {
    case appDefault, shared, appGroup

    static let sharedGroupSuffix = "com.jorisconrad.AppleToolbox.shared"
    static let appGroupIdentifier = "group.com.jorisconrad.AppleToolbox"

    var id: String { rawValue }
    var title: String {
        switch self {
        case .appDefault: "Default group (app's own)"
        case .shared: "Shared · …\(Self.sharedGroupSuffix)"
        case .appGroup: "App Group · \(Self.appGroupIdentifier)"
        }
    }

    /// The concrete access group, or nil when it cannot be named yet (the shared group needs the team prefix).
    func accessGroup(defaultGroup: String?) -> String? {
        switch self {
        case .appDefault: defaultGroup
        case .shared: defaultGroup.flatMap(KeychainSharingStore.teamPrefix).map { "\($0).\(Self.sharedGroupSuffix)" }
        case .appGroup: Self.appGroupIdentifier
        }
    }
}

nonisolated struct KeychainItemSummary: Sendable, Equatable {
    let itemClass: String
    let accessGroup: String
    let label: String
    let synchronizable: Bool
}

nonisolated struct KeychainGroupSummary: Sendable, Equatable {
    let accessGroup: String
    let items: [KeychainItemSummary]
}

nonisolated struct KeychainSharingReport: Sendable {
    let text: String
    let isError: Bool
}

/// Keychain calls for the sharing lab. Every result is the real OSStatus; nothing is cached or simulated.
nonisolated enum KeychainSharingStore {
    static let service = "com.jorisconrad.appletoolbox.sharing"
    static let account = "shared-demo"

    // MARK: Pure helpers

    /// The team (App ID) prefix of an access group such as `ABCDE12345.com.example.app`; App Group names have none.
    static func teamPrefix(_ accessGroup: String) -> String? {
        guard let prefix = accessGroup.split(separator: ".", maxSplits: 1).first, prefix.count == 10,
              prefix.allSatisfy({ $0.isASCII && ($0.isUppercase || $0.isNumber) }) else { return nil }
        return String(prefix)
    }

    /// Summarizes one item from its attribute dictionary (keys as SecItem returns them: agrp, svce, acct, srvr, labl, atag, sync).
    static func summary(of attributes: [String: Any], itemClass: String) -> KeychainItemSummary {
        func text(_ key: String) -> String? { attributes[key] as? String }
        let label: String = switch itemClass {
        case "generic password": [text("svce"), text("acct")].compactMap { $0 }.joined(separator: " · ")
        case "internet password": [text("srvr"), text("acct")].compactMap { $0 }.joined(separator: " · ")
        default: text("labl") ?? (attributes["atag"] as? Data).map { String(decoding: $0, as: UTF8.self) } ?? ""
        }
        return KeychainItemSummary(itemClass: itemClass, accessGroup: text("agrp") ?? "unknown group",
                                   label: label.isEmpty ? "unnamed" : label, synchronizable: (attributes["sync"] as? Bool) ?? false)
    }

    static func listing(_ groups: [KeychainGroupSummary], failures: [String]) -> KeychainSharingReport {
        let lines = groups.flatMap { group in
            ["\(group.accessGroup) — \(group.items.isEmpty ? "no items" : "\(group.items.count) item\(group.items.count == 1 ? "" : "s")")"]
                + group.items.map { "  \($0.itemClass) · \($0.label)\($0.synchronizable ? " · iCloud" : "")" }
        }
        return KeychainSharingReport(text: (["Items this app can see, per access group (attributes only, no data read):"] + lines + failures).joined(separator: "\n"),
                                     isError: !failures.isEmpty)
    }

    /// Groups items by access group; the known groups appear even when they hold nothing.
    static func grouped(_ items: [KeychainItemSummary], knownGroups: [String]) -> [KeychainGroupSummary] {
        let byGroup = Dictionary(grouping: items, by: \.accessGroup)
        let names = Set(byGroup.keys).union(knownGroups)
        return names.sorted().map { name in
            KeychainGroupSummary(accessGroup: name, items: (byGroup[name] ?? []).sorted { ($0.itemClass, $0.label) < ($1.itemClass, $1.label) })
        }
    }

    #if canImport(Security)
    // MARK: Keychain calls

    /// Adds and removes a probe item without an access group; the attributes the system returns name the default group.
    static func probeDefaultAccessGroup() -> (group: String?, status: OSStatus) {
        var probe = base(service: service + ".probe", account: "probe")
        SecItemDelete(probe as CFDictionary)
        probe[kSecValueData as String] = Data()
        probe[kSecReturnAttributes as String] = true
        var result: CFTypeRef?
        let status = SecItemAdd(probe as CFDictionary, &result)
        SecItemDelete(base(service: service + ".probe", account: "probe") as CFDictionary)
        return ((result as? [String: Any])?[kSecAttrAccessGroup as String] as? String, status)
    }

    static func save(_ value: String, accessGroup: String?, synchronizable: Bool) -> KeychainSharingReport {
        var query = base(service: service, account: account)
        if let accessGroup { query[kSecAttrAccessGroup as String] = accessGroup }
        var delete = query
        delete[kSecAttrSynchronizable as String] = kSecAttrSynchronizableAny
        SecItemDelete(delete as CFDictionary)
        var add = query
        add[kSecValueData as String] = Data(value.utf8)
        add[kSecAttrSynchronizable as String] = synchronizable
        // Synchronizable items cannot use a …ThisDeviceOnly class; local items stay on this device.
        add[kSecAttrAccessible as String] = synchronizable ? kSecAttrAccessibleAfterFirstUnlock : kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        add[kSecReturnAttributes as String] = true
        var result: CFTypeRef?
        let status = SecItemAdd(add as CFDictionary, &result)
        var lines = ["Save in \(accessGroup ?? "the default access group"): \(KeychainStatus.describe(status))"]
        if let attributes = result as? [String: Any] {
            lines.append("Stored in access group: \(attributes[kSecAttrAccessGroup as String] as? String ?? "not reported")")
            lines.append("Synchronizable: \((attributes[kSecAttrSynchronizable as String] as? Bool) == true ? "yes" : "no") · accessible: \(synchronizable ? "after first unlock" : "after first unlock, this device only")")
        }
        lines += notes(for: status, accessGroup: accessGroup, synchronizable: synchronizable)
        return KeychainSharingReport(text: lines.joined(separator: "\n"), isError: status != errSecSuccess)
    }

    static func read(accessGroup: String?) -> KeychainSharingReport {
        var query = base(service: service, account: account)
        if let accessGroup { query[kSecAttrAccessGroup as String] = accessGroup }
        query[kSecAttrSynchronizable as String] = kSecAttrSynchronizableAny
        query[kSecReturnData as String] = true
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        var lines = ["Read from \(accessGroup ?? "any group"): \(KeychainStatus.describe(status))"]
        if let attributes = result as? [String: Any] {
            let value = (attributes[kSecValueData as String] as? Data).map { String(decoding: $0, as: UTF8.self) } ?? "<no data>"
            lines += [
                "Value: \(value)",
                "Access group: \(attributes[kSecAttrAccessGroup as String] as? String ?? "not reported")",
                "Synchronizable: \((attributes[kSecAttrSynchronizable as String] as? Bool) == true ? "yes (iCloud Keychain)" : "no (this device)")",
                "Modified: \((attributes[kSecAttrModificationDate as String] as? Date)?.formatted(date: .abbreviated, time: .standard) ?? "unknown")",
            ]
        }
        lines += notes(for: status, accessGroup: accessGroup, synchronizable: false)
        return KeychainSharingReport(text: lines.joined(separator: "\n"), isError: status != errSecSuccess)
    }

    static func delete(accessGroup: String?) -> KeychainSharingReport {
        var query = base(service: service, account: account)
        if let accessGroup { query[kSecAttrAccessGroup as String] = accessGroup }
        query[kSecAttrSynchronizable as String] = kSecAttrSynchronizableAny
        let status = SecItemDelete(query as CFDictionary)
        let text = (["Delete from \(accessGroup ?? "any group"): \(KeychainStatus.describe(status))"]
                    + notes(for: status, accessGroup: accessGroup, synchronizable: false)).joined(separator: "\n")
        return KeychainSharingReport(text: text, isError: status != errSecSuccess)
    }

    /// Attributes only (never data), so access-controlled items are listed without an authentication prompt.
    static func listItems() -> (items: [KeychainItemSummary], statuses: [String]) {
        let classes: [(CFString, String)] = [(kSecClassGenericPassword, "generic password"), (kSecClassInternetPassword, "internet password"),
                                             (kSecClassKey, "key"), (kSecClassCertificate, "certificate")]
        var items: [KeychainItemSummary] = []
        var statuses: [String] = []
        for (itemClass, name) in classes {
            var query: [String: Any] = [kSecClass as String: itemClass, kSecMatchLimit as String: kSecMatchLimitAll,
                                        kSecReturnAttributes as String: true, kSecAttrSynchronizable as String: kSecAttrSynchronizableAny]
            #if os(macOS)
            query[kSecUseDataProtectionKeychain as String] = true
            #endif
            var result: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &result)
            if status == errSecSuccess, let found = result as? [[String: Any]] {
                items += found.map { summary(of: $0, itemClass: name) }
            } else if status != errSecItemNotFound {
                statuses.append("\(name): \(KeychainStatus.describe(status))")
            }
        }
        return (items, statuses)
    }

    private static func base(service: String, account: String) -> [String: Any] {
        var query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
        #if os(macOS)
        // Access groups and synchronizable items only exist in the data protection keychain on macOS.
        query[kSecUseDataProtectionKeychain as String] = true
        #endif
        return query
    }

    private static func notes(for status: OSStatus, accessGroup: String?, synchronizable: Bool) -> [String] {
        var notes: [String] = []
        if status == errSecMissingEntitlement {
            notes.append("This build's keychain-access-groups (or application-groups) entitlement does not list \(accessGroup ?? "this group"), so the system refuses to touch it. Add it under Signing & Capabilities › Keychain Sharing.")
        }
        if status == errSecSuccess, let accessGroup, accessGroup.hasSuffix(KeychainAccessGroupOption.sharedGroupSuffix) || accessGroup.hasPrefix("group.") {
            notes.append("Every app of the same team whose entitlements list \(accessGroup) can read and change this item.")
        }
        if status == errSecSuccess && synchronizable {
            notes.append("Marked for iCloud Keychain. It only leaves this device if the person turned on iCloud Keychain (Passwords & Keychain in iCloud settings); apps cannot read that switch, so this lab cannot confirm the upload. On another device with the same Apple Account and this app, Read finds the item once it has synced.")
        }
        return notes
    }
    #endif
}

/// Keychain Sharing and iCloud Keychain lab (spec §8, secure storage).
@MainActor
final class KeychainSharingExperimentService: ObservableObject {
    @Published var group = KeychainAccessGroupOption.shared
    @Published var synchronizable = false
    @Published var value = "Shared secret from Apple Toolbox"
    @Published private(set) var defaultGroup: String?
    @Published private(set) var groupSummary = "Not checked yet."
    @Published private(set) var output: String
    @Published private(set) var isError = false
    @Published private(set) var isRunning = false

    init(initialOutput: String) {
        output = initialOutput
    }

    /// Names the default group (via a probe item) and the groups the entitlements declare.
    func inspect() {
        #if canImport(Security)
        run(update: { [weak self] probe in
            self?.defaultGroup = probe.group
            self?.groupSummary = Self.groupSummary(defaultGroup: probe.group, probeStatus: probe.status)
        }) { KeychainSharingStore.probeDefaultAccessGroup() }
        #else
        groupSummary = "The Keychain is not available on this platform."
        #endif
    }

    /// Saves without kSecAttrAccessGroup for the default option, so the result shows where the system puts such items.
    func save() {
        #if canImport(Security)
        let value = value, synchronizable = synchronizable, omitGroup = group == .appDefault
        withAccessGroup { KeychainSharingStore.save(value, accessGroup: omitGroup ? nil : $0, synchronizable: synchronizable) }
        #endif
    }

    func read() {
        #if canImport(Security)
        withAccessGroup { KeychainSharingStore.read(accessGroup: $0) }
        #endif
    }

    func delete() {
        #if canImport(Security)
        withAccessGroup { KeychainSharingStore.delete(accessGroup: $0) }
        #endif
    }

    /// Lists every item the app can see, grouped by access group.
    func listItems() {
        #if canImport(Security)
        let known = KeychainAccessGroupOption.allCases.compactMap { $0.accessGroup(defaultGroup: defaultGroup) }
        run(update: { [weak self] (report: KeychainSharingReport) in self?.finish(report.text, isError: report.isError) }) {
            let (items, failures) = KeychainSharingStore.listItems()
            return KeychainSharingStore.listing(KeychainSharingStore.grouped(items, knownGroups: known), failures: failures)
        }
        #endif
    }

    /// Resolves the chosen group; the default option may stay unnamed (nil) before the probe ran, the shared one may not.
    private func withAccessGroup(_ operation: @escaping @Sendable (String?) -> KeychainSharingReport) {
        let accessGroup = group.accessGroup(defaultGroup: defaultGroup)
        guard accessGroup != nil || group == .appDefault else {
            return finish("The shared group is named after the team prefix, which comes from the default access group. Run “Check Access Groups” first.", isError: true)
        }
        run(update: { [weak self] (report: KeychainSharingReport) in self?.finish(report.text, isError: report.isError) }) { operation(accessGroup) }
    }

    /// Runs a Keychain call off the main actor (SecItem calls can block) and applies the Sendable result on it.
    private func run<Value: Sendable>(update: @escaping @MainActor (Value) -> Void, _ operation: @escaping @Sendable () -> Value) {
        isRunning = true
        Task {
            let value = await Task.detached(priority: .userInitiated, operation: operation).value
            isRunning = false
            update(value)
        }
    }

    private func finish(_ text: String, isError: Bool) {
        output = text
        self.isError = isError
    }

    private static func groupSummary(defaultGroup: String?, probeStatus: OSStatus) -> String {
        let entitlement = IdentityEntitlements.summary(of: IdentityEntitlements.state(ofCapability: "keychain-sharing"), key: "keychain-access-groups")
        guard let defaultGroup else {
            return "Default access group: unknown (probe item: \(KeychainStatus.describe(probeStatus)))\n\(entitlement)"
        }
        let prefix = KeychainSharingStore.teamPrefix(defaultGroup)
        return [
            "Default access group: \(defaultGroup)",
            "Team prefix: \(prefix ?? "not found")",
            "Shared group: \(KeychainAccessGroupOption.shared.accessGroup(defaultGroup: defaultGroup) ?? "cannot be named without a team prefix")",
            "App Group: \(KeychainAccessGroupOption.appGroupIdentifier)",
            entitlement,
        ].joined(separator: "\n")
    }
}
