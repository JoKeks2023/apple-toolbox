import Foundation
import Combine
import CoreGraphics
#if os(iOS)
import UIKit
#endif
#if canImport(GameController) && (os(iOS) || os(macOS))
import GameController
#endif

extension ExperimentAvailability {
    /// Apple Pencil pairs only with iPad; whether one is paired right now is not exposed by a public API.
    static func applePencil() -> ExperimentStatus {
        #if canImport(PencilKit) && os(iOS)
        .available
        #else
        .platformUnsupported
        #endif
    }

    /// A Mac always has keyboard and pointer events. On iPad and iPhone a hardware keyboard, mouse or trackpad must be connected.
    static func pointerKeyboard() -> ExperimentStatus {
        #if os(macOS)
        .available
        #elseif os(iOS) && canImport(GameController)
        GCKeyboard.coalesced != nil || !GCMouse.mice().isEmpty ? .available : .unavailable
        #else
        .platformUnsupported
        #endif
    }

    /// Size classes, window scenes and screens are UIKit concepts; iPhone runs a single full-screen window.
    static func windowsDisplays() -> ExperimentStatus {
        #if os(iOS)
        .available
        #else
        .platformUnsupported
        #endif
    }
}

// MARK: - Formatting (pure, testable on every platform)

nonisolated enum PencilFormatting {
    static func degrees(_ radians: Double) -> String {
        "\(Int((radians * 180 / .pi).rounded()))°"
    }

    /// `UITouch.force` relative to `maximumPossibleForce`; a maximum of 0 means the touch has no pressure data.
    static func force(_ force: Double, maximum: Double) -> String {
        guard maximum > 0 else { return "Not reported for this touch" }
        let share = Int((min(force / maximum, 1) * 100).rounded())
        return String(format: "%.2f of %.2f (%d %%)", force, maximum, share)
    }

    /// Altitude is π/2 when the Pencil stands upright and approaches 0 when it lies flat.
    static func tilt(altitude: Double) -> String {
        "\(degrees(altitude)) altitude · \(degrees(.pi / 2 - altitude)) from vertical"
    }

    static func distance(_ zOffset: Double) -> String {
        String(format: "%.2f (0 = touching, 1 = edge of hover range)", zOffset)
    }
}

nonisolated enum KeyboardFormatting {
    /// Modifier symbols in the order macOS menus use.
    static func modifiers(capsLock: Bool, shift: Bool, control: Bool, option: Bool, command: Bool) -> String {
        let symbols = [(control, "⌃"), (option, "⌥"), (capsLock, "⇪"), (shift, "⇧"), (command, "⌘")].filter(\.0).map(\.1)
        return symbols.isEmpty ? "None" : symbols.joined(separator: " ")
    }
}

nonisolated enum WindowFormatting {
    static func size(_ size: CGSize) -> String {
        "\(Int(size.width.rounded())) × \(Int(size.height.rounded())) pt"
    }

    /// Infers the window layout from window and screen size; iPadOS has no public API that names the multitasking mode.
    static func layout(window: CGSize, screen: CGSize) -> String {
        guard window.width > 0, window.height > 0, screen.width > 0, screen.height > 0 else { return "Unknown" }
        // The screen size is reported for its current orientation; compare against both to be safe.
        let screens = [screen, CGSize(width: screen.height, height: screen.width)]
        let close = { (a: CGFloat, b: CGFloat) in abs(a - b) <= 1 }
        if screens.contains(where: { close($0.width, window.width) && close($0.height, window.height) }) { return "Full screen" }
        guard let match = screens.first(where: { window.width <= $0.width + 1 && window.height <= $0.height + 1 }) else { return "Larger than the screen" }
        let width = Int((window.width / match.width * 100).rounded()), height = Int((window.height / match.height * 100).rounded())
        if close(window.height, match.height) { return "Full height, \(width) % width (split or tiled)" }
        return "Window at \(width) % × \(height) % of the screen (Stage Manager or windowed apps)"
    }
}

