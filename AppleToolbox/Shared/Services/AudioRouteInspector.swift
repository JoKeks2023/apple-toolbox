import Foundation
#if os(iOS) || os(tvOS)
import AVFAudio
#elseif os(macOS)
import CoreAudio
#endif

nonisolated struct AudioPortInfo: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let type: String
    let channels: Int?
}

nonisolated struct AudioRouteDetail: Identifiable, Equatable, Sendable {
    let label: String
    let value: String
    var id: String { label }
}

/// Output/input route and I/O timing as reported by AVAudioSession (iOS, tvOS) or the Core Audio HAL (macOS).
nonisolated struct AudioRouteSnapshot: Equatable, Sendable {
    var source = "Not available on this platform"
    var outputs: [AudioPortInfo] = []
    var inputs: [AudioPortInfo] = []
    var sampleRate: Double?
    var ioBufferDuration: TimeInterval?
    var outputLatency: TimeInterval?
    var inputLatency: TimeInterval?
    var outputChannels: Int?
    var inputChannels: Int?
    var details: [AudioRouteDetail] = []

    var outputSummary: String { outputs.isEmpty ? "No output route" : outputs.map(\.name).joined(separator: " + ") }
}

/// One line of an audio or media event log.
nonisolated struct AudioEventEntry: Identifiable, Sendable {
    let id = UUID()
    let date: Date
    let title: String
    let detail: String

    init(title: String, detail: String = "", date: Date = Date()) {
        self.title = title
        self.detail = detail
        self.date = date
    }
}

nonisolated enum AudioRouteEventKind: Equatable, Sendable {
    case routeChange, interruptionBegan, interruptionEnded(shouldResume: Bool), mediaServicesReset, defaultDeviceChange
}

nonisolated struct AudioRouteEvent: Sendable {
    let kind: AudioRouteEventKind
    let entry: AudioEventEntry
}

nonisolated enum AudioText {
    static func milliseconds(_ seconds: TimeInterval?) -> String {
        guard let seconds, seconds.isFinite else { return "—" }
        return (seconds * 1_000).formatted(.number.precision(.fractionLength(2))) + " ms"
    }

    static func sampleRate(_ hertz: Double?) -> String {
        guard let hertz, hertz > 0 else { return "—" }
        return hertz.formatted(.number.precision(.fractionLength(0))) + " Hz"
    }

    static func channels(_ count: Int?) -> String {
        guard let count else { return "—" }
        return "\(count)"
    }

    static func decibels(_ value: Double) -> String {
        value <= Double(SpectrumMath.floorDecibels) ? "−∞ dBFS" : value.formatted(.number.precision(.fractionLength(1))) + " dBFS"
    }
}

