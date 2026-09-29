import SwiftUI

struct SoundAnalysisRunView: View {
    @StateObject private var sound = SoundAnalysisExperimentService()

    var body: some View {
        Button(sound.isRunning ? "Stop Listening" : "Start Listening", systemImage: sound.isRunning ? "stop.fill" : "ear") {
            sound.isRunning ? sound.stop() : sound.start()
        }
        .buttonStyle(.borderedProminent)
        .experimentSession(sound)
        Section("Top sounds right now") {
            if sound.topLabels.isEmpty {
                Text("Start listening and make a sound: speech, music, clapping, a dog barking…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(sound.topLabels) { label in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(label.name)
                            Spacer()
                            Text(label.confidence.formatted(.percent.precision(.fractionLength(0))))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        ProgressView(value: min(max(label.confidence, 0), 1))
                    }
                }
            }
            if !sound.classifierInfo.isEmpty {
                LabeledContent("Classifier", value: sound.classifierInfo)
                LabeledContent("Results received", value: "\(sound.resultCount)")
            }
        }
        OutputView(text: sound.output, isError: sound.status != .available)
    }
}
