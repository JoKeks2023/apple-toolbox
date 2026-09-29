import Foundation
import Combine
#if canImport(PassKit) && os(iOS)
import PassKit
#endif

// MARK: pass.json model

/// The five pass styles; the key names the top-level dictionary that holds the fields in pass.json.
nonisolated enum WalletPassStyle: String, CaseIterable, Identifiable, Sendable {
    case boardingPass, coupon, eventTicket, storeCard, generic
    var id: String { rawValue }

    var title: String {
        switch self {
        case .boardingPass: "Boarding pass"
        case .coupon: "Coupon"
        case .eventTicket: "Event ticket"
        case .storeCard: "Store card"
        case .generic: "Generic"
        }
    }
}

/// `transitType` values for boarding passes (required there, ignored elsewhere).
nonisolated enum WalletTransitType: String, CaseIterable, Identifiable, Sendable {
    case air = "PKTransitTypeAir", train = "PKTransitTypeTrain", bus = "PKTransitTypeBus", boat = "PKTransitTypeBoat", generic = "PKTransitTypeGeneric"
    var id: String { rawValue }

    var title: String {
        switch self {
        case .air: "Air"
        case .train: "Train"
        case .bus: "Bus"
        case .boat: "Boat"
        case .generic: "Generic"
        }
    }
}

/// Everything the creator puts into pass.json.
nonisolated struct WalletPassDraft: Sendable {
    var style: WalletPassStyle = .generic
    var transitType: WalletTransitType = .air
    var passName = "Apple Toolbox Pass"
    var organizationName = "Apple Toolbox"
    var serialNumber = "toolbox-001"
    var includeLocation = false
    var latitude = 37.3349
    var longitude = -122.0090
    var includeBeacon = false
    var beaconUUID = ""
    var beaconMajor = 1
    var beaconMinor = 1
    var includeRelevantDate = false
    var relevantDate = Date()
}

