import SwiftUI
#if canImport(PencilKit) && os(iOS)
import PencilKit
import UIKit
import UIKit.UIGestureRecognizerSubclass
#endif

// MARK: - Apple Pencil

struct ApplePencilRunView: View {
    #if canImport(PencilKit) && os(iOS)
    @StateObject private var pencil = PencilLabService()
    @State private var showsToolPicker = false

    var body: some View {
        Picker("Drawing policy", selection: $pencil.drawingPolicy) {
            ForEach(PencilLabService.DrawingPolicy.allCases) { Text($0.rawValue).tag($0) }
        }
        Toggle("Show PKToolPicker", isOn: $showsToolPicker)
        PencilCanvas(service: pencil, policy: pencil.drawingPolicy, showsToolPicker: showsToolPicker, clearToken: pencil.clearToken)
            .frame(height: 340)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        HStack {
            Text("\(pencil.strokes) stroke\(pencil.strokes == 1 ? "" : "s") in the PKDrawing").font(.caption).foregroundStyle(.secondary)
            Spacer()
            Button("Clear", systemImage: "trash") { pencil.clear() }
        }
        Section("Touch · UITouch") {
            if let touch = pencil.touch {
                LabeledContent("Input", value: "\(touch.type) · \(touch.phase)")
                LabeledContent("Location", value: "\(Int(touch.location.x)), \(Int(touch.location.y)) pt")
                LabeledContent("Force", value: PencilFormatting.force(touch.force, maximum: touch.maximumForce))
                LabeledContent("Tilt", value: PencilFormatting.tilt(altitude: touch.altitude))
                LabeledContent("Azimuth", value: PencilFormatting.degrees(touch.azimuth))
                LabeledContent("Barrel roll", value: touch.roll == 0 ? "0° (Apple Pencil Pro only)" : PencilFormatting.degrees(touch.roll))
                LabeledContent("Coalesced · predicted", value: "\(touch.coalesced) · \(touch.predicted) touches")
                LabeledContent("Estimated, updates pending", value: touch.estimatedProperties)
            } else {
                Text("Draw on the canvas. A finger reports location only; Apple Pencil adds force, altitude and azimuth, and Apple Pencil Pro adds barrel roll.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        Section("Hover · UIHoverGestureRecognizer") {
            if let hover = pencil.hover {
                LabeledContent("Location", value: "\(Int(hover.location.x)), \(Int(hover.location.y)) pt")
                LabeledContent("Distance (zOffset)", value: PencilFormatting.distance(hover.zOffset))
                LabeledContent("Tilt", value: PencilFormatting.tilt(altitude: hover.altitude))
                LabeledContent("Azimuth", value: PencilFormatting.degrees(hover.azimuth))
            } else {
                Text("Hold Apple Pencil (2nd generation, USB-C or Pro) just above an iPad with M2 or later, or move a pointer over the canvas. Other iPads report no Pencil hover.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        Section("Double-tap and squeeze · UIPencilInteraction") {
            ForEach(pencil.settings) { LabeledContent($0.title, value: $0.value) }
            if pencil.events.isEmpty {
                Text("Double-tap Apple Pencil (2nd generation or Pro) or squeeze Apple Pencil Pro while this screen is open. The system reports the gesture; the app decides what to do with it.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                OutputView(text: pencil.events.joined(separator: "\n"), isError: false)
            }
        }
        Text("No public API tells an app whether an Apple Pencil is paired or which model it is; the lab shows what each touch, hover and interaction actually reports.")
            .font(.caption).foregroundStyle(.secondary)
    }
    #else
    var body: some View {
        OutputView(text: "PencilKit's canvas (PKCanvasView), Apple Pencil touches and UIPencilInteraction are iPadOS and iOS APIs. Open Apple Toolbox on an iPad with Apple Pencil.", isError: true)
    }
    #endif
}

#if canImport(PencilKit) && os(iOS)
private struct PencilCanvas: UIViewRepresentable {
    let service: PencilLabService
    let policy: PencilLabService.DrawingPolicy
    let showsToolPicker: Bool
    let clearToken: Int

    func makeCoordinator() -> Coordinator { Coordinator(service: service) }

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.backgroundColor = .secondarySystemBackground
        canvas.isOpaque = false
        canvas.isScrollEnabled = false
        canvas.tool = PKInkingTool(.pen, color: .label, width: 4)
        canvas.delegate = context.coordinator

        let probe = TouchProbeRecognizer()
        probe.delegate = context.coordinator
        probe.onSample = { [weak service] sample in service?.record(touch: sample) }
        canvas.addGestureRecognizer(probe)

        let hover = UIHoverGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.hovered(_:)))
        hover.delegate = context.coordinator
        canvas.addGestureRecognizer(hover)

        canvas.addInteraction(UIPencilInteraction(delegate: context.coordinator))
        context.coordinator.toolPicker.addObserver(canvas)
        return canvas
    }

    func updateUIView(_ canvas: PKCanvasView, context: Context) {
        canvas.drawingPolicy = switch policy {
        case .system: .default
        case .anyInput: .anyInput
        case .pencilOnly: .pencilOnly
        }
        let coordinator = context.coordinator
        if coordinator.clearToken != clearToken {
            coordinator.clearToken = clearToken
            canvas.drawing = PKDrawing()
        }
        if coordinator.showsToolPicker != showsToolPicker {
            coordinator.showsToolPicker = showsToolPicker
            coordinator.toolPicker.setVisible(showsToolPicker, forFirstResponder: canvas)
            if showsToolPicker { canvas.becomeFirstResponder() } else { canvas.resignFirstResponder() }
        }
    }

    static func dismantleUIView(_ canvas: PKCanvasView, coordinator: Coordinator) {
        coordinator.toolPicker.setVisible(false, forFirstResponder: canvas)
        coordinator.toolPicker.removeObserver(canvas)
        canvas.resignFirstResponder()
    }

    /// UIKit calls these delegates on the main thread.
    final class Coordinator: NSObject, PKCanvasViewDelegate, UIGestureRecognizerDelegate, UIPencilInteractionDelegate {
        let toolPicker = PKToolPicker()
        var clearToken = 0
        var showsToolPicker = false
        private weak var service: PencilLabService?

        init(service: PencilLabService) { self.service = service }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            service?.record(strokes: canvasView.drawing.strokes.count)
        }

        /// The touch probe and hover recognizer only observe, so they run alongside PencilKit's drawing gesture.
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }

        @objc func hovered(_ recognizer: UIHoverGestureRecognizer) {
            switch recognizer.state {
            case .began, .changed:
                service?.record(hover: HoverSample(location: recognizer.location(in: recognizer.view), zOffset: Double(recognizer.zOffset),
                                                   altitude: Double(recognizer.altitudeAngle), azimuth: Double(recognizer.azimuthAngle(in: recognizer.view)),
                                                   roll: Double(recognizer.rollAngle)))
            default:
                service?.record(hover: nil)
            }
        }

        func pencilInteraction(_ interaction: UIPencilInteraction, didReceiveTap tap: UIPencilInteraction.Tap) {
            service?.log("Double-tap\(Self.pose(tap.hoverPose)) · preferred action: \(PencilLabService.name(UIPencilInteraction.preferredTapAction))")
        }

        func pencilInteraction(_ interaction: UIPencilInteraction, didReceiveSqueeze squeeze: UIPencilInteraction.Squeeze) {
            let phase: String? = switch squeeze.phase {
            case .began: "began"
            case .ended: "ended"
            case .cancelled: "cancelled"
            default: nil
            }
            guard let phase else { return }
            service?.log("Squeeze \(phase)\(Self.pose(squeeze.hoverPose)) · preferred action: \(PencilLabService.name(UIPencilInteraction.preferredSqueezeAction))")
        }

        private static func pose(_ pose: UIPencilHoverPose?) -> String {
            guard let pose else { return " (Pencil not hovering)" }
            return " while hovering at \(Int(pose.location.x)), \(Int(pose.location.y)) pt, z \(String(format: "%.2f", pose.zOffset)), roll \(PencilFormatting.degrees(Double(pose.rollAngle)))"
        }
    }
}

