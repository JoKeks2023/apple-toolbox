import Foundation
import Combine

#if canImport(HomeKit) && !os(macOS)
import HomeKit
import CoreLocation
#endif

// MARK: Snapshot types

/// A property from `HMCharacteristic.properties`.
nonisolated enum HomeCharacteristicProperty: String, CaseIterable, Sendable {
    case readable = "read", writable = "write", notifies = "notify", hidden = "hidden", authorizationData = "auth data"
}

/// The value format from `HMCharacteristicMetadata.format`.
nonisolated enum HomeCharacteristicFormat: String, CaseIterable, Sendable {
    case bool, int, float, string, uint8, uint16, uint32, uint64, data, tlv8, array, dictionary = "dict"

    var isInteger: Bool { [.int, .uint8, .uint16, .uint32, .uint64].contains(self) }
}

/// A characteristic value as HomeKit returned it.
nonisolated enum HomeCharacteristicValue: Equatable, Sendable {
    case bool(Bool), integer(Int), number(Double), text(String), bytes(Int), list(Int), other(String)

    init?(_ value: Any?, format: HomeCharacteristicFormat?) {
        guard let value, !(value is NSNull) else { return nil }
        switch value {
        case let number as NSNumber:
            switch format {
            case .bool: self = .bool(number.boolValue)
            case .float: self = .number(number.doubleValue)
            case let format? where format.isInteger: self = .integer(number.intValue)
            default:
                if CFGetTypeID(number) == CFBooleanGetTypeID() { self = .bool(number.boolValue) }
                else if CFNumberIsFloatType(number as CFNumber) { self = .number(number.doubleValue) }
                else { self = .integer(number.intValue) }
            }
        case let string as String: self = .text(string)
        case let data as Data: self = .bytes(data.count)
        case let array as [Any]: self = .list(array.count)
        default: self = .other(String(describing: value))
        }
    }

    var boolValue: Bool? {
        switch self {
        case .bool(let value): value
        case .integer(let value): value != 0
        default: nil
        }
    }

    var intValue: Int? {
        switch self {
        case .integer(let value): value
        case .bool(let value): value ? 1 : 0
        case .number(let value): Int(value.rounded())
        default: nil
        }
    }

    var doubleValue: Double? {
        switch self {
        case .number(let value): value
        case .integer(let value): Double(value)
        default: nil
        }
    }
}

/// A named value of an enumerated characteristic, e.g. 1 = "Secured" for a lock.
nonisolated struct HomeValueChoice: Identifiable, Hashable, Sendable {
    let value: Int
    let title: String
    var id: Int { value }
}

/// A value the inspector writes; converted to the object HomeKit expects right before the write.
nonisolated enum HomeWriteValue: Equatable, Sendable {
    case bool(Bool), integer(Int), number(Double), text(String)

    var characteristicValue: HomeCharacteristicValue {
        switch self {
        case .bool(let flag): .bool(flag)
        case .integer(let number): .integer(number)
        case .number(let number): .number(number)
        case .text(let text): .text(text)
        }
    }
}

/// The write control a characteristic gets, derived from its format and metadata.
nonisolated enum HomeWriteControl: Equatable, Sendable {
    case toggle
    case choice([HomeValueChoice])
    case slider(minimum: Double, maximum: Double, step: Double)
    /// Evenly spaced float values where no slider exists (tvOS).
    case levels([Double])
    case text(maxLength: Int?)
    case unsupported(String)
}

nonisolated struct HomeCharacteristicInfo: Identifiable, Equatable, Sendable {
    let id: UUID
    let name: String
    /// `characteristicType`, the HomeKit/HAP type UUID.
    let type: String
    let properties: [HomeCharacteristicProperty]
    let format: HomeCharacteristicFormat?
    let rawFormat: String?
    /// Unit symbol, e.g. "%" or "°C".
    let units: String?
    let minimum: Double?
    let maximum: Double?
    let step: Double?
    let maxLength: Int?
    let validValues: [Int]
    let manufacturerDescription: String?
    let value: HomeCharacteristicValue?
    /// Names for the values of well-known enumerated characteristics.
    let namedValues: [HomeValueChoice]
    /// Writes change physical security (locks, doors, alarm systems) and are confirmed first.
    let needsConfirmation: Bool
    let isNotificationEnabled: Bool

    var isReadable: Bool { properties.contains(.readable) }
    var isWritable: Bool { properties.contains(.writable) }
    var supportsNotifications: Bool { properties.contains(.notifies) }
    var valueText: String { HomeInspectorFormat.describe(value, units: units, names: namedValues) }
    var metadataText: String { HomeInspectorFormat.metadata(of: self) }
}

nonisolated struct HomeServiceInfo: Identifiable, Equatable, Sendable {
    let id: UUID
    let name: String
    /// `localizedDescription` of the service type, e.g. "Lightbulb".
    let typeName: String
    let type: String
    let isPrimary: Bool
    let isUserInteractive: Bool
    let linkedServiceCount: Int
    let matterEndpointID: UInt16?
    let characteristics: [HomeCharacteristicInfo]
}

nonisolated struct HomeAccessorySummary: Identifiable, Equatable, Sendable {
    let id: UUID
    let name: String
    let roomID: UUID?
    let roomName: String
    let isReachable: Bool
}

nonisolated struct HomeAccessoryInfo: Identifiable, Equatable, Sendable {
    let id: UUID
    let name: String
    let roomName: String
    let category: String
    let categoryType: String
    let isReachable: Bool
    let isBlocked: Bool
    let isBridged: Bool
    let bridgedAccessoryCount: Int
    let manufacturer: String?
    let model: String?
    let firmwareVersion: String?
    let matterNodeID: UInt64?
    let supportsIdentify: Bool
    let profiles: [String]
    let services: [HomeServiceInfo]
}

nonisolated struct HomeRoomInfo: Identifiable, Equatable, Sendable {
    let id: UUID
    let name: String
    /// `roomForEntireHome()`: accessories that are not assigned to a room.
    let isDefault: Bool
    let accessoryCount: Int
}

