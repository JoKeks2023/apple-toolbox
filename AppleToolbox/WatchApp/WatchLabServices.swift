import Foundation
import Combine
import WatchKit

struct WatchInfoRow: Identifiable, Equatable {
    let title: String
    let value: String
    var id: String { title }
}

struct WatchInfoSection: Identifiable, Equatable {
    let title: String
    let rows: [WatchInfoRow]
    var footer: String?
    var id: String { title }
}

/// Reads `WKInterfaceDevice`. Battery values are only reported while battery monitoring is enabled,
/// so monitoring is switched on only while the Device screen is visible.
@MainActor
final class WatchDeviceService: ObservableObject {
    @Published private(set) var sections: [WatchInfoSection] = []
    @Published private(set) var isMonitoring = false
    private var refreshTask: Task<Void, Never>?

    init() {
        sections = Self.read(monitoring: false)
    }

    func start() {
        guard refreshTask == nil else { return }
        WKInterfaceDevice.current().isBatteryMonitoringEnabled = true
        isMonitoring = true
        // WatchKit posts no battery notifications, so the values are re-read while the screen is visible.
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.refresh()
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    func stop() {
        refreshTask?.cancel()
        refreshTask = nil
        WKInterfaceDevice.current().isBatteryMonitoringEnabled = false
        isMonitoring = false
        refresh()
    }

    private func refresh() {
        sections = Self.read(monitoring: isMonitoring)
    }

    private static func read(monitoring: Bool) -> [WatchInfoSection] {
        let device = WKInterfaceDevice.current()
        let bounds = device.screenBounds, scale = device.screenScale
        let model = device.localizedModel == device.model ? device.model : "\(device.model) (\(device.localizedModel))"
        return [
            WatchInfoSection(title: "Device", rows: [
                WatchInfoRow(title: "Name", value: device.name),
                WatchInfoRow(title: "Model", value: model),
                WatchInfoRow(title: "System", value: "\(device.systemName) \(device.systemVersion)"),
                WatchInfoRow(title: "Audio streaming", value: device.supportsAudioStreaming ? "Supported" : "Not supported")
            ]),
            WatchInfoSection(title: "Screen", rows: [
                WatchInfoRow(title: "Size", value: "\(Int(bounds.width)) × \(Int(bounds.height)) pt"),
                WatchInfoRow(title: "Pixels", value: "\(Int(bounds.width * scale)) × \(Int(bounds.height * scale)) px"),
                WatchInfoRow(title: "Scale", value: "\(Double(scale).formatted())×"),
                WatchInfoRow(title: "Text size", value: device.preferredContentSizeCategory.replacingOccurrences(of: "UICTContentSizeCategory", with: ""))
            ]),
            WatchInfoSection(title: "Battery", rows: batteryRows(device, monitoring: monitoring),
                             footer: "Battery monitoring is on only while this screen is visible."),
            WatchInfoSection(title: "Wrist", rows: [
                WatchInfoRow(title: "Worn on", value: device.wristLocation == .left ? "Left wrist" : "Right wrist"),
                WatchInfoRow(title: "Digital Crown", value: device.crownOrientation == .left ? "Left side" : "Right side"),
                WatchInfoRow(title: "Water resistance", value: waterResistance(device.waterResistanceRating)),
                WatchInfoRow(title: "Water Lock", value: device.isWaterLockEnabled ? "On" : "Off")
            ], footer: "Wrist and crown come from the watch orientation setting. Only an app with an active workout or location session may turn on Water Lock, so this lab only reads it.")
        ]
    }

    private static func batteryRows(_ device: WKInterfaceDevice, monitoring: Bool) -> [WatchInfoRow] {
        guard monitoring else { return [WatchInfoRow(title: "Monitoring", value: "Off")] }
        let level = device.batteryLevel
        let state: String = switch device.batteryState {
        case .unplugged: "On battery"
        case .charging: "Charging"
        case .full: "Full"
        case .unknown: "Unknown"
        @unknown default: "Unknown"
        }
        return [
            WatchInfoRow(title: "Level", value: level < 0 ? "Unknown" : Double(level).formatted(.percent.precision(.fractionLength(0)))),
            WatchInfoRow(title: "State", value: state)
        ]
    }

    private static func waterResistance(_ rating: WKWaterResistanceRating) -> String {
        switch rating {
        case .ipx7: "IPX7 (splash resistant)"
        case .wr50: "WR50 (swimproof)"
        case .wr100: "WR100 (100 m)"
        @unknown default: "Unknown rating"
        }
    }
}

/// Plays the system haptics WatchKit exposes. `play(_:)` returns nothing, so there is no delivery result to report.
enum WatchHaptics {
    static let all: [WKHapticType] = [
        .notification, .directionUp, .directionDown, .success, .failure, .retry, .start, .stop, .click,
        .navigationLeftTurn, .navigationRightTurn, .navigationGenericManeuver, .underwaterDepthPrompt, .underwaterDepthCriticalPrompt
    ]

    @MainActor
    static func play(_ type: WKHapticType) -> String {
        WKInterfaceDevice.current().play(type)
        #if targetEnvironment(simulator)
        return "Requested “\(type.title)”. The Simulator has no Taptic Engine, so nothing is felt."
        #else
        return "Requested “\(type.title)” from WatchKit. It reports no result; you should feel it on your wrist now."
        #endif
    }
}

extension WKHapticType {
    var title: String {
        switch self {
        case .notification: "Notification"
        case .directionUp: "Direction Up"
        case .directionDown: "Direction Down"
        case .success: "Success"
        case .failure: "Failure"
        case .retry: "Retry"
        case .start: "Start"
        case .stop: "Stop"
        case .click: "Click"
        case .navigationLeftTurn: "Left Turn"
        case .navigationRightTurn: "Right Turn"
        case .navigationGenericManeuver: "Maneuver"
        case .underwaterDepthPrompt: "Depth Prompt"
        case .underwaterDepthCriticalPrompt: "Critical Depth"
        @unknown default: "Haptic \(rawValue)"
        }
    }

    var purpose: String {
        switch self {
        case .notification: "Tells the wearer that something needs attention."
        case .directionUp: "Signals that a value went up."
        case .directionDown: "Signals that a value went down."
        case .success: "Confirms that an action completed."
        case .failure: "Signals that an action failed."
        case .retry: "Asks the wearer to try again."
        case .start: "Marks the start of an activity, like a timer."
        case .stop: "Marks the end of an activity."
        case .click: "A subtle tick, for example while turning a dial."
        case .navigationLeftTurn: "Turn-by-turn cue for a left turn."
        case .navigationRightTurn: "Turn-by-turn cue for a right turn."
        case .navigationGenericManeuver: "Turn-by-turn cue for any other maneuver."
        case .underwaterDepthPrompt: "Depth alert for underwater activities."
        case .underwaterDepthCriticalPrompt: "Critical depth alert for underwater activities."
        @unknown default: "A system haptic."
        }
    }
}