/// Observes touches on the canvas without claiming them, so the readout never interferes with drawing.
private final class TouchProbeRecognizer: UIGestureRecognizer {
    var onSample: ((PencilSample) -> Void)?

    init() {
        super.init(target: nil, action: nil)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) { report(touches, event, phase: "began") }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) { report(touches, event, phase: "moved") }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        report(touches, event, phase: "ended")
        state = .failed
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        report(touches, event, phase: "cancelled")
        state = .failed
    }

    private func report(_ touches: Set<UITouch>, _ event: UIEvent, phase: String) {
        guard let touch = touches.first, let view else { return }
        onSample?(PencilSample(
            type: PencilLabService.touchType(touch.type), phase: phase, location: touch.preciseLocation(in: view),
            force: Double(touch.force), maximumForce: Double(touch.maximumPossibleForce),
            altitude: Double(touch.altitudeAngle), azimuth: Double(touch.azimuthAngle(in: view)), roll: Double(touch.rollAngle),
            coalesced: event.coalescedTouches(for: touch)?.count ?? 0, predicted: event.predictedTouches(for: touch)?.count ?? 0,
            estimatedProperties: PencilLabService.estimated(touch.estimatedPropertiesExpectingUpdates)))
    }
}
#endif

// MARK: - Pointer and keyboard