nonisolated struct HomeSceneInfo: Identifiable, Equatable, Sendable {
    let id: UUID
    let name: String
    let typeName: String
    let actions: [String]
    let isExecuting: Bool
    let lastExecution: Date?
    let needsConfirmation: Bool
}

nonisolated struct HomeAutomationInfo: Identifiable, Equatable, Sendable {
    let id: UUID
    let name: String
    let kind: String
    let isEnabled: Bool
    /// `HMEventTrigger.triggerActivationState`, which also says why an enabled automation cannot run.
    let activation: String?
    let details: [String]
    let scenes: [String]
}

nonisolated struct HomeInfo: Identifiable, Equatable, Sendable {
    let id: UUID
    let name: String
    let isPrimary: Bool
    let hubState: String
    let rooms: [HomeRoomInfo]
    let accessories: [HomeAccessorySummary]
    let scenes: [HomeSceneInfo]
    let automations: [HomeAutomationInfo]
}

nonisolated struct HomeInspectorEvent: Identifiable, Equatable, Sendable {
    let id = UUID()
    let date: Date
    let title: String
    let detail: String
}

// MARK: Pure formatting

nonisolated enum HomeInspectorFormat {
    static func number(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)).grouping(.never))
    }

    static func describe(_ value: HomeCharacteristicValue?, units: String?, names: [HomeValueChoice] = []) -> String {
        guard let value else { return "—" }
        let suffix = units.map { " \($0)" } ?? ""
        switch value {
        case .bool(let flag): return flag ? "true" : "false"
        case .integer(let number):
            if let name = names.first(where: { $0.value == number }) { return "\(name.title) (\(number))" }
            return "\(number)\(suffix)"
        case .number(let number): return number.formatted(.number.precision(.fractionLength(0...2))) + suffix
        case .text(let text): return "“\(text)”"
        case .bytes(let count): return "\(count) bytes"
        case .list(let count): return "\(count) items"
        case .other(let text): return text
        }
    }

    /// One line with format, units, range, step, length and properties.
    static func metadata(of characteristic: HomeCharacteristicInfo) -> String {
        var parts: [String] = [characteristic.rawFormat ?? "no format"]
        if let units = characteristic.units { parts.append(units) }
        if let minimum = characteristic.minimum, let maximum = characteristic.maximum {
            parts.append("\(number(minimum))…\(number(maximum))")
        } else if let minimum = characteristic.minimum {
            parts.append("≥ \(number(minimum))")
        } else if let maximum = characteristic.maximum {
            parts.append("≤ \(number(maximum))")
        }
        if let step = characteristic.step { parts.append("step \(number(step))") }
        if let maxLength = characteristic.maxLength { parts.append("max \(maxLength) chars") }
        if !characteristic.validValues.isEmpty { parts.append("valid " + characteristic.validValues.map(String.init).joined(separator: ",")) }
        parts.append(characteristic.properties.isEmpty ? "no properties" : characteristic.properties.map(\.rawValue).joined(separator: " "))
        return parts.joined(separator: " · ")
    }

    /// The control used to write a characteristic; nil when it is not writable. Without sliders (tvOS) ranges become
    /// a list of evenly spaced values.
    static func control(for characteristic: HomeCharacteristicInfo, allowsSlider: Bool) -> HomeWriteControl? {
        guard characteristic.isWritable else { return nil }
        guard let format = characteristic.format else {
            return .unsupported("The accessory reports no value format, so the type of value to write is unknown.")
        }
        switch format {
        case .bool: return .toggle
        case .string: return .text(maxLength: characteristic.maxLength)
        case .data, .tlv8, .array, .dictionary:
            return .unsupported("\(format.rawValue) values are structured by the accessory's own protocol; the inspector does not compose them.")
        case .int, .uint8, .uint16, .uint32, .uint64, .float: break
        }
        let names = characteristic.namedValues
        if !characteristic.validValues.isEmpty {
            return .choice(characteristic.validValues.map { choice($0, names: names, units: characteristic.units) })
        }
        guard let minimum = characteristic.minimum, let maximum = characteristic.maximum, maximum > minimum else {
            if format.isInteger, !names.isEmpty { return .choice(names) }
            return .unsupported("The metadata has no minimum and maximum, so there is no safe range to offer.")
        }
        let step = characteristic.step.flatMap { $0 > 0 ? $0 : nil } ?? (format.isInteger ? 1 : (maximum - minimum) / 100)
        let count = Int(((maximum - minimum) / step).rounded()) + 1
        if format.isInteger, count <= 12 {
            return .choice((0..<count).map { choice(Int((minimum + Double($0) * step).rounded()), names: names, units: characteristic.units) })
        }
        if allowsSlider { return .slider(minimum: minimum, maximum: maximum, step: step) }
        var seen = Set<Double>()
        let levels = (0...10).map { index -> Double in
            let raw = minimum + (maximum - minimum) * Double(index) / 10
            return min(maximum, minimum + ((raw - minimum) / step).rounded() * step)
        }.filter { seen.insert($0).inserted }
        if format.isInteger { return .choice(levels.map { choice(Int($0.rounded()), names: names, units: characteristic.units) }) }
        return .levels(levels)
    }

    private static func choice(_ value: Int, names: [HomeValueChoice], units: String?) -> HomeValueChoice {
        if let name = names.first(where: { $0.value == value }) { return HomeValueChoice(value: value, title: "\(name.title) (\(value))") }
        return HomeValueChoice(value: value, title: "\(value)" + (units.map { " \($0)" } ?? ""))
    }

    /// `HMTimerTrigger.recurrence`, e.g. "every day" or "every 2 hours".
    static func recurrence(_ components: DateComponents?) -> String {
        guard let components else { return "once" }
        let units: [(Int?, String)] = [(components.minute, "minute"), (components.hour, "hour"), (components.day, "day"),
                                       (components.weekOfYear, "week"), (components.month, "month")]
        let parts = units.compactMap { value, unit -> String? in
            guard let value, value > 0 else { return nil }
            return value == 1 ? "every \(unit)" : "every \(value) \(unit)s"
        }
        return parts.isEmpty ? "once" : parts.joined(separator: ", ")
    }

    /// `HMEventTrigger.recurrences`: weekday components (1 = Sunday).
    static func weekdays(_ recurrences: [DateComponents]) -> String {
        let symbols = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        let days = Set(recurrences.compactMap(\.weekday)).sorted()
        if days.count == 7 { return "every day" }
        return days.compactMap { (1...7).contains($0) ? symbols[$0 - 1] : nil }.joined(separator: ", ")
    }

    /// Hour and minute of a calendar event, e.g. "07:30".
    static func timeOfDay(_ components: DateComponents) -> String {
        guard let hour = components.hour else { return "any time" }
        let minute = components.minute ?? 0
        return String(format: "%02d:%02d", hour, minute)
    }

    /// Offset of a sunrise/sunset event, e.g. "+30 min" or "−1 h 15 min".
    static func offset(_ components: DateComponents?) -> String {
        let minutes = (components?.hour ?? 0) * 60 + (components?.minute ?? 0)
        guard minutes != 0 else { return "" }
        let sign = minutes > 0 ? "+" : "−"
        let value = abs(minutes)
        let text = value >= 60 ? "\(value / 60) h" + (value % 60 == 0 ? "" : " \(value % 60) min") : "\(value) min"
        return " \(sign)\(text)"
    }

    static func duration(_ seconds: TimeInterval) -> String {
        Duration.seconds(seconds).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .abbreviated))
    }

    static func errorText(_ error: any Error) -> String {
        let error = error as NSError
        return "\(error.localizedDescription) (\(error.domain) \(error.code))"
    }
}

