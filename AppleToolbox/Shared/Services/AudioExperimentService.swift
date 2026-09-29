import Foundation
import Combine
import Synchronization
#if canImport(AVFoundation) && (os(iOS) || os(macOS))
import AVFoundation
#endif

// MARK: - Effect presets

enum ReverbSetting: String, CaseIterable, Identifiable {
    case off = "Off", smallRoom = "Small room", mediumRoom = "Medium room", largeRoom = "Large room", mediumHall = "Medium hall", largeHall = "Large hall"
    case plate = "Plate", mediumChamber = "Medium chamber", largeChamber = "Large chamber", cathedral = "Cathedral"
    var id: String { rawValue }
    var wetDryMix: Float { self == .cathedral ? 60 : 40 }
}

enum DelaySetting: String, CaseIterable, Identifiable {
    case off = "Off", slapback = "Slapback · 90 ms", echo = "Echo · 250 ms", longEcho = "Long echo · 500 ms", dub = "Dub · 375 ms, high feedback"
    var id: String { rawValue }

    /// AVAudioUnitDelay parameters: time (s), feedback (%), low-pass cutoff (Hz), wet/dry mix (%).
    var parameters: (time: Double, feedback: Float, lowPassCutoff: Float, wetDryMix: Float)? {
        switch self {
        case .off: nil
        case .slapback: (0.09, 0, 12_000, 35)
        case .echo: (0.25, 30, 8_000, 35)
        case .longEcho: (0.5, 45, 6_000, 40)
        case .dub: (0.375, 70, 2_500, 45)
        }
    }
}

enum DistortionSetting: String, CaseIterable, Identifiable {
    case off = "Off", radioTower = "Radio tower", cellphone = "Cellphone concert", brokenSpeaker = "Broken speaker", decimated = "Decimated"
    case lofi = "Lo-fi drums", squared = "Distorted squared", cubed = "Distorted cubed", alienChatter = "Alien chatter"
    var id: String { rawValue }
}

nonisolated enum EQBandKind: Sendable { case lowShelf, highShelf, parametric, highPass, lowPass }

/// One band of AVAudioUnitEQ: frequency (Hz), gain (dB, shelves and parametric), bandwidth (octaves, parametric).
nonisolated struct EQBandSpec: Equatable, Sendable {
    let kind: EQBandKind
    let frequency: Float
    var gain: Float = 0
    var bandwidth: Float = 1
}

enum EqualizerSetting: String, CaseIterable, Identifiable {
    case flat = "Flat (bypassed)", bassBoost = "Bass boost · +9 dB below 120 Hz", trebleBoost = "Treble boost · +9 dB above 5 kHz"
    case telephone = "Telephone · 300 Hz–3.4 kHz", notch = "Notch · −30 dB at 1 kHz", smile = "Smile · +6 dB bass and treble"
    var id: String { rawValue }

    static let bandCount = 3

    var bands: [EQBandSpec] {
        switch self {
        case .flat: []
        case .bassBoost: [EQBandSpec(kind: .lowShelf, frequency: 120, gain: 9)]
        case .trebleBoost: [EQBandSpec(kind: .highShelf, frequency: 5_000, gain: 9)]
        case .telephone: [EQBandSpec(kind: .highPass, frequency: 300), EQBandSpec(kind: .lowPass, frequency: 3_400)]
        case .notch: [EQBandSpec(kind: .parametric, frequency: 1_000, gain: -30, bandwidth: 0.2)]
        case .smile: [EQBandSpec(kind: .lowShelf, frequency: 100, gain: 6), EQBandSpec(kind: .parametric, frequency: 1_000, gain: -4, bandwidth: 2), EQBandSpec(kind: .highShelf, frequency: 8_000, gain: 6)]
        }
    }
}

// MARK: - Service

/// Audio Analyzer: an AVAudioEngine tone generator with an effects chain, a second engine that taps the
/// microphone for an FFT spectrum and level meter, and the output route with its timing.
@MainActor
final class AudioExperimentService: ObservableObject {
    @Published var waveform = ToneWaveform.sine { didSet { tone.waveform = waveform } }
    @Published var frequency = 440.0 { didSet { tone.frequency = frequency } }
    /// Linear peak amplitude of the tone, 0…1.
    @Published var volume = 0.2 { didSet { tone.amplitude = volume } }
    @Published var equalizer = EqualizerSetting.flat { didSet { applyEffects() } }
    @Published var distortion = DistortionSetting.off { didSet { applyEffects() } }
    @Published var delay = DelaySetting.off { didSet { applyEffects() } }
    @Published var reverb = ReverbSetting.off { didSet { applyEffects() } }

