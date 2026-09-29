import Foundation
import Combine
#if canImport(GameController) && !os(watchOS)
import GameController
#endif
#if canImport(CoreHaptics) && !os(watchOS)
import CoreHaptics
#endif

extension ExperimentAvailability {
    /// The framework is always present on supported platforms; without a connected controller there is nothing to read.
    static func gameController() -> ExperimentStatus {
        #if canImport(GameController) && !os(watchOS)
        GCController.controllers().isEmpty ? .unavailable : .available
        #else
        .platformUnsupported
        #endif
    }
}

struct GameControllerInfo: Identifiable, Equatable {
    let id: ObjectIdentifier
    let name: String
    let category: String
    let profile: String
    let battery: String
    let haptics: String
    let isCurrent: Bool
}

struct ControllerButtonState: Identifiable, Equatable {
    let id: String
    let name: String
    let symbol: String?
    let value: Float
    let isPressed: Bool
    let isAnalog: Bool
}

struct ControllerStickState: Identifiable, Equatable {
    let id: String
    let name: String
    let x: Float
    let y: Float
}

struct ControllerInputState: Equatable {
    let controllerName: String
    let profile: String
    var buttons: [ControllerButtonState] = []
    var sticks: [ControllerStickState] = []
    var lastChange: String?
}

/// A haptic pattern the experiment plays on a controller (spec §30). Pure description, turned into CHHapticEvents.
enum ControllerHapticPattern: String, CaseIterable, Identifiable {
    case tap = "Short tap"
    case pulses = "Three pulses"
    case rumble = "Rumble (1 s)"
    case rampDown = "Fading rumble"
    var id: String { rawValue }

    struct Event: Equatable {
        /// Seconds from the start of the pattern.
        let time: Double
        /// `nil` for a transient event, otherwise the continuous event's duration in seconds.
        let duration: Double?
        let intensity: Float
        let sharpness: Float
    }

    var events: [Event] {
        switch self {
        case .tap: [Event(time: 0, duration: nil, intensity: 1, sharpness: 0.8)]
        case .pulses: (0..<3).map { Event(time: Double($0) * 0.25, duration: 0.12, intensity: 0.9, sharpness: 0.5) }
        case .rumble: [Event(time: 0, duration: 1, intensity: 0.8, sharpness: 0.2)]
        case .rampDown: (0..<5).map { Event(time: Double($0) * 0.2, duration: 0.2, intensity: 1 - Float($0) * 0.2, sharpness: 0.3) }
        }
    }

    var totalDuration: Double { events.map { $0.time + ($0.duration ?? 0.05) }.max() ?? 0 }
}

#if canImport(GameController) && !os(watchOS)
/// Observes controller connections, optionally runs wireless discovery, and streams the live input of the current controller.
@MainActor
final class GameControllerExperimentService: ObservableObject {
    @Published private(set) var controllers: [GameControllerInfo] = []
    @Published private(set) var input: ControllerInputState?
    @Published private(set) var isMonitoring = false
    @Published private(set) var isDiscovering = false
    @Published private(set) var output = ""
    /// Localities the current controller's haptics support (`GCDeviceHaptics.supportedLocalities`), `default` first.
    @Published private(set) var hapticLocalities: [String] = []
    @Published private(set) var isPlayingHaptic = false
    private var observers: [NSObjectProtocol] = []
    #if canImport(CoreHaptics)
    private var hapticEngine: CHHapticEngine?
    private var hapticEngineKey: String?
    #endif
    private weak var liveController: GCController?

    init() {
        refreshControllers()
        output = controllers.isEmpty
            ? "No controller connected. Pair one in Bluetooth settings or start wireless discovery."
            : "\(controllers.count) controller(s) connected. Start monitoring to see live input."
    }