struct PointerKeyboardRunView: View {
    #if os(iOS) || os(macOS)
    @StateObject private var devices = PointerKeyboardService()
    @State private var effect = PointerEffectOption.automatic
    @State private var hoverLocation: CGPoint?
    @State private var lastKey: String?
    @State private var modifiers = EventModifiers()
    @FocusState private var padFocused: Bool

    var body: some View {
        Button(devices.isMonitoring ? "Stop Monitoring" : "Start Monitoring") { devices.isMonitoring ? devices.stop() : devices.start() }
            .buttonStyle(.borderedProminent)
            .experimentSession(devices)
        LabeledContent("Hardware keyboard", value: devices.keyboardConnected ? "Connected (GCKeyboard)" : "None reported")
        LabeledContent("Mice and trackpads", value: devices.mice == 0 ? "None reported" : "\(devices.mice) (GCMouse)")
        Picker(pointerPickerTitle, selection: $effect) {
            ForEach(PointerEffectOption.platformCases) { Text($0.rawValue).tag($0) }
        }
        pad
        Section("SwiftUI events") {
            LabeledContent("Hover location", value: hoverLocation.map { "\(Int($0.x)), \(Int($0.y)) pt" } ?? "Pointer is not over the pad")
            LabeledContent("Last key press", value: lastKey ?? "Focus the pad, then type")
            LabeledContent(modifiersTitle, value: Self.symbols(modifiers))
        }
        Section("Raw input · GameController") {
            LabeledContent("Key", value: devices.rawKey ?? "—")
            LabeledContent("Modifiers", value: devices.rawModifiers)
            LabeledContent("Mouse delta", value: "\(Int(devices.mouseDelta.width)), \(Int(devices.mouseDelta.height))")
            LabeledContent("Mouse buttons", value: devices.mouseButtons)
        }
        OutputView(text: devices.output, isError: false)
        #if os(iOS)
        if UIDevice.current.userInterfaceIdiom == .phone {
            Text("iPhone accepts hardware keyboards, but has no pointer: a connected mouse only works through AssistiveTouch, so hover and pointer effects stay silent.")
                .font(.caption).foregroundStyle(.secondary)
        }
        #endif
    }

