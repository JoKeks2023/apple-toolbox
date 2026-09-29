import Foundation
import Combine
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
    @Published private(set) var rmsLevel: Double = 0
    @Published private(set) var peakLevel: Double = 0
    @Published private(set) var levelHistory: [Double] = []
    @Published private(set) var channelCount = 0
    @Published private(set) var sampleRate = 0
    @Published private(set) var spectrum: [SpectrumBand] = []
    @Published private(set) var dominantPeak: SpectrumPeak?
    @Published private(set) var route = AudioRouteInspector.snapshot()
    @Published private(set) var engineDetails: [AudioRouteDetail] = []
    @Published private(set) var events: [AudioEventEntry] = []

    static let fftSize = 4_096
    static let bandCount = 72

    var isRunning: Bool { isTonePlaying || isMicrophoneRunning }

    private let tone = ToneParameters(waveform: .sine, frequency: 440, amplitude: 0.2)
    private let routeMonitor = AudioRouteMonitor()
    #if canImport(AVFoundation) && (os(iOS) || os(macOS))
    private var toneEngine: AVAudioEngine?
    private var toneSource: AVAudioSourceNode?
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
        guard !isTonePlaying else { return }
        do {
            if isMicrophoneRunning { try AudioSessionController.activateForPlayAndRecord() } else { try AudioSessionController.activateForPlayback() }
            let engine = AVAudioEngine()
            try buildToneGraph(in: engine)
            try engine.start()
            toneEngine = engine
            toneObserver = observeConfigurationChanges(of: engine)
            isTonePlaying = true
            status = .available
            startRouteMonitoring()
            refreshRoute()
            output = "Playing \(waveform.title.lowercased()) at \(ToneFrequencyScale.label(frequency)), \(AudioText.decibels(SpectrumMath.decibels(fromAmplitude: volume))): AVAudioSourceNode → EQ → distortion → delay → reverb → main mixer → \(route.outputSummary)."
            log("Tone started", "\(AudioText.sampleRate(engine.outputNode.outputFormat(forBus: 0).sampleRate)) on \(route.outputSummary)")
        } catch {
            tearDownToneGraph()
            if !isMicrophoneRunning { AudioSessionController.deactivate() }
            status = .unavailable
            output = "Audio engine error: \(error.localizedDescription)"
        }
        #else
        status = .platformUnsupported
        output = "The Audio Analyzer runs on iPhone, iPad and Mac."
        #endif
    }

    func stopTone() {
        #if canImport(AVFoundation) && (os(iOS) || os(macOS))
        guard isTonePlaying || toneEngine != nil else { return }
        tearDownToneGraph()
        isTonePlaying = false
        log("Tone stopped")
        output = "Tone stopped."
        sessionEnded()
        #endif
    }

    #if canImport(AVFoundation) && (os(iOS) || os(macOS))
    private func buildToneGraph(in engine: AVAudioEngine) throws {
        let hardware = engine.outputNode.outputFormat(forBus: 0)
        let rate = hardware.sampleRate > 0 ? hardware.sampleRate : 48_000
        guard let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2) else {
            throw AudioAnalyzerError.unsupportedFormat(rate)
        }
        let source = AVAudioSourceNode(format: format, renderBlock: ToneRenderBlock.make(for: ToneOscillator(parameters: tone, sampleRate: rate)))
        toneSource = source
        let chain: [AVAudioNode] = [source, equalizerUnit, distortionUnit, delayUnit, reverbUnit]
        chain.forEach(engine.attach)
        for (from, to) in zip(chain, chain.dropFirst()) { engine.connect(from, to: to, format: format) }
        engine.connect(reverbUnit, to: engine.mainMixerNode, format: format)
        engine.prepare()
    }

    private func tearDownToneGraph() {
        if let toneObserver { NotificationCenter.default.removeObserver(toneObserver) }
        toneObserver = nil
        guard let engine = toneEngine else { return }
        engine.stop()
        let nodes: [AVAudioNode] = [toneSource, equalizerUnit, distortionUnit, delayUnit, reverbUnit].compactMap { $0 }
        for node in nodes where node.engine === engine { engine.detach(node) }
        toneSource = nil
        toneEngine = nil
    }

    /// The engine stops itself when the I/O format or device changes (route change, category change, sample rate).
    private func restartToneAfterConfigurationChange() {
        guard isTonePlaying, let engine = toneEngine else { return }
        engine.stop()
        let nodes: [AVAudioNode] = [toneSource, equalizerUnit, distortionUnit, delayUnit, reverbUnit].compactMap { $0 }
        nodes.forEach(engine.detach)
        do {
            try buildToneGraph(in: engine)
            try engine.start()
            log("Tone engine reconfigured", "Output changed; restarted at \(AudioText.sampleRate(engine.outputNode.outputFormat(forBus: 0).sampleRate)).")
        } catch {
            log("Tone engine restart failed", error.localizedDescription)
            stopTone()
            status = .unavailable
            output = "The output changed and the tone could not restart: \(error.localizedDescription)"
        }
        refreshRoute()
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
        guard !isMicrophoneRunning else { return }
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
        do { try AudioSessionController.activateForPlayAndRecord() }
        catch { output = "Audio session error: \(error.localizedDescription)"; status = .unavailable; return }
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            if !isTonePlaying { AudioSessionController.deactivate() }
            output = "No audio input is available right now. The tone generator still works."
            status = .hardwareUnsupported
            return
        }
        guard let analyzer = SpectrumAnalyzer(size: Self.fftSize) else { output = "vDSP could not create an FFT setup."; status = .unavailable; return }
        channelCount = Int(format.channelCount)
        sampleRate = Int(format.sampleRate)
        let deliver: @Sendable (AudioAnalysisFrame) -> Void = { [weak self] frame in
            Task { @MainActor in self?.apply(frame) }
        }
        input.installTap(onBus: 0, bufferSize: 2_048, format: format,
                         block: MicrophoneAnalysisTap.make(analyzer: analyzer, sampleRate: format.sampleRate, bandCount: Self.bandCount, deliver: deliver))
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            if !isTonePlaying { AudioSessionController.deactivate() }
            output = "Audio engine error: \(error.localizedDescription)"
            status = .unavailable
            return
        }
        microphoneEngine = engine
        microphoneObserver = observeConfigurationChanges(of: engine)
        isMicrophoneRunning = true
        status = .available
        levelHistory = []
        startRouteMonitoring()
        refreshRoute()
        output = "Microphone running: \(channelCount) ch at \(AudioText.sampleRate(format.sampleRate)), \(Self.fftSize)-point Hann-windowed FFT (\(SpectrumMath.binWidth(sampleRate: format.sampleRate, fftSize: Self.fftSize).formatted(.number.precision(.fractionLength(1)))) Hz per bin)."
        log("Microphone started", route.inputs.map(\.name).joined(separator: " + "))
        #else
        status = .platformUnsupported
        output = "Microphone analysis runs on iPhone, iPad and Mac."
        #endif
    }

    func stopMicrophone() {
        #if canImport(AVFoundation) && (os(iOS) || os(macOS))
        guard isMicrophoneRunning || microphoneEngine != nil else { return }
        if let microphoneObserver { NotificationCenter.default.removeObserver(microphoneObserver) }
        microphoneObserver = nil
        microphoneEngine?.inputNode.removeTap(onBus: 0)
        microphoneEngine?.stop()
        microphoneEngine = nil
        isMicrophoneRunning = false
        rmsLevel = 0
        peakLevel = 0
        log("Microphone stopped")
        output = "Microphone stopped. The last spectrum stays visible."
        sessionEnded()
        #endif
    }

    private func apply(_ frame: AudioAnalysisFrame) {
        guard isMicrophoneRunning else { return }
        rmsLevel = Double(frame.rms)
        peakLevel = Double(frame.peak)
        levelHistory = Array((levelHistory + [Double(frame.peak)]).suffix(48))
        if !frame.bands.isEmpty {
            spectrum = frame.bands
            dominantPeak = frame.dominant
        }
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
        do {
            if isMicrophoneRunning { try AudioSessionController.activateForPlayAndRecord() } else if isTonePlaying { try AudioSessionController.activateForPlayback() }
            if isTonePlaying, let toneEngine, !toneEngine.isRunning { try toneEngine.start() }
            if isMicrophoneRunning, let microphoneEngine, !microphoneEngine.isRunning { try microphoneEngine.start() }
            log("Resumed after interruption")
        } catch {
            log("Resume failed", error.localizedDescription)
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