    @Published private(set) var output = "Play a test tone, start the microphone spectrum, or both. Play a tone and watch its peak appear in the spectrum."
    @Published private(set) var status: ExperimentStatus = .available
    @Published private(set) var isTonePlaying = false
    @Published private(set) var isMicrophoneRunning = false
    /// Per-frame values live in their own object: only the meter and spectrum views observe it.
    let meter = AudioMeterState()
    @Published private(set) var route = AudioRouteInspector.snapshot()
    @Published private(set) var engineDetails: [AudioRouteDetail] = []
    @Published private(set) var events: [AudioEventEntry] = []

    static let fftSize = 4_096
    static let bandCount = 72

    /// Includes starts still in flight, so leaving the experiment stops them and a stop elsewhere keeps the session active.
    var isRunning: Bool { isTonePlaying || isMicrophoneRunning || isToneStarting || isMicrophoneStarting }

    private let tone = ToneParameters(waveform: .sine, frequency: 440, amplitude: 0.2)
    private let routeMonitor = AudioRouteMonitor()
    private var toneGeneration = 0
    private var isToneStarting = false
    private var microphoneGeneration = 0
    private var isMicrophoneStarting = false
    #if canImport(AVFoundation) && (os(iOS) || os(macOS))
    // Engines are created and referenced here, but start/stop, graph changes and taps run on the
    // AudioSessionController queue. A stop bumps the generation so a start still in flight cannot publish.
    private var toneEngine: AVAudioEngine?
    private let equalizerUnit = AVAudioUnitEQ(numberOfBands: EqualizerSetting.bandCount)
    private let distortionUnit = AVAudioUnitDistortion()
    private let delayUnit = AVAudioUnitDelay()
    private let reverbUnit = AVAudioUnitReverb()
    private var microphoneEngine: AVAudioEngine?
    private var toneObserver: NSObjectProtocol?
    private var microphoneObserver: NSObjectProtocol?
    #endif

    init() {
        applyEffects()
    }

    func stop() {
        stopTone()
        stopMicrophone()
    }

    func refreshRoute() {
        route = AudioRouteInspector.snapshot()
        #if canImport(AVFoundation) && (os(iOS) || os(macOS))
        var details: [AudioRouteDetail] = []
        if let toneEngine {
            let format = toneEngine.outputNode.outputFormat(forBus: 0)
            details.append(AudioRouteDetail(label: "Tone engine output", value: "\(AudioText.sampleRate(format.sampleRate)) · \(format.channelCount) ch"))
            details.append(AudioRouteDetail(label: "Output presentation latency", value: AudioText.milliseconds(toneEngine.outputNode.presentationLatency)))
        }
        if let microphoneEngine {
            let format = microphoneEngine.inputNode.outputFormat(forBus: 0)
            details.append(AudioRouteDetail(label: "Microphone engine input", value: "\(AudioText.sampleRate(format.sampleRate)) · \(format.channelCount) ch"))
            details.append(AudioRouteDetail(label: "Input presentation latency", value: AudioText.milliseconds(microphoneEngine.inputNode.presentationLatency)))
        }
        engineDetails = details
        #endif
    }

    // MARK: Tone generator

    func startTone() {
        #if canImport(AVFoundation) && (os(iOS) || os(macOS))
        guard !isTonePlaying, !isToneStarting else { return }
        isToneStarting = true
        toneGeneration += 1
        let engine = AVAudioEngine()
        toneEngine = engine // Set before any await: a stop meanwhile tears down (and detaches the shared units from) this engine.
        let generation = toneGeneration
        Task { await startTone(on: engine, generation: generation) }
        #else
        status = .platformUnsupported
        output = "The Audio Analyzer runs on iPhone, iPad and Mac."
        #endif
    }

    func stopTone() {
        #if canImport(AVFoundation) && (os(iOS) || os(macOS))
        guard isTonePlaying || toneEngine != nil else { return }
        toneGeneration += 1
        isToneStarting = false
        tearDownToneGraph()
        isTonePlaying = false
        log("Tone stopped")
        output = "Tone stopped."
        sessionEnded()
        #endif
    }

    #if canImport(AVFoundation) && (os(iOS) || os(macOS))
    private var effectUnits: [AVAudioNode] { [equalizerUnit, distortionUnit, delayUnit, reverbUnit] }

