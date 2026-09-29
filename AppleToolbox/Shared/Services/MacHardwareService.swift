import Foundation
import Combine
#if os(macOS)
import AppKit
import AVFoundation
import CoreAudio
import CoreGraphics
#endif

extension ExperimentAvailability {
    /// Core Audio's hardware layer, NSScreen and mounted-volume enumeration are macOS APIs.
    static func macHardware() -> ExperimentStatus {
        #if os(macOS)
        .available
        #else
        .platformUnsupported
        #endif
    }
}

struct AudioDeviceInfo: Identifiable, Equatable {
    let id: UInt32
    let name: String
    let manufacturer: String
    let transport: String
    let inputChannels: Int
    let outputChannels: Int
    let sampleRate: Double
    let availableRates: String
    let isDefaultInput: Bool
    let isDefaultOutput: Bool
}

struct VolumeInfo: Identifiable, Equatable {
    let id: String
    let name: String
    let facts: [PlatformFact]
}

struct DisplayInfo: Identifiable, Equatable {
    let id: UInt32
    let name: String
    let facts: [PlatformFact]
}

/// Pure formatting for the Mac hardware report, testable on every platform.
nonisolated enum MacHardwareFormatting {
    /// Renders a Core Audio four-character code such as `'usb '`.
    static func fourCC(_ code: UInt32) -> String {
        let bytes = [24, 16, 8, 0].map { UInt8((code >> UInt32($0)) & 0xFF) }
        guard bytes.allSatisfy({ $0 >= 0x20 && $0 < 0x7F }) else { return String(code) }
        return String(decoding: bytes, as: UTF8.self)
    }

    /// Names the `kAudioDeviceTransportType…` constants by their four-character code.
    static func transportName(_ code: UInt32) -> String {
        switch fourCC(code) {
        case "0": "Unknown"
        case "bltn": "Built-in"
        case "grup": "Aggregate"
        case "fgrp": "Auto aggregate"
        case "virt": "Virtual"
        case "pci ": "PCI"
        case "usb ": "USB"
        case "1394": "FireWire"
        case "blue": "Bluetooth"
        case "blea": "Bluetooth LE"
        case "hdmi": "HDMI"
        case "dprt": "DisplayPort"
        case "airp": "AirPlay"
        case "eavb": "AVB"
        case "thun": "Thunderbolt"
        case "ccwd": "Continuity (wired)"
        case "ccwl": "Continuity (wireless)"
        case "rscr": "Remote screen"
        case "rstr": "Remote streaming"
        default: "Other ('\(fourCC(code))')"
        }
    }

    /// "44.1, 48 kHz" or "8–192 kHz" for continuous ranges.
    static func sampleRates(_ ranges: [ClosedRange<Double>], locale: Locale = .current) -> String {
        guard !ranges.isEmpty else { return "None reported" }
        return ranges.map { range in
            range.lowerBound == range.upperBound
                ? kilohertz(range.lowerBound, locale: locale)
                : "\(kilohertz(range.lowerBound, locale: locale))–\(kilohertz(range.upperBound, locale: locale))"
        }.joined(separator: ", ") + " kHz"
    }

    static func kilohertz(_ hertz: Double, locale: Locale = .current) -> String {
        (hertz / 1000).formatted(.number.precision(.fractionLength(0...3)).locale(locale))
    }

    static func refreshRate(minimumInterval: Double, maximumInterval: Double, maximumFPS: Int) -> String {
        guard minimumInterval > 0, maximumInterval > 0 else { return "\(maximumFPS) Hz" }
        let fastest = (1 / minimumInterval).rounded(), slowest = (1 / maximumInterval).rounded()
        return fastest == slowest ? "\(Int(fastest)) Hz (fixed)" : "\(Int(slowest))–\(Int(fastest)) Hz (adaptive)"
    }
}