// MARK: HomeKit catalog

/// Mappings that depend on HomeKit's type and format constants.
nonisolated enum HomeCharacteristicCatalog {
    #if canImport(HomeKit) && !os(macOS)
    static func format(_ raw: String?) -> HomeCharacteristicFormat? {
        switch raw {
        case HMCharacteristicMetadataFormatBool: .bool
        case HMCharacteristicMetadataFormatInt: .int
        case HMCharacteristicMetadataFormatFloat: .float
        case HMCharacteristicMetadataFormatString: .string
        case HMCharacteristicMetadataFormatUInt8: .uint8
        case HMCharacteristicMetadataFormatUInt16: .uint16
        case HMCharacteristicMetadataFormatUInt32: .uint32
        case HMCharacteristicMetadataFormatUInt64: .uint64
        case HMCharacteristicMetadataFormatData: .data
        case HMCharacteristicMetadataFormatTLV8: .tlv8
        case HMCharacteristicMetadataFormatArray: .array
        case HMCharacteristicMetadataFormatDictionary: .dictionary
        default: nil
        }
    }

    static func properties(_ raw: [String]) -> [HomeCharacteristicProperty] {
        let map: [(String, HomeCharacteristicProperty)] = [
            (HMCharacteristicPropertyReadable, .readable), (HMCharacteristicPropertyWritable, .writable),
            (HMCharacteristicPropertySupportsEventNotification, .notifies), (HMCharacteristicPropertyHidden, .hidden),
            (HMCharacteristicPropertyRequiresAuthorizationData, .authorizationData),
        ]
        return map.filter { raw.contains($0.0) }.map(\.1)
    }

    static func unitSymbol(_ raw: String?) -> String? {
        switch raw {
        case nil: nil
        case HMCharacteristicMetadataUnitsCelsius: "°C"
        case HMCharacteristicMetadataUnitsFahrenheit: "°F"
        case HMCharacteristicMetadataUnitsPercentage: "%"
        case HMCharacteristicMetadataUnitsArcDegree: "°"
        case HMCharacteristicMetadataUnitsSeconds: "s"
        case HMCharacteristicMetadataUnitsLux: "lx"
        case HMCharacteristicMetadataUnitsPartsPerMillion: "ppm"
        case HMCharacteristicMetadataUnitsMicrogramsPerCubicMeter: "µg/m³"
        default: raw
        }
    }

    /// Value names from the HomeKit Accessory Protocol for common enumerated characteristics.
    static func namedValues(forType type: String) -> [HomeValueChoice] {
        let names: [String] = switch type {
        case HMCharacteristicTypeCurrentLockMechanismState: ["Unsecured", "Secured", "Jammed", "Unknown"]
        case HMCharacteristicTypeTargetLockMechanismState: ["Unsecured", "Secured"]
        case HMCharacteristicTypeCurrentDoorState: ["Open", "Closed", "Opening", "Closing", "Stopped"]
        case HMCharacteristicTypeTargetDoorState: ["Open", "Closed"]
        case HMCharacteristicTypeCurrentHeatingCooling: ["Off", "Heat", "Cool"]
        case HMCharacteristicTypeTargetHeatingCooling: ["Off", "Heat", "Cool", "Auto"]
        case HMCharacteristicTypeCurrentSecuritySystemState: ["Stay arm", "Away arm", "Night arm", "Disarmed", "Alarm triggered"]
        case HMCharacteristicTypeTargetSecuritySystemState: ["Stay arm", "Away arm", "Night arm", "Disarm"]
        case HMCharacteristicTypePositionState: ["Decreasing", "Increasing", "Stopped"]
        case HMCharacteristicTypeTemperatureUnits: ["Celsius", "Fahrenheit"]
        case HMCharacteristicTypeActive: ["Inactive", "Active"]
        case HMCharacteristicTypeContactState: ["Contact detected", "Contact not detected"]
        case HMCharacteristicTypeStatusLowBattery: ["Battery normal", "Battery low"]
        case HMCharacteristicTypeChargingState: ["Not charging", "Charging", "Not chargeable"]
        default: []
        }
        return names.enumerated().map { HomeValueChoice(value: $0.offset, title: $0.element) }
    }

    /// Writes that unlock, open or disarm something are confirmed before they are sent.
    static func needsConfirmation(type: String) -> Bool {
        [HMCharacteristicTypeTargetLockMechanismState, HMCharacteristicTypeTargetDoorState,
         HMCharacteristicTypeTargetSecuritySystemState, HMCharacteristicTypeLockPhysicalControls].contains(type)
    }

    static func sceneTypeName(_ raw: String) -> String {
        switch raw {
        case HMActionSetTypeWakeUp: "Wake up (built-in)"
        case HMActionSetTypeSleep: "Sleep (built-in)"
        case HMActionSetTypeHomeDeparture: "Leave home (built-in)"
        case HMActionSetTypeHomeArrival: "Arrive home (built-in)"
        case HMActionSetTypeUserDefined: "User defined"
        case HMActionSetTypeTriggerOwned: "Owned by an automation"
        default: raw
        }
    }
    #else
    static func format(_ raw: String?) -> HomeCharacteristicFormat? { nil }
    static func properties(_ raw: [String]) -> [HomeCharacteristicProperty] { [] }
    static func unitSymbol(_ raw: String?) -> String? { raw }
    static func namedValues(forType type: String) -> [HomeValueChoice] { [] }
    static func needsConfirmation(type: String) -> Bool { false }
    static func sceneTypeName(_ raw: String) -> String { raw }
    #endif
}