    private func startTone(on engine: AVAudioEngine, generation: Int) async {
        // After this point the engine and the effect units are only touched on the audio queue.
        let queueEngine = engine
        let units = effectUnits
        let tone = tone
        do {
            // A microphone start in flight also needs input: activating Playback here would switch its category away.
            if isMicrophoneRunning || isMicrophoneStarting { try await AudioSessionController.activateForPlayAndRecord() } else { try await AudioSessionController.activateForPlayback() }
            // Stopped during activation: stopTone() already enqueued the teardown and deactivation.
            guard generation == toneGeneration else { return }
            let rate = try await AudioSessionController.perform {
                try Self.buildToneGraph(in: queueEngine, units: units, tone: tone)
                try queueEngine.start()
                return queueEngine.outputNode.outputFormat(forBus: 0).sampleRate
            }
            // Stopped while starting: the teardown was enqueued after this start, so the engine ends stopped.
            guard generation == toneGeneration else { return }
            isToneStarting = false
            toneObserver = observeConfigurationChanges(of: engine)
            isTonePlaying = true
            status = .available
            startRouteMonitoring()
            refreshRoute()
            output = "Playing \(waveform.title.lowercased()) at \(ToneFrequencyScale.label(frequency)), \(AudioText.decibels(SpectrumMath.decibels(fromAmplitude: volume))): AVAudioSourceNode → EQ → distortion → delay → reverb → main mixer → \(route.outputSummary)."
            log("Tone started", "\(AudioText.sampleRate(rate)) on \(route.outputSummary)")
        } catch {
            guard generation == toneGeneration else { return }
            isToneStarting = false
            tearDownToneGraph()
            if !isRunning { AudioSessionController.deactivate() }
            status = .unavailable
            output = "Audio engine error: \(error.localizedDescription)"
        }
    }