#if os(macOS)
/// Reads audio devices (Core Audio HAL), cameras (AVFoundation), mounted volumes (URL resource values) and
/// displays (NSScreen, CoreGraphics). Everything is public API and works inside the App Sandbox; no IOKit.
@MainActor
final class MacHardwareService: ObservableObject {
    @Published private(set) var audioDevices: [AudioDeviceInfo] = []
    @Published private(set) var cameras: [PlatformFact] = []
    @Published private(set) var volumes: [VolumeInfo] = []
    @Published private(set) var displays: [DisplayInfo] = []
    @Published private(set) var isWatching = false
    @Published private(set) var output = "Reading hardware…"
    private var observers: [NSObjectProtocol] = []
    private var audioListener: AudioObjectPropertyListenerBlock?

    init() { refresh(reason: nil) }

    func refresh(reason: String?) {
        audioDevices = Self.readAudioDevices()
        cameras = Self.readCameras()
        volumes = Self.readVolumes()
        displays = Self.readDisplays()
        let summary = "\(audioDevices.count) audio device(s), \(cameras.count) camera(s), \(volumes.count) volume(s), \(displays.count) display(s)."
        output = reason.map { "\($0) Re-read: \(summary)" } ?? "Read at \(Date().formatted(date: .omitted, time: .standard)): \(summary)"
    }

