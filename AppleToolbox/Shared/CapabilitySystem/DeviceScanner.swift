import Foundation
#if canImport(CryptoKit)
import CryptoKit
#endif
#if canImport(LocalAuthentication) && !os(watchOS) && !os(tvOS)
import LocalAuthentication
#endif
#if canImport(CoreMotion) && (os(iOS) || os(watchOS))
import CoreMotion
#endif
#if canImport(CoreLocation)
import CoreLocation
#endif
#if canImport(CoreNFC) && os(iOS)
import CoreNFC
#endif
#if canImport(NearbyInteraction) && (os(iOS) || os(watchOS))
import NearbyInteraction
#endif
#if canImport(AVFoundation)
import AVFoundation
#endif
#if canImport(CoreHaptics) && !os(watchOS)
import CoreHaptics
#endif
#if canImport(GameController) && !os(watchOS)
import GameController
#endif
#if canImport(FoundationModels) && (os(iOS) || os(macOS))
import FoundationModels
#endif
#if canImport(ARKit) && os(iOS)
import ARKit
#endif
#if canImport(HealthKit) && !os(tvOS)
import HealthKit
#endif
#if canImport(PassKit) && !os(tvOS)
import PassKit
#endif
#if canImport(WatchConnectivity) && !os(tvOS)
import WatchConnectivity
#endif
#if canImport(Network)
import Network
#endif
#if canImport(MatterSupport) && (os(iOS) || os(macOS))
import MatterSupport
#endif
#if canImport(MusicKit)
import MusicKit
#endif
#if canImport(UIKit)
import UIKit
#endif
#if os(macOS)
import AppKit
import CoreAudio
#endif
#if os(watchOS)
import WatchKit
#endif

nonisolated enum CapabilityState: String, Sendable {
    case available = "Available"
    case unavailable = "Unavailable"
    case unknown = "Unknown"

    var marker: String {
        switch self {
        case .available: "✓"
        case .unavailable: "✗"
        case .unknown: "?"
        }
    }
}

nonisolated struct CapabilityItem: Identifiable, Sendable {
    let name: String
    let detail: String
    let state: CapabilityState
    var id: String { name }

    static func available(_ name: String, _ detail: String) -> CapabilityItem { CapabilityItem(name: name, detail: detail, state: .available) }
    static func unavailable(_ name: String, _ detail: String) -> CapabilityItem { CapabilityItem(name: name, detail: detail, state: .unavailable) }
    static func unknown(_ name: String, _ detail: String) -> CapabilityItem { CapabilityItem(name: name, detail: detail, state: .unknown) }
    static func flag(_ name: String, _ value: Bool, yes: String = "Supported on this device", no: String = "Not supported on this device") -> CapabilityItem {
        value ? .available(name, yes) : .unavailable(name, no)
    }
}

nonisolated struct CapabilitySection: Identifiable, Sendable {
    let title: String
    let symbol: String
    let items: [CapabilityItem]
    var id: String { title }
}

nonisolated struct DeviceScanReport: Sendable {
    let date: Date
    let platform: String
    let sections: [CapabilitySection]

    func count(_ state: CapabilityState) -> Int {
        sections.reduce(0) { total, section in total + section.items.filter { $0.state == state }.count }
    }
}

/// Scans the current device with public APIs only. Nothing here requests authorization,
/// creates a Bluetooth/HomeKit manager, or starts a session, so a scan never shows a permission prompt.
@MainActor
enum DeviceScanner {
    static func scan() async -> DeviceScanReport {
        let system = deviceItems()
        let display = displayItems()
        let controllers = gameControllerItem()
        let pairing = watchPairingItems()
        let home = [matterItem(), await musicKitItem()]
        // Location Services and capture-device discovery must not block the main thread.
        let probes = Task.detached(priority: .userInitiated) { DeviceProbes.run() }
        let network = await DeviceProbes.networkInterfaceItems()
        let probed = await probes.value
        return DeviceScanReport(date: Date(), platform: CurrentPlatform.value.rawValue, sections: [
            CapabilitySection(title: "Hardware", symbol: "cpu", items: probed.hardware + network + [controllers]),
            CapabilitySection(title: "Sensors", symbol: "gyroscope", items: probed.sensors),
            CapabilitySection(title: "Cameras & Audio", symbol: "camera", items: probed.media),
            CapabilitySection(title: "Display", symbol: "display", items: display),
            CapabilitySection(title: "Apple Features", symbol: "sparkles", items: probed.features + pairing + home),
            CapabilitySection(title: "System", symbol: "gearshape", items: system + probed.system)
        ])
    }