/// Pointer effects the lab can apply: hover effects on iPadOS, pointer styles on macOS.
enum PointerEffectOption: String, CaseIterable, Identifiable {
    case automatic = "Automatic"
    case highlight = "Highlight"
    case lift = "Lift"
    case link = "Link"
    case grab = "Grab"
    case text = "Text (I-beam)"
    case crosshair = "Crosshair"
    case hidden = "Hidden pointer"
    case disabled = "No effect"

    var id: String { rawValue }

    static var platformCases: [PointerEffectOption] {
        #if os(macOS)
        [.automatic, .link, .grab, .text, .crosshair, .hidden]
        #else
        [.automatic, .highlight, .lift, .disabled]
        #endif
    }
}

struct PencilSample: Equatable {
    var type: String
    var phase: String
    var location: CGPoint
    var force: Double
    var maximumForce: Double
    var altitude: Double
    var azimuth: Double
    var roll: Double
    var coalesced: Int
    var predicted: Int
    var estimatedProperties: String
}

struct HoverSample: Equatable {
    var location: CGPoint
    var zOffset: Double
    var altitude: Double
    var azimuth: Double
    var roll: Double
}

// MARK: - Apple Pencil

#if canImport(PencilKit) && os(iOS)
/// Collects what the PencilKit canvas reports: touches (force, altitude, azimuth, roll), hover and Pencil interactions.
@MainActor
final class PencilLabService: ObservableObject {
    enum DrawingPolicy: String, CaseIterable, Identifiable {
        case system = "System default"
        case anyInput = "Pencil and finger"
        case pencilOnly = "Pencil only"
        var id: String { rawValue }
    }

    @Published var drawingPolicy = DrawingPolicy.anyInput
    @Published private(set) var touch: PencilSample?
    @Published private(set) var hover: HoverSample?
    @Published private(set) var strokes = 0
    @Published private(set) var events: [String] = []
    @Published private(set) var clearToken = 0

    var settings: [PlatformFact] {
        [
            PlatformFact(title: "Double-tap action", value: Self.name(UIPencilInteraction.preferredTapAction)),
            PlatformFact(title: "Squeeze action", value: Self.name(UIPencilInteraction.preferredSqueezeAction)),
            PlatformFact(title: "Only draw with Pencil", value: UIPencilInteraction.prefersPencilOnlyDrawing ? "On" : "Off"),
            PlatformFact(title: "Hover tool preview", value: UIPencilInteraction.prefersHoverToolPreview ? "On" : "Off"),
        ]
    }

    func record(touch sample: PencilSample) { touch = sample }
    func record(hover sample: HoverSample?) { hover = sample }
    func record(strokes count: Int) { strokes = count }

    func log(_ event: String) {
        events.insert("\(Date().formatted(date: .omitted, time: .standard))  \(event)", at: 0)
        if events.count > 8 { events.removeLast(events.count - 8) }
    }

    func clear() {
        clearToken += 1
        touch = nil
        hover = nil
        events = []
    }

    static func name(_ action: UIPencilPreferredAction) -> String {
        switch action {
        case .ignore: "Ignore"
        case .switchEraser: "Switch to eraser"
        case .switchPrevious: "Switch to previous tool"
        case .showColorPalette: "Show color palette"
        case .showInkAttributes: "Show ink attributes"
        case .showContextualPalette: "Show contextual palette"
        case .runSystemShortcut: "Run system shortcut"
        @unknown default: "Action \(action.rawValue)"
        }
    }

    static func touchType(_ type: UITouch.TouchType) -> String {
        switch type {
        case .direct: "Finger"
        case .pencil: "Apple Pencil"
        case .indirect: "Indirect"
        case .indirectPointer: "Pointer"
        @unknown default: "Type \(type.rawValue)"
        }
    }