nonisolated enum WalletPassJSON {
    /// Why webServiceURL and nfc are left out of the draft.
    static let serverOnlyKeys = """
    Not included (needs infrastructure Apple Toolbox cannot fake):
    • webServiceURL + authenticationToken: a server implementing the PassKit Web Service API (register devices, return updated signed passes, receive APNs pushes for the pass type ID).
    • nfc (message, encryptionPublicKey): Apple must approve NFC-enabled passes and issue an NFC pass certificate; readers need the matching private key (Value Added Services).
    """

    /// Problems that make the draft invalid pass.json; empty when it is fine.
    static func issues(_ draft: WalletPassDraft) -> [String] {
        var issues: [String] = []
        if draft.serialNumber.trimmingCharacters(in: .whitespaces).isEmpty { issues.append("serialNumber must not be empty.") }
        if draft.passName.trimmingCharacters(in: .whitespaces).isEmpty { issues.append("description (pass name) must not be empty.") }
        if draft.includeLocation, !(-90...90).contains(draft.latitude) || !(-180...180).contains(draft.longitude) {
            issues.append("Location coordinates are out of range.")
        }
        if draft.includeBeacon {
            if UUID(uuidString: draft.beaconUUID) == nil { issues.append("Beacon proximityUUID is not a UUID.") }
            if !(0...65535).contains(draft.beaconMajor) || !(0...65535).contains(draft.beaconMinor) { issues.append("Beacon major/minor must be 0–65535.") }
        }
        return issues
    }

    static func build(_ draft: WalletPassDraft) -> [String: Any] {
        var pass: [String: Any] = [
            "formatVersion": 1,
            "passTypeIdentifier": "pass.example.replace-with-your-pass-type-id",
            "serialNumber": draft.serialNumber,
            "teamIdentifier": "REPLACE_WITH_TEAM_IDENTIFIER",
            "organizationName": draft.organizationName,
            "description": draft.passName,
            "logoText": draft.organizationName,
            "foregroundColor": "rgb(255,255,255)",
            "backgroundColor": "rgb(35,35,40)",
            "labelColor": "rgb(180,180,190)",
            "barcodes": [["format": "PKBarcodeFormatQR", "message": draft.serialNumber, "messageEncoding": "iso-8859-1", "altText": draft.serialNumber]],
            draft.style.rawValue: structure(draft),
        ]
        if draft.includeLocation {
            pass["locations"] = [["latitude": draft.latitude, "longitude": draft.longitude, "relevantText": "You are near \(draft.organizationName)."]]
        }
        if draft.includeBeacon {
            pass["beacons"] = [["proximityUUID": draft.beaconUUID.uppercased(), "major": draft.beaconMajor, "minor": draft.beaconMinor,
                                "relevantText": "\(draft.passName) is nearby."]]
        }
        if draft.includeRelevantDate {
            pass["relevantDate"] = ISO8601DateFormatter().string(from: draft.relevantDate)
        }
        return pass
    }

    /// The field layout Wallet expects for each style (header, primary, secondary, auxiliary, back).
    static func structure(_ draft: WalletPassDraft) -> [String: Any] {
        let name = draft.passName, org = draft.organizationName, serial = draft.serialNumber
        var structure: [String: Any]
        switch draft.style {
        case .boardingPass:
            structure = [
                "transitType": draft.transitType.rawValue,
                "headerFields": [field("gate", "GATE", "A1")],
                "primaryFields": [field("origin", "FROM", "SFO"), field("destination", "TO", "JFK")],
                "secondaryFields": [field("passenger", "PASSENGER", name)],
                "auxiliaryFields": [field("seat", "SEAT", "12A"), field("boarding", "BOARDING", "08:15")],
            ]
        case .coupon:
            structure = [
                "primaryFields": [field("offer", "OFFER", name)],
                "secondaryFields": [field("merchant", "MERCHANT", org)],
                "auxiliaryFields": [field("code", "CODE", serial)],
            ]
        case .eventTicket:
            structure = [
                "headerFields": [field("row", "ROW", "7")],
                "primaryFields": [field("event", "EVENT", name)],
                "secondaryFields": [field("venue", "VENUE", org)],
                "auxiliaryFields": [field("seat", "SEAT", "14")],
            ]
        case .storeCard:
            structure = [
                "headerFields": [field("balance", "BALANCE", "0.00")],
                "primaryFields": [field("member", "MEMBER", name)],
                "secondaryFields": [field("store", "STORE", org)],
                "auxiliaryFields": [field("number", "CARD NUMBER", serial)],
            ]
        case .generic:
            structure = [
                "primaryFields": [field("name", "PASS", name)],
                "secondaryFields": [field("organization", "ORGANIZATION", org)],
                "auxiliaryFields": [field("serial", "SERIAL", serial)],
            ]
        }
        structure["backFields"] = [field("about", "ABOUT", "Draft created by Apple Toolbox. Sign it with your Pass Type ID certificate to install it.")]
        return structure
    }

    private static func field(_ key: String, _ label: String, _ value: String) -> [String: String] {
        ["key": key, "label": label, "value": value]
    }
}

// MARK: Service

nonisolated struct PassLibraryChange: Identifiable, Equatable, Sendable {
    let id = UUID()
    let date: Date
    let summary: String
}

@MainActor
final class WalletPassCreatorService: ObservableObject {
    @Published var style: WalletPassStyle = .generic
    @Published var transitType: WalletTransitType = .air
    @Published var passName = "Apple Toolbox Pass"
    @Published var organizationName = "Apple Toolbox"
    @Published var serialNumber = "toolbox-001"
    @Published var includeLocation = false
    @Published var latitude = 37.3349
    @Published var longitude = -122.0090
    @Published var includeBeacon = false
    @Published var beaconUUID = ""
    @Published var beaconMajor = 1
    @Published var beaconMinor = 1
    @Published var includeRelevantDate = false
    @Published var relevantDate = Date().addingTimeInterval(3600)
    @Published private(set) var output = "No Wallet pass draft created yet."
    @Published private(set) var isError = false
    @Published private(set) var draftURL: URL?
    @Published private(set) var isObserving = false
    @Published private(set) var libraryChanges: [PassLibraryChange] = []
    private var observer: NSObjectProtocol?
    #if canImport(PassKit) && os(iOS)
    private var library: PKPassLibrary?
    #endif

    var draft: WalletPassDraft {
        WalletPassDraft(style: style, transitType: transitType, passName: passName, organizationName: organizationName, serialNumber: serialNumber,
                        includeLocation: includeLocation, latitude: latitude, longitude: longitude, includeBeacon: includeBeacon, beaconUUID: beaconUUID,
                        beaconMajor: beaconMajor, beaconMinor: beaconMinor, includeRelevantDate: includeRelevantDate, relevantDate: relevantDate)
    }