    /// Runs on the audio queue.
    nonisolated private static func buildToneGraph(in engine: AVAudioEngine, units: [AVAudioNode], tone: ToneParameters) throws {
        let hardware = engine.outputNode.outputFormat(forBus: 0)
        let rate = hardware.sampleRate > 0 ? hardware.sampleRate : 48_000
        guard let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2) else {
            throw AudioAnalyzerError.unsupportedFormat(rate)
        }
        let source = AVAudioSourceNode(format: format, renderBlock: ToneRenderBlock.make(for: ToneOscillator(parameters: tone, sampleRate: rate)))
        let chain: [AVAudioNode] = [source] + units
        chain.forEach(engine.attach)
        for (from, to) in zip(chain, chain.dropFirst()) { engine.connect(from, to: to, format: format) }
        if let last = chain.last { engine.connect(last, to: engine.mainMixerNode, format: format) }
        engine.prepare()
    }

    /// Runs on the audio queue. Detaches the tone source and the shared effect units so the next engine can attach them.
    nonisolated private static func detachToneGraph(from engine: AVAudioEngine, units: [AVAudioNode]) {
        engine.stop()
        for node in engine.attachedNodes where node is AVAudioSourceNode || units.contains(where: { $0 === node }) {
            engine.detach(node)
        }
    }

    private func tearDownToneGraph() {
        if let toneObserver { NotificationCenter.default.removeObserver(toneObserver) }
        toneObserver = nil
        guard let engine = toneEngine else { return }
        toneEngine = nil
        let queueEngine = engine // Only touched on the audio queue.
        let units = effectUnits
        AudioSessionController.enqueue { Self.detachToneGraph(from: queueEngine, units: units) }
    }

    /// The engine stops itself when the I/O format or device changes (route change, category change, sample rate).
    private func restartToneAfterConfigurationChange() {
        guard isTonePlaying, let engine = toneEngine else { return }
        let generation = toneGeneration
        let queueEngine = engine // Only touched on the audio queue.
        let units = effectUnits
        let tone = tone
        Task {
            guard generation == toneGeneration else { return }
            do {
                let rate = try await AudioSessionController.perform {
                    Self.detachToneGraph(from: queueEngine, units: units)
                    try Self.buildToneGraph(in: queueEngine, units: units, tone: tone)
                    try queueEngine.start()
                    return queueEngine.outputNode.outputFormat(forBus: 0).sampleRate
                }
                guard generation == toneGeneration else { return }
                log("Tone engine reconfigured", "Output changed; restarted at \(AudioText.sampleRate(rate)).")
            } catch {
                guard generation == toneGeneration else { return }
                log("Tone engine restart failed", error.localizedDescription)
                stopTone()
                status = .unavailable
                output = "The output changed and the tone could not restart: \(error.localizedDescription)"
            }
            refreshRoute()
        }
    }
    #endif

    // MARK: Effects

    private func applyEffects() {
        #if canImport(AVFoundation) && (os(iOS) || os(macOS))
        let specs = equalizer.bands
        equalizerUnit.bypass = specs.isEmpty
        for (index, band) in equalizerUnit.bands.enumerated() {
            guard index < specs.count else { band.bypass = true; continue }
            let spec = specs[index]
            band.filterType = spec.kind.filterType
            band.frequency = spec.frequency
            band.gain = spec.gain
            band.bandwidth = spec.bandwidth
            band.bypass = false
        }
        if let preset = distortion.preset {
            distortionUnit.loadFactoryPreset(preset)
            distortionUnit.wetDryMix = 60
            distortionUnit.bypass = false
        } else {
            distortionUnit.bypass = true
        }
        if let parameters = delay.parameters {
            delayUnit.delayTime = parameters.time
            delayUnit.feedback = parameters.feedback
            delayUnit.lowPassCutoff = parameters.lowPassCutoff
            delayUnit.wetDryMix = parameters.wetDryMix
            delayUnit.bypass = false
        } else {
            delayUnit.bypass = true
        }
        if let preset = reverb.preset {
            reverbUnit.loadFactoryPreset(preset)
            reverbUnit.wetDryMix = reverb.wetDryMix
            reverbUnit.bypass = false
        } else {
            reverbUnit.bypass = true
        }
        #endif
    }

    // MARK: Microphone spectrum

    func startMicrophone() {
        #if canImport(AVFoundation) && (os(iOS) || os(macOS))
        guard !isMicrophoneRunning, !isMicrophoneStarting else { return }
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
            status = .permissionRequired
            AVCaptureDevice.requestAccess(for: .audio) { @Sendable [weak self] granted in
                Task { @MainActor in
                    PermissionCenter.shared.invalidate()
                    if granted { self?.startMicrophone() } else {
                        self?.status = .permissionDenied
                        self?.output = "Microphone permission was denied in Settings. The tone generator and route information still work."
                    }
                }
            }
            return
        }
        guard let analyzer = SpectrumAnalyzer(size: Self.fftSize) else { output = "vDSP could not create an FFT setup."; status = .unavailable; return }
        isMicrophoneStarting = true
        microphoneGeneration += 1
        let engine = AVAudioEngine()
        microphoneEngine = engine // Set before any await so a stop meanwhile stops this engine.
        let generation = microphoneGeneration
        Task { await startMicrophone(on: engine, analyzer: analyzer, generation: generation) }
        #else
        status = .platformUnsupported
        output = "Microphone analysis runs on iPhone, iPad and Mac."
        #endif
    }

    func stopMicrophone() {
        #if canImport(AVFoundation) && (os(iOS) || os(macOS))
        guard isMicrophoneRunning || microphoneEngine != nil else { return }
        microphoneGeneration += 1
        isMicrophoneStarting = false
        if let microphoneObserver { NotificationCenter.default.removeObserver(microphoneObserver) }
        microphoneObserver = nil
        if let engine = microphoneEngine {
            let queueEngine = engine // Only touched on the audio queue.
            AudioSessionController.enqueue {
                queueEngine.inputNode.removeTap(onBus: 0)
                queueEngine.stop()
            }
        }
        microphoneEngine = nil
        isMicrophoneRunning = false
        meter.resetLevels()
        log("Microphone stopped")
        output = "Microphone stopped. The last spectrum stays visible."
        sessionEnded()
        #endif
    }

    #if canImport(AVFoundation) && (os(iOS) || os(macOS))
    private func startMicrophone(on engine: AVAudioEngine, analyzer: SpectrumAnalyzer, generation: Int) async {
        do { try await AudioSessionController.activateForPlayAndRecord() }
        catch {
            guard generation == microphoneGeneration else { return }
            abandonMicrophoneStart()
            output = "Audio session error: \(error.localizedDescription)"
            status = .unavailable
            return
        }
        // Stopped during activation: stopMicrophone() already enqueued the stop and deactivation.
        guard generation == microphoneGeneration else { return }
        let throttle = AnalysisFrameThrottle(framesPerSecond: 15)
        let deliver: @Sendable (AudioAnalysisFrame) -> Void = { [weak self] frame in
            guard throttle.admit() else { return }
            Task { @MainActor in self?.apply(frame, generation: generation) }
        }
        let bandCount = Self.bandCount
        let queueEngine = engine // Only touched on the audio queue from here on.
        let hardware: AudioInputFormat?
        do {
            hardware = try await AudioSessionController.perform { () throws -> AudioInputFormat? in
                let input = queueEngine.inputNode
                let format = input.outputFormat(forBus: 0)
                guard format.sampleRate > 0, format.channelCount > 0 else { return nil }
                input.installTap(onBus: 0, bufferSize: 2_048, format: format,
                                 block: MicrophoneAnalysisTap.make(analyzer: analyzer, sampleRate: format.sampleRate, bandCount: bandCount, deliver: deliver))
                do { try queueEngine.start() } catch { input.removeTap(onBus: 0); throw error }
                return AudioInputFormat(sampleRate: format.sampleRate, channelCount: Int(format.channelCount))
            }
        } catch {
            guard generation == microphoneGeneration else { return }
            abandonMicrophoneStart()
            output = "Audio engine error: \(error.localizedDescription)"
            status = .unavailable
            return
        }
        // Stopped while starting: the stop was enqueued after this start, so the engine ends stopped.
        guard generation == microphoneGeneration else { return }
        guard let hardware else {
            abandonMicrophoneStart()
            output = "No audio input is available right now. The tone generator still works."
            status = .hardwareUnsupported
            return
        }
        isMicrophoneStarting = false
        meter.begin(channelCount: hardware.channelCount, sampleRate: Int(hardware.sampleRate))
        microphoneObserver = observeConfigurationChanges(of: engine)
        isMicrophoneRunning = true
        status = .available
        startRouteMonitoring()
        refreshRoute()
        output = "Microphone running: \(hardware.channelCount) ch at \(AudioText.sampleRate(hardware.sampleRate)), \(Self.fftSize)-point Hann-windowed FFT (\(SpectrumMath.binWidth(sampleRate: hardware.sampleRate, fftSize: Self.fftSize).formatted(.number.precision(.fractionLength(1)))) Hz per bin)."
        log("Microphone started", route.inputs.map(\.name).joined(separator: " + "))
    }

    /// A start that failed before the engine ran: nothing to stop, only the session to release.
    private func abandonMicrophoneStart() {
        isMicrophoneStarting = false
        microphoneEngine = nil
        if !isRunning { AudioSessionController.deactivate() }
    }
    #endif

    private func apply(_ frame: AudioAnalysisFrame, generation: Int) {
        guard isMicrophoneRunning, generation == microphoneGeneration else { return }
        meter.apply(frame)
    }

    #if canImport(AVFoundation) && (os(iOS) || os(macOS))
    private func restartMicrophoneAfterConfigurationChange() {
        guard isMicrophoneRunning else { return }
        stopMicrophone()
        log("Microphone engine reconfigured", "The input changed; restarting with the new format.")
        startMicrophone()
    }

    private func observeConfigurationChanges(of engine: AVAudioEngine) -> NSObjectProtocol {
        // Posted on an internal AVAudioEngine thread.
        NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil) { @Sendable [weak self] _ in
            Task { @MainActor in self?.configurationChanged(engine) }
        }
    }

    private func configurationChanged(_ engine: AVAudioEngine) {
        if engine === toneEngine { restartToneAfterConfigurationChange() }
        if engine === microphoneEngine { restartMicrophoneAfterConfigurationChange() }
    }
    #endif

    // MARK: Route monitoring

    private func startRouteMonitoring() {
        routeMonitor.start { [weak self] event in self?.handle(event) }
    }

    private func sessionEnded() {
        guard !isRunning else { refreshRoute(); return }
        AudioSessionController.deactivate()
        routeMonitor.stop()
        refreshRoute()
    }

    private func handle(_ event: AudioRouteEvent) {
        events.insert(event.entry, at: 0)
        trimEvents()
        switch event.kind {
        case .interruptionEnded(let shouldResume) where shouldResume:
            resumeAfterInterruption()
        case .mediaServicesReset:
            stop()
            output = "Media services were reset. Start the tone or microphone again."
        default:
            break
        }
        refreshRoute()
    }

    private func resumeAfterInterruption() {
        #if canImport(AVFoundation) && (os(iOS) || os(macOS))
        Task {
            do {
                if isMicrophoneRunning { try await AudioSessionController.activateForPlayAndRecord() } else if isTonePlaying { try await AudioSessionController.activateForPlayback() } else { return }
                // Read after the activation: an engine stopped meanwhile is nil here, and a later stop is enqueued after this start.
                let tone = isTonePlaying ? toneEngine : nil // Only touched on the audio queue.
                let microphone = isMicrophoneRunning ? microphoneEngine : nil
                guard tone != nil || microphone != nil else { return }
                try await AudioSessionController.perform {
                    if let tone, !tone.isRunning { try tone.start() }
                    if let microphone, !microphone.isRunning { try microphone.start() }
                }
                log("Resumed after interruption")
            } catch {
                log("Resume failed", error.localizedDescription)
            }
        }
        #endif
    }

    private func log(_ title: String, _ detail: String = "") {
        events.insert(AudioEventEntry(title: title, detail: detail), at: 0)
        trimEvents()
    }

    private func trimEvents() {
        if events.count > 40 { events.removeLast(events.count - 40) }
    }
}

