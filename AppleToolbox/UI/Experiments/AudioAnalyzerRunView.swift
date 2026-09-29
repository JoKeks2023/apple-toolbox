import SwiftUI

struct AudioAnalyzerRunView: View {
    @StateObject private var audio = AudioExperimentService()

    var body: some View {
        #if os(iOS) || os(macOS)
        HStack {
            Button(audio.isTonePlaying ? "Stop Tone" : "Play Tone", systemImage: audio.isTonePlaying ? "stop.circle" : "waveform") {
                audio.isTonePlaying ? audio.stopTone() : audio.startTone()
            }
            .buttonStyle(.borderedProminent)
            .experimentSession(audio)
            Button(audio.isMicrophoneRunning ? "Stop Microphone" : "Start Microphone", systemImage: audio.isMicrophoneRunning ? "mic.slash" : "mic") {
                audio.isMicrophoneRunning ? audio.stopMicrophone() : audio.startMicrophone()
            }
            .buttonStyle(.bordered)
        }
        ToneControls(audio: audio)
        OutputView(text: audio.output, isError: [.unavailable, .permissionDenied, .hardwareUnsupported, .platformUnsupported].contains(audio.status))
        EffectsChainSection(audio: audio)
        SpectrumSection(audio: audio)
        AudioMeterView(audio: audio)
        AudioFileRecorderSection()
        AudioRouteSection(route: audio.route, extraDetails: audio.engineDetails, refresh: audio.refreshRoute)
        Section("Route and engine events") {
            AudioEventLogView(events: audio.events, emptyText: "Route changes, interruptions and engine reconfigurations appear here while the tone or microphone runs. Try connecting headphones.")
        }
        #else
        OutputView(text: "The Audio Analyzer runs on iPhone, iPad and Mac: Apple TV apps have no microphone input for the spectrum.", isError: true)
        #endif
    }
}

#if os(iOS) || os(macOS)
/// AVAudioRecorder to a file, AVAudioPlayer playback, file inspection and sharing.
private struct AudioFileRecorderSection: View {
    @StateObject private var recorder = AudioFileRecorderService()

    var body: some View {
        Section("Record to file · AVAudioRecorder") {
            Picker("File format", selection: $recorder.format) {
                ForEach(AudioRecordingFormat.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.menu)
            .disabled(recorder.isRecording)
            HStack {
                Button(recorder.isRecording ? "Stop Recording" : "Record", systemImage: recorder.isRecording ? "stop.circle" : "record.circle") {
                    recorder.isRecording ? recorder.stopRecording() : recorder.startRecording()
                }
                .buttonStyle(.borderedProminent)
                .experimentSession(recorder)
                Button(recorder.isPlaying ? "Stop" : "Play", systemImage: recorder.isPlaying ? "stop.fill" : "play.fill") {
                    recorder.isPlaying ? recorder.stopPlayback() : recorder.play()
                }
                .buttonStyle(.bordered)
                .disabled(recorder.fileURL == nil || recorder.isRecording)
                if let url = recorder.fileURL {
                    ShareLink(item: url) { Label("Share", systemImage: "square.and.arrow.up") }
                        .disabled(recorder.isRecording)
                }
            }
            if recorder.isRecording || recorder.isPlaying {
                TimelineView(.periodic(from: .now, by: 0.25)) { _ in
                    LabeledContent(recorder.isRecording ? "Recorded" : "Position", value: recorder.elapsed.formatted(.number.precision(.fractionLength(1))) + " s")
                }
            }
            ForEach(recorder.fileDetails) { LabeledContent($0.label, value: $0.value) }
            OutputView(text: recorder.output, isError: recorder.isError)
        }
    }
}

private struct ToneControls: View {
    @ObservedObject var audio: AudioExperimentService
    private let presets: [Double] = [50, 100, 440, 1_000, 5_000, 10_000]