nonisolated enum AudioRouteInspector {
    static func snapshot() -> AudioRouteSnapshot {
        #if os(iOS) || os(tvOS)
        let session = AVAudioSession.sharedInstance()
        var snapshot = AudioRouteSnapshot(source: "AVAudioSession")
        snapshot.outputs = session.currentRoute.outputs.map(port)
        snapshot.inputs = session.currentRoute.inputs.map(port)
        snapshot.sampleRate = session.sampleRate
        snapshot.ioBufferDuration = session.ioBufferDuration
        snapshot.outputLatency = session.outputLatency
        snapshot.inputLatency = session.inputLatency
        snapshot.outputChannels = session.outputNumberOfChannels
        snapshot.inputChannels = session.inputNumberOfChannels
        snapshot.details = [
            AudioRouteDetail(label: "Category", value: session.category.rawValue.replacingOccurrences(of: "AVAudioSessionCategory", with: "")),
            AudioRouteDetail(label: "Mode", value: session.mode.rawValue.replacingOccurrences(of: "AVAudioSessionMode", with: "")),
            AudioRouteDetail(label: "Preferred sample rate", value: AudioText.sampleRate(session.preferredSampleRate)),
            AudioRouteDetail(label: "Preferred IO buffer", value: AudioText.milliseconds(session.preferredIOBufferDuration)),
            AudioRouteDetail(label: "Max output channels", value: "\(session.maximumOutputNumberOfChannels)"),
            AudioRouteDetail(label: "Output volume", value: session.outputVolume.formatted(.percent.precision(.fractionLength(0)))),
            AudioRouteDetail(label: "Input available", value: session.isInputAvailable ? "Yes" : "No"),
            AudioRouteDetail(label: "Other audio playing", value: session.isOtherAudioPlaying ? "Yes" : "No"),
            AudioRouteDetail(label: "Multichannel content", value: session.supportsMultichannelContent ? "Supported" : "Not supported"),
        ]
        return snapshot
        #elseif os(macOS)
        return CoreAudioHAL.snapshot()
        #else
        return AudioRouteSnapshot()
        #endif
    }

    #if os(iOS) || os(tvOS)
    private static func port(_ description: AVAudioSessionPortDescription) -> AudioPortInfo {
        AudioPortInfo(id: description.uid, name: description.portName, type: description.portType.rawValue, channels: description.channels?.count)
    }

    static func describe(_ reason: AVAudioSession.RouteChangeReason) -> String {
        switch reason {
        case .unknown: "Unknown reason"
        case .newDeviceAvailable: "A new device became available (e.g. headphones connected)"
        case .oldDeviceUnavailable: "The previous device became unavailable (e.g. headphones disconnected)"
        case .categoryChange: "The audio session category changed"
        case .override: "The output route was overridden"
        case .wakeFromSleep: "The device woke from sleep"
        case .noSuitableRouteForCategory: "No route is suitable for the current category"
        case .routeConfigurationChange: "The route configuration changed (port, data source or channels)"
        @unknown default: "Unknown reason (\(reason.rawValue))"
        }
    }

    /// Runs on the thread that posted the notification; only reads the Sendable user info.
    fileprivate static func routeChangeEvent(from notification: Notification) -> AudioRouteEvent {
        let reasonValue = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
        let reason = reasonValue.flatMap(AVAudioSession.RouteChangeReason.init(rawValue:))
        let previous = (notification.userInfo?[AVAudioSessionRouteChangePreviousRouteKey] as? AVAudioSessionRouteDescription)?
            .outputs.map(\.portName).joined(separator: " + ")
        let current = AVAudioSession.sharedInstance().currentRoute.outputs.map(\.portName).joined(separator: " + ")
        var detail = reason.map(describe) ?? "No reason given"
        if let previous, !previous.isEmpty { detail += "\nPrevious output: \(previous)" }
        detail += "\nCurrent output: \(current.isEmpty ? "none" : current)"
        return AudioRouteEvent(kind: .routeChange, entry: AudioEventEntry(title: "Route change", detail: detail))
    }

    fileprivate static func interruptionEvent(from notification: Notification) -> AudioRouteEvent {
        let typeValue = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
        switch typeValue.flatMap(AVAudioSession.InterruptionType.init(rawValue:)) {
        case .began?:
            return AudioRouteEvent(kind: .interruptionBegan, entry: AudioEventEntry(title: "Interruption began", detail: "Another app or the system took the audio session (e.g. a call or alarm). Audio engines stop."))
        case .ended?:
            let options = AVAudioSession.InterruptionOptions(rawValue: notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0)
            let resume = options.contains(.shouldResume)
            return AudioRouteEvent(kind: .interruptionEnded(shouldResume: resume), entry: AudioEventEntry(title: "Interruption ended", detail: resume ? "The system suggests resuming playback." : "The system does not suggest resuming playback."))
        default:
            return AudioRouteEvent(kind: .interruptionBegan, entry: AudioEventEntry(title: "Interruption", detail: "Unknown interruption type"))
        }
    }
    #endif
}

/// Observes route changes while an audio experiment runs: AVAudioSession notifications on iOS and tvOS,
/// default-device listeners of the Core Audio HAL on macOS.
@MainActor
final class AudioRouteMonitor {
    private(set) var isRunning = false
    private var observers: [NSObjectProtocol] = []
    #if os(macOS)
    private var listeners: [(AudioObjectPropertySelector, AudioObjectPropertyListenerBlock)] = []
    #endif

