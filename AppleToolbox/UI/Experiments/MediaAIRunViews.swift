import SwiftUI

struct AudioInputRunView: View {
    @StateObject private var audio = AudioExperimentService()

    var body: some View {
        Button(audio.isRunning ? "Stop Audio Input" : "Start Audio Input") { audio.isRunning ? audio.stop() : audio.start() }.buttonStyle(.borderedProminent)
            .experimentSession(audio)
        AudioMeterView(audio: audio)
        OutputView(text: audio.output, isError: audio.status != .available)
    }
}

struct MusicKitRunView: View {
    @StateObject private var music = MusicExperimentService()

    var body: some View {
        Button("Request MusicKit Authorization", action: music.requestAuthorization).buttonStyle(.borderedProminent)
        OutputView(text: music.output, isError: music.output.localizedCaseInsensitiveContains("denied") || music.output.localizedCaseInsensitiveContains("restricted"))
    }
}

struct SpeechRunView: View {
    @StateObject private var speech = SpeechExperimentService()

    var body: some View {
        Group {
            if speech.isRunning { Button("Stop Speech Recognition", action: speech.stop).buttonStyle(.borderedProminent) }
            else { Button("Start Speech Recognition", action: speech.start).buttonStyle(.borderedProminent) }
        }
        .experimentSession(speech)
        OutputView(text: speech.output, isError: speech.output.localizedCaseInsensitiveContains("error") || speech.output.localizedCaseInsensitiveContains("denied"))
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
                Text(value.formatted(.number.precision(.fractionLength(4))))
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