    func start() {
        guard !isMonitoring else { return }
        isMonitoring = true
        let events: [(Notification.Name, String)] = [(.GCControllerDidConnect, "connected"), (.GCControllerDidDisconnect, "disconnected"), (.GCControllerDidBecomeCurrent, "became the current controller")]
        observers = events.map { name, event in
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                let vendor = (notification.object as? GCController)?.vendorName ?? "A controller"
                MainActor.assumeIsolated { self?.controllersChanged("\(vendor) \(event).") }
            }
        }
        controllersChanged(nil)
        output = input == nil
            ? "Monitoring. No controller connected yet: turn one on or pair it and it appears here."
            : "Monitoring \(input?.controllerName ?? "controller"). Press buttons or move the sticks."
    }

    func stop() {
        #if canImport(CoreHaptics)
        hapticEngine?.stop()
        hapticEngine = nil
        hapticEngineKey = nil
        #endif
        isPlayingHaptic = false
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers = []
        detachInput()
        input = nil
        if isDiscovering {
            GCController.stopWirelessControllerDiscovery()
            isDiscovering = false
        }
        isMonitoring = false
        output = "Stopped. Controllers stay connected; this experiment no longer reads their input."
    }

    /// Discovery also starts monitoring, so a controller that pairs shows up immediately.
    func startDiscovery() {
        guard !isDiscovering else { return }
        start()
        isDiscovering = true
        output = "Searching for wireless controllers in pairing mode…"
        GCController.startWirelessControllerDiscovery { @Sendable [weak self] in
            Task { @MainActor in self?.discoveryFinished() }
        }
    }

    func stopDiscovery() {
        guard isDiscovering else { return }
        GCController.stopWirelessControllerDiscovery()
        isDiscovering = false
        output = "Wireless discovery stopped."
    }

    private func discoveryFinished() {
        guard isDiscovering else { return }
        isDiscovering = false
        refreshControllers()
        output = controllers.isEmpty
            ? "Discovery ended without a controller. Xbox, PlayStation, and Switch controllers are paired in Bluetooth settings instead."
            : "Discovery ended. \(controllers.count) controller(s) connected."
    }

    private func controllersChanged(_ message: String?) {
        refreshControllers()
        if isMonitoring { attachInput(to: GCController.current ?? GCController.controllers().first) }
        if let message { output = message }
        // The registry status depends on whether a controller is connected.
        PermissionCenter.shared.invalidate()
    }

    private func refreshControllers() {
        let current = GCController.current
        controllers = GCController.controllers().map { Self.info(for: $0, isCurrent: $0 === current) }
        let localities = hapticController?.haptics?.supportedLocalities.map(\.rawValue) ?? []
        hapticLocalities = localities.sorted { lhs, rhs in
            lhs == GCHapticsLocality.default.rawValue || (rhs != GCHapticsLocality.default.rawValue && lhs < rhs)
        }
    }

    // MARK: Haptics

    /// The controller haptics are played on: the current controller, else the first connected one with haptics.
    private var hapticController: GCController? {
        if let current = GCController.current, current.haptics != nil { return current }
        return GCController.controllers().first { $0.haptics != nil }
    }

    /// Creates a CHHapticEngine with GCDeviceHaptics.createEngine(withLocality:) and plays the pattern on it.
    func playHaptic(_ pattern: ControllerHapticPattern, locality: String) {
        #if canImport(CoreHaptics)
        guard let controller = hapticController, let haptics = controller.haptics else {
            output = "No connected controller reports haptics (GCController.haptics is nil). DualSense, DualShock 4 and Xbox controllers support them; the Siri Remote does not."
            return
        }
        let name = controller.vendorName ?? "controller"
        do {
            let key = "\(ObjectIdentifier(controller).hashValue)-\(locality)"
            if hapticEngine == nil || hapticEngineKey != key {
                hapticEngine?.stop()
                guard let engine = haptics.createEngine(withLocality: GCHapticsLocality(rawValue: locality)) else {
                    output = "createEngine(withLocality: \(locality)) returned nil for \(name)."
                    return
                }
                engine.stoppedHandler = { @Sendable [weak self] reason in
                    Task { @MainActor in self?.hapticEngineStopped(reason.rawValue) }
                }
                hapticEngine = engine
                hapticEngineKey = key
            }
            guard let engine = hapticEngine else { return }
            try engine.start()
            let events = pattern.events.map { event in
                let parameters = [CHHapticEventParameter(parameterID: .hapticIntensity, value: event.intensity),
                                  CHHapticEventParameter(parameterID: .hapticSharpness, value: event.sharpness)]
                if let duration = event.duration {
                    return CHHapticEvent(eventType: .hapticContinuous, parameters: parameters, relativeTime: event.time, duration: duration)
                }
                return CHHapticEvent(eventType: .hapticTransient, parameters: parameters, relativeTime: event.time)
            }
            let player = try engine.makePlayer(with: CHHapticPattern(events: events, parameters: []))
            try player.start(atTime: CHHapticTimeImmediate)
            isPlayingHaptic = true
            output = "Playing \"\(pattern.rawValue)\" on \(name) · locality \(locality) · \(events.count) event(s), \(pattern.totalDuration.formatted(.number.precision(.fractionLength(2)))) s."
            let duration = pattern.totalDuration
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(duration))
                self?.isPlayingHaptic = false
            }
        } catch {
            isPlayingHaptic = false
            output = "Core Haptics error on \(name): \(error.localizedDescription)"
        }
        #else
        output = "Core Haptics is not available on this platform."
        #endif
    }

    private func hapticEngineStopped(_ reason: Int) {
        isPlayingHaptic = false
        #if canImport(CoreHaptics)
        hapticEngine = nil
        hapticEngineKey = nil
        #endif
        output = "The controller's haptic engine stopped (CHHapticEngine.StoppedReason \(reason)), e.g. because the controller disconnected or went idle."
    }

    // MARK: Live input

    private func attachInput(to controller: GCController?) {
        guard controller !== liveController || input == nil else { return }
        detachInput()
        guard let controller else { input = nil; return }
        liveController = controller
        let name = controller.vendorName ?? "Controller"
        let profile = Self.profileName(of: controller)
        // The handlers below update main-actor state, so they must run on the main queue (the default).
        controller.handlerQueue = .main
        if let gamepad = controller.extendedGamepad {
            gamepad.valueChangedHandler = { [weak self] gamepad, element in
                self?.input = Self.reading(of: gamepad, name: name, profile: profile, change: element)
            }
            input = Self.reading(of: gamepad, name: name, profile: profile, change: nil)
        } else if let gamepad = controller.microGamepad {
            gamepad.valueChangedHandler = { [weak self] gamepad, element in
                self?.input = Self.reading(of: gamepad, name: name, profile: profile, change: element)
            }
            input = Self.reading(of: gamepad, name: name, profile: profile, change: nil)
        } else {
            input = ControllerInputState(controllerName: name, profile: profile, lastChange: "This controller exposes neither an extended nor a micro gamepad profile.")
        }
    }

    private func detachInput() {
        liveController?.extendedGamepad?.valueChangedHandler = nil
        liveController?.microGamepad?.valueChangedHandler = nil
        liveController = nil
    }

    private static func reading(of gamepad: GCExtendedGamepad, name: String, profile: String, change: GCControllerElement?) -> ControllerInputState {
        let buttons: [(String, GCControllerButtonInput?)] = [
            ("Button A", gamepad.buttonA), ("Button B", gamepad.buttonB), ("Button X", gamepad.buttonX), ("Button Y", gamepad.buttonY),
            ("Left shoulder", gamepad.leftShoulder), ("Right shoulder", gamepad.rightShoulder),
            ("Left trigger", gamepad.leftTrigger), ("Right trigger", gamepad.rightTrigger),
            ("Left stick button", gamepad.leftThumbstickButton), ("Right stick button", gamepad.rightThumbstickButton),
            ("Menu", gamepad.buttonMenu), ("Options", gamepad.buttonOptions), ("Home", gamepad.buttonHome)
        ]
        let sticks: [(String, GCControllerDirectionPad)] = [("Left stick", gamepad.leftThumbstick), ("Right stick", gamepad.rightThumbstick), ("D-pad", gamepad.dpad)]
        return ControllerInputState(controllerName: name, profile: profile, buttons: buttons.compactMap(button), sticks: sticks.map(stick), lastChange: change.map(elementName))
    }

    private static func reading(of gamepad: GCMicroGamepad, name: String, profile: String, change: GCControllerElement?) -> ControllerInputState {
        let buttons: [(String, GCControllerButtonInput?)] = [("Button A", gamepad.buttonA), ("Button X", gamepad.buttonX), ("Menu", gamepad.buttonMenu)]
        return ControllerInputState(controllerName: name, profile: profile, buttons: buttons.compactMap(button),
                                    sticks: [stick("Touch surface / D-pad", gamepad.dpad)], lastChange: change.map(elementName))
    }

    private static func button(_ id: String, _ input: GCControllerButtonInput?) -> ControllerButtonState? {
        guard let input else { return nil }
        return ControllerButtonState(id: id, name: input.localizedName ?? id, symbol: input.sfSymbolsName, value: input.value, isPressed: input.isPressed, isAnalog: input.isAnalog)
    }

    private static func stick(_ id: String, _ pad: GCControllerDirectionPad) -> ControllerStickState {
        ControllerStickState(id: id, name: pad.localizedName ?? id, x: pad.xAxis.value, y: pad.yAxis.value)
    }

    private static func elementName(_ element: GCControllerElement) -> String {
        element.localizedName ?? element.unmappedLocalizedName ?? "Input"
    }

    // MARK: Controller details

    private static func info(for controller: GCController, isCurrent: Bool) -> GameControllerInfo {
        GameControllerInfo(id: ObjectIdentifier(controller), name: controller.vendorName ?? "Unnamed controller", category: controller.productCategory,
                           profile: profileName(of: controller), battery: batteryText(controller.battery),
                           haptics: controller.haptics == nil ? "Not supported" : "Supported", isCurrent: isCurrent)
    }

    private static func profileName(of controller: GCController) -> String {
        if let gamepad = controller.extendedGamepad {
            switch gamepad {
            case is GCDualSenseGamepad: return "Extended gamepad · DualSense"
            case is GCDualShockGamepad: return "Extended gamepad · DualShock"
            case is GCXboxGamepad: return "Extended gamepad · Xbox"
            default: return "Extended gamepad"
            }
        }
        if let gamepad = controller.microGamepad {
            return gamepad is GCDirectionalGamepad ? "Micro gamepad · Directional" : "Micro gamepad"
        }
        return "No gamepad profile"
    }

    private static func batteryText(_ battery: GCDeviceBattery?) -> String {
        guard let battery else { return "Not reported" }
        let level = Double(battery.batteryLevel).formatted(.percent.precision(.fractionLength(0)))
        switch battery.batteryState {
        case .charging: return "\(level) · charging"
        case .full: return "\(level) · full"
        case .discharging: return level
        case .unknown: return "\(level) · state unknown"
        @unknown default: return level
        }
    }
}

extension GameControllerExperimentService: StoppableExperiment {
    var isActive: Bool { isMonitoring || isDiscovering }
}
#endif