// MARK: Home Inspector

/// Home Inspector (spec §17/§40): homes → rooms → accessories → services → characteristics, reads, writes, live
/// notifications, scenes and automations. HMHomeManager, HMHome and HMAccessory call their delegates on the main
/// queue, so the conformances stay main-actor isolated; completion handlers hop back explicitly.
@MainActor
final class HomeInspectorService: NSObject, ObservableObject {
    @Published private(set) var output: String
    @Published private(set) var isError = false
    @Published private(set) var status: ExperimentStatus = .permissionRequired
    @Published private(set) var homes: [HomeInfo] = []
    @Published private(set) var selectedHomeID: UUID?
    /// nil shows the accessories of every room.
    @Published private(set) var selectedRoomID: UUID?
    @Published private(set) var selectedAccessoryID: UUID?
    @Published private(set) var accessory: HomeAccessoryInfo?
    @Published private(set) var events: [HomeInspectorEvent] = []
    /// Characteristics with a read, write or notification change in flight.
    @Published private(set) var pending: Set<UUID> = []
    @Published private(set) var notifying: Set<UUID> = []
    @Published private(set) var runningScenes: Set<UUID> = []
    @Published private(set) var isLoaded = false

    private var readBatch: (id: UUID, remaining: Int, failures: [String])?
    #if canImport(HomeKit) && !os(macOS)
    /// Created on the first load: instantiating HMHomeManager triggers the HomeKit privacy prompt.
    private var manager: HMHomeManager?
    #endif

    init(initialOutput: String = "Load the homes to inspect accessories, scenes and automations.") {
        output = initialOutput
        super.init()
        #if !canImport(HomeKit) || os(macOS)
        status = .platformUnsupported
        #endif
    }

    var home: HomeInfo? { homes.first { $0.id == selectedHomeID } }

    var filteredAccessories: [HomeAccessorySummary] {
        guard let home else { return [] }
        return home.accessories.filter { selectedRoomID == nil || $0.roomID == selectedRoomID }
    }

    func load() {
        #if canImport(HomeKit) && !os(macOS)
        guard let manager else {
            let manager = HMHomeManager()
            manager.delegate = self
            self.manager = manager
            report("Waiting for HomeKit to load homes…")
            return
        }
        apply(manager, readValues: true)
        #else
        report("HomeKit is not available on this platform.", isError: true)
        #endif
    }

    /// Opens straight into the homes when access was granted before, so it never prompts. Runs once per inspector.
    func loadIfPreviouslyAuthorized() {
        #if canImport(HomeKit) && !os(macOS)
        guard manager == nil, PermissionProbe.homeKit() == .granted else { return }
        load()
        #endif
    }

    func selectHome(_ id: UUID?) {
        selectedHomeID = id
        selectedRoomID = nil
        selectedAccessoryID = nil
        rebuild()
        readAll()
    }

    func selectRoom(_ id: UUID?) {
        selectedRoomID = id
        selectedAccessoryID = nil
        rebuild()
        readAll()
    }

    func selectAccessory(_ id: UUID?) {
        selectedAccessoryID = id
        rebuild()
        readAll()
    }

    func clearEvents() { events = [] }

    private func report(_ text: String, isError: Bool = false) {
        output = text
        self.isError = isError
    }

    private func log(_ title: String, _ detail: String) {
        events.insert(HomeInspectorEvent(date: Date(), title: title, detail: detail), at: 0)
        if events.count > 200 { events.removeLast(events.count - 200) }
    }

    #if canImport(HomeKit) && !os(macOS)
    // MARK: Authorization and snapshots

    /// Applies the authorization state and snapshots the homes. Values are read from the accessory when asked to or
    /// when an accessory is selected for the first time.
    private func apply(_ manager: HMHomeManager, readValues: Bool = false) {
        let authorization = manager.authorizationStatus
        let permission: PermissionState = authorization.contains(.authorized) ? .granted
            : authorization.contains(.restricted) ? .restricted
            : authorization.contains(.determined) ? .denied : .notDetermined
        PermissionProbe.remember(permission, for: .homeKit)
        PermissionCenter.shared.invalidate()
        guard authorization.contains(.authorized) else {
            homes = []
            accessory = nil
            isLoaded = false
            if authorization.contains(.restricted) {
                status = .permissionDenied
                report("HomeKit access is restricted on this device.", isError: true)
            } else if authorization.contains(.determined) {
                status = .permissionDenied
                report("HomeKit access was denied. Allow it in Settings › Privacy & Security › HomeKit.", isError: true)
            } else {
                status = .permissionRequired
                report("HomeKit access has not been decided yet.")
            }
            return
        }
        status = .available
        let hadAccessory = accessory != nil
        isLoaded = true
        rebuild()
        if manager.homes.isEmpty {
            report("HomeKit access granted, but no homes are set up. Create a home in the Home app; for testing, pair simulated accessories from the HomeKit Accessory Simulator (Additional Tools for Xcode) with it.")
        } else {
            let accessories = manager.homes.reduce(0) { $0 + $1.accessories.count }
            report("Found \(manager.homes.count) home(s) with \(accessories) accessory(ies).")
        }
        if readValues || (!hadAccessory && accessory != nil) { readAll() }
    }