    private var modifiersTitle: String {
        #if os(macOS)
        "Modifiers held"
        #else
        "Modifiers with last key"
        #endif
    }

    private var pointerPickerTitle: String {
        #if os(macOS)
        "Pointer style"
        #else
        "Hover effect"
        #endif
    }

    private var pad: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14)
                .fill(padFocused ? Color.accentColor.opacity(0.14) : Color.secondary.opacity(0.1))
            VStack(spacing: 6) {
                Image(systemName: padFocused ? "keyboard" : "cursorarrow.rays").font(.title)
                Text(padFocused ? "Keys go to this pad now" : "Hover here, then tap or click to type").font(.callout)
            }
            .foregroundStyle(.secondary)
            if let hoverLocation {
                Circle().fill(.tint).frame(width: 10, height: 10).position(hoverLocation)
            }
        }
        .frame(height: 200)
        .contentShape(RoundedRectangle(cornerRadius: 14))
        .onContinuousHover(coordinateSpace: .local) { phase in
            switch phase {
            case .active(let location): hoverLocation = location
            case .ended: hoverLocation = nil
            }
        }
        .modifier(PointerEffectModifier(option: effect))
        .focusable()
        .focused($padFocused)
        .onTapGesture { padFocused = true }
        .onKeyPress(phases: .all) { press in
            // Tab and Escape keep moving focus as usual.
            guard press.key != .tab, press.key != .escape else { return .ignored }
            lastKey = Self.describe(press)
            #if os(iOS)
            // iOS has no onModifierKeysChanged; the key press carries the modifiers held at that moment.
            modifiers = press.modifiers
            #endif
            return .handled
        }
        .modifier(ModifierKeysObserver(modifiers: $modifiers))
    }

    private static func describe(_ press: KeyPress) -> String {
        let phase = switch press.phase {
        case .down: "down"
        case .repeat: "repeat"
        case .up: "up"
        default: "all"
        }
        let names: [KeyEquivalent: String] = [
            .return: "Return", .space: "Space", .delete: "Delete", .deleteForward: "Forward Delete", .upArrow: "↑", .downArrow: "↓",
            .leftArrow: "←", .rightArrow: "→", .home: "Home", .end: "End", .pageUp: "Page Up", .pageDown: "Page Down", .clear: "Clear",
        ]
        let key = names[press.key] ?? (press.characters.isEmpty ? "U+\(String(press.key.character.unicodeScalars.first?.value ?? 0, radix: 16, uppercase: true))" : "“\(press.characters)”")
        let modifiers = symbols(press.modifiers)
        return "\(key) \(phase)" + (modifiers == "None" ? "" : " with \(modifiers)")
    }

    private static func symbols(_ modifiers: EventModifiers) -> String {
        KeyboardFormatting.modifiers(capsLock: modifiers.contains(.capsLock), shift: modifiers.contains(.shift), control: modifiers.contains(.control),
                                     option: modifiers.contains(.option), command: modifiers.contains(.command))
    }
    #else
    var body: some View {
        OutputView(text: "Hardware keyboard and pointer input is an iPadOS, iOS and macOS feature. On Apple TV, see the Game Controller experiment for the Siri Remote.", isError: true)
    }
    #endif
}

#if os(iOS) || os(macOS)
/// Live modifier state where SwiftUI offers it (macOS); on iOS the key press handler updates it.
private struct ModifierKeysObserver: ViewModifier {
    @Binding var modifiers: EventModifiers

    func body(content: Content) -> some View {
        #if os(macOS)
        content.onModifierKeysChanged(mask: .all, initial: true) { _, new in modifiers = new }
        #else
        content
        #endif
    }
}

private struct PointerEffectModifier: ViewModifier {
    let option: PointerEffectOption

