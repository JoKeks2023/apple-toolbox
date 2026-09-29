import Foundation
import Combine
#if canImport(GameController) && !os(watchOS)
import GameController
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

#if canImport(GameController) && !os(watchOS)
/// Observes controller connections, optionally runs wireless discovery, and streams the live input of the current controller.
@MainActor
final class GameControllerExperimentService: ObservableObject {
    @Published private(set) var controllers: [GameControllerInfo] = []
    @Published private(set) var input: ControllerInputState?
    @Published private(set) var isMonitoring = false
    @Published private(set) var isDiscovering = false
    @Published private(set) var output = ""
    private var observers: [NSObjectProtocol] = []
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