    static func estimated(_ properties: UITouch.Properties) -> String {
        let names: [(UITouch.Properties, String)] = [(.force, "force"), (.azimuth, "azimuth"), (.altitude, "altitude"), (.location, "location"), (.roll, "roll")]
        let listed = names.filter { properties.contains($0.0) }.map(\.1)
        return listed.isEmpty ? "None (final values)" : listed.joined(separator: ", ")
    }
}
#endif

// MARK: - Pointer and keyboard

#if os(iOS) || os(macOS)
/// Reads hardware keyboards and mice through GameController while monitoring, next to the SwiftUI events the run view shows.
@MainActor
final class PointerKeyboardService: ObservableObject {
    @Published private(set) var keyboardConnected = false
    @Published private(set) var mice = 0
    @Published private(set) var isMonitoring = false
    @Published private(set) var rawKey: String?
    @Published private(set) var rawModifiers = "None"
    @Published private(set) var mouseDelta = CGSize.zero
    @Published private(set) var mouseButtons = "None"
    @Published private(set) var output = "Start monitoring to read raw keyboard and mouse input through GameController."
    private var observers: [NSObjectProtocol] = []

    init() {
        #if canImport(GameController) && (os(iOS) || os(macOS))
        keyboardConnected = GCKeyboard.coalesced != nil
        mice = GCMouse.mice().count
        #endif
    }

    #if canImport(GameController) && (os(iOS) || os(macOS))
    func start() {
        guard !isMonitoring else { return }
        isMonitoring = true
        let events: [(Notification.Name, String)] = [
            (.GCKeyboardDidConnect, "A keyboard connected."), (.GCKeyboardDidDisconnect, "A keyboard disconnected."),
            (.GCMouseDidConnect, "A mouse or trackpad connected."), (.GCMouseDidDisconnect, "A mouse or trackpad disconnected."),
        ]
        observers = events.map { name, event in
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.refreshDevices()
                    self?.attach()
                    self?.output = event
                }
            }
        }
        refreshDevices()
        attach()
        output = keyboardConnected || mice > 0
            ? "Monitoring. Press keys or move the mouse or trackpad."
            : "Monitoring. No hardware keyboard or mouse is connected yet; attach one and it appears here."
    }

    func stop() {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers = []
        GCKeyboard.coalesced?.keyboardInput?.keyChangedHandler = nil
        GCMouse.mice().forEach { mouse in
            mouse.mouseInput?.mouseMovedHandler = nil
            mouse.mouseInput?.leftButton.pressedChangedHandler = nil
            mouse.mouseInput?.rightButton?.pressedChangedHandler = nil
        }
        isMonitoring = false
        output = "Stopped. GameController no longer reports raw input to this experiment."
    }

    private func refreshDevices() {
        keyboardConnected = GCKeyboard.coalesced != nil
        mice = GCMouse.mice().count
        // The registry status depends on whether a keyboard or mouse is connected.
        PermissionCenter.shared.invalidate()
    }

    /// Handlers run on the main queue (set explicitly), so they may update main-actor state.
    private func attach() {
        if let keyboard = GCKeyboard.coalesced {
            keyboard.handlerQueue = .main
            keyboard.keyboardInput?.keyChangedHandler = { [weak self] input, key, keyCode, pressed in
                let name = key.localizedName ?? "Key code \(keyCode.rawValue)"
                self?.rawKey = "\(name) \(pressed ? "down" : "up") · HID usage \(keyCode.rawValue)"
                self?.rawModifiers = KeyboardFormatting.modifiers(
                    capsLock: input.button(forKeyCode: .capsLock)?.isPressed == true,
                    shift: Self.pressed(input, .leftShift, .rightShift),
                    control: Self.pressed(input, .leftControl, .rightControl),
                    option: Self.pressed(input, .leftAlt, .rightAlt),
                    command: Self.pressed(input, .leftGUI, .rightGUI))
            }
        }
        for mouse in GCMouse.mice() {
            mouse.handlerQueue = .main
            guard let input = mouse.mouseInput else { continue }
            input.mouseMovedHandler = { [weak self] _, deltaX, deltaY in
                self?.mouseDelta = CGSize(width: CGFloat(deltaX), height: CGFloat(deltaY))
            }
            input.leftButton.pressedChangedHandler = { [weak self] _, _, pressed in self?.mouseButtons = pressed ? "Left" : "None" }
            input.rightButton?.pressedChangedHandler = { [weak self] _, _, pressed in self?.mouseButtons = pressed ? "Right" : "None" }
        }
    }

    private static func pressed(_ input: GCKeyboardInput, _ left: GCKeyCode, _ right: GCKeyCode) -> Bool {
        input.button(forKeyCode: left)?.isPressed == true || input.button(forKeyCode: right)?.isPressed == true
    }
    #else
    func start() {}
    func stop() {}
    #endif
}