nonisolated enum AudioAnalyzerError: LocalizedError {
    case unsupportedFormat(Double)

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat(let rate): "No standard float format for \(rate) Hz."
        }
    }
}

#if canImport(AVFoundation) && (os(iOS) || os(macOS))
private extension EQBandKind {
    var filterType: AVAudioUnitEQFilterType {
        switch self {
        case .lowShelf: .lowShelf
        case .highShelf: .highShelf
        case .parametric: .parametric
        case .highPass: .highPass
        case .lowPass: .lowPass
        }
    }
}

private extension DistortionSetting {
    var preset: AVAudioUnitDistortionPreset? {
        switch self {
        case .off: nil
        case .radioTower: .speechRadioTower
        case .cellphone: .multiCellphoneConcert
        case .brokenSpeaker: .multiBrokenSpeaker
        case .decimated: .multiDecimated2
        case .lofi: .drumsLoFi
        case .squared: .multiDistortedSquared
        case .cubed: .multiDistortedCubed
        case .alienChatter: .speechAlienChatter
        }
    }
}

private extension ReverbSetting {
    var preset: AVAudioUnitReverbPreset? {
        switch self {
        case .off: nil
        case .smallRoom: .smallRoom
        case .mediumRoom: .mediumRoom
        case .largeRoom: .largeRoom
        case .mediumHall: .mediumHall
        case .largeHall: .largeHall
        case .plate: .plate
        case .mediumChamber: .mediumChamber
        case .largeChamber: .largeChamber
        case .cathedral: .cathedral
        }
    }
}
#endif

