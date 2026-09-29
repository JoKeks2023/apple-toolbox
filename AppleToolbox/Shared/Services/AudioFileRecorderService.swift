import Foundation
import Combine
#if canImport(AVFoundation) && (os(iOS) || os(macOS))
import AVFoundation
#endif

/// File formats offered for AVAudioRecorder, from compressed to uncompressed.
enum AudioRecordingFormat: String, CaseIterable, Identifiable {
    case aac, alac, wav, caf

    var id: String { rawValue }

    var label: String {
        switch self {
        case .aac: "AAC · .m4a (lossy)"
        case .alac: "Apple Lossless · .m4a"
        case .wav: "Linear PCM 16-bit · .wav"
        case .caf: "Linear PCM 32-bit float · .caf"
        }
    }

    var fileExtension: String {
        switch self {
        case .aac, .alac: "m4a"
        case .wav: "wav"
        case .caf: "caf"
        }
    }

    /// Core Audio format ID (`AVFormatIDKey`) for the recorder settings.
    var formatID: UInt32 {
        switch self {
        case .aac: 0x6161_6320 // 'aac '
        case .alac: 0x616c_6163 // 'alac'
        case .wav, .caf: 0x6c70_636d // 'lpcm'
        }
    }

    var isLinearPCM: Bool { self == .wav || self == .caf }

    /// Settings dictionary for AVAudioRecorder (keys are the AVFAudio setting key strings).
    func recorderSettings(sampleRate: Double, channels: Int) -> [String: Any] {
        var settings: [String: Any] = ["AVFormatIDKey": formatID, "AVSampleRateKey": sampleRate, "AVNumberOfChannelsKey": channels]
        switch self {
        case .aac:
            settings["AVEncoderAudioQualityKey"] = 0x60 // AVAudioQuality.high
        case .alac:
            settings["AVEncoderBitDepthHintKey"] = 16
        case .wav:
            settings["AVLinearPCMBitDepthKey"] = 16
            settings["AVLinearPCMIsFloatKey"] = false
            settings["AVLinearPCMIsBigEndianKey"] = false
        case .caf:
            settings["AVLinearPCMBitDepthKey"] = 32
            settings["AVLinearPCMIsFloatKey"] = true
            settings["AVLinearPCMIsBigEndianKey"] = false
        }
        return settings
    }
}

/// Describes a Core Audio format ID as its four-character code, e.g. `aac ` or `lpcm`.
func fourCharacterCode(_ value: UInt32) -> String {
    let bytes = [24, 16, 8, 0].map { UInt8((value >> $0) & 0xFF) }
    guard bytes.allSatisfy({ $0 >= 0x20 && $0 < 0x7F }) else { return String(value) }
    return String(decoding: bytes, as: UTF8.self)
}

/// Records the microphone to a file with AVAudioRecorder and plays it back with AVAudioPlayer.
@MainActor
final class AudioFileRecorderService: NSObject, ObservableObject {
    @Published var format = AudioRecordingFormat.aac
    @Published private(set) var isRecording = false
    @Published private(set) var isPlaying = false
    /// True while the session activation for a recording or playback is in flight.
    var isStarting: Bool { pendingStart != nil }
    /// The start waiting for its session activation; stop() clears it so the start gives up after the await.
    private var pendingStart: UUID?
    @Published private(set) var fileURL: URL?
    @Published private(set) var fileDetails: [AudioRouteDetail] = []
    @Published private(set) var output = "Pick a file format and record the microphone to a file, then play it back or share it."
    @Published private(set) var isError = false
    #if canImport(AVFoundation) && (os(iOS) || os(macOS))
    private var recorder: AVAudioRecorder?
    private var player: AVAudioPlayer?
    #endif

    /// Seconds recorded or played so far; read from a TimelineView while active.
    var elapsed: TimeInterval {
        #if canImport(AVFoundation) && (os(iOS) || os(macOS))
        if let recorder, recorder.isRecording { return recorder.currentTime }
        if let player { return player.currentTime }
        #endif
        return 0
    }