    private static func deviceItems() -> [CapabilityItem] {
        let version = ProcessInfo.processInfo.operatingSystemVersionString
        #if os(watchOS)
        let device = WKInterfaceDevice.current()
        return [.available("Device", device.model), .available("Operating system", "\(device.systemName) \(version)")]
        #elseif canImport(UIKit)
        let device = UIDevice.current
        return [.available("Device", device.model), .available("Operating system", "\(device.systemName) \(version)")]
        #else
        return [.available("Device", "Mac"), .available("Operating system", "macOS \(version)")]
        #endif
    }

    private static func displayItems() -> [CapabilityItem] {
        #if os(iOS) || os(tvOS)
        guard let screen = UIApplication.shared.connectedScenes.lazy.compactMap({ ($0 as? UIWindowScene)?.screen }).first else {
            return [.unknown("Display", "No connected window scene to read the screen from.")]
        }
        let pixels = screen.nativeBounds.size, points = screen.bounds.size
        var items: [CapabilityItem] = [
            .available("Resolution", "\(Int(pixels.width)) × \(Int(pixels.height)) px · \(Int(points.width)) × \(Int(points.height)) pt"),
            .available("Scale", "\(DeviceProbes.number(screen.scale))× (native \(DeviceProbes.number(screen.nativeScale))×)"),
            .available("Maximum refresh rate", "\(screen.maximumFramesPerSecond) Hz")
        ]
        switch screen.traitCollection.displayGamut {
        case .P3: items.append(.available("Wide color", "Display P3 gamut"))
        case .SRGB: items.append(.unavailable("Wide color", "sRGB gamut"))
        default: items.append(.unknown("Wide color", "The system did not specify a display gamut."))
        }
        let headroom = screen.potentialEDRHeadroom
        items.append(headroom > 1 ? .available("HDR / EDR", "Up to \(DeviceProbes.number(headroom))× SDR brightness") : .unavailable("HDR / EDR", "No extended dynamic range headroom reported"))
        return items
        #elseif os(macOS)
        let screens = NSScreen.screens
        guard let screen = NSScreen.main ?? screens.first else { return [.unknown("Display", "NSScreen reports no screen.")] }
        let points = screen.frame.size, scale = screen.backingScaleFactor
        let headroom = screen.maximumPotentialExtendedDynamicRangeColorComponentValue
        return [
            .available("Main display", screen.localizedName),
            .available("Resolution", "\(Int(points.width * scale)) × \(Int(points.height * scale)) px · \(Int(points.width)) × \(Int(points.height)) pt"),
            .available("Scale", "\(DeviceProbes.number(scale))×"),
            .available("Maximum refresh rate", "\(screen.maximumFramesPerSecond) Hz"),
            .flag("Wide color", screen.canRepresent(.p3), yes: "Display P3 gamut", no: "sRGB gamut"),
            headroom > 1 ? .available("HDR / EDR", "Up to \(DeviceProbes.number(headroom))× SDR brightness") : .unavailable("HDR / EDR", "No extended dynamic range headroom reported"),
            .available("Connected displays", "\(screens.count)")
        ]
        #elseif os(watchOS)
        let device = WKInterfaceDevice.current()
        let bounds = device.screenBounds, scale = device.screenScale
        return [
            .available("Resolution", "\(Int(bounds.width * scale)) × \(Int(bounds.height * scale)) px · \(Int(bounds.width)) × \(Int(bounds.height)) pt"),
            .available("Scale", "\(DeviceProbes.number(scale))×"),
            .unknown("Maximum refresh rate", "Not exposed by a public watchOS API.")
        ]
        #else
        return [.unknown("Display", "No display API on this platform.")]
        #endif
    }