    /// Listens for Core Audio device-list changes, display reconfiguration and volume mounts until stopped.
    func startWatching() {
        guard !isWatching else { return }
        isWatching = true
        let center = NotificationCenter.default, workspace = NSWorkspace.shared.notificationCenter
        observers = [
            center.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh(reason: "Display configuration changed.") }
            },
            workspace.addObserver(forName: NSWorkspace.didMountNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh(reason: "A volume was mounted.") }
            },
            workspace.addObserver(forName: NSWorkspace.didUnmountNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh(reason: "A volume was unmounted.") }
            },
        ]
        // The HAL calls the block on the queue passed here (main), so it may touch main-actor state.
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated { self?.refresh(reason: "The audio device list changed.") }
        }
        var address = Self.devicesAddress
        let status = AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, listener)
        audioListener = status == noErr ? listener : nil
        output = status == noErr
            ? "Watching: connect or remove an audio device, display or drive to see the lists update."
            : "Watching displays and volumes. The Core Audio listener failed with OSStatus \(status)."
    }

    func stopWatching() {
        observers.forEach {
            NotificationCenter.default.removeObserver($0)
            NSWorkspace.shared.notificationCenter.removeObserver($0)
        }
        observers = []
        if let audioListener {
            var address = Self.devicesAddress
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, audioListener)
        }
        audioListener = nil
        isWatching = false
        output = "Stopped watching for hardware changes."
    }

    // MARK: Core Audio

    private static let devicesAddress = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)

    private static func readAudioDevices() -> [AudioDeviceInfo] {
        let system = AudioObjectID(kAudioObjectSystemObject)
        let ids: [AudioObjectID] = array(system, selector: kAudioHardwarePropertyDevices)
        let defaultInput: AudioObjectID? = value(system, selector: kAudioHardwarePropertyDefaultInputDevice)
        let defaultOutput: AudioObjectID? = value(system, selector: kAudioHardwarePropertyDefaultOutputDevice)
        return ids.map { id in
            let ranges: [AudioValueRange] = array(id, selector: kAudioDevicePropertyAvailableNominalSampleRates)
            let transport: UInt32? = value(id, selector: kAudioDevicePropertyTransportType)
            let rate: Float64? = value(id, selector: kAudioDevicePropertyNominalSampleRate)
            return AudioDeviceInfo(
                id: id,
                name: string(id, selector: kAudioObjectPropertyName) ?? "Audio device \(id)",
                manufacturer: string(id, selector: kAudioObjectPropertyManufacturer) ?? "Unknown",
                transport: transport.map(MacHardwareFormatting.transportName) ?? "Unknown",
                inputChannels: channels(id, scope: kAudioObjectPropertyScopeInput),
                outputChannels: channels(id, scope: kAudioObjectPropertyScopeOutput),
                sampleRate: rate ?? 0,
                availableRates: MacHardwareFormatting.sampleRates(ranges.map { $0.mMinimum...max($0.mMinimum, $0.mMaximum) }),
                isDefaultInput: id == defaultInput,
                isDefaultOutput: id == defaultOutput)
        }
    }

    private static func address(_ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    private static func value<T>(_ object: AudioObjectID, selector: AudioObjectPropertySelector) -> T? {
        var address = address(selector)
        var size = UInt32(MemoryLayout<T>.size)
        let result = UnsafeMutablePointer<T>.allocate(capacity: 1)
        defer { result.deallocate() }
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, result) == noErr else { return nil }
        return result.pointee
    }

    private static func array<T>(_ object: AudioObjectID, selector: AudioObjectPropertySelector) -> [T] {
        var address = address(selector)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(object, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        let count = Int(size) / MemoryLayout<T>.stride
        let buffer = UnsafeMutablePointer<T>.allocate(capacity: count)
        defer { buffer.deallocate() }
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, buffer) == noErr else { return [] }
        return Array(UnsafeBufferPointer(start: buffer, count: Int(size) / MemoryLayout<T>.stride))
    }

    private static func string(_ object: AudioObjectID, selector: AudioObjectPropertySelector) -> String? {
        var address = address(selector)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = withUnsafeMutablePointer(to: &value) { AudioObjectGetPropertyData(object, &address, 0, nil, &size, $0) }
        guard status == noErr, let value else { return nil }
        return value.takeRetainedValue() as String
    }

    /// Sums the channels of every stream in the given direction (kAudioDevicePropertyStreamConfiguration).
    private static func channels(_ object: AudioObjectID, scope: AudioObjectPropertyScope) -> Int {
        var address = address(kAudioDevicePropertyStreamConfiguration, scope: scope)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(object, &address, 0, nil, &size) == noErr, size > 0 else { return 0 }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, raw) == noErr else { return 0 }
        let list = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
        return list.reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    // MARK: Cameras

    private static func readCameras() -> [PlatformFact] {
        let session = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera, .deskViewCamera], mediaType: .video, position: .unspecified)
        return session.devices.map { device in
            let kind: String = switch device.deviceType {
            case .builtInWideAngleCamera: "Built-in"
            case .external: "External (USB or display)"
            case .continuityCamera: "Continuity Camera (iPhone)"
            case .deskViewCamera: "Desk View"
            default: device.deviceType.rawValue
            }
            return PlatformFact(title: device.localizedName, value: "\(kind) · \(device.manufacturer)\(device.isConnected ? "" : " · disconnected")")
        }
    }

    // MARK: Volumes

    private static let volumeKeys: [URLResourceKey] = [
        .volumeNameKey, .volumeLocalizedFormatDescriptionKey, .volumeTypeNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityKey,
        .volumeAvailableCapacityForImportantUsageKey, .volumeIsEncryptedKey, .volumeSupportsCaseSensitiveNamesKey, .volumeIsInternalKey,
        .volumeIsRemovableKey, .volumeIsEjectableKey, .volumeIsReadOnlyKey, .volumeIsRootFileSystemKey, .volumeSupportsFileCloningKey,
        .volumeSupportsCompressionKey, .volumeIsLocalKey,
    ]

    private static func readVolumes() -> [VolumeInfo] {
        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: volumeKeys, options: [.skipHiddenVolumes]) ?? []
        return urls.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: Set(volumeKeys)) else { return nil }
            var facts: [PlatformFact] = []
            let format = values.volumeTypeName.map { $0 == "apfs" ? "APFS" : $0.uppercased() } ?? "Unknown"
            facts.append(PlatformFact(title: "File system", value: values.volumeLocalizedFormatDescription.map { "\(format) · \($0)" } ?? format))
            if let total = values.volumeTotalCapacity {
                let available = values.volumeAvailableCapacityForImportantUsage ?? values.volumeAvailableCapacity.map(Int64.init) ?? 0
                facts.append(PlatformFact(title: "Capacity", value: "\(Int64(available).formatted(.byteCount(style: .file))) free of \(Int64(total).formatted(.byteCount(style: .file)))"))
            }
            facts.append(PlatformFact(title: "Encrypted", value: flag(values.volumeIsEncrypted)))
            facts.append(PlatformFact(title: "Case-sensitive", value: flag(values.volumeSupportsCaseSensitiveNames)))
            facts.append(PlatformFact(title: "Clones (copy-on-write)", value: flag(values.volumeSupportsFileCloning)))
            facts.append(PlatformFact(title: "Compression", value: flag(values.volumeSupportsCompression)))
            let traits = [
                values.volumeIsRootFileSystem == true ? "Startup volume" : nil,
                values.volumeIsInternal == true ? "Internal" : (values.volumeIsInternal == false ? "External" : nil),
                values.volumeIsLocal == false ? "Network" : nil,
                values.volumeIsRemovable == true ? "Removable" : nil,
                values.volumeIsEjectable == true ? "Ejectable" : nil,
                values.volumeIsReadOnly == true ? "Read-only" : nil,
            ].compactMap { $0 }
            if !traits.isEmpty { facts.append(PlatformFact(title: "Traits", value: traits.joined(separator: " · "))) }
            return VolumeInfo(id: url.path, name: values.volumeName ?? url.lastPathComponent, facts: facts)
        }
    }

    private static func multiple(_ value: CGFloat) -> String {
        Double(value).formatted(.number.precision(.fractionLength(1))) + "×"
    }

    private static func flag(_ value: Bool?) -> String {
        value.map { $0 ? "Yes" : "No" } ?? "Not reported"
    }

    // MARK: Displays

    private static func readDisplays() -> [DisplayInfo] {
        NSScreen.screens.map { screen in
            let displayID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
            let points = screen.frame.size, scale = screen.backingScaleFactor
            let headroom = screen.maximumExtendedDynamicRangeColorComponentValue
            let potential = screen.maximumPotentialExtendedDynamicRangeColorComponentValue
            let reference = screen.maximumReferenceExtendedDynamicRangeColorComponentValue
            var facts = [
                PlatformFact(title: "Role", value: [screen == NSScreen.main ? "Main (key window)" : nil, CGDisplayIsBuiltin(displayID) != 0 ? "Built-in" : "External",
                                                     CGDisplayIsInMirrorSet(displayID) != 0 ? "Mirrored" : nil].compactMap { $0 }.joined(separator: " · ")),
                PlatformFact(title: "Resolution", value: "\(Int(points.width * scale)) × \(Int(points.height * scale)) px · \(Int(points.width)) × \(Int(points.height)) pt @ \(scale.formatted())×"),
                PlatformFact(title: "Refresh rate", value: MacHardwareFormatting.refreshRate(minimumInterval: screen.minimumRefreshInterval, maximumInterval: screen.maximumRefreshInterval, maximumFPS: screen.maximumFramesPerSecond)),
                PlatformFact(title: "Color space", value: screen.colorSpace?.localizedName ?? "Not reported"),
                PlatformFact(title: "Wide color (P3)", value: screen.canRepresent(.p3) ? "Yes" : "No"),
                PlatformFact(title: "EDR headroom", value: potential > 1
                    ? "\(multiple(headroom)) now · up to \(multiple(potential))"
                    : "None (SDR only)"),
            ]
            if reference > 0 {
                facts.append(PlatformFact(title: "Reference EDR", value: "\(multiple(reference)) (reference mode)"))
            }
            if screen.safeAreaInsets.top > 0 {
                facts.append(PlatformFact(title: "Camera housing", value: "\(Int(screen.safeAreaInsets.top)) pt top safe area"))
            }
            return DisplayInfo(id: displayID, name: screen.localizedName, facts: facts)
        }
    }
}

extension MacHardwareService: StoppableExperiment {
    var isActive: Bool { isWatching }
    func stop() { stopWatching() }
}
#endif