    private var selectedHome: HMHome? {
        manager?.homes.first { $0.uniqueIdentifier == selectedHomeID }
    }

    private var selectedAccessory: HMAccessory? {
        selectedHome?.accessories.first { $0.uniqueIdentifier == selectedAccessoryID }
    }

    private func characteristic(_ id: UUID) -> HMCharacteristic? {
        for accessory in selectedHome?.accessories ?? [] {
            for service in accessory.services {
                if let match = service.characteristics.first(where: { $0.uniqueIdentifier == id }) { return match }
            }
        }
        return nil
    }

    /// Rebuilds the value snapshots and keeps the selection valid.
    private func rebuild() {
        guard let manager, isLoaded else { return }
        let hmHomes = manager.homes
        if !hmHomes.contains(where: { $0.uniqueIdentifier == selectedHomeID }) {
            selectedHomeID = (hmHomes.first(where: \.isPrimary) ?? hmHomes.first)?.uniqueIdentifier
            selectedRoomID = nil
            selectedAccessoryID = nil
        }
        hmHomes.forEach { $0.delegate = self }
        homes = hmHomes.map(homeInfo)
        guard let home = selectedHome else { accessory = nil; return }
        let rooms = [home.roomForEntireHome()] + home.rooms
        if let room = selectedRoomID, !rooms.contains(where: { $0.uniqueIdentifier == room }) { selectedRoomID = nil }
        home.accessories.forEach { $0.delegate = self }
        let visible = filteredAccessories
        if !visible.contains(where: { $0.id == selectedAccessoryID }) { selectedAccessoryID = visible.first?.id }
        accessory = selectedAccessory.map(accessoryInfo)
    }

    private func homeInfo(_ home: HMHome) -> HomeInfo {
        let rooms = [home.roomForEntireHome()] + home.rooms
        let defaultRoom = home.roomForEntireHome().uniqueIdentifier
        return HomeInfo(
            id: home.uniqueIdentifier, name: home.name, isPrimary: home.isPrimary, hubState: hubStateName(home.homeHubState),
            rooms: rooms.map { HomeRoomInfo(id: $0.uniqueIdentifier, name: $0.name, isDefault: $0.uniqueIdentifier == defaultRoom, accessoryCount: $0.accessories.count) },
            accessories: home.accessories.map { HomeAccessorySummary(id: $0.uniqueIdentifier, name: $0.name, roomID: $0.room?.uniqueIdentifier, roomName: $0.room?.name ?? "No room", isReachable: $0.isReachable) },
            scenes: home.actionSets.map(sceneInfo),
            automations: home.triggers.map(automationInfo))
    }

    private func hubStateName(_ state: HMHomeHubState) -> String {
        switch state {
        case .notAvailable: "No home hub"
        case .connected: "Home hub connected"
        case .disconnected: "Home hub disconnected"
        @unknown default: "Unknown (\(state.rawValue))"
        }
    }

    private func accessoryInfo(_ accessory: HMAccessory) -> HomeAccessoryInfo {
        HomeAccessoryInfo(
            id: accessory.uniqueIdentifier, name: accessory.name, roomName: accessory.room?.name ?? "No room",
            category: accessory.category.localizedDescription, categoryType: accessory.category.categoryType,
            isReachable: accessory.isReachable, isBlocked: accessory.isBlocked, isBridged: accessory.isBridged,
            bridgedAccessoryCount: accessory.bridgedAccessories.count,
            manufacturer: accessory.manufacturer, model: accessory.model, firmwareVersion: accessory.firmwareVersion,
            matterNodeID: accessory.matterNodeID, supportsIdentify: accessory.supportsIdentify,
            profiles: accessory.profiles.map(profileName),
            services: accessory.services.map(serviceInfo))
    }

    private func profileName(_ profile: HMAccessoryProfile) -> String {
        switch profile {
        case is HMCameraProfile: "Camera"
        case is HMNetworkConfigurationProfile: "Network configuration"
        default: String(describing: type(of: profile))
        }
    }

    private func serviceInfo(_ service: HMService) -> HomeServiceInfo {
        HomeServiceInfo(
            id: service.uniqueIdentifier, name: service.name, typeName: service.localizedDescription, type: service.serviceType,
            isPrimary: service.isPrimaryService, isUserInteractive: service.isUserInteractive,
            linkedServiceCount: service.linkedServices?.count ?? 0, matterEndpointID: service.matterEndpointID,
            characteristics: service.characteristics.map(characteristicInfo))
    }

    private func characteristicInfo(_ characteristic: HMCharacteristic) -> HomeCharacteristicInfo {
        let metadata = characteristic.metadata
        let format = HomeCharacteristicCatalog.format(metadata?.format)
        let type = characteristic.characteristicType
        return HomeCharacteristicInfo(
            id: characteristic.uniqueIdentifier, name: characteristic.localizedDescription, type: type,
            properties: HomeCharacteristicCatalog.properties(characteristic.properties),
            format: format, rawFormat: metadata?.format, units: HomeCharacteristicCatalog.unitSymbol(metadata?.units),
            minimum: metadata?.minimumValue?.doubleValue, maximum: metadata?.maximumValue?.doubleValue,
            step: metadata?.stepValue?.doubleValue, maxLength: metadata?.maxLength?.intValue,
            validValues: metadata?.validValues?.map(\.intValue) ?? [],
            manufacturerDescription: metadata?.manufacturerDescription,
            value: HomeCharacteristicValue(characteristic.value, format: format),
            namedValues: HomeCharacteristicCatalog.namedValues(forType: type),
            needsConfirmation: HomeCharacteristicCatalog.needsConfirmation(type: type),
            isNotificationEnabled: characteristic.isNotificationEnabled)
    }