    private static func gameControllerItem() -> CapabilityItem {
        #if canImport(GameController) && !os(watchOS)
        let controllers = GCController.controllers()
        guard !controllers.isEmpty else { return .unavailable("Game controllers", "None connected. Connect a controller and rescan.") }
        return .available("Game controllers", controllers.map { $0.vendorName ?? "Controller" }.joined(separator: ", "))
        #else
        return .unavailable("Game controllers", "GameController is not available on this platform.")
        #endif
    }

    /// Pairing is only read from the already activated WatchConnectivity session; the scanner never activates one.
    /// MatterAddDeviceRequest.isSupported: whether this device can add Matter accessories through MatterSupport.
    private static func matterItem() -> CapabilityItem {
        #if canImport(MatterSupport) && (os(iOS) || os(macOS))
        return .flag("Matter", MatterAddDeviceRequest.isSupported, yes: "MatterAddDeviceRequest.isSupported · accessory setup available",
                     no: "MatterAddDeviceRequest.isSupported is false on this device")
        #else
        return .unavailable("Matter", "MatterSupport is not available on this platform.")
        #endif
    }

    /// MusicAuthorization.currentStatus never prompts; the subscription is only read once access was granted.
    private static func musicKitItem() async -> CapabilityItem {
        #if canImport(MusicKit)
        let name = "MusicKit"
        switch MusicAuthorization.currentStatus {
        case .authorized:
            do {
                let subscription = try await MusicSubscription.current
                let detail = "Authorized · catalog playback: \(yesNo(subscription.canPlayCatalogContent)) · can subscribe: \(yesNo(subscription.canBecomeSubscriber)) · cloud library: \(yesNo(subscription.hasCloudLibraryEnabled))"
                return subscription.canPlayCatalogContent ? .available(name, detail) : .unavailable(name, detail)
            } catch {
                return .unknown(name, "Authorized, but MusicSubscription.current failed: \(error.localizedDescription)")
            }
        case .notDetermined: return .unknown(name, "Not asked yet: the subscription is read after access is granted in the MusicKit experiment.")
        case .denied: return .unavailable(name, "Access to Apple Music was denied in Settings.")
        case .restricted: return .unavailable(name, "Access to Apple Music is restricted on this device.")
        @unknown default: return .unknown(name, "Unknown authorization status.")
        }
        #else
        return .unavailable("MusicKit", "MusicKit is not available on this platform.")
        #endif
    }

    private static func yesNo(_ value: Bool) -> String { value ? "yes" : "no" }

    private static func watchPairingItems() -> [CapabilityItem] {
        #if os(iOS) && canImport(WatchConnectivity)
        guard WCSession.isSupported() else { return [] }
        let continuity = ContinuityExperimentService.shared
        guard let paired = continuity.isPaired else {
            return [.unknown("Apple Watch pairing", "Not checked: the WatchConnectivity session is not activated yet. See the WatchConnectivity experiment.")]
        }
        let app = continuity.isCounterpartInstalled.map { $0 ? "watch app installed" : "watch app not installed" } ?? "watch app state unknown"
        return [paired ? .available("Apple Watch pairing", "Paired · \(app)") : .unavailable("Apple Watch pairing", "No Apple Watch paired")]
        #else
        return []
        #endif
    }
}