    func startRecording() {
        #if canImport(AVFoundation) && (os(iOS) || os(macOS))
        guard !isRecording, !isStarting else { return }
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
            AVCaptureDevice.requestAccess(for: .audio) { @Sendable [weak self] granted in
                Task { @MainActor in
                    PermissionCenter.shared.invalidate()
                    if granted { self?.startRecording() } else { self?.fail("Microphone permission was denied. Allow it in Settings so AVAudioRecorder can record.") }
                }
            }
            return
        }
        guard AVCaptureDevice.default(for: .audio) != nil else { fail("No microphone is available on this device."); return }
        stopPlayback()
        if let fileURL { try? FileManager.default.removeItem(at: fileURL) }
        fileURL = nil
        fileDetails = []
        let url = URL.temporaryDirectory.appending(path: "AppleToolbox-Recording-\(Int(Date.now.timeIntervalSince1970)).\(format.fileExtension)")
        let token = UUID()
        pendingStart = token
        Task { await startRecording(to: url, token: token) }
        #else
        fail("Recording to a file needs a microphone; Apple Toolbox records only on iPhone, iPad and Mac.")
        #endif
    }

    #if canImport(AVFoundation) && (os(iOS) || os(macOS))
    private func startRecording(to url: URL, token: UUID) async {
        var activated = false
        do {
            try await AudioSessionController.activateForRecording()
            // Cancelled during activation: cancelPendingStart() already enqueued the deactivation.
            guard pendingStart == token else { return }
            pendingStart = nil
            activated = true
            let recorder = try AVAudioRecorder(url: url, settings: format.recorderSettings(sampleRate: 44_100, channels: 1))
            recorder.isMeteringEnabled = true
            guard recorder.prepareToRecord(), recorder.record() else {
                AudioSessionController.deactivate()
                fail("AVAudioRecorder refused to start recording \(format.label). The encoder may not support these settings on this device.")
                return
            }
            self.recorder = recorder
            isRecording = true
            isError = false
            output = "Recording \(format.label) at 44.1 kHz mono to \(url.lastPathComponent)…"
        } catch {
            if !activated {
                guard pendingStart == token else { return } // Cancelled meanwhile: nothing to report.
                pendingStart = nil
            }
            AudioSessionController.deactivate()
            fail("AVAudioRecorder could not be created: \(error.localizedDescription)\nDomain: \((error as NSError).domain) · Code: \((error as NSError).code)")
        }
    }
    #endif

    /// Drops a recording or playback start whose activation is still in flight and releases its session.
    private func cancelPendingStart() {
        guard pendingStart != nil else { return }
        pendingStart = nil
        AudioSessionController.deactivate()
    }

    func stopRecording() {
        cancelPendingStart()
        #if canImport(AVFoundation) && (os(iOS) || os(macOS))
        guard let recorder, isRecording else { return }
        let duration = recorder.currentTime
        recorder.stop()
        self.recorder = nil
        isRecording = false
        AudioSessionController.deactivate()
        fileURL = recorder.url
        inspect(recorder.url)
        isError = false
        output = "Saved \(duration.formatted(.number.precision(.fractionLength(1)))) s to \(recorder.url.lastPathComponent)."
        #endif
    }

    func play() {
        #if canImport(AVFoundation) && (os(iOS) || os(macOS))
        guard let fileURL, !isRecording, !isStarting else { return }
        let token = UUID()
        pendingStart = token
        Task { await play(fileURL, token: token) }
        #endif
    }

    #if canImport(AVFoundation) && (os(iOS) || os(macOS))
    private func play(_ fileURL: URL, token: UUID) async {
        var activated = false
        do {
            try await AudioSessionController.activateForPlayback()
            // Cancelled during activation: cancelPendingStart() already enqueued the deactivation.
            guard pendingStart == token else { return }
            pendingStart = nil
            activated = true
            let player = try AVAudioPlayer(contentsOf: fileURL)
            player.delegate = self
            guard player.play() else { fail("AVAudioPlayer could not start playback."); return }
            self.player = player
            isPlaying = true
            isError = false
            output = "Playing \(fileURL.lastPathComponent) with AVAudioPlayer…"
        } catch {
            if !activated {
                guard pendingStart == token else { return } // Cancelled meanwhile: nothing to report.
                pendingStart = nil
            }
            fail("AVAudioPlayer could not open the file: \(error.localizedDescription)")
        }
    }
    #endif

    func stopPlayback() {
        cancelPendingStart()
        #if canImport(AVFoundation) && (os(iOS) || os(macOS))
        player?.stop()
        player = nil
        #endif
        guard isPlaying else { return }
        isPlaying = false
        AudioSessionController.deactivate()
    }

    func stop() {
        stopRecording()
        stopPlayback()
    }

    private func fail(_ message: String) {
        output = message
        isError = true
    }

    #if canImport(AVFoundation) && (os(iOS) || os(macOS))
    private func inspect(_ url: URL) {
        var details: [AudioRouteDetail] = []
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false))[.size] as? Int) ?? 0
        details.append(AudioRouteDetail(label: "File", value: url.lastPathComponent))
        details.append(AudioRouteDetail(label: "Size", value: size.formatted(.byteCount(style: .file))))
        do {
            let file = try AVAudioFile(forReading: url)
            let fileFormat = file.fileFormat
            let formatID = (fileFormat.settings[AVFormatIDKey] as? NSNumber)?.uint32Value ?? 0
            let duration = fileFormat.sampleRate > 0 ? Double(file.length) / fileFormat.sampleRate : 0
            details.append(AudioRouteDetail(label: "Format", value: "\(fourCharacterCode(formatID)) · \(format.label)"))
            details.append(AudioRouteDetail(label: "Sample rate", value: "\(Int(fileFormat.sampleRate)) Hz"))
            details.append(AudioRouteDetail(label: "Channels", value: "\(fileFormat.channelCount)"))
            if let bitDepth = fileFormat.settings[AVLinearPCMBitDepthKey] as? NSNumber, format.isLinearPCM {
                details.append(AudioRouteDetail(label: "Bit depth", value: "\(bitDepth.intValue)-bit"))
            }
            details.append(AudioRouteDetail(label: "Duration", value: duration.formatted(.number.precision(.fractionLength(2))) + " s"))
            details.append(AudioRouteDetail(label: "Frames", value: file.length.formatted()))
            if duration > 0, size > 0 {
                details.append(AudioRouteDetail(label: "Average bit rate", value: "\(Int(Double(size * 8) / duration / 1_000)) kbit/s"))
            }
        } catch {
            details.append(AudioRouteDetail(label: "AVAudioFile", value: error.localizedDescription))
        }
        fileDetails = details
    }
    #endif
}

#if canImport(AVFoundation) && (os(iOS) || os(macOS))
extension AudioFileRecorderService: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.player = nil
            self.isPlaying = false
            AudioSessionController.deactivate()
            self.output = flag ? "Playback finished." : "Playback stopped because the audio could not be decoded."
        }
    }
}
#endif