    private func sceneInfo(_ actionSet: HMActionSet) -> HomeSceneInfo {
        let writes = actionSet.actions.compactMap { $0 as? HMCharacteristicWriteAction<NSCopying> }
        var actions = writes.map { action -> String in
            let characteristic = action.characteristic
            let info = characteristicInfo(characteristic)
            let target = HomeInspectorFormat.describe(HomeCharacteristicValue(action.targetValue, format: info.format), units: info.units, names: info.namedValues)
            return "\(characteristic.service?.accessory?.name ?? "Accessory") · \(characteristic.localizedDescription) → \(target)"
        }.sorted()
        let other = actionSet.actions.count - writes.count
        if other > 0 { actions.append("\(other) other action(s)") }
        return HomeSceneInfo(
            id: actionSet.uniqueIdentifier, name: actionSet.name, typeName: HomeCharacteristicCatalog.sceneTypeName(actionSet.actionSetType),
            actions: actions, isExecuting: actionSet.isExecuting, lastExecution: actionSet.lastExecutionDate,
            needsConfirmation: writes.contains { HomeCharacteristicCatalog.needsConfirmation(type: $0.characteristic.characteristicType) })
    }

    private func automationInfo(_ trigger: HMTrigger) -> HomeAutomationInfo {
        var kind = "Trigger"
        var activation: String?
        var details: [String] = []
        if let timer = trigger as? HMTimerTrigger {
            kind = "Timer"
            details.append("Fires \(timer.fireDate.formatted(date: .abbreviated, time: .shortened)), repeats \(HomeInspectorFormat.recurrence(timer.recurrence))")
        } else if let event = trigger as? HMEventTrigger {
            kind = "Event"
            activation = activationName(event.triggerActivationState)
            details += event.events.map { "When: " + describe($0) }
            details += event.endEvents.map { "Ends: " + describe($0) }
            if let predicate = event.predicate { details.append("Condition: " + predicate.predicateFormat) }
            if let recurrences = event.recurrences, !recurrences.isEmpty { details.append("On: " + HomeInspectorFormat.weekdays(recurrences)) }
            if event.executeOnce { details.append("Runs once, then disables itself") }
        }
        return HomeAutomationInfo(id: trigger.uniqueIdentifier, name: trigger.name, kind: kind, isEnabled: trigger.isEnabled,
                                  activation: activation, details: details, scenes: trigger.actionSets.map(\.name))
    }

    private func activationName(_ state: HMEventTriggerActivationState) -> String {
        switch state {
        case .enabled: "Active"
        case .disabled: "Disabled"
        case .disabledNoHomeHub: "Cannot run: no home hub"
        case .disabledNoCompatibleHomeHub: "Cannot run: home hub does not support it"
        case .disabledNoLocationServicesAuthorization: "Cannot run: location access missing"
        @unknown default: "Unknown (\(state.rawValue))"
        }
    }

    private func describe(_ event: HMEvent) -> String {
        switch event {
        case let event as HMCharacteristicEvent<NSCopying>:
            let info = characteristicInfo(event.characteristic)
            let value = event.triggerValue.map { HomeInspectorFormat.describe(HomeCharacteristicValue($0, format: info.format), units: info.units, names: info.namedValues) }
            return "\(event.characteristic.service?.accessory?.name ?? "Accessory") · \(info.name) " + (value.map { "becomes \($0)" } ?? "changes")
        case let event as HMCharacteristicThresholdRangeEvent:
            let range = event.thresholdRange
            let bounds = [range.minValue.map { "≥ \(HomeInspectorFormat.number($0.doubleValue))" }, range.maxValue.map { "≤ \(HomeInspectorFormat.number($0.doubleValue))" }].compactMap { $0 }
            return "\(event.characteristic.service?.accessory?.name ?? "Accessory") · \(event.characteristic.localizedDescription) \(bounds.joined(separator: " and "))"
        case let event as HMDurationEvent:
            return "After \(HomeInspectorFormat.duration(event.duration))"
        case let event as HMSignificantTimeEvent:
            let name = event.significantEvent == .sunrise ? "Sunrise" : event.significantEvent == .sunset ? "Sunset" : event.significantEvent.rawValue
            return name + HomeInspectorFormat.offset(event.offset)
        case let event as HMCalendarEvent:
            return "At " + HomeInspectorFormat.timeOfDay(event.fireDateComponents)
        case let event as HMPresenceEvent:
            return "\(presenceUserName(event.presenceUserType)): \(presenceEventName(event.presenceEventType))"
        case let event as HMLocationEvent:
            guard let region = event.region else { return "Location event without a region" }
            if let circle = region as? CLCircularRegion {
                return "Location: within \(Int(circle.radius)) m of \(String(format: "%.4f, %.4f", circle.center.latitude, circle.center.longitude))"
            }
            return "Location region \(region.identifier)"
        default:
            return String(describing: type(of: event))
        }
    }

    private func presenceEventName(_ type: HMPresenceEventType) -> String {
        switch type {
        case .everyEntry: "every arrival"
        case .everyExit: "every departure"
        case .firstEntry: "first person arrives"
        case .lastExit: "last person leaves"
        @unknown default: "presence type \(type.rawValue)"
        }
    }

    private func presenceUserName(_ type: HMPresenceEventUserType) -> String {
        switch type {
        case .currentUser: "You"
        case .homeUsers: "Home members"
        case .customUsers: "Selected people"
        @unknown default: "User type \(type.rawValue)"
        }
    }
    #else
    private func rebuild() {}
    #endif

    // MARK: Reads, writes, notifications, scenes

    /// Reads every readable characteristic of the selected accessory from the accessory itself.
    func readAll() {
        #if canImport(HomeKit) && !os(macOS)
        guard let accessory = selectedAccessory else { return }
        let targets = accessory.services.flatMap(\.characteristics).filter { $0.properties.contains(HMCharacteristicPropertyReadable) }
        guard !targets.isEmpty else { return }
        let batch = UUID()
        readBatch = (batch, targets.count, [])
        report("Reading \(targets.count) value(s) from \(accessory.name)…")
        for characteristic in targets {
            let id = characteristic.uniqueIdentifier
            let name = characteristic.localizedDescription
            pending.insert(id)
            characteristic.readValue { @Sendable [weak self] error in
                let failure = error.map { "\(name): \(HomeInspectorFormat.errorText($0))" }
                Task { @MainActor in self?.finishBatchRead(batch: batch, id: id, failure: failure) }
            }
        }
        #endif
    }