    func body(content: Content) -> some View {
        #if os(macOS)
        let style: PointerStyle? = switch option {
        case .link: .link
        case .grab: .grabIdle
        case .text: .horizontalText
        case .crosshair: .rectSelection
        default: nil
        }
        content.pointerStyle(style).pointerVisibility(option == .hidden ? .hidden : .automatic)
        #else
        switch option {
        case .highlight: content.hoverEffect(.highlight)
        case .lift: content.hoverEffect(.lift)
        case .disabled: content.hoverEffectDisabled()
        default: content.hoverEffect(.automatic)
        }
        #endif
    }
}
#endif

// MARK: - Windows and displays

enum WindowProbe {
    /// Scene identifier of the secondary window group in `AppleToolboxApp`.
    static let sceneID = "window-probe"
}

struct WindowsDisplaysRunView: View {
    #if os(iOS)
    @StateObject private var windows = WindowLabService()
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.supportsMultipleWindows) private var supportsMultipleWindows
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        LabeledContent("Size classes (SwiftUI)", value: "\(Self.name(horizontalSizeClass)) width · \(Self.name(verticalSizeClass)) height")
            .background(WindowSceneProbe { windows.attach(to: $0) })
        ForEach(windows.window) { LabeledContent($0.title, value: $0.value) }
        Section("Windows · UIApplication and openWindow") {
            ForEach(windows.scenes) { LabeledContent($0.title, value: $0.value) }
            LabeledContent("supportsMultipleWindows", value: supportsMultipleWindows ? "true" : "false")
            Button("Open Another Window", systemImage: "macwindow.badge.plus") { openWindow(id: WindowProbe.sceneID) }
                .disabled(!supportsMultipleWindows)
            if !supportsMultipleWindows {
                Text("SwiftUI reports that this device or scene configuration shows one window at a time (always the case on iPhone).")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        Section("Displays · UIScreen of each scene") {
            ForEach(windows.screens) { FactGroupRow(title: $0.name, symbol: "display", facts: $0.facts) }
        }
        OutputView(text: windows.output, isError: false)
        Text("iPadOS has no public API that says whether Stage Manager, windowed apps or full-screen apps is active, so the layout is inferred from the window and screen sizes. External displays appear once a scene of this app is on them.")
            .font(.caption).foregroundStyle(.secondary)
    }

    private static func name(_ sizeClass: UserInterfaceSizeClass?) -> String {
        switch sizeClass {
        case .compact: "Compact"
        case .regular: "Regular"
        default: "Unspecified"
        }
    }
    #else
    var body: some View {
        OutputView(text: "Size classes, window scenes and UIScreen are iPadOS and iOS concepts. On the Mac, Mac Hardware lists the connected displays.", isError: true)
    }
    #endif
}

#if os(iOS)
/// Reports the window scene that hosts the run view.
private struct WindowSceneProbe: UIViewRepresentable {
    let onScene: (UIWindowScene?) -> Void

    func makeUIView(context: Context) -> ProbeView {
        let view = ProbeView()
        view.isUserInteractionEnabled = false
        view.onScene = onScene
        return view
    }

    func updateUIView(_ view: ProbeView, context: Context) { view.onScene = onScene }

    final class ProbeView: UIView {
        var onScene: ((UIWindowScene?) -> Void)?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            // Report after the current SwiftUI update, since the service publishes new state in response.
            let scene = window?.windowScene
            Task { @MainActor [weak self] in self?.onScene?(scene) }
        }
    }
}

/// Content of the secondary window opened by the Windows & Displays experiment.
struct WindowProbeView: View {
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 12) {
                Image(systemName: "macwindow").font(.largeTitle).foregroundStyle(.tint)
                Text("Window Probe").font(.title2.weight(.semibold))
                Text(WindowFormatting.size(proxy.size)).font(.title3.monospacedDigit())
                Text("A second scene opened with openWindow(id:). Resize it or move it to another display; the Windows & Displays experiment in the first window lists every connected scene.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                Button("Close Window", systemImage: "xmark") { dismissWindow() }
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
#endif