    func start(onEvent: @escaping @MainActor @Sendable (AudioRouteEvent) -> Void) {
        guard !isRunning else { return }
        isRunning = true
        #if os(iOS) || os(tvOS)
        let center = NotificationCenter.default
        // AVAudioSession posts these on a secondary thread.
        observers.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: nil) { @Sendable notification in
            let event = AudioRouteInspector.routeChangeEvent(from: notification)
            Task { @MainActor in onEvent(event) }
        })
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: nil) { @Sendable notification in
            let event = AudioRouteInspector.interruptionEvent(from: notification)
            Task { @MainActor in onEvent(event) }
        })
        observers.append(center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: nil) { @Sendable _ in
            let event = AudioRouteEvent(kind: .mediaServicesReset, entry: AudioEventEntry(title: "Media services were reset", detail: "The audio server restarted; audio objects must be rebuilt."))
            Task { @MainActor in onEvent(event) }
        })
        #elseif os(macOS)
        let selectors = [(kAudioHardwarePropertyDefaultOutputDevice, false), (kAudioHardwarePropertyDefaultInputDevice, true)]
        for (selector, isInput) in selectors {
            let block: AudioObjectPropertyListenerBlock = { @Sendable _, _ in
                Task { @MainActor in
                    let name = CoreAudioHAL.defaultDevice(input: isInput).flatMap(CoreAudioHAL.name) ?? "none"
                    onEvent(AudioRouteEvent(kind: .defaultDeviceChange, entry: AudioEventEntry(title: isInput ? "Default input changed" : "Default output changed", detail: "Now: \(name)")))
                }
            }
            var address = CoreAudioHAL.address(selector)
            if AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, DispatchQueue.main, block) == noErr {
                listeners.append((selector, block))
            }
        }
        #endif
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        #if os(macOS)
        for (selector, block) in listeners {
            var address = CoreAudioHAL.address(selector)
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, DispatchQueue.main, block)
        }
        listeners.removeAll()
        #endif
    }
}