    private func finishBatchRead(batch: UUID, id: UUID, failure: String?) {
        pending.remove(id)
        rebuild()
        guard var current = readBatch, current.id == batch else { return }
        current.remaining -= 1
        if let failure { current.failures.append(failure) }
        readBatch = current.remaining > 0 ? current : nil
        guard current.remaining == 0 else { return }
        let name = accessory?.name ?? "the accessory"
        if current.failures.isEmpty {
            report("Read all values of \(name) from the accessory.")
        } else {
            report("Read \(name) with \(current.failures.count) error(s):\n" + current.failures.joined(separator: "\n"), isError: true)
        }
    }

    func read(_ id: UUID) {
        #if canImport(HomeKit) && !os(macOS)
        guard let characteristic = characteristic(id) else { return }
        let name = characteristic.localizedDescription
        pending.insert(id)
        characteristic.readValue { @Sendable [weak self] error in
            let failure = error.map(HomeInspectorFormat.errorText)
            Task { @MainActor in self?.finishRead(id: id, name: name, failure: failure) }
        }
        #endif
    }

    private func finishRead(id: UUID, name: String, failure: String?) {
        pending.remove(id)
        rebuild()
        if let failure { report("Reading \(name) failed: \(failure)", isError: true); return }
        let value = accessory?.services.flatMap(\.characteristics).first { $0.id == id }?.valueText ?? "—"
        report("\(name) = \(value)")
    }

    func write(_ value: HomeWriteValue, to id: UUID) {
        #if canImport(HomeKit) && !os(macOS)
        guard let characteristic = characteristic(id) else { return }
        let name = characteristic.localizedDescription
        let accessoryName = characteristic.service?.accessory?.name ?? "Accessory"
        let object: Any = switch value {
        case .bool(let flag): NSNumber(value: flag)
        case .integer(let number): NSNumber(value: number)
        case .number(let number): NSNumber(value: number)
        case .text(let text): text as NSString
        }
        let text = HomeInspectorFormat.describe(value.characteristicValue, units: nil)
        pending.insert(id)
        report("Writing \(text) to \(accessoryName) · \(name)…")
        characteristic.writeValue(object) { @Sendable [weak self] error in
            let failure = error.map(HomeInspectorFormat.errorText)
            Task { @MainActor in self?.finishWrite(id: id, title: "\(accessoryName) · \(name)", value: text, failure: failure) }
        }
        #endif
    }

    private func finishWrite(id: UUID, title: String, value: String, failure: String?) {
        pending.remove(id)
        rebuild()
        if let failure {
            log(title, "Write \(value) failed: \(failure)")
            report("Writing \(value) to \(title) failed: \(failure)", isError: true)
        } else {
            log(title, "Wrote \(value)")
            report("Wrote \(value) to \(title). The accessory accepted the value.")
        }
    }

    /// Turns change notifications on or off; changes arrive through HMAccessoryDelegate and fill the live change log.
    func setNotifications(_ enabled: Bool, for id: UUID) {
        #if canImport(HomeKit) && !os(macOS)
        guard let characteristic = characteristic(id) else { return }
        let name = characteristic.localizedDescription
        characteristic.service?.accessory?.delegate = self
        pending.insert(id)
        characteristic.enableNotification(enabled) { @Sendable [weak self] error in
            let failure = error.map(HomeInspectorFormat.errorText)
            Task { @MainActor in self?.finishNotification(id: id, name: name, enabled: enabled, failure: failure) }
        }
        #endif
    }

    private func finishNotification(id: UUID, name: String, enabled: Bool, failure: String?) {
        pending.remove(id)
        if let failure {
            report("\(enabled ? "Enabling" : "Disabling") notifications for \(name) failed: \(failure)", isError: true)
        } else {
            if enabled { notifying.insert(id) } else { notifying.remove(id) }
            report(enabled ? "Notifications on for \(name). Changes appear in the live change log while the app is in the foreground." : "Notifications off for \(name).")
        }
        rebuild()
    }

    func runScene(_ id: UUID) {
        #if canImport(HomeKit) && !os(macOS)
        guard let home = selectedHome, let actionSet = home.actionSets.first(where: { $0.uniqueIdentifier == id }) else { return }
        let name = actionSet.name
        runningScenes.insert(id)
        report("Running scene \(name)…")
        home.executeActionSet(actionSet) { @Sendable [weak self] error in
            let failure = error.map(HomeInspectorFormat.errorText)
            Task { @MainActor in self?.finishScene(id: id, name: name, failure: failure) }
        }
        #endif
    }

    private func finishScene(id: UUID, name: String, failure: String?) {
        runningScenes.remove(id)
        rebuild()
        if let failure {
            log("Scene \(name)", "Failed: \(failure)")
            report("Running scene \(name) failed: \(failure)", isError: true)
        } else {
            log("Scene \(name)", "Executed")
            report("Scene \(name) executed.")
        }
    }

    /// Disables every notification this inspector turned on.
    func stopNotifications() {
        #if canImport(HomeKit) && !os(macOS)
        for id in notifying {
            characteristic(id)?.enableNotification(false) { @Sendable _ in }
        }
        #endif
        notifying = []
    }
}

#if canImport(HomeKit) && !os(macOS)
extension HomeInspectorService: HMHomeManagerDelegate {
    func homeManagerDidUpdateHomes(_ manager: HMHomeManager) { apply(manager) }
    func homeManager(_ manager: HMHomeManager, didUpdate status: HMHomeManagerAuthorizationStatus) { apply(manager) }
    func homeManager(_ manager: HMHomeManager, didAdd home: HMHome) { log(home.name, "Home added"); apply(manager) }
    func homeManager(_ manager: HMHomeManager, didRemove home: HMHome) { log(home.name, "Home removed"); apply(manager) }
}