    func createDraft() {
        let draft = draft
        let issues = WalletPassJSON.issues(draft)
        guard issues.isEmpty else {
            isError = true
            draftURL = nil
            output = "Could not create the draft:\n" + issues.map { "• \($0)" }.joined(separator: "\n")
            return
        }
        do {
            let data = try JSONSerialization.data(withJSONObject: WalletPassJSON.build(draft), options: [.prettyPrinted, .sortedKeys])
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("apple-toolbox-pass-draft.json")
            try data.write(to: url, options: .atomic)
            draftURL = url
            isError = false
            output = "\(draft.style.title) draft created.\n\(url.path)\n\nThis is valid pass.json content, but it is not installable yet. Apple Wallet requires a signed .pkpass package (manifest.json + signature from a Pass Type ID certificate, plus icon.png).\n\n\(WalletPassJSON.serverOnlyKeys)"
        } catch {
            isError = true
            output = "Could not create Wallet pass draft: \(error.localizedDescription)"
            draftURL = nil
        }
    }

    /// Observes PKPassLibraryDidChange. Wallet only reports passes whose pass type IDs this app's team may access.
    func startObserving() {
        #if canImport(PassKit) && os(iOS)
        guard observer == nil else { return }
        guard PKPassLibrary.isPassLibraryAvailable() else {
            isError = true
            output = "PKPassLibrary.isPassLibraryAvailable() is false; there are no library changes to observe."
            return
        }
        let library = PKPassLibrary()
        self.library = library
        observer = NotificationCenter.default.addObserver(forName: Notification.Name(PKPassLibraryNotificationName.PKPassLibraryDidChange.rawValue), object: library, queue: .main) { @Sendable [weak self] notification in
            let summary = Self.summarize(notification.userInfo)
            Task { @MainActor in self?.record(summary) }
        }
        isObserving = true
        let visible = library.passes().count
        record("Observing PKPassLibraryDidChange. \(visible) pass(es) are visible to this app; changes to passes of other issuers are not reported.")
        #else
        isError = true
        output = "PKPassLibraryDidChangeNotification exists on iPhone and iPad (and watchOS) only; macOS Wallet does not post it."
        #endif
    }

    func stopObserving() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        #if canImport(PassKit) && os(iOS)
        library = nil
        #endif
        isObserving = false
    }

    private func record(_ summary: String) {
        libraryChanges.insert(PassLibraryChange(date: Date(), summary: summary), at: 0)
        if libraryChanges.count > 50 { libraryChanges.removeLast() }
    }

    #if canImport(PassKit) && os(iOS)
    nonisolated private static func summarize(_ info: [AnyHashable: Any]?) -> String {
        func names(_ key: PKPassLibraryNotificationKey) -> [String] {
            (info?[key.rawValue] as? [PKPass])?.map { "\($0.localizedName) (\($0.serialNumber))" } ?? []
        }
        let added = names(.addedPassesUserInfoKey), replaced = names(.replacementPassesUserInfoKey)
        let removed = (info?[PKPassLibraryNotificationKey.removedPassInfosUserInfoKey.rawValue] as? [[String: Any]])?.map {
            "\($0[PKPassLibraryNotificationKey.passTypeIdentifierUserInfoKey.rawValue] as? String ?? "?") / \($0[PKPassLibraryNotificationKey.serialNumberUserInfoKey.rawValue] as? String ?? "?")"
        } ?? []
        var parts: [String] = []
        if !added.isEmpty { parts.append("Added: " + added.joined(separator: ", ")) }
        if !replaced.isEmpty { parts.append("Replaced: " + replaced.joined(separator: ", ")) }
        if !removed.isEmpty { parts.append("Removed: " + removed.joined(separator: ", ")) }
        return parts.isEmpty ? "Library changed (no pass details in userInfo)." : parts.joined(separator: "\n")
    }
    #endif
}

#if !os(watchOS)
extension WalletPassCreatorService: StoppableExperiment {
    var isActive: Bool { isObserving }
    func stop() { stopObserving() }
}
#endif