#if os(macOS)
/// Reads the default devices from the Core Audio HAL, the macOS counterpart of AVAudioSession's route and timing.
nonisolated enum CoreAudioHAL {
    static func address(_ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    static func defaultDevice(input: Bool) -> AudioDeviceID? {
        let selector = input ? kAudioHardwarePropertyDefaultInputDevice : kAudioHardwarePropertyDefaultOutputDevice
        guard let device = value(AudioObjectID(kAudioObjectSystemObject), selector, initial: AudioDeviceID(kAudioObjectUnknown)),
              device != kAudioObjectUnknown else { return nil }
        return device
    }

    static func name(_ device: AudioDeviceID) -> String? {
        guard let name = value(device, kAudioObjectPropertyName, initial: Unmanaged<CFString>?.none), let name else { return nil }
        return name.takeRetainedValue() as String
    }

    static func snapshot() -> AudioRouteSnapshot {
        var snapshot = AudioRouteSnapshot(source: "Core Audio HAL (default devices)")
        var details: [AudioRouteDetail] = []
        if let output = defaultDevice(input: false) {
            let io = timing(output, scope: kAudioObjectPropertyScopeOutput)
            snapshot.outputs = [port(output, scope: kAudioObjectPropertyScopeOutput)]
            snapshot.sampleRate = io.sampleRate
            snapshot.ioBufferDuration = io.bufferDuration
            snapshot.outputLatency = io.latency
            snapshot.outputChannels = channelCount(output, scope: kAudioObjectPropertyScopeOutput)
            details.append(AudioRouteDetail(label: "Output transport", value: transport(output)))
            details.append(AudioRouteDetail(label: "Output buffer", value: io.bufferFrames.map { "\($0) frames" } ?? "—"))
            details.append(AudioRouteDetail(label: "Output latency (frames)", value: io.breakdown))
        }
        if let input = defaultDevice(input: true) {
            let io = timing(input, scope: kAudioObjectPropertyScopeInput)
            snapshot.inputs = [port(input, scope: kAudioObjectPropertyScopeInput)]
            snapshot.inputLatency = io.latency
            snapshot.inputChannels = channelCount(input, scope: kAudioObjectPropertyScopeInput)
            details.append(AudioRouteDetail(label: "Input transport", value: transport(input)))
            details.append(AudioRouteDetail(label: "Input sample rate", value: AudioText.sampleRate(io.sampleRate)))
            details.append(AudioRouteDetail(label: "Input latency (frames)", value: io.breakdown))
        }
        snapshot.details = details
        return snapshot
    }

    private struct Timing {
        var sampleRate: Double?
        var bufferFrames: UInt32?
        var latencyFrames: UInt32?
        var safetyFrames: UInt32?
        var streamFrames: UInt32?

        var bufferDuration: TimeInterval? {
            guard let sampleRate, sampleRate > 0, let bufferFrames else { return nil }
            return Double(bufferFrames) / sampleRate
        }

        /// Device latency + safety offset + stream latency, as the HAL recommends for presentation timing.
        var latency: TimeInterval? {
            guard let sampleRate, sampleRate > 0, latencyFrames != nil || safetyFrames != nil || streamFrames != nil else { return nil }
            return Double((latencyFrames ?? 0) + (safetyFrames ?? 0) + (streamFrames ?? 0)) / sampleRate
        }

        var breakdown: String {
            "device \(latencyFrames.map(String.init) ?? "—") + safety \(safetyFrames.map(String.init) ?? "—") + stream \(streamFrames.map(String.init) ?? "—")"
        }
    }

    private static func timing(_ device: AudioDeviceID, scope: AudioObjectPropertyScope) -> Timing {
        Timing(sampleRate: value(device, kAudioDevicePropertyNominalSampleRate, initial: Float64(0)),
               bufferFrames: value(device, kAudioDevicePropertyBufferFrameSize, scope: scope, initial: UInt32(0)),
               latencyFrames: value(device, kAudioDevicePropertyLatency, scope: scope, initial: UInt32(0)),
               safetyFrames: value(device, kAudioDevicePropertySafetyOffset, scope: scope, initial: UInt32(0)),
               streamFrames: firstStream(device, scope: scope).flatMap { value($0, kAudioStreamPropertyLatency, initial: UInt32(0)) })
    }

    private static func port(_ device: AudioDeviceID, scope: AudioObjectPropertyScope) -> AudioPortInfo {
        AudioPortInfo(id: "\(device)", name: name(device) ?? "Device \(device)", type: transport(device), channels: channelCount(device, scope: scope))
    }

    private static func transport(_ device: AudioDeviceID) -> String {
        guard let type = value(device, kAudioDevicePropertyTransportType, initial: UInt32(0)) else { return "Unknown" }
        return switch type {
        case kAudioDeviceTransportTypeBuiltIn: "Built-in"
        case kAudioDeviceTransportTypeUSB: "USB"
        case kAudioDeviceTransportTypeBluetooth: "Bluetooth"
        case kAudioDeviceTransportTypeBluetoothLE: "Bluetooth LE"
        case kAudioDeviceTransportTypeAirPlay: "AirPlay"
        case kAudioDeviceTransportTypeHDMI: "HDMI"
        case kAudioDeviceTransportTypeDisplayPort: "DisplayPort"
        case kAudioDeviceTransportTypeThunderbolt: "Thunderbolt"
        case kAudioDeviceTransportTypeVirtual: "Virtual"
        case kAudioDeviceTransportTypeAggregate: "Aggregate"
        case kAudioDeviceTransportTypePCI: "PCI"
        case kAudioDeviceTransportTypeFireWire: "FireWire"
        case kAudioDeviceTransportTypeAVB: "AVB"
        case kAudioDeviceTransportTypeContinuityCaptureWired, kAudioDeviceTransportTypeContinuityCaptureWireless: "Continuity"
        default: "Other"
        }
    }

    private static func channelCount(_ device: AudioDeviceID, scope: AudioObjectPropertyScope) -> Int? {
        var address = address(kAudioDevicePropertyStreamConfiguration, scope: scope)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr, size > 0 else { return nil }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, raw) == noErr else { return nil }
        let list = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
        return list.reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    private static func firstStream(_ device: AudioDeviceID, scope: AudioObjectPropertyScope) -> AudioStreamID? {
        var address = address(kAudioDevicePropertyStreams, scope: scope)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr, size >= UInt32(MemoryLayout<AudioStreamID>.size) else { return nil }
        var streams = [AudioStreamID](repeating: 0, count: Int(size) / MemoryLayout<AudioStreamID>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &streams) == noErr else { return nil }
        return streams.first
    }

    private static func value<T>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal, initial: T) -> T? {
        var address = address(selector, scope: scope)
        guard AudioObjectHasProperty(object, &address) else { return nil }
        var result = initial
        var size = UInt32(MemoryLayout<T>.size)
        let status = withUnsafeMutablePointer(to: &result) { AudioObjectGetPropertyData(object, &address, 0, nil, &size, $0) }
        return status == noErr ? result : nil
    }
}
#endif