    var body: some View {
        Picker("Waveform", selection: $audio.waveform) {
            ForEach(ToneWaveform.allCases) { Text($0.title).tag($0) }
        }
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Frequency")
                Spacer()
                Menu("Presets") {
                    ForEach(presets, id: \.self) { value in
                        Button(ToneFrequencyScale.label(value)) { audio.frequency = value }
                    }
                }
                .fixedSize()
                Text(ToneFrequencyScale.label(audio.frequency))
                    .font(.body.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(value: frequencyPosition, in: 0...1) {
                Text("Frequency")
            } minimumValueLabel: {
                Text("20 Hz").font(.caption2)
            } maximumValueLabel: {
                Text("20 kHz").font(.caption2)
            }
            .disabled(audio.waveform == .whiteNoise)
        }
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Volume")
                Spacer()
                Text(AudioText.decibels(SpectrumMath.decibels(fromAmplitude: audio.volume)))
                    .font(.body.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(value: $audio.volume, in: 0...1) { Text("Volume") }
            Text("Peak amplitude of the generated signal before the effects. Start quietly on headphones.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var frequencyPosition: Binding<Double> {
        Binding(get: { ToneFrequencyScale.position(forFrequency: audio.frequency) },
                set: { audio.frequency = (ToneFrequencyScale.frequency(forPosition: $0) * 10).rounded() / 10 })
    }
}

private struct EffectsChainSection: View {
    @ObservedObject var audio: AudioExperimentService

    var body: some View {
        Section("Effects chain · AVAudioUnit") {
            Picker("EQ", selection: $audio.equalizer) {
                ForEach(EqualizerSetting.allCases) { Text($0.rawValue).tag($0) }
            }
            Picker("Distortion", selection: $audio.distortion) {
                ForEach(DistortionSetting.allCases) { Text($0.rawValue).tag($0) }
            }
            Picker("Delay", selection: $audio.delay) {
                ForEach(DelaySetting.allCases) { Text($0.rawValue).tag($0) }
            }
            Picker("Reverb", selection: $audio.reverb) {
                ForEach(ReverbSetting.allCases) { Text($0.rawValue).tag($0) }
            }
            Text("Source → AVAudioUnitEQ → AVAudioUnitDistortion → AVAudioUnitDelay → AVAudioUnitReverb → main mixer. “Off” bypasses a unit; changes apply live.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct SpectrumSection: View {
    @ObservedObject var audio: AudioExperimentService

    var body: some View {
        Section("Microphone spectrum · vDSP FFT \(AudioExperimentService.fftSize)") {
            SpectrumView(bands: audio.spectrum, peak: audio.dominantPeak, nyquist: audio.sampleRate > 0 ? Double(audio.sampleRate) / 2 : 24_000)
                .frame(height: 170)
            if let peak = audio.dominantPeak {
                LabeledContent("Dominant frequency") {
                    Text("\(ToneFrequencyScale.label(peak.frequency)) · \(AudioText.decibels(Double(peak.level)))")
                        .font(.body.monospacedDigit())
                }
            } else {
                LabeledContent("Dominant frequency", value: "—")
            }
            Text("Hann window, log frequency axis from 20 Hz, 0 dBFS at the top, grid every 20 dB. Play a tone and compare its frequency with the dominant peak.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// Log-frequency bar spectrum in dBFS, drawn with Canvas so it can redraw at the tap rate.
private struct SpectrumView: View {
    let bands: [SpectrumBand]
    let peak: SpectrumPeak?
    let nyquist: Double
    private let minimumFrequency = 20.0
    private let range: Float = 100

    var body: some View {
        Canvas { context, size in
            let span = log(nyquist / minimumFrequency)
            func x(_ frequency: Double) -> CGFloat { CGFloat(log(max(frequency, minimumFrequency) / minimumFrequency) / span) * size.width }
            func y(_ level: Float) -> CGFloat { CGFloat(min(max(-level / range, 0), 1)) * size.height }

            for level in stride(from: Float(-20), through: -80, by: -20) {
                var line = Path()
                line.move(to: CGPoint(x: 0, y: y(level)))
                line.addLine(to: CGPoint(x: size.width, y: y(level)))
                context.stroke(line, with: .color(.secondary.opacity(0.25)), lineWidth: 0.5)
                context.draw(Text("\(Int(level))").font(.caption2).foregroundStyle(.secondary), at: CGPoint(x: 2, y: y(level) - 1), anchor: .bottomLeading)
            }
            for frequency in [100.0, 1_000, 10_000] where frequency < nyquist {
                var line = Path()
                line.move(to: CGPoint(x: x(frequency), y: 0))
                line.addLine(to: CGPoint(x: x(frequency), y: size.height))
                context.stroke(line, with: .color(.secondary.opacity(0.25)), lineWidth: 0.5)
                context.draw(Text(frequency >= 1_000 ? "\(Int(frequency / 1_000))k" : "\(Int(frequency))").font(.caption2).foregroundStyle(.secondary),
                             at: CGPoint(x: x(frequency) + 2, y: size.height - 1), anchor: .bottomLeading)
            }
            for band in bands {
                let left = x(band.lowerFrequency), right = x(band.upperFrequency), top = y(band.level)
                let rect = CGRect(x: left, y: top, width: max(right - left - 1, 1), height: size.height - top)
                context.fill(Path(rect), with: .color(band.level > -12 ? .red : band.level > -40 ? .orange : .accentColor))
            }
            if let peak {
                var marker = Path()
                marker.move(to: CGPoint(x: x(peak.frequency), y: 0))
                marker.addLine(to: CGPoint(x: x(peak.frequency), y: size.height))
                context.stroke(marker, with: .color(.primary.opacity(0.6)), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
        }
        .padding(8)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement()
        .accessibilityLabel("Microphone spectrum")
        .accessibilityValue(peak.map { "Dominant frequency \(ToneFrequencyScale.label($0.frequency)) at \(Int($0.level)) dBFS" } ?? "No signal")
    }
}

private struct AudioMeterView: View {
    @ObservedObject var audio: AudioExperimentService

    var body: some View {
        Section("Live microphone meter") {
            LabeledContent("Channels", value: audio.channelCount == 0 ? "—" : "\(audio.channelCount)")
            LabeledContent("Sample rate", value: audio.sampleRate == 0 ? "—" : "\(audio.sampleRate) Hz")
            LevelRow(title: "RMS", value: audio.rmsLevel)
            LevelRow(title: "Peak", value: audio.peakLevel)
            AudioLevelChart(levels: audio.levelHistory)
                .frame(height: 110)
            Text("Speak or make a sound near the microphone to see the levels move.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct LevelRow: View {
    let title: String
    let value: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text("\(value.formatted(.number.precision(.fractionLength(4)))) · \(AudioText.decibels(SpectrumMath.decibels(fromAmplitude: value)))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: min(max(value, 0), 1))
                .tint(value > 0.8 ? .red : .accentColor)
        }
    }
}

private struct AudioLevelChart: View {
    let levels: [Double]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Peak history")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            GeometryReader { proxy in
                HStack(alignment: .bottom, spacing: 2) {
                    ForEach(Array(levels.enumerated()), id: \.offset) { _, level in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(level > 0.8 ? Color.red : Color.accentColor)
                            .frame(maxWidth: .infinity, minHeight: 3, maxHeight: max(3, proxy.size.height * min(level, 1)))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            }
            .padding(8)
            .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
        }
    }
}
#endif

/// Current audio route with sample rate, IO buffer and latency (AVAudioSession or Core Audio HAL).
struct AudioRouteSection: View {
    let route: AudioRouteSnapshot
    var extraDetails: [AudioRouteDetail] = []
    let refresh: () -> Void

    var body: some View {
        Section("Route · \(route.source)") {
            if route.outputs.isEmpty { LabeledContent("Output", value: "None") }
            ForEach(route.outputs) { PortRow(title: "Output", port: $0) }
            ForEach(route.inputs) { PortRow(title: "Input", port: $0) }
            LabeledContent("Sample rate", value: AudioText.sampleRate(route.sampleRate))
            LabeledContent("IO buffer duration", value: AudioText.milliseconds(route.ioBufferDuration))
            LabeledContent("Output latency", value: AudioText.milliseconds(route.outputLatency))
            LabeledContent("Input latency", value: AudioText.milliseconds(route.inputLatency))
            LabeledContent("Channels out / in", value: "\(AudioText.channels(route.outputChannels)) / \(AudioText.channels(route.inputChannels))")
            ForEach(route.details + extraDetails) { LabeledContent($0.label, value: $0.value) }
            Button("Refresh Route", systemImage: "arrow.clockwise", action: refresh)
        }
    }
}

private struct PortRow: View {
    let title: String
    let port: AudioPortInfo

    var body: some View {
        LabeledContent(title) {
            VStack(alignment: .trailing, spacing: 2) {
                Text(port.name)
                Text([port.type, port.channels.map { "\($0) ch" }].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Newest-first list of audio or media events.
struct AudioEventLogView: View {
    let events: [AudioEventEntry]
    let emptyText: String

    var body: some View {
        if events.isEmpty {
            Text(emptyText)
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            ForEach(events) { event in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(event.title).font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(event.date, format: .dateTime.hour().minute().second())
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    if !event.detail.isEmpty {
                        Text(event.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}