/// Live meter and spectrum values. Kept out of `AudioExperimentService` so a frame only redraws the views that observe it,
/// not the controls, pickers and event log.
@MainActor
final class AudioMeterState: ObservableObject {
    static let historyCapacity = 48

    @Published private(set) var rmsLevel: Double = 0
    @Published private(set) var peakLevel: Double = 0
    /// Most recent peaks, oldest first, never longer than `historyCapacity`.
    @Published private(set) var levelHistory: [Double] = []
    @Published private(set) var channelCount = 0
    @Published private(set) var sampleRate = 0
    @Published private(set) var spectrum: [SpectrumBand] = []
    @Published private(set) var dominantPeak: SpectrumPeak?

    fileprivate func begin(channelCount: Int, sampleRate: Int) {
        self.channelCount = channelCount
        self.sampleRate = sampleRate
        levelHistory.removeAll(keepingCapacity: true)
    }

    fileprivate func resetLevels() {
        rmsLevel = 0
        peakLevel = 0
    }

    fileprivate func apply(_ frame: AudioAnalysisFrame) {
        rmsLevel = Double(frame.rms)
        peakLevel = Double(frame.peak)
        levelHistory.append(Double(frame.peak))
        if levelHistory.count > Self.historyCapacity { levelHistory.removeFirst(levelHistory.count - Self.historyCapacity) }
        if !frame.bands.isEmpty {
            spectrum = frame.bands
            dominantPeak = frame.dominant
        }
    }
}

/// Lets at most one analysis frame per interval through from the tap thread, so the UI updates at a steady rate
/// instead of once per buffer.
nonisolated final class AnalysisFrameThrottle: Sendable {
    private let interval: Duration
    private let lastDelivery = Mutex<ContinuousClock.Instant?>(nil)

    init(framesPerSecond: Int) {
        interval = .seconds(1) / framesPerSecond
    }

    func admit() -> Bool {
        let now = ContinuousClock.now
        return lastDelivery.withLock { last in
            if let last, now - last < interval { return false }
            last = now
            return true
        }
    }
}

nonisolated struct AudioInputFormat: Sendable {
    let sampleRate: Double
    let channelCount: Int
}