extension HomeInspectorService: HMHomeDelegate {
    func homeDidUpdateName(_ home: HMHome) { rebuild() }
    func home(_ home: HMHome, didAdd accessory: HMAccessory) { log(accessory.name, "Accessory added to \(home.name)"); rebuild() }
    func home(_ home: HMHome, didRemove accessory: HMAccessory) { log(accessory.name, "Accessory removed from \(home.name)"); rebuild() }
    func home(_ home: HMHome, didUpdate room: HMRoom, for accessory: HMAccessory) { log(accessory.name, "Moved to \(room.name)"); rebuild() }
    func home(_ home: HMHome, didAdd room: HMRoom) { rebuild() }
    func home(_ home: HMHome, didRemove room: HMRoom) { rebuild() }
    func home(_ home: HMHome, didAdd actionSet: HMActionSet) { log(actionSet.name, "Scene added"); rebuild() }
    func home(_ home: HMHome, didRemove actionSet: HMActionSet) { log(actionSet.name, "Scene removed"); rebuild() }
    func home(_ home: HMHome, didUpdateActionsFor actionSet: HMActionSet) { rebuild() }
    func home(_ home: HMHome, didAdd trigger: HMTrigger) { log(trigger.name, "Automation added"); rebuild() }
    func home(_ home: HMHome, didRemove trigger: HMTrigger) { log(trigger.name, "Automation removed"); rebuild() }
    func home(_ home: HMHome, didUpdate trigger: HMTrigger) { log(trigger.name, "Automation updated"); rebuild() }
    func home(_ home: HMHome, didUpdate homeHubState: HMHomeHubState) { log(home.name, hubStateName(homeHubState)); rebuild() }
    func home(_ home: HMHome, didEncounterError error: any Error, for accessory: HMAccessory) {
        log(accessory.name, "Error: \(HomeInspectorFormat.errorText(error))")
    }
}

/// HMAccessoryDelegate is a Sendable protocol, so the conformance cannot be main-actor isolated: the callbacks are
/// nonisolated and hop to the main actor (HomeKit delivers them on the main queue anyway).
extension HomeInspectorService: HMAccessoryDelegate {
    nonisolated func accessory(_ accessory: HMAccessory, service: HMService, didUpdateValueFor characteristic: HMCharacteristic) {
        Task { @MainActor in
            let info = self.characteristicInfo(characteristic)
            self.log("\(accessory.name) · \(info.name)", info.valueText)
            self.rebuild()
        }
    }

    nonisolated func accessoryDidUpdateReachability(_ accessory: HMAccessory) {
        Task { @MainActor in
            self.log(accessory.name, accessory.isReachable ? "Reachable" : "Not reachable")
            self.rebuild()
        }
    }

    nonisolated func accessory(_ accessory: HMAccessory, didUpdateFirmwareVersion firmwareVersion: String) {
        Task { @MainActor in
            self.log(accessory.name, "Firmware \(firmwareVersion)")
            self.rebuild()
        }
    }

    nonisolated func accessoryDidUpdateName(_ accessory: HMAccessory) { Task { @MainActor in self.rebuild() } }
    nonisolated func accessoryDidUpdateServices(_ accessory: HMAccessory) { Task { @MainActor in self.rebuild() } }
}
#endif

#if !os(watchOS)
/// Enabled notifications are the live session: leaving the experiment turns them off again.
extension HomeInspectorService: StoppableExperiment {
    var isActive: Bool { !notifying.isEmpty }
    func stop() { stopNotifications() }
}
#endif

// MARK: Matter accessory setup

/// Starts Apple Home's own accessory setup UI, which commissions Matter accessories into a home. The app needs the
/// HomeKit entitlement but no home-data authorization. No setup payload is passed, so the
/// com.apple.developer.matter.allow-setup-payload entitlement is not required.
@MainActor
final class MatterSetupExperimentService: ObservableObject {
    @Published private(set) var output = "Starts Apple Home's setup flow to add a Matter accessory to one of your homes."
    @Published private(set) var isRunning = false
    @Published private(set) var isError = false
    @Published private(set) var homeIdentifier: String?
    @Published private(set) var accessoryIdentifiers: [String] = []
    #if canImport(HomeKit) && os(iOS)
    private var manager: HMAccessorySetupManager?
    #endif

    func startSetup() {
        #if canImport(HomeKit) && os(iOS)
        let manager = HMAccessorySetupManager()
        self.manager = manager
        isRunning = true
        isError = false
        output = "Apple Home setup is open. Scan the accessory's setup code and follow the system steps."
        Task {
            defer { isRunning = false; self.manager = nil }
            do {
                let result = try await manager.performAccessorySetup(using: HMAccessorySetupRequest())
                let home = result.homeUniqueIdentifier.uuidString
                homeIdentifier = home
                accessoryIdentifiers = result.accessoryUniqueIdentifiers.map(\.uuidString)
                output = "Setup finished: \(accessoryIdentifiers.count) accessory(ies) added to home \(home).\nHome Inspector lists them with their services once HomeKit access is granted."
            } catch let error as HMError where error.code == .operationCancelled {
                isError = true
                output = "Setup was cancelled before an accessory was added."
            } catch {
                let nsError = error as NSError
                isError = true
                output = "Setup failed: \(error.localizedDescription)\n\(nsError.domain) code \(nsError.code)"
            }
        }
        #else
        output = "Apple Home accessory setup (HMAccessorySetupManager) is not available on this platform."
        #endif
    }
}

extension ExperimentAvailability {
    /// Apple Home's setup UI needs no home-data authorization, so the HomeKit permission does not gate it.
    static func matterSetup() -> ExperimentStatus {
        #if canImport(HomeKit) && os(iOS)
        if #available(iOS 27.0, *) { return HMAccessorySetupManager.isSupported ? .available : .unavailable }
        return .available
        #else
        return .platformUnsupported
        #endif
    }
}