/// Probes that are safe to run off the main actor.
nonisolated enum DeviceProbes {
    nonisolated struct Results: Sendable {
        let hardware: [CapabilityItem]
        let sensors: [CapabilityItem]
        let media: [CapabilityItem]
        let features: [CapabilityItem]
        let system: [CapabilityItem]
    }

    nonisolated struct Biometry: Sendable {
        let name: String?
        let isReady: Bool
        let reason: String?
    }

    static func run() -> Results {
        Results(hardware: hardware(), sensors: sensors(), media: camerasAndAudio(), features: appleFeatures(), system: system())
    }

    // MARK: Shared with DeviceCapabilities

    /// Hardware facts: read once, they cannot change while the app runs.
    static let hasSecureEnclave: Bool = {
        #if canImport(CryptoKit)
        SecureEnclave.isAvailable
        #else
        false
        #endif
    }()

    static let hasMotionSensors: Bool = {
        #if canImport(CoreMotion) && (os(iOS) || os(watchOS))
        let manager = CMMotionManager()
        return manager.isDeviceMotionAvailable || manager.isAccelerometerAvailable
        #else
        return false
        #endif
    }()

    static var hasCoreLocation: Bool {
        #if canImport(CoreLocation)
        true
        #else
        false
        #endif
    }

    /// `canEvaluatePolicy` only inspects state; the Face ID prompt appears on `evaluatePolicy`, which is never called here.
    static func biometry() -> Biometry {
        #if canImport(LocalAuthentication) && !os(watchOS) && !os(tvOS)
        let context = LAContext()
        var error: NSError?
        let ready = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
        let name: String?
        switch context.biometryType {
        case .faceID: name = "Face ID"
        case .touchID: name = "Touch ID"
        case .opticID: name = "Optic ID"
        case .none: name = nil
        @unknown default: name = ready ? "Biometrics" : nil
        }
        let reason: String? = error.map { error in
            switch LAError.Code(rawValue: error.code) {
            case .biometryNotEnrolled: "no biometrics enrolled"
            case .biometryLockout: "locked out after failed attempts"
            case .biometryNotAvailable: "not available to this app or device"
            case .passcodeNotSet: "no device passcode set"
            default: error.localizedDescription
            }
        }
        return Biometry(name: name, isReady: ready, reason: reason)
        #else
        return Biometry(name: nil, isReady: false, reason: "LocalAuthentication biometrics are not available on this platform")
        #endif
    }

    static func number(_ value: Double) -> String { value.formatted(.number.precision(.fractionLength(0...2))) }

    // MARK: Hardware

    private static func hardware() -> [CapabilityItem] {
        let biometry = biometry()
        let biometrics: CapabilityItem = biometry.name.map { name in
            .available("Biometrics", biometry.isReady ? "\(name) enrolled and ready" : "\(name) · \(biometry.reason ?? "not ready")")
        } ?? .unavailable("Biometrics", biometry.reason.map { "No Face ID, Touch ID or Optic ID: \($0)" } ?? "No Face ID, Touch ID or Optic ID reported")
        return [
            modelIdentifier(),
            chip(),
            .available("CPU", processorDetail()),
            .available("Memory", ByteCountFormatter.string(fromByteCount: Int64(ProcessInfo.processInfo.physicalMemory), countStyle: .memory)),
            .flag("Secure Enclave", hasSecureEnclave, yes: "CryptoKit can create hardware-backed keys", no: "CryptoKit reports no Secure Enclave"),
            biometrics,
            nfc(),
            ultraWideband(),
            haptics(),
            .unknown("Bluetooth", "Not probed: reading the radio state needs a CBCentralManager, which shows the Bluetooth prompt. Use the Core Bluetooth experiment."),
            .unknown("GPS / GNSS", "Core Location does not reveal whether a satellite receiver is present; positions may come from Wi-Fi or cellular.")
        ]
    }

    private static func modelIdentifier() -> CapabilityItem {
        #if targetEnvironment(simulator)
        if let identifier = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] {
            return .available("Model identifier", "\(identifier) (Simulator)")
        }
        #endif
        #if os(macOS)
        let identifier = sysctlString("hw.model")
        #else
        var info = utsname()
        let identifier: String? = uname(&info) == 0 ? withUnsafeBytes(of: &info.machine) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) } : nil
        #endif
        guard let identifier, !identifier.isEmpty else { return .unknown("Model identifier", "The system did not return a model identifier.") }
        return .available("Model identifier", identifier)
    }

    private static func chip() -> CapabilityItem {
        guard let brand = sysctlString("machdep.cpu.brand_string") else {
            return .unknown("Chip", "No public API names the chip on this platform; the model identifier determines it.")
        }
        #if targetEnvironment(simulator)
        return .available("Chip", "\(brand) (the Mac running the Simulator)")
        #else
        return .available("Chip", brand)
        #endif
    }

    private static func processorDetail() -> String {
        let info = ProcessInfo.processInfo
        var detail = "\(info.activeProcessorCount) of \(info.processorCount) cores active"
        if let performance = sysctlInt("hw.perflevel0.physicalcpu"), let efficiency = sysctlInt("hw.perflevel1.physicalcpu") {
            detail += " · \(performance) performance + \(efficiency) efficiency"
        }
        return detail
    }

    private static func nfc() -> CapabilityItem {
        #if canImport(CoreNFC) && os(iOS)
        return .flag("NFC tag reading", NFCNDEFReaderSession.readingAvailable, yes: "Core NFC reader sessions are supported", no: "Core NFC reports that this device cannot read tags")
        #else
        return .unavailable("NFC tag reading", "Core NFC is only available on iPhone.")
        #endif
    }

    private static func ultraWideband() -> CapabilityItem {
        #if canImport(NearbyInteraction) && (os(iOS) || os(watchOS))
        return .flag("Ultra Wideband", NISession.deviceCapabilities.supportsPreciseDistanceMeasurement, yes: "Nearby Interaction supports precise distance measurement", no: "Nearby Interaction reports no precise distance measurement")
        #else
        return .unavailable("Ultra Wideband", "Nearby Interaction device capabilities are not available on this platform.")
        #endif
    }

    private static func haptics() -> CapabilityItem {
        #if canImport(CoreHaptics) && !os(watchOS)
        let capabilities = CHHapticEngine.capabilitiesForHardware()
        return .flag("Haptics", capabilities.supportsHaptics, yes: "Core Haptics supported\(capabilities.supportsAudio ? " · haptic audio" : "")", no: "Core Haptics reports no haptic hardware")
        #else
        return .unknown("Haptics", "Core Haptics is not available on watchOS; WatchKit plays system haptics without a capability query.")
        #endif
    }

    // MARK: Network

    static func networkInterfaceItems() async -> [CapabilityItem] {
        #if canImport(Network)
        guard let interfaces = await NetworkPathProbe().run() else {
            return [.unknown("Network interfaces", "The network path did not report within 2 seconds.")]
        }
        let kinds: [(String, NWInterface.InterfaceType)] = [("Wi-Fi", .wifi), ("Cellular", .cellular), ("Wired Ethernet", .wiredEthernet)]
        return kinds.map { name, type in
            interfaces.contains(type) ? .available(name, "Active on the current network path") : .unknown(name, "No active interface; the hardware may still exist but be off or disconnected.")
        }
        #else
        return [.unknown("Network interfaces", "Network framework is not available on this platform.")]
        #endif
    }

    // MARK: Sensors

    private static func sensors() -> [CapabilityItem] {
        var items: [CapabilityItem] = []
        #if canImport(CoreMotion) && (os(iOS) || os(watchOS))
        let motion = CMMotionManager()
        let steps = CMPedometer.isStepCountingAvailable()
        items += [
            .flag("Accelerometer", motion.isAccelerometerAvailable),
            .flag("Gyroscope", motion.isGyroAvailable),
            .flag("Magnetometer", motion.isMagnetometerAvailable),
            .flag("Device motion", motion.isDeviceMotionAvailable, yes: "Sensor-fused attitude, gravity and rotation"),
            .flag("Barometer", CMAltimeter.isRelativeAltitudeAvailable(), yes: "Relative altitude changes supported"),
            .flag("Absolute altitude", CMAltimeter.isAbsoluteAltitudeAvailable()),
            steps ? .available("Pedometer", "Steps · distance: \(yesNo(CMPedometer.isDistanceAvailable())) · floors: \(yesNo(CMPedometer.isFloorCountingAvailable()))") : .unavailable("Pedometer", "Step counting not supported"),
            .flag("Motion activity", CMMotionActivityManager.isActivityAvailable(), yes: "Walking, running, driving detection supported")
        ]
        #else
        items.append(.unavailable("Motion sensors", "Core Motion accelerometer, gyroscope and barometer are not available on this platform."))
        #endif
        #if canImport(CoreLocation)
        items.append(CLLocationManager.locationServicesEnabled() ? .available("Location Services", "Switched on system-wide") : .unavailable("Location Services", "Switched off system-wide in Settings"))
        #if os(tvOS)
        items.append(.unavailable("Compass heading", "Heading updates are not available on tvOS."))
        #else
        items.append(.flag("Compass heading", CLLocationManager.headingAvailable()))
        #endif
        #if os(iOS) || os(macOS)
        items += [
            .flag("Significant-change monitoring", CLLocationManager.significantLocationChangeMonitoringAvailable()),
            .flag("Region monitoring", CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self)),
            .flag("Beacon ranging", CLLocationManager.isRangingAvailable())
        ]
        #endif
        #endif
        return items
    }

    // MARK: Cameras & audio

    private static func camerasAndAudio() -> [CapabilityItem] {
        var items: [CapabilityItem] = []
        #if canImport(AVFoundation) && !os(watchOS)
        #if os(iOS)
        let types: [AVCaptureDevice.DeviceType] = [.builtInWideAngleCamera, .builtInUltraWideCamera, .builtInTelephotoCamera, .builtInTrueDepthCamera, .builtInLiDARDepthCamera, .external]
        #elseif os(macOS)
        let types: [AVCaptureDevice.DeviceType] = [.builtInWideAngleCamera, .continuityCamera, .external]
        #else
        let types: [AVCaptureDevice.DeviceType] = [.continuityCamera]
        #endif
        // Enumerating devices does not open them, so no camera prompt is shown.
        let cameras = AVCaptureDevice.DiscoverySession(deviceTypes: types, mediaType: .video, position: .unspecified).devices
        func camera(_ name: String, _ matches: (AVCaptureDevice) -> Bool) -> CapabilityItem {
            let found = cameras.filter(matches)
            return found.isEmpty ? .unavailable(name, "Not reported by capture-device discovery") : .available(name, found.map(\.localizedName).joined(separator: ", "))
        }
        #if os(iOS)
        items += [
            camera("Back camera") { $0.deviceType == .builtInWideAngleCamera && $0.position == .back },
            camera("Ultra-wide camera") { $0.deviceType == .builtInUltraWideCamera },
            camera("Telephoto camera") { $0.deviceType == .builtInTelephotoCamera },
            camera("Front camera") { $0.position == .front },
            camera("TrueDepth camera") { $0.deviceType == .builtInTrueDepthCamera },
            camera("LiDAR depth camera") { $0.deviceType == .builtInLiDARDepthCamera },
            camera("External cameras") { $0.deviceType == .external }
        ]
        #elseif os(macOS)
        items += [
            camera("Built-in camera") { $0.deviceType == .builtInWideAngleCamera },
            camera("Continuity Camera") { $0.deviceType == .continuityCamera },
            camera("External cameras") { $0.deviceType == .external }
        ]
        #else
        items.append(camera("Continuity Camera") { $0.deviceType == .continuityCamera })
        #endif
        let microphones = AVCaptureDevice.DiscoverySession(deviceTypes: [.microphone], mediaType: .audio, position: .unspecified).devices
        items.append(microphones.isEmpty ? .unavailable("Microphone", "No audio capture device reported") : .available("Microphone", microphones.map(\.localizedName).joined(separator: ", ")))
        #elseif canImport(AVFoundation)
        items.append(.flag("Microphone", AVAudioSession.sharedInstance().isInputAvailable, yes: "Audio input route available", no: "No audio input route available"))
        #endif
        items.append(audioOutput())
        return items
    }

    private static func audioOutput() -> CapabilityItem {
        #if os(macOS)
        guard let name = defaultOutputDeviceName() else { return .unavailable("Audio output", "Core Audio reports no default output device") }
        return .available("Audio output", name)
        #elseif canImport(AVFoundation)
        let outputs = AVAudioSession.sharedInstance().currentRoute.outputs
        guard !outputs.isEmpty else { return .unknown("Audio output", "No output route reported") }
        return .available("Audio output", outputs.map(\.portName).joined(separator: ", "))
        #else
        return .unknown("Audio output", "No audio route API on this platform.")
        #endif
    }

    #if os(macOS)
    private static func defaultOutputDeviceName() -> String? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr, device != kAudioObjectUnknown else { return nil }
        address.mSelector = kAudioObjectPropertyName
        var name: Unmanaged<CFString>?
        size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = withUnsafeMutablePointer(to: &name) { AudioObjectGetPropertyData(device, &address, 0, nil, &size, $0) }
        guard status == noErr, let name else { return "Default output device" }
        return name.takeRetainedValue() as String
    }
    #endif

    // MARK: Apple features

    private static func appleFeatures() -> [CapabilityItem] {
        var items = [appleIntelligence(), nearbyInteraction(), wallet(), applePay(), healthKit(), watchConnectivity()]
        #if canImport(ARKit) && os(iOS)
        items += [
            .flag("ARKit world tracking", ARWorldTrackingConfiguration.isSupported),
            .flag("ARKit scene depth", ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth), yes: "LiDAR depth frames supported", no: "No scene depth (requires LiDAR)"),
            .flag("ARKit face tracking", ARFaceTrackingConfiguration.isSupported)
        ]
        #else
        items.append(.unavailable("ARKit", "ARKit world tracking is only available on iPhone and iPad."))
        #endif
        #if os(macOS)
        items.append(.unavailable("HomeKit", "HomeKit is not available to native macOS apps."))
        #else
        items.append(.unknown("HomeKit", "Not probed: creating an HMHomeManager shows the HomeKit prompt. Use the HomeKit experiment."))
        #endif
        #if os(iOS)
        items.append(.unknown("CarPlay", "No public API reports CarPlay support for this device."))
        #endif
        return items
    }

    private static func appleIntelligence() -> CapabilityItem {
        #if canImport(FoundationModels) && (os(iOS) || os(macOS))
        let name = "Apple Intelligence"
        switch SystemLanguageModel.default.availability {
        case .available: return .available(name, "On-device foundation model is ready")
        case .unavailable(.deviceNotEligible): return .unavailable(name, "This device is not eligible for Apple Intelligence")
        case .unavailable(.appleIntelligenceNotEnabled): return .unavailable(name, "Eligible, but Apple Intelligence is turned off in Settings")
        case .unavailable(.modelNotReady): return .unavailable(name, "Enabled, but the model is not ready yet (downloading or preparing)")
        case .unavailable(let reason): return .unknown(name, "Unavailable: \(reason)")
        }
        #else
        return .unavailable("Apple Intelligence", "Foundation Models is not available on this platform.")
        #endif
    }

    private static func nearbyInteraction() -> CapabilityItem {
        #if canImport(NearbyInteraction) && (os(iOS) || os(watchOS))
        let capabilities = NISession.deviceCapabilities
        let detail = "Direction: \(yesNo(capabilities.supportsDirectionMeasurement)) · camera assistance: \(yesNo(capabilities.supportsCameraAssistance)) · extended distance: \(yesNo(capabilities.supportsExtendedDistanceMeasurement))"
        return capabilities.supportsPreciseDistanceMeasurement ? .available("Nearby Interaction", detail) : .unavailable("Nearby Interaction", "No precise distance measurement on this device")
        #else
        return .unavailable("Nearby Interaction", "Not available on this platform.")
        #endif
    }

    private static func wallet() -> CapabilityItem {
        #if canImport(PassKit) && !os(tvOS)
        return .flag("Wallet", PKPassLibrary.isPassLibraryAvailable(), yes: "Pass library available", no: "Pass library not available on this device")
        #else
        return .unavailable("Wallet", "The pass library is not available on this platform.")
        #endif
    }

    private static func applePay() -> CapabilityItem {
        #if canImport(PassKit) && !os(tvOS)
        return .flag("Apple Pay", PKPaymentAuthorizationController.canMakePayments(), yes: "Device supports Apple Pay (cards not checked)", no: "Apple Pay unsupported or restricted on this device")
        #else
        return .unavailable("Apple Pay", "PassKit payments are not available on this platform.")
        #endif
    }

    private static func healthKit() -> CapabilityItem {
        #if canImport(HealthKit) && !os(tvOS)
        return .flag("HealthKit", HKHealthStore.isHealthDataAvailable(), yes: "Health data store available (reading needs authorization)", no: "HealthKit reports no health data store on this device")
        #else
        return .unavailable("HealthKit", "HealthKit is not available on this platform.")
        #endif
    }

    private static func watchConnectivity() -> CapabilityItem {
        #if canImport(WatchConnectivity) && !os(tvOS)
        return .flag("WatchConnectivity", WCSession.isSupported(), yes: "Sessions supported on this device", no: "Not supported on this device (for example iPad)")
        #else
        return .unavailable("WatchConnectivity", "Not available on this platform.")
        #endif
    }

    // MARK: System

    private static func system() -> [CapabilityItem] {
        let info = ProcessInfo.processInfo
        let thermal: String
        switch info.thermalState {
        case .nominal: thermal = "Nominal"
        case .fair: thermal = "Fair"
        case .serious: thermal = "Serious (performance is being reduced)"
        case .critical: thermal = "Critical"
        @unknown default: thermal = "Unrecognized state"
        }
        #if targetEnvironment(simulator)
        let runtime = "Simulator: sensors, cameras and radios reflect the simulator, not real hardware"
        #else
        let runtime = info.isiOSAppOnMac ? "iPhone/iPad app running on a Mac" : "Physical device"
        #endif
        return [
            .available("Runtime", runtime),
            .available("Thermal state", thermal),
            .available("Low Power Mode", info.isLowPowerModeEnabled ? "On" : "Off")
        ]
    }

    // MARK: Helpers

    private static func yesNo(_ value: Bool) -> String { value ? "yes" : "no" }

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        let value = String(decoding: buffer.prefix { $0 != 0 }, as: UTF8.self)
        return value.isEmpty ? nil : value
    }

    private static func sysctlInt(_ name: String) -> Int? {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        return sysctlbyname(name, &value, &size, nil, 0) == 0 ? Int(value) : nil
    }
}

#if canImport(Network)
/// Reads the current network path once. All state is confined to `queue`.
nonisolated private final class NetworkPathProbe: @unchecked Sendable {
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "DeviceScanner.networkPath")
    private var continuation: CheckedContinuation<[NWInterface.InterfaceType]?, Never>?

    func run() async -> [NWInterface.InterfaceType]? {
        await withCheckedContinuation { continuation in
            queue.async {
                self.continuation = continuation
                self.monitor.pathUpdateHandler = { path in self.finish(path.availableInterfaces.map(\.type)) }
                self.monitor.start(queue: self.queue)
                self.queue.asyncAfter(deadline: .now() + 2) { self.finish(nil) }
            }
        }
    }

    private func finish(_ interfaces: [NWInterface.InterfaceType]?) {
        guard let continuation else { return }
        self.continuation = nil
        monitor.pathUpdateHandler = nil
        monitor.cancel()
        continuation.resume(returning: interfaces)
    }
}
#endif