extension PointerKeyboardService: StoppableExperiment {
    var isActive: Bool { isMonitoring }
}
#endif

// MARK: - Windows and displays

#if os(iOS)
/// Follows the window scene that hosts the run view: geometry, size restrictions, sessions and the screens scenes are on.
@MainActor
final class WindowLabService: ObservableObject {
    @Published private(set) var window: [PlatformFact] = []
    @Published private(set) var scenes: [PlatformFact] = []
    @Published private(set) var screens: [DisplayInfo] = []
    @Published private(set) var output = "Waiting for the window scene…"
    private weak var scene: UIWindowScene?
    private var geometryObservation: NSKeyValueObservation?
    private var observers: [NSObjectProtocol] = []

    init() {
        let names: [Notification.Name] = [UIScene.willConnectNotification, UIScene.didDisconnectNotification, UIScene.didActivateNotification, UIScene.didEnterBackgroundNotification]
        observers = names.map { name in
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                let event = notification.name.rawValue.replacingOccurrences(of: "UIScene", with: "Scene ").replacingOccurrences(of: "Notification", with: "")
                MainActor.assumeIsolated { self?.refresh(reason: event) }
            }
        }
    }

    isolated deinit {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        geometryObservation?.invalidate()
    }

    /// Called by the probe view once it is in a window.
    func attach(to scene: UIWindowScene?) {
        guard let scene, scene !== self.scene else { return }
        self.scene = scene
        // effectiveGeometry is key-value observable and changes on resize, rotation and display moves.
        geometryObservation = scene.observe(\.effectiveGeometry, options: [.new]) { @Sendable [weak self] _, _ in
            Task { @MainActor in self?.refresh(reason: "Window geometry changed") }
        }
        refresh(reason: nil)
    }

    func refresh(reason: String?) {
        guard let scene else { return }
        let geometry = scene.effectiveGeometry
        let windowSize = geometry.coordinateSpace.bounds.size
        let screenSize = scene.screen.bounds.size
        var facts = [
            PlatformFact(title: "Window", value: WindowFormatting.size(windowSize)),
            PlatformFact(title: "Screen", value: WindowFormatting.size(screenSize)),
            PlatformFact(title: "Layout (inferred)", value: WindowFormatting.layout(window: windowSize, screen: screenSize)),
            PlatformFact(title: "Orientation", value: Self.orientation(geometry.interfaceOrientation) + (geometry.isInterfaceOrientationLocked ? " · locked" : "")),
            PlatformFact(title: "Resizing now", value: geometry.isInteractivelyResizing ? "Yes" : "No"),
            PlatformFact(title: "Size classes (UIKit)", value: "\(Self.sizeClass(scene.traitCollection.horizontalSizeClass)) width · \(Self.sizeClass(scene.traitCollection.verticalSizeClass)) height"),
        ]
        if let restrictions = scene.sizeRestrictions {
            facts.append(PlatformFact(title: "Size restrictions", value: "min \(WindowFormatting.size(restrictions.minimumSize)) · max \(Self.maximum(restrictions.maximumSize))"))
        }
        if let behaviors = scene.windowingBehaviors {
            facts.append(PlatformFact(title: "Windowing behaviors", value: "closable \(behaviors.isClosable ? "yes" : "no") · minimizable \(behaviors.isMiniaturizable ? "yes" : "no")"))
        }
        window = facts

        let application = UIApplication.shared
        let windowScenes = application.connectedScenes.compactMap { $0 as? UIWindowScene }
        scenes = [
            PlatformFact(title: "Multiple scenes", value: application.supportsMultipleScenes ? "Supported (UIApplicationSupportsMultipleScenes)" : "Not supported"),
            PlatformFact(title: "Open sessions", value: "\(application.openSessions.count)"),
            PlatformFact(title: "Connected window scenes", value: windowScenes.map { Self.role($0.session.role) + " · " + Self.state($0.activationState) }.joined(separator: "\n")),
        ]

        var seen = Set<ObjectIdentifier>()
        let uniqueScreens = windowScenes.map(\.screen).filter { seen.insert(ObjectIdentifier($0)).inserted }
        screens = uniqueScreens.enumerated().map { index, screen in
            let facts = [
                PlatformFact(title: "Bounds", value: "\(WindowFormatting.size(screen.bounds.size)) @ \(screen.scale.formatted())×"),
                PlatformFact(title: "Native", value: "\(Int(screen.nativeBounds.width)) × \(Int(screen.nativeBounds.height)) px @ \(screen.nativeScale.formatted())×"),
                PlatformFact(title: "Refresh rate", value: "up to \(screen.maximumFramesPerSecond) Hz"),
                PlatformFact(title: "EDR headroom", value: screen.potentialEDRHeadroom > 1 ? "\(Self.multiple(screen.currentEDRHeadroom)) now · up to \(Self.multiple(screen.potentialEDRHeadroom))" : "None (SDR only)"),
                PlatformFact(title: "Mirroring", value: screen.mirrored == nil ? "No" : "Mirrors another screen"),
                PlatformFact(title: "Hosts", value: windowScenes.filter { $0.screen === screen }.map { Self.role($0.session.role) }.joined(separator: ", ")),
            ]
            return DisplayInfo(id: UInt32(index), name: screen === scene.screen ? "This window's screen" : "Screen \(index + 1)", facts: facts)
        }
        output = (reason.map { "\($0). " } ?? "") + "\(windowScenes.count) window scene(s) on \(screens.count) screen(s). Resize the window, rotate, or connect a display to see live updates."
    }

    private static func multiple(_ value: CGFloat) -> String {
        Double(value).formatted(.number.precision(.fractionLength(1))) + "×"
    }

    private static func maximum(_ size: CGSize) -> String {
        size.width >= CGFloat(Float.greatestFiniteMagnitude) || size.height >= CGFloat(Float.greatestFiniteMagnitude) ? "unlimited" : WindowFormatting.size(size)
    }

    private static func sizeClass(_ sizeClass: UIUserInterfaceSizeClass) -> String {
        switch sizeClass {
        case .compact: "Compact"
        case .regular: "Regular"
        case .unspecified: "Unspecified"
        @unknown default: "Unknown"
        }
    }

    private static func orientation(_ orientation: UIInterfaceOrientation) -> String {
        switch orientation {
        case .portrait: "Portrait"
        case .portraitUpsideDown: "Portrait upside down"
        case .landscapeLeft: "Landscape left"
        case .landscapeRight: "Landscape right"
        case .unknown: "Unknown"
        @unknown default: "Unknown"
        }
    }

    private static func role(_ role: UISceneSession.Role) -> String {
        switch role {
        case .windowApplication: "App window"
        case .windowExternalDisplayNonInteractive: "External display (non-interactive)"
        default: role.rawValue
        }
    }

    private static func state(_ state: UIScene.ActivationState) -> String {
        switch state {
        case .foregroundActive: "active"
        case .foregroundInactive: "inactive"
        case .background: "background"
        case .unattached: "unattached"
        @unknown default: "unknown"
        }
    }
}
#endif
